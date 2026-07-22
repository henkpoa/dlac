--[[
    dlac/lockstyle.lua -- LOCKSTYLE SETS: a new set type (Henrik, 07-14). NOT
    dynamic sets -- one item name per visual slot, saved in numbered boxes and
    applied through LuaAshitacast's own packet builder (gFunc.LockStyle).

    Window (armor button in the gearui header): the Equipped-tab 4x4 grid on
    the left EDITS the working lockstyle (click a slot -> pick from your
    gear.lua items for it); to the right, 30 boxes (3 columns x 10 rows, the
    macro-menu look) hold the saved lockstyle sets. The MARKED box (gold) is
    where Save lands, box 1 is marked until you pick another. Switching boxes
    with unsaved changes warns first -- continuing DISCARDS the edits.

    Storage: <char>\dlac\profiles\<Name>\lockstyles\<JOB>.lua -- the boxes
    are PER JOB ENTRY (v41) { active, keepSub, townOff, townBox, onload={JOB=box}, slots }.
    In a town, ONE of two answers (mutually exclusive in the GUI) governs the look:
    townOff (v45) = "Disable in town": drop the lockstyle while you stand in a
    town (data/zones.lua, via feature/location) so your inTown idle gear shows --
    the zone guard stops blocking the client's auto-disable there so the style
    falls, and the base box re-applies when you leave. townBox (v46) = a chosen
    box worn WHILE in a town: it REPLACES your style on entering and restores your
    normal box on leaving, and the guard blocks zoning resets so it survives, like
    any lockstyle. The pump's applyTownPick resolves one 'pick' ('off' / a box /
    nil) at every apply site -- OnLoad, keep-sub, and the zone transition -- so
    logging in INSIDE a town lands the town look with the right timing.
    keepSub (v44) = "Keep on sub change": the game clears style lock on ANY
    job change (server 0x100 handler -- a server-side clear, so unlike the
    zone guard there is nothing to block); with the option on, the pump
    re-applies the session's last-applied box ~3s after a subjob-only
    change. Main-job changes stay OnLoad Lockstyle's business. Reads fall
    back per file: the v40 per-profile lockstyles.lua, then the pre-profile
    global dlac\lockstyles.lua; every save serializes ALL boxes into the job
    entry's file, so older-tier boxes migrate whole on the first write.
    Switching profiles OR jobs reloads the boxes live.
    Apply is ENGINE-side ('/dl ls apply [box]' -- dispatch.lua v38 builds the
    table and calls gFunc.LockStyle; only the LAC state has gFunc). Apply reads
    the SAVED file, never the working copy: unsaved edits do not apply. "OnLoad
    Lockstyle" binds CURRENT JOB -> MARKED BOX: the pump below (macrobook's
    login/job-change pattern) queues the apply ~6s after login / ~3s after a
    job change, when the game accepts lockstyle packets again.

    Preview is CLIENT-side and equips NOTHING (v42): it writes the entity's
    look_t (feature/lookpreview.lua). The old equip-based preview could not show
    the off-job / under-level gear this server happily lockstyles to -- LAC
    refuses to equip it, so those picks silently did nothing. See lookpreview.lua.

    Because the preview never asks the server, it can show gear you do not OWN:
    the picker's "Show gear I don't own" tick sources the full catalog instead of
    gear.lua, so you can try a look on before hunting the pieces down. Save is
    what enforces ownership, not the list -- an unowned piece is preview-only and
    the Save button refuses while one is in the working copy (the server renders
    a style only if HasItem; a style you lack silently leaves the slot's OLD look
    in place). Apply needs no gate of its own: it reads the SAVED file, which
    ownership-gated Save can never have written.

    Self-contained on purpose (gearui is at the 200-local chunk cap, hard
    rule 1). gearui INJECTS its helpers via M.wire{} -- the 4x4 grid renderer,
    item icons/tooltips and the catalog name lookup -- instead of us requiring
    gearui (load order: this module loads before it).
]]--

local M = {};

local _iok, imgui = pcall(require, 'imgui');
local hasImgui = _iok and imgui ~= nil;
local _gok, gear = pcall(require, 'dlac\\gear');
local _pok, profsets = pcall(require, 'dlac\\gear\\profilesets');
local _pfok, profiles = pcall(require, 'dlac\\profiles');
_pfok = _pfok and type(profiles) == 'table';
local _lvok, look = pcall(require, 'dlac\\feature\\lookpreview');
_lvok = _lvok and type(look) == 'table';
-- Job-level gate (v47): the addon-side canEquipItemOnAnyJob mirror -- only offer
-- lockstyle gear one of your jobs can wear at its CURRENT level. The GATE now goes
-- through the Gear Oracle's one door (oracle.anyJobCanWear, issue #71), which delegates
-- to jobgate.canEquip and preserves its FAIL-OPEN semantics; jobgate stays required for
-- its live level READER (jobgate.levels()), which the oracle does not front.
local _jgok, jobgate = pcall(require, 'dlac\\gear\\jobgate');
_jgok = _jgok and type(jobgate) == 'table';
local _orok, oracle = pcall(require, 'dlac\\gear\\gearoracle');
_orok = _orok and type(oracle) == 'table';
-- Central town service (v45): "am I in a town?" for the Disable-in-town option.
local _locok, location = pcall(require, 'dlac\\feature\\location');
_locok = _locok and type(location) == 'table';

M.visible = false;

-- gearui-injected helpers: slotGrid (renderSlotGrid), icon (renderIcon),
-- tooltip (renderItemTooltip), catalog (lookupByName), catalogById + ownedById
-- (by-Id lookups -- names can't do it, the API drops apostrophes), allEquip
-- (the flat catalog list, for "Show gear I don't own"). All optional-guarded.
local W = {};
function M.wire(t) if type(t) == 'table' then for k, v in pairs(t) do W[k] = v; end end end

-- The slots lockstyle can SHOW (packet 0x53 carries equip slots 0-8 only;
-- gFunc.LockStyle filters the rest -- the grid dims them as "not visual").
local VISUAL = { Main = true, Sub = true, Range = true, Ammo = true, Head = true,
                 Body = true, Hands = true, Legs = true, Feet = true };
local N_BOXES, BOX_W = 30, 112;

local COL_DIM    = { 0.62, 0.62, 0.62, 1.0 };
local COL_HEADER = { 0.60, 0.75, 1.00, 1.0 };
local COL_WARN   = { 1.00, 0.55, 0.30, 1.0 };
local COL_USABLE = { 1.00, 1.00, 1.00, 1.0 };
local GOLD       = { 0.42, 0.36, 0.16, 1.0 };

-- ---------------------------------------------------------------------------
-- storage (macrobook pattern: own char path, own tiny load/save)
-- ---------------------------------------------------------------------------
local data = nil;   -- { active = 1..30, onload = { JOB = box }, slots = { [n] = { name, set = {Slot=Name} } } }

-- Windows joins ('\') are the addon's native tongue; the headless suite also
-- runs where '/' is the separator (CI), and there a '\' is a filename char --
-- every io/loadfile boundary below goes through fsp, a no-op under Ashita.
local DIRSEP = package.config:sub(1, 1);
local function fsp(p)
    if p == nil or DIRSEP == '\\' then return p; end
    return (p:gsub('\\', '/'));
end

local function charBase()
    local base = nil;
    pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty();
        local name  = party:GetMemberName(0);
        local id    = party:GetMemberServerId(0);
        if name == nil or name == '' or id == nil or id == 0 then return; end
        base = string.format('%sconfig\\addons\\luashitacast\\%s_%u\\', AshitaCore:GetInstallPath(), name, id);
    end);
    return base;
end

local function jobAbbr()
    local abbr = nil;
    pcall(function()
        local j = AshitaCore:GetMemoryManager():GetPlayer():GetMainJob();
        if j == nil or j == 0 then return; end
        local s = AshitaCore:GetResourceManager():GetString('jobs.names_abbr', j);
        if type(s) == 'string' and s ~= '' then abbr = s; end
    end);
    return abbr;
end

local function subAbbr()
    local abbr = nil;
    pcall(function()
        local p = AshitaCore:GetMemoryManager():GetPlayer();
        local j = p:GetSubJob();
        if j == nil or j == 0 then return; end   -- no subjob set = nil, a valid state
        local s = AshitaCore:GetResourceManager():GetString('jobs.names_abbr', j);
        if type(s) == 'string' and s ~= '' then abbr = s; end
    end);
    return abbr;
end

local function legacyPath()
    local base = charBase();
    return base and (base .. 'dlac\\lockstyles.lua') or nil;
end

-- which profile + job `data` was loaded for: a change in EITHER reloads the
-- boxes (job changes switch the job entry; the profile menu switches profiles)
local dataProf, dataJob = nil, nil;
local dataRaw = nil;    -- the file bytes `data` mirrors (nil = loaded from nothing)
local _watchAt = -1;    -- 1s content-follow throttle

local function readAll(p)
    if p == nil then return nil; end
    local f = io.open(p, 'r'); if f == nil then return nil; end
    local t = f:read('*a'); f:close(); return t;
end

-- Content-follow decision, pure (tests LGW*): same profile + job, but the
-- resolved boxes file may have been REPLACED underneath (a Profiles-menu
-- import writes lockstyles\<JOB>.lua without moving the (profile, job) key --
-- field case 2026-07-22). Changed bytes reload the boxes; a mid-edit working
-- copy (the 4x4) survives the reload -- Save afterwards writes it over the
-- imported box, the user's explicit call.
function M._followBoxes(diskRaw, loadedRaw, curDirty)
    if diskRaw == loadedRaw then return 'keep'; end
    return curDirty and 'follow-keep-edit' or 'follow';
end

local function load_()
    local prof = _pfok and profiles.activeName() or nil;
    local job = jobAbbr();
    local keepCur = false;
    if data ~= nil and prof == dataProf and job == dataJob then
        -- Same key: follow the file's CONTENT, one disk read per second (the
        -- engine's content-keyed watch cadence). Re-resolve the path fresh --
        -- an import can CREATE the per-job file above the tier we loaded from.
        local now = os.time();
        if _watchAt == now then return; end
        _watchAt = now;
        local pNow = (_pfok and profiles.readLockstylesPath(job) or nil) or legacyPath();
        local act = M._followBoxes(readAll(fsp(pNow)), dataRaw, M._curDirty());
        if act == 'keep' then return; end
        keepCur = (act == 'follow-keep-edit');
    end
    if charBase() == nil or job == nil then return; end   -- pre-login: retry next call
    -- boxes are PER JOB ENTRY: the active profile's lockstyles\<JOB>.lua,
    -- falling back to the v40 per-profile file, then the pre-profile global
    -- one (profiles.lua is the shared path authority)
    local p = (_pfok and profiles.readLockstylesPath(job) or nil) or legacyPath();
    dataProf, dataJob = prof, job;
    dataRaw = readAll(fsp(p));
    data = { active = 1, onload = {}, slots = {} };  -- box 1 marked until chosen otherwise
    if not keepCur then
        M._curReset();                               -- profile switch: working copy follows
    end
    pcall(function()
        local chunk = loadfile(fsp(p));
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' then
            if tonumber(t.active) ~= nil then data.active = math.max(1, math.min(N_BOXES, tonumber(t.active))); end
            if t.keepSub == true then data.keepSub = true; end
            if t.townOff == true then data.townOff = true; end
            if tonumber(t.townBox) ~= nil then data.townBox = math.max(1, math.min(N_BOXES, tonumber(t.townBox))); end
            if type(t.onload) == 'table' then data.onload = t.onload; end
            if type(t.slots) == 'table' then data.slots = t.slots; end
        end
    end);
end

-- Pure serializer (headless-tested): data table -> file text.
function M._serialize(d)
    local L = { '-- dlac lockstyle sets -- written by the GUI (header armor button); safe to hand-edit.',
                '-- active = the marked box; onload.<JOB> = box applied on login/job change for that job;',
                '-- keepSub = re-apply the last-applied box after a subjob-only change (v44).',
                '-- townOff = drop the lockstyle while you stand in a town (v45), restored on leaving.',
                '-- townBox = a lockstyle box worn while in a town (v46; mutually exclusive with townOff).',
                'return {',
                string.format('    active = %d,', tonumber(d.active) or 1) };
    if d.keepSub == true then L[#L + 1] = '    keepSub = true,'; end
    if d.townOff == true then L[#L + 1] = '    townOff = true,'; end
    if tonumber(d.townBox) ~= nil then L[#L + 1] = string.format('    townBox = %d,', tonumber(d.townBox)); end
    L[#L + 1] = '    onload = {';
    local jobs = {};
    for j in pairs(d.onload or {}) do jobs[#jobs + 1] = j; end
    table.sort(jobs);
    for _, j in ipairs(jobs) do
        local b = tonumber(d.onload[j]);
        if b ~= nil then L[#L + 1] = string.format('        %s = %d,', j, b); end
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '    slots = {';
    local ns = {};
    for n in pairs(d.slots or {}) do if tonumber(n) then ns[#ns + 1] = tonumber(n); end end
    table.sort(ns);
    for _, n in ipairs(ns) do
        local e = d.slots[n];
        if type(e) == 'table' and type(e.set) == 'table' then
            L[#L + 1] = string.format('        [%d] = { name = %q, set = {', n, tostring(e.name or ''));
            local ks = {};
            for k in pairs(e.set) do ks[#ks + 1] = k; end
            table.sort(ks);
            for _, k in ipairs(ks) do
                if type(e.set[k]) == 'string' then
                    L[#L + 1] = string.format('            %s = %q,', k, e.set[k]);
                end
            end
            L[#L + 1] = '        } },';
        end
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '};';
    L[#L + 1] = '';
    return table.concat(L, '\n');
end

-- Writes ALWAYS land in the job entry (creating 'Default' storage on first
-- use -- the house compat rule); the whole table is serialized, so boxes
-- loaded off an older tier carry into the job entry on the first save.
-- dataJob (not the live job) keys the file: data must never save into a
-- different job's entry than it was loaded for.
-- What actually lands in a JOB ENTRY file: boxes and active whole, but onload
-- filtered to THIS job's binding only. The v41 migration serialized the whole
-- v40 onload map -- every job's bindings -- into each entry it saved. Those
-- cross-job copies are never read for the file's own job, but they RESURFACE
-- through the read fallback: a job with no entry yet falls back to a file
-- whose onload still names it, and the OnLoad pump fires a stale box (field:
-- DRG=1 from box-1 "test" leaked into every file). Each save scrubs its file.
function M._entryData(d, job)
    local out = { active = d.active, slots = d.slots, onload = {},
                  keepSub = (d.keepSub == true) or nil,
                  townOff = (d.townOff == true) or nil,
                  townBox = tonumber(d.townBox) or nil };   -- scalars, ride whole
    if job ~= nil and type(d.onload) == 'table' and d.onload[job] ~= nil then
        out.onload[job] = d.onload[job];
    end
    return out;
end

local function save()
    if data == nil then return; end
    local p, perJob = nil, false;
    if _pfok and dataJob ~= nil then
        pcall(function() profiles.ensureStorage(); end);
        p = profiles.lockstylesPath(dataJob);
        perJob = (p ~= nil);
    end
    p = p or legacyPath();
    if p == nil then return; end
    -- the LEGACY global file (no profiles module) keeps the whole onload map:
    -- there, one file serves every job by design -- filtering would destroy
    -- other jobs' real bindings.
    local d = perJob and M._entryData(data, dataJob) or data;
    pcall(function()
        local text = M._serialize(d);
        local f = io.open(fsp(p), 'w');
        if f ~= nil then
            f:write(text); f:close();
            -- Our own write is the content-follow's new baseline (load_):
            -- without this, every Save would read as an external change.
            dataRaw = text;
        end
    end);
end

-- ---------------------------------------------------------------------------
-- working copy (what the 4x4 edits) -- always mirrors the MARKED box
-- ---------------------------------------------------------------------------
local cur = nil;            -- { set = {Slot=Name}, dirty = false }
local nameBuf = { '' };
local _status = nil;

-- load_ is defined above this local: a profile switch drops the working copy
-- through this hook (the M._touched pattern) and ensure() rebuilds it.
function M._curReset() cur = nil; end
-- Same hook pattern for the content-follow: is the 4x4 mid-edit? (load_ keeps
-- a dirty working copy across a followed reload -- see M._followBoxes.)
function M._curDirty() return cur ~= nil and cur.dirty == true; end

local function loadBox()
    local e = data.slots[data.active];
    cur = { set = {}, dirty = false };
    if type(e) == 'table' and type(e.set) == 'table' then
        for k, v in pairs(e.set) do if VISUAL[k] and type(v) == 'string' then cur.set[k] = v; end end
    end
    nameBuf[1] = (type(e) == 'table' and type(e.name) == 'string') and e.name or '';
end

local function ensure()
    load_();
    if data ~= nil and cur == nil then loadBox(); end
    return data ~= nil and cur ~= nil;
end

local function switchTo(n)
    data.active = n;
    save();
    loadBox();
    _status = string.format('box %d marked%s.', n,
        (data.slots[n] ~= nil) and (' -- "' .. tostring(data.slots[n].name or '') .. '" loaded') or ' (empty)');
    -- a live preview follows the working copy -- forward-declared local, so the
    -- publish rides an upvalue set later (touchedRef), not a direct call
    if type(M._touched) == 'function' then M._touched(); end
end

-- ---------------------------------------------------------------------------
-- item picking: your gear.lua entries for one slot (Main/Range nest by skill)
-- ---------------------------------------------------------------------------
-- CatsEyeXI lets you lockstyle gear your CURRENT job can't equip (Henrik,
-- field-verified; server source read 07-15: the real gate is one of YOUR jobs,
-- at its current level, could wear it -- charutils canEquipItemOnAnyJob). The
-- picker stays ownership-only regardless (Henrik's ruling): the source is
-- gear.lua and nothing here filters by job or Level. Do not add a jobOK-style
-- filter back; an off-job pick is ordinary here, and the engine's apply
-- (dispatch v42) warns per piece when the server's gate would bite. The look
-- PREVIEW renders anything either way -- it never asks the server.
--
-- `all` = the picker's "Show gear I don't own" tick: source the full catalog
-- instead of gear.lua, so the preview can dress you in anything in the game.
-- Ownership is still the ONLY thing that ever filters here -- `all` LIFTS that
-- filter, it does not add a new one, and Save (not the list) is what enforces
-- ownership. Default/2-arg calls are owned-only and unchanged.
local BROWSE_CAP = 200;   -- Main alone is 3749 catalog rows, and every rendered row
                          -- loads an icon texture -- an uncapped list hitches on open.
                          -- Sorted highest-level-first, so the cap keeps the good end;
                          -- renderPicker says the count out loud and points at search.

-- A lockstyle shows a MODEL, so an item without one has nothing to show:
-- lookpreview DROPS a modelless slot (AI tests: "no model => dropped, not
-- zeroed") and the server would render that slot EMPTY. Offering one in a LOOK
-- picker is offering a no-op.
--
-- It also cleans the server's junk out of the catalog, which is what Henrik hit
-- (07-15: "you can see hand, leg, feet, head pieces even though you are choosing
-- a body piece"). catalog.lua is a raw scrape of CatsEyeXI's item DB, and that DB
-- carries 259 UNIMPLEMENTED placeholder rows -- verified against tools/api_cache:
-- jobs=0, MId=0, and `slot` DEFAULTED TO 32 (Body). 258 of the 259 land in Body,
-- which is why browsing Body offered crossbows ('Gletis Crossbow'), bows
-- ('Mpacas Bow') and the Amini boots/gloves/caps: the API itself reports
-- slot=32 for every one of them, so the crawler filed them there and we listed
-- them. Dropping modelless rows removes all 259 as a side effect (they are a
-- strict subset), and Body goes 1743 -> 1470 real body pieces, verified with a
-- name sweep: zero wrong-slot names survive.
--
-- NOT applied to the owned list, deliberately: gear.lua is what you actually
-- HAVE (the bag scan slots it from the CLIENT's own resource, so no placeholder
-- rows), and the AH HARD RULE says that list filters on the search box and
-- NOTHING else -- AH6 pins a fixture whose entries carry no Model at all.
local function hasLook(rec)
    local m = tonumber(rec.Model);
    return m ~= nil and m ~= 0;
end
M._hasLook = hasLook;   -- test seam

-- Sub lists the dual-wield offhands too (Henrik, 07-17): one-handers live
-- under Main in BOTH sources (gear.lua nests them by skill category; the
-- catalog files them Slot="Main"), so a plain slot match could never offer one
-- and a dual-wield lockstyle was impossible to compose. Same regulation as the
-- set builder's Sub pool (gearui subCandidatePool + the A-series HARD RULE):
-- every shield, grip AND 1H weapon is offered, with no Dual Wield or pairing
-- gate -- the player composes, the server decides what renders (and the engine
-- apply already warns per piece). 2H/H2H stay out -- but NOT via the flag
-- alone: the catalog wrongly stamps H2H OneHanded=true (apicrawl ONE-set bug,
-- 2026-07-22), so H2H is refused by Type, exactly like utils.subSlotAllowed's
-- isH2H (normalized 'HandToHand' / legacy 'Hand-to-Hand').
local function is1H(rec)
    if rec.OneHanded ~= true then return false; end
    local t = type(rec.Type) == 'string' and string.lower((rec.Type:gsub('%W', ''))) or '';
    return t ~= 'handtohand' and t ~= 'h2h';
end

local function listFor(slot, q, all, jobLevels)
    local out = {};
    -- v47: only offer gear ONE of your jobs can wear at its CURRENT level
    -- (canEquipItemOnAnyJob). nil jobLevels (pre-login / no jobgate) FAILS OPEN.
    local function gateOk(rec)
        return jobLevels == nil or not _jgok or not _orok or oracle.anyJobCanWear(rec, jobLevels);
    end
    local function take(t, pred)
        for _, rec in pairs(t) do
            if type(rec) == 'table' and type(rec.Name) == 'string'
               and (pred == nil or pred(rec))
               and gateOk(rec)
               and (q == '' or string.find(string.lower(rec.Name), q, 1, true) ~= nil) then
                out[#out + 1] = rec;
            end
        end
    end
    if all and W.allEquip ~= nil then
        pcall(function()
            for _, rec in ipairs(W.allEquip()) do   -- flat, and already carries .Slot
                if (rec.Slot == slot or (slot == 'Sub' and rec.Slot == 'Main' and is1H(rec)))
                   and type(rec.Name) == 'string' and hasLook(rec)
                   and gateOk(rec)
                   and (q == '' or string.find(string.lower(rec.Name), q, 1, true) ~= nil) then
                    out[#out + 1] = rec;
                end
            end
        end);
    else
        pcall(function()
            local t = _gok and gear[slot] or nil;
            if type(t) == 'table' then
                if slot == 'Main' or slot == 'Range' then
                    for _, byCat in pairs(t) do if type(byCat) == 'table' then take(byCat); end end
                else
                    take(t);
                end
            end
            -- the dual-wield merge: gear.Sub above holds only shields/grips
            if slot == 'Sub' then
                local m = _gok and gear.Main or nil;
                if type(m) == 'table' then
                    for _, byCat in pairs(m) do if type(byCat) == 'table' then take(byCat, is1H); end end
                end
            end
        end);
    end
    table.sort(out, function(a, b)
        local la, lb = tonumber(a.Level) or 0, tonumber(b.Level) or 0;
        if la ~= lb then return la > lb; end
        return tostring(a.Name) < tostring(b.Name);
    end);
    return out;
end
M._listFor = listFor;   -- test seam (HARD RULE guards in tests/run_tests.lua)

-- Do you own this? Id-keyed, never name-keyed (see the wire note in gearui:
-- catalog "Arhats Gi" vs client "Arhat's Gi"). Returns YOUR record, so a pick
-- off the catalog list can be stored under the name gear.lua and the engine
-- actually know -- dispatch resolves a saved set by NAME at apply time.
local function ownedRec(rec)
    if type(rec) ~= 'table' or rec.Id == nil or W.ownedById == nil then return nil; end
    local o = nil;
    pcall(function() o = W.ownedById(rec.Id); end);
    return o;
end
M._ownedRec = ownedRec;   -- test seam: the catalog-spelling -> your-spelling bridge

-- The Save gate, over a name already in the working set. Deliberately gear.lua
-- membership and NOT a live bag scan: gear.lua is add-only and a superset of
-- what you hold, so this passes everything the owned picker would have offered
-- (no existing set can newly fail) and blocks exactly the catalog-only picks.
-- The server's HasItem is the real gate; this only stops us SAVING a style that
-- provably could not render. 'remove'/cleared slots are not items.
local function nameOwned(name)
    if type(name) ~= 'string' or name == '' or name == 'remove' then return true; end
    local n2o = nil;
    pcall(function() n2o = _gok and gear.NameToObject or nil; end);
    -- Fail OPEN when we cannot tell -- gear.lua absent, or still the bundled
    -- empty template (dlac.lua preloads at Ashita boot, BEFORE login; the real
    -- one swaps in on the first frame after). ownedcache's rule, for the same
    -- reason: a lookup that failed must never take a feature away. The server
    -- is the real gate; this only stops a save we can PROVE is pointless.
    if type(n2o) ~= 'table' or next(n2o) == nil then return true; end
    return n2o[name] ~= nil;
end

-- Slots in the working copy holding gear you don't own (sorted, for the warning).
local function unownedSlots(set)
    local out = {};
    if type(set) ~= 'table' then return out; end
    for sl, nm in pairs(set) do
        if not nameOwned(nm) then out[#out + 1] = sl; end
    end
    table.sort(out);
    return out;
end
M._nameOwned, M._unownedSlots = nameOwned, unownedSlots;   -- test seams

local function recOf(name)
    if type(name) ~= 'string' or name == '' or name == 'remove' then return nil; end
    local rec = nil;
    pcall(function() rec = _gok and gear.NameToObject[name] or nil; end);
    if rec == nil and W.catalog ~= nil then pcall(function() rec = W.catalog(name); end); end
    return rec;
end

-- Job-level gate plumbing (v47). Live job levels, throttled; a nil read
-- (pre-login) FAILS OPEN so the picker/grid never hide everything.
local _jlAt, _jlLevels = -1e9, nil;
local function jobLevels()
    if os.clock() >= _jlAt then
        _jlAt = os.clock() + 1.0;
        _jlLevels = _jgok and jobgate.levels() or nil;
    end
    return _jlLevels;
end

-- Pure: the first piece in a box's set that NO job of yours can wear at level, or
-- nil (box is fine). `resolve` maps a piece name -> record (live: recOf; tests
-- inject a stub). A nil jl FAILS OPEN (returns nil). Test seam.
function M._boxBadPiece(setTable, jl, resolve)
    if type(setTable) ~= 'table' or jl == nil or not _jgok or not _orok then return nil; end
    for _, nm in pairs(setTable) do
        if type(nm) == 'string' and nm ~= '' and nm ~= 'remove' then
            local rec = resolve and resolve(nm) or nil;
            if rec ~= nil and not oracle.anyJobCanWear(rec, jl) then return nm; end
        end
    end
    return nil;
end

-- Throttled { boxNum -> offending piece name } for the grid grey-out + Apply guard.
local _bbAt, _badBox = -1e9, {};
local function badBoxes()
    if os.clock() >= _bbAt then
        _bbAt = os.clock() + 1.0;
        local jl, bad = jobLevels(), {};
        if data ~= nil then
            for n, e in pairs(data.slots or {}) do
                if type(e) == 'table' then
                    local p = M._boxBadPiece(e.set, jl, recOf);
                    if p ~= nil then bad[n] = p; end
                end
            end
        end
        _badBox = bad;
    end
    return _badBox;
end

-- ---------------------------------------------------------------------------
-- Preview (v42 -- LOOK, not gear). lookpreview.lua injects the client's own
-- appearance packet (GRAP_LIST 0x051) locally with our model ids -- the exact
-- channel the server uses when a lockstyle applies, minus the server. Nothing
-- is equipped, nothing reaches the server, and it renders gear no job or level
-- of yours could wear -- which is the point: the old equip-based preview asked
-- LAC to physically wear the set, and LAC rightly refuses a MNK body on a DRK
-- (field: Arhat's Gi on DRK did nothing; the previous body stayed on).
--
-- Gone with it: <char>\dlac\lspreview.lua, its 10s heartbeat and the engine's
-- 30s kill -- all of which existed only because the old preview UNDRESSED you
-- and a dead addon had to not strip you. The worst this one can do is look
-- wrong until the next appearance update.
--
-- Model ids come from the catalog (data/catalog.lua ships a Model per item);
-- modelOf below resolves them, by Id -- see the note there, names can't do it.
-- ---------------------------------------------------------------------------
local _preview = false;

local function queueCmd(c)
    pcall(function() AshitaCore:GetChatManager():QueueCommand(1, c); end);
end

-- Item name -> appearance model id. nil = nothing to show (an accessory, or an
-- item with no model) -- lookpreview DROPS those rather than blanking the slot.
--
-- Two-step on purpose. gear.lua is an ownership record and carries no Model of
-- its own; gearui fills it in from the catalog BY ID, but only once its owned
-- cache has been built, and this window can open before that. So fall back to
-- the catalog by Id, which also sidesteps the name problem: the API drops
-- apostrophes, so the catalog holds "Arhats Gi" where the client (and gear.lua)
-- says "Arhat's Gi" -- a name lookup would miss it. Ids always agree.
local function modelOf(name)
    local rec = recOf(name);
    if rec == nil then return nil; end
    local m = tonumber(rec.Model);
    if m ~= nil then return m; end
    if W.catalogById ~= nil and rec.Id ~= nil then
        local c = nil;
        pcall(function() c = W.catalogById(rec.Id); end);
        if type(c) == 'table' then return tonumber(c.Model); end
    end
    return nil;
end
M._modelOf = modelOf;   -- test seam: smoke_ui resolves a real catalog item through
                        -- the FULL live chain (NameToObject -> catalogById ->
                        -- flattenGear record) -- the field bug hid exactly there

-- Every mutation of the working copy funnels through here: while a preview is
-- live it re-pushes immediately, so the look on screen tracks every edit.
local function touched()
    if _preview and _lvok and cur ~= nil then look.update(cur.set, modelOf); end
end
M._touched = touched;   -- switchTo is defined above this section and publishes through here

local function startPreview()
    if not _lvok then _status = 'preview unavailable (lookpreview failed to load).'; return; end
    -- No '/lockstyle off' here anymore. The equip-era preview needed it because
    -- a live lockstyle VISUAL hid the engine's gear swaps; this preview IS a
    -- visual, painted over whatever shows, and lookpreview intercepts incoming
    -- appearance packets while active -- a live lockstyle cannot stomp it. The
    -- off-command was also the start-up "flash" (the server redressed you).
    local ok, n = look.start(cur ~= nil and cur.set or {}, modelOf);
    if ok then
        _preview = true;
        if (n or 0) > 0 then
            _status = string.format('previewing -- %d slot%s styled, your LOOK only, nothing is equipped (live as you edit).',
                n, n == 1 and '' or 's');
        else
            -- 0 resolved slots repaints the current look verbatim -- on screen
            -- that reads as "nothing happened", so say it out loud.
            _status = 'previewing -- but NO piece here resolves to a model yet (empty set?); pick one and it shows live.';
        end
    else
        _status = 'preview unavailable -- no player entity (not logged in yet?).';
    end
end

local function endPreview()
    _preview = false;
    if _lvok then look.stop(); end
    _status = 'preview ended -- your real gear shows again.';
end

-- One-shot migration: dispatch's lspreview reader is gone (v42), but the LAC
-- state keeps running whatever seeded dispatch.lua it loaded until the next
-- /lac reload -- for that window an OLD engine still reads this file, and a
-- stale enabled=true would keep it wearing the equip preview until the 30s
-- heartbeat lapses. Retiring the file covers exactly that user. Delete this
-- once no pre-v42 seeded copies plausibly remain in the wild.
local _legacyRetired = false;
local function retireLegacyPreview()
    if _legacyRetired then return; end
    local base = charBase(); if base == nil then return; end   -- pre-login: retry next pump
    _legacyRetired = true;
    pcall(function()
        local f = io.open(fsp(base .. 'dlac\\lspreview.lua'), 'w');
        if f == nil then return; end
        f:write('-- dlac lockstyle preview -- RETIRED (v42 previews the look, not the gear).\nreturn {\n    enabled = false,\n};\n');
        f:close();
    end);
end

-- ---------------------------------------------------------------------------
-- window
-- ---------------------------------------------------------------------------
local ui = { selSlot = nil, pick = { '' }, pendingBox = nil, openPick = false, openConfirm = false,
             openArr = { true }, showAll = { false } };

local function boxColumn(from, to)
    local clickedBox = nil;
    local bad = badBoxes();   -- v47: { boxNum -> offending piece name }
    imgui.BeginGroup();
    for n = from, to do
        local e = data.slots[n];
        -- name only (Henrik: the number ate the width); the tooltip keeps the
        -- box number, and the 10x3 layout implies it anyway
        local nm = (type(e) == 'table' and type(e.name) == 'string' and e.name ~= '') and e.name or '--';
        if #nm > 15 then nm = string.sub(nm, 1, 14) .. '~'; end
        local on = (n == data.active);
        local dead = bad[n];   -- a piece no job of yours can wear at its level
        if on then imgui.PushStyleColor(ImGuiCol_Button, GOLD);
        elseif dead then imgui.PushStyleColor(ImGuiCol_Text, COL_DIM); end   -- grey the unavailable box
        if imgui.Button(nm .. '##lsbox' .. n, { BOX_W, 19 }) then clickedBox = n; end
        if on or dead then imgui.PopStyleColor(1); end
        if imgui.IsItemHovered() then
            local ol = '';
            for j, b in pairs(data.onload or {}) do if b == n then ol = ol .. ' [OnLoad: ' .. j .. ']'; end end
            imgui.SetTooltip(string.format('box %d%s%s\nClick to mark it -- Save lands in the marked box.%s%s',
                n, (nm ~= '--') and (': ' .. tostring(e.name)) or ' (empty)', ol,
                (cur ~= nil and cur.dirty and n ~= data.active) and '\nWARNING: unsaved edits on the current box.' or '',
                dead and ('\nUNAVAILABLE: "' .. tostring(dead) .. '" -- no job of yours can wear it at its level; it will not apply.') or ''));
        end
    end
    imgui.EndGroup();
    return clickedBox;
end

local function renderPicker()
    if ui.openPick then ui.openPick = false; imgui.OpenPopup('##dlac_lspick'); end
    if not imgui.BeginPopup('##dlac_lspick') then return; end
    local slot = ui.selSlot;
    if slot == nil then imgui.EndPopup(); return; end
    imgui.TextColored(COL_HEADER, slot .. ' -- shown in this lockstyle:');
    imgui.SameLine(0, 8);
    imgui.PushItemWidth(150);
    imgui.InputText('##lssearch', ui.pick, 32);
    imgui.PopItemWidth();
    -- The browse toggle lives HERE, not in the window's button column: this list
    -- is the only thing it changes, and this is where you notice the piece you
    -- want is missing. Sticky across opens (module ui state), deliberately NOT
    -- persisted to disk -- it is a look-at-things mode, not a setting.
    imgui.Checkbox("Show gear I don't own##lsall", ui.showAll);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Off (default): your own gear (gear.lua) -- these can be saved and applied.\n'
            .. 'On: every piece of equipment in the game.\n\n'
            .. 'You can PREVIEW anything -- the preview is your look only and never asks\n'
            .. 'the server. But a piece you do not own CANNOT be saved into a box: the\n'
            .. 'server only renders a style you actually have, so it would silently do\n'
            .. 'nothing. Orange = you do not own it.');
    end
    imgui.Separator();
    imgui.BeginChild('##lspicklist', { 340, 300 }, false);
    if imgui.Selectable('(clear -- no lockstyle piece for this slot)##lsclear', false) then
        cur.set[slot] = nil; cur.dirty = true; touched();
        imgui.CloseCurrentPopup();
    end
    if imgui.Selectable('(hide -- lockstyle the slot EMPTY)##lshide', false) then
        cur.set[slot] = 'remove'; cur.dirty = true; touched();
        imgui.CloseCurrentPopup();
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("LAC's 'remove': the lockstyle shows NOTHING in this slot,\neven while something is equipped.");
    end
    imgui.Separator();
    local q = string.lower(ui.pick[1] or '');
    -- ANDed with the wire, so `all` means "this list IS the catalog" and not
    -- merely "the box is ticked": listFor degrades to the owned list without
    -- gearui, and rows must not then be painted as gear you don't own.
    local all   = (ui.showAll[1] == true) and (W.allEquip ~= nil);
    local items = listFor(slot, q, all, jobLevels());   -- v47: gate by canEquipItemOnAnyJob (fail-open pre-login)
    local shown = #items;
    if all and shown > BROWSE_CAP then shown = BROWSE_CAP; end
    for i = 1, shown do
        local rec = items[i];
        -- In the catalog list, is this one YOURS? Ask by Id, and pick up your own
        -- record while we're here: a catalog Name can be spelled differently
        -- (apostrophes), and the saved set is resolved by name at apply time.
        local mine = (not all) and rec or ownedRec(rec);
        local own  = (mine ~= nil);
        if W.icon ~= nil then pcall(W.icon, rec.Id, 18, rec); imgui.SameLine(0, 6); end
        if not own then imgui.PushStyleColor(ImGuiCol_Text, COL_WARN); end
        if imgui.Selectable(string.format('%s   Lv%d%s##lsi%d', tostring(rec.Name),
                tonumber(rec.Level) or 0, own and '' or '   (not owned -- preview only)', i), false) then
            cur.set[slot] = own and mine.Name or rec.Name;   -- your spelling when it's yours
            cur.dirty = true; touched();
            imgui.CloseCurrentPopup();
        end
        if not own then imgui.PopStyleColor(1); end
        if imgui.IsItemHovered() and W.tooltip ~= nil then pcall(W.tooltip, rec); end
    end
    if #items == 0 then
        imgui.TextColored(COL_DIM, (q ~= '')
            and (all and 'Nothing in the game matches that.' or "No owned item matches -- tick \"Show gear I don't own\" to search everything.")
            or  'Nothing in gear.lua for this slot yet (/dl sync).');
    elseif shown < #items then
        -- Never truncate quietly: say what was dropped and how to reach it.
        imgui.TextColored(COL_WARN, string.format('... %d more -- showing the %d highest-level. Type above to narrow.',
            #items - shown, shown));
    end
    imgui.EndChild();
    imgui.EndPopup();
end

local function renderDelete()
    if ui.openDelete then ui.openDelete = false; imgui.OpenPopup('##dlac_lsdelete'); end
    if not imgui.BeginPopup('##dlac_lsdelete') then return; end
    local e = data.slots[data.active];
    imgui.TextColored(COL_WARN, string.format('Delete box %d ("%s")?', data.active,
        tostring((type(e) == 'table') and (e.name or '') or '')));
    imgui.TextColored(COL_DIM, 'The saved lockstyle and its OnLoad bindings are removed.');
    if imgui.Button('Delete it##lsdelgo', { 260, 22 }) then
        data.slots[data.active] = nil;
        for j, b in pairs(data.onload or {}) do
            if b == data.active then data.onload[j] = nil; end
        end
        save();
        loadBox();
        touched();
        _status = string.format('box %d deleted.', data.active);
        imgui.CloseCurrentPopup();
    end
    if imgui.Button('Keep it##lsdelno', { 260, 22 }) then
        imgui.CloseCurrentPopup();
    end
    imgui.EndPopup();
end

local function renderConfirm()
    if ui.openConfirm then ui.openConfirm = false; imgui.OpenPopup('##dlac_lsconfirm'); end
    if not imgui.BeginPopup('##dlac_lsconfirm') then return; end
    imgui.TextColored(COL_WARN, string.format('Box %d has UNSAVED changes.', data.active));
    imgui.TextColored(COL_DIM, 'Switching discards them and loads the other box.');
    -- Stacked + wide (Henrik: the side-by-side pair clipped both labels).
    if imgui.Button('Discard changes & switch##lsdisc', { 260, 22 }) then
        local n = ui.pendingBox;
        ui.pendingBox = nil;
        if n ~= nil then switchTo(n); end
        imgui.CloseCurrentPopup();
    end
    if imgui.Button('Keep editing##lskeep', { 260, 22 }) then
        ui.pendingBox = nil;
        imgui.CloseCurrentPopup();
    end
    imgui.EndPopup();
end

-- Rendered from gearui's drawWindow (themed scope), every frame while visible.
function M.render()
    if not hasImgui or not M.visible then return; end
    if not ensure() then
        M.visible = false;
        return;
    end
    imgui.SetNextWindowSize({ 620, 400 }, ImGuiCond_FirstUseEver or 0);
    ui.openArr[1] = true;
    if imgui.Begin('dlac Lockstyle###dlac_lockstyle', ui.openArr, ImGuiWindowFlags_None or 0) then
        local job = jobAbbr();
        local e = data.slots[data.active];
        -- the job in the title says WHOSE boxes these are (per job entry, v41)
        imgui.TextColored(COL_HEADER, string.format('%s lockstyle box %d', tostring(job or '?'), data.active));
        imgui.SameLine(0, 8);
        imgui.TextColored(cur.dirty and COL_WARN or COL_DIM,
            cur.dirty and 'unsaved changes' or ((e ~= nil) and ('"' .. tostring(e.name or '') .. '"') or '(empty)'));
        -- top-right on this row (Henrik): kill the lockstyle visual
        pcall(function()
            local bw = 178;   -- 17 chars at the wide themed font (9.5px/char + padding)
            imgui.SameLine();
            local avail = imgui.GetContentRegionAvail();
            if type(avail) == 'number' and avail > bw then
                imgui.SetCursorPosX(imgui.GetCursorPosX() + avail - bw);
            end
            if imgui.Button('Disable lockstyle##lsoff', { bw, 0 }) then
                queueCmd('/lockstyle off');
                -- stamp the intent HERE (round 6): our own queued command
                -- never re-enters this state's command event, and an
                -- unstamped disable is "client noise" to the guard -- it
                -- would block this button inside an armed window and let a
                -- subjob switch resurrect a style the player just killed
                pcall(function() M._guardUserOff(); end);
                _status = 'lockstyle disabled (/lockstyle off) -- your real gear shows again.';
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('The game\'s /lockstyle off: the lockstyle VISUAL comes off and\nwhat you actually wear shows again.');
            end
        end);
        imgui.Separator();

        imgui.BeginGroup();   -- LEFT: the 4x4 + controls
        if W.slotGrid ~= nil then
            W.slotGrid('dlacls', 186, ui.selSlot,
                function(sl)   -- icon id
                    if not VISUAL[sl.label] then return nil; end
                    local rec = recOf(cur.set[sl.label]);
                    return rec and rec.Id or nil;
                end,
                function(sl)   -- hover text (no record)
                    if not VISUAL[sl.label] then return '(not part of lockstyle)'; end
                    local v = cur.set[sl.label];
                    if v == 'remove' then return '(hidden -- lockstyled empty)'; end
                    return v or '(no lockstyle piece)';
                end,
                function(label)   -- click
                    if not VISUAL[label] then
                        _status = label .. ' is not a visual slot -- lockstyle covers Main/Sub/Range/Ammo/Head/Body/Hands/Legs/Feet.';
                        return;
                    end
                    ui.selSlot = label;
                    ui.pick[1] = '';
                    ui.openPick = true;
                end,
                function(sl) return recOf(cur.set[sl.label]); end,
                190);
        else
            imgui.TextColored(COL_DIM, 'grid unavailable (gearui not wired)');
        end
        -- Gear you don't own is PREVIEW-ONLY: the server renders a style only if
        -- you have the item, so saving one would silently show nothing (worse,
        -- the slot keeps its OLD style -- the "why is my lockstyle stale" trap).
        -- Refuse the save and say which slots, rather than disabling a dead
        -- button: a button that explains itself beats one that just ignores you.
        local bad = unownedSlots(cur.set);
        imgui.PushItemWidth(108);
        imgui.InputText('##lsname', nameBuf, 24);
        imgui.PopItemWidth();
        if imgui.IsItemHovered() then imgui.SetTooltip('Name for this lockstyle -- saved with the box.'); end
        imgui.SameLine(0, 4);
        if #bad > 0 then imgui.PushStyleColor(ImGuiCol_Text, COL_DIM); end
        if imgui.Button('Save##lssave', { 60, 0 }) then   -- height 0 = frame height, matches the input box
            if #bad > 0 then
                _status = string.format('cannot save -- you do not own: %s. Preview shows them; the server will not. '
                    .. 'Replace %s with gear you own, or just keep previewing.',
                    table.concat(bad, ', '), (#bad == 1) and 'it' or 'them');
            else
                local copy = {};
                for k, v in pairs(cur.set) do copy[k] = v; end
                data.slots[data.active] = { name = tostring(nameBuf[1] or ''), set = copy };
                cur.dirty = false;
                save();
                _status = string.format('saved box %d as "%s".', data.active, tostring(nameBuf[1] or ''));
            end
        end
        if #bad > 0 then imgui.PopStyleColor(1); end
        if imgui.IsItemHovered() then
            imgui.SetTooltip((#bad > 0)
                and ('Cannot save: you do not own ' .. table.concat(bad, ', ') .. '.\n\n'
                     .. 'The server only renders a lockstyle piece you actually have, so this\n'
                     .. 'box would silently do nothing. Preview it all you like -- that is your\n'
                     .. 'look only and never asks the server.')
                or  'Save the working lockstyle into the MARKED (gold) box.');
        end
        imgui.SameLine(0, 4);
        if imgui.Button('Del##lsdel', { 44, 0 }) then ui.openDelete = true; end
        if imgui.IsItemHovered() then imgui.SetTooltip('Delete the MARKED box\'s saved lockstyle (asks first).'); end
        -- A greyed Save is easy to miss, so say it in the column too. Kept SHORT
        -- on purpose: this group is 216 wide and the 30 boxes sit beside it --
        -- a long line here pushes them out of the window.
        if #bad > 0 then
            imgui.TextColored(COL_WARN, string.format('%d slot%s not owned', #bad, (#bad == 1) and '' or 's'));
            if imgui.IsItemHovered() then
                imgui.SetTooltip(table.concat(bad, ', ') .. '\n\nPreview-only -- Save is off while these are in the set.\n'
                    .. 'The server only renders lockstyle pieces you own.');
            end
        end
        -- Import from static: many players keep old lockstyle sets as statics.
        local statics = (_pok and type(profsets.staticSetNames) == 'function') and profsets.staticSetNames() or {};
        imgui.PushItemWidth(216);   -- wide enough for the label at the themed font (field-clipped at 186)
        if imgui.BeginCombo('##lsimp', 'Import from static...') then
            if #statics == 0 then imgui.TextColored(COL_DIM, '(no static sets found)'); end
            for _, nm in ipairs(statics) do
                if imgui.Selectable(nm .. '##lsimp_' .. nm, false) then
                    pcall(function()
                        local S = profsets.getSetsRoot();
                        local src = (type(S) == 'table') and S[nm] or nil;
                        if type(src) ~= 'table' then return; end
                        cur.set = {};
                        for k, v in pairs(src) do
                            if VISUAL[k] then
                                if type(v) == 'string' then cur.set[k] = v;
                                elseif type(v) == 'table' and type(v.Name) == 'string' then cur.set[k] = v.Name; end
                            end
                        end
                        cur.dirty = true; touched();
                        _status = string.format('imported static "%s" -- Save to keep it in box %d.', nm, data.active);
                    end);
                end
            end
            imgui.EndCombo();
        end
        imgui.PopItemWidth();
        if imgui.IsItemHovered() then imgui.SetTooltip('Copy the visual slots of a static set (live job file +\npre-profiles backups) into the working lockstyle.'); end
        -- OnLoad + Apply row.
        local olBox = { job ~= nil and data.onload[job] == data.active or false };
        if imgui.Checkbox('OnLoad Lockstyle##lsol', olBox) and job ~= nil then
            data.onload[job] = (olBox[1] == true) and data.active or nil;
            save();
            _status = (olBox[1] == true)
                and string.format('%s lockstyles box %d on every login/job change.', job, data.active)
                or (job .. ' OnLoad lockstyle off.');
        end
        if imgui.IsItemHovered() then
            local cur_ol = (job ~= nil) and data.onload[job] or nil;
            imgui.SetTooltip(string.format(
                'Apply the MARKED box automatically every time %s loads\n(login and job change, a few seconds in).%s',
                tostring(job or '?'),
                (cur_ol ~= nil and cur_ol ~= data.active) and string.format('\nCurrently bound to box %d.', cur_ol) or ''));
        end
        -- Keep-on-subjob (v44). The game clears style lock on ANY job change,
        -- server-side (0x100 handler) -- nothing to block, so this one is a
        -- re-apply, the OnLoad pump's pattern.
        local ksBox = { data.keepSub == true };
        if imgui.Checkbox('Keep on sub change##lsks', ksBox) then
            data.keepSub = (ksBox[1] == true) or nil;
            save();
            _status = (data.keepSub ~= nil)
                and 'lockstyle re-applies a few seconds after a subjob change.'
                or  'subjob changes drop the lockstyle again (game default).';
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('The game clears style lock on ANY job change (that is the server, not\n'
                .. 'dlac). With this on, dlac re-applies the LAST APPLIED lockstyle a few\n'
                .. 'seconds after a subjob-only change. Main-job changes load a different\n'
                .. 'job\'s boxes -- those are OnLoad Lockstyle\'s business (above). A\n'
                .. 'lockstyle you turned off yourself stays off.');
        end
        -- Disable in town (v45): show off your inTown idle gear. Just flips the
        -- setting -- the pump sees the change next frame and drops/restores.
        local tsBox = { data.townOff == true };
        if imgui.Checkbox('Disable in town##lstown', tsBox) then
            data.townOff = (tsBox[1] == true) or nil;
            if data.townOff then data.townBox = nil; end   -- mutually exclusive with a town lockstyle
            save();
            _status = (data.townOff ~= nil)
                and 'lockstyle turns OFF while you are in a town -- your real (idle) gear shows there.'
                or  'lockstyle stays on in towns again.';
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Show off your town idle gear: while you stand in a town, dlac drops the\n'
                .. 'lockstyle so your real gear shows, and re-applies your last box when you\n'
                .. 'leave. It also skips applying a lockstyle at all while in a town -- OnLoad\n'
                .. 'and Keep-on-sub included -- so logging in inside a town stays bare. Town\n'
                .. 'list is server-derived: every city plus Nashmau, Celennia, Mog Garden.\n'
                .. 'A lockstyle you turned off yourself stays off.');
        end
        -- (The 'keep6' live-readout line lived here during field rounds 5-6;
        -- removed once the feature was confirmed -- Henrik: the user doesn't
        -- need it. '/dl ls state' remains the on-demand debug readout, and
        -- the LGF suite drives the whole chain headlessly.)
        -- own row (Henrik: beside the checkbox it widened the whole window);
        -- full column width, same as Import/Preview
        if imgui.Button('Apply lockstyle##lsgo', { 216, 0 }) then
            local dead = badBoxes()[data.active];   -- v47: a box with an unwearable piece won't fully render
            if dead ~= nil then
                _status = string.format('box %d has "%s" -- no job of yours can wear it at its level, so it would keep its old look. Swap it or re-level that job.',
                    data.active, tostring(dead));
            else
                queueCmd('/dl ls apply');
                -- record the box HERE: our own queued command never re-enters
                -- this state's command event (round 6) -- and apply-without-a-
                -- number means the marked box, the same resolution dispatch uses
                pcall(function() M._noteApplied(data.active); end);
            end
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Lockstyle the MARKED box now (engine-side: /dl ls apply --\nneeds LuaAshitacast loaded). Unsaved edits are NOT applied: Save first.');
        end
        if imgui.Button((_preview and 'End preview' or 'Preview') .. '##lsprev', { 216, 0 }) then
            if _preview then endPreview(); else startPreview(); end
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Shows the WORKING copy on your character, live as you edit -- your LOOK\nonly. Nothing is equipped, nothing reaches the server, nobody else sees\nit, and it renders gear no job or level of yours could wear. Works with a\nlive lockstyle -- the preview paints over it and hands it back at the end.\nClick again (or close this window) to end; zoning ends it too. Safe in\ncombat.');
        end
        imgui.EndGroup();

        imgui.SameLine(0, 12);
        imgui.BeginGroup();   -- RIGHT: the 30 boxes, macro-menu style
        local styled = (ImGuiStyleVar_ItemSpacing ~= nil);
        if styled then imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 3, 2 }); end
        local c1 = boxColumn(1, 10);
        imgui.SameLine(0, 4);
        local c2 = boxColumn(11, 20);
        imgui.SameLine(0, 4);
        local c3 = boxColumn(21, 30);
        if styled then imgui.PopStyleVar(1); end
        imgui.EndGroup();
        local clicked = c1 or c2 or c3;
        if clicked ~= nil and clicked ~= data.active then
            if cur.dirty then
                ui.pendingBox = clicked;
                ui.openConfirm = true;
            else
                switchTo(clicked);
            end
        end

        -- Town lockstyle (v46), UNDER the boxes: ONE box worn while in a town --
        -- it REPLACES your current style on entering and restores your normal one
        -- on leaving, and rides zoning like any lockstyle (the guard keeps it).
        -- None = keep your normal style. Mutually exclusive with Disable-in-town.
        imgui.Separator();
        imgui.TextColored(COL_HEADER, 'In town, wear:');
        imgui.SameLine(0, 6);
        imgui.PushItemWidth(240);
        local curTB = tonumber(data.townBox);
        local tbName = (curTB ~= nil and type(data.slots[curTB]) == 'table'
                        and type(data.slots[curTB].name) == 'string' and data.slots[curTB].name ~= '')
                       and (' -- ' .. data.slots[curTB].name) or '';
        local tbPreview = (curTB ~= nil) and string.format('box %d%s', curTB, tbName)
                          or 'None (keep your normal lockstyle)';
        if imgui.BeginCombo('##lstownbox', tbPreview) then
            if imgui.Selectable('None##lstb_none', curTB == nil) then
                data.townBox = nil; save();
                _status = 'no town lockstyle -- your normal lockstyle shows in town too.';
            end
            for n = 1, N_BOXES do
                local e = data.slots[n];
                local nm = (type(e) == 'table' and type(e.name) == 'string' and e.name ~= '')
                           and (' -- ' .. e.name) or (type(e) == 'table' and '' or ' (empty)');
                if imgui.Selectable(string.format('box %d%s##lstb_%d', n, nm, n), curTB == n) then
                    data.townBox = n;
                    data.townOff = nil;   -- a chosen town lockstyle replaces "Disable in town"
                    save();
                    _status = string.format('town lockstyle = box %d -- worn while you are in a town (Disable-in-town cleared).', n);
                end
            end
            imgui.EndCombo();
        end
        imgui.PopItemWidth();
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Pick ONE lockstyle to wear while you are in a town. It replaces your\n'
                .. 'current lockstyle when you enter a town and restores your normal one\n'
                .. 'when you leave, and it survives zoning like any lockstyle. None = keep\n'
                .. 'your normal style in town. Choosing a box turns OFF "Disable in town"\n'
                .. '(they are two answers to the same question).');
        end

        if _status ~= nil then
            imgui.Separator();
            imgui.TextColored(COL_DIM, _status);
        end
        renderPicker();
        renderConfirm();
        renderDelete();
    end
    imgui.End();
    if ui.openArr[1] == false then M.visible = false; end
end

function M.open()
    M.visible = true;
end

-- ---------------------------------------------------------------------------
-- OnLoad pump (macrobook's login/job-change pattern): queue the engine apply
-- once per job, ~6s after login (zone-in grace) / ~3s after a job change.
-- Jobs with no OnLoad binding are never touched.
-- ---------------------------------------------------------------------------
local appliedJob, pendingJob, dueAt = nil, nil, nil;
-- Keep-on-subjob (v44) state. lastBox = the box this session last actually
-- applied ('/dl ls apply' observed in the command handler below -- covers the
-- GUI button, the OnLoad pump and hand-typed applies alike); box numbers are
-- per JOB ENTRY, so a main-job change resets it and the OnLoad apply that
-- follows re-records it. Session-only on purpose: after a reload we no longer
-- know a lockstyle is ours to keep, and the guard starts inactive anyway.
local lastSub, lastBox, subDueAt = nil, nil, nil;
-- Town lockstyle (v45/v46): the last DEFINITE town pick applied ('off' = drop /
-- a box number = the town lockstyle / nil = no override), so the pump acts only
-- on a real change and holds through a mid-zone unreadable blink.
local lastTownPick = nil;
-- A town-BOX apply (entering replace-mode, or leaving -> restoring the base box)
-- is a SET, and the server RELOADS the previously-persisted style on this very
-- zone-in -- an immediate SET loses that race (the same reason OnLoad/keep-sub
-- wait out their windows; off-mode is spared only because the guard 'suppress'
-- rides the client's own ~0.6s auto-disable). The pump books the SET this long
-- past the zone change, then applies; a 'off' drop still fires at once.
local TOWN_APPLY_DELAY = 2.0;   -- seconds after the zone change; field-tunable
local townDueAt, townDuePick, townDueBase = nil, nil, nil;
-- Live-state accessors for the window readout (render() is defined ABOVE
-- these locals, so it reaches them through M at frame time -- the same
-- late-binding pattern as M._touched).
function M._lastBox() return lastBox; end
function M._healDue() return subDueAt; end
-- The keep memory's writer (field round 6). The GUI Apply button and the
-- OnLoad pump call this DIRECTLY at their queue sites: a command queued from
-- this very state does NOT loop back into this state's own command event
-- (field: lastBox stayed nil after button applies -- 'keep4: box -'), so the
-- command-event observation below catches only hand-TYPED applies, where the
-- event provably fires.
function M._noteApplied(b)
    if tonumber(b) ~= nil then lastBox = tonumber(b); end
end
-- Apply a town pick's effect (v46). 'off' -> drop the style (the guard's
-- 'suppress' verdict lets it fall in a town); a BOX -> replace with it and ARM
-- the guard so the client's zoning resets are BLOCKED and the town style
-- survives, exactly as a normal lockstyle does; nil -> restore the base (normal)
-- box. A town-box override deliberately does NOT touch lastBox, so what you
-- restore to on leaving town is still your real lockstyle.
local function applyTownPick(pick, baseBox)
    if pick == 'off' then
        queueCmd('/lockstyle off');
    elseif pick == 'clear' then
        -- Leaving town with NO base lockstyle to restore: DROP the town box.
        -- Replace-mode's guard BLOCKS the client's remove packet, so stamp userOff
        -- to make the guard 'retire' it -- let the remove through, leaving no
        -- lockstyle outside town (Henrik: don't keep the town style alive when
        -- nothing is set to replace it).
        M._guardUserOff();
        queueCmd('/lockstyle off');
    elseif type(pick) == 'number' then
        M._guardArm();
        queueCmd(string.format('/dl ls apply %d', pick));
    elseif tonumber(baseBox) ~= nil then
        M._guardArm();
        M._noteApplied(tonumber(baseBox));
        queueCmd(string.format('/dl ls apply %d', tonumber(baseBox)));
    end
end
function M.pump()
    retireLegacyPreview();
    -- Closing the window while previewing ends the preview (Henrik: always);
    -- zoning ends it inside lookpreview (the new zone's look is authoritative)
    -- and we just sync the UI; while it runs, lookpreview re-asserts the look
    -- if anything stomped it (compare-then-inject, once a second).
    if _preview then
        if _lvok and not look.active() then
            _preview = false;
            _status = 'preview ended -- zoning redressed you.';
        elseif not M.visible then endPreview();
        elseif _lvok then look.pump(); end
    end
    local job = jobAbbr();
    if job == nil then return; end
    load_();
    if data == nil then return; end
    -- Town lockstyle transitions (v46). pick = 'off' (disable-in-town, drop) |
    -- <box> (replace your style with that town lockstyle) | nil (no override).
    -- location.inTown() is tri-state; a nil (mid-zone) HOLDS the last pick. The
    -- apply-SITES below (OnLoad / keep-sub) own the login/job-change timing, so a
    -- town box shows correctly when you log in INSIDE a town; this transition
    -- owns genuine zone in/out. Both paths are idempotent -- a login that also
    -- trips this transition just re-asserts the same pick.
    local it = nil;
    if _locok then it = location.inTown(); end   -- true / false / nil (keep false!)
    if it ~= nil then
        local pick = M._townPick(it, data.townOff, data.townBox);
        if pick ~= lastTownPick then
            if pick == 'off' then
                applyTownPick('off', nil);   -- a drop is immediate (and the guard 'suppress' drops it anyway)
            else
                -- a box (enter replace-mode) or nil (leave -> restore the base
                -- box) is a SET; the server reloads the previously-persisted
                -- style on this same zone-in, so an immediate SET loses the race.
                -- Book it past the zone-in reload window (TOWN_APPLY_DELAY).
                local base = lastBox or (type(data.onload) == 'table' and data.onload[job]) or nil;
                townDueBase = base;
                -- leaving town (pick=nil) with a town box applied but NO base to
                -- restore -> DROP it, else the guard keeps the town box alive.
                townDuePick = (pick == nil and M._townLeaveClear(lastTownPick, base)) and 'clear' or pick;
                townDueAt = os.clock() + TOWN_APPLY_DELAY;
            end
            lastTownPick = pick;
        end
    end
    if townDueAt ~= nil and os.clock() >= townDueAt then
        townDueAt = nil;
        applyTownPick(townDuePick, townDueBase);
    end
    if job ~= appliedJob and job ~= pendingJob then
        pendingJob = job;
        dueAt = os.clock() + ((appliedJob == nil) and 6 or 3);
        -- a MAIN change switches the whole box set: yesterday's box number
        -- means nothing in the new job entry, and the sub reading flips too
        lastBox, lastSub, subDueAt = nil, nil, nil;
    end
    if pendingJob ~= nil and dueAt ~= nil and os.clock() >= dueAt then
        appliedJob, pendingJob, dueAt = pendingJob, nil, nil;
        -- v46: a town pick (off / a town box) overrides the OnLoad box while you
        -- are in a town -- applied HERE so it lands with the login/job-change
        -- timing the game needs (logging in inside a town shows the town box, not
        -- the plain one). Not in a town -> the normal OnLoad box, as before.
        local pick = (it ~= nil) and M._townPick(it, data.townOff, data.townBox) or nil;
        applyTownPick(pick, data.onload[appliedJob]);
        if it ~= nil then lastTownPick = pick; end
    end
    -- Keep-on-subjob (v44, gate fixed in round 2): a subjob-only flip loses
    -- the lockstyle -- the mog-house path clears it server-side (0x100
    -- handler) and the client's own job-change reflex sends a DISABLE (its
    -- private flag is off, the zone-in story again). Round 1 gated the
    -- re-apply on the guard still holding the lockstyle live, and that
    -- DISABLE had already retired the guard by flip time -- the gate vetoed
    -- the exact event the feature exists for. Now lastBox alone is the
    -- authority: it survives client noise and clears only when the PLAYER
    -- ends the lockstyle ('retire'/'adopt' in the guard). The flip also arms
    -- the guard's blockable window, so a straggling DISABLE around the
    -- change is swallowed whichever side of our re-apply it lands on.
    local sub = subAbbr();
    if sub ~= lastSub then
        local realFlip = (lastSub ~= nil) and (pendingJob == nil);   -- not login settle, not a main change in flight
        lastSub = sub;
        if realFlip and data.keepSub == true and lastBox ~= nil then
            -- book-once: an earlier trigger (the DISABLE heal, or 0x100) may
            -- already hold the timer -- never push a booked heal further out
            if subDueAt == nil then subDueAt = os.clock() + 3; end
            if type(M._guardArm) == 'function' then M._guardArm(); end
        end
    end
    if subDueAt ~= nil and os.clock() >= subDueAt then
        subDueAt = nil;
        -- v46: the town pick governs the re-apply too -- the town box in a town,
        -- the last normal box otherwise, a drop in disable-in-town mode.
        local pick = (it ~= nil) and M._townPick(it, data.townOff, data.townBox) or nil;
        applyTownPick(pick, lastBox);
        if it ~= nil then lastTownPick = pick; end
    end
end

-- ---------------------------------------------------------------------------
-- Disable-in-town (v45): with data.townOff on, dlac wants the lockstyle OFF
-- while you stand in a town, so your inTown idle gear shows. Two pillars:
--   * PASSIVE -- the guard stops blocking the client's zone-in auto-disable in a
--     town (verdict 'suppress'), so an ALREADY-applied style just drops.
--   * ACTIVE  -- the pump STOPS the OnLoad / keep-on-sub apply from firing in a
--     town at all (Henrik: at login there is no style yet -- dlac applies it,
--     so we must not apply it in the first place, not merely disable it after).
-- Pure decision + the live wrapper (location = the central town service). A nil
-- inTown (mid-zone/unreadable) is NOT a town here -- callers hold via lastTownSup.
function M._wantTownOff(townOff, inTownVal) return townOff == true and inTownVal == true; end
function M._townSuppress()
    if data == nil or data.townOff ~= true or not _locok then return false; end
    return M._wantTownOff(true, location.inTown());
end
-- Town lockstyle pick (v46): what should show while you are in a town --
-- 'off' (disable-in-town: drop to your real gear), a BOX number (replace your
-- style with that town lockstyle), or nil (no override -- keep your normal
-- style). Pure; 'off' outranks a box (the GUI keeps them mutually exclusive --
-- this is just the safety). A nil inTown (unknown zone) is not a town here.
function M._townPick(inTownVal, townOff, townBox)
    if inTownVal ~= true then return nil; end
    if townOff == true then return 'off'; end
    local b = tonumber(townBox);
    if b ~= nil then return b; end
    return nil;
end
-- Leaving town (the town pick resolved to nil): should we DROP the town box we
-- applied instead of restoring? Yes only when we HAD a town box (lastPick is a
-- number) and there is NO base lockstyle to fall back to -- otherwise the guard
-- keeps the town box alive and the player is stuck with it outside town. Pure.
function M._townLeaveClear(lastPick, base)
    return base == nil and type(lastPick) == 'number';
end

-- ---------------------------------------------------------------------------
-- Zone-in guard (v43): dlac lockstyles survive zoning.
--
-- Field-pinned 2026-07-19 (dlacprobe v1.9 /probe ls, Mindie, Upper Jeuno):
-- the retail client keeps a PRIVATE lockstyle flag that only its own
-- /lockstyle command (or menu) sets, and ~0.6s after every zone-in packet it
-- re-asserts that flag to the server -- 0x053 CONTINUE when it thinks the
-- lock is on, 0x053 DISABLE when it thinks it is off. Our apply injects the
-- SET packet straight to the server, so the client's flag stays off and the
-- client itself killed the lockstyle on the next zone (the server is
-- blameless: it persists the lock in DB and reloads it every zone-in --
-- chars.isstylelocked, 0x053_lockstyle.cpp + charutils.cpp, read 07-19).
-- A natively-set lockstyle never dropped because CONTINUE healed it each
-- zone, which is also why the drops looked intermittent: any session that
-- ever touched native /lockstyle had the flag on.
--
-- The guard swallows exactly that one packet: an outgoing DISABLE inside the
-- zone-in window, while a lockstyle we saw SET is live, that the player did
-- not just ask for. Everything else passes untouched -- CONTINUE/QUERY
-- always, a DISABLE the player typed (the command stamp below), a DISABLE
-- outside the window, or one with no live lockstyle (blocking would be a
-- server no-op anyway; letting it through keeps the client honest).
-- Blocking beats re-applying: no undressed flash, no extra traffic, and the
-- house already intercepts appearance packets (lookpreview). The steady
-- state it preserves -- server locked, client flag off -- is exactly the
-- state every dlac lockstyle already lives in between zones today.
-- ---------------------------------------------------------------------------
local ZONE_WINDOW  = 10;   -- s after zone-in 0x00A the client's auto-DISABLE can land (field: ~0.6s)
local INTENT_WINDOW = 3;   -- s after a typed '/lockstyle off' its packet counts as the player's

-- Pure (headless-tested, LG series): one outgoing 0x053 mode -> what to do.
-- modes: 0 Disable / 1 Continue / 2 Query / 3 Set / 4 Enable (server enum).
-- The two disable verdicts are NOT the same thing (field round 2, the keep-
-- on-subjob fix): 'retire' = the player typed it -- the guard yields AND the
-- keep memory forgets the box, nothing may resurrect it. 'deactivate' = a
-- disable we let through but nobody asked for (the client's job-change
-- reflex, mostly) -- the guard yields but the keep memory SURVIVES, because
-- keep-on-subjob exists exactly for those. 'adopt' = a native /lockstyle on:
-- the server rebuilds the style from WORN gear, stomping any dlac box -- so
-- the guard arms but the box memory clears; keep must not resurrect a look
-- the player replaced.
function M._lsGuard(mode, now, zoneInAt, active, userOffAt, suppressTown)
    if mode == 3 then return 'activate'; end
    if mode == 4 then return 'adopt'; end
    if mode == 0 then
        if now - (userOffAt or -1e9) < INTENT_WINDOW then return 'retire'; end
        -- Disable-in-town (v45): in a town with the option on, dlac WANTS the
        -- lock off -- let any disable through (the client's zone-in auto-disable,
        -- or our own queued one) and KEEP lastBox so leaving town restores it.
        -- Never block, never book a keep-heal: townOff outranks keepSub in a town.
        if suppressTown then return 'suppress'; end
        if active and now - (zoneInAt or -1e9) < ZONE_WINDOW then return 'block'; end
        return 'deactivate';
    end
    return 'pass';
end

-- The job-change packet is the keep trigger of record (round 3). The memory
-- poll in the pump races the client's DISABLE -- field capture 2026-07-19
-- 11:27 (Upper Jeuno moogle): the DISABLE leaves AT menu confirm, before the
-- player struct shows the new sub, so a poll-armed window comes too late.
-- The outgoing 0x100 job-change request does not race anything: it leaves at
-- the same confirm, through this very handler, BEFORE the DISABLE. Fields
-- (server 0x100_myroom_job.h): MainJobIndex u8 @0x04, SupportJobIndex u8
-- @0x05, 0 = unchanged -- so main==0 with sub~=0 is a subjob-only change,
-- and re-selecting the SAME sub still shows here (the server still clears
-- style lock for it; the poll could never see that one). The pump's poll
-- stays as the fallback for job-change paths that skip 0x100.
function M._jobPktKind(mainIdx, subIdx)
    if (mainIdx or 0) ~= 0 then return 'main'; end
    if (subIdx or 0) ~= 0 then return 'sub'; end
    return 'none';
end

-- Round 4: the unasked DISABLE is the heal trigger of record. Field captures
-- (11:27 and 11:34, Upper Jeuno moogle) put it BEFORE the 0x100 on the wire
-- -- round 3's "arm off the job packet, it leaves first" was backwards -- and
-- it is the one event present in every observed kill of a kept lockstyle.
-- So the kill itself schedules the cure: an unasked disable passing through
-- ('deactivate') while keep is on and a box is remembered books the +3s
-- re-apply. Main-job changes stay safe without special-casing the order:
-- their 0x100 lands right after the DISABLE and nils lastBox, and the pump
-- re-checks lastBox when the timer fires. 0x100-sub and the pump's poll stay
-- as belts.
function M._keepHeal(verdict, keepSub, box)
    return verdict == 'deactivate' and keepSub == true and box ~= nil;
end

local guard = { active = false, zoneInAt = -1e9, userOffAt = -1e9 };
function M._guardUserOff() guard.userOffAt = os.clock(); end
function M._guardOn() return guard.active; end   -- window readout
-- The keep-on-subjob pump (above) calls this on a subjob flip it intends to
-- survive: the client's confused DISABLE (its private flag is off) can land
-- before OR after our re-apply, so open the same blockable window a zone-in
-- gets and swallow it either way.
function M._guardArm() guard.active = true; guard.zoneInAt = os.clock(); end

ashita.events.register('packet_in', 'dlac-lockstyle-pin', function(e)
    if e.id == 0x00A then guard.zoneInAt = os.clock(); end
end);

ashita.events.register('packet_out', 'dlac-lockstyle-pout', function(e)
    if e.id == 0x100 then
        local kind = M._jobPktKind((#e.data >= 6) and e.data:byte(5) or 0,
                                   (#e.data >= 6) and e.data:byte(6) or 0);
        if kind == 'main' then
            lastBox = nil;    -- new job = new box set; main changes are OnLoad's business
            subDueAt = nil;   -- cancels the heal the preceding DISABLE just booked
        elseif kind == 'sub' and data ~= nil and data.keepSub == true and lastBox ~= nil then
            M._guardArm();               -- stragglers around the change get swallowed
            if subDueAt == nil then      -- book-once (the DISABLE usually got here first)
                subDueAt = os.clock() + 3;
            end
        end
        return;
    end
    if e.id ~= 0x053 then return; end
    -- Mode u8 @0x05 (4-byte header + Count) -- same decode as dlacprobe's lsOut.
    local mode = (#e.data >= 6) and e.data:byte(6) or -1;
    local act = M._lsGuard(mode, os.clock(), guard.zoneInAt, guard.active, guard.userOffAt, M._townSuppress());
    if act == 'activate' then
        guard.active = true;
    elseif act == 'adopt' then
        guard.active = true;   -- native enable: live style = worn gear now
        lastBox = nil;         -- ...so the dlac box is not what is showing
        subDueAt = nil;        -- a pending heal must not stomp the new style
    elseif act == 'retire' then
        guard.active = false;
        lastBox = nil;         -- the player meant OFF: nothing resurrects it
        subDueAt = nil;        -- ...including a heal already booked
    elseif act == 'deactivate' then
        guard.active = false;  -- yields -- but lastBox survives (client noise)
        if M._keepHeal(act, data ~= nil and data.keepSub == true, lastBox)
           and subDueAt == nil then      -- book-once, like every other trigger
            subDueAt = os.clock() + 3;   -- the kill schedules the cure (round 4)
        end
    elseif act == 'suppress' then
        -- Disable-in-town (v45): we WANT the style off here -- let the disable
        -- reach the server (drops the lock, your inTown gear shows) and yield,
        -- but keep lastBox so leaving town restores it, and book no keep-heal.
        guard.active = false;
    elseif act == 'block' then
        -- silently (Henrik, field round 1): the player asked for a lockstyle;
        -- it still being on after a zone is not news.
        e.blocked = true;
    end
end);

-- Unloading mid-preview is the one way to leave a mark: ActorLockFlag would stay
-- set and freeze the model until a zone. End the preview first, always -- /addon
-- reload dlac is routine while iterating on this very window.
ashita.events.register('unload', 'dlac-lockstyle-unload', function()
    if _preview then endPreview(); end
end);

-- '/dl ls' in the ADDON state: open the window; block so the game parser stays
-- quiet. 'apply' is left for the LAC state's dispatch handler (it sees the
-- same command -- separate Lua state), which owns gFunc.LockStyle.
ashita.events.register('command', 'dlac-lockstyle', function(e)
    local raw = string.lower(e.command);
    -- The zone guard's user-intent stamp: a REAL '/lockstyle off' (typed, or
    -- queued by this window's Disable button) must never be blocked -- stamp
    -- it here and let it through; the guard reads the stamp when the client's
    -- 0x053 goes out a frame later.
    if raw:match('^/lockstyle%s+off%s*$') ~= nil then M._guardUserOff(); end
    local s = nil;
    if raw == '/dlac' or string.sub(raw, 1, 6) == '/dlac ' then s = 7;
    elseif raw == '/dl' or string.sub(raw, 1, 4) == '/dl ' then s = 5; end
    if s == nil then return; end
    local args = {};
    for a in string.gmatch(string.sub(raw, s), '%S+') do args[#args + 1] = a; end
    if args[1] ~= 'ls' then return; end
    e.blocked = true;
    if args[2] == nil or args[2] == 'open' or args[2] == 'ui' then M.open(); end
    -- Field-debug readout for the keep machinery ('/dl ls state'): every value
    -- the keep decision reads, plus a round marker -- an old seeded copy of
    -- this file answers with nothing, which is itself the diagnosis.
    if args[2] == 'state' then
        print(string.format('[dlac] ls state (keep round 6): keepSub=%s lastBox=%s lastSub=%s guardActive=%s healPending=%s',
            tostring(data ~= nil and data.keepSub or nil), tostring(lastBox), tostring(lastSub),
            tostring(guard.active), tostring(subDueAt ~= nil)));
        -- v46 town readout: run it while standing in a town to see WHY a town
        -- lockstyle did/didn't apply -- townBox=nil (setting lost), inTown~=true
        -- (zone not detected), lastPick=the applied pick, townDue=apply pending.
        print(string.format('[dlac] ls town (v46): townOff=%s townBox=%s inTown=%s lastPick=%s townDue=%s',
            tostring(data ~= nil and data.townOff or nil), tostring(data ~= nil and data.townBox or nil),
            tostring(_locok and location.inTown()), tostring(lastTownPick), tostring(townDueAt ~= nil)));
    end
    -- Keep-on-subjob's memory of "the lockstyle that is on": every apply
    -- passes through here (GUI button, OnLoad pump, hand-typed -- the LAC
    -- state's dispatch does the actual sending, this state just remembers).
    -- No explicit box = the marked one, same resolution dispatch uses.
    if args[2] == 'apply' then
        lastBox = tonumber(args[3]) or (data ~= nil and tonumber(data.active)) or nil;
    end
end);

return M;
