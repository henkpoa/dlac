-- Headless tests for the profile-side rebuild engine (utils.lua).
-- Run from the dlac addon root:   lua tests\run_tests.lua
-- No Ashita required: gData / AshitaCore / ashita are stubbed below.

-- ---------------------------------------------------------------------------
-- environment stubs (must exist BEFORE utils.lua loads)
-- ---------------------------------------------------------------------------
package.loaded['dlac\\gear'] = { NameToObject = {} };   -- utils requires dlac\gear at load
ashita = { events = { register = function() end } };    -- utils registers /dl at load
package.loaded['dlac\\profiles'] = dofile('profiles.lua');   -- dispatch/setmanager require it (guarded)
package.loaded['dlac\\data\\nativemp'] = dofile('data/nativemp.lua');   -- dispatch requires it (Oneiros resolver)
package.loaded['dlac\\data\\zones'] = dofile('data/zones.lua');   -- dispatch requires it (the inTown town set)
package.loaded['dlac\\feature\\mpbands'] = dofile('feature/mpbands.lua');   -- dispatch requires it (the banded ladder, maxmp v2)
package.loaded['dlac\\feature\\location'] = dofile('feature/location.lua');   -- lockstyle requires it (Disable-in-town)
package.loaded['dlac\\gear\\jobgate'] = dofile('gear/jobgate.lua');   -- lockstyle requires it (v47 picker/box job-level gate)
package.loaded['dlac\\gear\\gearrecord'] = dofile('gear/gearrecord.lua');   -- record rules: gearimport/weaponfilter/gearexport require it
package.loaded['dlac\\lib\\safewrite'] = dofile('lib/safewrite.lua');   -- safe-replace ladder: gearimport requires it, profiles guards it
package.loaded['dlac\\gear\\catalogindex'] = dofile('gear/catalogindex.lua');   -- catalog walker: gearimport requires it (no catalog headless -> empty indexes)
package.loaded['dlac\\gear\\gearoracle'] = dofile('gear/gearoracle.lua');   -- THE worn-item/bag door: gearimport + useitem require it (issue #70; parity-pinned below)
package.loaded['dlac\\lib\\statefile'] = dofile('lib/statefile.lua');   -- addon-side charDir: the watchers require it (guarded)

local TEST_PLAYER = nil;                                -- set per test
gData = { GetPlayer = function() return TEST_PLAYER; end };

-- AshitaCore stub: controls the Dual Wield trait bit (HasAbility(1554)) and records
-- the id actually asked for, so a wrong trait id fails the test.
local lastAbilityId = nil;
local function ashitaWithDW(hasDW)
    local p = {
        GetMainJob = function(self) return 7; end,      -- any valid 1..22 job id
        HasAbility = function(self, id) lastAbilityId = id; return hasDW; end,
    };
    return { GetMemoryManager = function(self) return { GetPlayer = function(self) return p; end }; end };
end

AshitaCore = nil;
-- The REAL dispatch engine, loaded headlessly BEFORE utils so utils captures it as
-- M.dispatchModule: BuildDynamicSets consults dispatch.modeActive for mode-gated
-- set entries (section G drives dispatch.M.modes directly).
local dispatchM = dofile('dispatch.lua');
package.loaded['dlac\\dispatch'] = dispatchM;
local utils = dofile('utils.lua');

-- ---------------------------------------------------------------------------
-- tiny runner
-- ---------------------------------------------------------------------------
local failures, count = {}, 0;
local function check(name, got, want)
    count = count + 1;
    if got ~= want then
        failures[#failures + 1] = string.format('%s: got %s, want %s', name, tostring(got), tostring(want));
    end
end

-- ---------------------------------------------------------------------------
-- OR. Gear Oracle parity pins (issue #70) -- worn-item decode + equip-bag list.
--
--   The oracle (gear/gearoracle.lua) is the ONE door in the addon state; the
--   seeded engine (dispatch.lua) keeps its OWN twin decode + bag list because
--   ADR 0002 forbids it requiring addon modules. These pins feed BOTH the door
--   and the engine twin a fixture matrix so the two can never silently drift --
--   and every failure message NAMES the twin (dispatch.decodeEquipIndex /
--   dispatch.AMMO_BAGS) so the fix has an address. Prior art: the Blueprints
--   serializer parity pins (TGB34/35).
-- ---------------------------------------------------------------------------
(function()
    local oracle = package.loaded['dlac\\gear\\gearoracle'];
    check('OR0 oracle module present',        type(oracle), 'table');
    check('OR1 wornItem is the door',         type(oracle.wornItem), 'function');
    check('OR2 equipBags is the door',        type(oracle.equipBags), 'function');
    check('OR3 decodeIndex is pure+exported', type(oracle.decodeIndex), 'function');

    -- LITERAL bag-list comparison: oracle.equipBags() vs the engine twin
    -- dispatch.AMMO_BAGS, element for element. The list is Inventory(0) + the 8
    -- Wardrobes (8,10-16) -- pinned ABSOLUTELY too, so a matched drift in BOTH
    -- copies is still caught.
    local EXPECT_BAGS = { 0, 8, 10, 11, 12, 13, 14, 15, 16 };
    local bags = oracle.equipBags();
    local twinBags = dispatchM.AMMO_BAGS;
    check('OR4 engine exposes twin bag list (dispatch.AMMO_BAGS)', type(twinBags), 'table');
    check('OR5 oracle bag list length',      #bags, #EXPECT_BAGS);
    check('OR6 twin bag list length (dispatch.AMMO_BAGS)', twinBags and #twinBags, #EXPECT_BAGS);
    for i = 1, #EXPECT_BAGS do
        check('OR7.' .. i .. ' oracle bag[' .. i .. '] == absolute',      bags[i], EXPECT_BAGS[i]);
        check('OR8.' .. i .. ' twin bag[' .. i .. '] == oracle (dispatch.AMMO_BAGS DRIFT)',
              twinBags and twinBags[i], bags[i]);
    end

    -- DECODE parity matrix: synthetic packed Indexes (high byte = container, low
    -- byte = slot) fed to oracle.decodeIndex AND dispatch.decodeEquipIndex. Both
    -- must agree with each other AND with the hand-computed container/slot.
    local FIX = {
        { idx = 0x0001, cont = 0,   slot = 1   },  -- Inventory, slot 1
        { idx = 0x0801, cont = 8,   slot = 1   },  -- Wardrobe, slot 1
        { idx = 0x0A05, cont = 10,  slot = 5   },  -- Wardrobe 2, slot 5
        { idx = 0x1010, cont = 16,  slot = 16  },  -- Wardrobe 8, slot 16
        { idx = 0x0100, cont = 1,   slot = 0   },  -- container 1, slot 0
        { idx = 0x00FF, cont = 0,   slot = 255 },  -- low-byte extreme
        { idx = 0xFFFF, cont = 255, slot = 255 },  -- both-byte extreme
    };
    for _, f in ipairs(FIX) do
        local oc, os_ = oracle.decodeIndex(f.idx);
        local tc, ts  = dispatchM.decodeEquipIndex(f.idx);
        local tag = string.format('0x%04X', f.idx);
        check('OR9 oracle decode container ' .. tag,  oc,  f.cont);
        check('OR10 oracle decode slot ' .. tag,      os_, f.slot);
        check('OR11 twin decode container ' .. tag .. ' (dispatch.decodeEquipIndex DRIFT)', tc, oc);
        check('OR12 twin decode slot ' .. tag .. ' (dispatch.decodeEquipIndex DRIFT)',      ts, os_);
    end

    -- wornItem is safe to call headless (no AshitaCore) and returns nil, never throws.
    check('OR13 wornItem headless-safe', oracle.wornItem(0), nil);

    -- Eligibility + identity join the oracle (issue #71). These are FACADE checks:
    -- the door must give the SAME answer as the interpreter it fronts. canWear must
    -- track dispatch.canWear exactly (the two inline fallbacks are deleted); a claim-
    -- blind boundary means it never consults locks/pins/claims.
    check('OR14 canWear is the door',        type(oracle.canWear), 'function');
    check('OR15 anyJobCanWear is the door',  type(oracle.anyJobCanWear), 'function');
    check('OR16 lookup is the door',         type(oracle.lookup), 'function');
    check('OR17 setLookupSource is the door',type(oracle.setLookupSource), 'function');

    -- canWear parity with the fronted engine rule (dispatch.canWear), same matrix as J5-7.
    local CW = {
        { rec = { Jobs = { 'RDM' }, Level = 74 }, job = 'RDM', lvl = 73 },  -- under level
        { rec = { Jobs = { 'RDM' }, Level = 74 }, job = 'RDM', lvl = 74 },  -- at level
        { rec = { Jobs = { 'WHM' }, Level = 10 }, job = 'RDM', lvl = 75 },  -- wrong job
        { rec = { Jobs = { 'All' }, Level = 20 }, job = 'RDM', lvl = 20 },  -- All at level
        { rec = { Level = 5 },                    job = 'RDM', lvl = 99 },  -- no Jobs -> wearable
    };
    for i, c in ipairs(CW) do
        check('OR18.' .. i .. ' canWear == dispatch.canWear (fronted rule)',
              oracle.canWear(c.rec, c.job, c.lvl), dispatchM.canWear(c.rec, c.job, c.lvl));
    end

    -- anyJobCanWear delegates to the addon-state gate module (jobgate.canEquip), same
    -- answer, and keeps its FAIL-OPEN semantics (nil/unknown offers everything).
    local jg = package.loaded['dlac\\gear\\jobgate'];
    local AJ = {
        { rec = { Jobs = { 'THF' }, Level = 30 }, jl = { THF = 30 } },  -- on-job at level
        { rec = { Jobs = { 'THF' }, Level = 50 }, jl = { THF = 30 } },  -- under level
        { rec = { Jobs = { 'All' }, Level = 40 }, jl = { WHM = 50 } },  -- All, one at level
        { rec = { Jobs = { 'BLM' }, Level = 1  }, jl = { WHM = 50 } },  -- no such job
        { rec = { Level = 99 },                   jl = { WHM = 1  } },  -- no Jobs -> pass
    };
    for i, c in ipairs(AJ) do
        check('OR19.' .. i .. ' anyJobCanWear == jobgate.canEquip (delegation)',
              oracle.anyJobCanWear(c.rec, c.jl), jg.canEquip(c.rec, c.jl));
    end
    -- No fabricated fail-open inside the door: nil jobLevels delegates faithfully
    -- (the CALLER short-circuits on jobLevels == nil -- lockstyle's gateOk does). An
    -- unknown record (no Jobs) still passes, jobgate's own fail-open.
    check('OR20 anyJobCanWear on nil jobLevels == jobgate (no fabricated fail-open)',
          oracle.anyJobCanWear({ Jobs = { 'WAR' }, Level = 1 }, nil), jg.canEquip({ Jobs = { 'WAR' }, Level = 1 }, nil));
    check('OR20b anyJobCanWear passes an unknown record (no Jobs)', oracle.anyJobCanWear({ Level = 99 }, {}), true);

    -- lookup(idOrName): the owned+catalog JOIN recipe. Inject a stub source (the role
    -- gearui fills in production) and prove owned wins over catalog, id is authoritative,
    -- name is the case-insensitive fallback, and a miss is nil.
    local owned = { byId = { [7] = { Name = 'Owned Cap', Id = 7 } },
                    byName = { ['owned cap'] = { Name = 'Owned Cap', Id = 7 } } };
    local cat   = { byId = { [7] = { Name = 'Catalog Cap', Id = 7 }, [9] = { Name = 'Catalog Only', Id = 9 } },
                    byName = { ['catalog only'] = { Name = 'Catalog Only', Id = 9 } } };
    oracle.setLookupSource({
        ownedById     = function(id) return owned.byId[id]; end,
        ownedByName   = function(ln) return owned.byName[ln]; end,
        catalogById   = function(id) return cat.byId[id]; end,
        catalogByName = function(ln) return cat.byName[ln]; end,
    });
    check('OR21 lookup by id: owned wins over catalog', oracle.lookup(7).Name, 'Owned Cap');
    check('OR22 lookup by id: catalog fallback',        oracle.lookup(9).Name, 'Catalog Only');
    check('OR23 lookup by id: unknown -> nil',          oracle.lookup(404), nil);
    check('OR24 lookup by name: owned wins',            oracle.lookup('Owned Cap').Name, 'Owned Cap');
    check('OR25 lookup by name: case-insensitive fallback', oracle.lookup('CATALOG only').Name, 'Catalog Only');
    check('OR26 lookup by name: unknown -> nil',        oracle.lookup('nope'), nil);
    check('OR27 lookup nil arg -> nil',                 oracle.lookup(nil), nil);
    oracle.setLookupSource(nil);
    check('OR28 lookup with no source -> nil',          oracle.lookup(7), nil);

    -- CLAIM-BLIND boundary (PRD #69): the oracle answers capability, never permission.
    -- It must expose no may-word door -- canEquip is the Arbiter's word, never the
    -- oracle's -- and no method may consult locks/pins/claims (all absent by design).
    check('OR29 no permission-word door (canEquip never exists on the oracle)', oracle.canEquip, nil);
end)();

-- ---------------------------------------------------------------------------
-- GRD. Gear Oracle HARD RULE source guards (issue #73, PRD #69) -- "the door
--      becomes law". Source-level greps that make a private gear deduction a CI
--      failure, not a review catch. Prior art in spirit: the Sub-slot never-gated
--      A* HARD RULES (behaviour) and the OR parity pins (twins) above; these are
--      the SOURCE ratchet. Each guard:
--        * confines a centralized gear answer to its ONE sanctioned home(s);
--        * on reintroduction elsewhere, FAILS naming the rule + the offending file;
--        * carries a SELF-CHECK proving the pattern is actually detectable (a guard
--          that matches nothing is a false sense of security -- issue #73).
--
--      The interpreter-require guard (GRD5) carries the ONE temporary allowlist --
--      the Phase-2 stat-glue surfaces that still hand-glue level-scaled/augment/
--      set-bonus stats. Oracle step 5 (issue #74) migrates them onto oracle.stats()
--      / setStats() and EMPTIES the allowlist; from then the rule is absolute.
-- ---------------------------------------------------------------------------
(function()
    -- Read a source file with Lua comments stripped, so a PROSE mention of a
    -- banned idiom (e.g. gearui's "equipped-item lookup via GetEquippedItem"
    -- doc-comment) never false-trips a guard. Block comments (--[[ ]] / --[==[ ]==])
    -- first, then line comments to EOL. Returns '' for a missing/empty file.
    local function readStripped(path)
        local fh = io.open(path, 'r');
        if fh == nil then return nil; end
        local src = fh:read('*a'); fh:close();
        if type(src) ~= 'string' then return ''; end
        src = src:gsub('%-%-%[(=*)%[.-%]%1%]', ' ');   -- long-bracket block comments
        src = src:gsub('%-%-[^\n]*', '');              -- line comments
        return src;
    end

    -- The production modules the guards scan. Explicit (deterministic, cross-platform
    -- -- no io.popen, which the repo forbids for discovery) and MAINTAINED: a new
    -- logic module belongs here so it cannot dodge the ratchet. Generated data tables
    -- (data/catalog, fishdb, spells, ...) carry no gear-fetch logic and are excluded.
    local ROOT_FILES = { 'utils.lua', 'dispatch.lua', 'chatfmt.lua', 'profiles.lua', 'gear.lua', 'dlac.lua' };
    local UI = { 'ammoui','automationsui','craftbar','equippedui','filetex','fishbar','fishui',
                 'floatgear','gearui','helmbar','helmui','hobbybar','idlefloat','itemicons','menuui','priorityui','profilesmenu',
                 'restockui','setupui','triggersui','uihost','uistyle','weightsui' };
    local GEAR = { 'actionpicker','blueprintsmodel','catalogindex','gearcheck','geareffects','gearexport',
                   'gearfmt','gearimport','gearoptim','gearoracle','gearrecord','groupimport','groupscan',
                   'groupsmodel','jobgate','modeslibrary','ownedcache','profileexport','profilesets','setimport',
                   'setmanager','syncflags','triggermodel','weaponfilter','weightimport' };
    local FEATURE = { 'ammowatch','arbwatch','augments','check','chocowatch','craftwatch','debug','digcalc','digrank',
                      'eboxammo','eboxclient','eboxtrace','fishcalc','fishwatch','gamemode','helmwatch','idleexcl','location','lockstyle','lookpreview',
                      'macrobook','meritwatch','mpbands','pinwatch','restockwatch','synthrun','useitem','vanamoon' };
    local LIB = { 'cmdqueue','entwatch','safewrite','statefile' };

    local ALL = {};
    for _, f in ipairs(ROOT_FILES) do ALL[#ALL + 1] = f; end
    for _, n in ipairs(UI)      do ALL[#ALL + 1] = 'ui/' .. n .. '.lua'; end
    for _, n in ipairs(GEAR)    do ALL[#ALL + 1] = 'gear/' .. n .. '.lua'; end
    for _, n in ipairs(FEATURE) do ALL[#ALL + 1] = 'feature/' .. n .. '.lua'; end
    for _, n in ipairs(LIB)     do ALL[#ALL + 1] = 'lib/' .. n .. '.lua'; end

    -- Cache each scanned file's stripped source once.
    local STRIPPED = {};
    local readable = 0;
    for _, path in ipairs(ALL) do
        local s = readStripped(path);
        if s ~= nil then STRIPPED[path] = s; readable = readable + 1; end
    end
    -- Coverage sanity: the scan must actually see the files (a wrong CWD would make
    -- every guard vacuously pass). gearoracle + dispatch are load-bearing sanctions.
    check('GRD0 scan sees the tree (CWD is the addon root)', readable >= #ALL, true);
    check('GRD0a scan reached the oracle',  STRIPPED['gear/gearoracle.lua'] ~= nil and #STRIPPED['gear/gearoracle.lua'] > 0, true);
    check('GRD0b scan reached the engine',  STRIPPED['dispatch.lua'] ~= nil and #STRIPPED['dispatch.lua'] > 0, true);

    -- Run `detect` over every scanned file except the sanctioned homes; return the
    -- offenders as a comma-joined string ('' == clean). `subset` limits the scan
    -- (nil == the whole tree) so a folder-scoped rule (interpreter requires) only
    -- polices its folder.
    local function offendersOf(detect, sanctioned, subset)
        local list = subset or ALL;
        local hits = {};
        for _, path in ipairs(list) do
            local s = STRIPPED[path];
            if s ~= nil and not sanctioned[path] and detect(s) then
                hits[#hits + 1] = path;
            end
        end
        return table.concat(hits, ', ');
    end

    -- Prove a sanctioned home actually CONTAINS the idiom -- otherwise the guard
    -- guards nothing (the pattern rotted) and its green is a lie.
    local function present(detect, path)
        local s = STRIPPED[path];
        return (s ~= nil and detect(s)) == true;
    end

    -- --- GRD1: raw equipped-item read (the worn-item packed-index decode entry).
    -- GetEquippedItem is THE raw equipped-item read (PRD: duplicated x4 before the
    -- oracle). Confined to the engine twin (dispatch) + the oracle door. Match the
    -- CALL form so a stray prose mention that survived comment-stripping still can't
    -- trip it.
    local function hasWornRead(s) return s:find('GetEquippedItem%s*%(') ~= nil; end
    local WORN_HOMES = { ['dispatch.lua'] = true, ['gear/gearoracle.lua'] = true };
    check('GRD1 raw GetEquippedItem read confined to {dispatch, gearoracle}',
          offendersOf(hasWornRead, WORN_HOMES), '');
    check('GRD1a self-check: the read pattern is detectable', hasWornRead('local e = inv:GetEquippedItem(0)'), true);
    check('GRD1b self-check: prose without a call does not trip', hasWornRead('the GetEquippedItem index maps to a slot'), false);
    check('GRD1c self-check: the engine twin really holds the read', present(hasWornRead, 'dispatch.lua'), true);
    check('GRD1d self-check: the oracle door really holds the read', present(hasWornRead, 'gear/gearoracle.lua'), true);

    -- --- GRD2: the packed-index decode ARITHMETIC (container + slot from one Index).
    -- The distinctive signature is the TWO-value split "... / 256) % 256, <i> % 256"
    -- (container AND slot). Plain "math.floor(x / 256) % 256;" is generic byte-split
    -- packet math (eboxammo/lookpreview/dispatch packet code) and is NOT banned -- the
    -- trailing comma is what marks the worn-index decode. Confined to {dispatch, oracle}.
    local function hasIndexDecode(s) return s:find('/%s*256%s*%)%s*%%%s*256%s*,') ~= nil; end
    check('GRD2 packed-index decode arithmetic confined to {dispatch, gearoracle}',
          offendersOf(hasIndexDecode, WORN_HOMES), '');
    check('GRD2a self-check: the decode split is detectable',
          hasIndexDecode('return math.floor(index / 256) % 256, index % 256'), true);
    check('GRD2b self-check: a lone byte-split is not the decode',
          hasIndexDecode('pkt[o] = math.floor(id / 256) % 256;'), false);
    check('GRD2c self-check: the engine twin really holds the decode', present(hasIndexDecode, 'dispatch.lua'), true);
    check('GRD2d self-check: the oracle door really holds the decode', present(hasIndexDecode, 'gear/gearoracle.lua'), true);

    -- --- GRD3: the equip-eligible bag list literal (Inventory + 8 Wardrobes).
    -- { 0, 8, 10, 11, 12, 13, 14, 15, 16 } -- duplicated x4 before the oracle. Confined
    -- to the engine twin (dispatch.AMMO_BAGS) + the oracle (EQUIP_BAGS); every other
    -- consumer sources oracle.equipBags().
    local function hasBagList(s)
        return s:find('0%s*,%s*8%s*,%s*10%s*,%s*11%s*,%s*12%s*,%s*13%s*,%s*14%s*,%s*15%s*,%s*16') ~= nil;
    end
    check('GRD3 equip-bag list literal confined to {dispatch, gearoracle}',
          offendersOf(hasBagList, WORN_HOMES), '');
    check('GRD3a self-check: the bag list is detectable',
          hasBagList('local B = { 0, 8, 10, 11, 12, 13, 14, 15, 16 };'), true);
    check('GRD3b self-check: a different bag set does not trip',
          hasBagList('local B = { 0, 1, 2, 3, 4, 5, 6, 7, 8 };'), false);
    check('GRD3c self-check: the engine twin really holds the list', present(hasBagList, 'dispatch.lua'), true);
    check('GRD3d self-check: the oracle door really holds the list', present(hasBagList, 'gear/gearoracle.lua'), true);

    -- --- GRD4: the 22-job ORDERED list ({ 'WAR', 'MNK', 'WHM', ... }).
    -- The gate/level list, duplicated across the engine twins and the addon gate. The
    -- id->name MAP form ([1]='WAR',[2]='MNK', ... used by gearui/gearimport to decode a
    -- numeric job id) is a DIFFERENT structure and is deliberately not matched -- only a
    -- comma-then-quote sequence (the ordered list) trips. Confined to the engine twins
    -- (dispatch.LS_JOBS, profiles.JOBS) + the addon-state gate the oracle delegates to
    -- (jobgate.JOBS -- anyJobCanWear's home).
    local function hasJobList(s) return s:find("WAR['\"]%s*,%s*['\"]MNK['\"]%s*,%s*['\"]WHM") ~= nil; end
    local JOB_HOMES = { ['dispatch.lua'] = true, ['profiles.lua'] = true, ['gear/jobgate.lua'] = true };
    check('GRD4 22-job ordered list confined to {dispatch, profiles, jobgate}',
          offendersOf(hasJobList, JOB_HOMES), '');
    check('GRD4a self-check: the ordered list is detectable',
          hasJobList("local J = { 'WAR', 'MNK', 'WHM', 'BLM' };"), true);
    check('GRD4b self-check: the id->name map form does not trip',
          hasJobList("local J = { [1]='WAR',[2]='MNK',[3]='WHM' };"), false);
    check('GRD4c self-check: an engine twin really holds the list', present(hasJobList, 'dispatch.lua'), true);
    check('GRD4d self-check: the addon gate really holds the list', present(hasJobList, 'gear/jobgate.lua'), true);

    -- --- GRD5: interpreter REQUIRES (feature/ + ui/ only). The stat interpreters the
    -- oracle fronts -- level-stats resolver (data\levelstats), set-bonus evaluator
    -- (gear\geareffects), augment decoder (feature\augments) -- may be required only by
    -- the oracle and the gear pipeline itself. A feature/UI module that loads one is
    -- hand-gluing stats; it must ask the oracle instead. (The catalog index is a
    -- STANDING central service -- callers browse it directly, architecture.md -- so it
    -- is not policed here; the oracle fronts it only for the identity JOIN.)
    --
    -- On-disk the path reads with escaped separators (dlac\\data\\levelstats); plain
    -- find, backslashes literal. Load form (require / try / pcall) is irrelevant -- the
    -- PATH string is the signal.
    local function loadsInterp(s)
        return s:find('dlac\\\\data\\\\levelstats', 1, true) ~= nil
            or s:find('dlac\\\\gear\\\\geareffects', 1, true) ~= nil
            or s:find('dlac\\\\feature\\\\augments', 1, true) ~= nil;
    end
    -- The feature/ + ui/ slice only (the gear pipeline is a sanctioned requirer).
    local FEATURE_UI = {};
    for _, n in ipairs(UI)      do FEATURE_UI[#FEATURE_UI + 1] = 'ui/' .. n .. '.lua'; end
    for _, n in ipairs(FEATURE) do FEATURE_UI[#FEATURE_UI + 1] = 'feature/' .. n .. '.lua'; end

    -- THE ALLOWLIST -- EMPTIED by Oracle step 5 (issue #74). The Phase-2 stat-glue
    -- surfaces (automationsui manifest ladders, gearui Sets-core totals/hover/scoring,
    -- equippedui worn-augment display) were migrated onto oracle.stats()/setStats()
    -- plus the augment passthrough, so NO feature/UI module loads an interpreter any
    -- more. The table is now {} and the rule is ABSOLUTE: a new interpreter require in
    -- feature/ or ui/ is a CI failure, no exemptions. It must stay empty.
    local STATGLUE_ALLOWLIST = {};
    check('GRD5 stat interpreters (levelstats/geareffects/augments) not loaded outside the allowlist',
          offendersOf(loadsInterp, STATGLUE_ALLOWLIST, FEATURE_UI), '');
    check('GRD5a self-check: an interpreter load is detectable',
          loadsInterp('local g = require("dlac\\\\gear\\\\geareffects")'), true);
    check('GRD5b self-check: a try-form load is detectable',
          loadsInterp('local a = try("dlac\\\\feature\\\\augments")'), true);
    check('GRD5c self-check: the oracle door is not a stat-interpreter load',
          loadsInterp('local o = require("dlac\\\\gear\\\\gearoracle")'), false);
    check('GRD5d self-check: the catalog index is a standing service, not policed here',
          loadsInterp('local c = require("dlac\\\\gear\\\\catalogindex")'), false);
    -- The allowlist is EMPTY and must STAY empty (issue #74 finishing move): a
    -- non-zero count is a re-introduced stat-glue exemption and fails here, so the
    -- door stays absolute.
    local allowN = 0;
    for _ in pairs(STATGLUE_ALLOWLIST) do allowN = allowN + 1; end
    check('GRD5e allowlist is EMPTY -- the door is absolute (issue #74)', allowN, 0);
    check('GRD5f every allowlist entry is a real, scanned module', (function()
        for path in pairs(STATGLUE_ALLOWLIST) do
            if STRIPPED[path] == nil then return path; end   -- a stale name would silently widen the rule
        end
        return '';
    end)(), '');
end)();

-- ---------------------------------------------------------------------------
-- fixtures
-- ---------------------------------------------------------------------------
local sword1H  = { Name = 'Joyeuse',       Level = 72, OneHanded = true,  Type = 'Sword'  };
local dagger1H = { Name = 'Kris',          Level = 71, OneHanded = true,  Type = 'Dagger' };
local shield   = { Name = 'GenbusShield',  Level = 70, OneHanded = false, Type = 'Shield' };
local grip     = { Name = 'PoleGrip',      Level = 71, OneHanded = false, Type = 'Grip'   };
local gsword2H = { Name = 'Ragnarok',      Level = 73, OneHanded = false, Type = 'Great Sword' };
local twinKris = { Name = 'Kris',          Level = 71, OneHanded = true,  Type = 'Dagger', Count = 2 };

-- catalog-vocabulary records (imported gear: shields AND grips say Type="Sub";
-- weapons carry a skill name + OneHanded)
local catShield = { Name = 'Jennet Shield', Level = 38, Type = 'Sub' };
local catGrip   = { Name = 'Ariesian Grip', Level = 60, Type = 'Sub' };
local catAxe1H  = { Name = 'Kriegsbeil',    Level = 70, Type = 'Axe', OneHanded = true };

-- ---------------------------------------------------------------------------
-- A. subSlotAllowed -- the shared Sub-slot pairing rule
--
--    HARD RULE (Henrik, 2026-07-12; reverted THREE times before this -- if one
--    of these checks is in your way, you are about to revert it a fourth time.
--    STOP and read docs/adr/0006-builder-plans-engine-decides.md, addendum):
--    building=true (composing a set) offers EVERY Sub-capable item -- shield,
--    grip, one-hander -- regardless of Main pick, DW trait, or any live state.
--    Only physical impossibility excludes: 2H/H2H in Sub; same-name without a
--    provable second copy. Equip-time (building absent): DW/pairing decides.
-- ---------------------------------------------------------------------------
check('A0 subSlotAllowed exported', type(utils.subSlotAllowed), 'function');
if type(utils.subSlotAllowed) == 'function' then
    local f = utils.subSlotAllowed;
    -- H2H: the OneHanded flag is UNRELIABLE in the wild -- the catalog stamped
    -- true (apicrawl's old ONE set) and /dl fix backfilled it into files, fresh
    -- scans stamp false, legacy entries carry none -- so the rule keys on Type.
    -- h2hCat is the FIELD shape (the catalog lie) that slipped the craft guard.
    -- (Block-local on purpose: the main chunk sits at Lua's 200-local limit.)
    local h2hCat    = { Name = 'Beat Cesti',    Level = 40, Type = 'HandToHand',   OneHanded = true };
    local h2hLegacy = { Name = 'Cat Baghnakhs', Level = 30, Type = 'Hand-to-Hand' };
    -- HARD RULE regression guards -- building never adapts to Main/DW:
    check('A1 HARD RULE build: 1H+1H, no DW -> offered',      f(sword1H, dagger1H, { building = true             }), true);
    check('A5 HARD RULE build: 1H even with 2H main planned', f(sword1H, gsword2H, { dw = true, building = true  }), true);
    check('A7 HARD RULE build: grip even with 1H main',       f(grip,    dagger1H, { dw = true, building = true  }), true);
    check('A11 HARD RULE build: no Main planned -> still offered', f(sword1H, nil,  { dw = true, building = true  }), true);
    check('A14 HARD RULE build: catalog grip, 1H main',       f(catGrip, catAxe1H, { dw = true, building = true  }), true);
    check('A16 HARD RULE build: catalog 1H weapon',           f(catAxe1H, dagger1H, { building = true            }), true);
    -- building-time exclusions are PHYSICAL only:
    check('A12 build: 2H sub weapon never',  f(gsword2H, dagger1H, { dw = true, building = true }), false);
    check('A8 same name: file Count >= 2',   f(twinKris, twinKris, { building = true            }), true);
    check('A8b equip: file Count enables same-name DW', f(twinKris, twinKris, { dw = true       }), true);
    check('A9 same name: two copies',        f(dagger1H, dagger1H, { building = true, copies = 2 }), true);
    check('A10 same name: single copy',      f(dagger1H, dagger1H, { building = true, copies = 1 }), false);
    -- equip-time (building absent) stays strictly gated -- the ENGINE's call:
    check('A2 equip: 1H+1H, no DW',          f(sword1H, dagger1H, {           }), false);
    check('A3 equip: 1H+1H, DW',             f(sword1H, dagger1H, { dw = true }), true);
    check('A4 equip: 2H main, grip ok',      f(grip,    gsword2H, { dw = true }), true);
    check('A5b equip: 2H main, 1H never',    f(sword1H, gsword2H, { dw = true }), false);
    check('A6 equip: 1H main, shield always', f(shield, dagger1H, {           }), true);
    check('A7b equip: 1H main, grip never',  f(grip,    dagger1H, { dw = true }), false);
    check('A11b equip: no main -> no sub',   f(sword1H, nil,      { dw = true }), false);
    check('A13 equip: catalog shield, 1H main', f(catShield, catAxe1H, {      }), true);
    check('A14b equip: catalog grip, 1H main',  f(catGrip, catAxe1H, { dw = true }), false);
    check('A15 equip: catalog grip, 2H main',   f(catGrip, gsword2H, {        }), true);
    check('A17 classifySub exported',        type(utils.classifySub), 'function');
    -- H2H pairs with NOTHING at equip time (server knocks grips too, unlike
    -- 2H) -- and the catalog's OneHanded=true lie must not win (field case
    -- 2026-07-22: a monk's Main vs the craft overlay's Kupo Shield):
    check('A18 equip: H2H main, shield never',           f(shield,  h2hCat, {           }), false);
    check('A19 equip: H2H main, grip never (unlike 2H)', f(grip,    h2hCat, {           }), false);
    check('A20 equip: H2H main, 1H weapon never',        f(sword1H, h2hCat, { dw = true }), false);
    check('A21 equip: legacy-spelled H2H main held too', f(shield,  h2hLegacy, {        }), false);
    check('A22 equip: H2H never sits in Sub',            f(h2hCat, dagger1H, { dw = true }), false);
    check('A23 build: H2H in Sub never -- physical, like 2H',
          f(h2hCat, dagger1H, { dw = true, building = true }), false);
    -- HARD RULE stands: an H2H MAIN planned still gates nothing while building
    check('A24 HARD RULE build: shield offered with H2H main planned',
          f(shield,  h2hCat, { building = true }), true);
    check('A25 HARD RULE build: 1H offered with H2H main planned',
          f(sword1H, h2hCat, { building = true }), true);
end

-- ---------------------------------------------------------------------------
-- B. isDualWieldAvailable -- the memory trait bit (1554) is authoritative
-- ---------------------------------------------------------------------------
AshitaCore = ashitaWithDW(true);
check('B1 memory bit true -> true',  utils.isDualWieldAvailable('WAR', 75, 'WHM', 37), true);
check('B2 asks for trait id 1554',   lastAbilityId, 1554);
AshitaCore = ashitaWithDW(false);
-- CatsEyeXI truth: memory answer must WIN over the legacy THF>=20 table
check('B3 memory bit false beats legacy THF row', utils.isDualWieldAvailable('THF', 75, 'WHM', 37), false);
AshitaCore = nil;   -- memory unavailable -> legacy fallback
check('B4 fallback: /NIN37 -> true', utils.isDualWieldAvailable('WAR', 75, 'NIN', 37), true);
check('B5 fallback: /WHM37 -> false', utils.isDualWieldAvailable('WAR', 75, 'WHM', 37), false);

-- ---------------------------------------------------------------------------
-- C. BuildDynamicSets -- equip-time: DW decides, the list's shield is the fallback.
--    Also locks the Main-before-Sub resolution order (pairs() order must not matter).
-- ---------------------------------------------------------------------------
TEST_PLAYER = { MainJob = 'WHM', SubJob = 'NIN', MainJobSync = 75, SubJobSync = 37 };

local function freshSets()
    return { Dynamic = { TP = {
        Sub  = { shield, sword1H },   -- Sub listed BEFORE Main on purpose (order lock)
        Main = { dagger1H },
    } } };
end

AshitaCore = ashitaWithDW(true);
local sDW = utils.BuildDynamicSets(freshSets());
check('C1 DW on: main resolves',   sDW.TP and sDW.TP.Main, 'Kris');
check('C2 DW on: weapon offhand',  sDW.TP and sDW.TP.Sub,  'Joyeuse');

AshitaCore = ashitaWithDW(false);
local sNo = utils.BuildDynamicSets(freshSets());
check('C3 no DW: shield fallback', sNo.TP and sNo.TP.Sub,  'GenbusShield');

-- catalog-vocabulary records resolve the same way (Type="Sub" shield fallback)
local function catSets()
    return { Dynamic = { WS = { Main = { catAxe1H }, Sub = { catShield, sword1H } } } };
end
AshitaCore = ashitaWithDW(false);
local sCat = utils.BuildDynamicSets(catSets());
check('C4 no DW: catalog shield fallback', sCat.WS and sCat.WS.Sub, 'Jennet Shield');
AshitaCore = ashitaWithDW(true);
sCat = utils.BuildDynamicSets(catSets());
check('C5 DW on: weapon beats catalog shield', sCat.WS and sCat.WS.Sub, 'Joyeuse');

-- ---------------------------------------------------------------------------
-- D. gearimport parser -- prune/fix/dedupe must see entries whose header line
--    carries a trailing "-- comment" (hand-annotated legacy entries). Field-
--    verified: 25 such entries in a real gear.lua were invisible to /dl prune.
-- ---------------------------------------------------------------------------
local gearimport = dofile('gear/gearimport.lua');
local fixtureGear = table.concat({
    'gear = {',
    '    Main = {',
    '        Sword = { -- category comment',
    '            CleanSword = {',
    '                Name = "Clean Sword",',
    '            },',
    '            NotedSword = { -- legacy note',
    '                Name = "Noted Sword",',
    '            },',
    '        },',
    '    },',
    '    Body = {',
    '        CleanBody = {',
    '            Name = "Clean Body",',
    '            Jobs = {"WAR", "THF"},',
    '        },',
    '        NotedBody = { -- Mtl. style/annotated',
    '            Name = "Noted Body",',
    '        }, -- trailing close comment',
    '    },',
    '};',
}, '\n');
-- empty owned list -> every entry the parser SEES must be reported for removal
local _, dRep, dTotal = gearimport.computePrune(fixtureGear, {});
check('D1 all 4 entries visible to prune', dTotal, 4);
local dSeen = {};
for _, r in ipairs(dRep) do dSeen[tostring(r.parent) .. '.' .. tostring(r.key)] = true; end
check('D2 comment-header weapon entry seen', dSeen['Main.Sword.NotedSword'], true);
check('D3 comment-header flat entry seen',   dSeen['Body.NotedBody'], true);
check('D4 owned name still kept', select(3, gearimport.computePrune(fixtureGear,
    { { Name = 'Noted Body' }, { Name = 'Clean Sword' }, { Name = 'Noted Sword' }, { Name = 'Clean Body' } })), 0);

-- ---------------------------------------------------------------------------
-- E. computeFixes metadata backfill -- the equip-time engine reads RAW gear.lua,
--    so /dl fix stamps Type / OneHanded from the catalog (weapons) and the
--    Shield/Grip label (Sub items). Must be idempotent.
-- ---------------------------------------------------------------------------
local eGear = table.concat({
    'gear = {',
    '    Main = {',
    '        Axe = {',
    '            Kriegsbeil = {',
    '                Name = "Kriegsbeil",',
    '                Level = 70,',
    '                Id = 17939,',
    '            },',
    '        },',
    '    },',
    '    Sub = {',
    '        JennetShield = {',
    '            Name = "Jennet Shield",',
    '            Level = 38,',
    '            Id = 12405,',
    '        },',
    '        AriesianGrip = {',
    '            Name = "Ariesian Grip",',
    '            Level = 60,',
    '            Id = 19042,',
    '        },',
    '    },',
    '};',
}, '\n');
local eMeta = {
    [17939] = { Type = 'Axe', OneHanded = true },
    [12405] = { Type = 'Sub' },
    [19042] = { Type = 'Sub' },
};
local eText, eRep = gearimport.computeFixes(eGear, {}, eMeta);
check('E1 weapon Type stamped',      eText:find('Type = "Axe"',     1, true) ~= nil, true);
check('E2 weapon OneHanded stamped', eText:find('OneHanded = true', 1, true) ~= nil, true);
check('E3 shield labeled Shield',    eText:find('Type = "Shield"',  1, true) ~= nil, true);
check('E4 grip labeled by name',     eText:find('Type = "Grip"',    1, true) ~= nil, true);
check('E5 result still parses',      (loadstring or load)(eText) ~= nil, true);
local _, eRep2 = gearimport.computeFixes(eText, {}, eMeta);
check('E6 idempotent second pass',   #eRep2.fixed, 0);

-- RSlot backfill: the reserved-slot fact reaches an EXISTING gear.lua only through
-- /dl fix (the engine has no catalog to look it up in). Any slot, not just weapons.
local e2Gear = table.concat({
    'gear = {',
    '    Body = {',
    '        RylFtmTunic = {',
    '            Name = "Ryl.Ftm. Tunic",',
    '            Level = 10,',
    '            Id = 13718,',
    '        },',
    '        CottonDoublet = {',
    '            Name = "Cotton Doublet",',
    '            Level = 9,',
    '            Id = 12588,',
    '        },',
    '    },',
    '};',
}, '\n');
local e2Meta = { [13718] = { Type = 'Body', RSlot = 16 }, [12588] = { Type = 'Body' } };
local e2Text, e2Rep = gearimport.computeFixes(e2Gear, {}, e2Meta);
check('E7 RSlot stamped on a reserving Body', e2Text:find('RSlot = 16', 1, true) ~= nil, true);
check('E8 non-reserving items stay thin',     select(2, e2Text:gsub('RSlot', '')), 1);
check('E9 result still parses',               (loadstring or load)(e2Text) ~= nil, true);
local _, e2Rep2 = gearimport.computeFixes(e2Text, {}, e2Meta);
check('E10 RSlot backfill is idempotent',     #e2Rep2.fixed, 0);
check('E11 the backfill is reported',
    e2Rep.fixed[1] ~= nil and e2Rep.fixed[1]:find('RSlot', 1, true) ~= nil, true);

-- RSlot retraction: the stamp is machine-owned both ways. A reservation the
-- record rule no longer asserts (the Automaton Oils' wrongly-completed Range
-- bit -- field case 2026-07-22: a manually equipped oil was displaced every
-- Default dispatch) must be REMOVED by the same machinery that stamped it; a
-- reservation whose catalog value changed is corrected in place. Genuine
-- reservations (Rimestone-class sticks, still completed) stay.
-- (do-block: keeps the main chunk under Lua's 200-local limit.)
do
local e3Gear = table.concat({
    'gear = {',
    '    Ammo = {',
    '        CanOfAutomatonOil_2 = {',
    '            Name = "Automat. Oil +2",',
    '            Level = 50,',
    '            Id = 18733,',
    '            RSlot = 4,',
    '        },',
    '        Rimestone = {',
    '            Name = "Rimestone",',
    '            Level = 60,',
    '            Id = 21384,',
    '            RSlot = 4,',
    '        },',
    '        PetFoodAlpha = {',
    '            Name = "Pet Food Alpha",',
    '            Level = 12,',
    '            Id = 17016,',
    '            RSlot = 8,',
    '        },',
    '    },',
    '};',
}, '\n');
local e3Meta = {
    [18733] = { Type = 'Ammo', Id = 18733 },              -- oil: completion now exempts it
    [21384] = { Type = 'Ammo', Id = 21384 },              -- stat stick: still completed to 4
    [17016] = { Type = 'Ammo', Id = 17016, RSlot = 4 },   -- catalog value changed: 8 -> 4
};
local e3Text, e3Rep = gearimport.computeFixes(e3Gear, {}, e3Meta);
check('E12 stale oil RSlot removed',       select(2, e3Text:gsub('RSlot', '')), 2);
check('E13 genuine reservation kept',      e3Text:find('Id = 21384,\n            RSlot = 4,', 1, true) ~= nil, true);
check('E14 changed value corrected',       e3Text:find('Id = 17016,\n            RSlot = 4,', 1, true) ~= nil, true);
check('E15 removal + correction reported', #e3Rep.fixed, 2);
check('E16 result still parses',           (loadstring or load)(e3Text) ~= nil, true);
local _, e3Rep2 = gearimport.computeFixes(e3Text, {}, e3Meta);
check('E17 retraction is idempotent',      #e3Rep2.fixed, 0);

-- H2H OneHanded: the catalog LIES true (apicrawl ONE-set bug, 2026-07-22) and
-- this backfill once propagated it -- computeFixes now rides the record rule
-- (gearrecord.healOneHanded): a missing flag backfills FALSE despite the
-- catalog, and a previously propagated true is corrected in place
-- (machine-owned both ways, the RSlot precedent above). do-block: the main
-- chunk sits at Lua's 200-local limit.
do
    local ehGear = table.concat({
        'gear = {',
        '    Main = {',
        '        HandToHand = {',
        '            BeatCesti = {',
        '                Name = "Beat Cesti",',
        '                Level = 40,',
        '                Id = 17478,',
        '            },',
        '            CatBaghnakhs = {',
        '                Name = "Cat Baghnakhs",',
        '                Level = 30,',
        '                Id = 17510,',
        '                Type = "Hand-to-Hand",',
        '                OneHanded = true,',
        '            },',
        '        },',
        '    },',
        '};',
    }, '\n');
    local ehMeta = {
        [17478] = { Type = 'HandToHand', OneHanded = true },   -- the catalog lie, verbatim
        [17510] = { Type = 'HandToHand', OneHanded = true },
    };
    local ehText, ehRep = gearimport.computeFixes(ehGear, {}, ehMeta);
    check('E18 H2H missing flag backfills FALSE despite the catalog lie',
          ehText:find('OneHanded = false', 1, true) ~= nil, true);
    check('E19 the propagated H2H lie is corrected in place',
          ehText:find('OneHanded = true', 1, true), nil);
    check('E20 H2H fix result still parses', (loadstring or load)(ehText) ~= nil, true);
    local _, ehRep2 = gearimport.computeFixes(ehText, {}, ehMeta);
    check('E21 H2H OneHanded fix idempotent', #ehRep2.fixed, 0);

    -- E22+. Range/Ammo Pair backfill (v128). EVERY gear.lua predates this field,
    -- and without it the engine sees a gun and a crossbow as the same
    -- "Marksmanship" -- so AutoAmmo can keep a bolt out of a bow but not out of a
    -- gun. Insert-only: a pair key is a fixed server fact, not a rule we derive.
    local epGear = table.concat({
        'gear = {',
        '    Range = {',
        '        Marksmanship = {',
        '            Hexagun = {',
        '                Name = "Hexagun",',
        '                Level = 65,',
        '                Id = 17222,',
        '                Type = "Marksmanship",',
        '            },',
        '            Crossbow = {',
        '                Name = "Crossbow",',
        '                Level = 12,',
        '                Id = 17217,',
        '                Type = "Marksmanship",',
        '                Pair = "26:0",',
        '            },',
        '        },',
        '    },',
        '};',
    }, '\n');
    local epMeta = {
        [17222] = { Type = 'Marksmanship', Pair = '26:1' },
        [17217] = { Type = 'Marksmanship', Pair = '26:0' },
    };
    local epText, epRep = gearimport.computeFixes(epGear, {}, epMeta);
    check('E22 a missing Pair is backfilled from the catalog',
          epText:find('Pair = "26:1"', 1, true) ~= nil, true);
    check('E23 an existing Pair is left alone (one insert, not two)', #epRep.fixed, 1);
    check('E24 Pair backfill result still parses', (loadstring or load)(epText) ~= nil, true);
    local _, epRep2 = gearimport.computeFixes(epText, {}, epMeta);
    check('E25 Pair backfill is idempotent', #epRep2.fixed, 0);
    -- The whitelist bug that shipped on v128 day: catalogindex.flatten builds
    -- records field-by-field, so a field missing there is silently absent
    -- everywhere downstream -- which is why AutoAmmo's "+ Add" stamped no pair.
    do
        local cx = require('dlac\\gear\\catalogindex');
        local flat = cx.flatten({ Ammo = {
            GoldBullet = { Name = 'Gold Bullet', Id = 12, Level = 40,
                           Type = 'Ammo', AmmoType = 'Marksmanship', Pair = '26:1' },
        } });
        check('E26 flatten carries Pair through to the panel records',
              flat[1] and flat[1].Pair, '26:1');
        check('E26b ...alongside the AmmoType it refines', flat[1] and flat[1].AmmoType, 'Marksmanship');
        -- Main/Range are normally nested by weapon category, but the skill-0 families
        -- (Animators, Soultrappers) have no category to nest under and are emitted
        -- FLAT at the slot level. apicrawl used to drop that bucket entirely, which
        -- deleted every Animator from the catalog -- and with it the Animator/oil
        -- pairing the server enforces. Pin BOTH depths so a tidy-up of either side
        -- cannot quietly lose them again.
        local mixed, mixedById = cx.flatten({ Range = {
            Marksmanship = { Hexagun = { Name = 'Hexagun', Id = 17222, Type = 'Marksmanship', Pair = '26:1' } },
            Animator = { Name = 'Animator', Id = 17859, Type = 'Range', Pair = '0:10' },
        } });
        check('E27 a categorised Range item still indexes', mixedById[17222] and mixedById[17222].Pair, '26:1');
        check('E27b an UNCATEGORISED Range item indexes too (the Animator case)',
              mixedById[17859] and mixedById[17859].Pair, '0:10');
        check('E27c ...and lands in the Range slot, not a category named after it',
              mixedById[17859] and mixedById[17859].Slot, 'Range');
        check('E27d both depths reach the flat list', #mixed, 2);
        -- The pairing these exist to express, through the real law.
        check('E28 Animator + Automaton Oil pair (0:10)',
              dispatchM.pairsWith('0:10', '0:10'), true);
        check('E28b Animator P II refuses the same oil (0:11 vs 0:10)',
              dispatchM.pairsWith('0:11', '0:10'), false);
    end
end
end

-- ---------------------------------------------------------------------------
-- F. setmanager shim analysis -- COMMENTED-OUT handlers ("-- profile.HandleX =
--    function()") are dead code: they must read as 'missing' (Setup creates
--    them), not 'unparsable' (Setup gave up with "no changes needed" while the
--    banner stayed red). Field case: Mindie's BLU.lua / COR.lua.
-- ---------------------------------------------------------------------------
local setmgr = dofile('gear/setmanager.lua');
local fProfile = table.concat({
    'local profile = {};',
    'local utils = require("dlac\\\\utils");',
    '',
    '-- profile.HandleAbility = function()',
    '--     local ability = gData.GetAction();',
    '--     if ability.Name == \'Release\' then return end',
    '-- end',
    '',
    'profile.HandleDefault = function()',
    '    sets = utils.rebuildSets(sets);',
    '    utils.dispatch(\'Default\');',
    'end',
    '',
    'profile.HandleItem        = function() utils.dispatch(\'Item\');        end',
    'profile.HandlePrecast     = function() utils.dispatch(\'Precast\');     end',
    'profile.HandleMidcast     = function() utils.dispatch(\'Midcast\');     end',
    'profile.HandlePreshot     = function() utils.dispatch(\'Preshot\');     end',
    'profile.HandleMidshot     = function() utils.dispatch(\'Midshot\');     end',
    'profile.HandleWeaponskill = function() utils.dispatch(\'Weaponskill\'); end',
    '',
    'return profile;',
}, '\n');
local fA = setmgr.analyzeShims(fProfile);
check('F1 commented handler is missing, not unparsable', fA.handlers.Ability, 'missing');
check('F2 live handlers still ok', fA.handlers.Item, 'ok');
local fText, fRep = setmgr.repairShimsText(fProfile);
check('F3 repair creates the commented-out handler', fRep.created[1], 'Ability');
check('F4 repair emits no warnings', #fRep.warnings, 0);
check('F5 repaired text parses', (loadstring or load)(fText) ~= nil, true);
check('F6 repaired profile is healthy', setmgr.analyzeShims(fText).healthy, true);

-- ---------------------------------------------------------------------------
-- G. mode-gated set entries -- an entry with `mode = '...'` participates only
--    while that mode is active, and then OUTRANKS unconditional entries; the
--    wrapper merge must never mutate the shared gear record.
-- ---------------------------------------------------------------------------
check('G1 modeActive cycle hit',    dispatchM.modeActive('Weapon:Melee', { weapon = 'Melee' }), true);
check('G2 modeActive cycle miss',   dispatchM.modeActive('Weapon:Melee', { weapon = 'Ranged' }), false);
check('G3 modeActive toggle on',    dispatchM.modeActive('DT', { dt = true }), true);
check('G4 modeActive toggle off',   dispatchM.modeActive('DT', {}), false);
check('G5 modeActive bare cycle',   dispatchM.modeActive('Weapon', { weapon = 'Ranged' }), true);

TEST_PLAYER = { MainJob = 'WHM', SubJob = 'NIN', MainJobSync = 75, SubJobSync = 37 };
AshitaCore = ashitaWithDW(false);

local plainBody = { Name = 'PlainBody', Level = 50, Type = 'Body' };
local modeBody  = { Name = 'ModeBody',  Level = 40, Type = 'Body' };   -- lower level on purpose
local lateBody  = { Name = 'LateBody',  Level = 10, Type = 'Body' };
local function gatedSets()
    return { Dynamic = { TP = {
        Body = { plainBody, { gear = modeBody, mode = 'Weapon:Melee' } },
    } } };
end

dispatchM.modes = {};
local gOff = utils.BuildDynamicSets(gatedSets());
check('G6 mode off: unconditional wins', gOff.TP and gOff.TP.Body, 'PlainBody');

dispatchM.modes = { weapon = 'Melee' };
local gOn = utils.BuildDynamicSets(gatedSets());
check('G7 mode on: gated entry beats higher-level unconditional', gOn.TP and gOn.TP.Body, 'ModeBody');

dispatchM.modes = { weapon = 'Ranged' };
local gOther = utils.BuildDynamicSets(gatedSets());
check('G8 other cycle value: gated entry excluded', gOther.TP and gOther.TP.Body, 'PlainBody');

dispatchM.modes = { dt = true };
local gTog = utils.BuildDynamicSets({ Dynamic = { TP = {
    Body = { plainBody, { gear = modeBody, mode = 'DT' } },
} } });
check('G9 toggle mode gates too', gTog.TP and gTog.TP.Body, 'ModeBody');
dispatchM.modes = {};

check('G10 wrapper merge does not mutate the shared record', modeBody.mode, nil);

-- mode LISTS are OR: active while ANY entry matches
check('G13 list: second entry matches', dispatchM.modeActive({ 'Weapon:Melee', 'DT' }, { dt = true }), true);
check('G14 list: cycle value matches',  dispatchM.modeActive({ 'Weapon:Melee', 'Weapon:Ranged' }, { weapon = 'Ranged' }), true);
check('G15 list: none match',           dispatchM.modeActive({ 'Weapon:Melee', 'DT' }, {}), false);

dispatchM.modes = { weapon = 'Ranged' };
local gList = utils.BuildDynamicSets({ Dynamic = { TP = {
    Body = { plainBody, { gear = modeBody, mode = { 'Weapon:Melee', 'Weapon:Ranged' } } },
} } });
check('G16 engine honours mode lists', gList.TP and gList.TP.Body, 'ModeBody');
dispatchM.modes = {};
check('G17 list wrapper does not mutate the shared record', modeBody.mode, nil);

-- rebuildSets must re-flatten on a MODE change (not only level/sub-job) --
-- the field bug: rotating a cycle left the flattened sets stale forever.
TEST_PLAYER = { MainJob = 'RDM', SubJob = 'WHM', MainJobSync = 75, SubJobSync = 37 };
dispatchM.modes = {};
local sets20 = { Dynamic = { TP = {
    Body = { plainBody, { gear = modeBody, mode = 'DT' } },
} } };
sets20 = utils.rebuildSets(sets20);
check('G20 initial flatten picks unconditional', sets20.TP and sets20.TP.Body, 'PlainBody');
dispatchM.setMode('DT', true);              -- bumps modesRev via saveModeState
sets20 = utils.rebuildSets(sets20);         -- same level/SJ: old code skipped this
check('G21 mode flip re-flattens via modesRev', sets20.TP and sets20.TP.Body, 'ModeBody');
dispatchM.setMode('DT', false);
sets20 = utils.rebuildSets(sets20);
check('G22 flip back re-flattens again', sets20.TP and sets20.TP.Body, 'PlainBody');

-- serializer writes both gate forms
local serLines = table.concat(setmgr.renderSetLines('T', {
    { name = 'Body', items = {
        { path = 'gear.Body.A', mode = 'DT' },
        { path = 'gear.Body.B', mode = { 'Weapon:Melee', 'Weapon:Ranged' } },
    } },
}), '\n');
check('G18 serializes single gate',  serLines:find('mode = "DT"', 1, true) ~= nil, true);
check('G19 serializes gate list',    serLines:find('mode = { "Weapon:Melee", "Weapon:Ranged" }', 1, true) ~= nil, true);

-- min/maxLevel bounds through the same wrapper (the ffxi-lac semantics)
TEST_PLAYER = { MainJob = 'WHM', SubJob = 'NIN', MainJobSync = 50, SubJobSync = 25 };
local gMin = utils.BuildDynamicSets({ Dynamic = { TP = {
    Body = { { gear = lateBody, minLevel = 60 }, { gear = plainBody, maxLevel = 55 } },
} } });
check('G11 minLevel bound excludes below', gMin.TP and gMin.TP.Body, 'PlainBody');
TEST_PLAYER = { MainJob = 'WHM', SubJob = 'NIN', MainJobSync = 60, SubJobSync = 30 };
local gMax = utils.BuildDynamicSets({ Dynamic = { TP = {
    Body = { { gear = lateBody, minLevel = 60 }, { gear = plainBody, maxLevel = 55 } },
} } });
check('G12 past maxLevel: banded item takes over', gMax.TP and gMax.TP.Body, 'LateBody');

-- ---------------------------------------------------------------------------
-- H. set-level optimization under caps (gearoptim.optimizePicks) -- greedy
--    per-slot picking overspends capped stats; the optimizer must give cap
--    budget to the piece that brings the most ALONGSIDE it, prefer EMPTY on
--    ties, and respect paired-slot conflicts.
-- ---------------------------------------------------------------------------
local optim = dofile('gear/gearoptim.lua');
local W = {
    Haste      = { perUnit = 100, cap = 5 },
    SwordSkill = { perUnit = 2 },
    Accuracy   = { perUnit = 3 },
};
-- Henrik's field case: a haste-only head wins per-item, but the feet already
-- cap haste AND bring skill/acc -- the head must yield to the accuracy hat.
local hasteHat  = { stats = { Haste = 5 },                                ref = 'HasteHat'  };
local statHat   = { stats = { Accuracy = 5 },                             ref = 'StatHat'   };
local greatFeet = { stats = { Haste = 5, SwordSkill = 7, Accuracy = 5 },  ref = 'GreatFeet' };
local weakFeet  = { stats = { Accuracy = 2 },                             ref = 'WeakFeet'  };
local h1 = optim.optimizePicks({ Head = { hasteHat, statHat }, Feet = { greatFeet, weakFeet } }, W);
check('H1 feet take the cap with company', h1.picks.Feet ~= nil and 'GreatFeet',
      h1.picks.Feet ~= nil and ({ greatFeet, weakFeet })[h1.picks.Feet].ref);
check('H2 head yields the cap to real value', h1.picks.Head ~= nil and ({ hasteHat, statHat })[h1.picks.Head].ref, 'StatHat');
check('H3 capped set total', h1.total, 100 * 5 + 2 * 7 + 3 * (5 + 5));

-- empty preferred: a slot with only unweighted (or cap-redundant) gear stays home
local junk = { stats = { VIT = 9 }, ref = 'Junk' };
local h2 = optim.optimizePicks({ Head = { junk }, Feet = { greatFeet } }, W);
check('H4 unweighted slot stays empty', h2.picks.Head, nil);
local h3 = optim.optimizePicks({ Head = { hasteHat }, Feet = { greatFeet } }, W);
check('H5 cap-redundant slot stays empty', h3.picks.Head, nil);

-- paired-slot conflict: one physical copy cannot fill both rings
local ring = { stats = { Accuracy = 5 }, ref = 'OnlyRing' };
local h4 = optim.optimizePicks({ Ring1 = { ring }, Ring2 = { ring } }, W,
    { conflict = function(a, b) return a == b; end });
local filled = 0;
if h4.picks.Ring1 ~= nil then filled = filled + 1; end
if h4.picks.Ring2 ~= nil then filled = filled + 1; end
check('H6 one copy fills only one paired slot', filled, 1);

-- same-NAME duplicates (legacy gear.lua double entries) are ONE physical item:
-- the name-aware conflict must keep them out of both paired slots (the field
-- bug: two Jalzahn's Rings suggested from one owned ring)
local dupA = { stats = { Accuracy = 6 }, ref = { Name = "Jalzahn's Ring", Id = 901 } };
local dupB = { stats = { Accuracy = 6 }, ref = { Name = "Jalzahn's Ring" } };        -- legacy: no Id
local h4b = optim.optimizePicks({ Ring1 = { dupA }, Ring2 = { dupB } },
    { Accuracy = { perUnit = 3 } },
    { conflict = function(a, b)
        return a == b or (a.Id ~= nil and a.Id == b.Id)
            or string.lower(tostring(a.Name or '?')) == string.lower(tostring(b.Name or '??'));
    end });
local dupFilled = 0;
if h4b.picks.Ring1 ~= nil then dupFilled = dupFilled + 1; end
if h4b.picks.Ring2 ~= nil then dupFilled = dupFilled + 1; end
check('H6b same-name duplicate fills only one slot', dupFilled, 1);

-- baseStats background: an already-chosen set consumes the cap
local h5 = optim.optimizePicks({ Head = { hasteHat } }, W, { baseStats = { { Haste = 5 } } });
check('H7 background consumes the cap', h5.picks.Head, nil);

-- negative-good stats still score as goodness under caps
local WD = { DT = { perUnit = 10, cap = 10 } };
local dtA = { stats = { DT = -8 }, ref = 'A' };
local dtB = { stats = { DT = -8 }, ref = 'B' };
local h6 = optim.optimizePicks({ Body = { dtA }, Legs = { dtB } }, WD);
check('H8 DT capped as goodness', h6.total, 10 * 10);

-- ---------------------------------------------------------------------------
-- H9-H14. Range/Ammo are picked TOGETHER, never greedily per slot.
-- Field case (Henrik): Cinderstone / Morion Tathlum occupy the Ammo slot but can
-- be fired by nothing. The server adds the ammo's delay to ranged delay for TP
-- with no compatibility check (GetRangedWeaponDelay), so pairing one with a bow
-- silently costs its full 999. Ammo with no corresponding Range weapon -- unfirable,
-- Throwing (a Range weapon shadows it), or no owned weapon of its type -- must
-- leave Range EMPTY. Catalog AmmoType is the discriminator; absent = unfirable.
-- ---------------------------------------------------------------------------
do   -- scoped: the main chunk is near Lua's 200-local ceiling
local G = package.loaded['dlac\\gear'];
local function ammoSet(rangeTbl, ammoTbl)
    G.Range, G.Ammo = rangeTbl, ammoTbl;
    return optim.buildMaxStatSet('Accuracy', { job = 'WAR', level = 99 });
end
local function it(name, acc, extra)
    local e = { Name = name, Level = 1, Id = 0, Jobs = { 'All' }, Stats = { Accuracy = acc } };
    for k, v in pairs(extra or {}) do e[k] = v; end
    return e;
end
-- a bow that scores WELL and a stat stick that scores a little: greedy would take both
local bow   = it('Test Bow',    10, { Type = 'Archery' });
local arrow = it('Test Arrow',   1, { AmmoType = 'Archery' });
local stick = it('Cinderstone',  4);                              -- no AmmoType = unfirable

local r1 = ammoSet({ Archery = { bow } }, { stick = stick, arrow = arrow });
check('H9 bow keeps its matching ammo',      r1.slots.Ammo, 'Test Arrow');
check('H10 bow survives the pairing',        r1.slots.Range, 'Test Bow');

-- stat stick outscores the whole bow+arrow pair (4+10=14 vs 20) -> Range must empty out
local fatStick = it('Cinderstone', 20);
local r2 = ammoSet({ Archery = { bow } }, { stick = fatStick });
check('H11 unfirable ammo wins the pair',    r2.slots.Ammo, 'Cinderstone');
check('H12 ... and Range stays EMPTY',       r2.slots.Range, nil);

-- Throwing fires from the Ammo slot itself; any Range weapon shadows it
local shuriken = it('Test Shuriken', 20, { AmmoType = 'Throwing' });
local r3 = ammoSet({ Archery = { bow } }, { shuriken = shuriken });
check('H13 Throwing ammo empties Range',     r3.slots.Range, nil);

-- arrows whose bow is not owned: no corresponding Range weapon -> Range stays empty
local r4 = ammoSet({ Marksmanship = { it('Test Gun', 3, { Type = 'Marksmanship' }) } }, { arrow = it('Test Arrow', 20, { AmmoType = 'Archery' }) });
check('H14 ammo without its weapon empties Range', r4.slots.Range, nil);
G.Range, G.Ammo = nil, nil;
end

-- ---------------------------------------------------------------------------
-- I. max-MP hold rule (dispatch.mpHoldNeeded) -- keep a worn MP piece while
--    swapping it out would waste unspent MP; release once it's spent.
--    Field spec: +50 MP head vs +5 MP incoming -> release after 45 MP spent.
-- ---------------------------------------------------------------------------
check('I1 full pool holds',           dispatchM.mpHoldNeeded(50, 5, 1000, 1000), true);
check('I2 one MP unspent still holds', dispatchM.mpHoldNeeded(50, 5, 956, 1000), true);
-- >= boundary on purpose: a battery equipped at a FULL pool sits exactly here
-- (cur == newMax - delta); releasing would drop it before any recovery landed
check('I3 exact boundary still holds', dispatchM.mpHoldNeeded(50, 5, 955, 1000), true);
check('I3b spent past the surplus releases', dispatchM.mpHoldNeeded(50, 5, 954, 1000), false);
check('I4 well spent releases',       dispatchM.mpHoldNeeded(50, 5, 700, 1000), false);
check('I5 incoming has more MP: never hold', dispatchM.mpHoldNeeded(5, 50, 1000, 1000), false);
check('I6 equal MP: never hold',      dispatchM.mpHoldNeeded(30, 30, 1000, 1000), false);
check('I7 nil-safe',                  dispatchM.mpHoldNeeded(nil, nil, nil, nil), false);

-- ---------------------------------------------------------------------------
-- J. THE central equip-eligibility rule (dispatch.jobCanEquip / canWear):
--    main job only (sub NEVER widens -- field-verified), level gated on main.
--    gearui, gearoptim and the automation manifests all delegate here.
-- ---------------------------------------------------------------------------
check('J1 no restriction wears',   dispatchM.jobCanEquip(nil, 'RDM'), true);
check('J2 All wears',              dispatchM.jobCanEquip({ 'All' }, 'RDM'), true);
check('J3 main job listed wears',  dispatchM.jobCanEquip({ 'WHM', 'RDM' }, 'RDM'), true);
check('J4 other job never wears',  dispatchM.jobCanEquip({ 'WHM' }, 'RDM'), false);
check('J5 canWear level gate',     dispatchM.canWear({ Jobs = { 'RDM' }, Level = 74 }, 'RDM', 73), false);
check('J6 canWear at level',       dispatchM.canWear({ Jobs = { 'RDM' }, Level = 74 }, 'RDM', 74), true);
check('J7 canWear wrong job',      dispatchM.canWear({ Jobs = { 'WHM' }, Level = 10 }, 'RDM', 75), false);

-- ---------------------------------------------------------------------------
-- K. max-MP battery pick (dispatch.mpPick): the manifest carries a LADDER per
--    slot (best first, may include gear to grow into); the engine wears the
--    best rung wearable at the LIVE level. Field case: Bunzi's Robe (99) in
--    rung 1 must not block a level-74 RDM from the level-59 rung below it.
-- ---------------------------------------------------------------------------
local ladder = { { name = 'Bunzi\'s Robe', mp = 50, level = 99 },
                 { name = 'Vermillion Cloak', mp = 30, level = 59 },
                 { name = 'Baron\'s Saio', mp = 10, level = 20 } };
check('K1 top rung at level',      dispatchM.mpPick(ladder, 99).name, 'Bunzi\'s Robe');
check('K2 fallback below level',   dispatchM.mpPick(ladder, 74).name, 'Vermillion Cloak');
check('K3 deep fallback',          dispatchM.mpPick(ladder, 30).name, 'Baron\'s Saio');
check('K4 nothing wearable',       dispatchM.mpPick(ladder, 10), nil);
check('K5 legacy single entry',    dispatchM.mpPick({ name = 'Astral Ring', mp = 25, level = 10 }, 74).name, 'Astral Ring');
check('K6 legacy entry too high',  dispatchM.mpPick({ name = 'X', mp = 1, level = 99 }, 74), nil);
check('K7 nil-safe',               dispatchM.mpPick(nil, 74), nil);

-- ---------------------------------------------------------------------------
-- MS. staged battery movement (dispatch.mpStageRelease / mpStageEquip, engine
--     v76): at most ONE battery moves per dispatch. Release picks the SMALLEST
--     surplus (the big battery stays on longest; simultaneous releases were
--     the clamp bug -- N same-dispatch releases drop max MP by the SUM of
--     surpluses while each hold justified only its own). Equip picks the
--     BIGGEST gain. Both tie-break on the slot name so pairs() collection
--     order can never flip the pick.
-- ---------------------------------------------------------------------------
(function()
local relCands = { { slot = 'Body', surplus = 29 },
                   { slot = 'Ring1', surplus = 10 },
                   { slot = 'Head', surplus = 45 } };
check('MS1 release picks the smallest surplus', dispatchM.mpStageRelease(relCands).slot, 'Ring1');
check('MS2 release tie breaks on slot name',
    dispatchM.mpStageRelease({ { slot = 'Ring2', surplus = 10 }, { slot = 'Ring1', surplus = 10 } }).slot, 'Ring1');
check('MS3 single candidate wins',  dispatchM.mpStageRelease({ { slot = 'Neck', surplus = 5 } }).slot, 'Neck');
check('MS4 release empty -> none',  dispatchM.mpStageRelease({}), nil);
check('MS5 release nil-safe',       dispatchM.mpStageRelease(nil), nil);
local upCands = { { slot = 'Ring1', gain = 25 },
                  { slot = 'Body', gain = 50 },
                  { slot = 'Neck', gain = 5 } };
check('MS6 equip picks the biggest gain', dispatchM.mpStageEquip(upCands).slot, 'Body');
check('MS7 equip tie breaks on slot name',
    dispatchM.mpStageEquip({ { slot = 'Ear2', gain = 25 }, { slot = 'Ear1', gain = 25 } }).slot, 'Ear1');
check('MS8 equip nil-safe',         dispatchM.mpStageEquip(nil), nil);

-- v78 scope ruling: a battery whose RSlot reserves an OCCUPIED slot never
-- stages (it would shove the planned/worn piece off server-side) -- and
-- filtering it here keeps the one-per-dispatch stage from being starved by a
-- doomed biggest-gain pick.
local msOcc = function(ls) return ({ range = 'Rouser' })[ls]; end
local msRs  = function(n) return ({ Rimestone = 4 })[n]; end
local msKeep, msSkip = dispatchM.mpStageEligible(
    { { slot = 'Ammo', lslot = 'ammo', name = 'Rimestone', gain = 20 },
      { slot = 'Ring1', lslot = 'ring1', name = 'Astral Ring', gain = 15 } }, msOcc, msRs);
check('MS9 Range-reserving battery skipped when Range occupied', #msKeep, 1);
check('MS9b the survivor is the ring',           msKeep[1].name, 'Astral Ring');
check('MS9c skip reports the blocking slot',     msSkip[1].blocking, 'range');
check('MS10 free Range: the battery stages',
    #(dispatchM.mpStageEligible({ { slot = 'Ammo', lslot = 'ammo', name = 'Rimestone', gain = 20 } },
        function() return nil; end, msRs)), 1);
check('MS10b Range=remove counts as free',
    #(dispatchM.mpStageEligible({ { slot = 'Ammo', lslot = 'ammo', name = 'Rimestone', gain = 20 } },
        function(ls) return ({ range = 'remove' })[ls]; end, msRs)), 1);
check('MS10c nil-safe', dispatchM.mpStageEligible(nil, msOcc, msRs), nil);
end)();

-- ---------------------------------------------------------------------------
-- MPL. /dl plan v2 formatter (dispatch.mpPlanLines, engine v88) -- renders
--      the band context: rows in RELEASE order with off<=/on>= thresholds,
--      refresh tag, live state (ON worn / ON equipping / RELEASING / off /
--      holding); a missing context answers the self-heal hint.
-- ---------------------------------------------------------------------------
(function()
local mb = dofile('feature/mpbands.lua');
local bands = mb.build({
    { slot = 'feet', name = 'MP Boots', low = 5, high = 15 },
    { slot = 'body', name = 'Refresh Robe', low = 0, high = 30, refresh = true },
}, 1100, 15);
-- cur 1050: feet (off<=1075) is past its off threshold -> releasing/off;
-- body (refresh band: off<=1045, on>=1060 clamped) sits in its DEAD ZONE
-- -> holding.
local worn = function(sl) if sl == 'body' then return 'Refresh Robe'; end return nil; end
local mpCtx = {
    bands = bands, cur = 1050, total = 1100, tick = 15, resting = false,
    target = mb.target(bands, 1050, worn),
    hi = {}, mpMap = {},
};
local lines = dispatchM.mpPlanLines(mpCtx, worn);
check('MPL1 header carries cur/total/tick',
    string.find(lines[1], 'MP 1050 of 1100', 1, true) ~= nil
    and string.find(lines[1], 'tick 15', 1, true) ~= nil, true);
check('MPL2 release order: small diff row first',
    string.find(lines[2], '1. feet:', 1, true) ~= nil, true);
check('MPL2b refresh band sinks deep + tagged',
    string.find(lines[3], '2. body:', 1, true) ~= nil
    and string.find(lines[3], '[refresh]', 1, true) ~= nil, true);
check('MPL3 thresholds printed (worked example)',
    string.find(lines[2], 'off<=1075', 1, true) ~= nil
    and string.find(lines[2], 'on>=1085', 1, true) ~= nil, true);
check('MPL4 dead-zone worn battery reads holding',
    string.find(lines[3], 'holding', 1, true) ~= nil, true);
check('MPL5 dead-zone empty slot reads off',
    string.find(lines[2], '-- off', 1, true) ~= nil, true);
check('MPL6 no context -> self-heal hint',
    string.find(dispatchM.mpPlanLines(nil)[1], 'no battery data', 1, true) ~= nil, true);
end)();

-- ---------------------------------------------------------------------------
-- MPS. paired-slot veto (dispatch.mpPairSkip, engine v83) -- a battery worn
--      in the SIBLING ear/ring is the same physical item (equipping it here
--      would shuffle it across and leave a hole; field: Loquacious Earring
--      hopped ear2 -> ear1 on rest). Duplicates are exempt: the manifest
--      lists dup-owned items in BOTH paired ladders, so a sibling ladder
--      naming the item means a second copy exists.
-- ---------------------------------------------------------------------------
(function()
local sibLad = { { name = 'Outlaw\'s Earring', mp = 15, level = 60 },
                 { name = 'Morion Earring', mp = 4, level = 16 } };
check('MPS1 single copy worn in sibling -> veto',
    dispatchM.mpPairSkip('Loquac. Earring', 'Loquac. Earring', sibLad), true);
check('MPS2 case-insensitive match still vetoes',
    dispatchM.mpPairSkip('Loquac. Earring', 'loquac. earring', sibLad), true);
check('MPS3 dup-owned (sibling ladder lists it) -> allowed',
    dispatchM.mpPairSkip('Astral Ring', 'Astral Ring',
        { { name = 'Astral Ring', mp = 25, level = 10 } }), false);
check('MPS4 different item worn in sibling -> allowed',
    dispatchM.mpPairSkip('Loquac. Earring', 'Outlaw\'s Earring', sibLad), false);
check('MPS5 empty sibling slot -> allowed',
    dispatchM.mpPairSkip('Loquac. Earring', nil, sibLad), false);
check('MPS6 legacy single-entry sibling ladder shape',
    dispatchM.mpPairSkip('Astral Ring', 'Astral Ring',
        { name = 'Astral Ring', mp = 25, level = 10 }), false);
check('MPS7 nil ladder: worn in sibling still vetoes',
    dispatchM.mpPairSkip('Loquac. Earring', 'Loquac. Earring', nil), true);

-- MPS8+: THE shared battery resolver (dispatch.mpBestPick, engine v88) --
-- the engine, the band builder and /dl plan all pick through it, and it
-- applies the pair veto while walking the ladder (field: the plan once
-- advertised a +20 ear1 gain the engine would never equip).
local pBest = {
    ear1 = { { name = 'Loquac. Earring', mp = 30, level = 41 },
             { name = 'Curate\'s Earring', mp = 10, level = 21 } },
    ear2 = { { name = 'Outlaw\'s Earring', mp = 15, level = 60 } },
    ring1 = { { name = 'Astral Ring', mp = 25, level = 10 } },
    ring2 = { { name = 'Astral Ring', mp = 25, level = 10 } },
};
local pworn = function(l)
    if l == 'ear2' then return 'Loquac. Earring'; end
    if l == 'ring1' then return 'Astral Ring'; end
    return nil;
end
check('MPS8 pick falls past the vetoed rung',
    dispatchM.mpBestPick(pBest, 'ear1', 75, pworn).name, 'Curate\'s Earring');
check('MPS8b level gate still applies',
    dispatchM.mpBestPick(pBest, 'ear1', 20, pworn), nil);
-- ---------------------------------------------------------------------------
-- MR. max-MP reconciliation (dispatch.mpReconcileMax, engine v86): Ashita's
--     GetMPMax can go stale across gear/job churn (field: engine 975/1052 vs
--     bar 975/975 -- dead full-pool gate + early releases). The party MP%
--     (floored, same packet family as cur) pins true max in
--     [cur*100/(mpp+1), cur*100/mpp]; 100% pins it exactly.
-- ---------------------------------------------------------------------------
check('MR1 field pin: 100% pins max = cur', dispatchM.mpReconcileMax(975, 1052, 100), 975);
-- v87 LOW bias: below full GetMPMax is ignored outright -- an under-estimate
-- can only over-hold a battery, never dump it early (round 7's cascade).
check('MR2 below full: GetMPMax ignored, low edge wins', dispatchM.mpReconcileMax(975, 1000, 97), 995);
check('MR3 stale-high ignored the same way', dispatchM.mpReconcileMax(500, 1200, 50), 981);
check('MR4 stale-low ignored the same way',  dispatchM.mpReconcileMax(500, 700, 50), 981);
check('MR5 nil mpp: raw max unchanged',     dispatchM.mpReconcileMax(975, 1052, nil), 1052);
check('MR6 empty pool: raw max unchanged',  dispatchM.mpReconcileMax(0, 714, 0), 714);
check('MR7 nil max at 100% still pins',     dispatchM.mpReconcileMax(975, nil, 100), 975);
check('MR8 nil max mid-pool takes lo',      dispatchM.mpReconcileMax(500, nil, 50), 981);

-- MF. the exact full-pool signal (dispatch.mpPoolFull, v87): floored MP%
--     reads 100 ONLY at cur == max; cur >= max survives as the fallback when
--     the percent is unreadable (its stale-low false-full armed round 7).
check('MF1 100% = full',                    dispatchM.mpPoolFull(975, 975, 100), true);
check('MF2 99% never full (fresh battery)', dispatchM.mpPoolFull(975, 975, 99), false);
check('MF3 no percent: cur >= max fallback', dispatchM.mpPoolFull(975, 975, nil), true);
check('MF3b no percent, below max',         dispatchM.mpPoolFull(975, 1052, nil), false);
check('MF4 nil-safe',                       dispatchM.mpPoolFull(nil, nil, nil), false);

check('MPS8c dup-owned pick survives the veto',
    dispatchM.mpBestPick(pBest, 'ring2', 75, pworn).name, 'Astral Ring');
check('MPS8d nil-safe', dispatchM.mpBestPick(nil, 'ear1', 75, pworn), nil);

-- MSS. STICKY paired slots (dispatch.mpStickyPairs, engine v93): a battery
--      candidate whose piece the sibling ear/ring already claims -- in this
--      dispatch's PLAN or on the body -- never writes (field: Loquacious
--      bounced ear2 <-> ear1 between the set's plan and the band's ladder
--      home). Dup-owned items stay exempt (both paired ladders list them).
local claims = function(map) return function(ls) return map[ls]; end end
local kept, moved = dispatchM.mpStickyPairs(
    { { slot = 'Ear1', lslot = 'ear1', name = 'Loquac. Earring', gain = 20 },
      { slot = 'Neck', lslot = 'neck', name = 'Warloq\'s Locket', gain = 31 } },
    claims({ ear2 = 'Loquac. Earring' }), pBest);
check('MSS1 sibling-claimed piece never writes', #kept, 1);
check('MSS1b the survivor is the unpaired slot', kept[1].lslot, 'neck');
check('MSS1c the skip names the claim', moved[1].sib .. '/' .. moved[1].claimed,
    'ear2/Loquac. Earring');
check('MSS2 dup-owned pair still writes',
    #(dispatchM.mpStickyPairs(
        { { slot = 'Ring2', lslot = 'ring2', name = 'Astral Ring', gain = 25 } },
        claims({ ring1 = 'Astral Ring' }), pBest)), 1);
check('MSS3 unclaimed sibling: candidate passes',
    #(dispatchM.mpStickyPairs(
        { { slot = 'Ear1', lslot = 'ear1', name = 'Loquac. Earring', gain = 20 } },
        claims({ ear2 = 'Outlaw\'s Earring' }), pBest)), 1);
check('MSS4 nil-safe', #(dispatchM.mpStickyPairs(nil, nil, nil)), 0);
-- v94, the field hole: the sibling's PLAN names a different piece (the set
-- displacing the earring) while the WORN claim still holds it -- either
-- claim vetoes now; `plan or worn` used to shadow the worn signal.
check('MSS5 worn claim vetoes even when the plan differs',
    #(dispatchM.mpStickyPairs(
        { { slot = 'Ear1', lslot = 'ear1', name = 'Loquac. Earring', gain = 20 } },
        function(ls)
            if ls == 'ear2' then return 'Outlaw\'s Earring', 'Loquac. Earring'; end
        end, pBest)), 0);
end)();

-- ---------------------------------------------------------------------------
-- MB. the banded-ladder core (feature/mpbands.lua, maxmp v2 -- Henrik's
--     2026-07-21 design). Thresholds are precomputed absolute current-MP
--     numbers; current MP is the ONLY live input. MB1/MB5/MB6 pin Henrik's
--     worked example VERBATIM: total 1100, feet low 5 / high 15 (diff 10),
--     tick 15 -> unequip at 1075, re-equip at 1085.
-- ---------------------------------------------------------------------------
(function()
local mb = dofile('feature/mpbands.lua');
package.loaded['dlac\\feature\\mpbands'] = mb;

local ex = mb.build({ { slot = 'feet', name = 'MP Boots', low = 5, high = 15 } }, 1100, 15);
check('MB1 worked example: one band',      #ex, 1);
check('MB1b lastMax = total',              ex[1].lastMax, 1100);
check('MB1c endMax = total - diff',        ex[1].endMax, 1090);
check('MB1d unequip trigger (Henrik: 1075)', ex[1].offAt, 1075);
check('MB1e re-equip trigger (Henrik: 1085)', ex[1].onAt, 1085);

local three = mb.build({
    { slot = 'neck', name = 'Locket', low = 0, high = 45 },
    { slot = 'feet', name = 'Boots',  low = 5, high = 15 },
    { slot = 'ring', name = 'Ring',   low = 0, high = 25 },
}, 1100, 15);
check('MB2 smallest diff first',   three[1].slot .. '>' .. three[2].slot .. '>' .. three[3].slot, 'feet>ring>neck');
check('MB2b bands chain: lastMax', three[2].lastMax, 1090);
check('MB2c bands chain: deepest', three[3].endMax, 1020);
check('MB3 non-positive diff gets no band',
    #(mb.build({ { slot = 'body', low = 50, high = 50 }, { slot = 'head', low = 30, high = 20 } }, 1100, 15)), 0);
check('MB3b nil-safe build', #(mb.build(nil, nil, nil)), 0);

local wearing = function(name) return function() return name; end end
check('MB4 above onAt: the rung belongs on', mb.target(ex, 1085, wearing(nil)).feet, 'MP Boots');
check('MB5 at/below offAt: set piece belongs on', mb.target(ex, 1075, wearing('MP Boots')).feet, false);
check('MB6 dead zone keeps worn rung',  mb.target(ex, 1080, wearing('MP Boots')).feet, 'MP Boots');
check('MB6b dead zone keeps empty slot empty', mb.target(ex, 1080, wearing(nil)).feet, false);
check('MB7 unreadable cur keeps state', mb.target(ex, nil, wearing('MP Boots')).feet, 'MP Boots');
local plunge = mb.target(three, 900, wearing('x'));   -- big spell: BATCH release
check('MB8 batch release on a big drop', tostring(plunge.feet) .. ',' .. tostring(plunge.ring) .. ',' .. tostring(plunge.neck),
    'false,false,false');
local surge = mb.target(three, 1100, wearing(nil));  -- Sublimation pop: BATCH equip
check('MB8b batch equip on a big rise', tostring(surge.feet) .. ',' .. tostring(surge.ring) .. ',' .. tostring(surge.neck),
    'Boots,Ring,Locket');

mb.reset();
check('MB9 unmeasured tick = default', mb.tick(false), mb.DEFAULT_TICK);
mb.observe(900, false); mb.observe(912, false); mb.observe(912, false); mb.observe(927, false); mb.observe(939, false);
check('MB10 standing tick = median of rises', mb.tick(false), 12);
mb.observe(600, false);            -- a spell DROP is not a tick
mb.observe(1000, false);           -- a +400 zone/item jump is not a tick
check('MB10b drops and jumps ignored', mb.tick(false), 12);
mb.observe(500, true); mb.observe(535, true);
check('MB11 resting bucket separate', mb.tick(true), 35);
mb.reset();
mb.observe(900, false); mb.observe(910, false);
check('MB11b resting falls back to standing measure', mb.tick(true), 10);
mb.reset();
mb.observe(900, false); mb.observe(901, false); mb.observe(902, false);
check('MB11c margin floors at MIN_TICK (unbuffed +1 ticks are real but tiny)',
    mb.tick(false), mb.MIN_TICK);

-- MB12: the SIGNED refresh delta ("mp recovery is key", engine v89). Field
-- pin: Bunzi's Robe (flat 50 MP) over Cleric's Bliaut +1 (Refresh 2 with
-- augments) = rfDelta -2 -> that band floats SHALLOWEST (first out, last
-- back) even with the biggest diff, so the refresh piece stays worn through
-- the spend; a refresh-GAIN battery still sinks deepest.
local signed = mb.build({
    { slot = 'body', name = 'Bunzi\'s Robe',  low = 29, high = 50, rfDelta = -2 },
    { slot = 'feet', name = 'Boots',          low = 5,  high = 15 },
    { slot = 'neck', name = 'Refresh Torque', low = 0,  high = 10, rfDelta = 1 },
}, 1100, 15);
check('MB12 refresh-cost floats shallowest',  signed[1].slot, 'body');
check('MB12b plain diff order in the middle', signed[2].slot, 'feet');
check('MB12c refresh-gain sinks deepest',     signed[3].slot, 'neck');
check('MB12d legacy refresh=true alias sinks deep',
    mb.build({ { slot = 'a', low = 0, high = 10, refresh = true },
               { slot = 'b', low = 0, high = 5 } }, 100, 0)[2].slot, 'a');

-- MB13: ONE band per slot, the round-10 RULING: "to get refresh in is NOT
-- YOUR JOB -- that is the idle set's job... you should be aware there is a
-- potential refresh piece there and adapt accordingly." The engine's band
-- = the top battery (augs counted: Hlr. Bliaut +1 at 35+18=53 tops body)
-- vs the POTENCY POINT = the idle's own piece (Clr. Bliaut +1 rf2 body,
-- Bunzi's Hat rf1 head). Awareness = ordering only: the refresh-cost
-- bands float shallowest, so the idle's refresh pieces are back FIRST
-- (body then head) and displaced LAST.
local multi = mb.build({
    { slot = 'head', low = 25, lowRf = 1,   -- idle wears Bunzi's Hat (its job, not ours)
      rungs = { { name = 'Erudite Cap', mp = 30, rf = 0 },
                { name = 'Bunzi\'s Hat', mp = 25, rf = 1 } } },
    { slot = 'body', low = 31, lowRf = 2,   -- idle wears Clr. Bliaut +1
      rungs = { { name = 'Hlr. Bliaut +1', mp = 53, rf = 0 },
                { name = 'Bunzi\'s Robe', mp = 50, rf = 0 } } },
    { slot = 'feet', low = 5, lowRf = 0,
      rungs = { { name = 'Boots', mp = 15, rf = 0 } } },
}, 1100, 15);
local order = {};
for _, b in ipairs(multi) do order[#order + 1] = b.name; end
check('MB13 one band per slot, refresh-cost shallowest', table.concat(order, '>'),
    'Hlr. Bliaut +1>Erudite Cap>Boots');
check('MB13b the engine never wears the refresh piece (no Hat/Clr band)',
    (function()
        for _, b in ipairs(multi) do
            if b.name == 'Bunzi\'s Hat' or b.name == 'Clr. Bliaut +1' then return 'worn by engine'; end
        end
        return 'idle set\'s job';
    end)(), 'idle set\'s job');
-- REACHABILITY (the round-10 field bug: "not switching away the refresh
-- pieces even at max MP"): body diff 22 > tick 15, so the raw on-trigger
-- (lastMax - tick = 1085) sits ABOVE the reachable pool (endMax 1078) --
-- clamped to endMax it fires the moment the pool genuinely tops out.
check('MB13c big-diff on-trigger clamps reachable', multi[1].onAt, multi[1].endMax);
check('MB13d small-diff keeps the early trigger (worked example intact)',
    mb.build({ { slot = 'feet', low = 5, lowRf = 0,
        rungs = { { name = 'MP Boots', mp = 15, rf = 0 } } } }, 1100, 15)[1].onAt, 1085);
-- At the top the battery displaces the refresh set piece; spending brings
-- the refresh piece back FIRST (body band shallowest).
local wornTop = function(sl)
    if sl == 'body' then return 'Hlr. Bliaut +1'; end
    if sl == 'head' then return 'Erudite Cap'; end
    return nil;
end
check('MB13e at the top: the battery belongs on',
    mb.target(multi, 1078, wornTop).body, 'Hlr. Bliaut +1');
check('MB13f spending: the battery off first -> the idle refresh piece returns',
    mb.target(multi, 1060, wornTop).body, false);
-- At equal MP the higher-Refresh copy wins the pick.
check('MB13g equal-MP pick prefers the refresh copy',
    mb.build({ { slot = 'x', low = 0, lowRf = 0,
        rungs = { { name = 'Flat', mp = 30, rf = 0 },
                  { name = 'Rf Copy', mp = 30, rf = 1 } } } }, 100, 0)[1].name, 'Rf Copy');
end)();

-- ---------------------------------------------------------------------------
-- L. THE central stats-at-level resolver (levelstats.effective), against the
--    REAL generated scaling data: Tamas Ring is MP 15 on paper, 29 at Lv74,
--    30 fully scaled (Lv75). Every section -- gearui display/scoring, gearoptim
--    ranking, the automation manifests -- resolves item stats through this one
--    function, so no section values a scaling item at its base stats.
-- ---------------------------------------------------------------------------
package.loaded['dlac\\data\\levelscaling'] = dofile('data/levelscaling.lua');
local lstats = dofile('data/levelstats.lua');
local tamas = { Name = 'Tamas Ring', Id = 15545, Level = 30,
                Stats = { MP = 15, INT = 2, MND = 2, Enmity = -3 } };
check('L1 Tamas MP at Lv74',       lstats.effective(tamas, 74).MP, 29);
check('L2 Tamas MP fully scaled',  lstats.effective(tamas, 75).MP, 30);
check('L3 base table never mutated', tamas.Stats.MP, 15);
check('L4 non-scaling passthrough', lstats.effective({ Id = 13548, Stats = { ConvertHPtoMP = 25 } }, 74).ConvertHPtoMP, 25);
check('L5 nil level = base stats', lstats.effective(tamas, nil).MP, 15);
check('L6 nil-safe',               lstats.effective(nil, 74), nil);
-- thresholds = the band edges levelLadder re-scores at (real generated data:
-- Garrison Tunica +1 changes once at 51; 13680 ramps DEF at every decade)
check('L7 thresholds: Garrison Tunica +1', table.concat(lstats.thresholds(26543), ','), '51');
check('L8 thresholds: DEF ramp item',      table.concat(lstats.thresholds(13680), ','), '30,40,50,60,70,80,90');
check('L9 thresholds: non-scaling = {}',   #lstats.thresholds(13548), 0);

-- ---------------------------------------------------------------------------
-- M. cross-job cycle values. Mode DEFINITIONS are per-job trigger data; VALUES
--    are session-global (field case: "WHM Weapons" is defined in BRD's file and
--    gates WHM's sets). With no local definition: an explicit value jump works,
--    a bare flip must NOT toggle-corrupt the string into a boolean, off clears.
-- ---------------------------------------------------------------------------
check('M1 value jump without local def', dispatchM.setMode('WHM Weapons', 'DivinitySolo'), 'DivinitySolo');
check('M2 bare flip keeps the value',    dispatchM.setMode('WHM Weapons'), 'DivinitySolo');
check('M3 gated condition still true',   dispatchM.modeActive('WHM Weapons:DivinitySolo'), true);
check('M4 off still clears',             dispatchM.setMode('WHM Weapons', false), false);
check('M5 cleared for conditions',       dispatchM.modeActive('WHM Weapons:DivinitySolo'), false);

-- ---------------------------------------------------------------------------
-- N. mode-gated VIRTUAL slot entries. The Sets tab commits a gated virtual in
--    wrapper form ({ gear = 'dlac:AutoIridescence', mode = 'Weapon:Caster' });
--    only bare-string virtuals were recognised, so the gated marker flattened
--    to NOTHING (field case: WHM's Caster weapon cycle equipped no staff).
-- ---------------------------------------------------------------------------
AshitaCore = ashitaWithDW(true);
TEST_PLAYER = { MainJob = 'WHM', SubJob = 'NIN', MainJobSync = 75, SubJobSync = 37 };
local function weaponSets()
    return { Dynamic = { Weapon = { Main = {
        { gear = 'dlac:AutoIridescence', mode = 'Weapon:Caster' },
        { gear = dagger1H, mode = 'Weapon:SoloKC' },
    } } } };
end
dispatchM.setMode('Weapon', 'Caster');            -- def-less value jump (section M)
local sV = utils.BuildDynamicSets(weaponSets());
check('N1 active gated virtual flattens', sV.Weapon and sV.Weapon.Main, 'dlac:AutoIridescence');
dispatchM.setMode('Weapon', 'SoloKC');
sV = utils.BuildDynamicSets(weaponSets());
check('N2 other value: the gated item wins', sV.Weapon and sV.Weapon.Main, 'Kris');
dispatchM.setMode('Weapon', false);
sV = utils.BuildDynamicSets(weaponSets());
check('N3 no value at all: slot left alone', sV.Weapon and sV.Weapon.Main, nil);

-- ---------------------------------------------------------------------------
-- P. a Main STAFF MARKER pairs like a two-handed staff: the grip that belongs
--    with it is a legal Sub (field case: Weapon:Caster grip sat unequipped
--    under dlac:AutoIridescence because currentMain stayed nil).
-- ---------------------------------------------------------------------------
TEST_PLAYER = { MainJob = 'WHM', SubJob = 'NIN', MainJobSync = 75, SubJobSync = 37 };
AshitaCore = ashitaWithDW(false);
dispatchM.setMode('Weapon', 'Caster');
local vg = { Dynamic = { WV = {
    Main = { { gear = 'dlac:AutoIridescence', mode = 'Weapon:Caster' } },
    Sub  = { { gear = grip, mode = 'Weapon:Caster' } },
} } };
local sVG = utils.BuildDynamicSets(vg);
check('P1 marker main flattens',          sVG.WV and sVG.WV.Main, 'dlac:AutoIridescence');
check('P2 grip legal under the marker',   sVG.WV and sVG.WV.Sub, 'PoleGrip');
dispatchM.setMode('Weapon', false);

-- ---------------------------------------------------------------------------
-- VL. a virtual marker is a ladder RUNG at the level of the lowest item it can
--     resolve to (dispatch.virtualMinLevel; Henrik 2026-07-17: AutoIridescence
--     counted as Lv0 on a leveling WHM and shadowed the Pilgrim's Wand actually
--     worn -- with Chatoyant Staff as best owned it must read Lv51). Below that
--     level the flatten SKIPS the marker and the real best-by-level item owns
--     the slot; at/above it the marker|fallback composite returns. No manifest
--     answer (legacy boolean shape, craft family) -> nil -> old always-adopt.
-- ---------------------------------------------------------------------------
do
    dispatchM._autoOverride = {
        universal = { name = 'Chatoyant Staff', tier = 2, level = 51 },
        staff = { Fire = { name = 'Vulcans Staff', tier = 1, level = 51 } },
        obi = { Fire = { name = 'Karin Obi', level = 71 } },
    };
    check('VL1 staff marker min level',   dispatchM.virtualMinLevel('dlac:AutoIridescence'), 51);
    check('VL2 composite form tolerated', dispatchM.virtualMinLevel('dlac:AutoStaff|Pilgrims Wand'), 51);
    check('VL3 obi marker min level',     dispatchM.virtualMinLevel('dlac:AutoObi'), 71);
    check('VL4 craft marker: no answer',  dispatchM.virtualMinLevel('dlac:AutoCraft'), nil);

    local wand = { Name = 'Pilgrims Wand', Level = 7, OneHanded = true, Type = 'Club' };
    local function whmWeapon()
        return { Dynamic = { W = { Main = { 'dlac:AutoIridescence', wand } } } };
    end
    TEST_PLAYER = { MainJob = 'WHM', SubJob = 'BLM', MainJobSync = 40, SubJobSync = 20 };
    local sVL = utils.BuildDynamicSets(whmWeapon());
    check('VL5 below the rung: real item owns the slot', sVL.W and sVL.W.Main, 'Pilgrims Wand');
    TEST_PLAYER = { MainJob = 'WHM', SubJob = 'BLM', MainJobSync = 51, SubJobSync = 25 };
    sVL = utils.BuildDynamicSets(whmWeapon());
    check('VL6 at the rung: marker with fallback', sVL.W and sVL.W.Main, 'dlac:AutoIridescence|Pilgrims Wand');
    dispatchM._autoOverride = { iridescence = true };   -- legacy boolean manifest: no level info
    TEST_PLAYER = { MainJob = 'WHM', SubJob = 'BLM', MainJobSync = 40, SubJobSync = 20 };
    sVL = utils.BuildDynamicSets(whmWeapon());
    check('VL7 legacy manifest: old always-adopt behavior', sVL.W and sVL.W.Main, 'dlac:AutoIridescence|Pilgrims Wand');

    -- v82: the universals LADDER (manifest fmt 10). Preference-ordered by the
    -- GUI (tier desc, job-specific first); the engine takes the FIRST rung
    -- usable at the live level -- a level-synced character falls through a
    -- parked Inanna to Foreshadow +1 instead of losing the universal outright.
    -- virtualMinLevel answers the LOWEST rung: the marker adopts as early as
    -- the earliest universal, not only the top pick.
    local ladder = {
        { name = 'Inanna',        tier = 3, level = 75 },
        { name = 'Foreshadow +1', tier = 2, level = 50 },
    };
    dispatchM._autoOverride = { universals = ladder };
    check('VL8 ladder min level = lowest rung', dispatchM.virtualMinLevel('dlac:AutoIridescence'), 50);
    dispatchM._autoOverride = { universals = ladder,
        staff = { Fire = { name = 'Vulcans Staff', tier = 2, level = 40 } },
    };
    local function rs(lvl, el)
        return dispatchM._resolveVirtual('dlac:AutoStaff',
            { player = { MainJobSync = lvl }, action = (el ~= nil) and { Element = el } or nil });
    end
    check('VL9 top rung at level',                    rs(75), 'Inanna');
    check('VL10 synced under the top rung: falls through', rs(60), 'Foreshadow +1');
    check('VL11 tier tie vs elemental goes universal', rs(60, 'Fire'), 'Foreshadow +1');
    check('VL12 under every rung: elemental owns the cast', rs(45, 'Fire'), 'Vulcans Staff');
    check('VL13 under everything: no resolution',      rs(30, 'Fire'), nil);
    dispatchM._autoOverride = nil;
end

-- ---------------------------------------------------------------------------
-- Q. an explicitly RANGED entry owns its window: Garrison Tunica +1 ranged
--    20-51 must beat the higher-level unbounded Druid's Robe at 50 -- and hand
--    the slot back once the window closes.
-- ---------------------------------------------------------------------------
AshitaCore = ashitaWithDW(true);
local function rangedSets()
    return { Dynamic = { QT = { Body = {
        { Name = 'DruidsRobe', Level = 48 },
        { gear = { Name = 'GarrisonTunica', Level = 20 }, minLevel = 20, maxLevel = 51 },
    } } } };
end
TEST_PLAYER = { MainJob = 'WHM', SubJob = 'NIN', MainJobSync = 50, SubJobSync = 25 };
local sQ = utils.BuildDynamicSets(rangedSets());
check('Q1 live range beats a higher unbounded item', sQ.QT and sQ.QT.Body, 'GarrisonTunica');
TEST_PLAYER = { MainJob = 'WHM', SubJob = 'NIN', MainJobSync = 52, SubJobSync = 25 };
sQ = utils.BuildDynamicSets(rangedSets());
check('Q2 window closed: the unbounded item resumes', sQ.QT and sQ.QT.Body, 'DruidsRobe');
TEST_PLAYER = { MainJob = 'WHM', SubJob = 'NIN', MainJobSync = 19, SubJobSync = 25 };
sQ = utils.BuildDynamicSets(rangedSets());
check('Q3 below the window: nothing forced', sQ.QT and sQ.QT.Body, nil);

-- ---------------------------------------------------------------------------
-- R. multi-set trigger rules round-trip: set = { 'Base', 'Overlay' } must
--    serialize as the ordered list (a wiped second set = a silently dead
--    overlay); a single set stays in the plain string form.
-- ---------------------------------------------------------------------------
local rtext = dispatchM.serializeTriggers({
    Midcast = {
        { when = { name = 'Madrigal' }, set = { 'WindSkill', 'Madrigal' } },
        { when = { skill = 'Singing' }, set = 'SongPotency' },
    },
});
check('R1 ordered list serialized',
    rtext:find([[set = { "WindSkill", "Madrigal" }]], 1, true) ~= nil, true);
check('R2 single set stays plain',
    rtext:find([[set = "SongPotency"]], 1, true) ~= nil, true);

-- ---------------------------------------------------------------------------
-- S. PetAction is a first-class trigger section (dlac-synthesized event: this
--    LAC build tracks the pet's action but never calls a profile handler).
-- ---------------------------------------------------------------------------
check('S1 event canon', dispatchM.canonEvent('petaction'), 'PetAction');
local stext = dispatchM.serializeTriggers({
    PetAction = { { when = { contains = 'Predator' }, set = 'PetWS' } },
});
check('S2 section serializes', stext:find('PetAction = {', 1, true) ~= nil, true);
check('S3 rule serializes', stext:find([[contains = "Predator"]], 1, true) ~= nil, true);

-- ---------------------------------------------------------------------------
-- T. craftwatch -- synth detection core (packet 0x096 decode + recipe lookup).
--    Layout per XiPackets GP_CLI_COMMAND_COMBINE_ASK: Crystal u16 @0x06,
--    Items u8 @0x09, ItemNo[8] u16 @0x0A.
-- ---------------------------------------------------------------------------
package.loaded['dlac\\data\\crafts'] = {
    ['4096:1165,1165'] = { skill = 'Alchemy', lv = 60 },
    ['4096:640,650']   = { skill = 'Smithing', lv = 10, desynth = true },
};
-- auto-equip deps, stubbed: a profile with a Craft_Alchemy set + a recording cmdqueue
local craftCmds = {};
package.loaded['dlac\\lib\\cmdqueue'] = {
    enqueue = function(delay, cmd) craftCmds[#craftCmds + 1] = cmd; end,
    frame = function() return 0; end, tick = function() end,
};
package.loaded['dlac\\gear\\profilesets'] = {
    getSetsRoot = function()
        return { Dynamic = {
            Craft_Alchemy = {
                Main  = 'Chemists Kukri',                       -- plain string
                Head  = { Name = 'Midrass Helm +1' },            -- record form
                Body  = { gear = 'Alchemists Smock', minLevel = 40 },  -- wrapper form
                Range = 'dlac:AutoStaff|Fallback',               -- virtual: must be skipped
            },
            Craft = { Neck = 'Artisans Torque' },                -- universal fallback set
        } };
    end,
};
local craftwatch = dofile('feature/craftwatch.lua');

check('T1 key sorts ingredients', craftwatch.key(4096, { 650, 640 }), '4096:640,650');

-- synthetic 0x096: header(4) + HashNo + pad + crystal 4096 LE + idx + count 2
-- + ItemNo[8] (1165, 1165, zeroes) + TableNo[8]
local function u16le(v) return string.char(v % 256, math.floor(v / 256)); end
local pkt = string.char(0x96, 0x11, 0, 0)          -- header (id/size/sync -- unused by decode)
    .. string.char(0, 0)                            -- HashNo, padding
    .. u16le(4096) .. string.char(5)                -- Crystal, CrystalIdx
    .. string.char(2)                               -- Items = 2
    .. u16le(1165) .. u16le(1165) .. string.rep('\0', 12)  -- ItemNo[8]
    .. string.rep('\0', 8);                         -- TableNo[8]
local tcr, tings = craftwatch.decode(pkt);
check('T2 decode crystal', tcr, 4096);
check('T3 decode ingredient count', tings ~= nil and #tings or 0, 2);
check('T4 decode ingredient id', tings ~= nil and tings[1] or 0, 1165);
check('T5 lookup finds recipe', (craftwatch.lookup(4096, { 1165, 1165 }) or {}).skill, 'Alchemy');
check('T6 onSynth resolves craft', craftwatch.onSynth(4096, { 1165, 1165 }, 1).skill, 'Alchemy');
check('T7 onSynth desynth flag', craftwatch.onSynth(4096, { 650, 640 }, 2).desynth, true);
check('T8 unknown recipe fails soft', craftwatch.onSynth(4096, { 9999 }, 3).skill, 'unknown');
check('T9 malformed packet -> nil', craftwatch.decode('short'), nil);
check('T10 zero-ingredient packet -> nil',
    craftwatch.decode(string.char(0x96, 0x11, 0, 0, 0, 0) .. u16le(4096) .. string.char(5, 0) .. string.rep('\0', 24)), nil);

-- auto-equip: set entry resolution + the queued /lac commands
check('T11 entry: plain string',    craftwatch._entryName('Chemists Kukri'), 'Chemists Kukri');
check('T12 entry: virtual skipped', craftwatch._entryName('dlac:AutoStaff|Fallback'), nil);
check('T13 entry: record form',     craftwatch._entryName({ Name = 'X' }), 'X');
check('T14 entry: wrapper form',    craftwatch._entryName({ gear = 'Y', minLevel = 40 }), 'Y');
-- MANUAL model (Henrik): craftwatch just holds state (craft/goal/switch);
-- the ENGINE overlays the gear (dispatch.craftOverlay). No commands here.
-- saveCraftState no-ops without a live client, so we assert state only.
check('T14b fresh state defaults to Woodworking (first-timer rule, the HELM H0 twin)',
                                      craftwatch.getCraft(), 'Woodworking');
craftwatch.goal = 'hq';
craftwatch.selectCraft('Alchemy');
check('T15 selectCraft sets active',  craftwatch.getCraft(), 'Alchemy');
check('T16 select does NOT enable',   craftwatch.isEnabled(), false);
craftwatch.setEnabled(true);
check('T17 switch turns on',          craftwatch.isEnabled(), true);
craftwatch.setGoal('nq');
check('T18 goal stored',              craftwatch.getGoal(), 'nq');
craftwatch.onSynth(4096, { 1165, 1165 }, 20);   -- detection: info only, no state change
check('T19 detection keeps active',   craftwatch.getCraft(), 'Alchemy');
craftwatch.setEnabled(false);
check('T20 switch off',               craftwatch.isEnabled(), false);
craftwatch.goal = 'hq';

-- Engine overlay: dispatch resolves the craft gear per slot from the manifest
-- + goal (the same resolveVirtual path the addon preview uses).
dispatchM._autoOverride = { craft = {
    neck = { Alchemy = { hq = { { name = 'Artisan\'s Torque', score = 20, level = 1 } } } },
    ring1 = { Alchemy = { hq = { { name = 'Craftmaster\'s Ring', score = 5, level = 1 } } } },
} };
local ov = dispatchM._craftOverlayFor({ craft = 'Alchemy', goal = 'hq', enabled = true }, { player = { MainJobSync = 75 } });
check('T21 overlay resolves neck',    ov and ov.Neck, 'Artisan\'s Torque');
check('T22 overlay resolves ring1',   ov and ov.Ring1, 'Craftmaster\'s Ring');
local ovOff = dispatchM._craftOverlayFor({ craft = 'Alchemy', goal = 'hq', enabled = false }, { player = { MainJobSync = 75 } });
check('T23 disabled -> no overlay',   ovOff, nil);
local ovNoCraft = dispatchM._craftOverlayFor({ craft = '', goal = 'hq', enabled = true }, { player = { MainJobSync = 75 } });
check('T24 no craft -> no overlay',   ovNoCraft, nil);
dispatchM._autoOverride = nil;

-- Repeat-synth wait (a SETTING living in craftstate.lua, which craftwatch owns).
-- The 20s floor is FIELD TRUTH, not source math: the server would allow ~17s,
-- but the client's synthesis animation is frame-tied, so ~22s is the real
-- interval in a quiet zone (Henrik, 07-25).
check('T24b wait defaults to 30',          craftwatch.getSynthWait(), 30);
check('T24c wait clamps up to the floor',  craftwatch._clampWait(5), 20);
check('T24d wait clamps to the ceiling',   craftwatch._clampWait(999), 120);
check('T24e garbage falls back to default', craftwatch._clampWait('x'), 30);
check('T24f a sane value is kept',         craftwatch.setSynthWait(45), 45);
check('T24g setSynthWait clamps too',      craftwatch.setSynthWait(1), 20);
craftwatch.setSynthWait(30);

-- ---------------------------------------------------------------------------
-- U. synthrun -- the 2..6 repeat-synth batch runner (feature/synthrun.lua).
-- Drives the whole state machine headless on an injected clock, a recording
-- AshitaCore and a stub chatfmt, so the colour of each report is assertable.
-- Wrapped in an IIFE (the smoke_ui idiom): the main chunk is at Lua's 200-local
-- ceiling, and a scope of its own also keeps the stubs from leaking downstream.
-- ---------------------------------------------------------------------------
(function()
local _savedChatfmt = package.loaded['dlac\\chatfmt'];
local chatlog = {};
package.loaded['dlac\\chatfmt'] = {
    good = function(s) chatlog[#chatlog + 1] = { 'good', s }; end,
    warn = function(s) chatlog[#chatlog + 1] = { 'warn', s }; end,
    msg  = function(s) chatlog[#chatlog + 1] = { 'msg',  s }; end,
};
local function clearLog() for i = #chatlog, 1, -1 do chatlog[i] = nil; end end

local synthrun = dofile('feature/synthrun.lua');

-- s2c 0x030 synthesis animation: TargetIndex u16 @0x08, result type i8 @0x0C.
local function animPkt(idx, typ)
    return string.rep('\0', 8) .. u16le(idx) .. string.rep('\0', 2)
        .. string.char(typ) .. string.rep('\0', 8);
end
-- s2c 0x06F synthesis results: Result @0x04, Count @0x06, ItemNo u16 @0x08.
local function resPkt(code, count, id)
    return string.rep('\0', 4) .. string.char(code) .. '\0' .. string.char(count)
        .. '\0' .. u16le(id) .. string.rep('\0', 8);
end

local aIdx, aTyp = synthrun.decodeAnim(animPkt(0x1234, 2));
check('U1 anim decodes the actor index',  aIdx, 0x1234);
check('U2 anim decodes the result type',  aTyp, 2);
check('U3 short anim packet -> nil',      synthrun.decodeAnim('xx'), nil);
local rCode, rCount, rId = synthrun.decodeResult(resPkt(0x00, 4, 640));
check('U4 result decodes the code',       rCode, 0);
check('U5 result decodes the quantity',   rCount, 4);
check('U6 result decodes the item id',    rId, 640);
check('U7 short result packet -> nil',    synthrun.decodeResult('x'), nil);

-- Tally. HQ needs NO special case: the game names HQ items "... +1", so they
-- separate on their own (crafts.lua only stores the NQ result id).
synthrun._itemName = function(id)
    return ({ [640] = 'Bronze Ingot', [641] = 'Bronze Ingot +1' })[id] or ('item #' .. tostring(id));
end
local tMade, tBroke, tItems = synthrun.tally({
    { code = 0x00, count = 2, id = 640 },
    { code = 0x01, count = 0, id = 0   },   -- break
    { code = 0x00, count = 2, id = 640 },
    { code = 0x00, count = 1, id = 641 },   -- HQ
});
check('U8 tally counts successes',        tMade, 3);
check('U9 tally counts breaks',           tBroke, 1);
check('U10 tally groups by item, HQ apart', tItems, '4x Bronze Ingot, 1x Bronze Ingot +1');

-- --- the state machine -------------------------------------------------------
local sent = {};
local _savedAC = rawget(_G, 'AshitaCore');
local _savedGPE = rawget(_G, 'GetPlayerEntity');
_G.AshitaCore = { GetChatManager = function()
    return { QueueCommand = function(_, mode, cmd) sent[#sent + 1] = { mode = mode, cmd = cmd }; end };
end };
_G.GetPlayerEntity = function() return { TargetIndex = 100 }; end
local T = 0;
synthrun._now = function() return T; end
synthrun.getWait = function() return 25; end

check('U11 start refuses 0',                  synthrun.start(0), false);
check('U12 start refuses 7 (macro-bar cap)',  synthrun.start(7), false);
check('U13 start fires immediately',          synthrun.start(3) and #sent, 1);
check('U14 it TYPES the game\'s own command', sent[1].cmd, '/lastsynth');
check('U15 ...in Typed mode (Ashita CommandMode 1)', sent[1].mode, 1);
check('U16 a second batch is refused',        synthrun.start(2), false);

synthrun.onPacket(0x030, animPkt(999, 0));    -- a BYSTANDER's synth
synthrun.tick();
check('U17 a bystander\'s animation is ignored', synthrun.status().done, 0);
synthrun.onPacket(0x030, animPkt(100, 0));    -- ours
synthrun.tick();
check('U18 our animation counts the synth',   synthrun.status().done, 1);
check('U19 the next shot waits out the timer', synthrun.status().nextIn, 25);
T = T + 24; synthrun.tick();
check('U20 nothing fires before the wait elapses', #sent, 1);
T = T + 2;  synthrun.tick();
check('U21 the next synth fires after the wait', #sent, 2);

-- Shot 2 never lands. ONE retry (frame hitches are transient), then abort --
-- "out of materials" and "inventory full" are permanent, so the retry costs
-- ~2s at the end of a run that was over anyway (Henrik, 07-25).
T = T + 1.9; synthrun.tick();
check('U22 no retry inside the 2s detect window', #sent, 2);
T = T + 0.2; synthrun.tick();
check('U23 a missed shot is retried once',    #sent, 3);
check('U24 status surfaces the retry',        synthrun.status().retrying, true);
clearLog();
T = T + 2.1; synthrun.tick();
check('U25 a second miss aborts the batch',   synthrun.status(), nil);
check('U26 an early stop reports in YELLOW',  chatlog[1] and chatlog[1][1], 'warn');
check('U27 ...and says how far it got',       (chatlog[1] and chatlog[1][2] or ''):sub(1, 29),
                                              'Crafting stopped after 1 of 3');

-- A clean run: the report waits for the LAST 0x06F, so it can name what came out.
T = 1000; sent = {}; clearLog();
synthrun.start(2);
synthrun.onPacket(0x030, animPkt(100, 0)); synthrun.tick();
synthrun.onPacket(0x06F, resPkt(0x00, 2, 640)); synthrun.tick();
T = T + 25; synthrun.tick();
check('U28 the second synth fires',           #sent, 2);
synthrun.onPacket(0x030, animPkt(100, 2)); synthrun.tick();
check('U29 the last synth is not reported until its result lands', #chatlog, 0);
synthrun.onPacket(0x06F, resPkt(0x00, 1, 641)); synthrun.tick();
check('U30 the batch completes',              synthrun.status(), nil);
check('U31 a full run reports in GREEN',      chatlog[1] and chatlog[1][1], 'good');
check('U32 the report names what was made',   chatlog[1] and chatlog[1][2],
      'Crafting complete -- 2 synths: 2x Bronze Ingot, 1x Bronze Ingot +1.');

-- Breaks are counted, and they change the wording but not the colour.
T = 2000; sent = {}; clearLog();
synthrun.start(2);
synthrun.onPacket(0x030, animPkt(100, 0)); synthrun.tick();
synthrun.onPacket(0x06F, resPkt(0x01, 0, 0)); synthrun.tick();   -- break
T = T + 25; synthrun.tick();
synthrun.onPacket(0x030, animPkt(100, 0)); synthrun.tick();
synthrun.onPacket(0x06F, resPkt(0x00, 3, 640)); synthrun.tick();
check('U33 a run with a break still reports made/broke', chatlog[1] and chatlog[1][2],
      'Crafting complete -- 2 synths (1 made, 1 broke): 3x Bronze Ingot.');

-- The final result never arrives (bad zone): report anyway once the grace ends.
T = 3000; sent = {}; clearLog();
synthrun.start(1);
synthrun.onPacket(0x030, animPkt(100, 0)); synthrun.tick();
T = T + 31; synthrun.tick();
check('U34 a missing final result still reports after the grace', synthrun.status(), nil);
check('U35 ...still green (the synths did run)', chatlog[1] and chatlog[1][1], 'good');

-- A 0x06F cancel code arrives with NO animation -- stop at once and name it.
T = 4000; sent = {}; clearLog();
synthrun.start(3);
synthrun.onPacket(0x06F, resPkt(0x06, 0, 0)); synthrun.tick();   -- CancelSkillTooLow
check('U36 a cancel code stops the batch at once', synthrun.status(), nil);
check('U37 cancel reports in YELLOW',         chatlog[1] and chatlog[1][1], 'warn');
check('U38 cancel names the real reason',
      (chatlog[1] and chatlog[1][2] or ''):find('craft skill is too low', 1, true) ~= nil, true);

-- Zoning voids every assumption (and on this server it destroys the materials).
T = 5000; sent = {}; clearLog();
synthrun.start(3);
synthrun.onPacket(0x030, animPkt(100, 0)); synthrun.tick();
synthrun.onPacket(0x00A, ''); synthrun.tick();
check('U39 zoning aborts the batch',          synthrun.status(), nil);

-- Your own Stop is not an alarm: white, not yellow.
T = 6000; sent = {}; clearLog();
synthrun.start(3);
synthrun.onPacket(0x030, animPkt(100, 0)); synthrun.tick();
synthrun.stop();
check('U40 stop ends the batch',              synthrun.status(), nil);
check('U41 your own stop is not an alarm',    chatlog[1] and chatlog[1][1], 'msg');
check('U42 stop says how far it got',         chatlog[1] and chatlog[1][2],
      'Crafting stopped -- 1 of 3 done.');
check('U43 stop is a no-op when idle',        synthrun.stop(), false);
check('U44 status is nil when idle',          synthrun.status(), nil);

_G.AshitaCore = _savedAC;
_G.GetPlayerEntity = _savedGPE;
package.loaded['dlac\\chatfmt'] = _savedChatfmt;
end)();

-- 0x055 key item tracker (the SDK HasKeyItem memory read is dead on this
-- client -- craftwatch keeps its own bitfield from the packet stream).
-- Layout: u32 header | avail[0x40] | examined[0x40] | blockOffset | pad x3.
local function kiPacket(block, setBits)   -- setBits = { id, ... } within the block
    local avail = {};
    for i = 1, 0x40 do avail[i] = 0; end
    for _, id in ipairs(setBits) do
        local rel = id - block * 512;
        local x, y = math.floor(rel / 8), rel % 8;
        avail[x + 1] = avail[x + 1] + 2 ^ y;
    end
    local bytes = {};
    for i = 1, 0x40 do bytes[i] = string.char(avail[i]); end
    return string.char(0x55, 0x24, 0, 0) .. table.concat(bytes)
        .. string.rep('\0', 0x40) .. string.char(block) .. string.rep('\0', 3);
end
craftwatch.onKeyItemPacket(kiPacket(3, { 1988, 2044 }));   -- Carpenter + Culinarian
check('T21 ki bit -> owned',           craftwatch.hasKeyItem(2044), true);
check('T22 second ki bit -> owned',    craftwatch.hasKeyItem(1988), true);
check('T23 unset ki -> not owned',     craftwatch.hasKeyItem(2000), false);
check('T24 blocks counted',            craftwatch.kiBlocksSeen, 1);
craftwatch.onKeyItemPacket(kiPacket(3, { 1988 }));         -- resync without Culinarian
check('T25 cleared bit -> revoked',    craftwatch.hasKeyItem(2044), false);
check('T26 other block untouched',     craftwatch.hasKeyItem(1988), true);

-- Guild points from s2c 0x113 -- verify the byte offsets against Henrik's
-- in-game currency menu values. int32 LE at absolute e.data offsets.
local function i32(v) return string.char(v % 256, math.floor(v/256)%256, math.floor(v/65536)%256, math.floor(v/16777216)%256); end
-- header(4) + PacketData: pad to fishing@0x20, then the 8 craft int32s.
local gpPkt = string.rep('\0', 0x20)   -- header + conquest/seals/... up to fishing
    .. i32(1111)      -- 0x20 fishing (parsed since the fishing system -- F-tests assert it)
    .. i32(2555)      -- 0x24 woodworking
    .. i32(6536)      -- 0x28 smithing
    .. i32(10990)     -- 0x2C goldsmithing
    .. i32(540)       -- 0x30 weaving/clothcraft
    .. i32(23539)     -- 0x34 leathercraft
    .. i32(0)         -- 0x38 bonecraft
    .. i32(75200)     -- 0x3C alchemy
    .. i32(4325);     -- 0x40 cooking
craftwatch.onCurrencyPacket(gpPkt);
check('T27 gp woodworking',  craftwatch.guildPointsFor('Woodworking'), 2555);
check('T28 gp goldsmithing', craftwatch.guildPointsFor('Goldsmithing'), 10990);
check('T29 gp clothcraft(weaving)', craftwatch.guildPointsFor('Clothcraft'), 540);
check('T30 gp alchemy',      craftwatch.guildPointsFor('Alchemy'), 75200);
check('T31 gp cooking',      craftwatch.guildPointsFor('Cooking'), 4325);
check('T32 gp bonecraft zero', craftwatch.guildPointsFor('Bonecraft'), 0);
check('T33 gpReady', craftwatch.gpReady(), true);

-- Last Synth observation: onSynth must retain crystal + ingredients (they
-- label the craft bar's "Last synth:" line; /lastsynth itself is the GAME'S
-- native command -- dlac never intercepts or re-sends, so no slot/packet
-- machinery exists to test since c38c2ff's successor).
local curT = craftwatch.onSynth(4096, { 1165, 1165 }, 40);
check('T34 current keeps crystal', curT.crystal, 4096);
check('T35 current keeps ings order', curT.ings[1] == 1165 and #curT.ings == 2, true);

-- ---------------------------------------------------------------------------
-- IE. idleexcl -- the four idle hobbies (Craft/HELM/Fishing/Chocobo) are MUTUALLY
--     EXCLUSIVE at the enable toggle (ADR 0017): arming one stands the other three
--     down, getActive() names the armed one, deactivate() stands it down (the
--     float's Off button). This is the ENABLE-layer radio, NOT the claim-side
--     co-claim engine -- AR8/AR9/AR10 stub state files and never call setEnabled,
--     so they are untouched by this.
-- (Wrapped in an IIFE so its locals stay OFF the test file's 200-local main-chunk
-- ceiling -- the same hard rule the addon's own modules follow.)
-- ---------------------------------------------------------------------------
;(function()
    -- Fresh watcher instances; preload so idleexcl.onActivated can require() its
    -- peers (in the addon dlac.lua's package.path does this; the harness doesn't).
    local IE_cw = dofile('feature/craftwatch.lua');
    local IE_hw = dofile('feature/helmwatch.lua');
    local IE_fw = dofile('feature/fishwatch.lua');
    local IE_ch = dofile('feature/chocowatch.lua');
    local savedLoaded = {};
    for _, k in ipairs({ 'craftwatch', 'helmwatch', 'fishwatch', 'chocowatch', 'idleexcl' }) do
        savedLoaded['dlac\\feature\\' .. k] = package.loaded['dlac\\feature\\' .. k];
    end
    package.loaded['dlac\\feature\\craftwatch'] = IE_cw;
    package.loaded['dlac\\feature\\helmwatch']  = IE_hw;
    package.loaded['dlac\\feature\\fishwatch']  = IE_fw;
    package.loaded['dlac\\feature\\chocowatch'] = IE_ch;
    local idleexcl = dofile('feature/idleexcl.lua');
    package.loaded['dlac\\feature\\idleexcl'] = idleexcl;

    -- HELM's ONE switch is Auto HELM now (manual idle is unwired from the UI).
    local function armedCount()
        return (IE_cw.isEnabled() and 1 or 0)
             + (IE_hw.isAutoHelm() and 1 or 0)
             + (IE_fw.isEnabled() and 1 or 0)
             + (IE_ch.isEnabled() and 1 or 0);
    end

    -- clean slate
    IE_cw.setEnabled(false); IE_hw.setEnabled(false); IE_hw.setAutoHelm(false);
    IE_fw.setEnabled(false); IE_ch.setEnabled(false);
    check('IE0 nothing armed -> getActive nil',     idleexcl.getActive(), nil);
    check('IE0b canActivate any when idle',         idleexcl.canActivate('fish'), true);

    -- Arm Craft.
    IE_cw.setEnabled(true);
    check('IE1 craft armed -> active is craft',     (idleexcl.getActive() or {}).key, 'craft');
    check('IE1b craft detail = the picked craft',   (idleexcl.getActive() or {}).detail, IE_cw.getCraft());

    -- LOCK-while-active: arming another hobby is REFUSED (no auto-disarm).
    check('IE2 canActivate helm false vs active craft', idleexcl.canActivate('helm'), false);
    IE_hw.setAutoHelm(true);
    check('IE2b arming HELM refused -> HELM stays off',  IE_hw.isAutoHelm(), false);
    check('IE2c craft is still the active one',          (idleexcl.getActive() or {}).key, 'craft');
    check('IE2d still exactly one armed',                armedCount(), 1);

    IE_fw.setEnabled(true);
    check('IE3 arming Fishing refused vs active craft',  IE_fw.isEnabled(), false);
    check('IE3b craft still active',                     (idleexcl.getActive() or {}).key, 'craft');

    -- SWITCH: turn Craft off, THEN arm HELM (Auto).
    IE_cw.setEnabled(false);
    check('IE4 craft off -> nothing active',        idleexcl.getActive(), nil);
    IE_hw.setAutoHelm(true);
    check('IE4b HELM (auto) now arms',              IE_hw.isAutoHelm(), true);
    check('IE4c HELM is the active one',            (idleexcl.getActive() or {}).key, 'helm');
    check('IE4d HELM detail = gather category',     (idleexcl.getActive() or {}).detail, IE_hw.getGather());
    check('IE4e re-arming the SAME hobby is allowed', idleexcl.canActivate('helm'), true);

    -- deactivate() stands the armed one down (badge Off) -> clears BOTH HELM switches.
    check('IE5 deactivate returns the armed key',   idleexcl.deactivate(), 'helm');
    check('IE5b HELM auto cleared by deactivate',   IE_hw.isAutoHelm(), false);
    check('IE5c none armed after deactivate',       idleexcl.getActive(), nil);
    check('IE5d isActive false when none armed',    idleexcl.isActive(), false);

    -- With nothing active, any hobby can arm; Chocobo works.
    IE_ch.setEnabled(true);
    check('IE6 chocobo arms when idle',             (idleexcl.getActive() or {}).key, 'choco');
    check('IE6b exactly one armed',                 armedCount(), 1);

    -- Restore: stand everything down and put package.loaded back so later blocks
    -- are unaffected (a later fishwatch.setEnabled must NOT reach these peers).
    IE_ch.setEnabled(false);
    IE_hw.setEnabled(false); IE_hw.setAutoHelm(false);
    for k, v in pairs(savedLoaded) do package.loaded[k] = v; end
end)();

-- ---------------------------------------------------------------------------
-- U. Set-entry name resolution -- case-insensitive fallback + quiet-once warn.
--    Field case (SMN "test" commit): static-migrated sets say "Solid wand" but
--    gear.lua's client name is "Solid Wand"; every rebuild flooded chat with
--    per-occurrence "Unable to find" lines and the entries flattened to nothing.
-- ---------------------------------------------------------------------------
TEST_PLAYER = { MainJob = 'SMN', SubJob = 'WHM', MainJobSync = 75, SubJobSync = 37 };
package.loaded['dlac\\gear'].NameToObject['Solid Wand'] =
    { Name = 'Solid Wand', Level = 20, Type = 'Club', OneHanded = true };
utils._resetNameIndex();
AshitaCore = ashitaWithDW(false);
local sCase = utils.BuildDynamicSets({ Dynamic = { Idle = { Main = { 'solid wand' } } } });
check('U1 case-insensitive name resolves', sCase.Idle and sCase.Idle.Main, 'Solid Wand');
local sWrap = utils.BuildDynamicSets({ Dynamic = { Idle = { Main = { { gear = 'SOLID WAND', minLevel = 10 } } } } });
check('U2 wrapper ref resolves case-blind', sWrap.Idle and sWrap.Idle.Main, 'Solid Wand');
local sMiss = utils.BuildDynamicSets({ Dynamic = { Idle = { Main = { 'No Such Item' } } } });
check('U3 missing name flattens empty, no error', sMiss.Idle and sMiss.Idle.Main, nil);

-- ---------------------------------------------------------------------------
-- T. deleteStaticSetText: removes a direct child of the sets ROOT (a legacy
--    static set), never the Dynamic block, never nested lookalikes.
-- ---------------------------------------------------------------------------
local setmgrT = dofile('gear/setmanager.lua');
local statFix = table.concat({
    'local sets = {',
    '    Dynamic = {',
    '        TP = {',
    '            Main = { "A" },',
    '        },',
    '    },',
    '    Idle = {',
    '        Body = "X",',
    '        Sub = { "Y" },',
    '    },',
    '    Precast = { Head = "Z" },',
    '};',
    'profile = { Sets = sets };',
    'return profile;',
}, '\n');
local tOut, tAct = setmgrT.deleteStaticSetText(statFix, 'Idle');
check('T1 static deleted',        tAct, 'deleted static');
check('T2 block gone',            tOut ~= nil and tOut:find('Idle = {', 1, true), nil);
check('T3 Dynamic intact',        tOut ~= nil and tOut:find('TP = {', 1, true) ~= nil, true);
check('T4 sibling intact',        tOut ~= nil and tOut:find('Precast = {', 1, true) ~= nil, true);
check('T5 result parses',         tOut ~= nil and (loadstring or load)(tOut) ~= nil, true);
local _, tErr = setmgrT.deleteStaticSetText(statFix, 'Dynamic');
check('T6 Dynamic refused',       tErr, 'refusing to delete the Dynamic block');
local _, tErr2 = setmgrT.deleteStaticSetText(statFix, 'Sub');
check('T7 nested name never matches', tErr2 ~= nil and tErr2:find('no static set named', 1, true) ~= nil, true);

-- ---------------------------------------------------------------------------
-- V. dlac:AutoCraft resolution (craft automation, docs/design/craft-automation.md)
--    Per-slot manifest ladders, active craft from the 'craft' mode (or
--    ctx.craftOverride), goal from 'craftgoal' (hq default, STRICT per-goal --
--    no cross-goal substitution), level-gated best-first rungs.
-- ---------------------------------------------------------------------------
dispatchM._autoOverride = { craft = {
    neck = { Alchemy = {
        hq = { { name = 'Alchemists Torque', score = 30, level = 50 },
               { name = 'Artisans Torque',   score = 8,  level = 1 } },
        nq = { { name = 'Artisans Torque',   score = 8,  level = 1 } },
    } },
    ring1 = { Alchemy = {
        nq = { { name = 'Artisans Ring', score = 100, level = 45 } },
    } },
} };
local vctx = { player = { MainJobSync = 75 } };
dispatchM.modes['craft'] = 'Alchemy';
check('V1 hq default: best rung',   dispatchM._resolveVirtual('dlac:AutoCraft', vctx, 'Neck'), 'Alchemists Torque');
-- the goal is the manifest's ONE craftGoal field (no mode-system round-trip)
dispatchM._autoOverride.craftGoal = 'nq';
check('V2 nq goal picks nq ladder', dispatchM._resolveVirtual('dlac:AutoCraft', vctx, 'Neck'), 'Artisans Torque');
check('V3 nq ring1 ladder',         dispatchM._resolveVirtual('dlac:AutoCraft', vctx, 'Ring1'), 'Artisans Ring');
check('V4 STRICT per-goal: hq-only slot unresolved under nq',
    dispatchM._resolveVirtual('dlac:AutoCraft', { player = { MainJobSync = 75 }, goalOverride = 'nq', craftOverride = 'Alchemy' }, 'Feet'), nil);
dispatchM._autoOverride.craftGoal = nil;
check('V5 level gate falls down the ladder',
    dispatchM._resolveVirtual('dlac:AutoCraft', { player = { MainJobSync = 40 } }, 'Neck'), 'Artisans Torque');
dispatchM.modes['craft'] = nil;
check('V6 mode off -> unresolved',  dispatchM._resolveVirtual('dlac:AutoCraft', vctx, 'Neck'), nil);
check('V7 craftOverride resolves without the mode',
    dispatchM._resolveVirtual('dlac:AutoCraft', { player = { MainJobSync = 75 }, craftOverride = 'Alchemy' }, 'Neck'), 'Alchemists Torque');
check('V8 slot without craft gear -> unresolved',
    dispatchM._resolveVirtual('dlac:AutoCraft', { player = { MainJobSync = 75 }, craftOverride = 'Alchemy' }, 'Body'), nil);
-- third goal: skillup ladders resolve like the others (strictly per-goal)
dispatchM._autoOverride.craft.neck.Alchemy.skillup = { { name = 'Shapers Shawl', score = 250, level = 1 } };
check('V9 skillup goal picks skillup ladder',
    dispatchM._resolveVirtual('dlac:AutoCraft', { player = { MainJobSync = 75 }, craftOverride = 'Alchemy', goalOverride = 'skillup' }, 'Neck'), 'Shapers Shawl');
dispatchM._autoOverride = nil;

-- ---------------------------------------------------------------------------
-- W. craftwatch tier / binding-craft calc: HQ tiers break at margins >11/31/51;
--    on subcraft recipes the SMALLEST margin binds (Henrik: enough clothcraft
--    but not bonecraft -> boost bonecraft).
-- ---------------------------------------------------------------------------
check('W1 tier 0 at margin 11',  craftwatch.tierOf(11), 0);
check('W2 tier 1 above 11',      craftwatch.tierOf(12), 1);
check('W3 tier 2 above 31',      craftwatch.tierOf(32), 2);
check('W4 tier 3 above 51',      craftwatch.tierOf(52), 3);
check('W5 nil margin -> nil',    craftwatch.tierOf(nil), nil);
local fakeSkill = function(cr) return ({ Clothcraft = 80, Bonecraft = 40 })[cr]; end
local bCr, bMg = craftwatch.bindingCraft({ Clothcraft = 60, Bonecraft = 35 }, fakeSkill);
check('W6 binding = smallest margin craft', bCr, 'Bonecraft');
check('W7 binding margin', bMg, 5);
check('W8 no skills -> nil', (craftwatch.bindingCraft(nil, fakeSkill)), nil);

-- ---------------------------------------------------------------------------
-- X. engine self-swap handshake (dispatch.lua hot-reload, v32). Re-executing
--    dispatch.lua with _G.__dlacEngineRoot set must populate THAT table --
--    identity preserved, so utils' captured reference and the profiles' shims
--    run the new code with no re-require -- and the swapper's version-parse
--    must find the real assignment (a reformat of the M.VERSION line would
--    kill the swap SILENTLY otherwise).
-- ---------------------------------------------------------------------------
local root = { VERSION = -1, dispatch = 'stale sentinel', leftover = 'kept' };
_G.__dlacEngineRoot = root;
local swapped = dofile('dispatch.lua');
_G.__dlacEngineRoot = nil;
check('X1 swap populates the handed-over root table', rawequal(swapped, root), true);
check('X2 stale fields are overwritten with live code', type(root.dispatch), 'function');
check('X3 version claimed on the root', root.VERSION, dispatchM.VERSION);
local fresh = dofile('dispatch.lua');
check('X4 normal load (no handshake) stays a fresh table', rawequal(fresh, root), false);
local fh = io.open('dispatch.lua', 'r');
local rawSrc = fh:read('*a'); fh:close();
check('X5 swapper version-parse finds the assignment',
    tonumber(string.match(rawSrc, 'M%.VERSION%s*=%s*(%d+)')), dispatchM.VERSION);

-- X6. WHAT SURVIVES A SELF-SWAP. The swap re-executes the file against the SAME
-- module table (rawset __dlacEngineRoot -> run chunk), so every `M.x = {}` at file
-- scope is a silent reset of live session state every time a `git pull` lands.
-- M.locks used to be exactly that: all sixteen slots quietly unlocked mid-session,
-- announced only by a parenthetical in the swap line. ADR 0021 named the leak while
-- rejecting a lock-based naked; ADR 0022 then put a LOCKED SET on the same row, so
-- half the row surviving a reseed while the other half evaporated was the last
-- reason to leave it. Modelled here exactly as trySelfSwap does it.
(function()
    local live = { VERSION = -1 };
    _G.__dlacEngineRoot = live;
    dofile('dispatch.lua');                       -- first load: fills the table
    live.locks['head'] = true;                    -- the player locks a slot...
    live.modes['testmode'] = true;                -- ...and sets a mode
    live.lockedSet = { name = 'Incursion T3', mode = 'set', claim = { Head = 'X' }, n = 1 };
    dofile('dispatch.lua');                       -- ...then a git pull lands
    _G.__dlacEngineRoot = nil;
    check('X6 a self-swap KEEPS the player\'s slot locks', live.locks['head'], true);
    check('X6b ...and a locked set (ADR 0022)',            live.lockedSet ~= nil, true);
    -- Modes are still reset by the same re-execution, and that is correct: they
    -- have a disk mirror the engine reads BACK on load (loadModeState), so they
    -- heal. Locks never could -- __locks is display-only and deliberately never
    -- restored, because a lock is a "right now" decision -- which is exactly why
    -- the fix for them had to live on the table instead of in the mirror.
    check('X6c modes still reset -- they heal from the modestate mirror, locks cannot',
        live.modes['testmode'], nil);
    check('X6d ...the swap line no longer promises otherwise',
        rawSrc:find('slot locks reset', 1, true), nil);
end)();
-- A FRESH Lua state still starts clean: no handshake table, so M is new and every
-- `or {}` above takes its empty branch. This is the LAC-reload path.
check('X7 a fresh load starts with no locks',    next(dofile('dispatch.lua').locks), nil);
check('X7b ...and nothing locked',               dofile('dispatch.lua').lockedSet, nil);

-- ---------------------------------------------------------------------------
-- Y. profile storage layer (profiles.lua, v33): the pure text machinery, and
--    headless safety (every fs/Ashita touch is call-time + guarded, so nil
--    answers -- never errors -- before login). The extract -> frame -> extract
--    round trip IS the migration's "your dynamic sets survive byte-for-byte"
--    guarantee; the splice checks pin that setmanager's scanners keep working
--    on the profile sets file unchanged.
-- ---------------------------------------------------------------------------
local profilesM = package.loaded['dlac\\profiles'];

check('Y1 loads headlessly', type(profilesM), 'table');
check('Y2 sanitize: ok name', profilesM.sanitizeName('My_Profile-2'), 'My_Profile-2');
check('Y3 sanitize: rejects spaces', profilesM.sanitizeName('two words'), nil);
check('Y4 sanitize: rejects path tricks', profilesM.sanitizeName('..\\evil'), nil);
check('Y5 headless: setsPath is nil pre-login', profilesM.setsPath('WAR'), nil);
check('Y6 headless: readSetsFile refuses politely', (select(2, profilesM.readSetsFile('WAR'))), 'not logged in');
check('Y7 headless: cloneProfile refuses politely', (select(2, profilesM.cloneProfile('A', 'B'))), 'not logged in');

-- a realistic job file: nested braces, a brace inside a comment, a brace inside
-- a string, mode/minLevel wrappers, virtual slot entries, static siblings.
local JOBFILE = [[
local profile = {};
local utils = require("dlac\utils");
local gear  = utils.gear;
local sets = {
    Dynamic = {
        Idle = {
            Head = {
                gear.Head.PoetsCirclet,
                { gear = gear.Head.WlkChapeau, minLevel = 60 },  -- gated { brace in comment
            },
            Body = { 'dlac:AutoStaff', gear.Body.Doublet_1 },
        },
        Tp_Default = {
            Main = { { gear = gear.Main.Club.MapleWand_1, mode = "Weapon:Melee}" } },
        },
    },
    Idle = { Head = "Poet's Circlet" },
    Precast = { Body = 'Doublet' },
};
profile.Sets = sets;
profile.HandleDefault = function() sets = utils.rebuildSets(sets); utils.dispatch('Default'); end
return profile;
]];

local dynText, dynErr = profilesM.extractDynamicText(JOBFILE);
check('Y8 extract finds the block', dynErr, nil);
check('Y9 extract starts at the keyword', dynText ~= nil and dynText:sub(1, 7), 'Dynamic');
check('Y10 extract keeps every set', dynText ~= nil and dynText:find('Tp_Default', 1, true) ~= nil, true);
check('Y11 extract stops at the block (statics excluded)', dynText ~= nil and dynText:find('Precast', 1, true), nil);
check('Y12 extract is verbatim (a substring of the source)', dynText ~= nil and JOBFILE:find(dynText, 1, true) ~= nil, true);
check('Y13 no block -> nil + why', (select(2, profilesM.extractDynamicText('local x = 1;'))), 'no sets.Dynamic block');

-- frame it into a profile sets file, run it, and extract it back out.
local function loadWithEnv(text, env)
    if setfenv ~= nil then
        local c = (loadstring or load)(text);
        if c == nil then return nil; end
        setfenv(c, env);
        return c;
    end
    return load(text, 'framed', 't', env);
end
local STUBG; STUBG = setmetatable({}, { __index = function() return STUBG; end });

local framed = profilesM.frameSetsText(dynText);
check('Y14 framed file parses', (loadstring or load)(framed) ~= nil, true);
check('Y15 frame -> extract round trip is byte-identical', profilesM.extractDynamicText(framed), dynText);
local fchunk = loadWithEnv(framed, setmetatable({ gear = STUBG }, { __index = _G }));
local fok, fsets = pcall(fchunk);
check('Y16 framed file runs', fok, true);
check('Y17 framed Dynamic has both sets', fok and type(fsets) == 'table' and type(fsets.Dynamic) == 'table'
    and fsets.Dynamic.Idle ~= nil and fsets.Dynamic.Tp_Default ~= nil, true);

local emptyFramed = profilesM.frameSetsText(nil);
local echunk = loadWithEnv(emptyFramed, setmetatable({ gear = STUBG }, { __index = _G }));
local eok, esets = pcall(echunk);
check('Y18 empty frame runs with an empty Dynamic', eok and type(esets) == 'table'
    and type(esets.Dynamic) == 'table' and next(esets.Dynamic) == nil, true);

-- setmanager's scanners work on the framed file UNCHANGED (commit/delete land
-- in profile storage now -- this is the compatibility that makes that free).
local spliced, saction = setmgrT.spliceSet(framed, 'Resting', {
    { name = 'Head', items = { { path = 'gear.Head.PoetsCirclet' } } },
});
check('Y19 splice into framed file', saction, 'inserted');
check('Y20 spliced framed file still parses', (loadstring or load)(spliced or '') ~= nil, true);
local deleted, daction = setmgrT.deleteSetText(spliced, 'Idle');
check('Y21 delete from framed file', daction, 'deleted');
local dchunk = loadWithEnv(deleted, setmetatable({ gear = STUBG }, { __index = _G }));
local dok, dsets = pcall(dchunk);
check('Y22 delete removed only the target set', dok and dsets.Dynamic.Idle == nil
    and dsets.Dynamic.Tp_Default ~= nil and dsets.Dynamic.Resting ~= nil, true);

-- the clean shim
check('Y23 shim parses', (loadstring or load)(profilesM.shimFileText()) ~= nil, true);
check('Y24 shim recognized', profilesM.isCleanShim(profilesM.shimFileText()), true);
check('Y25 a real profile is NOT a shim', profilesM.isCleanShim(JOBFILE), false);

-- the starter sets scaffold (fresh Setup + a migration that found no Dynamic
-- block): frames, parses, and holds exactly the four EMPTY base sets the
-- starter triggers target -- a new job never complains out of the box.
do
    local sframed = profilesM.frameSetsText(profilesM.starterDynText);
    local schunk = loadWithEnv(sframed, setmetatable({ gear = STUBG }, { __index = _G }));
    local sok2, ssets = pcall(schunk);
    check('Y25b starter sets scaffold parses', sok2 and type(ssets) == 'table' and type(ssets.Dynamic) == 'table', true);
    check('Y25c scaffold = the four base sets, empty', sok2
        and type(ssets.Dynamic.Idle) == 'table' and next(ssets.Dynamic.Idle) == nil
        and type(ssets.Dynamic.Tp_Default) == 'table' and type(ssets.Dynamic.Resting) == 'table'
        and type(ssets.Dynamic.Movement) == 'table', true);
end

-- the migration planner (pure): ONLY a clean shim is ever skipped (THE SETUP
-- STANDARD, 2026-07-17 -- a file with logic in it never stays live), Dynamic
-- blocks travel verbatim, an existing profile sets file is never overwritten
-- by an import, and a first backup is never overwritten (reshim = stamped copy).
local plan = profilesM.planMigration({
    { job = 'WAR', text = JOBFILE, hasBackup = false, hasProfileSets = false, hasLegacyTrig = true,  hasProfileTrig = false },
    { job = 'WHM', text = profilesM.shimFileText(), hasBackup = false, hasProfileSets = false, hasLegacyTrig = false, hasProfileTrig = false },
    { job = 'BLM', text = JOBFILE, hasBackup = true,  hasProfileSets = false, hasLegacyTrig = false, hasProfileTrig = false },
    { job = 'RDM', text = 'local x = 1; return x;', hasBackup = false, hasProfileSets = false, hasLegacyTrig = false, hasProfileTrig = false },
    { job = 'THF', text = JOBFILE, hasBackup = false, hasProfileSets = true,  hasLegacyTrig = false, hasProfileTrig = false },
    { job = 'PLD', text = profilesM.shimFileText(), hasBackup = true, hasProfileSets = true, hasLegacyTrig = false, hasProfileTrig = false },
});
check('Y26 plan: real profile migrates', plan[1].action, 'migrate');
check('Y27 plan: Dynamic block travels verbatim', plan[1].dynText, dynText);
check('Y28 plan: clean shim skipped', plan[2].action, 'skip');
check('Y29 STANDARD: backed-up file with logic in it is re-shimmed, not skipped',
      plan[3].action == 'migrate' and plan[3].reshim == true, true);
check('Y30 plan: no Dynamic block -> empty store, still migrates', plan[4].action == 'migrate' and plan[4].dynText == nil, true);
check('Y31 plan: existing profile sets file is never re-imported over', plan[5].action == 'migrate' and plan[5].dynText == nil, true);
check('Y31b plan: a shim with a backup is left alone (nothing to do)', plan[6].action, 'skip');
-- SETUP HARD RULE: whatever the flag combination, a file whose text is NOT the
-- clean shim always migrates -- no input may leave old logic live. (The skip
-- for a clean shim is equally load-bearing: migration must be idempotent.)
do
    local inputs = {};
    local texts = { JOBFILE, 'return {};', profilesM.shimFileText() };
    for t = 1, #texts do for a = 0, 1 do for b = 0, 1 do for c = 0, 1 do for d = 0, 1 do
        inputs[#inputs + 1] = { job = 'J' .. #inputs, text = texts[t],
            hasBackup = a == 1, hasProfileSets = b == 1, hasLegacyTrig = c == 1, hasProfileTrig = d == 1 };
    end end end end end
    local p2 = profilesM.planMigration(inputs);
    local rule = true;
    for i, f in ipairs(inputs) do
        local want = profilesM.isCleanShim(f.text) and 'skip' or 'migrate';
        if p2[i].action ~= want then rule = false; end
    end
    check('Y31c SETUP HARD RULE: every non-shim file migrates; every clean shim skips (48 combos)', rule, true);
end

-- missing-gear-safe sets loading (profile sharing): a reader who doesn't own
-- referenced items gets ladder HOLES (nil), a missing weapon CATEGORY resolves
-- through an empty table instead of erroring the whole file away, and items
-- the reader DOES own come back as the REAL records (identity-shared).
do
    local myGear = { Main = { Sword = { Joyeuse = { Name = 'Joyeuse' } } }, Sub = {}, Head = { Cap = { Name = 'Cap' } } };
    local g = profilesM._wrapGear(myGear);
    check('Y38 owned item is the REAL record', rawequal(g.Head.Cap, myGear.Head.Cap), true);
    check('Y39 unowned item -> nil ladder hole', g.Head.Crown, nil);
    check('Y40 missing weapon CATEGORY does not error', (pcall(function() return g.Main.Club.MapleWand_1; end)) and (g.Main.Club.MapleWand_1 == nil), true);
    check('Y41 flat Sub: missing item is nil, not a table', g.Sub.Pelte, nil);
    check('Y42 owned nested item is the REAL record', rawequal(g.Main.Sword.Joyeuse, myGear.Main.Sword.Joyeuse), true);
end

-- per-job export/import: the %q-encoded payload round trip must be byte-exact
-- (quotes, newlines, long-bracket sequences and all), and damaged/foreign
-- files must be rejected, never half-imported.
do
    local setsBlob = 'local sets = {\n    Dynamic = {\n        Idle = { Head = { gear.Head.X } },  -- "quoted" and ]==] tricky\n    },\n};\nreturn sets;\n';
    local trigBlob = 'return {\n    Default = { { when = { status = "Engaged" }, set = \'Tp_Default\' } },\n};\n';
    local ex = profilesM.buildExportText('BLU', 'Default', 'Mindie', setsBlob, trigBlob);
    local meta, perr = profilesM.parseExportText(ex);
    check('Y43 export parses back', perr, nil);
    check('Y44 export meta survives', meta ~= nil and meta.job == 'BLU' and meta.profile == 'Default' and meta.from == 'Mindie', true);
    check('Y45 sets payload is byte-exact', meta ~= nil and meta.sets, setsBlob);
    check('Y46 triggers payload is byte-exact', meta ~= nil and meta.triggers, trigBlob);
    check('Y47 sets-only export is valid', (profilesM.parseExportText(profilesM.buildExportText('WHM', 'P', 'X', setsBlob, nil))) ~= nil, true);
    check('Y48 foreign lua file rejected', (select(2, profilesM.parseExportText('return { some = "table" };'))), 'not a dlac job export');
    check('Y49 garbage rejected', (select(2, profilesM.parseExportText('this is not lua {'))), 'file does not parse');
    check('Y50 headless: importJobFile refuses politely', (select(2, profilesM.importJobFile('somefile', 'Other_1', 'Default', 'BLU'))), 'not available');
    check('Y51 headless: listExports is nil, never an error', profilesM.listExports(), nil);
end

-- lockstyle path resolution (v41, per-job-entry boxes): headless = pre-login,
-- every path is nil and the read resolver answers nil instead of erroring.
check('Y52 headless: lockstylesPath is nil pre-login', profilesM.lockstylesPath('DRK'), nil);
check('Y53 headless: legacy lockstyle tiers are nil pre-login',
      profilesM.profileLockstylesPath() == nil and profilesM.legacyLockstylesPath() == nil, true);
check('Y54 headless: readLockstylesPath is nil, never an error', profilesM.readLockstylesPath('DRK'), nil);

-- v45: the profile auto-install (LAC tick) must not LATCH before it can tell
-- whether a job has a sets file, or a login-time miss is permanent for the whole
-- session (field case 07-15: WHM logged in with an empty .Dynamic, every trigger
-- silently equipping nothing). setsPath == nil pre-login IS that "can't tell yet"
-- signal, and hasSetsFile MUST answer false rather than throw -- if either ever
-- changes, the guard silently reverts to latching on an unanswered question.
check('Y55 headless: setsPath is nil pre-login (the auto-install retry signal)',
      profilesM.setsPath('WHM'), nil);
check('Y56 headless: hasSetsFile is false pre-login, never an error',
      profilesM.hasSetsFile('WHM'), false);

-- v49: "NON" is not a job. THE login bug (field-caught 07-15, /dl instdiag showed
-- `latches=tick 1: job=NON hasSets=false`): at login GetMainJob() reads 0 = None,
-- which gData stringifies via jobs.names_abbr to "NON" -- neither '' nor '?', so a
-- guard checking only those accepted it, found no sets\NON.lua, installed nothing
-- and latched for the whole session. If jobReady ever accepts NON or a 0 id again,
-- every migrated character silently plays with an empty .Dynamic.
check('Z1 jobReady rejects job id 0 (None -- player block not ready at login)',
      dispatchM.jobReady(0, 'NON'), false);
check('Z2 jobReady rejects the "NON" STRING even if an id came through',
      dispatchM.jobReady(1, 'NON'), false);
check('Z3 jobReady rejects nil id', dispatchM.jobReady(nil, 'SAM'), false);
check('Z4 jobReady rejects empty / unknown job names',
      dispatchM.jobReady(12, '') == false and dispatchM.jobReady(12, '?') == false, true);
check('Z5 jobReady rejects a nil name (gData not ready)', dispatchM.jobReady(12, nil), false);
check('Z6 jobReady ACCEPTS a real settled job', dispatchM.jobReady(12, 'SAM'), true);
check('Z7 jobReady accepts WAR (id 1) -- a real job, not the None sentinel',
      dispatchM.jobReady(1, 'WAR'), true);

-- job export carries the lockstyles payload (optional, still "job-export v1":
-- readers that predate the field ignore it; any single payload is a valid file).
do
    local lsBlob = 'return { active = 1, onload = {}, slots = {} };';
    local ex2 = profilesM.buildExportText('DRK', 'Default', 'Mindie', nil, nil, lsBlob);
    local meta2, perr2 = profilesM.parseExportText(ex2);
    check('Y55 lockstyles-only export is valid', perr2, nil);
    check('Y56 lockstyles payload round-trips verbatim', meta2 ~= nil and meta2.lockstyles, lsBlob);
end

-- cross-character browsing/import: headless-safe (no AshitaCore -> nil answers).
check('Y34 headless: importProfile refuses politely', (select(2, profilesM.importProfile('Other_1', 'Default', 'New'))), 'not logged in');
check('Y35 headless: importProfile still validates the name first', (select(2, profilesM.importProfile('Other_1', 'Default', 'bad name'))), 'bad target name (letters/digits/_/- only)');
check('Y36 headless: listCharFolders is nil, never an error', (profilesM.listCharFolders()), nil);
check('Y37 headless: profileJobsAt empty, never an error', #profilesM.profileJobsAt('Other_1', 'Default'), 0);

-- headless migrate: refuses politely, touches nothing, never errors.
local said = {};
local mdone, mskip, mfail = profilesM.migrate(false, function(s) said[#said + 1] = s; end);
check('Y32 headless migrate is a safe no-op', mdone == 0 and mskip == 0 and mfail == 0, true);
check('Y33 headless migrate says why', #said > 0 and said[1]:find('log in first', 1, true) ~= nil, true);

-- ---------------------------------------------------------------------------
-- Z. gear export (/dl export -> gearexport.json for external tools, e.g. the
--    friend's damage simulator). The pure builders: JSON encoding (escaping,
--    scalar arrays inline, sorted object keys, integer formatting) and the
--    export walk (armor slots hold records DIRECTLY, weapon slots hold TYPE
--    BUCKETS -- both shapes; catalog gap-fill with owned-override precedence;
--    augments attached by id).
-- ---------------------------------------------------------------------------
local gx = dofile('gear/gearexport.lua');
check('Z1 json escapes quotes/backslash/newline', gx.jsonEncode('a"b\\c\n'), '"a\\"b\\\\c\\n"');
check('Z2 scalar array stays inline', gx.jsonEncode({ 1, -5, 'x', true }), '[1, -5, "x", true]');
check('Z3 object keys sorted', gx.jsonEncode({ b = 1, a = 2 }), '{\n  "a": 2,\n  "b": 1\n}');
check('Z4 integers never get a decimal point', gx.jsonEncode(276.0), '276');

local zGear = {
    Main = { Axe = { K = { Name = 'Kriegsbeil', Id = 1, Level = 70, Jobs = { 'WAR' },
                           Type = 'Axe', OneHanded = true, Stats = { DMG = 3, Delay = 276 } } } },
    Head = { H = { Name = 'Brass Cap', Id = 2, Level = 11, Jobs = { 'WAR', 'MNK' } },
             Z = { Name = 'Aketon', Id = 3, Level = 50, Jobs = { 'WAR' } } },
    NameToObject = { Kriegsbeil = { Name = 'SHOULD NOT APPEAR', Id = 99 } },
};
local zCat  = { [1] = { Stats = { DMG = 99, ACC = 5 } }, [2] = { Stats = { DEF = 4 }, Type = 'Armor' } };
local zAugs = { [1] = { 'STR+1, DEX+1' } };
local zAugStats = { [1] = { STR = 1, DEX = 1 } };
local zCounts = { [1] = 2 };   -- owned-anywhere map: two Kriegsbeil, nothing else in bags
local zExp = gx.buildExport(zGear, zCat, zAugs, zAugStats, zCounts, { character = 'Testy' });
check('Z5 both category shapes walked', zExp.itemCount, 3);
check('Z6 slot order: Main before Head', zExp.items[1].name, 'Kriegsbeil');
check('Z7 within a slot: sorted by name', zExp.items[2].name, 'Aketon');
check('Z8 owned stat overrides catalog', zExp.items[1].stats.DMG, 3);
check('Z9 catalog fills the gaps (same record)', zExp.items[1].stats.ACC, 5);
check('Z10 catalog stats for a bare record', zExp.items[3].stats.DEF, 4);
check('Z11 catalog type backfill', zExp.items[3].type, 'Armor');
check('Z12 augments attach by id', zExp.items[1].augments[1], 'STR+1, DEX+1');
check('Z13 augment stat deltas attach by id', zExp.items[1].augmentStats.STR, 1);
check('Z14 no augments -> key omitted', zExp.items[2].augments, nil);
check('Z15 meta lands at the root', zExp.character, 'Testy');
check('Z16 copy count attaches by id', zExp.items[1].count, 2);
check('Z17 scanned map, missing id -> count 0 (not owned now)', zExp.items[2].count, 0);
local zExpNC = gx.buildExport(zGear, zCat, nil, nil, nil, {});
check('Z18 no scan -> count omitted (unknown is not 0)', zExpNC.items[1].count, nil);
local zJson = gx.jsonEncode(zExp);
check('Z19 full export encodes with the format marker',
    string.find(zJson, '"format": "dlac-gear-export"', 1, true) ~= nil, true);

-- ---------------------------------------------------------------------------
-- AC. AutoAcc type automation -- entries typed autoType='AutoAcc' flatten to a
--     budgeted marker 'dlac:AutoAcc:<prio>:<acc>:<Name>|<fallback>' (utils);
--     the engine releases them against the cap surplus accwatch publishes to
--     accstate.lua (dispatch._accResolveSet). The WRITER (accwatch) ships on
--     feature/autoacc pending GM approval -- these tests cover main's dormant
--     foundation, which the branch relies on. Rules under test (Henrik
--     2026-07-14): fallback = the slot's normal pick; two typed candidates ->
--     the higher-leveled item wins; release order = removePrio desc, only as
--     far as the surplus covers; invalid/stale/missing measurement -> pieces
--     stay worn ("handle the equipment as per usual"); the budget folds
--     already-released pieces back in, so a re-measure never flaps.
-- ---------------------------------------------------------------------------
do
    TEST_PLAYER = { MainJob = 'WAR', SubJob = 'NIN', MainJobSync = 75, SubJobSync = 37 };
    AshitaCore = ashitaWithDW(true);
    local peacock = { Name = 'Peacock Charm',    Level = 33 };
    local spike   = { Name = 'Spike Necklace',   Level = 20 };
    local chiv    = { Name = 'Chivalrous Chain', Level = 60 };

    -- flatten: typed entry -> marker half, the slot's normal pick -> fallback
    local acSets = utils.BuildDynamicSets({ Dynamic = { TP = {
        Neck = { spike, { gear = peacock, autoType = 'AutoAcc', removePrio = 3, acc = 10 } },
    } } });
    check('AC1 marker + fallback', acSets.TP and acSets.TP.Neck,
        'dlac:AutoAcc:3:10:Peacock Charm|Spike Necklace');

    local acTwo = utils.BuildDynamicSets({ Dynamic = { TP = {
        Neck = { spike,
                 { gear = peacock, autoType = 'AutoAcc', removePrio = 3, acc = 10 },
                 { gear = chiv,    autoType = 'AutoAcc', removePrio = 5, acc = 8 } },
    } } });
    check('AC2 higher-leveled candidate wins the slot', acTwo.TP and acTwo.TP.Neck,
        'dlac:AutoAcc:5:8:Chivalrous Chain|Spike Necklace');

    local acBare = utils.BuildDynamicSets({ Dynamic = { TP = {
        Neck = { { gear = peacock, autoType = 'AutoAcc', removePrio = 3, acc = 10 } },
    } } });
    check('AC3 no fallback -> bare marker', acBare.TP and acBare.TP.Neck,
        'dlac:AutoAcc:3:10:Peacock Charm');

    local acDef = utils.BuildDynamicSets({ Dynamic = { TP = {
        Neck = { { gear = peacock, autoType = 'AutoAcc' } },
    } } });
    check('AC4 defaults: prio 1, acc 0', acDef.TP and acDef.TP.Neck,
        'dlac:AutoAcc:1:0:Peacock Charm');

    TEST_PLAYER = { MainJob = 'WAR', SubJob = 'NIN', MainJobSync = 20, SubJobSync = 10 };
    local acOver = utils.BuildDynamicSets({ Dynamic = { TP = {
        Neck = { spike, { gear = peacock, autoType = 'AutoAcc', removePrio = 3, acc = 10 } },
    } } });
    check('AC5 under-leveled candidate: plain fallback, no marker',
        acOver.TP and acOver.TP.Neck, 'Spike Necklace');
    TEST_PLAYER = { MainJob = 'WAR', SubJob = 'NIN', MainJobSync = 75, SubJobSync = 37 };

    -- marker parser (name deliberately LAST so any item name survives)
    local pr, ac, nm = dispatchM._parseAccMarker('dlac:AutoAcc:3:10:Peacock Charm');
    check('AC6 marker parses prio', pr, 3);
    check('AC7 marker parses acc', ac, 10);
    check('AC8 marker parses name', nm, 'Peacock Charm');
    check('AC9 other virtuals do not parse', dispatchM._parseAccMarker('dlac:AutoObi'), nil);

    -- engine decisions, driven through the accstate test seam
    local SNECK = { Neck = 'dlac:AutoAcc:3:10:Peacock Charm|Spike Necklace' };
    dispatchM._accReset();
    dispatchM._accStateOverride = nil;
    local r = dispatchM._accResolveSet(SNECK);
    check('AC10 no measurement -> piece worn', r and r.Neck, 'Peacock Charm');

    dispatchM._accStateOverride = { seq = 1, valid = true, capGap = -10 };
    r = dispatchM._accResolveSet(SNECK);
    check('AC11 over cap by its acc -> released to fallback', r and r.Neck, 'Spike Necklace');

    -- next engage measures with the charm OFF (capGap 0); the budget folds the
    -- released 10 back in, so the decision holds instead of flapping
    dispatchM._accStateOverride = { seq = 2, valid = true, capGap = 0 };
    r = dispatchM._accResolveSet(SNECK);
    check('AC12 stable across the re-measure', r and r.Neck, 'Spike Necklace');

    dispatchM._accStateOverride = { seq = 3, valid = true, capGap = 4 };
    r = dispatchM._accResolveSet(SNECK);
    check('AC13 harder mob -> piece comes back', r and r.Neck, 'Peacock Charm');

    dispatchM._accReset();
    dispatchM._accStateOverride = { seq = 4, valid = true, capGap = -8 };
    r = dispatchM._accResolveSet(SNECK);
    check('AC14 surplus below the acc -> worn', r and r.Neck, 'Peacock Charm');

    -- removal priority: HIGHER released first; the leftover budget is not
    -- enough for the second candidate
    local two = {
        Neck  = 'dlac:AutoAcc:3:10:Peacock Charm|Spike Necklace',
        Ring1 = 'dlac:AutoAcc:9:6:Woodsman Ring|Courage Ring',
    };
    dispatchM._accReset();
    dispatchM._accStateOverride = { seq = 5, valid = true, capGap = -12 };
    r = dispatchM._accResolveSet(two);
    check('AC15 higher removePrio released first', r and r.Ring1, 'Courage Ring');
    check('AC16 leftover budget too small -> worn', r and r.Neck, 'Peacock Charm');

    -- generous surplus (measured with the ring already off) -> both released
    dispatchM._accStateOverride = { seq = 6, valid = true, capGap = -20 };
    r = dispatchM._accResolveSet(two);
    check('AC17a both fit: neck released', r and r.Neck, 'Spike Necklace');
    check('AC17b both fit: ring released', r and r.Ring1, 'Courage Ring');

    -- unknown mob / no calc -> valid=false: worn as usual, release state wiped
    dispatchM._accStateOverride = { seq = 7, valid = false, capGap = 0 };
    r = dispatchM._accResolveSet(two);
    check('AC18a invalid -> neck worn as usual', r and r.Neck, 'Peacock Charm');
    check('AC18b invalid -> ring worn as usual', r and r.Ring1, 'Woodsman Ring');

    dispatchM._accStateOverride = { seq = 8, valid = true, capGap = -20, at = os.time() - 3600 };
    r = dispatchM._accResolveSet(SNECK);
    check('AC19 stale measurement (>15 min) -> worn', r and r.Neck, 'Peacock Charm');

    dispatchM._accReset();
    dispatchM._accStateOverride = { seq = 9, valid = true, capGap = -50 };
    r = dispatchM._accResolveSet({ Neck = 'dlac:AutoAcc:3:10:Peacock Charm' });
    check('AC20 no fallback -> never released', r and r.Neck, 'Peacock Charm');

    r = dispatchM._accResolveSet({ Neck = 'dlac:AutoAcc:3:0:Peacock Charm|Spike Necklace' });
    check('AC21 zero acc -> never released', r and r.Neck, 'Peacock Charm');

    check('AC22 set without markers -> nil (no decisions)',
        dispatchM._accResolveSet({ Neck = 'Spike Necklace' }), nil);

    -- serializer: the wrapper carries the type fields through a Commit
    local acSer = table.concat(setmgr.renderSetLines('T', {
        { name = 'Neck', items = {
            { path = 'gear.Neck.PeacockCharm', autoType = 'AutoAcc', removePrio = 3, acc = 10 },
        } },
    }), '\n');
    check('AC23 serializes autoType', acSer:find('autoType = "AutoAcc"', 1, true) ~= nil, true);
    check('AC24 serializes removePrio + acc', acSer:find('removePrio = 3, acc = 10', 1, true) ~= nil, true);

    dispatchM._accStateOverride = nil;
    dispatchM._accReset();
end

-- (The accwatch custom-mob family tests -- section AD -- live on
--  feature/autoacc with accwatch.lua/accdata.lua, pending GM approval.)

-- ---------------------------------------------------------------------------
-- AE. per-set stat-weight memory (gearoptim.bindSetWeights) -- every set owns
--     its weights; a never-bound set starts BLANK; the SHARED (no-set) table
--     is a DEAD CONCEPT (Henrik 2026-07-17: "we start blank, have weights per
--     set and can save -- delete it"): unbound reads are empty, unbound edits
--     are refused, nothing unbound persists. Switching sets never carries
--     another set's edits along (Henrik's isolation rule). Headless:
--     weightsPath() is nil, so persistence no-ops here.
-- ---------------------------------------------------------------------------
check('AE1 unbound edit refused (the shared table is gone)', optim.setWeight('Accuracy', 20, 60), false);
check('AE2 nothing bound yet', optim.weightsBoundTo(), nil);
check('AE2b unbound weights read empty', next(optim.getWeights()), nil);
check('AE3 first bind reports a change', optim.bindSetWeights('DRK', 'Midshort'), true);
check('AE4 first bind starts BLANK', optim.getWeights()['Accuracy'], nil);
check('AE4b bound edits are accepted', optim.setWeight('STR', 5), true);
optim.setWeight('Accuracy', 99);
check('AE5 rebind of the same key is a no-op', optim.bindSetWeights('DRK', 'Midshort'), false);
optim.bindSetWeights('DRK', 'Tp_Default');
check('AE6 second set starts BLANK too (not the last-used set)', optim.getWeights()['Accuracy'], nil);
check('AE7 second set did not inherit the STR edit', optim.getWeights()['STR'], nil);
optim.bindSetWeights('DRK', 'Midshort');
check('AE8 re-selecting a set gets its own edits back', optim.getWeights()['Accuracy'].perUnit, 99);
check('AE9 ...including added stats', optim.getWeights()['STR'].perUnit, 5);
check('AE10 unbinding empties the active view', (optim.bindSetWeights(nil, nil) == true)
    and next(optim.getWeights()), nil);
check('AE11 ...and refuses edits again', optim.setWeight('VIT', 1), false);
check('AE12 pre-login job "?" never creates a binding', optim.bindSetWeights('?', 'AnySet'), false);
check('AE13 ...and stays unbound', optim.weightsBoundTo(), nil);
optim.bindSetWeights('DRK', 'Midshort');
check('AE14 score() follows the binding', optim.score({ Accuracy = 1 }), 99);
optim.bindSetWeights(nil, nil);
check('AE15 unbound score() is 0 (nothing is weighted)', optim.score({ Accuracy = 1 }), 0);

-- ---------------------------------------------------------------------------
-- AS. per-set build-slot mask (the weights window's 4x4 grid): which slots
--     Auto-build FILLS. Same per-set binding + gearweights.lua persistence as
--     the weights; a never-bound set starts from the FIXED default (weapons
--     unmarked -- the old Skip-weapons ON state); unbound the mask READS as
--     that default and refuses edits (no shared mask anymore).
-- ---------------------------------------------------------------------------
(function()
    optim.bindSetWeights(nil, nil);
    local dm = optim.getSlotMask();
    check('AS1 default: Main unmarked',  dm.Main,  nil);
    check('AS2 default: Sub unmarked',   dm.Sub,   nil);
    check('AS3 default: Range unmarked', dm.Range, nil);
    check('AS4 default: Ammo MARKED (ammo trinkets are real picks)', dm.Ammo, true);
    check('AS5 default: all 12 armor slots marked', (dm.Head and dm.Neck and dm.Ear1
        and dm.Ear2 and dm.Body and dm.Hands and dm.Ring1 and dm.Ring2 and dm.Back
        and dm.Waist and dm.Legs and dm.Feet) == true, true);
    check('AS6 unknown label rejected', (optim.setSlotEnabled('Helmet', true)), false);
    check('AS7 unbound mark edit refused (no shared mask)', optim.setSlotEnabled('Main', true), false);
    optim.bindSetWeights('DRK', 'GridSet');
    check('AS8 first bind starts from the DEFAULT mask', optim.getSlotMask().Main, nil);
    optim.setSlotEnabled('Main', true);
    optim.setSlotEnabled('Head', false);
    check('AS9 set edit sticks to the set', optim.getSlotMask().Head, nil);
    optim.bindSetWeights(nil, nil);
    check('AS10 unbound view is back on the pristine default', optim.getSlotMask().Head, true);
    check('AS11 ...Main included', optim.getSlotMask().Main, nil);
    optim.bindSetWeights('DRK', 'GridSet');
    check('AS12 re-selecting the set gets its marks back', optim.getSlotMask().Main, true);

    -- Round-trip through a real file (weightsPath overridden; headless it's nil).
    local _wp = optim.weightsPath;
    local _tmp = 'tests_tmp_gearweights.lua';
    optim.weightsPath = function() return _tmp; end
    optim.setWeight('Accuracy', 11);                        -- a bound edit rides along
    check('AS13 save writes the masks', optim.saveWeights(), true);
    optim.setSlotEnabled('Main', false);                    -- diverge memory from disk
    optim.setSlotEnabled('Head', true);
    check('AS14 load restores the per-set mask', (optim.loadWeights() == true)
        and optim.getSlotMask().Main, true);
    check('AS15 ...every saved mark', optim.getSlotMask().Head, nil);
    check('AS16 ...and the weights beside it', optim.getWeights()['Accuracy'].perUnit, 11);
    -- Legacy FLAT file: it was ONLY the dead shared table -- loads clean,
    -- contributes nothing.
    local f = io.open(_tmp, 'w');
    f:write('return { ["Accuracy"] = { perUnit = 7 } }\n');
    f:close();
    check('AS17 legacy flat file loads clean', optim.loadWeights(), true);
    check('AS18 legacy: dead shared content is DROPPED', optim.getWeights()['Accuracy'], nil);
    check('AS19 legacy: mask falls back to the default', optim.getSlotMask().Main, nil);
    check('AS20 legacy: ...armor still marked', optim.getSlotMask().Body, true);
    -- An old STRUCTURED file: its shared/slotsShared sections are ignored, the
    -- per-set payload survives.
    f = io.open(_tmp, 'w');
    f:write('return { shared = { ["Evasion"] = { perUnit = 9 } }, slotsShared = { "Main" },'
        .. ' perSet = { ["DRK|GridSet"] = { ["STR"] = { perUnit = 2 } } } }\n');
    f:close();
    check('AS21 old structured file loads clean', optim.loadWeights(), true);
    check('AS22 ...its per-set weights survive', optim.getWeights()['STR'].perUnit, 2);
    check('AS23 ...its shared section is dropped', optim.getWeights()['Evasion'], nil);
    os.remove(_tmp);
    optim.weightsPath = _wp;
    optim.bindSetWeights(nil, nil);
end)();

-- ---------------------------------------------------------------------------
-- AW. weights "copy from" (optim.copyWeightsFrom): copy another stored table's
--     weights + build-slot mask into the ACTIVE binding. Source untouched;
--     active-table identity preserved (they alias _shared/_perSet entries).
-- ---------------------------------------------------------------------------
(function()
    optim.bindSetWeights('DRK', 'CopySrc');
    optim.setWeight('Accuracy', 42, 60);
    optim.setSlotEnabled('Main', true);
    optim.bindSetWeights('DRK', 'CopyDst');
    optim.setWeight('STR', 3);
    check('AW1 dst starts with its own table',  optim.getWeights()['Accuracy'], nil);
    check('AW2 copy succeeds',                  optim.copyWeightsFrom('DRK|CopySrc'), true);
    check('AW3 weights copied',                 optim.getWeights()['Accuracy'].perUnit, 42);
    check('AW4 cap rides along',                optim.getWeights()['Accuracy'].cap, 60);
    check('AW5 dst extras cleared',             optim.getWeights()['STR'], nil);
    check('AW6 slot mask copied',               optim.getSlotMask().Main, true);
    optim.setWeight('Accuracy', 1);                          -- edit the COPY only
    optim.bindSetWeights('DRK', 'CopySrc');
    check('AW7 source untouched',               optim.getWeights()['Accuracy'].perUnit, 42);
    check('AW8 self-copy refused',              optim.copyWeightsFrom('DRK|CopySrc'), false);
    check('AW9 unknown source refused',         optim.copyWeightsFrom('DRK|NoSuch'), false);
    check('AW10 the dead shared source is refused', optim.copyWeightsFrom(nil), false);
    optim.bindSetWeights(nil, nil);
    check('AW11 unbound copy refused (nothing to copy into)', optim.copyWeightsFrom('DRK|CopySrc'), false);
end)();

-- ---------------------------------------------------------------------------
-- AWN. named weight profiles ("Saved Sets") + the copy-undo snapshot -- the
--      cascading copy-from menu's backend: save a tuning under a proper name,
--      copy it anywhere, revert a binding to its pre-first-copy state, and
--      round-trip the named store through gearweights.lua.
-- ---------------------------------------------------------------------------
(function()
    optim.bindSetWeights('DRK', 'CopySrc');
    check('AWN1 save named trims + succeeds', (optim.saveNamedWeights('  Awesome Melee  ')), true);
    check('AWN2 named key listed', optim.namedKeys()[1], 'Awesome Melee');
    optim.bindSetWeights('DRK', 'CopyDst');
    check('AWN3 copy from named', optim.copyWeightsFromNamed('Awesome Melee'), true);
    check('AWN4 named weights land', optim.getWeights()['Accuracy'].perUnit, 42);
    check('AWN5 named mask lands', optim.getSlotMask().Main, true);
    check('AWN6 revert restores the PRE-FIRST-COPY table',
        (optim.revertCopiedWeights() == true) and (optim.getWeights()['STR'] or {}).perUnit, 3);
    check('AWN7 unknown named refused', optim.copyWeightsFromNamed('NoSuch'), false);
    local _wp = optim.weightsPath;
    local _tmp = 'tests_tmp_gearweights2.lua';
    optim.weightsPath = function() return _tmp; end
    optim.saveWeights();
    optim.deleteNamedWeights('Awesome Melee');
    check('AWN8 delete named', #optim.namedKeys(), 0);
    check('AWN9 load restores named', (optim.loadWeights() == true) and optim.namedKeys()[1], 'Awesome Melee');
    check('AWN10 ...with its weights', optim.peekWeights('named', 'Awesome Melee')['Accuracy'].perUnit, 42);
    os.remove(_tmp);
    optim.weightsPath = _wp;
    optim.deleteNamedWeights('Awesome Melee');               -- leave the store clean
    optim.bindSetWeights(nil, nil);
end)();

-- ---------------------------------------------------------------------------
-- AP. priority-list mode (the "simple" weights, 2026-07-17) -- an ORDERED
--     stat list with optional caps. Scoring derives dominance weights (one
--     point of a higher stat outranks everything below it combined), so the
--     whole existing pipeline -- score, optimizePicks, Auto-build -- runs
--     unchanged. Own per-set + named stores (never mixes with point
--     templates); the MODE flips to whichever editor's data you mutate.
-- ---------------------------------------------------------------------------
(function()
    -- unbound: priority reads empty and refuses edits (no shared list)
    optim.bindSetWeights(nil, nil);
    check('AP1 unbound mode reads points', optim.weightsMode(), 'points');
    check('AP2 unbound prio list reads empty', #optim.getPrio(), 0);
    check('AP2b unbound prio edit refused', optim.prioAdd('Accuracy', 10), false);
    check('AP2c unbound mode set refused', optim.setWeightsMode('priority'), false);

    -- mode + derivation basics, on a bound set
    optim.bindSetWeights('DRK', 'PrioMain');
    check('AP3 add flips the mode', (optim.prioAdd('Accuracy', 10) == true) and optim.weightsMode(), 'priority');
    optim.prioAdd('STR');
    check('AP4 dup add refused', optim.prioAdd('Accuracy'), false);
    check('AP5 getWeights is now the DERIVED table', optim.getWeights()['STR'].perUnit, 1);
    check('AP6 higher rank dominates: 1 Accuracy beats 400 STR',
        optim.score({ Accuracy = 1 }) > optim.score({ STR = 400 }), true);
    check('AP7 the cap clamps per item', optim.score({ Accuracy = 50 }), optim.score({ Accuracy = 10 }));
    check('AP8 a points edit flips the mode back', (optim.setWeight('VIT', 2) == true) and optim.weightsMode(), 'points');
    check('AP9 ...and scoring follows', optim.score({ VIT = 1 }), 2);
    optim.clearWeight('VIT');
    optim.setWeightsMode('priority');
    check('AP10 explicit mode set works', optim.weightsMode(), 'priority');

    -- reorder + caps + remove
    optim.prioMove(2, -1);                 -- STR above Accuracy now
    check('AP11 move reorders', optim.getPrio()[1].stat, 'STR');
    check('AP12 dominance follows the order', optim.score({ STR = 1 }) > optim.score({ Accuracy = 10 }), true);
    optim.prioSetCap(1, 30);
    check('AP13 cap edit lands', optim.getPrio()[1].cap, 30);
    optim.prioSetCap(1, 0);
    check('AP14 cap 0 clears it', optim.getPrio()[1].cap, nil);
    check('AP15 remove drops the row', (optim.prioRemove(1) == true) and optim.getPrio()[1].stat, 'Accuracy');

    -- per-set isolation + blank seeding (the same rules the weights follow)
    optim.bindSetWeights('DRK', 'PrioSet');
    check('AP16 new binding starts with a blank list', #optim.getPrio(), 0);
    check('AP17 ...and points mode', optim.weightsMode(), 'points');
    optim.prioAdd('Evasion');
    optim.bindSetWeights('DRK', 'PrioMain');
    check('AP18 first set\'s list untouched by the other\'s edits', optim.getPrio()[1].stat, 'Accuracy');
    check('AP19 ...and keeps its own mode', optim.weightsMode(), 'priority');
    optim.bindSetWeights('DRK', 'PrioSet');
    check('AP20 re-selecting the set gets its list back', optim.getPrio()[1].stat, 'Evasion');
    check('AP21 ...and its mode', optim.weightsMode(), 'priority');

    -- named store ("Saved Lists") + copy + revert; separate from point saves
    check('AP22 save named list trims + succeeds', (optim.savePrioNamed('  Heal Prio  ')), true);
    check('AP23 named key listed', optim.prioNamedKeys()[1], 'Heal Prio');
    check('AP24 prio saves never appear among point templates', #optim.namedKeys(), 0);
    optim.bindSetWeights('DRK', 'PrioDst');
    optim.prioAdd('MND');
    check('AP25 copy from named replaces the list', (optim.copyPrioFromNamed('Heal Prio') == true)
        and optim.getPrio()[1].stat, 'Evasion');
    check('AP26 revert restores the pre-copy list', (optim.revertCopiedPrio() == true)
        and optim.getPrio()[1].stat, 'MND');
    check('AP27 unknown named refused', optim.copyPrioFromNamed('NoSuch'), false);
    check('AP28 copy from a per-set list', (optim.copyPrioFrom('DRK|PrioSet') == true)
        and optim.getPrio()[1].stat, 'Evasion');
    check('AP29 self-copy refused', optim.copyPrioFrom('DRK|PrioDst'), false);

    -- clear (snapshots like a copy, so revert works after a mis-click)
    optim.bindSetWeights('DRK', 'PrioSet');
    check('AP30 clear empties the list', (optim.prioClear() == true) and #optim.getPrio(), 0);
    check('AP31 revert brings a cleared list back', (optim.revertCopiedPrio() == true)
        and optim.getPrio()[1].stat, 'Evasion');

    -- the joint optimizer follows priority mode (weights=nil resolves through it)
    local res = optim.optimizePicks({
        Head = {
            { stats = { STR = 400 },   ref = 'strhat' },
            { stats = { Evasion = 1 }, ref = 'evahat' },
        },
    }, nil, {});
    check('AP32 optimizePicks obeys the priority order', res.picks.Head, 2);

    -- persistence round-trip (all prio sections + modes)
    local _wp = optim.weightsPath;
    local _tmp = 'tests_tmp_gearweights3.lua';
    optim.weightsPath = function() return _tmp; end
    check('AP33 save writes the prio sections', optim.saveWeights(), true);
    optim.prioClear();                      -- diverge memory from disk
    optim.deletePrioNamed('Heal Prio');
    optim.setWeightsMode('points');
    check('AP34 load restores the per-set list', (optim.loadWeights() == true)
        and optim.getPrio()[1].stat, 'Evasion');
    check('AP35 ...the mode', optim.weightsMode(), 'priority');
    check('AP36 ...and the named store', optim.peekPrio('named', 'Heal Prio')[1].stat, 'Evasion');
    -- a pre-priority file (no prio/mode sections) loads as all-points, empty lists
    local f = io.open(_tmp, 'w');
    f:write('return { perSet = { ["DRK|PrioSet"] = { ["MND"] = { perUnit = 4 } } } }\n');
    f:close();
    check('AP37 pre-priority file: points mode', (optim.loadWeights() == true) and optim.weightsMode(), 'points');
    check('AP38 pre-priority file: empty prio list', #optim.getPrio(), 0);
    os.remove(_tmp);
    optim.weightsPath = _wp;

    optim.bindSetWeights(nil, nil);                          -- leave the module unbound
end)();

-- ---------------------------------------------------------------------------
-- AF. craft Sub-vs-Main guard (dispatch.craftMainGuard + the equipResolved
--     post-pass) -- while the craft overlay owns Sub with no Main of its own,
--     a set Main that can't PAIR with that Sub (subSlotAllowed) is HELD out of
--     the dispatch (field case: Kupo Shield vs a scythe knocking each other
--     off every pass). Stateless: overlay gone -> Main dispatches again.
-- ---------------------------------------------------------------------------
package.loaded['dlac\\utils'] = utils;   -- the guard resolves pairing through utils
local gearT = package.loaded['dlac\\gear'];
gearT.NameToObject['Kupo Shield']  = { Name = 'Kupo Shield',  Type = 'Sub' };   -- catalog vocab: Sub + name -> Shield
gearT.NameToObject['Death Scythe'] = { Name = 'Death Scythe', Type = 'Great Scythe', OneHanded = false };
gearT.NameToObject['Parry Knife']  = { Name = 'Parry Knife',  Type = 'Dagger', OneHanded = true };
gearT.NameToObject['Cat Baghnakhs'] = { Name = 'Cat Baghnakhs', Type = 'Hand-to-Hand', OneHanded = true };   -- H2H, the FIELD shape: the catalog lied OneHanded=true (/dl fix backfilled it) -- Type must decide the hold
utils._resetNameIndex();

local guard = dispatchM._craftMainGuard({ Sub = 'Kupo Shield', Hands = 'Weaver Gloves' });
check('AF1 guard built when the overlay has Sub but no Main', guard ~= nil, true);
check('AF2 a 2H Main is held', guard('Death Scythe'), true);
check('AF3 a 1H Main pairs fine and passes', guard('Parry Knife'), false);
check('AF4 an H2H Main is held', guard('Cat Baghnakhs'), true);
check('AF5 an unknown Main name is left alone', guard('Mystery Club'), false);
check('AF6 no guard when the overlay brings its own Main',
    dispatchM._craftMainGuard({ Sub = 'Kupo Shield', Main = 'Parry Knife' }), nil);
check('AF7 no guard when the overlay has no Sub',
    dispatchM._craftMainGuard({ Hands = 'Weaver Gloves' }), nil);

-- the equipResolved post-pass: the offending Main is dropped, everything else kept
local afNote, afTbl = dispatchM._equipResolved({ Main = 'Death Scythe', Body = 'Weaver Apron' },
    { craftMainGuard = guard });
check('AF8 offending Main held out of the equip', afTbl.Main, nil);
check('AF9 the rest of the set is untouched', afTbl.Body, 'Weaver Apron');
check('AF10 the hold is traced for /dl why', string.find(afNote, 'HELD', 1, true) ~= nil, true);
local _, afTbl2 = dispatchM._equipResolved({ Main = 'Parry Knife' }, { craftMainGuard = guard });
check('AF11 a pairable Main equips normally', afTbl2.Main, 'Parry Knife');
local _, afTbl3 = dispatchM._equipResolved({ Main = 'Death Scythe' }, {});
check('AF12 no guard, no hold (craft off)', afTbl3.Main, 'Death Scythe');

-- ---------------------------------------------------------------------------
-- LK. slot locks -- what the Sets tab's "Equip & Lock" (/dl lock set) rests on:
--     setLock('all') flips every slot, and equipResolved strips locked slots,
--     so the engine leaves server-locked (Incursion T3) gear alone.
-- ---------------------------------------------------------------------------
check('LK1 lock all reports ON', dispatchM.setLock('all', true), true);
local lkN = 0;
for _ in pairs(dispatchM.locks) do lkN = lkN + 1; end
check('LK2 all 16 slots locked', lkN, 16);
local lkNote, lkTbl = dispatchM._equipResolved({ Main = 'Death Scythe', Body = 'Weaver Apron' }, {});
check('LK3 a locked slot is stripped (kept as worn)', lkTbl.Main, nil);
check('LK4 every locked slot is stripped', lkTbl.Body, nil);
check('LK5 the strip is traced for /dl why', string.find(lkNote, 'LOCKED', 1, true) ~= nil, true);
check('LK6 unknown slot names refuse', dispatchM.setLock('incursion'), nil);
check('LK7 unlock all reports OFF', dispatchM.setLock('all', false), false);
check('LK8 no locks left behind', next(dispatchM.locks), nil);
local _, lkTbl2 = dispatchM._equipResolved({ Body = 'Weaver Apron' }, {});
check('LK9 an unlocked slot equips again', lkTbl2.Body, 'Weaver Apron');

-- ---------------------------------------------------------------------------
-- AG. lockstyle sets -- dispatch._lockstyleFrom picks the box and reduces it
--     to what gFunc.LockStyle takes; lockstyle.lua's serializer round-trips.
-- ---------------------------------------------------------------------------
local lsT = {
    active = 2,
    onload = { DRK = 2 },
    slots = {
        [1] = { name = 'AF Glam', set = { Main = 'Kris', Head = 'Ducal Guard\'s Ribbon', Body = 'remove' } },
        [2] = { name = '',        set = { Body = 'Weaver Apron' } },
        [3] = { name = 'Broken',  set = { Head = 42, Body = '' } },   -- nothing usable
    },
};
local g1, n1, b1 = dispatchM._lockstyleFrom(lsT, 1);
check('AG1 explicit box wins', b1, 1);
check('AG2 slot names ride', g1.Main, 'Kris');
check('AG3 the remove literal rides too', g1.Body, 'remove');
check('AG4 box name returned', n1, 'AF Glam');
local g2, n2, b2 = dispatchM._lockstyleFrom(lsT, nil);
check('AG5 no box arg -> the marked (active) box', b2, 2);
check('AG6 unnamed box falls back to "box N"', n2, 'box 2');
check('AG7 non-string and empty values are dropped', (dispatchM._lockstyleFrom(lsT, 3)), nil);
check('AG8 empty box says so', select(2, dispatchM._lockstyleFrom(lsT, 9)), 'lockstyle box 9 is empty');
check('AG9 no file/table says so', select(2, dispatchM._lockstyleFrom(nil)), 'no lockstyle sets saved yet');

-- serializer round-trip (lockstyle.lua is addon-state UI but its serializer is pure)
local lockstyleM = dofile('feature/lockstyle.lua');
local lsText = lockstyleM._serialize(lsT);
local lsChunk = (loadstring or load)(lsText);
check('AG10 serialized file parses', lsChunk ~= nil, true);
local lsBack = lsChunk();
check('AG11 active survives', lsBack.active, 2);
check('AG12 onload survives', lsBack.onload.DRK, 2);
check('AG13 set entries survive', lsBack.slots[1].set.Main, 'Kris');
check('AG14 quoting survives an apostrophe', lsBack.slots[1].set.Head, 'Ducal Guard\'s Ribbon');
check('AG15 round-trip feeds _lockstyleFrom', (dispatchM._lockstyleFrom(lsBack, 1)).Main, 'Kris');
-- (AG16-AG20 tested the v39 equip-preview plan; removed with it in v42 --
--  the preview paints the LOOK now, see the AI section.)

-- onload is PER JOB ENTRY on save (v42): the v41 migration serialized the whole
-- v40 onload map into every job file it touched; those cross-job copies are
-- never read for the file's own job, but they RESURFACE through the fallback
-- tiers (a job with no entry falls back to a file whose onload names it --
-- field: DRG=1 from box-1 "test" leaked into every file). Saves scrub it.
check('AG16 _entryData exported', type(lockstyleM._entryData), 'function');
if type(lockstyleM._entryData) == 'function' then
    local ed = lockstyleM._entryData({ active = 3, slots = { [1] = { name = 'x', set = {} } },
                                       onload = { DRK = 3, DRG = 1, WHM = 2 } }, 'DRK');
    check('AG17 entry keeps its OWN onload binding', ed.onload.DRK, 3);
    check('AG18 entry drops other jobs\' bindings', ed.onload.DRG == nil and ed.onload.WHM == nil, true);
    check('AG19 boxes and active ride unchanged', ed.active == 3 and ed.slots[1].name == 'x', true);
    local ed2 = lockstyleM._entryData({ active = 1, slots = {}, onload = { DRG = 1 } }, 'DRK');
    check('AG20 no own binding -> empty onload', next(ed2.onload), nil);
end

-- ---------------------------------------------------------------------------
-- AH. lockstyle picker: you can lockstyle to ANYTHING you own
--
--    RULE (Henrik, 2026-07-20 -- REVISES the 07-15 "anything you own" rule,
--    which was too OPEN): the picker offers gear ONE of your jobs can wear at
--    its CURRENT level -- the server's canEquipItemOnAnyJob (charutils.cpp:2591,
--    getReqLvl() <= jobs.job[i]). We mirror it via GetJobLevel, which reads that
--    same current level, so it is PRESTIGE-CORRECT: a DE-LEVELED THF's gear
--    drops out. Not the OLD current-job-only filter (too tight) and not
--    anything-owned (too loose) -- the middle. It FAILS OPEN on a nil levels
--    read (pre-login): offer everything, never hide it all (the Save-gate
--    lesson). Ownership is a SEPARATE axis, still gated only at Save. Supersedes
--    [[lockstyle-anything-you-own]]; the engine's _lsStyleGate (AJ) is the same
--    gate, and the LOOK preview (AI) still renders anything.
-- ---------------------------------------------------------------------------
local savedGear = package.loaded['dlac\\gear'];
package.loaded['dlac\\gear'] = {
    NameToObject = {},
    Head = {
        Onjob     = { Name = 'Onjob Cap',     Level = 1,  Jobs = { 'WHM' } },
        Wrongjob  = { Name = 'Wrongjob Cap',  Level = 1,  Jobs = { 'BLM' } },
        Highlevel = { Name = 'Highlevel Cap', Level = 99, Jobs = { 'WHM' } },
        Wrongboth = { Name = 'Wrongboth Cap', Level = 99, Jobs = { 'BLM' } },
        Anyjob    = { Name = 'Anyjob Cap',    Level = 1,  Jobs = { 'All' } },
        Thief     = { Name = 'Thief Cap',     Level = 50, Jobs = { 'THF' } },   -- the prestige case
    },
    Main = {   -- Main/Range nest one level deeper, by skill category
        Sword      = { Offsword = { Name = 'Offjob Sword', Level = 75, Jobs = { 'DRK' }, OneHanded = true } },
        GreatSword = { Big      = { Name = 'Big Blade',    Level = 70, Jobs = { 'DRK' }, OneHanded = false } },
    },
    Sub = {
        Targe = { Name = 'Test Targe', Level = 30, Jobs = { 'All' } },
    },
};
-- lockstyle captures gear as a load-time upvalue, so the fixture only has to be
-- in place across the dofile; restoring right after keeps the other sections' gear
-- table (section G's 'Solid Wand' etc.) untouched.
local lockstyleM = dofile('feature/lockstyle.lua');
package.loaded['dlac\\gear'] = savedGear;

check('AH0 _listFor exported', type(lockstyleM._listFor), 'function');
if type(lockstyleM._listFor) == 'function' then
    -- You have WHM 50, THF 30 (prestige-lowered), DRK 80. No BLM.
    local JL = { WHM = 50, THF = 30, DRK = 80 };
    local function offered(slot, jl, q)
        local set = {};
        for _, rec in ipairs(lockstyleM._listFor(slot, q or '', false, jl)) do set[rec.Name] = true; end
        return set;
    end
    local head = offered('Head', JL);
    check('AH1 wrong-job item NOT offered (no BLM)',      head['Wrongjob Cap'],  nil);
    check('AH2 under-level item NOT offered (WHM 50<99)', head['Highlevel Cap'], nil);
    check('AH3 wrong-job AND under-level NOT offered',    head['Wrongboth Cap'], nil);
    check('AH4 on-job item offered (WHM 50>=1)',          head['Onjob Cap'],     true);
    check('AH5 All-jobs item offered (some job >=1)',     head['Anyjob Cap'],    true);
    check('AH5b PRESTIGE: de-leveled THF gear NOT offered (THF 30<50)', head['Thief Cap'], nil);
    check('AH6 picker offers only wearable gear (2 of 6)', #lockstyleM._listFor('Head', '', false, JL), 2);
    check('AH7 any-job gear offered when a job IS at level (DRK 80 >= sword 75)',
        offered('Main', JL)['Offjob Sword'], true);
    -- FAIL OPEN: a nil levels read (pre-login) offers EVERYTHING, never hides it.
    check('AH8 FAIL-OPEN: nil levels offers all 6',       #lockstyleM._listFor('Head', '', false, nil), 6);
    check('AH9 search still narrows by name (fail-open)', #lockstyleM._listFor('Head', 'wrongjob', false, nil), 1);
    check('AH10 unknown slot -> empty, no error',         #lockstyleM._listFor('Nope', '', false, JL), 0);
    -- Sub still merges dual-wield 1H offhands from Main, now also gated.
    local sub = offered('Sub', JL);
    check('AH11 native Sub item offered (Targe Lv30, WHM 50>=30)', sub['Test Targe'],   true);
    check('AH12 DW: a 1H DRK weapon offered in Sub (DRK 80>=75)',  sub['Offjob Sword'], true);
    check('AH13 a 2H weapon is NOT offered in Sub',               sub['Big Blade'],    nil);
    check('AH14 Main list has no Sub bleed-back',                 offered('Main', JL)['Test Targe'], nil);
    -- the pure gate (jobgate.canEquip) itself:
    local jg = dofile('gear/jobgate.lua');
    check('AH15 canEquip: on-job at level',               jg.canEquip({ Jobs = { 'THF' }, Level = 30 }, { THF = 30 }), true);
    check('AH16 canEquip: on-job UNDER level (prestige)', jg.canEquip({ Jobs = { 'THF' }, Level = 50 }, { THF = 30 }), false);
    check('AH17 canEquip: All jobs, any at level',        jg.canEquip({ Jobs = { 'All' }, Level = 40 }, { WHM = 50 }), true);
    check('AH18 canEquip: no such job of yours',          jg.canEquip({ Jobs = { 'BLM' }, Level = 1 }, { WHM = 50 }), false);
    check('AH19 canEquip: no Jobs data -> pass',          jg.canEquip({ Level = 99 }, { WHM = 1 }), true);
    -- box gate: a box with a piece no job can wear is flagged (the offending name).
    local resolve = function(nm) return ({
        ['Thief Cap'] = { Name = 'Thief Cap', Level = 50, Jobs = { 'THF' } },
        ['Onjob Cap'] = { Name = 'Onjob Cap', Level = 1,  Jobs = { 'WHM' } } })[nm]; end
    check('AH20 box with a de-leveled piece -> flagged',  lockstyleM._boxBadPiece({ Head = 'Thief Cap' }, JL, resolve), 'Thief Cap');
    check('AH21 box all-wearable -> nil',                 lockstyleM._boxBadPiece({ Head = 'Onjob Cap' }, JL, resolve), nil);
    check('AH22 box gate FAILS OPEN (nil levels)',        lockstyleM._boxBadPiece({ Head = 'Thief Cap' }, nil, resolve), nil);
end

-- ---------------------------------------------------------------------------
-- AI. lockstyle LOOK preview: entity look_t plan (v42)
--
--    The preview writes the player's look_t instead of equipping, because the
--    picker offers gear a job of yours can wear (see AH) -- often off your
--    CURRENT job -- and LAC will never equip an off-job piece to show it. Bases are the SDK's (plugins/sdk/ffxi/entity.h:
--    "Head Armor (Starts at 0x1000)" ... Ranged 0x8000); the stored value is
--    base + model id, so base alone = nothing in the slot.
-- ---------------------------------------------------------------------------
local lookM = dofile('feature/lookpreview.lua');
check('AI0 _plan exported', type(lookM._plan), 'function');
if type(lookM._plan) == 'function' then
    local MODELS = { ["Arhat's Gi"] = 13, ['Kris'] = 7, ['Warp Ring'] = 0, ['Buckler'] = 5, ['Shuriken'] = 9 };
    local function modelOf(n) return MODELS[n]; end
    local plan = lookM._plan;

    -- the eight slots FFXI renders, each on its own base:
    check('AI1 body -> 0x2000 + model', plan({ Body = "Arhat's Gi" }, modelOf).Body, 0x2000 + 13);
    check('AI2 main -> 0x6000 + model', plan({ Main = 'Kris' }, modelOf).Main, 0x6000 + 7);
    check('AI3 sub  -> 0x7000 + model', plan({ Sub = 'Buckler' }, modelOf).Sub, 0x7000 + 5);
    -- dlac says Range, look_t says Ranged:
    check('AI4 Range maps to the Ranged field', plan({ Range = 'Kris' }, modelOf).Ranged, 0x8000 + 7);
    check('AI5 Range does NOT create a Range field', plan({ Range = 'Kris' }, modelOf).Range, nil);

    -- HARD RULE (AH) in look form: an off-job piece plans exactly like any other.
    -- The old preview could not render this; that is why this module exists.
    check('AI6 off-job piece plans normally', plan({ Body = "Arhat's Gi" }, modelOf).Body, 0x2000 + 13);

    -- 'remove' = LAC's "show nothing in this slot" -> the bare base:
    check('AI7 remove -> bare base', plan({ Head = 'remove' }, modelOf).Head, 0x1000);

    -- no model id -> DROPPED, never zeroed. An accessory (Model absent in the
    -- catalog) must not blank a slot; Warp Ring is Model 0 and Ring has no field.
    check('AI8 unknown name is dropped', plan({ Body = 'No Such Item' }, modelOf).Body, nil);
    check('AI9 model 0 is dropped, not zeroed', plan({ Head = 'Warp Ring' }, modelOf).Head, nil);
    check('AI10 non-look slot (Neck) ignored', plan({ Neck = 'Kris' }, modelOf).Neck, nil);

    -- Ammo has no look_t field: a thrown weapon renders in Ranged, but only when
    -- no real ranged weapon claims the slot.
    check('AI11 Ammo fills Ranged when Range is empty', plan({ Ammo = 'Shuriken' }, modelOf).Ranged, 0x8000 + 9);
    check('AI12 a real Range weapon beats Ammo',
        plan({ Ammo = 'Shuriken', Range = 'Kris' }, modelOf).Ranged, 0x8000 + 7);

    -- shape / robustness:
    local full = plan({ Head = 'remove', Body = "Arhat's Gi", Main = 'Kris' }, modelOf);
    local n = 0; for _ in pairs(full) do n = n + 1; end
    check('AI13 plans only the named slots', n, 3);
    local e1 = 0; for _ in pairs(plan({}, modelOf)) do e1 = e1 + 1; end
    check('AI14 empty set -> empty plan', e1, 0);
    local e2 = 0; for _ in pairs(plan(nil, modelOf)) do e2 = e2 + 1; end
    check('AI15 nil set -> empty plan, no error', e2, 0);
    local e3 = 0; for _ in pairs(plan({ Body = 'Kris' }, nil)) do e3 = e3 + 1; end
    check('AI16 no resolver -> empty plan, no error', e3, 0);

    -- v42 round 2: the preview INJECTS the client's own appearance packet
    -- (GRAP_LIST 0x051) -- layout from the server source (0x051_grap_list.cpp):
    -- GrapIDTbl[0] = face | race<<8, then head..ranged as base+model u16s.
    check('AI17 _merged: plan wins over snapshot',
        lookM._merged({ Head = 0x1005, Body = 0x2007 }, { Body = 0x2063 }).Body, 0x2063);
    check('AI18 _merged: snapshot fills unplanned slots',
        lookM._merged({ Head = 0x1005, Body = 0x2007 }, { Body = 0x2063 }).Head, 0x1005);
    check('AI19 _merged: bare base where neither knows',
        lookM._merged({ Head = 0x1005 }, { Body = 0x2063 }).Main, 0x6000);
    local pk = lookM._packet51(7, 2, { Head = 0x1001, Body = 0x2002, Hands = 0x3003, Legs = 0x4004,
                                       Feet = 0x5005, Main = 0x6006, Sub = 0x7007, Ranged = 0x8008 });
    check('AI20 packet51: GRAP_LIST length (0x18)', #pk, 0x18);
    check('AI21 packet51: header id|size', pk[1] == 0x51 and pk[2] == 0x18, true);
    check('AI22 packet51: face and race bytes', pk[5] == 7 and pk[6] == 2, true);
    check('AI23 packet51: Head u16 LE at 0x06', pk[7] == 0x01 and pk[8] == 0x10, true);
    check('AI24 packet51: Ranged u16 LE at 0x14', pk[21] == 0x08 and pk[22] == 0x80, true);
end

-- ---------------------------------------------------------------------------
-- AJ. lockstyle APPLY: the engine-built 0x053 (v42)
--
--    The server (CatsEyeXI src/map/packets/c2s/0x053_lockstyle.cpp, read
--    2026-07-15) takes ItemNo + EquipKind per entry -- container/index are
--    ignored, so no bag scan belongs in the client. styleItems persist per
--    slot server-side, so a box is only authoritative if all 9 visual slots
--    ride in every packet: named -> id, 'remove' -> 0 (renders EMPTY), unnamed
--    -> the worn item's id (freeze-current). The style gate mirrors the
--    server's canEquipItemOnAnyJob: one of YOUR jobs, at its CURRENT level.
-- ---------------------------------------------------------------------------
check('AJ0 _lockstylePacket exported', type(dispatchM._lockstylePacket), 'function');
if type(dispatchM._lockstylePacket) == 'function' then
    local RES = { ["Arhat's Gi"] = 13795, ['Kris'] = 16450 };
    local eqf = function(slot) if slot == 'Main' then return 21639; end return nil; end
    local pkt, r = dispatchM._lockstylePacket(
        { Body = "Arhat's Gi", Head = 'remove', Legs = 'No Such' },
        function(n) return RES[n]; end, eqf);
    check('AJ1 wire length 0x88', #pkt, 136);
    check('AJ2 header id|size', pkt[1] == 0x53 and pkt[2] == 0x88, true);
    check('AJ3 Count: all 9 slots, always', pkt[5], 9);
    check('AJ4 Mode: Set', pkt[6], 3);
    check('AJ5 named piece: EquipKind + ItemNo LE',
        pkt[50] == 5 and pkt[53] == 227 and pkt[54] == 53, true);   -- Body=kind5, 13795=0x35E3
    check('AJ6 remove -> ItemNo 0 (slot renders EMPTY)',
        pkt[42] == 4 and pkt[45] == 0 and pkt[46] == 0, true);      -- Head=kind4
    check('AJ7 unnamed -> frozen to worn item',
        pkt[10] == 0 and pkt[13] == 135 and pkt[14] == 84, true);   -- Main=kind0, 21639=0x5487
    check('AJ8 frozen reported', r.frozen.Main, 21639);
    check('AJ9 unnamed with nothing worn -> 0', pkt[18] == 1 and pkt[21] == 0 and pkt[22] == 0, true);   -- Sub
    check('AJ10 unresolved name reported missing', r.missing[1], 'No Such');
    check('AJ11 unresolved name -> ItemNo 0', pkt[66] == 7 and pkt[69] == 0 and pkt[70] == 0, true);     -- Legs
    check('AJ12 sent reported', r.sent.Body, "Arhat's Gi");

    -- the server's silent job gate, mirrored (charutils.cpp canEquipItemOnAnyJob)
    local gate = dispatchM._lsStyleGate;
    check('AJ13 gate: no job high enough -> old look persists',
        gate({ Jobs = { 'MNK', 'SAM', 'NIN' }, Level = 64 }, { MNK = 52, SAM = 10, DRK = 75 }), false);
    check('AJ14 gate: ANY job at level passes (not just the current one)',
        gate({ Jobs = { 'MNK', 'SAM', 'NIN' }, Level = 64 }, { NIN = 64, DRK = 75 }), true);
    check('AJ15 gate: All-jobs item needs any job at level',
        gate({ Jobs = { 'All' }, Level = 50 }, { DRK = 75 }), true);
    check('AJ16 gate: All-jobs item above every level fails',
        gate({ Jobs = { 'All' }, Level = 99 }, { DRK = 75 }), false);
    check('AJ17 gate: unknown record passes (server decides)', gate(nil, {}), true);
    check('AJ18 gate: record without Jobs passes', gate({ Level = 99 }, {}), true);
end

-- ---------------------------------------------------------------------------
-- LAP. lockstyleapply (issue #81, PRD #80) -- the ADDON-state lockstyle
--      executor the GUI Apply button injects through DIRECTLY (no command bus,
--      no request file, the Engine uninvolved). Its pure core is relocated from
--      the Engine BYTE-FOR-BYTE: these tests pin the new module's _lockstyleFrom
--      / _lockstylePacket against the Engine's surviving copy (dispatchM) -- the
--      AG-suite parity the acceptance criteria demand, so the two produce the
--      identical 0x053 until phase 2 deletes the Engine's. The live apply() is
--      driven headlessly through its injectable deps seam: it predicts the
--      server's silent gates (job gate through the Gear Oracle door; weapon
--      category from the Addon state's own worn reads) with the Engine's chat
--      wording VERBATIM, injects, and stamps a sender-side send witness.
-- ---------------------------------------------------------------------------
(function()
    -- Stub the Gear Oracle so the job-gate path (oracle.anyJobCanWear, captured
    -- at load) is exercisable headlessly: 'Bad Piece' fails the gate, else pass.
    local savedOracle = package.loaded['dlac\\gear\\gearoracle'];
    package.loaded['dlac\\gear\\gearoracle'] = {
        anyJobCanWear = function(rec, _) return type(rec) ~= 'table' or rec.Name ~= 'Bad Piece'; end,
        wornItem = function() return nil; end,
    };
    local lap = dofile('feature/lockstyleapply.lua');
    package.loaded['dlac\\gear\\gearoracle'] = savedOracle;

    check('LAP0 module loads', type(lap), 'table');
    check('LAP1 _lockstyleFrom exported', type(lap._lockstyleFrom), 'function');
    check('LAP2 _lockstylePacket exported', type(lap._lockstylePacket), 'function');

    -- _lockstyleFrom parity vs the Engine (lsT is the AG fixture above).
    local la1, lan1, lab1 = lap._lockstyleFrom(lsT, 1);
    local ea1, ean1, eab1 = dispatchM._lockstyleFrom(lsT, 1);
    check('LAP3 _lockstyleFrom box name parity', lan1, ean1);
    check('LAP4 _lockstyleFrom box index parity', lab1, eab1);
    check('LAP5 _lockstyleFrom slot parity (Main)', la1.Main, ea1.Main);
    check('LAP6 _lockstyleFrom remove-literal parity', la1.Body, ea1.Body);
    check('LAP7 marked-box fallback parity', select(3, lap._lockstyleFrom(lsT, nil)),
        select(3, dispatchM._lockstyleFrom(lsT, nil)));
    check('LAP8 empty-box why parity', select(2, lap._lockstyleFrom(lsT, 9)),
        select(2, dispatchM._lockstyleFrom(lsT, 9)));
    check('LAP9 no-table why parity', select(2, lap._lockstyleFrom(nil)),
        select(2, dispatchM._lockstyleFrom(nil)));

    -- _lockstylePacket BYTE-IDENTICAL to the Engine, same fixtures as AJ.
    local RES = { ["Arhat's Gi"] = 13795, ['Kris'] = 16450 };
    local eqf = function(slot) if slot == 'Main' then return 21639; end return nil; end
    local resolve = function(n) return RES[n]; end
    local setP = { Body = "Arhat's Gi", Head = 'remove', Legs = 'No Such' };
    local lpkt = lap._lockstylePacket(setP, resolve, eqf);
    local epkt = dispatchM._lockstylePacket(setP, resolve, eqf);
    check('LAP10 same wire length', #lpkt, #epkt);
    local diff = nil;
    for i = 1, 136 do if lpkt[i] ~= epkt[i] then diff = i; break; end end
    check('LAP11 0x053 byte-identical to the Engine (all 136 bytes)', diff, nil);

    -- live apply() via the injectable deps seam: injects, reports, witnesses.
    local lines, injected = {}, nil;
    local res = lap.apply(lsT, 1, {
        resolveId  = function(n) return ({ Kris = 16450, ["Ducal Guard's Ribbon"] = 111 })[n]; end,
        equippedId = function() return nil; end,
        jobLevels  = function() return nil; end,   -- nil -> fail open, no gate warnings
        wornType   = function() return nil; end,
        recType    = function() return nil; end,
        rec        = function() return nil; end,
        inject     = function(pkt) injected = pkt; return true; end,
        emit       = function(l) lines[#lines + 1] = l; end,
    });
    check('LAP12 apply reports ok', res.ok, true);
    check('LAP13 apply injected a 0x053', injected ~= nil and injected[1], 0x53);
    check('LAP14 apply reports the box', res.box, 1);
    check('LAP15 styled count (Kris + Ducal ribbon; Body=remove not counted)', res.styled, 2);
    local sawOk = false;
    for _, l in ipairs(lines) do if l:match('^%[dlac%] lockstyle "AF Glam" %(box 1%) sent') then sawOk = true; end end
    check('LAP16 success line verbatim', sawOk, true);
    check('LAP17 send witness stamped', lap.lastSend() ~= nil and lap.lastSend().box, 1);

    -- job-gate warning routes through the Gear Oracle door (stub), wording VERBATIM.
    local glines = {};
    lap.apply({ slots = { [1] = { name = 'G', set = { Body = 'Bad Piece' } } } }, 1, {
        resolveId = function() return 5; end, equippedId = function() return nil; end,
        jobLevels = function() return { WAR = 1 }; end,   -- non-nil -> the gate runs
        rec = function(n) return { Name = n, Jobs = { 'WAR' }, Level = 75 }; end,
        wornType = function() return nil; end, recType = function() return nil; end,
        inject = function() return true; end, emit = function(l) glines[#glines + 1] = l; end,
    });
    local sawGate = false;
    for _, l in ipairs(glines) do
        if l:match('will KEEP ITS OLD LOOK') and l:match('Bad Piece') and l:match('one of YOUR jobs') then sawGate = true; end
    end
    check('LAP18 job-gate warning via the oracle door, wording matches', sawGate, true);

    -- weapon-category warning from the Addon state's own worn reads, wording VERBATIM.
    local wlines = {};
    lap.apply({ slots = { [1] = { set = { Main = 'Dagger' } } } }, 1, {
        resolveId = function() return 5; end, equippedId = function() return nil; end,
        jobLevels = function() return nil; end,
        recType = function() return 'Dagger'; end, wornType = function() return 'Great Sword'; end,
        rec = function() return nil; end, inject = function() return true; end,
        emit = function(l) wlines[#wlines + 1] = l; end,
    });
    local sawWeap = false;
    for _, l in ipairs(wlines) do
        if l:match('will NOT show over your') and l:match('same category') then sawWeap = true; end
    end
    check('LAP19 weapon-category warning, wording matches', sawWeap, true);

    -- unresolved name -> EMPTY-slot warning, wording VERBATIM.
    local mlines = {};
    lap.apply({ slots = { [1] = { set = { Legs = 'Ghost Pants' } } } }, 1, {
        resolveId = function() return nil; end, equippedId = function() return nil; end,
        jobLevels = function() return nil; end, recType = function() return nil; end,
        wornType = function() return nil; end, rec = function() return nil; end,
        inject = function() return true; end, emit = function(l) mlines[#mlines + 1] = l; end,
    });
    local sawMiss = false;
    for _, l in ipairs(mlines) do if l:match('did not resolve to an item id') then sawMiss = true; end end
    check('LAP20 unresolved-name warning, wording matches', sawMiss, true);

    -- inject failure and an empty box both report ok=false (no silent apply).
    local r2 = lap.apply(lsT, 1, {
        resolveId = function() return 1; end, equippedId = function() return nil; end,
        jobLevels = function() return nil; end, recType = function() return nil; end,
        wornType = function() return nil; end, rec = function() return nil; end,
        inject = function() return false; end, emit = function() end,
    });
    check('LAP21 inject failure -> ok=false', r2.ok, false);
    local r3 = lap.apply(lsT, 3, { emit = function() end });   -- box 3: nothing usable
    check('LAP22 empty box refused (ok=false)', r3.ok, false);
end)();

-- ---------------------------------------------------------------------------
-- AK. reserved slots (dispatch.reservedDrops) -- an item's RSlot mask is the
--     server's item_equipment.rslot: the slots it TAKES AWAY while worn. The
--     Ryl.Ftm. Tunic (Body) reserves Head; equipping a head piece anyway makes
--     the server strip it and dlac re-equip it, forever. The reserver wins and
--     the reserved slot is dropped -- the only stable state.
-- ---------------------------------------------------------------------------
do
    local RS = { ['Ryl.Ftm. Tunic'] = 0x0010,     -- Body  -> Head
                 ['Wikyo Cloak']    = 0x0010,     -- Body  -> Head
                 ['Decennial Coat'] = 0x0040,     -- Body  -> Hands
                 ['Moogle Suit']    = 0x01C0,     -- Body  -> Hands + Legs + Feet
                 ['Marine Boxers']  = 0x0100,     -- Legs  -> Feet
                 ['Boomerang']      = 0x0008,     -- Range -> Ammo
                 ['Pet Food Alpha'] = 0x0004 };   -- Ammo  -> Range
    local function look(n) return RS[n]; end
    local function drops(set, worn) return dispatchM.reservedDrops(set, look, worn) or {}; end

    -- the reported bug
    local d = drops({ Body = 'Ryl.Ftm. Tunic', Head = 'Silver Hairpin', Legs = 'Cotton Brais' });
    check('AK1 a reserved Head is dropped',        d.Head, 'Ryl.Ftm. Tunic');
    check('AK2 the reserver itself is kept',       d.Body, nil);
    check('AK3 unrelated slots are untouched',     d.Legs, nil);

    check('AK4 no reserver -> nothing dropped',
        dispatchM.reservedDrops({ Body = 'Cotton Doublet', Head = 'Silver Hairpin' }, look), nil);
    check('AK5 reserver with the slot empty -> nothing dropped',
        dispatchM.reservedDrops({ Body = 'Ryl.Ftm. Tunic' }, look), nil);
    check('AK6 an unknown item reserves nothing',
        dispatchM.reservedDrops({ Body = 'Mystery Robe', Head = 'Silver Hairpin' }, look), nil);

    -- multi-bit masks
    local m = drops({ Body = 'Moogle Suit', Hands = 'G1', Legs = 'G2', Feet = 'G3', Head = 'G4' });
    check('AK7 every bit of the mask drops',  (m.Hands ~= nil and m.Legs ~= nil and m.Feet ~= nil), true);
    check('AK8 a bit NOT in the mask stays',  m.Head, nil);

    -- a dropped slot must not go on to reserve: Body takes Legs, so the Legs
    -- piece is never worn and its own claim on Feet must not fire.
    local c = drops({ Body = 'Moogle Suit', Legs = 'Marine Boxers', Feet = 'Leather Highboots' });
    check('AK9 chained: Legs dropped by Body',        c.Legs, 'Moogle Suit');
    check('AK10 chained: Feet dropped by Body, not by the dropped Legs', c.Feet, 'Moogle Suit');

    -- mutual reservation resolves deterministically by slot order, not pairs() luck
    local mut = drops({ Range = 'Boomerang', Ammo = 'Pet Food Alpha' });
    check('AK11 mutual: Range wins',  mut.Range, nil);
    check('AK12 mutual: Ammo dropped', mut.Ammo, 'Boomerang');
    check('AK13 arrows are not ammo-reserved', drops({ Range = 'Power Bow', Ammo = 'Iron Arrow' }).Ammo, nil);

    -- WORN pieces reserve too: the common case is a set that only writes Head
    -- while the Tunic is already on your back.
    local function wornTunic(slot) if slot == 'Body' then return 'Ryl.Ftm. Tunic'; end return nil; end
    check('AK14 a worn reserver drops the planned Head',
        drops({ Head = 'Silver Hairpin' }, wornTunic).Head, 'Ryl.Ftm. Tunic');
    check('AK15 a set that REPLACES the reserver keeps its Head',
        drops({ Head = 'Silver Hairpin', Body = 'Cotton Doublet' }, wornTunic).Head, nil);
    check('AK16 worn slots are never themselves dropped',
        drops({ Head = 'Silver Hairpin' }, wornTunic).Body, nil);
    check('AK17 a throwing worn() is survivable',
        dispatchM.reservedDrops({ Head = 'Silver Hairpin' }, look,
            function() error('no equipment'); end), nil);

    -- slot keys are matched case-insensitively; the dropped key keeps the set's case
    local lc = drops({ body = 'Ryl.Ftm. Tunic', head = 'Silver Hairpin' });
    check('AK18 lowercase set keys still resolve', lc.head, 'Ryl.Ftm. Tunic');

    -- the equipResolved post-pass end-to-end. First with a manifest that has no
    -- RSlot (every gear.lua written before v43): the engine must behave exactly as
    -- it did, or an un-fixed file would start losing slots.
    local gT = package.loaded['dlac\\gear'];
    gT.NameToObject['Ryl.Ftm. Tunic'] = { Name = 'Ryl.Ftm. Tunic', Type = 'Body' };
    gT.NameToObject['Silver Hairpin'] = { Name = 'Silver Hairpin', Type = 'Head' };
    local _, akTbl = dispatchM._equipResolved({ Body = 'Ryl.Ftm. Tunic', Head = 'Silver Hairpin' }, {});
    check('AK19 a manifest without RSlot leaves the engine unchanged', akTbl.Head, 'Silver Hairpin');

    -- now stamp RSlot, as the scan / `/dl fix` does -> the engine drops the Head.
    -- This is the wiring test: reservedDrops is pure, but rslotOf reads the real
    -- manifest, and that read is what actually has to work in LAC's state.
    gT.NameToObject['Ryl.Ftm. Tunic'].RSlot = 0x0010;
    local akNote, akTbl2 = dispatchM._equipResolved({ Body = 'Ryl.Ftm. Tunic', Head = 'Silver Hairpin' }, {});
    check('AK20 manifest RSlot -> reserved Head dropped', akTbl2.Head, nil);
    check('AK21 the reserver still equips',               akTbl2.Body, 'Ryl.Ftm. Tunic');
    check('AK22 the drop is traced for /dl why',
        string.find(akNote, 'RESERVED', 1, true) ~= nil, true);
end

-- ---------------------------------------------------------------------------
-- AL. PINNED slots (dispatch v44) -- "equip item, lock slot so nothing removes
--     equipped item" (Henrik). pinwatch writes pinstate.lua; the engine wears
--     the named item at TOP priority (above the craft overlay) on EVERY event.
--     scope = 'All' (every dispatch) or a list of "<Event>|<rule label>" keys.
--
--     NOTE: `(function() ... end)()`, not the `do ... end` the older sections
--     use. THIS FILE hit the same LuaJIT/Lua 200-local-per-chunk cap gearui did
--     -- it is one ~1800-line main chunk and a `do` block's locals share that
--     chunk's budget, so wrapping in `do` does not buy a single register. A
--     function body gets its OWN 200. Add new sections this way; it is also the
--     cheapest fix if an older `do` section ever tips the cap over.
-- ---------------------------------------------------------------------------
;(function()
    local PF = dispatchM._pinOverlayFor;

    -- scope 'All': applies with no triggers matched at all (a bare profile still
    -- has to honour a pin) and on every event, not just Default.
    local pAll = { Ring1 = { item = 'Rajas Ring', scope = 'All' } };
    check('AL1 All pin applies with zero hits',
        (PF(pAll, {}, 'Default') or {}).Ring1, 'Rajas Ring');
    check('AL2 All pin applies on a non-Default event',
        (PF(pAll, {}, 'Midcast') or {}).Ring1, 'Rajas Ring');

    -- no state / empty state -> nil (nil, not {}: dispatch tests `pEquip == nil`
    -- to decide whether it may bail out of the whole dispatch)
    check('AL3 no pin state -> nil overlay', PF(nil, {}, 'Default'), nil);
    check('AL4 empty pin state -> nil overlay', PF({}, {}, 'Default'), nil);

    -- scoped pins: only on a dispatch where THAT trigger matched
    local key = dispatchM.pinScopeKey('Midcast', 'name=slow ii');
    local pScoped = { Head = { item = 'Uk\'uxkaj Cap', scope = { key } } };
    local hitSlow  = { { label = 'name=slow ii' } };
    local hitOther = { { label = 'name=dia ii' } };
    check('AL5 scoped pin applies when its trigger matched',
        (PF(pScoped, hitSlow, 'Midcast') or {}).Head, 'Uk\'uxkaj Cap');
    check('AL6 scoped pin is silent when another trigger matched',
        PF(pScoped, hitOther, 'Midcast'), nil);
    check('AL7 scoped pin is silent with no hits at all',
        PF(pScoped, {}, 'Midcast'), nil);
    -- the reason scope keys carry the EVENT: 'any' is the label of every
    -- unconditional rule, so a Precast 'any' and a Midcast 'any' would be
    -- indistinguishable and one pin would silently cover both.
    check('AL8 scoped pin does not leak across events (same label, other event)',
        PF(pScoped, hitSlow, 'Precast'), nil);

    -- a pin scoped to a trigger that no longer exists goes QUIET rather than
    -- falling back to forcing gear on every dispatch
    local pGone = { Feet = { item = 'Herald\'s Gaiters', scope = { 'Midcast|name=deleted' } } };
    check('AL9 pin on a deleted trigger goes quiet', PF(pGone, hitSlow, 'Midcast'), nil);

    -- tolerated shapes: bare string, and a missing scope (hand-written file)
    check('AL10 bare-string pin is treated as All',
        (PF({ Back = 'Cape' }, {}, 'Default') or {}).Back, 'Cape');
    check('AL11 pin with no scope is treated as All',
        (PF({ Back = { item = 'Cape' } }, {}, 'Default') or {}).Back, 'Cape');
    check('AL12 empty item name is ignored',
        PF({ Back = { item = '', scope = 'All' } }, {}, 'Default'), nil);

    -- several slots at once; mixed scopes resolve independently
    local pMix = { Ring1 = { item = 'Rajas Ring', scope = 'All' },
                   Head  = { item = 'Uk\'uxkaj Cap', scope = { key } } };
    local mix = PF(pMix, hitSlow, 'Midcast') or {};
    check('AL13 mixed scopes: All applies',    mix.Ring1, 'Rajas Ring');
    check('AL14 mixed scopes: scoped applies', mix.Head, 'Uk\'uxkaj Cap');
    local mix2 = PF(pMix, {}, 'Default') or {};
    check('AL15 mixed scopes: All still applies out of scope', mix2.Ring1, 'Rajas Ring');
    check('AL16 mixed scopes: scoped drops out of scope',      mix2.Head, nil);

    -- pinScopeKey is the ONE spelling of a scope key: the GUI builds menu entries
    -- with it and the engine matches with it, so the two states cannot drift.
    check('AL17 pinScopeKey format', dispatchM.pinScopeKey('Midcast', 'name=slow ii'),
        'Midcast|name=slow ii');

    -- ruleLabel: shared by normalize (engine) and the pin menu (GUI). A condition
    -- value may be a LIST (when.mode holds several modes) and tostring() on a
    -- table yields an ADDRESS -- different in each Lua state and after every
    -- reload -- so a scoped pin could never match. Serialize lists by value.
    check('AL18 ruleLabel: no conditions -> any', dispatchM.ruleLabel({}), 'any');
    check('AL19 ruleLabel: single condition', dispatchM.ruleLabel({ name = 'Slow II' }), 'name=Slow II');
    check('AL20 ruleLabel: sorted + joined',
        dispatchM.ruleLabel({ skill = 'Enfeebling Magic', name = 'Slow II' }),
        'name=Slow II+skill=Enfeebling Magic');
    check('AL21 ruleLabel: list value is serialized BY VALUE, not by address',
        dispatchM.ruleLabel({ mode = { 'DT', 'Acc' } }), 'mode=Acc,DT');
    check('AL22 ruleLabel: two equal lists in DIFFERENT tables label identically',
        dispatchM.ruleLabel({ mode = { 'DT', 'Acc' } }) == dispatchM.ruleLabel({ mode = { 'Acc', 'DT' } }), true);
    check('AL23 ruleLabel: keys lowercased like normalize',
        dispatchM.ruleLabel({ Name = 'Slow II' }), 'name=Slow II');

    -- Sub-vs-Main, the pin side. A pinned Sub with no pinned Main is top
    -- priority and must survive the set's Main: without a guard the two knock
    -- each other off on every pass (the v37 flap, the reason craftMainGuard
    -- exists). The guard SOURCE is what dispatch picks; these check the shape
    -- dispatch feeds it and the resulting hold.
    local pinSubOnly = { Sub = 'Kupo Shield' };
    local pg = dispatchM._craftMainGuard(pinSubOnly);
    check('AL26 a pinned Sub with no pinned Main builds a guard', pg ~= nil, true);
    check('AL27 the guard holds a 2H set Main against a pinned Sub', pg('Death Scythe'), true);
    check('AL28 a 1H set Main pairs with a pinned Sub and passes', pg('Parry Knife'), false);
    check('AL29 no guard when the pin brings its own Main',
        dispatchM._craftMainGuard({ Sub = 'Kupo Shield', Main = 'Parry Knife' }), nil);
    local _, alHeld = dispatchM._equipResolved({ Main = 'Death Scythe', Body = 'Weaver Apron' },
        { craftMainGuard = pg });
    check('AL30 the set Main is held so the pinned Sub survives', alHeld.Main, nil);
    check('AL31 the rest of the set is untouched by the hold', alHeld.Body, 'Weaver Apron');

    -- The other side: a PINNED Main beats the craft overlay's Sub. dispatch drops
    -- the craft Sub when it cannot pair, or craft re-equips it every pass and the
    -- pinned Main knocks it off again. (Same guard function, asked in reverse.)
    local cg = dispatchM._craftMainGuard({ Sub = 'Kupo Shield' });
    check('AL32 a pinned 2H Main conflicts with the craft Sub', cg('Death Scythe'), true);
    check('AL33 a pinned 1H Main leaves the craft Sub alone', cg('Parry Knife'), false);

    -- A pin goes through equipResolved like any other set, so it inherits the
    -- reserved-slot pass: pinning a Body that reserves Head drops the Head.
    local gT = require('dlac\\gear');
    if type(gT) == 'table' and type(gT.NameToObject) == 'table'
       and gT.NameToObject['Ryl.Ftm. Tunic'] ~= nil then
        gT.NameToObject['Ryl.Ftm. Tunic'].RSlot = 0x0010;
        local _, alTbl = dispatchM._equipResolved(
            { Body = 'Ryl.Ftm. Tunic', Head = 'Silver Hairpin' }, {});
        check('AL24 a pinned reserver still drops the reserved slot', alTbl.Head, nil);
        check('AL25 the pinned reserver itself equips', alTbl.Body, 'Ryl.Ftm. Tunic');

        -- THE FLAP, through the overlay. reservedDrops judges ONE table at a
        -- time, and the pin lands in its OWN equipResolved -- so the SET's pass
        -- never learns the pinned Tunic is about to reserve the Head it is
        -- equipping, and the pin's pass cannot drop a Head its table never
        -- names. Without the hold: set equips Head, pin equips Tunic, server
        -- strips Head, forever ("it just flashes back and forth infinitely").
        -- (Nested do: this file's main chunk has its own 200-local ceiling.)
        do
            local res = dispatchM._pinReservedSlots({ Body = 'Ryl.Ftm. Tunic' });
            check('AL34 a pinned reserver reports its reserved slot',
                (res or {}).head, 'Ryl.Ftm. Tunic');
            check('AL35 it does not report slots it never reserves', (res or {}).legs, nil);
            -- the hold applied to the SET's pass: Head must not be equipped at all
            local nt, st = dispatchM._equipResolved(
                { Head = 'Silver Hairpin', Body = 'Cotton Doublet' },
                { pinReserved = res });
            check('AL36 the set never equips a slot a PIN reserves', st.Head, nil);
            check('AL37 the set keeps every other slot', st.Body, 'Cotton Doublet');
            check('AL38 the hold is traced for /dl why',
                string.find(nt or '', 'RESERVED by pinned', 1, true) ~= nil, true);
        end
        do
            -- no pins -> no hold -> the slot dispatches normally (stateless:
            -- unpin and Head comes straight back on the next pass)
            check('AL39 no pins -> nothing reserved', dispatchM._pinReservedSlots(nil), nil);
            local _, fr = dispatchM._equipResolved({ Head = 'Silver Hairpin' }, {});
            check('AL40 unpinned, the same Head equips again', fr.Head, 'Silver Hairpin');
            -- a pin never reserves ANOTHER pin's slot: you asked for both, both land
            local r2 = dispatchM._pinReservedSlots({ Body = 'Ryl.Ftm. Tunic', Head = 'Silver Hairpin' });
            check('AL41 a pin does not reserve a slot another pin owns', (r2 or {}).head, nil);
        end
    end
end)();

-- ---------------------------------------------------------------------------
-- AM. pinwatch (addon state) -- the writer half of the pin contract. Serializes
--     the table the engine's ensurePinState() loads back, so the two must agree
--     on the format exactly.
-- ---------------------------------------------------------------------------
;(function()
    -- dofile, not require: the harness has no addons/ on package.path (the
    -- dispatch/utils pattern above). serialize is pure -- charDir is pcall-guarded
    -- and just yields nil without AshitaCore, so nothing here touches disk.
    local pw = dofile('feature/pinwatch.lua');   -- forward slash: also loads on Linux CI

    local function roundTrip(pins)
        local text = pw.serialize(pins);
        local chunk = (loadstring or load)(text, '@pinstate.lua');
        if chunk == nil then return nil, text; end
        local ok, t = pcall(chunk);
        return (ok and t or nil), text;
    end

    -- empty -> a valid, loadable file (NOT an empty string: the engine loadstrings it)
    local e, eText = roundTrip({});
    check('AM1 empty pin table serializes to a loadable chunk', type(e), 'table');
    check('AM2 empty pin table has no entries', next(e or {}), nil);
    check('AM3 empty file is the canonical spelling', eText, 'return { }\n');

    -- All-scope round trip
    local r = roundTrip({ Ring1 = { item = 'Rajas Ring', scope = 'All' } });
    check('AM4 All pin round-trips: item', (r.Ring1 or {}).item, 'Rajas Ring');
    check('AM5 All pin round-trips: scope', (r.Ring1 or {}).scope, 'All');

    -- scoped round trip
    local r2 = roundTrip({ Head = { item = 'Uk\'uxkaj Cap', scope = { 'Midcast|name=slow ii' } } });
    check('AM6 scoped pin round-trips: item', (r2.Head or {}).item, 'Uk\'uxkaj Cap');
    check('AM7 scoped pin round-trips: scope is a list',
        type((r2.Head or {}).scope) == 'table' and (r2.Head or {}).scope[1], 'Midcast|name=slow ii');

    -- the serialized file must be exactly what the ENGINE accepts
    local eng = dispatchM._pinOverlayFor(r2, { { label = 'name=slow ii' } }, 'Midcast');
    check('AM8 the engine reads pinwatch output', (eng or {}).Head, 'Uk\'uxkaj Cap');

    -- names with quotes/backslashes must survive (%q) -- FFXI item names carry
    -- apostrophes routinely (Uk'uxkaj Cap, Herald's Gaiters)
    local r3 = roundTrip({ Feet = { item = 'Herald\'s Gaiters', scope = 'All' } });
    check('AM9 apostrophes survive serialization', (r3.Feet or {}).item, 'Herald\'s Gaiters');

    -- malformed entries are dropped, not written
    local r4 = roundTrip({ Bad = { scope = 'All' }, Good = { item = 'X', scope = 'All' } });
    check('AM10 entry with no item is dropped', r4.Bad, nil);
    check('AM11 the valid entry beside it survives', (r4.Good or {}).item, 'X');

    -- stable output: dispatch's reader content-compares the RAW TEXT before
    -- re-parsing, so an unstable key order would defeat that cache every second
    local a = pw.serialize({ Ring1 = { item = 'A', scope = 'All' }, Head = { item = 'B', scope = 'All' },
                             Feet = { item = 'C', scope = 'All' }, Back = { item = 'D', scope = 'All' } });
    local b = pw.serialize({ Back = { item = 'D', scope = 'All' }, Feet = { item = 'C', scope = 'All' },
                             Head = { item = 'B', scope = 'All' }, Ring1 = { item = 'A', scope = 'All' } });
    check('AM12 serialization is order-stable across pairs() luck', a, b);

    -- Adversarial names. The engine loads this file with loadstring: anything %q
    -- fails to escape is a syntax error there, and the pin silently never applies.
    for i, nm in ipairs({ 'Herald\'s Gaiters', 'A "quoted" Ring', 'Back\\slash',
                          'new\nline', 'tab\there', 'pct%20', 'brace}Cap',
                          'Uk\'uxkaj Cap' }) do
        local rt = roundTrip({ Head = { item = nm, scope = 'All' } });
        check('AM13.' .. i .. ' adversarial name round-trips: ' .. string.format('%q', nm),
            (rt or {}).Head and rt.Head.item, nm);
    end
    -- and the same through a scope key, which is also user-influenced text
    local rtk = roundTrip({ Head = { item = 'X', scope = { 'Midcast|name=a"b\'c' } } });
    check('AM14 adversarial scope key round-trips',
        ((rtk or {}).Head or {}).scope[1], 'Midcast|name=a"b\'c');

    -- Character switch. An Ashita addon survives a logout, so the session-only
    -- clear must be keyed on the CHARACTER, not a one-shot boolean -- otherwise
    -- the next character to log in keeps this table and never gets their own
    -- pinstate.lua cleared, and last session's pins force gear on them at login.
    -- (charDir is nil headlessly, so drive the guard through the seam directly.)
    check('AM15 loadPinState is a no-op before login (no character dir yet)',
        pcall(pw.loadPinState), true);
    pw.pins = { Head = { item = 'CharA Cap', scope = 'All' } };
    pw.loadPinState();          -- still pre-login: must NOT clear or write
    check('AM16 pre-login load leaves the table alone', (pw.pins.Head or {}).item, 'CharA Cap');
end)();

-- ---------------------------------------------------------------------------
-- AN. lockstyle "Show gear I don't own" -- preview anything, save only what you
--     own (Henrik, 2026-07-15).
--
--     The preview never asks the server (it injects your own 0x051), so it can
--     render any item in the game. The SERVER renders a style only if you have
--     the item -- so an unowned pick is preview-only and Save refuses it.
--
--     Two rules this section exists to hold down:
--     1. `all` LIFTS the ownership filter -- it must never ADD one. The AH HARD
--        RULE (no job/level gate, ever) applies to the catalog list too, and a
--        2-arg call must stay owned-only and byte-identical to before.
--     2. Ownership is decided BY ID, never by name. The API drops apostrophes,
--        so the catalog says "Arhats Gi" where gear.lua says "Arhat's Gi" --
--        a name compare would call an item you own unowned, and (worse) save a
--        name the engine cannot resolve at apply time.
-- ---------------------------------------------------------------------------
(function()
    local savedGear = package.loaded['dlac\\gear'];
    package.loaded['dlac\\gear'] = {
        NameToObject = { ["Arhat's Gi"] = { Name = "Arhat's Gi", Id = 14000, Level = 60 },
                         ['Plain Robe']  = { Name = 'Plain Robe',  Id = 14001, Level = 1  } },
        Body = { Arhat = { Name = "Arhat's Gi", Id = 14000, Level = 60 },
                 Plain = { Name = 'Plain Robe',  Id = 14001, Level = 1  } },
    };
    local ls = dofile('feature/lockstyle.lua');
    package.loaded['dlac\\gear'] = savedGear;

    -- The catalog as gearui hands it over: FLAT, .Slot-carrying, API spelling.
    -- 'Gletis Crossbow' is the REAL shape of CatsEyeXI's junk (verified against
    -- tools/api_cache): an unimplemented row the server reports as slot=32 Body
    -- with MId=0 and jobs=0. 258 of those sit in the Body bucket -- they are why
    -- browsing Body listed crossbows and boots. No Model => no look => not offered.
    ls.wire{
        allEquip = function()
            return {
                { Name = 'Arhats Gi',  Id = 14000, Level = 60, Slot = 'Body', Model = 59 },  -- owned, other spelling
                { Name = 'Plain Robe', Id = 14001, Level = 1,  Slot = 'Body', Model = 1  },  -- owned, same spelling
                { Name = 'Royal Robe', Id = 14002, Level = 75, Slot = 'Body', Model = 2  },  -- NOT owned
                { Name = 'Kris',       Id = 16000, Level = 60, Slot = 'Main', Model = 7, OneHanded = true },  -- other slot; 1H
                { Name = 'Gletis Crossbow', Id = 14003, Level = 99, Slot = 'Body' },         -- server junk: no Model
                { Name = 'Amini Bottillons +2', Id = 14004, Level = 99, Slot = 'Body', Model = 0 }, -- junk: Model 0
                { Name = 'Kite Shield', Id = 16001, Level = 10, Slot = 'Sub',  Model = 3 },  -- native Sub
                { Name = 'Great Blade', Id = 16002, Level = 50, Slot = 'Main', Model = 8, OneHanded = false }, -- 2H
            };
        end,
        ownedById = function(id)
            local g = { [14000] = { Name = "Arhat's Gi" }, [14001] = { Name = 'Plain Robe' } };
            return g[id];
        end,
    };

    local function names(list) local s = {}; for _, r in ipairs(list) do s[r.Name] = true; end return s; end

    -- 1. the default is untouched
    check('AN1 owned-only by default (2-arg call)', #ls._listFor('Body', ''), 2);
    check('AN2 owned-only never shows unowned gear', names(ls._listFor('Body', ''))['Royal Robe'], nil);

    -- 2. all=true lifts ownership and NOTHING else
    local all = ls._listFor('Body', '', true);
    check('AN3 all=true adds the unowned item',   names(all)['Royal Robe'], true);
    check('AN4 all=true keeps the owned ones',    names(all)['Plain Robe'], true);
    check('AN5 all=true filters by slot',         names(all)['Kris'],       nil);
    check('AN6 all=true is the whole slot',       #all, 3);
    check('AN7 HARD RULE: all=true adds no job/level gate -- Lv75 on a Lv1 fixture is offered',
        names(all)['Royal Robe'], true);
    check('AN8 search still narrows the catalog list', #ls._listFor('Body', 'royal', true), 1);
    check('AN9 all=true sorts highest level first (the browse cap keeps the good end)',
        all[1].Name, 'Royal Robe');

    -- The junk rows (Henrik, 07-15). The server's item DB defaults unimplemented
    -- items to slot=32/Body with MId=0, so the Body bucket collects crossbows and
    -- boots. A LOOK picker must not offer something with no look.
    check('AN9a server junk (no Model) is not offered -- the wrong-slot crossbow',
        names(all)['Gletis Crossbow'], nil);
    check('AN9b Model=0 is "no look" too, not a real model',
        names(all)['Amini Bottillons +2'], nil);
    check('AN9c the junk did not take the real body pieces with it', #all, 3);
    check('AN9d hasLook: a real model passes',       ls._hasLook({ Model = 59 }), true);
    check('AN9e hasLook: model 0 fails',             ls._hasLook({ Model = 0 }),  false);
    check('AN9f hasLook: absent model fails',        ls._hasLook({}),             false);
    -- HARD RULE: the look filter is for the CATALOG only. gear.lua carries no
    -- Model of its own (gearui back-fills it later), so filtering the owned list
    -- on it would empty the picker -- and AH6 pins "nothing is filtered out".
    check('AN9g HARD RULE: the owned list is NOT look-filtered (its entries have no Model)',
        #ls._listFor('Body', ''), 2);
    -- Dual wield rides the catalog list too (Henrik, 07-17): a Slot="Main" row
    -- with OneHanded=true belongs in the Sub browse; a 2H one never does.
    local subAll = ls._listFor('Sub', '', true);
    check('AN9h catalog Sub browse carries the native Sub item', names(subAll)['Kite Shield'], true);
    check('AN9i DUAL WIELD: a 1H Main-slot row is offered in Sub', names(subAll)['Kris'], true);
    check('AN9j a 2H Main-slot row is NOT offered in Sub', names(subAll)['Great Blade'], nil);
    check('AN9k the Sub browse is exactly those two', #subAll, 2);
    -- No gearui wire (load order: lockstyle loads first, and every W helper is
    -- optional-guarded) -- all=true must degrade to the owned list, never throw.
    -- Asserts the CONTRACT, not a count: the fixture here is the shared gear
    -- table other sections own, and its Body count is not this section's to pin.
    check('AN10 all=true with no wire degrades to owned, no error',
        (function()
            local m = dofile('feature/lockstyle.lua');
            local ok, r = pcall(m._listFor, 'Body', '', true);
            return ok and type(r) == 'table';
        end)(), true);

    -- 3. the Save gate
    check('AN11 owned name passes the gate',          ls._nameOwned("Arhat's Gi"), true);
    check('AN12 unowned name fails the gate',         ls._nameOwned('Royal Robe'), false);
    check('AN13 APOSTROPHE TRAP: the catalog spelling is NOT owned -- the picker must store YOUR name',
        ls._nameOwned('Arhats Gi'), false);
    check('AN14 "remove" is not an item -- never blocks a save', ls._nameOwned('remove'), true);
    check('AN15 empty/cleared slot never blocks a save',         ls._nameOwned(''),       true);
    check('AN16 nil never blocks a save',                        ls._nameOwned(nil),      true);

    check('AN17 a fully-owned set saves', #ls._unownedSlots({ Body = "Arhat's Gi", Head = 'remove' }), 0);
    local bad = ls._unownedSlots({ Body = 'Royal Robe', Head = 'Nonesuch Cap', Legs = 'Plain Robe' });
    check('AN18 unowned slots are reported', #bad, 2);
    check('AN19 unowned slots are sorted (stable warning text)', bad[1] .. ',' .. bad[2], 'Body,Head');
    check('AN20 an empty set saves', #ls._unownedSlots({}), 0);
    check('AN21 a nil set never errors',  #ls._unownedSlots(nil), 0);

    -- 4. the two rules meet: picking the owned item off the CATALOG list must
    --    store gear.lua's spelling, or the engine cannot resolve it at apply and
    --    the gate would reject an item you actually own. This is the bridge.
    local catRec = { Name = 'Arhats Gi', Id = 14000, Level = 60, Slot = 'Body' };   -- API spelling
    check('AN22 ownedRec finds your copy of a catalog row, by Id',
        (ls._ownedRec(catRec) or {}).Name, "Arhat's Gi");
    check('AN23 ownedRec returns nil for gear you do not own',
        ls._ownedRec({ Name = 'Royal Robe', Id = 14002 }), nil);
    check('AN24 THE BRIDGE: the name the picker stores is the name the gate accepts',
        ls._nameOwned((ls._ownedRec(catRec) or catRec).Name), true);
    check('AN25 without the bridge the same pick would be rejected (why AN24 matters)',
        ls._nameOwned(catRec.Name), false);
    check('AN26 ownedRec tolerates a row with no Id', ls._ownedRec({ Name = 'x' }), nil);

    -- 5. FAIL OPEN. The gate must never brick Save because a lookup failed --
    --    pre-login gear.lua is the bundled EMPTY template (dlac.lua preloads at
    --    Ashita boot, the real one swaps in on the first frame after login). A
    --    fail-closed gate would call every item unowned and refuse every save.
    local saved2 = package.loaded['dlac\\gear'];
    package.loaded['dlac\\gear'] = { NameToObject = {} };       -- the empty template
    local lsEmpty = dofile('feature/lockstyle.lua');
    package.loaded['dlac\\gear'] = saved2;
    check('AN27 FAIL OPEN: an empty gear table does not block a save',
        lsEmpty._nameOwned('Anything At All'), true);
    check('AN28 FAIL OPEN: nothing is reported unowned when we cannot tell',
        #lsEmpty._unownedSlots({ Body = 'Anything At All' }), 0);
end)();

-- ---------------------------------------------------------------------------
-- AO. setimport.importStaticSet -- the pure "Copy from static" transform (#15/ADR 0008)
--
--   Full-replace: only slots the static DEFINES (and that resolve to >=1 candidate)
--   appear in working; order carried verbatim; notBestFirst names slots whose candidate
--   order is not highest-item-Level first. Resolver is injected (owned records -> entry).
-- ---------------------------------------------------------------------------
(function()
    local simport = dofile('gear/setimport.lua');   -- forward slash: also loads on Linux CI
    check('AO0 importStaticSet exported', type(simport.importStaticSet), 'function');

    local SLOTS = { { label = 'Main' }, { label = 'Sub' }, { label = 'Head' },
                    { label = 'Body' }, { label = 'Hands' }, { label = 'Waist' } };

    -- Owned records (Name -> record), the only ones the resolver knows. A resolver over
    -- these mirrors gearui.resolveSetItem: a name not owned -> nil (dropped candidate);
    -- a dlac: string -> a virtual entry (Level 0, taken outright at equip).
    local OWNED = {
        ['warp cudgel']    = { Name = 'Warp Cudgel',    Level = 30 },
        ['yagrush']        = { Name = 'Yagrush',        Level = 75 },
        ['chatoyant staff']= { Name = 'Chatoyant Staff',Level = 70 },
        ['austere hat']    = { Name = 'Austere Hat',    Level = 60 },
        ['dalmatica']      = { Name = 'Dalmatica',      Level = 60 },
        ['errant houppe.'] = { Name = 'Errant Houppe.', Level = 71 },
    };
    local function resolve(elem)
        if type(elem) == 'string' then
            if string.lower(string.sub(elem, 1, 5)) == 'dlac:' then
                return { rec = { Name = elem, Level = 0, Virtual = true } };
            end
            local rec = OWNED[string.lower(elem)];
            return rec and { rec = rec } or nil;
        end
        if type(elem) == 'table' and type(elem.Name) == 'string' then
            local rec = OWNED[string.lower(elem.Name)];
            return rec and { rec = rec } or nil;
        end
        return nil;
    end

    -- 1. A plain static set: one element per slot -> one-candidate working lists, no
    --    warnings (a single candidate is trivially best-first).
    local plain = { Main = 'Yagrush', Head = 'Austere Hat', Body = 'Dalmatica',
                    NotASlot = 'ignored' };
    local r1 = simport.importStaticSet(plain, SLOTS, resolve);
    check('AO1 plain: slotCount', r1.slotCount, 3);
    check('AO2 plain: Main list len', #r1.working.Main, 1);
    check('AO3 plain: Main[1] name', r1.working.Main[1].rec.Name, 'Yagrush');
    check('AO4 plain: undefined slot cleared (Sub absent)', r1.working.Sub, nil);
    check('AO5 plain: no best-first warnings', #r1.notBestFirst, 0);

    -- 2. A level-descending _Priority list imports silently and keeps its order.
    local descending = { Main = { 'Yagrush', 'Chatoyant Staff', 'Warp Cudgel' } };
    local r2 = simport.importStaticSet(descending, SLOTS, resolve);
    check('AO6 descending: order verbatim [1]', r2.working.Main[1].rec.Name, 'Yagrush');
    check('AO7 descending: order verbatim [3]', r2.working.Main[3].rec.Name, 'Warp Cudgel');
    check('AO8 descending: no warning (best-first)', #r2.notBestFirst, 0);

    -- 3. A not-best-first list (a lower-Level piece ranked above a higher one) is named.
    local mixed = { Main = { 'Warp Cudgel', 'Yagrush' },   -- 30 then 75 -> NOT best-first
                    Body = { 'Dalmatica', 'Errant Houppe.' } }; -- 60 then 71 -> NOT best-first
    local r3 = simport.importStaticSet(mixed, SLOTS, resolve);
    check('AO9 mixed: order still verbatim', r3.working.Main[1].rec.Name, 'Warp Cudgel');
    check('AO10 mixed: two slots flagged', #r3.notBestFirst, 2);
    local flagged = {}; for _, l in ipairs(r3.notBestFirst) do flagged[l] = true; end
    check('AO11 mixed: Main flagged', flagged.Main, true);
    check('AO12 mixed: Body flagged', flagged.Body, true);

    -- 4. Equal Levels are a tie, not a divergence -> best-first, no warning.
    local tie = { Main = { { Name = 'Austere Hat' }, { Name = 'Dalmatica' } } };  -- both 60
    check('AO13 equal Levels are best-first', #(simport.importStaticSet(tie, SLOTS, resolve).notBestFirst), 0);

    -- 5. Unowned candidates drop; a slot with NO owned candidate never appears (and so
    --    is not counted) -- full-replace acts on what actually resolves.
    local partial = { Main = { 'Yagrush', 'Unowned Club', 'Warp Cudgel' },  -- drop the middle
                      Sub  = { 'Nothing Owned Here' } };                    -- 0 resolved -> absent
    local r5 = simport.importStaticSet(partial, SLOTS, resolve);
    check('AO14 partial: unowned dropped from list', #r5.working.Main, 2);
    check('AO15 partial: order after drop [2]', r5.working.Main[2].rec.Name, 'Warp Cudgel');
    check('AO16 partial: best-first is judged on the resolved remainder (75 then 30)', #r5.notBestFirst, 0);
    check('AO17 partial: all-unowned slot absent', r5.working.Sub, nil);
    check('AO18 partial: only the one resolvable slot counts', r5.slotCount, 1);

    -- 6. A virtual entry (dlac:AutoStaff) is skipped by the best-first check, not read as
    --    a Level-0 candidate that would falsely flag the slot.
    local virt = { Main = { 'dlac:AutoStaff', 'Yagrush' } };
    local r6 = simport.importStaticSet(virt, SLOTS, resolve);
    check('AO19 virtual carried as candidate', #r6.working.Main, 2);
    check('AO20 virtual does not trip best-first', #r6.notBestFirst, 0);

    -- 7. Degenerate inputs never error.
    check('AO21 nil static set -> 0 slots', simport.importStaticSet(nil, SLOTS, resolve).slotCount, 0);
    check('AO22 nil resolver -> 0 slots', simport.importStaticSet(plain, SLOTS, nil).slotCount, 0);
    check('AO23 isBestFirst on empty list', simport.isBestFirst({}), true);
end)();

-- ---------------------------------------------------------------------------
-- AP. setimport.resolveNewSetNames -- "Copy from" > "New set(s)" destination naming.
--     Migrate many sets at once: each keeps its source name; a name already taken
--     becomes <name>_Copy (then _Copy2, _Copy3, ...). Case-insensitive; in-batch
--     collisions resolve top-to-bottom.
-- ---------------------------------------------------------------------------
(function()
    local simport = dofile('gear/setimport.lua');   -- forward slash: also loads on Linux CI
    check('AP0 resolveNewSetNames exported', type(simport.resolveNewSetNames), 'function');

    -- No collision: names kept verbatim, nothing flagged renamed.
    local r1 = simport.resolveNewSetNames(
        { { name = 'Idle', kind = 'static' }, { name = 'TP', kind = 'static' } },
        { 'Precast', 'Midcast' });
    check('AP1 kept name [1]', r1[1].finalName, 'Idle');
    check('AP2 not renamed [1]', r1[1].renamed, false);
    check('AP3 kept name [2]', r1[2].finalName, 'TP');
    check('AP4 kind carried through', r1[1].kind, 'static');

    -- Collision with an existing dynamic set -> _Copy, flagged renamed.
    local r2 = simport.resolveNewSetNames({ { name = 'Idle', kind = 'static' } }, { 'Idle' });
    check('AP5 collided -> _Copy', r2[1].finalName, 'Idle_Copy');
    check('AP6 renamed flagged', r2[1].renamed, true);

    -- Case-insensitive collision (matches the Sets tab rename rule).
    local r3 = simport.resolveNewSetNames({ { name = 'idle' } }, { 'IDLE' });
    check('AP7 case-insensitive collision', r3[1].finalName, 'idle_Copy');

    -- _Copy ALSO taken -> _Copy2, _Copy3 ...
    local r4 = simport.resolveNewSetNames({ { name = 'Idle' } }, { 'Idle', 'Idle_Copy', 'Idle_Copy2' });
    check('AP8 stacks to _Copy3', r4[1].finalName, 'Idle_Copy3');

    -- Two marked sources sharing a name: the second dodges the first WITHIN the batch.
    local r5 = simport.resolveNewSetNames({ { name = 'Nuke' }, { name = 'Nuke' } }, {});
    check('AP9 first keeps name', r5[1].finalName, 'Nuke');
    check('AP10 second gets _Copy (in-batch)', r5[2].finalName, 'Nuke_Copy');
    check('AP11 first not flagged', r5[1].renamed, false);

    -- Bare-string sources are accepted too (kind optional).
    local r6 = simport.resolveNewSetNames({ 'Solo' }, {});
    check('AP12 bare string name', r6[1].finalName, 'Solo');

    -- Degenerate inputs never error.
    check('AP13 nil sources -> empty', #simport.resolveNewSetNames(nil, {}), 0);
    check('AP14 nil existing tolerated', simport.resolveNewSetNames({ { name = 'A' } }, nil)[1].finalName, 'A');
end)();

-- ---------------------------------------------------------------------------
-- AP. weaponfilter -- the pure weapon-type picker filter (#16 F2a, PRD #14)
--
--   Two pure decisions the Add-item picker's weapon-type dropdown is a thin shell over:
--   presentBuckets (which type buckets are actually present in a slot's candidates, in
--   canonical order, no empty buckets) and visible (is a record shown under the marked
--   type set -- {} / nil = "All"). VIEW-ONLY: never eligibility (HARD RULE 6 / ADR 0006).
-- ---------------------------------------------------------------------------
(function()
    local wf = dofile('gear/weaponfilter.lua');   -- forward slash: also loads on Linux CI
    check('AP0 presentBuckets exported', type(wf.presentBuckets), 'function');
    check('AP1 visible exported',        type(wf.visible),        'function');

    -- Candidate pool for a Warrior Main: axes + great axes + a sword, unordered by type,
    -- with a duplicate type and a nil-Type oddball (a virtual entry has no Type).
    local cands = {
        { Name = 'Woodville Axe', Type = 'Axe' },
        { Name = 'Colossal Axe',  Type = 'GreatAxe' },
        { Name = 'Barbaroi Axe',  Type = 'Axe' },        -- duplicate bucket -> one option
        { Name = 'Fransisca',     Type = 'GreatAxe' },
        { Name = 'Firangi',       Type = 'Sword' },
        { Name = 'dlac:AutoCraft', Virtual = true },      -- no Type -> no bucket
    };

    -- 1. presentBuckets: only owned types, canonical order (Sword before Axe before
    --    GreatAxe), de-duplicated, no empty buckets, no bucket for the Type-less oddball.
    local buckets = wf.presentBuckets(cands, 'Main');
    check('AP2 three buckets present',        #buckets, 3);
    check('AP3 canonical order [1] Sword',    buckets[1].key, 'Sword');
    check('AP4 canonical order [2] Axe',      buckets[2].key, 'Axe');
    check('AP5 canonical order [3] GreatAxe', buckets[3].key, 'GreatAxe');
    check('AP6 player-facing label',          buckets[3].label, 'Great Axe');

    -- 2. Empty pool / unknown slot -> no options (dropdown hidden), never an error.
    check('AP7 empty pool -> no buckets',     #wf.presentBuckets({}, 'Main'), 0);
    check('AP8 unfilterable slot -> no buckets', #wf.presentBuckets(cands, 'Head'), 0);
    check('AP9 nil cands -> no buckets',      #wf.presentBuckets(nil, 'Main'), 0);

    -- 3. visible: {} / nil = "All" -> everything shows.
    check('AP10 empty marks = All (axe)',   wf.visible(cands[1], {}, 'Main'), true);
    check('AP11 nil marks = All (sword)',   wf.visible(cands[5], nil, 'Main'), true);

    -- 4. visible: a single marked type shows only that bucket.
    local onlyAxe = { Axe = true };
    check('AP12 marked Axe shows Axe',        wf.visible(cands[1], onlyAxe, 'Main'), true);
    check('AP13 marked Axe hides GreatAxe',   wf.visible(cands[2], onlyAxe, 'Main'), false);
    check('AP14 marked Axe hides Sword',      wf.visible(cands[5], onlyAxe, 'Main'), false);

    -- 5. Multi-pick: Axe + GreatAxe shows both, still hides Sword.
    local axes = { Axe = true, GreatAxe = true };
    check('AP15 multi shows Axe',      wf.visible(cands[1], axes, 'Main'), true);
    check('AP16 multi shows GreatAxe', wf.visible(cands[2], axes, 'Main'), true);
    check('AP17 multi hides Sword',    wf.visible(cands[5], axes, 'Main'), false);

    -- 6. A record with no bucket (virtual / Type-less) is hidden once ANY type is marked,
    --    but shows under "All".
    check('AP18 no-bucket hidden when narrowed', wf.visible(cands[6], onlyAxe, 'Main'), false);
    check('AP19 no-bucket shown under All',       wf.visible(cands[6], {}, 'Main'), true);

    -- 7. Unfilterable slot: a marked filter can't leak in (the predicate is All-open there
    --    only via empty marks; a non-empty mark on an unknown slot hides everything, which
    --    is moot because gearui never shows the dropdown for such a slot).
    check('AP20 bucketOf unknown slot -> nil', wf.bucketOf(cands[1], 'Head'), nil);
end)();

-- APL. weaponfilter legacy Type spellings (Henrik 2026-07-18: Mindie's Lv20
--   Savagery, Type = "Great Axe" WITH a space, vanished under the Great Axe
--   filter while name search found it). Early gear.lua vocabularies wrote
--   display forms; a scan never rewrites an existing entry, so real files mix
--   'Great Axe'/'GreatAxe', 'Hand-to-Hand'/'HandToHand', 'Wind Instrument',
--   bare 'String'... Buckets resolve through normalization (strip
--   non-alphanumerics + casefold + alias) so both spellings are ONE bucket.
-- ---------------------------------------------------------------------------
(function()
    local wf = dofile('gear/weaponfilter.lua');
    -- THE field case: a spaced-Type record is visible under its canonical mark
    check('APL1 Savagery: spaced Type buckets canonically',
        wf.bucketOf({ Name = 'Savagery', Type = 'Great Axe' }, 'Main'), 'GreatAxe');
    check('APL2 ...so the Great Axe mark shows it',
        wf.visible({ Name = 'Savagery', Type = 'Great Axe' }, { GreatAxe = true }, 'Main'), true);
    check('APL3 hyphen drift: Hand-to-Hand', wf.bucketOf({ Type = 'Hand-to-Hand' }, 'Main'), 'HandToHand');
    check('APL4 case drift alone heals too', wf.bucketOf({ Type = 'greataxe' }, 'Main'), 'GreatAxe');
    check('APL5 Range: spaced instrument', wf.bucketOf({ Type = 'Wind Instrument' }, 'Range'), 'WindInstrument');
    check('APL6 Range: legacy bare String aliases', wf.bucketOf({ Type = 'String' }, 'Range'), 'StringInstrument');
    check('APL7 Sub: one-hander with case drift', wf.bucketOf({ Type = 'sword' }, 'Sub'), 'Sword');
    check('APL8 unknown types still pass through', wf.bucketOf({ Type = 'Chainsaw' }, 'Main'), 'Chainsaw');
    -- both spellings in one pool -> ONE dropdown bucket, not two "Great Axe" twins
    local buckets = wf.presentBuckets({
        { Name = 'Savagery',     Type = 'Great Axe' },
        { Name = 'Colossal Axe', Type = 'GreatAxe'  },
    }, 'Main');
    check('APL9 mixed spellings merge to one bucket', #buckets, 1);
    check('APL10 ...the canonical one', buckets[1].key .. '/' .. buckets[1].label, 'GreatAxe/Great Axe');
end)();

-- AP2. weaponfilter Range + Ammo -- the F2b buckets (issue #17, PRD #14)
--
--   Range buckets off the catalog `Type`: Bows (Archery), Guns & Crossbows (Marksmanship
--   -- guns and crossbows folded together), Throwing, plus instruments / rod when owned.
--   Ammo buckets off `AmmoType`: Arrows (Archery), Bolts & Bullets (Marksmanship -- bolts
--   and bullets folded), Throwables (Throwing), and Trinkets (ammo with NO AmmoType, fired
--   by nothing -- Cinderstone, Morion Tathlum). View-only, same as Main (HARD RULE 6).
-- ---------------------------------------------------------------------------
(function()
    local wf = dofile('gear/weaponfilter.lua');

    -- 1. Range: a bow + a crossbow + a gun + a harp + a fishing rod, unordered, with a gun
    --    and a crossbow sharing the Marksmanship bucket (guns & crossbows folded together).
    local range = {
        { Name = 'Test Harp',      Type = 'StringInstrument' },
        { Name = 'Test Bow',       Type = 'Archery' },
        { Name = 'Test Crossbow',  Type = 'Marksmanship' },
        { Name = 'Test Gun',       Type = 'Marksmanship' },   -- same bucket as the crossbow
        { Name = 'Test Rod',       Type = 'FishingRod' },
    };
    local rb = wf.presentBuckets(range, 'Range');
    check('AP2-1 range: four buckets (gun+xbow fold)', #rb, 4);
    check('AP2-2 canonical order [1] Archery',   rb[1].key, 'Archery');
    check('AP2-3 Archery labelled Bows',         rb[1].label, 'Bows');
    check('AP2-4 canonical order [2] Marksmanship', rb[2].key, 'Marksmanship');
    check('AP2-5 Marksmanship label folds both', rb[2].label, 'Guns & Crossbows');
    check('AP2-6 instruments before the rod',    rb[3].key, 'StringInstrument');
    check('AP2-7 fishing rod its own bucket',    rb[4].key, 'FishingRod');
    -- Guns & Crossbows marked: shows both the gun and the crossbow, hides the bow.
    local onlyMarks = { Marksmanship = true };
    check('AP2-8 Marks shows crossbow',  wf.visible(range[3], onlyMarks, 'Range'), true);
    check('AP2-9 Marks shows gun',       wf.visible(range[4], onlyMarks, 'Range'), true);
    check('AP2-10 Marks hides bow',      wf.visible(range[2], onlyMarks, 'Range'), false);

    -- 2. Ammo: arrows + bolts + bullets + a throwable + two trinkets (no AmmoType). Bolts
    --    and bullets fold into one Marksmanship bucket; the trinkets are their own bucket
    --    and must NOT land under arrows / bolts / throwables.
    local ammo = {
        { Name = 'Test Bolt',       AmmoType = 'Marksmanship' },
        { Name = 'Test Arrow',      AmmoType = 'Archery' },
        { Name = 'Test Bullet',     AmmoType = 'Marksmanship' },   -- folds with the bolt
        { Name = 'Test Shuriken',   AmmoType = 'Throwing' },
        { Name = 'Cinderstone' },                                   -- no AmmoType = Trinket
        { Name = 'Morion Tathlum' },                                -- no AmmoType = Trinket
    };
    local ab = wf.presentBuckets(ammo, 'Ammo');
    check('AP2-11 ammo: four buckets (bolt+bullet fold)', #ab, 4);
    check('AP2-12 order [1] Arrows',          ab[1].label, 'Arrows');
    check('AP2-13 order [2] Bolts & Bullets', ab[2].label, 'Bolts & Bullets');
    check('AP2-14 order [3] Throwables',      ab[3].label, 'Throwables');
    check('AP2-15 order [4] Trinkets',        ab[4].label, 'Trinkets');
    -- The Trinket bucket key is the internal sentinel, never a real AmmoType.
    local trinketKey = ab[4].key;
    check('AP2-16 trinket bucketOf Cinderstone', wf.bucketOf(ammo[5], 'Ammo'), trinketKey);
    check('AP2-17 trinket key is not an AmmoType', ammo[1].AmmoType == trinketKey, false);
    -- Bolts & Bullets marked: shows bolt + bullet, hides arrows / throwables / trinkets.
    local onlyBolts = { [ab[2].key] = true };
    check('AP2-18 Marks shows bolt',    wf.visible(ammo[1], onlyBolts, 'Ammo'), true);
    check('AP2-19 Marks shows bullet',  wf.visible(ammo[3], onlyBolts, 'Ammo'), true);
    check('AP2-20 Marks hides arrow',   wf.visible(ammo[2], onlyBolts, 'Ammo'), false);
    check('AP2-21 Marks hides trinket', wf.visible(ammo[5], onlyBolts, 'Ammo'), false);
    -- Trinkets marked: the two sticks show, the fired ammo hides -- the AC's exclusion.
    local onlyTrinket = { [trinketKey] = true };
    check('AP2-22 Trinket shows Cinderstone',  wf.visible(ammo[5], onlyTrinket, 'Ammo'), true);
    check('AP2-23 Trinket shows Morion',       wf.visible(ammo[6], onlyTrinket, 'Ammo'), true);
    check('AP2-24 Trinket hides arrow',        wf.visible(ammo[2], onlyTrinket, 'Ammo'), false);
    check('AP2-25 Trinket hides bolt',         wf.visible(ammo[1], onlyTrinket, 'Ammo'), false);
    check('AP2-26 Trinket hides throwable',    wf.visible(ammo[4], onlyTrinket, 'Ammo'), false);

    -- 3. Present-only + All default carry over to the new slots.
    check('AP2-27 empty ammo pool -> no buckets', #wf.presentBuckets({}, 'Ammo'), 0);
    check('AP2-28 All default shows a trinket',   wf.visible(ammo[5], {}, 'Ammo'), true);
    check('AP2-29 arrows-only range pool -> one bucket',
        #wf.presentBuckets({ { Name = 'Bow', Type = 'Archery' } }, 'Range'), 1);
end)();

-- ---------------------------------------------------------------------------
-- TG. Trigger Groups (G1, ADR 0009): a named action-list matcher generalizing
--     modes. M.groupMatch mirrors M.modeActive's one-of (list = OR) semantics;
--     `group` is specificity tier 45 (below name 50, above contains 40); the
--     Groups section load->serialize is byte-stable beside Modes.
-- ---------------------------------------------------------------------------
(function()
    local groups = {
        StrBlue = { 'Hysteric Barrage', 'Quad. Continuum' },
        MndBlue = { 'Magic Hammer', 'Actinic Burst' },
    };
    -- membership
    check('TG1 member of group',        dispatchM.groupMatch('StrBlue', 'Hysteric Barrage', groups), true);
    check('TG2 non-member',             dispatchM.groupMatch('StrBlue', 'Magic Hammer', groups), false);
    check('TG3 group name CI',          dispatchM.groupMatch('strblue', 'Quad. Continuum', groups), true);
    check('TG4 member name CI',         dispatchM.groupMatch('StrBlue', 'hysteric barrage', groups), true);
    check('TG5 unknown group',          dispatchM.groupMatch('NoSuchGroup', 'Hysteric Barrage', groups), false);
    check('TG6 nil action name',        dispatchM.groupMatch('StrBlue', nil, groups), false);
    -- list value = OR (one-of), exactly like mode lists
    check('TG7 list: first group hits', dispatchM.groupMatch({ 'StrBlue', 'MndBlue' }, 'Hysteric Barrage', groups), true);
    check('TG8 list: second group hits',dispatchM.groupMatch({ 'StrBlue', 'MndBlue' }, 'Actinic Burst', groups), true);
    check('TG9 list: none match',       dispatchM.groupMatch({ 'StrBlue', 'MndBlue' }, 'Head Butt', groups), false);

    -- specificity tier 45: group is a baseline a per-spell `name` overrides, and
    -- it still beats contains / skill.
    check('TG10 group default priority', dispatchM.defaultPriority({ group = 'StrBlue' }), 45);
    check('TG11 name overrides group',   dispatchM.defaultPriority({ group = 'StrBlue', name = 'Quad. Continuum' }), 50);
    check('TG12 group beats contains',   dispatchM.defaultPriority({ group = 'StrBlue' }) > dispatchM.defaultPriority({ contains = 'Continuum' }), true);
    check('TG13 group beats skill',      dispatchM.defaultPriority({ group = 'StrBlue', skill = 'Blue Magic' }), 45);

    -- Groups section load -> serialize is byte-stable alongside Modes, and does
    -- not disturb the handler/mode sections.
    local data = {
        Midcast = {
            { when = { group = 'StrBlue' }, set = 'StrBluGear' },
            { when = { group = { 'StrBlue', 'MndBlue' } }, set = 'AnyBluGear' },
        },
        Modes  = { Weapon = { values = { 'Melee', 'Ranged' }, bind = '^F3' } },
        Groups = groups,
    };
    local text = dispatchM.serializeTriggers(data);
    check('TG14 group condition serialized', text:find('group = "StrBlue"', 1, true) ~= nil, true);
    check('TG15 group list serialized',      text:find('group = { "StrBlue", "MndBlue" }', 1, true) ~= nil, true);
    check('TG16 Groups section present',      text:find('Groups = {', 1, true) ~= nil, true);
    check('TG17 members preserved in order',  text:find('%["StrBlue"%] = { "Hysteric Barrage", "Quad. Continuum" }') ~= nil, true);
    check('TG18 Modes section still present', text:find('Modes = {', 1, true) ~= nil, true);
    -- load back and re-serialize: identical bytes (round-trip stable)
    local t2 = (loadstring or load)(text)();
    check('TG19 reloads to a table', type(t2), 'table');
    check('TG20 round-trip byte-stable', dispatchM.serializeTriggers(t2) == text, true);
end)();

-- ---------------------------------------------------------------------------
-- TM. triggermodel.fromRaw -- the GUI-side raw->edit-model translation (moved
--     out of triggersui; pure, canonEvent injected). THE WIPE CONTRACT: Commit
--     serializes the WHOLE model, so every section serializeTriggers can emit
--     must survive fromRaw or the next Commit erases it (the SetOptions/Modes
--     lesson -- that bug shipped once). TM2 is the contract; the rest pin the
--     normalization the old in-triggersui copy never had a test for.
-- ---------------------------------------------------------------------------
(function()
    package.loaded['dlac\\gear\\groupsmodel'] = package.loaded['dlac\\gear\\groupsmodel'] or dofile('gear/groupsmodel.lua');
    local tmodel = dofile('gear/triggermodel.lua');

    -- A maximal file: every field + section the serializer can emit. Written by
    -- the real serializer, reloaded, translated, re-serialized -- byte-stable.
    local text = dispatchM.serializeTriggers({
        Precast = {
            { when = { skill = 'Enfeebling Magic' }, set = 'FastCast', priority = 12 },
        },
        Midcast = {
            { when = { name = 'Slow II' }, whenAny = { { mode = 'DT' }, { hpbelow = 50 } }, set = { 'MidA', 'MidB' } },
            { when = { group = 'StrBlue' }, equip = { Waist = 'Karin Obi', Head = 'Zha Xia Hat' } },
        },
        Modes  = { Weapon = { values = { 'Melee', 'Ranged' }, bind = '^F3' }, DT = { values = { 'On', 'Off' } } },
        Groups = { StrBlue = { 'Hysteric Barrage', 'Quad. Continuum' } },
    });
    local rawT = (loadstring or load)(text)();
    check('TM1 maximal fixture reloads', type(rawT), 'table');
    local model = tmodel.fromRaw(rawT, dispatchM.canonEvent);
    check('TM2 WIPE CONTRACT model round-trip byte-stable', dispatchM.serializeTriggers(model) == text, true);

    -- Normalization: condition keys lowercase, priority numeric, list shapes kept.
    check('TM3 when keys lowercased',      model.Precast[1].when.skill, 'Enfeebling Magic');
    check('TM4 priority numeric',          model.Precast[1].priority, 12);
    check('TM5 multi-set stays ordered',   model.Midcast[1].set[2], 'MidB');
    check('TM6 whenAny entries carried',   model.Midcast[1].whenAny[2].hpbelow, 50);
    check('TM7 equip payload carried',     model.Midcast[2].equip.Waist, 'Karin Obi');
    check('TM8 Modes carried',             model.Modes.Weapon.bind, '^F3');
    check('TM9 Groups carried',            model.Groups.StrBlue[2], 'Quad. Continuum');

    -- Handler keys canon through the INJECTED fn; unknown sections dropped.
    local m2 = tmodel.fromRaw({ midCAST = { { when = { name = 'X' }, set = 'S' } },
                                Junk    = { { when = {}, set = 'S' } } }, dispatchM.canonEvent);
    check('TM10 handler key canonicalized', type(m2.Midcast), 'table');
    check('TM11 unknown section dropped',   m2.Junk, nil);

    -- Malformed rules are skipped, never carried as garbage.
    local m3 = tmodel.fromRaw({ Midcast = { { set = 'NoWhen' }, { when = { name = 'Y' } }, 'junk' } }, dispatchM.canonEvent);
    check('TM12 malformed rules skipped', #m3.Midcast, 0);

    -- Legacy spellings: whenany, modes, bare mode-value arrays; 1-item set list collapses.
    local m4 = tmodel.fromRaw({ Midcast = { { when = { name = 'Z' }, whenany = { { mode = 'DT' } }, set = { 'OnlyOne' } } },
                                modes = { Idle = { 'On', 'Off' } } }, dispatchM.canonEvent);
    check('TM13 legacy whenany accepted',   m4.Midcast[1].whenAny[1].mode, 'DT');
    check('TM14 1-item set list collapses', m4.Midcast[1].set, 'OnlyOne');
    check('TM15 legacy bare modes array',   m4.Modes.Idle.values[2], 'Off');

    -- No canonEvent: handler sections unreachable, Modes/Groups still carried --
    -- the degraded no-dispatch behavior the Triggers tab always had.
    local m6 = tmodel.fromRaw({ Midcast = { { when = { name = 'X' }, set = 'S' } },
                                Modes = { A = { values = { 'B' } } },
                                Groups = { G = { 'x' } } }, nil);
    check('TM16 no-canon drops handlers', m6.Midcast, nil);
    check('TM17 no-canon keeps Modes',    m6.Modes.A.values[1], 'B');
    check('TM18 no-canon keeps Groups',   m6.Groups.G[1], 'x');
    check('TM19 non-table raw yields {}', next(tmodel.fromRaw(nil, dispatchM.canonEvent)), nil);

    -- Bare toggle definitions (2026-07-20, Mindie BLU): a toggle with no bind
    -- and no values is a REAL definition -- `[name] = {}` must survive the
    -- whole wipe contract, or a plain UI-created toggle vanishes from the
    -- Modes list on the next load.
    local tg = dispatchM.serializeTriggers({ Modes = { Stoneskin = {}, DT = { bind = 'F9' } } });
    check('TM20 bare toggle serialized', tg:find('["Stoneskin"] = {},', 1, true) ~= nil, true);
    local tgM = tmodel.fromRaw((loadstring or load)(tg)(), dispatchM.canonEvent);
    check('TM21 bare toggle survives fromRaw', type(tgM.Modes.Stoneskin) == 'table'
        and tgM.Modes.Stoneskin.values == nil and tgM.Modes.Stoneskin.bind == nil, true);
    check('TM22 bare toggle round-trip byte-stable', dispatchM.serializeTriggers(tgM) == tg, true);
end)();

-- ---------------------------------------------------------------------------
-- TGB. Blueprints pure core (issue #65, slice 1; PRD #64): the per-character
--      library of reusable trigger rules. CRUD, default-name derivation, the
--      stamp transform (entry + a job's trigger data -> NEW data with the rule in
--      its Handler), priority carry-over, identical-rule detection, and a
--      deterministic serialize/parse round-trip. Ashita/imgui/file-IO-free -- the
--      Groups model precedent (TGM/TGI). The strongest stamp check runs the
--      result through the REAL dispatch serializer + reload, so "stamp lands an
--      identical rule in the target handler" is pinned end to end.
-- ---------------------------------------------------------------------------
(function()
    local bp = dofile('gear/blueprintsmodel.lua');

    -- The demo rule: slept/lullaby'd -> inline equip (self-contained, zero deps).
    local sleepRule = { when = {}, whenAny = { { buff = 'Sleep' }, { buff = 'Lullaby' } },
                        equip = { Ear1 = 'Toxic Earring' } };

    -- Default-name derivation (PRD story 5): a readable summary of the condition.
    check('TGB1 default name from whenAny OR', bp.defaultName(sleepRule), 'Sleep or Lullaby');
    check('TGB2 default name from & value',    bp.defaultName({ when = { name = 'Slow II' }, set = 'X' }), 'Slow II');
    check('TGB3 default name flag key',         bp.defaultName({ when = { moving = true }, set = 'X' }), 'moving');
    check('TGB4 default name any -> "Any"',     bp.defaultName({ when = { any = true }, set = 'X' }), 'Any');
    check('TGB5 default name & + or',           bp.defaultName({ when = { status = 'Engaged' },
                                                                 whenAny = { { buff = 'Sleep' }, { buff = 'Lullaby' } }, set = 'X' }),
          'Engaged + Sleep or Lullaby');

    -- CRUD: add captures a deep copy (detached from the source rule), rename, remove.
    local lib = {};
    local okA, errA = bp.add(lib, 'Midcast', sleepRule);
    check('TGB6 add ok',            okA and errA, nil);
    check('TGB7 add appended',      #lib, 1);
    check('TGB8 add derived name',  lib[1].name, 'Sleep or Lullaby');
    check('TGB9 add carries handler', lib[1].handler, 'Midcast');
    sleepRule.equip.Ear1 = 'Mutated';   -- mutate the SOURCE after capture
    check('TGB10 entry detached from source', lib[1].rule.equip.Ear1, 'Toxic Earring');
    sleepRule.equip.Ear1 = 'Toxic Earring';
    check('TGB11 add bad handler refused', (bp.add(lib, 'Nope', sleepRule)), false);
    check('TGB12 add no-action refused',   (bp.add(lib, 'Midcast', { when = { name = 'X' } })), false);
    bp.add(lib, 'Precast', { when = { skill = 'Enfeebling Magic' }, set = 'FastCast', priority = 12 }, 'Custom Name');
    check('TGB13 custom name kept', lib[2].name, 'Custom Name');
    check('TGB14 rename ok', (bp.rename(lib, 1, 'Sleep protection')), true);
    check('TGB15 renamed',   lib[1].name, 'Sleep protection');
    check('TGB16 rename blank refused', (bp.rename(lib, 1, '   ')), false);

    -- Stamp: NEW data table, rule appended to the entry's Handler, priority carried
    -- verbatim, source data untouched (non-mutating -> detached).
    local jobData = { Default = { { when = { status = 'Idle' }, set = 'Idle' } } };
    local out = bp.stamp(lib[1], jobData);
    check('TGB17 stamp lands in Handler',  #out.Midcast, 1);
    check('TGB18 stamp keeps inline equip', out.Midcast[1].equip.Ear1, 'Toxic Earring');
    check('TGB19 stamp leaves source intact', jobData.Midcast, nil);
    check('TGB20 stamp preserves other handlers', out.Default[1].set, 'Idle');
    local out2 = bp.stamp(lib[2], out);
    check('TGB21 priority carried verbatim', out2.Precast[1].priority, 12);
    -- edit a stamped rule -> the library entry is UNCHANGED (detached both ways)
    out2.Precast[1].priority = 999;
    check('TGB22 stamped edit does not touch the Blueprint', lib[2].rule.priority, 12);

    -- Identical-rule detection: warn-but-allow double stamping.
    check('TGB23 identical detected after stamp', bp.identicalExists(lib[1], out), true);
    check('TGB24 not identical in a fresh job',   bp.identicalExists(lib[1], { Midcast = {} }), false);
    -- priority is part of identity (a re-priced rule is not "identical")
    local reprio = bp.deepcopy(lib[2]); reprio.rule.priority = 34;
    check('TGB25 differing priority is not identical', bp.identicalExists(reprio, out2), false);

    -- Serialize / parse round-trip (the library file), byte-stable.
    local text = bp.serialize(lib);
    check('TGB26 serialize returns text', type(text), 'string');
    check('TGB27 file is a blueprints table', text:find('blueprints = {', 1, true) ~= nil, true);
    check('TGB28 file carries the version',  text:find('version = 1', 1, true) ~= nil, true);
    local lib2, perr = bp.parse(text);
    check('TGB29 parse ok',        perr, nil);
    check('TGB30 parse count',     #lib2, 2);
    check('TGB31 round-trip byte-stable', bp.serialize(lib2) == text, true);
    check('TGB32 parse recovers the rule', lib2[1].rule.equip.Ear1, 'Toxic Earring');
    -- the sandbox: a hostile blob errors, never runs
    check('TGB33 sandbox blocks a global', (select(2, bp.parse('return { blueprints = os.time() }'))) ~= nil
        or type(select(1, bp.parse('return { blueprints = os.time() }'))) == 'table', true);

    -- END-TO-END through the REAL dispatch serializer + reload: a stamp lands an
    -- identical rule that survives the actual commit path the Triggers tab uses.
    local committed = dispatchM.serializeTriggers(out);
    local reloaded  = (loadstring or load)(committed)();
    check('TGB34 stamped rule survives serialize+reload',
        type(reloaded.Midcast) == 'table' and reloaded.Midcast[1].equip.Ear1, 'Toxic Earring');
    -- normalize the reloaded file the way the engine does and confirm the rule is live
    local norm = dispatchM._normalize(reloaded);
    local found = false;
    for _, r in ipairs(norm.Midcast or {}) do
        if r.equip and r.equip.Ear1 == 'Toxic Earring' then found = true; end
    end
    check('TGB35 engine normalizes the stamped rule', found, true);

    -- ------- Slice 2 (issue #66): text sharing -- View text / Copy all / paste-import. -------

    -- Round-trip is byte-stable: serialize -> parse -> serialize is identical (headless, pure
    -- core). Both one-entry (View text) and multi-entry (Copy all) blobs are the SAME format.
    local oneBlob = bp.serializeOne(lib[1]);
    check('TGB36 one-entry blob is list-shaped', oneBlob:find('blueprints = {', 1, true) ~= nil, true);
    local one, oneErr = bp.parse(oneBlob);
    check('TGB37 one-entry blob parses', oneErr == nil and #one, 1);
    check('TGB38 one-entry round-trip byte-stable', bp.serialize(one) == oneBlob, true);
    local allBlob = bp.serialize(lib);
    local many, manyErr = bp.parse(allBlob);
    check('TGB39 multi-entry blob parses', manyErr == nil and #many, 2);
    check('TGB40 multi-entry round-trip byte-stable', bp.serialize(many) == allBlob, true);

    -- Live-preview: parse + classify in one call, entries listed before commit.
    local emptyLib = {};
    local prev, prevErr = bp.previewImport(allBlob, emptyLib);
    check('TGB41 preview lists entries before commit', prevErr == nil and #prev.entries, 2);
    check('TGB42 preview: all new against an empty library', #prev.created, 2);
    check('TGB43 preview: nothing collides yet', #prev.collided, 0);

    -- Collision matrix. CREATED: both import into the empty library.
    local sumNew = bp.applyImport(emptyLib, prev.entries, false);
    check('TGB44 created: both imported', sumNew.created, 2);
    check('TGB45 created: library now holds them', #emptyLib, 2);
    check('TGB46 created: entry detached from the blob', emptyLib[1].rule.equip.Ear1, 'Toxic Earring');

    -- COLLIDE-REFUSE (default): re-importing the same blob touches nothing.
    local prev2 = bp.previewImport(allBlob, emptyLib);
    check('TGB47 collide classified case-insensitively', #prev2.collided, 2);
    local sumRefuse = bp.applyImport(emptyLib, prev2.entries, false);
    check('TGB48 collide-refuse: none overwritten', sumRefuse.updated, 0);
    check('TGB49 collide-refuse: all refused',       sumRefuse.refused, 2);
    check('TGB50 collide-refuse: library unchanged',  #emptyLib, 2);

    -- COLLIDE-OVERWRITE (confirmed): the same names, a CHANGED rule -> the entry adopts it.
    local changed = bp.deepcopy(lib);
    changed[1].rule.equip.Ear1 = 'Star Earring';   -- same name, different rule
    local sumOver = bp.applyImport(emptyLib, changed, true);
    check('TGB51 collide-overwrite: both updated', sumOver.updated, 2);
    check('TGB52 collide-overwrite: no growth',    #emptyLib, 2);
    local overIdx = bp.findEntryCI(emptyLib, changed[1].name);
    check('TGB53 collide-overwrite: rule adopted', emptyLib[overIdx].rule.equip.Ear1, 'Star Earring');

    -- Case-insensitive collision: a different-cased name still collides (never a duplicate).
    local recased = bp.deepcopy(lib[1]); recased.name = string.upper(lib[1].name);
    local _, coll = bp.classifyImport({ recased }, emptyLib);
    check('TGB54 collide-refuse matches across case', #coll, 1);

    -- Sandbox hardness (issue #66): a blob calling a global, or a non-text (bytecode) load,
    -- errors WITHOUT executing (the TGI* hardened-env precedent).
    local badGlobal, gErr = bp.parse('return { blueprints = { os.execute("echo pwned") } }');
    check('TGB55 sandbox: a global errors, never runs', badGlobal == nil and type(gErr), 'string');
    local bytecode = string.dump(load('return {}'));
    local badBytes = bp.parse(bytecode);
    check('TGB56 sandbox: non-text (bytecode) load refused', badBytes, nil);
    -- previewImport surfaces the same parse error (nil + message), never a crash.
    local nilPrev, nilErr = bp.previewImport('return function() end', emptyLib);
    check('TGB57 preview surfaces a bad blob as an error', nilPrev == nil and type(nilErr), 'string');
end)();

-- ---------------------------------------------------------------------------
-- PM. Player-state trigger conditions (v53): hpBelow/hpAbove, mpBelow/mpAbove,
--     tpBelow/tpAbove (strict compares off ctx.player) and buff/buffNot (the
--     per-dispatch buff set; tests inject ctx.buffs -- the seam the matchers
--     read first). Unreadable state matches NEITHER polarity: a failed read
--     must never flap gear on OR off.
-- ---------------------------------------------------------------------------
(function()
    local mm = dispatchM._matchers;
    local ctx = { player = { HPP = 40, MPP = 80, TP = 1200 } };
    check('PM1 hpBelow fires under the line',   mm.hpbelow(50, ctx), true);
    check('PM2 hpBelow strict at the line',     mm.hpbelow(40, ctx), false);
    check('PM3 hpAbove quiet under the line',   mm.hpabove(50, ctx), false);
    check('PM4 mpAbove fires over the line',    mm.mpabove(50, ctx), true);
    check('PM5 mpBelow quiet over the line',    mm.mpbelow(50, ctx), false);
    check('PM6 tpAbove fires at 1200 > 1000',   mm.tpabove(1000, ctx), true);
    check('PM7 tpBelow quiet at 1200',          mm.tpbelow(1000, ctx), false);
    check('PM8 string threshold coerces',       mm.hpbelow('50', ctx), true);
    check('PM9 nil player never matches',       mm.hpbelow(50, {}), false);
    check('PM10 junk threshold never matches',  mm.hpbelow('half', ctx), false);
    local bctx = { buffs = { sleep = true, [2] = true, refresh = true } };
    check('PM11 buff by name, case-insensitive', mm.buff('Sleep', bctx), true);
    check('PM12 buff by id',                     mm.buff(2, bctx), true);
    check('PM13 buff absent',                    mm.buff('Haste', bctx), false);
    check('PM14 buffNot fires when absent',      mm.buffnot('Haste', bctx), true);
    check('PM15 buffNot quiet when present',     mm.buffnot('Refresh', bctx), false);
    -- Unknown state: kill the game read entirely -- both polarities stay quiet.
    local savedAC = AshitaCore;
    AshitaCore = nil;
    local dead = {};
    check('PM16 unreadable buffs: buff quiet',    mm.buff('Sleep', dead), false);
    check('PM17 unreadable buffs: buffNot quiet', mm.buffnot('Sleep', dead), false);
    AshitaCore = savedAC;
    -- Tier + pretty-case + round-trip: the new keys are first-class vocabulary.
    check('PM18 default priority just under mode',
        dispatchM.defaultPriority({ hpbelow = 50, name = 'Cure IV' }), 95);
    local text = dispatchM.serializeTriggers({
        Default = { { when = { hpbelow = 50, buffnot = 'Refresh' }, set = 'LowHp' } },
    });
    check('PM19 pretty keys serialize', text:find('hpBelow = 50', 1, true) ~= nil, true);
    check('PM20 buffNot serializes',    text:find('buffNot = "Refresh"', 1, true) ~= nil, true);
    local t2 = (loadstring or load)(text)();
    check('PM21 round-trip byte-stable', dispatchM.serializeTriggers(t2) == text, true);
end)();

-- ---------------------------------------------------------------------------
-- PN. Player conditions v54: canonical raw + percent keys (playerHPBelow/...)
--     and the whenAny OR group -- a rule matches when ALL `when` conditions
--     hold OR ANY whenAny entry holds; an OR-only rule is NOT always-on.
-- ---------------------------------------------------------------------------
(function()
    local mm = dispatchM._matchers;
    local ctx = { player = { HP = 320, HPP = 40, MP = 90, MPP = 75, TP = 1200 } };
    check('PN1 raw HP below',            mm.playerhpbelow(500, ctx), true);
    check('PN2 raw HP not below',        mm.playerhpbelow(300, ctx), false);
    check('PN3 percent HP below',        mm.playerhppercentbelow(50, ctx), true);
    check('PN4 raw vs percent distinct', mm.playerhpabove(300, ctx) and not mm.playerhppercentabove(50, ctx), true);
    check('PN5 raw MP above',            mm.playermpabove(50, ctx), true);
    check('PN6 percent MP below quiet',  mm.playermppercentbelow(75, ctx), false);
    check('PN7 v53 alias still percent', mm.hpbelow(50, ctx), true);

    -- OR-group evaluation through the engine's own matches()
    local mt = dispatchM._matches;
    local bctx = { player = { HPP = 90 }, buffs = { sleep = true } };
    local r1 = { when = { hpbelow = 50 },
                 whenAny = { { buff = 'Lullaby' }, { buff = 'Sleep' } } };
    check('PN8 AND misses, OR hits -> match', mt(r1, bctx), true);
    local r2 = { when = { hpbelow = 95 },
                 whenAny = { { buff = 'Lullaby' } } };
    check('PN9 AND hits, OR misses -> match', mt(r2, bctx), true);
    local r3 = { when = { hpbelow = 50 },
                 whenAny = { { buff = 'Lullaby' } } };
    check('PN10 both legs miss -> no match', mt(r3, bctx), false);
    local r4 = { when = {}, whenAny = { { buff = 'Haste' } } };
    check('PN11 OR-only rule is NOT always-on', mt(r4, bctx), false);
    local r5 = { when = {}, whenAny = { { buff = 'Sleep' } } };
    check('PN12 OR-only rule fires on its hit', mt(r5, bctx), true);
    check('PN13 no whenAny keeps legacy any-shape', mt({ when = {} }, bctx), true);
    local r6 = { when = {}, whenAny = { { buff = 'Sleep', hpbelow = 50 } } };
    check('PN14 multi-key OR entry is AND within', mt(r6, bctx), false);

    -- normalize: whenAny parsed, priority from OR keys, label carries the OR leg
    local norm = dispatchM._normalize({
        Default = { { when = { status = 'Engaged' },
                      whenAny = { { buff = 'Sleep' }, { buff = 'Lullaby' } },
                      set = 'WakeUp' } },
    });
    local nr = norm.Default[1];
    check('PN15 whenAny normalized', #nr.whenAny, 2);
    check('PN16 OR keys raise the default priority', nr.prio, 95);
    check('PN17 label carries the OR leg',
        nr.label, 'status=Engaged|buff=Lullaby|buff=Sleep');
    local bad = select(2, dispatchM._normalize({
        Default = { { when = { any = true }, whenAny = { { nosuchcond = 1 } }, set = 'X' } },
    }));
    check('PN18 unknown OR key drops the rule with a warn', #bad >= 1, true);
    check('PN19 defaultPriority takes whenAny',
        dispatchM.defaultPriority({ status = 'Engaged' }, { { buff = 'Sleep' } }), 95);

    -- serializer: whenAny round-trip byte-stable, canonical pretty keys
    local text = dispatchM.serializeTriggers({
        Default = { { when = { playerhppercentbelow = 50 },
                      whenAny = { { buff = 'Lullaby' }, { buff = 'Sleep' } },
                      set = 'WakeUp' } },
    });
    check('PN20 canonical pretty key serializes',
        text:find('playerHPPercentBelow = 50', 1, true) ~= nil, true);
    check('PN21 whenAny serializes in author order',
        text:find('whenAny = { { buff = "Lullaby" }, { buff = "Sleep" } }', 1, true) ~= nil, true);
    local t2 = (loadstring or load)(text)();
    check('PN22 OR round-trip byte-stable', dispatchM.serializeTriggers(t2) == text, true);
end)();

-- ---------------------------------------------------------------------------
-- CS. Trigger CASES, read-side (issue #125, slice 1/5). matchedCase names the
--     winning case for /dl why over the EXISTING schema: the together-block (the
--     `&` leg), a "standalone" (single-condition `|` entry), or a "case"
--     (multi-condition `|` entry). It mirrors matches() EXACTLY -- same MATCHERS,
--     together-block first (only when NON-empty and fully true -- the OR-only
--     law), else the first `|` entry that holds in file order.
-- ---------------------------------------------------------------------------
(function()
    local mc = dispatchM.matchedCase;
    local mt = dispatchM._matches;
    local ctx  = { player = { HPP = 90 }, buffs = { sleep = true } };  -- hpbelow is a percent alias
    local ctxL = { player = { HPP = 40 }, buffs = { sleep = true } };

    check('CS1 no whenAny -> names nothing (reads as before)',
        mc({ when = { hpbelow = 50 } }, ctx), nil);
    check('CS2 together-block holds -> together-block',
        mc({ when = { hpbelow = 95 }, whenAny = { { buff = 'Lullaby' } } }, ctx), 'together-block');
    check('CS3 together-block misses, standalone hits',
        mc({ when = { hpbelow = 50 }, whenAny = { { buff = 'Sleep' } } }, ctx), 'standalone buff=Sleep');
    check('CS4 OR-only rule names its standalone, never the empty together-block',
        mc({ when = {}, whenAny = { { buff = 'Sleep' } } }, ctx), 'standalone buff=Sleep');
    check('CS5 multi-condition entry that holds -> case (AND-within-OR, sorted)',
        mc({ when = { hpbelow = 30 }, whenAny = { { buff = 'Sleep', hpbelow = 50 } } }, ctxL),
        'case buff=Sleep & hpbelow=50');
    check('CS6 multi-condition entry with one miss does NOT name it',
        mc({ when = { hpbelow = 30 }, whenAny = { { buff = 'Sleep', hpbelow = 30 } } }, ctxL), nil);
    check('CS7 together-block wins when BOTH legs hold (checked first, like the engine)',
        mc({ when = { hpbelow = 95 }, whenAny = { { buff = 'Sleep' } } }, ctx), 'together-block');
    check('CS8 first standalone that holds wins (file order)',
        mc({ when = {}, whenAny = { { buff = 'Haste' }, { buff = 'Sleep' } } }, ctx), 'standalone buff=Sleep');
    -- consistency: a case-bearing rule names a case IFF matches() fires.
    local rhit  = { when = { hpbelow = 50 }, whenAny = { { buff = 'Sleep' } } };
    local rmiss = { when = { hpbelow = 50 }, whenAny = { { buff = 'Haste' } } };
    check('CS9 names a case exactly when matches() fires (hit)',
        (mc(rhit, ctx) ~= nil) == mt(rhit, ctx) and mt(rhit, ctx), true);
    check('CS10 names nothing exactly when matches() misses',
        mc(rmiss, ctx) == nil and mt(rmiss, ctx) == false, true);
end)();

-- ---------------------------------------------------------------------------
-- CX. Trigger CASES, the schema backbone (issue #126, slice 2/5). The `cases`
--     tier in the engine + BOTH serializers. One sentence, both tiers: `&`
--     things bind into one together-block; each `|` thing stands alone; fire if
--     the together-block holds, or any `|` thing does. Canonical serialization
--     is oldest-form-first (a `| case` with only `&` rows is a whenAny multi-
--     entry); any rule with a cases list carries the always-true version guard.
-- ---------------------------------------------------------------------------
(function()
    local mt = dispatchM._matches;
    local mc = dispatchM.matchedCase;
    local bp = dofile('gear/blueprintsmodel.lua');
    package.loaded['dlac\\gear\\groupsmodel'] = package.loaded['dlac\\gear\\groupsmodel'] or dofile('gear/groupsmodel.lua');
    local tmodel = dofile('gear/triggermodel.lua');
    local ctx = { action = { Name = 'Fire IV', Type = 'Black Magic', Element = 'Fire' },
                  player = { Status = 'Engaged', HPP = 90, TP = 1500 }, buffs = { sleep = true } };

    -- ---- Match seam ----
    -- (A) `& case` GATES the body: BlackMagic AND (Fire|Ice|Thunder). Together-
    -- block holds only when the & case's internal | leg does too.
    local rGate = { when = { magictype = 'Black Magic' }, cases = {
        { op = '&', when = {}, whenAny = { { element = 'Fire' }, { element = 'Ice' } } } } };
    check('CX1 & case gates: body + case both hold -> fire', mt(rGate, ctx), true);
    local ctxThunder = { action = { Name = 'Thunder', Type = 'Black Magic', Element = 'Thunder' } };
    check('CX2 & case gates: case fails -> no fire', mt(rGate, ctxThunder), false);
    local ctxWhite = { action = { Name = 'Cure', Type = 'White Magic', Element = 'Light' } };
    check('CX3 & case gates: body fails -> no fire', mt(rGate, ctxWhite), false);

    -- (B) `| case` fires INDEPENDENTLY of the body (OR of ANDs).
    local rOr = { when = { status = 'Engaged', tpabove = 1000 }, cases = {
        { op = '|', when = { magictype = 'Black Magic' }, whenAny = { { element = 'Fire' } } } } };
    check('CX4 | case fires alone (body misses, case hits)',
        mt(rOr, { action = { Type = 'Black Magic', Element = 'Fire' }, player = { Status = 'Idle', TP = 0 } }), true);
    check('CX5 together-block fires alone (case misses, body hits)',
        mt(rOr, { player = { Status = 'Engaged', TP = 1500 } }), true);
    check('CX6 both miss -> no fire',
        mt(rOr, { player = { Status = 'Idle', TP = 0 } }), false);

    -- (C) empty-together-block law at BOTH tiers: OR-only is never always-on.
    local rOrOnly = { when = {}, cases = { { op = '|', when = { buff = 'Sleep' } } } };
    check('CX7 tier-2 OR-only fires on its hit', mt(rOrOnly, ctx), true);
    check('CX8 tier-2 OR-only is NOT always-on',
        mt(rOrOnly, { buffs = {} }), false);
    -- internal legs match by the same sentence: an & case that is OR-only inside
    -- needs one internal | to hold (tier-1 law inside a tier-2 member).
    local rInner = { when = { magictype = 'Black Magic' }, cases = {
        { op = '&', when = {}, whenAny = { { element = 'Fire' }, { element = 'Ice' } } } } };
    check('CX9 internal OR-only case: no internal hit -> no fire',
        mt(rInner, { action = { Type = 'Black Magic', Element = 'Wind' } }), false);

    -- ---- matchedCase for /dl why ----
    check('CX10 & case in the together-block names together-block', mc(rGate, ctx), 'together-block');
    check('CX11 | case names its full leg',
        mc(rOr, { action = { Type = 'Black Magic', Element = 'Fire' }, player = { Status = 'Idle', TP = 0 } }),
        'case magictype=Black Magic & (element=Fire)');
    check('CX12 case-less rule still names nothing', mc({ when = { status = 'Engaged' } }, ctx), nil);

    -- ---- Auto-priority = max tier over EVERY leg of EVERY case ----
    -- body magicType(30) + an & case whose | leg holds `mode`(100): prio 100.
    local pRule = { when = { magictype = 'Black Magic' }, cases = {
        { op = '&', when = {}, whenAny = { { mode = 'Burst' } } } } };
    check('CX13 auto-priority spans cases', dispatchM.defaultPriority(pRule.when, pRule.whenAny, pRule.cases), 100);
    check('CX14 the guard never moves priority',
        dispatchM.defaultPriority({ any = true, hascases = true }, nil, nil), 10);

    -- ---- Labels: case-less byte-identical; case-bearing deterministic ----
    check('CX15 case-less label byte-identical to today',
        dispatchM.ruleLabel({ status = 'Engaged' }, { { buff = 'Sleep' } }, nil),
        'status=Engaged|buff=Sleep');
    -- case order irrelevant -> stable label (sorted), never a table address.
    local casesA = { { op = '|', when = { buff = 'Sleep' } }, { op = '&', when = { element = 'Fire' } } };
    local casesB = { { op = '&', when = { element = 'Fire' } }, { op = '|', when = { buff = 'Sleep' } } };
    check('CX16 case-bearing label is order-stable',
        dispatchM.ruleLabel({ status = 'Engaged' }, nil, casesA)
        == dispatchM.ruleLabel({ status = 'Engaged' }, nil, casesB), true);

    -- ---- normalize: validate legs, drop-with-warn, empty-drop, guard-strip ----
    local nOut, nWarn = dispatchM._normalize({ Midcast = { {
        when = { magictype = 'Black Magic', hascases = true }, cases = {
            { op = '&', when = {}, whenAny = { { element = 'Fire' } } } }, set = 'Nuke' } } });
    local nr = nOut.Midcast[1];
    check('CX17 normalize keeps the cases', nr.cases and #nr.cases, 1);
    check('CX18 normalize STRIPS the guard from the body', nr.when.hascases, nil);
    check('CX19 normalize priority spans cases (element 30)', nr.prio, 30);
    local badCase = select(2, dispatchM._normalize({ Midcast = { {
        when = { any = true }, cases = { { op = '&', when = { nosuchcond = 1 } } }, set = 'X' } } }));
    check('CX20 unknown key in a case drops the rule with a warn', #badCase >= 1, true);
    local badOp = select(2, dispatchM._normalize({ Midcast = { {
        when = { any = true }, cases = { { when = { element = 'Fire' } } }, set = 'X' } } }));
    check('CX21 a case with no operator drops the rule', #badOp >= 1, true);
    local emptyCase = dispatchM._normalize({ Midcast = { {
        when = { status = 'Engaged' }, cases = { { op = '&', when = {} } }, set = 'X' } } });
    check('CX22 an empty case is dropped at normalization', emptyCase.Midcast[1].cases, nil);

    -- ---- Serializer: case-less byte-identical (PINNED invariant) ----
    local caselessData = { Midcast = {
        { when = { name = 'Slow II' }, whenAny = { { mode = 'DT' }, { hpbelow = 50 } }, set = 'X' },
        { when = { status = 'Engaged' }, set = { 'A', 'B' }, priority = 40 },
    } };
    local caseless = dispatchM.serializeTriggers(caselessData);
    check('CX23 case-less rules never emit a cases list', caseless:find('cases', 1, true), nil);
    check('CX24 case-less rules never emit the guard', caseless:find('hasCases', 1, true), nil);

    -- ---- Oldest-form-first: a | case with only & conditions -> whenAny entry ----
    local oldForm = dispatchM.serializeTriggers({ Midcast = { {
        when = {}, cases = { { op = '|', when = { status = 'Engaged', tpabove = 1000 } } }, set = 'X' } } });
    check('CX25 | case (only &) serializes as a whenAny multi-entry',
        oldForm:find('whenAny = { { status = "Engaged", tpAbove = 1000 } }', 1, true) ~= nil, true);
    check('CX26 ...and NOT as a cases list (no guard needed either)',
        oldForm:find('cases', 1, true) == nil and oldForm:find('hasCases', 1, true) == nil, true);

    -- ---- Guard: present iff a real cases list survives; always-true, bottom tier ----
    local withGuard = dispatchM.serializeTriggers({ Midcast = { {
        when = { magictype = 'Black Magic' }, cases = {
            { op = '&', when = {}, whenAny = { { element = 'Fire' } } } }, set = 'X' } } });
    check('CX27 a rule with a cases list carries the guard',
        withGuard:find('hasCases = true', 1, true) ~= nil, true);
    check('CX28 the guard is an always-true matcher', dispatchM._matchers.hascases(true, {}), true);

    -- ---- The MAXIMAL fixture: every construct at once, byte-stable through BOTH
    --      serializers, and the two serializers are byte-parity mirrors. ----
    local maximal = { when = { magictype = 'Black Magic' },        -- body & leg
                      whenAny = { { buff = 'Sleep' } },            -- body | leg
                      cases = {
                          { op = '&', when = {}, whenAny = { { element = 'Fire' }, { element = 'Ice' } } },  -- & case, internal |
                          { op = '|', when = { status = 'Engaged', tpabove = 1000 } },                       -- | case, only & -> oldest form
                      },
                      set = 'Nuke' };
    local maxText = dispatchM.serializeTriggers({ Midcast = { maximal } });
    local maxRaw  = (loadstring or load)(maxText)();
    check('CX29 maximal fixture round-trips byte-stable (trigger serializer)',
        dispatchM.serializeTriggers(maxRaw) == maxText, true);
    -- through the model (the Commit path) -- the wipe contract, extended to cases.
    local maxModel = tmodel.fromRaw(maxRaw, dispatchM.canonEvent);
    check('CX30 maximal fixture round-trips byte-stable through the model',
        dispatchM.serializeTriggers(maxModel) == maxText, true);
    -- through the blueprints emitter -- the parity-pinned MIRROR: its per-rule body
    -- is byte-identical to what the trigger serializer writes.
    local bpBody = bp.emitRule(maximal, dispatchM.PRETTY_KEY);
    check('CX31 blueprint emitter is byte-parity with the trigger serializer',
        maxText:find(bpBody, 1, true) ~= nil, true);
    -- a case-bearing blueprint round-trips byte-stably through its own library format.
    local lib = {}; bp.add(lib, 'Midcast', maximal);
    local libText = bp.serialize(lib, dispatchM.PRETTY_KEY);
    local libBack = bp.parse(libText);
    check('CX32 blueprint library round-trip byte-stable with cases',
        bp.serialize(libBack, dispatchM.PRETTY_KEY) == libText, true);
    check('CX33 blueprint kept the & case', libBack[1].rule.cases[1].op, '&');

    -- ---- The version-guard contract, THIS engine's half: it knows `hasCases`, so
    --      the guarded maximal rule normalizes cleanly (no warn, rule kept) and
    --      still fires exactly as authored. An OLDER engine lacks the key, so its
    --      normalize would drop the rule with the standard unknown-condition warn
    --      (the "warn, never misread" law) -- the same drop PN18 pins for any
    --      unknown key. Here we pin our half: we do NOT drop it. ----
    local guNorm, guWarn = dispatchM._normalize({ Midcast = { maxRaw.Midcast[1] } });
    check('CX34 this engine accepts the guarded rule (no warn, rule kept)',
        #guWarn == 0 and guNorm.Midcast and #guNorm.Midcast, 1);
    check('CX35 the reloaded guarded rule still fires as authored',
        dispatchM._matches(guNorm.Midcast[1], ctx), true);
end)();

-- ---------------------------------------------------------------------------
-- PT. Pet conditions (engine v63): pet / petStatus / petName off ctx.pet
--     (gData.GetPet() -- nil petless AND at pet HPP 0, so a dead pet reads as
--     NO pet: pet=false fires). petStatus/petName IMPLY existence -- they must
--     never match a petless job (petStatus='Idle' is not "no pet"). Tiers 22/23
--     sit between status (20) and moving (25): a pet-refined rule outranks its
--     base status rule with no hand priority; petName is identity (name tier).
-- ---------------------------------------------------------------------------
(function()
    local mm = dispatchM._matchers;
    local petless = { player = { Status = 'Idle' } };
    local out = { player = { Status = 'Idle' },
                  pet = { Name = 'Garuda', Status = 'Engaged', HPP = 100, TP = 0 } };
    check('PT1 pet=true fires with a pet out',    mm.pet(true, out), true);
    check('PT2 pet=true quiet petless',           mm.pet(true, petless), false);
    check('PT3 pet=false fires petless',          mm.pet(false, petless), true);
    check('PT4 pet=false quiet with a pet out',   mm.pet(false, out), false);
    check('PT5 petStatus matches case-insensitively', mm.petstatus('engaged', out), true);
    check('PT6 petStatus wrong state quiet',      mm.petstatus('Idle', out), false);
    check('PT7 petStatus NEVER matches petless',  mm.petstatus('Idle', petless), false);
    check('PT8 petName matches case-insensitively', mm.petname('garuda', out), true);
    check('PT9 petName other pet quiet',          mm.petname('Carbuncle', out), false);
    check('PT10 petName petless quiet',           mm.petname('Garuda', petless), false);
    -- Tier ordering (the overlay ladder, no hand priorities anywhere):
    check('PT11 status+pet outranks bare status',
        dispatchM.defaultPriority({ status = 'Engaged', pet = true })
            > dispatchM.defaultPriority({ status = 'Engaged' }), true);
    check('PT12 petStatus outranks pet-exists',
        dispatchM.defaultPriority({ petstatus = 'Engaged' })
            > dispatchM.defaultPriority({ pet = true }), true);
    check('PT13 moving still overlays petStatus',
        dispatchM.defaultPriority({ moving = true })
            > dispatchM.defaultPriority({ petstatus = 'Engaged' }), true);
    check('PT14 petName sits at the name tier',
        dispatchM.defaultPriority({ petname = 'Garuda' }), 50);
    -- The player x pet 2x2 through the engine's own matches() -- the classic
    -- BST postures, incl. "master idle while the pet fights".
    local mt = dispatchM._matches;
    local r = { when = { status = 'Idle', petstatus = 'Engaged' } };
    check('PT15 idle + pet fighting fires',
        mt(r, { player = { Status = 'Idle' }, pet = { Status = 'Engaged' } }), true);
    check('PT16 same rule quiet when the pet idles',
        mt(r, { player = { Status = 'Idle' }, pet = { Status = 'Idle' } }), false);
    -- Serializer: pretty spellings round-trip byte-stable, pet = false included
    -- (false is a real value -- it must not vanish like nil).
    local text = dispatchM.serializeTriggers({
        Default = {
            { when = { status = 'Idle', petstatus = 'Engaged' }, set = 'Idle_PetFight' },
            { when = { pet = false }, set = 'NoPet' },
            { when = { petname = 'Carbuncle' }, set = 'Perp_Carby' },
        },
    });
    check('PT17 petStatus serializes pretty', text:find('petStatus = "Engaged"', 1, true) ~= nil, true);
    check('PT18 pet = false serializes',      text:find('pet = false', 1, true) ~= nil, true);
    check('PT19 petName serializes pretty',   text:find('petName = "Carbuncle"', 1, true) ~= nil, true);
    local t2 = (loadstring or load)(text)();
    check('PT20 round-trip byte-stable', dispatchM.serializeTriggers(t2) == text, true);
    -- normalize: the new keys are first-class vocabulary, priorities derive.
    local norm = dispatchM._normalize({
        Default = { { when = { status = 'Idle', petStatus = 'Engaged' }, set = 'Idle_PetFight' } },
    });
    check('PT21 normalize keeps pet keys', norm.Default ~= nil and #norm.Default, 1);
    check('PT22 normalized prio = petStatus tier', norm.Default[1].prio, 23);
end)();

-- ---------------------------------------------------------------------------
-- TG. Target condition (engine v81): WHO the action is aimed at; v1 value
--     'Self'. ctx.targetSelf is the injected seam (live: GetActionTarget's
--     entity index vs my own party index, one read per dispatch); tri-state --
--     nil = unknown (Default handler, failed read) matches NOTHING, so a
--     target rule never fires blind. Tier 55: a self-refined rule overlays
--     its base name/contains/group rule with no hand priority, under the
--     Automations band (60).
-- ---------------------------------------------------------------------------
(function()
    local mm = dispatchM._matchers;
    local selfCast  = { action = { Name = 'Curing Waltz III' }, targetSelf = true };
    local otherCast = { action = { Name = 'Curing Waltz III' }, targetSelf = false };
    local unknown   = { action = { Name = 'Curing Waltz III' } };   -- no seam, stub gData has no GetActionTarget
    check('TG1 target=Self fires on a self-cast',     mm.target('Self', selfCast), true);
    check('TG2 target=Self quiet on another target',  mm.target('Self', otherCast), false);
    check('TG3 target matches case-insensitively',    mm.target('self', selfCast), true);
    check('TG4 unknown target matches NOTHING',       mm.target('Self', unknown), false);
    check('TG5 unknown VALUE never matches',          mm.target('Enemy', selfCast), false);
    -- Tier ladder: the self-refinement overlays its base rule (name 50,
    -- contains 40) with no hand priority, and stays under player gates / mode.
    check('TG6 target sits at 55', dispatchM.defaultPriority({ target = 'Self' }), 55);
    check('TG7 name+target outranks bare name',
        dispatchM.defaultPriority({ name = 'Curing Waltz III', target = 'Self' })
            > dispatchM.defaultPriority({ name = 'Curing Waltz III' }), true);
    check('TG8 mode still outranks target',
        dispatchM.defaultPriority({ mode = 'DT' })
            > dispatchM.defaultPriority({ target = 'Self' }), true);
    -- Henrik's waltz pair through the engine's own matches(): the base rule
    -- fires either way, the Self rule only on the self-cast -- the overlay
    -- (55 > 40) puts VIT+CHR on top of the plain CHR set.
    local mt = dispatchM._matches;
    local base     = { when = { contains = 'Waltz' } };
    local selfRule = { when = { contains = 'Waltz', target = 'Self' } };
    check('TG9 base waltz rule fires on a self-cast', mt(base, selfCast), true);
    check('TG10 self rule fires on a self-cast',      mt(selfRule, selfCast), true);
    check('TG11 self rule quiet on another target',   mt(selfRule, otherCast), false);
    check('TG12 base rule still fires on others',     mt(base, otherCast), true);
    -- Serializer + normalize: first-class vocabulary, round-trips byte-stable.
    local text = dispatchM.serializeTriggers({
        Ability = { { when = { contains = 'Waltz', target = 'Self' }, set = 'Waltz_Self' } },
    });
    check('TG13 target serializes', text:find('target = "Self"', 1, true) ~= nil, true);
    local t2 = (loadstring or load)(text)();
    check('TG14 round-trip byte-stable', dispatchM.serializeTriggers(t2) == text, true);
    local norm = dispatchM._normalize({
        Ability = { { when = { name = 'Curing Waltz III', target = 'Self' }, set = 'Waltz_Self' } },
    });
    check('TG15 normalize keeps target', norm.Ability ~= nil and #norm.Ability, 1);
    check('TG16 normalized prio = target tier', norm.Ability[1].prio, 55);
end)();

-- ---------------------------------------------------------------------------
-- IT. inTown condition (engine v84): am I standing in a town? Town = the
--     curated data/zones.lua set -- server CITY zonetype + Nashmau, minus
--     combat-staging CITY zones (tools/gen_zones.py). ctx.zone is the injected
--     seam (live: GetParty():GetMemberZone(0), one read/dispatch); an unknown
--     zone (nil) matches NEITHER polarity, so the rule never fires blind. Tier
--     95 (location gate): a town show-off set overlays the plain Idle set, under
--     mode. Loader lowercases inTown -> intown + TIER-validates it (IT21/IT22).
-- ---------------------------------------------------------------------------
(function()
    local mm = dispatchM._matchers;
    local sandoria = { zone = 230 };   -- Southern San d'Oria: server CITY -> town
    local celennia = { zone = 284 };   -- Celennia Memorial Library: SoA zone, CITY -> town (the Wings-hub case)
    local nashmau  = { zone = 53  };   -- Nashmau: server types OUTDOORS -> town ONLY via the curated ADD
    local sealions = { zone = 32  };   -- Sealion's Den: server CITY, but curated-DROPPED (combat staging)
    local channel  = { zone = 1   };   -- Phanauet Channel: OUTDOORS, plainly not a town
    check('IT1 inTown=true fires in a city',           mm.intown(true,  sandoria), true);
    check('IT2 inTown=true fires in Celennia (Wings)', mm.intown(true,  celennia), true);
    check('IT3 curated ADD: Nashmau counts as town',   mm.intown(true,  nashmau),  true);
    check('IT4 curated DROP: Sealions Den not town',   mm.intown(true,  sealions), false);
    check('IT5 inTown=true quiet out in the field',    mm.intown(true,  channel),  false);
    check('IT6 inTown=false fires out in the field',   mm.intown(false, channel),  true);
    check('IT7 inTown=false quiet in a city',          mm.intown(false, sandoria), false);
    check('IT8 inTown=false quiet in Nashmau',         mm.intown(false, nashmau),  false);
    check('IT9 zone 0 (demo stub) is not a town',      mm.intown(true,  { zone = 0 }), false);
    -- Unknown zone (failed / headless read) matches NEITHER polarity. Force the
    -- live read to fail by nil-ing AshitaCore (harness idiom, ~line 116); restore.
    local savedAshita = AshitaCore;
    AshitaCore = nil;
    check('IT10 unknown zone quiet (inTown=true)',     mm.intown(true,  {}), false);
    check('IT11 unknown zone quiet (inTown=false)',    mm.intown(false, {}), false);
    AshitaCore = savedAshita;
    -- Tier ladder: the 95 location gate overlays the plain Idle set, under mode.
    check('IT12 inTown sits at 95', dispatchM.defaultPriority({ inTown = true }), 95);
    check('IT13 idle+inTown overlays plain idle',
        dispatchM.defaultPriority({ status = 'Idle', inTown = true })
            > dispatchM.defaultPriority({ status = 'Idle' }), true);
    check('IT14 mode still outranks inTown',
        dispatchM.defaultPriority({ mode = 'DT' })
            > dispatchM.defaultPriority({ inTown = true }), true);
    -- The headline scenario through the engine's own matches(): {Idle, inTown}
    -- fires standing in town, quiet in the field; the base idle rule fires both.
    -- (matches() sees post-load keys -> lowercase 'intown'.)
    local mt = dispatchM._matches;
    local base     = { when = { status = 'Idle' } };
    local townRule = { when = { status = 'Idle', intown = true } };
    local idleTown  = { player = { Status = 'Idle' }, zone = 230 };
    local idleField = { player = { Status = 'Idle' }, zone = 1 };
    check('IT15 base idle rule fires in town',       mt(base, idleTown),  true);
    check('IT16 town rule fires idle in town',       mt(townRule, idleTown),  true);
    check('IT17 town rule quiet idle in the field',  mt(townRule, idleField), false);
    check('IT18 base idle rule still fires in field',mt(base, idleField), true);
    -- First-class vocabulary: PRETTY-case inTown serializes + round-trips, and
    -- _normalize accepts it (loader lowercases + TIER-validates) at prio 95.
    local text = dispatchM.serializeTriggers({
        Default = { { when = { status = 'Idle', inTown = true }, set = 'ShowOff' } },
    });
    check('IT19 inTown serializes PRETTY-case', text:find('inTown', 1, true) ~= nil, true);
    local t2 = (loadstring or load)(text)();
    check('IT20 round-trip byte-stable', dispatchM.serializeTriggers(t2) == text, true);
    local norm = dispatchM._normalize({
        Default = { { when = { status = 'Idle', inTown = true }, set = 'ShowOff' } },
    });
    check('IT21 normalize keeps inTown rule', norm.Default ~= nil and #norm.Default, 1);
    check('IT22 normalized prio = 95',        norm.Default[1].prio, 95);
end)();

-- ---------------------------------------------------------------------------
-- weatherMatch (engine v121): a spell-handler flag -- true when the CURRENT
-- weather's element equals the action's element. NOT the day+weather net
-- (dayWeatherBonus): no day, no opposition, a plain weather match -- the gate
-- CatsEyeXI's Scholar cast-time bonus (ALACRITY_CELERITY_EFFECT) actually keys
-- on. ctx.wel is the cached weather-element seam: set it to drive the matcher
-- headlessly (nil -> a live gData read, which fails to '' in the harness = unknown).
-- Tier 30 (element band). Unreadable weather / no action element matches NEITHER.
-- ---------------------------------------------------------------------------
(function()
    local mm = dispatchM._matchers;
    local fireInFire  = { action = { Element = 'Fire' }, wel = 'Fire' };
    local fireInIce   = { action = { Element = 'Fire' }, wel = 'Ice'  };
    local fireInClear = { action = { Element = 'Fire' }, wel = 'None' };
    check('WM1 match: weatherMatch=true fires (Fire in Fire weather)', mm.weathermatch(true,  fireInFire), true);
    check('WM2 mismatch: weatherMatch=true quiet (Fire in Ice)',      mm.weathermatch(true,  fireInIce),  false);
    check('WM3 mismatch: weatherMatch=false fires (Fire in Ice)',     mm.weathermatch(false, fireInIce),  true);
    check('WM4 match: weatherMatch=false quiet (Fire in Fire)',       mm.weathermatch(false, fireInFire), false);
    check('WM5 element match is case-insensitive',                    mm.weathermatch(true,  { action = { Element = 'fire' }, wel = 'FIRE' }), true);
    -- Clear / 'None' weather is a REAL non-match (not unknown): =true quiet, =false fires.
    check('WM6 clear weather: weatherMatch=true quiet',               mm.weathermatch(true,  fireInClear), false);
    check('WM7 clear weather: weatherMatch=false fires',              mm.weathermatch(false, fireInClear), true);
    -- No action element (Default handler / Non-Elemental) -> matches NEITHER polarity.
    check('WM8 no action element: =true quiet',                       mm.weathermatch(true,  { wel = 'Fire' }), false);
    check('WM9 no action element: =false quiet',                      mm.weathermatch(false, { wel = 'Fire' }), false);
    check('WM10 Non-Elemental action: =true quiet',                   mm.weathermatch(true,  { action = { Element = 'Non-Elemental' }, wel = 'Fire' }), false);
    check('WM11 Non-Elemental action: =false quiet',                  mm.weathermatch(false, { action = { Element = 'Non-Elemental' }, wel = 'Fire' }), false);
    -- Unreadable weather ('' sentinel, e.g. a failed live read) -> matches NEITHER.
    check('WM12 unreadable weather: =true quiet',                     mm.weathermatch(true,  { action = { Element = 'Fire' }, wel = '' }), false);
    check('WM13 unreadable weather: =false quiet',                    mm.weathermatch(false, { action = { Element = 'Fire' }, wel = '' }), false);
    -- Tier ladder: weatherMatch sits at 30 (element band), like dayWeatherBonus.
    check('WM14 weatherMatch sits at 30', dispatchM.defaultPriority({ weatherMatch = true }), 30);
    check('WM15 buff still outranks weatherMatch',
        dispatchM.defaultPriority({ buff = 'Alacrity' })
            > dispatchM.defaultPriority({ weatherMatch = true }), true);
    -- Through matches(): the AND leg with a live weather ctx (post-load lowercase key).
    local mt = dispatchM._matches;
    check('WM16 matches() fires on a weather match',
        mt({ when = { weathermatch = true } }, { action = { Element = 'Fire' }, wel = 'Fire' }), true);
    check('WM17 matches() quiet on a mismatch',
        mt({ when = { weathermatch = true } }, { action = { Element = 'Fire' }, wel = 'Ice' }), false);
    -- First-class vocabulary: PRETTY-case weatherMatch serializes + round-trips,
    -- and _normalize accepts it (loader lowercases + TIER-validates) at prio 30.
    local text = dispatchM.serializeTriggers({
        Midcast = { { when = { weatherMatch = true }, set = 'StormNuke' } },
    });
    check('WM18 weatherMatch serializes PRETTY-case', text:find('weatherMatch', 1, true) ~= nil, true);
    local t2 = (loadstring or load)(text)();
    check('WM19 round-trip byte-stable', dispatchM.serializeTriggers(t2) == text, true);
    local norm = dispatchM._normalize({
        Midcast = { { when = { weatherMatch = true }, set = 'StormNuke' } },
    });
    check('WM20 normalize keeps weatherMatch rule', norm.Midcast ~= nil and #norm.Midcast, 1);
    check('WM21 normalized prio = 30',              norm.Midcast[1].prio, 30);
end)();

-- ---------------------------------------------------------------------------
-- TGM. Trigger Groups model (G2, issue #25, ADR 0009): the pure GUI-side CRUD +
--      name / member validation the Groups tab drives (groupsmodel.lua). Group
--      names and member names compare case-insensitively (engine parity), an
--      empty member list is legal, and fromRaw sanitizes the file's Groups section
--      into the model so a Commit round-trips it (the SetOptions/Modes wipe lesson).
-- ---------------------------------------------------------------------------
(function()
    local gmod = dofile('gear/groupsmodel.lua');
    check('TGM0 module loads', type(gmod), 'table');

    -- fromRaw: sanitize + carry-through (name -> string-member array).
    local raw = { Groups = {
        StrBlue = { 'Hysteric Barrage', 'Quad. Continuum' },
        Empty   = {},                                  -- a group still being built (kept)
        Junk    = 'not a table',                       -- dropped
        [5]     = { 'x' },                             -- non-string name dropped
        Mixed   = { 'Ok', '', 42, 'Two' },             -- blanks / non-strings dropped
    } };
    local g = gmod.fromRaw(raw);
    check('TGM1 fromRaw StrBlue members',   #g.StrBlue, 2);
    check('TGM2 fromRaw keeps empty group', type(g.Empty), 'table');
    check('TGM3 fromRaw empty is empty',    #g.Empty, 0);
    check('TGM4 fromRaw drops non-table',   g.Junk, nil);
    check('TGM5 fromRaw drops bad members', #g.Mixed, 2);       -- 'Ok', 'Two'
    check('TGM6 fromRaw member order kept', g.StrBlue[1], 'Hysteric Barrage');
    check('TGM7 fromRaw lowercase key ok',  gmod.fromRaw({ groups = { A = { 'z' } } }).A ~= nil, true);
    check('TGM8 fromRaw no section -> {}',  next(gmod.fromRaw({})), nil);
    check('TGM9 fromRaw nil-safe',          type(gmod.fromRaw(nil)), 'table');

    -- names: case-insensitively sorted.
    local order = gmod.names({ beta = {}, Alpha = {}, gamma = {} });
    check('TGM10 names sorted CI', table.concat(order, ','), 'Alpha,beta,gamma');

    -- findName / hasGroup: case-insensitive, returns the STORED spelling.
    local gg = { StrBlue = { 'a' } };
    check('TGM11 findName CI',   gmod.findName(gg, 'strBLUE'), 'StrBlue');
    check('TGM12 findName miss', gmod.findName(gg, 'nope'), nil);
    check('TGM13 hasGroup CI',   gmod.hasGroup(gg, 'STRBLUE'), true);

    -- validateName: blank / duplicate rejected; rename may keep its own name.
    check('TGM14 validate blank',      (gmod.validateName({}, '   ')), false);
    check('TGM15 validate dup CI',     (gmod.validateName({ Cures = {} }, 'cures')), false);
    check('TGM16 validate ok',         (gmod.validateName({ Cures = {} }, 'Enfeebles')), true);
    check('TGM17 validate rename self', (gmod.validateName({ Cures = {} }, 'CURES', 'Cures')), true);

    -- add: creates an empty group; rejects a duplicate.
    local c = {};
    check('TGM18 add ok',        (gmod.add(c, ' STR Spells ')), true);
    check('TGM19 add trims key', c['STR Spells'] ~= nil, true);
    check('TGM20 add empty body', #c['STR Spells'], 0);
    check('TGM21 add dup fails',  (gmod.add(c, 'str spells')), false);

    -- addMember: trims, rejects blank + case-insensitive duplicate.
    check('TGM22 addMember ok',       (gmod.addMember(c, 'STR Spells', ' Head Butt ')), true);
    check('TGM23 addMember trimmed',  c['STR Spells'][1], 'Head Butt');
    check('TGM24 addMember dup CI',   (gmod.addMember(c, 'STR Spells', 'head butt')), false);
    check('TGM25 addMember blank',    (gmod.addMember(c, 'STR Spells', '  ')), false);
    check('TGM26 addMember no group', (gmod.addMember(c, 'Nope', 'x')), false);

    -- removeMember: case-insensitive; reports a miss.
    check('TGM27 removeMember CI',    (gmod.removeMember(c, 'STR Spells', 'HEAD BUTT')), true);
    check('TGM28 removeMember gone',  #c['STR Spells'], 0);
    check('TGM29 removeMember miss',  (gmod.removeMember(c, 'STR Spells', 'x')), false);

    -- rename: preserves members + order; rejects a collision.
    local r2 = { Old = { 'm1', 'm2' }, Other = {} };
    check('TGM30 rename ok',        (gmod.rename(r2, 'old', 'New')), true);
    check('TGM31 rename moved',     r2.Old, nil);
    check('TGM32 rename members',   #r2.New, 2);
    check('TGM33 rename order kept', r2.New[1], 'm1');
    check('TGM34 rename collision', (gmod.rename(r2, 'New', 'other')), false);
    check('TGM35 rename missing',   (gmod.rename(r2, 'ghost', 'x')), false);

    -- remove: deletes; reports a miss (a dangling reference is a Triggers-tab concern).
    check('TGM36 remove CI',   (gmod.remove(r2, 'new')), true);
    check('TGM37 remove gone', r2.New, nil);
    check('TGM38 remove miss', (gmod.remove(r2, 'nope')), false);
end)();

-- ---------------------------------------------------------------------------
-- TGI. Group import model (G4, issue #30, ADR 0009): the pure "Import Lua Table(s)"
--      transform (groupimport.lua). Parse pasted `Name = T{...}` assignments into a
--      name->members map + a skip-reason list; T is identity; flat-only (a nested /
--      non-string value skips THAT key while the rest import); malformed / hostile
--      input yields an error, never a crash or code execution (sandboxed). classify
--      splits created vs collide (CI), apply overwrites under the stored spelling.
-- ---------------------------------------------------------------------------
(function()
    local gimp = dofile('gear/groupimport.lua');   -- forward slash: also loads on Linux CI
    check('TGI0 module loads',       type(gimp),        'table');
    check('TGI0b parse exported',    type(gimp.parse),  'function');
    check('TGI0c classify exported', type(gimp.classify), 'function');
    check('TGI0d apply exported',    type(gimp.apply),  'function');

    -- 1. The issue's own example: bare lines, T{...} and plain {...} mixed, a trailing comma,
    --    a single-element group. One Group per top-level key; members = the key's string array.
    local paste = [[
STR_DEX = T{'Foot Kick', 'Wild Oats', 'Queasyshroom', 'Battle Dance', 'Feather Storm' },
STR_VIT = T{'Quad. Continuum', },
VIT     = {'Cannonball', 'Tail Slap', 'Body Slam', 'Grand Slam' },
Debuff  = T{'Filamented Hold', 'Cimicine Discharge', 'Demoralizing Roar' },
]];
    local g, errs = gimp.parse(paste);
    check('TGI1 four groups created',    (function() local n=0; for _ in pairs(g) do n=n+1 end return n; end)(), 4);
    check('TGI2 no skip errors',         #errs, 0);
    check('TGI3 T{...} members',         #g.STR_DEX, 5);
    check('TGI4 plain {...} members',    #g.VIT, 4);
    check('TGI5 member order kept',      g.STR_DEX[1], 'Foot Kick');
    -- The acceptance criterion, exactly: STR_VIT = T{'Quad. Continuum', } -> ["Quad. Continuum"].
    check('TGI6 single-elem + trailing comma len', #g.STR_VIT, 1);
    check('TGI7 single-elem value exact', g.STR_VIT[1], 'Quad. Continuum');

    -- 2. The whole `{ Key = {...}, ... }` table form parses the same as bare lines.
    local whole = gimp.parse("{ A = T{'x'}, B = {'y', 'z'} }");
    check('TGI8 whole-table A',  #whole.A, 1);
    check('TGI9 whole-table B',  #whole.B, 2);

    -- 3. Flat-only: a nested table, a named-field value, and a non-string element each skip THAT
    --    key with a reported reason -- the remaining keys still import (no all-or-nothing).
    local mixed, merr = gimp.parse(
        "Good = {'a','b'}, Nested = {'a', {'deep'}}, Nums = {'a', 42}, Mapish = {foo='bar'}");
    check('TGI10 good key imported',   #mixed.Good, 2);
    check('TGI11 nested key skipped',  mixed.Nested, nil);
    check('TGI12 nonstring key skipped', mixed.Nums, nil);
    check('TGI13 named-field skipped', mixed.Mapish, nil);
    check('TGI14 three skip reasons',  #merr, 3);
    check('TGI15 reason names the key', (merr[1]:find('Mapish', 1, true) ~= nil), true);  -- sorted -> Mapish first

    -- 4. Malformed input -> an error message, groups nil, NOT a crash.
    local bad, berr = gimp.parse("STR = T{ unterminated ");
    check('TGI16 malformed -> nil groups', bad, nil);
    check('TGI17 malformed -> one error',  #berr, 1);
    check('TGI18 malformed error worded',  (berr[1]:find('parse', 1, true) ~= nil), true);

    -- 5. Sandbox: a hostile paste referencing a blocked global (os) errors at eval -- os is nil in
    --    the env, so it is never called. groups nil, reported, nothing executed.
    local hostile, herr = gimp.parse("X = os.execute('echo pwned')");
    check('TGI19 sandbox blocks os',       hostile, nil);
    check('TGI20 sandbox reports, no run', (herr[1]:find('nil value', 1, true) ~= nil), true);

    -- 6. Empty / blank input -> a single guiding message, not a crash.
    check('TGI21 blank input -> nil',   gimp.parse('   '), nil);
    check('TGI22 nil input -> nil',     gimp.parse(nil), nil);

    -- 7. An empty group value is legal (a group you are still filling).
    local em = gimp.parse("Filling = {}, Full = {'a'}");
    check('TGI23 empty group kept',  type(em.Filling), 'table');
    check('TGI24 empty group empty', #em.Filling, 0);

    -- 8. classify: created vs collision (case-insensitive), each sorted.
    local existing = { STR_DEX = { 'old' }, Keep = { 'k' } };
    local imp = gimp.parse("str_dex = {'new1','new2'}, Fresh = {'z'}");
    local created, overwritten = gimp.classify(imp, existing);
    check('TGI25 created list',     table.concat(created, ','),     'Fresh');
    check('TGI26 overwritten CI',   table.concat(overwritten, ','), 'str_dex');

    -- 9. apply: overwrite replaces members under the EXISTING stored spelling; a new name is
    --    created; the summary counts created / updated / total members.
    local sum = gimp.apply(existing, imp);
    check('TGI27 apply created count', sum.created, 1);
    check('TGI28 apply updated count', sum.updated, 1);
    check('TGI29 apply member total',  sum.members, 3);
    check('TGI30 overwrite keeps stored key', existing.str_dex, nil);       -- not re-keyed
    check('TGI31 overwrite replaced members', table.concat(existing.STR_DEX, ','), 'new1,new2');
    check('TGI32 new group created',   existing.Fresh ~= nil, true);
    check('TGI33 untouched group kept', existing.Keep[1], 'k');
end)();

-- ---------------------------------------------------------------------------
-- ACP. actionpicker (G3, issue #26, ADR 0009): the pure searchable spell/ability
--      browse-list core -- the job-filtered list build + the search-match predicate
--      the Groups tab's browse picker drives (and issue #12's `name` picker later).
--      A combined, UNGATED list (build-ahead, HARD RULE 6); each entry says spell vs
--      ability. Data injected (setimport precedent); search mirrors item search.
-- ---------------------------------------------------------------------------
(function()
    local ap = dofile('gear/actionpicker.lua');   -- forward slash: also loads on Linux CI
    check('ACP0 module loads', type(ap), 'table');
    check('ACP1 buildList exported', type(ap.buildList), 'function');
    check('ACP2 matches exported',   type(ap.matches),   'function');

    -- Stub picker-DB rows: a BLU-usable spell + BLU-usable ability that collide on name
    -- (untyped group would list both, each labelled), a high-level BLU spell (ungated), a
    -- WHM-only spell (must NOT appear for BLU), and a shared spell (BLM + RDM).
    local spells = {
        { Name = 'Head Butt',  Jobs = { BLU = 46 }, Skill = 'Blue Magic' },   -- also an ability name
        { Name = 'Actinic Burst', Jobs = { BLU = 74 } },                       -- Lv74 -> still listed
        { Name = 'Cure',       Jobs = { WHM = 1, RDM = 3 } },                  -- no BLU
        { Name = 'Stone',      Jobs = { BLM = 1, RDM = 4 } },
        { Name = 'Stone II',   Jobs = { BLM = 26, RDM = 34 } },
    };
    local abilities = {
        { Name = 'Head Butt',  Jobs = { BLU = 46 } },                          -- ability twin
        { Name = 'Berserk',    Jobs = { WAR = 15 } },                          -- no BLU
        { Name = 'Azure Lore', Jobs = { BLU = 1 }, MainOnly = true, SP = true },
    };

    -- sorted: Actinic Burst (spell), Azure Lore (ability), Head Butt (ability), Head Butt (spell)
    local blu = ap.buildList('BLU', spells, abilities);
    check('ACP3 BLU list size (2 spells + 2 abilities)', #blu, 4);
    check('ACP4 sorted by name, case-insensitive [1]', blu[1].name, 'Actinic Burst');
    check('ACP5 [2] is Azure Lore', blu[2].name, 'Azure Lore');
    check('ACP6 name tie: ability sorts before spell [3]', blu[3].kind, 'ability');
    check('ACP7 ...its spell twin follows [4]',            blu[4].kind, 'spell');
    check('ACP8 both twins are "Head Butt"', blu[3].name == 'Head Butt' and blu[4].name == 'Head Butt', true);
    check('ACP9 carries the acquisition level for display', (function()
        for _, e in ipairs(blu) do if e.name == 'Actinic Burst' then return e.level; end end
    end)(), 74);
    check('ACP10 NOT level-gated: a Lv74 action is present at any player level', (function()
        for _, e in ipairs(blu) do if e.name == 'Actinic Burst' then return true; end end
        return false;
    end)(), true);
    check('ACP11 other jobs excluded (no Cure/Berserk for BLU)', (function()
        for _, e in ipairs(blu) do if e.name == 'Cure' or e.name == 'Berserk' then return e.name; end end
        return true;
    end)(), true);

    -- job matching is case-insensitive on the passed job; unknown / not-ready jobs -> {}
    check('ACP12 job passed lower-case still matches', #ap.buildList('blu', spells, abilities), 4);
    check('ACP13 unknown job -> empty', #ap.buildList('XYZ', spells, abilities), 0);
    check('ACP14 not-ready "NON" -> empty', #ap.buildList('NON', spells, abilities), 0);
    check('ACP15 nil job -> empty', #ap.buildList(nil, spells, abilities), 0);
    check('ACP16 missing data -> empty, no error', #ap.buildList('BLU', nil, nil), 0);

    -- a job with the shared spell picks it up under both callers
    local blm = ap.buildList('BLM', spells, abilities);
    check('ACP17 BLM sees its shared spells', #blm, 2);   -- Stone, Stone II

    -- search-match predicate: comma-separated, ALL terms substring, case-insensitive.
    local function q(s) return ap.parseQuery(s); end
    check('ACP18 empty query matches everything', ap.matches(blu[1], q('')), true);
    check('ACP19 single term narrows',    ap.matches({ name = 'Stone II' }, q('stone')), true);
    check('ACP20 case-insensitive',       ap.matches({ name = 'Stone II' }, q('STONE')), true);
    check('ACP21 non-match rejected',     ap.matches({ name = 'Stone' },    q('cure')),  false);
    check('ACP22 comma = AND (both needed)', ap.matches({ name = 'Stone II' }, q('stone, ii')), true);
    check('ACP23 comma AND: one term misses -> false', ap.matches({ name = 'Stone' }, q('stone, ii')), false);
    check('ACP24 bare-string entry accepted', ap.matches('Head Butt', q('butt')), true);
    check('ACP25 whitespace query = show all', ap.matches({ name = 'X' }, q('   ')), true);
    check('ACP26 parseQuery drops empty terms', #q('stone,,  , ii'), 2);
end)();

-- ---------------------------------------------------------------------------
-- AP3. weaponfilter Sub -- the F2c buckets (issue #18, PRD #14)
--
--   Sub buckets: Shield + Grip (both carry catalog Type="Sub"; grip-vs-shield splits by
--   name, "* Grip" / "* Strap") + the one-hander weapon types present in the pool (each
--   keeps its own weapon Type: Dagger / Sword / ...). Canonical order is Shield, Grip,
--   then the one-handers. VIEW-ONLY: the filter narrows what is shown, NEVER what the Sub
--   picker offers -- the A* HARD RULE tests (below) still gate eligibility (HARD RULE 6).
-- ---------------------------------------------------------------------------
(function()
    local wf = dofile('gear/weaponfilter.lua');

    -- A shield + a grip (Type="Sub", split by name) + a strap grip + two one-handers, plus a
    -- hand-authored Type="Shield" record (gear.lua writes the concrete type too). Unordered.
    local sub = {
        { Name = 'Test Sword',       Type = 'Sword',  OneHanded = true },   -- one-hander
        { Name = 'Koenig Shield',    Type = 'Sub' },                        -- catalog shield
        { Name = 'Tactician Grip',   Type = 'Sub' },                        -- name -> Grip
        { Name = 'Pole Strap',       Type = 'Sub' },                        -- strap -> Grip
        { Name = 'Test Dagger',      Type = 'Dagger', OneHanded = true },   -- one-hander
        { Name = 'Kaman Buckler',    Type = 'Shield' },                     -- hand-authored
    };
    local sb = wf.presentBuckets(sub, 'Sub');
    check('AP3-1 sub: four buckets present',   #sb, 4);
    check('AP3-2 canonical order [1] Shield',  sb[1].key, 'Shield');
    check('AP3-3 canonical order [2] Grip',    sb[2].key, 'Grip');
    check('AP3-4 one-handers after Shield/Grip [3] Dagger', sb[3].key, 'Dagger');
    check('AP3-5 canonical order [4] Sword',   sb[4].key, 'Sword');
    check('AP3-6 Shield labelled',             sb[1].label, 'Shield');
    check('AP3-7 Grip labelled',               sb[2].label, 'Grip');

    -- bucketOf: shields (catalog + hand-authored), grips (both spellings), one-handers.
    check('AP3-8 catalog shield -> Shield',    wf.bucketOf(sub[2], 'Sub'), 'Shield');
    check('AP3-9 authored shield -> Shield',   wf.bucketOf(sub[6], 'Sub'), 'Shield');
    check('AP3-10 "* Grip" -> Grip',           wf.bucketOf(sub[3], 'Sub'), 'Grip');
    check('AP3-11 "* Strap" -> Grip',          wf.bucketOf(sub[4], 'Sub'), 'Grip');
    check('AP3-12 one-hander keeps its Type',  wf.bucketOf(sub[1], 'Sub'), 'Sword');

    -- Shield marked: shows both shields, hides grips and one-handers.
    local onlyShield = { Shield = true };
    check('AP3-13 Shield shows catalog shield',  wf.visible(sub[2], onlyShield, 'Sub'), true);
    check('AP3-14 Shield shows authored shield', wf.visible(sub[6], onlyShield, 'Sub'), true);
    check('AP3-15 Shield hides grip',            wf.visible(sub[3], onlyShield, 'Sub'), false);
    check('AP3-16 Shield hides one-hander',      wf.visible(sub[1], onlyShield, 'Sub'), false);

    -- Grip marked: both grip spellings show, shields / one-handers hide.
    local onlyGrip = { Grip = true };
    check('AP3-17 Grip shows "* Grip"',   wf.visible(sub[3], onlyGrip, 'Sub'), true);
    check('AP3-18 Grip shows "* Strap"',  wf.visible(sub[4], onlyGrip, 'Sub'), true);
    check('AP3-19 Grip hides shield',     wf.visible(sub[2], onlyGrip, 'Sub'), false);
    check('AP3-20 Grip hides one-hander', wf.visible(sub[5], onlyGrip, 'Sub'), false);

    -- One-hander types stay distinct: Dagger marked shows only the dagger.
    local onlyDagger = { Dagger = true };
    check('AP3-21 Dagger shows the dagger',  wf.visible(sub[5], onlyDagger, 'Sub'), true);
    check('AP3-22 Dagger hides the sword',   wf.visible(sub[1], onlyDagger, 'Sub'), false);
    check('AP3-23 Dagger hides a shield',    wf.visible(sub[2], onlyDagger, 'Sub'), false);

    -- Multi-pick and All-default carry over.
    local shieldOrDagger = { Shield = true, Dagger = true };
    check('AP3-24 multi shows shield',    wf.visible(sub[2], shieldOrDagger, 'Sub'), true);
    check('AP3-25 multi shows dagger',    wf.visible(sub[5], shieldOrDagger, 'Sub'), true);
    check('AP3-26 multi hides sword',     wf.visible(sub[1], shieldOrDagger, 'Sub'), false);
    check('AP3-27 All default shows grip', wf.visible(sub[3], {}, 'Sub'), true);
    check('AP3-28 nil marks show one-hander', wf.visible(sub[1], nil, 'Sub'), true);

    -- Present-only: a shields-only pool offers exactly one bucket.
    check('AP3-29 shields-only pool -> one bucket',
        #wf.presentBuckets({ { Name = 'Buckler', Type = 'Shield' } }, 'Sub'), 1);
    -- Empty pool -> no buckets (never an empty dropdown).
    check('AP3-30 empty sub pool -> no buckets', #wf.presentBuckets({}, 'Sub'), 0);
end)();

-- ---------------------------------------------------------------------------
-- TR. Trinket vs ranged weapon (ADR 0010): a stat-stick ammo reserves the Range
--     slot server-side, so the two can't coexist (the client would flap re-equipping
--     the weapon the server keeps clearing). gearimport.effectiveRSlot completes the
--     trinket category (Ammo + no AmmoType -> the Range bit) so the WHOLE class is
--     marked in gear.lua; dispatch.trinketRangeDrop keeps the HIGHER-LEVEL of the two
--     and drops the other -- deterministic, so it settles instead of flapping.
-- ---------------------------------------------------------------------------
(function()
    -- trinket detection: Ammo with no AmmoType -> Range bit; fired ammo / explicit RSlot untouched
    local gimp = dofile('gear/gearimport.lua');
    check('TR0 effectiveRSlot exported', type(gimp.effectiveRSlot), 'function');
    check('TR1 trinket (Ammo, no AmmoType) -> Range bit', gimp.effectiveRSlot({ Type = 'Ammo', Id = 1 }), 4);
    check('TR2 fired ammo (has AmmoType) -> nil',          gimp.effectiveRSlot({ Type = 'Ammo', AmmoType = 'Archery' }), nil);
    check('TR3 explicit RSlot kept',                       gimp.effectiveRSlot({ Type = 'Ammo', RSlot = 8 }), 8);
    check('TR4 non-ammo -> nil',                           gimp.effectiveRSlot({ Type = 'Body' }), nil);
    -- Animator-fed oils: item_weapon subskill 10 == every Animator, so the server
    -- KEEPS oil + Animator together -- the completion must not paint them
    -- Range-reserving (field case 2026-07-22: a manually equipped Automat. Oil +2
    -- was displaced every Default dispatch).
    check('TR4b Animator-fed oil exempt -> nil',           gimp.effectiveRSlot({ Type = 'Ammo', Id = 18733 }), nil);

    -- the level tiebreak (dispatchM.trinketRangeDrop). rslot: only the stat sticks reserve Range.
    local rslot = function(n) return ({ Cinderstone = 4, Morion = 4 })[n]; end
    local level = function(n) return ({ Cinderstone = 60, Morion = 25, ['Power Bow'] = 75, ['Toy Bow'] = 10, ['Iron Arrow'] = 1 })[n]; end
    local function drop(set) return dispatchM.trinketRangeDrop(set, rslot, level); end

    local k, w = drop({ Range = 'Power Bow', Ammo = 'Cinderstone' });   -- bow 75 > stick 60
    check('TR5 bow higher -> drop the trinket',  k, 'Ammo');
    check('TR5b ... keeping the bow',            w, 'Power Bow');
    k, w = drop({ Range = 'Toy Bow', Ammo = 'Cinderstone' });           -- stick 60 > bow 10
    check('TR6 trinket higher -> drop the weapon', k, 'Range');
    check('TR6b ... keeping the trinket',          w, 'Cinderstone');
    check('TR7 bow + real arrow -> no drop', (drop({ Range = 'Power Bow', Ammo = 'Iron Arrow' })), nil);
    check('TR8 trinket alone -> no drop',    (drop({ Ammo = 'Cinderstone' })), nil);
    check('TR9 bow alone -> no drop',        (drop({ Range = 'Power Bow' })), nil);
    -- tie on level -> keep the trinket (drop Range), matching the server's own resolution
    local level2 = function(n) return ({ Cinderstone = 75, ['Power Bow'] = 75 })[n]; end
    check('TR10 tie -> keep the trinket, drop Range',
        dispatchM.trinketRangeDrop({ Range = 'Power Bow', Ammo = 'Cinderstone' }, rslot, level2), 'Range');

    -- Scope ruling (v78): the Level contest is WITHIN-SET only. A worn trinket
    -- OUTSIDE the plan is displaced (Ammo='remove') so the set's ranged piece
    -- can land -- Level never protects it from outside the pairing.
    local function disp(plan, worn) return dispatchM.trinketWornDisplace(plan, worn, rslot); end
    check('TR11 worn trinket vs set Range -> displace',      disp({ Range = 'Toy Bow' }, 'Cinderstone'), 'Ammo');
    check('TR11b Level does NOT protect a worn trinket',     disp({ Range = 'Toy Bow' }, 'Morion'), 'Ammo');
    local _, tr11in = disp({ Range = 'Toy Bow' }, 'Cinderstone');
    check('TR11c the incoming piece is named',               tr11in, 'Toy Bow');
    check('TR12 plan speaks for Ammo itself -> no displace', disp({ Range = 'Toy Bow', Ammo = 'Iron Arrow' }, 'Cinderstone'), nil);
    check('TR13 worn fired ammo -> no displace',             disp({ Range = 'Toy Bow' }, 'Iron Arrow'), nil);
    check('TR13b nothing worn -> no displace',               disp({ Range = 'Toy Bow' }, nil), nil);
    check('TR14 no Range in plan -> no displace',            disp({ Body = 'Gaudy Harness' }, 'Cinderstone'), nil);
    check('TR15 Range=remove is not incoming',               disp({ Range = 'remove' }, 'Cinderstone'), nil);

    -- Engine-side stale-stamp guard (v101): gear.lua files written before
    -- 2026.07.22g carry a wrongly-completed RSlot=4 on the Animator-fed oils;
    -- the engine ignores it at the manifest reader, so the addon update alone
    -- heals every user -- no /dl fix migration required for behavior.
    check('TR16 recordRSlot exported',          type(dispatchM.recordRSlot), 'function');
    check('TR16b stale oil stamp ignored',      dispatchM.recordRSlot({ Id = 18733, RSlot = 4 }), nil);
    check('TR16c genuine reservation trusted',  dispatchM.recordRSlot({ Id = 21384, RSlot = 4 }), 4);
    check('TR16d no stamp -> nil',              dispatchM.recordRSlot({ Id = 21384 }), nil);
    check('TR16e no record -> nil',             dispatchM.recordRSlot(nil), nil);
    -- Twin parity: the engine's id-pin and gearrecord's must never drift apart.
    local grecTR = dofile('gear/gearrecord.lua');
    for _, oid in ipairs({ 18731, 18732, 18733, 19185 }) do
        check('TR17 twin parity for oil id ' .. oid,
            grecTR.effectiveRSlot({ Type = 'Ammo', Id = oid }) == nil
            and grecTR.ANIMATOR_FED[oid] == true
            and dispatchM.recordRSlot({ Id = oid, RSlot = 4 }) == nil, true);
    end
end)();

-- ---------------------------------------------------------------------------
-- TB. ADR 0010 scope ruling wired through equipResolved (v78): the field case
--     -- worn Rimestone Lv60 must not keep a set's Lv20 Rouser out of Range.
--     Worn ammo comes through the real wornItemName glue (AshitaCore stubbed);
--     RSlot/Level through the real gear-manifest delegates (NameToObject
--     stubbed, the LS20 technique). Locked Ammo keeps the OLD behavior: the
--     user's explicit word outranks the set, so the worn trinket still
--     reserves Range away (the server mirror stays intact).
-- ---------------------------------------------------------------------------
(function()
    local gearTB = package.loaded['dlac\\gear'];
    gearTB.NameToObject['Rimestone'] = { Name = 'Rimestone', RSlot = 4, Level = 60 };
    gearTB.NameToObject['Rouser']    = { Name = 'Rouser', Level = 20 };
    local savedAC = AshitaCore;
    -- Worn-gear stub: `name` sits in Ammo (equip id 3), every other slot empty.
    AshitaCore = {
        GetMemoryManager = function()
            return { GetInventory = function()
                return {
                    GetEquippedItem = function(self, id)
                        if id == 3 then return { Index = 1 }; end
                        return { Index = 0 };
                    end,
                    GetContainerItem = function(self, c, i) return { Id = 9001 }; end,
                };
            end };
        end,
        GetResourceManager = function()
            return { GetItemById = function(self, id) return { Name = { 'Rimestone' } }; end };
        end,
    };
    for k in pairs(dispatchM.locks) do dispatchM.locks[k] = nil; end
    dispatchM.modes['maxmp'] = nil;   -- the mp branch must not join this test

    -- the field case: set names Range only -> the worn trinket is displaced
    local tbNote, tbTbl = dispatchM._equipResolved({ Range = 'Rouser' }, {});
    check('TB1 set Range survives the worn trinket',  tbTbl.Range, 'Rouser');
    check('TB2 the worn trinket is displaced',        tbTbl.Ammo, 'remove');
    check('TB3 the displacement is traced',
        string.find(tbNote, 'yields Range', 1, true) ~= nil, true);

    -- locked Ammo: no displacement; the worn trinket reserves Range away
    dispatchM.locks['ammo'] = true;
    local _, tbLk = dispatchM._equipResolved({ Range = 'Rouser' }, {});
    check('TB4 locked Ammo: no displacement',              tbLk.Ammo, nil);
    check('TB5 locked Ammo: the worn trinket keeps Range', tbLk.Range, nil);
    dispatchM.locks['ammo'] = nil;

    -- the plan speaking for Ammo itself needs no displacement
    local _, tbAr = dispatchM._equipResolved({ Range = 'Rouser', Ammo = 'Iron Arrow' }, {});
    check('TB6 plan Ammo rides as-is', tbAr.Ammo, 'Iron Arrow');
    check('TB6b Range untouched',      tbAr.Range, 'Rouser');

    -- WITHIN-SET pairing unchanged: both named -> Level decides (ADR 0010)
    local _, tbIn = dispatchM._equipResolved({ Range = 'Rouser', Ammo = 'Rimestone' }, {});
    check('TB7 within-set: the higher-Level trinket still wins', tbIn.Ammo, 'Rimestone');
    check('TB7b ... and the set Range drops',                    tbIn.Range, nil);

    -- The v101 field case end-to-end: a MANUALLY equipped Automat. Oil +2 whose
    -- manifest record still carries the stale RSlot=4 stamp must survive the
    -- idle set's Animator -- the engine's recordRSlot guard, not /dl fix, is
    -- what stops the displace.
    gearTB.NameToObject['Automat. Oil +2'] = { Name = 'Automat. Oil +2', Id = 18733, RSlot = 4, Level = 50 };
    gearTB.NameToObject['Animator']        = { Name = 'Animator', Id = 17859, Level = 10 };
    AshitaCore.GetResourceManager = function()
        return { GetItemById = function(self, id) return { Name = { 'Automat. Oil +2' } }; end };
    end;
    local _, tbOil = dispatchM._equipResolved({ Range = 'Animator' }, {});
    check('TB8 worn oil survives the Animator plan', tbOil.Ammo, nil);
    check('TB8b the Animator still lands',           tbOil.Range, 'Animator');
    gearTB.NameToObject['Automat. Oil +2'] = nil;
    gearTB.NameToObject['Animator'] = nil;

    -- TB9+. The trinket rule asks the PAIRING LAW before it drops (v128, Henrik
    -- 2026-07-26: "Soultrapper and Soultrapper 2000 should pair with: Blank Soul
    -- Plate and Blank High-speed Soul Plate"). The RSlot bit is a per-ITEM stamp;
    -- the conflict is a per-PAIR fact. "Ammo with no AmmoType reserves Range" is
    -- right for a stat stick beside a bow and WRONG for the skill-0 families that
    -- pair with their own Range piece -- which is how the soul plates ended up
    -- stamped Range-reserving and dropped from a combination the server allows.
    -- Cancel-only: a proven-compatible pair is never in conflict; unknown changes
    -- nothing.
    local function pairOfTB(n)
        return ({ ['Soultrapper'] = '0:0', ['Soultrapper 2000'] = '0:0',
                  ['Blank Soulplate'] = '0:0', ['H.S. Soul Plate'] = '0:0',
                  ['Animator'] = '0:10', ['Automaton Oil'] = '0:10',
                  ['Animator P Ii'] = '0:11',
                  ['Cinderstone'] = '0:0', ['Coiste Bodhar'] = '1:0',
                  ['Longbow'] = '25:4' })[n];
    end
    local function rsTB(_) return 4; end          -- everything stamped Range-reserving
    local function lvTB(n) return (n == 'Blank Soulplate') and 1 or 50; end
    local function drop(range, ammo)
        return dispatchM.trinketRangeDrop(
            { Range = range, Ammo = ammo }, rsTB, lvTB, pairOfTB);
    end
    check('TB9 Soultrapper + Blank Soulplate: no drop, they pair',
          drop('Soultrapper', 'Blank Soulplate'), nil);
    check('TB9b Soultrapper 2000 + H.S. Soul Plate: no drop either',
          drop('Soultrapper 2000', 'H.S. Soul Plate'), nil);
    check('TB9c Animator + Automaton Oil: no drop (ANIMATOR_FED by law, not by id)',
          drop('Animator', 'Automaton Oil'), nil);
    -- The ones that MUST still drop -- Henrik: "Coiste Bodhar is a trinket, so
    -- categorize it as a trinket like cinderstone".
    check('TB10 Longbow + Cinderstone still conflicts (0:0 vs 25:4)',
          drop('Longbow', 'Cinderstone') ~= nil, true);
    check('TB10b Longbow + Coiste Bodhar too (1:0 matches no Range piece, ever)',
          drop('Longbow', 'Coiste Bodhar') ~= nil, true);
    check('TB10c Animator P II + Automaton Oil conflicts (0:11 vs 0:10)',
          drop('Animator P Ii', 'Automaton Oil') ~= nil, true);
    -- Unknown pair data must change NOTHING: an old manifest behaves as before.
    check('TB11 no pairFn at all -> the RSlot stamp decides, exactly as before',
          dispatchM.trinketRangeDrop({ Range = 'Longbow', Ammo = 'Cinderstone' },
                                     rsTB, lvTB) ~= nil, true);
    check('TB11b an unknown pair does not cancel a drop',
          dispatchM.trinketRangeDrop({ Range = 'Mystery Bow', Ammo = 'Cinderstone' },
                                     rsTB, lvTB, pairOfTB) ~= nil, true);
    -- The worn-side twin: a worn plate must survive an incoming Soultrapper.
    check('TB12 worn Blank Soulplate survives an incoming Soultrapper',
          dispatchM.trinketWornDisplace({ Range = 'Soultrapper' }, 'Blank Soulplate',
                                        rsTB, pairOfTB), nil);
    check('TB12b worn Cinderstone still yields Range to an incoming Longbow',
          dispatchM.trinketWornDisplace({ Range = 'Longbow' }, 'Cinderstone',
                                        rsTB, pairOfTB), 'Ammo');

    -- TB13+. The law also CAUSES a drop the RSlot stamp could never see: two ordinary
    -- pieces that simply cannot fire each other (Henrik 2026-07-26: "that would be
    -- good, so we don't spam the server"). Nothing here reserves Range -- rs0 -- so
    -- before v128 this pair sailed through and the SERVER stripped a slot, forever.
    local function rs0(_) return 0; end
    local function pairMix(n)
        return ({ ['Longbow'] = '25:4', ['Venom Bolt'] = '26:0', ['Beetle Arrow'] = '25:0',
                  ['Hexagun'] = '26:1', ['Iron Bullet'] = '26:1',
                  ['Ebisu Fishing Rod'] = '48:0', ['Sardine Ball'] = '48:0',
                  ['Maple Harp'] = '41:0' })[n];
    end
    -- The ammo ALWAYS yields: "It should NEVER force ranged off, that is HANDS OFF."
    local mk, mkeep, mwhy = dispatchM.trinketRangeDrop(
        { Range = 'Longbow', Ammo = 'Venom Bolt' }, rs0, lvTB, pairMix);
    check('TB13 a bolt in a set with a bow is now dropped', mk, 'Ammo');
    check('TB13b ...the BOW is what is kept', mkeep, 'Longbow');
    check('TB13c ...and the reason is a mismatch, not a stat stick', mwhy, 'mismatch');
    -- Level must NOT flip this one. A Lv25 bolt outranking a Lv5 bow would drop the
    -- bow and leave the player holding ammo and no weapon -- the exact thing Henrik
    -- forbade. (The trinket contest above still decides by Level; this one never does.)
    local hk, hkeep = dispatchM.trinketRangeDrop(
        { Range = 'Longbow', Ammo = 'Venom Bolt' }, rs0,
        function(n) return (n == 'Venom Bolt') and 99 or 1; end, pairMix);
    check('TB13d a higher-Level bolt STILL yields -- Range is never forced off', hk, 'Ammo');
    check('TB13e ...the low-level bow survives it', hkeep, 'Longbow');
    -- Compatible pairs must stay untouched by the new firing path.
    check('TB14 bow + arrow: no drop (25:4 fires 25:0)',
          dispatchM.trinketRangeDrop({ Range = 'Longbow', Ammo = 'Beetle Arrow' }, rs0, lvTB, pairMix), nil);
    check('TB14b gun + bullet: no drop',
          dispatchM.trinketRangeDrop({ Range = 'Hexagun', Ammo = 'Iron Bullet' }, rs0, lvTB, pairMix), nil);
    check('TB14c rod + bait: no drop (48:0 -- fishing must not regress)',
          dispatchM.trinketRangeDrop({ Range = 'Ebisu Fishing Rod', Ammo = 'Sardine Ball' }, rs0, lvTB, pairMix), nil);
    check('TB14d a harp fires nothing -- the arrow yields',
          dispatchM.trinketRangeDrop({ Range = 'Maple Harp', Ammo = 'Beetle Arrow' }, rs0, lvTB, pairMix), 'Ammo');
    -- Unknown pair data + no stamp = silence, exactly as before v128.
    check('TB15 unknown pair and no RSlot bit -> nothing happens (old manifest)',
          dispatchM.trinketRangeDrop({ Range = 'Mystery Bow', Ammo = 'Mystery Ammo' }, rs0, lvTB, pairMix), nil);
    check('TB15b no pairFn at all -> nothing happens either',
          dispatchM.trinketRangeDrop({ Range = 'Longbow', Ammo = 'Venom Bolt' }, rs0, lvTB), nil);
    -- The worn-side twin fires too: a worn bolt would take the incoming bow back off.
    check('TB16 a worn bolt yields to an incoming bow, with no stamp involved',
          dispatchM.trinketWornDisplace({ Range = 'Longbow' }, 'Venom Bolt', rs0, pairMix), 'Ammo');
    check('TB16b a worn arrow stays put under that same bow',
          dispatchM.trinketWornDisplace({ Range = 'Longbow' }, 'Beetle Arrow', rs0, pairMix), nil);
    check('TB16c worn bait survives an incoming rod',
          dispatchM.trinketWornDisplace({ Range = 'Ebisu Fishing Rod' }, 'Sardine Ball', rs0, pairMix), nil);

    AshitaCore = savedAC;
    gearTB.NameToObject['Rimestone'] = nil;
    gearTB.NameToObject['Rouser'] = nil;
end)();

-- ---------------------------------------------------------------------------
-- SW. Engine self-swap decision (v102): CONTENT is the key -- version-keying
--     alone went blind to same-version engine edits (field friction 2026-07-22:
--     mid-round fixes never swapped; a manual Reload LAC each time). The
--     version compare stays as a secondary trigger that heals a stale baseline.
-- ---------------------------------------------------------------------------
(function()
    local W = dispatchM.swapWanted;
    check('SW0 exported',                        type(W), 'function');
    check('SW1 unreadable file -> skip',         W(nil, 'old', nil, nil, 101), 'skip');
    check('SW2 failed build remembered -> skip', W('bad', 'old', 'bad', 102, 101), 'skip');
    check('SW3 no parseable version -> skip',    W('garbage', 'old', nil, nil, 101), 'skip');
    check('SW4 version difference -> swap even on a stale baseline',
                                                 W('new', 'new', nil, 102, 101), 'swap');
    check('SW5 nil baseline -> init',            W('same', nil, nil, 101, 101), 'init');
    check('SW6 same bytes -> skip',              W('same', 'same', nil, 101, 101), 'skip');
    check('SW7 same-version content edit -> swap (the field case)',
                                                 W('edited', 'orig', nil, 101, 101), 'swap');
    check('SW8 an edited failed build gets its retry',
                                                 W('bad2', 'old', 'bad', 101, 101), 'swap');
    check('SW9 failed build blocks init too',    W('bad', nil, 'bad', 101, 101), 'skip');
end)();

-- ---------------------------------------------------------------------------
-- REC. gearrecord -- the Owned-gear record rules, ONE home (Type canon + legacy
--      heal, Shield/Grip by name, effectiveRSlot trinket completion, catalog
--      enrichment precedence). Every stamp site (renderEntry fresh write,
--      /dl fix backfill, gearui enrich, gearexport, the weapon-type filter)
--      resolves through these; TR0-TR4 above pin the gearimport delegate.
-- ---------------------------------------------------------------------------
(function()
    local grec = package.loaded['dlac\\gear\\gearrecord'];
    check('REC0 module seeded', type(grec), 'table');

    -- Type canon + heal
    check('REC1 spaced legacy heals',     grec.canonType('Great Axe'), 'GreatAxe');
    check('REC2 hyphenated legacy heals', grec.canonType('Hand-to-Hand'), 'HandToHand');
    check('REC3 bare String alias',       grec.canonType('String'), 'StringInstrument');
    check('REC4 unknown passes through',  grec.canonType('Oddball'), 'Oddball');
    check('REC5 healType absent takes catalog',        grec.healType(nil, 'GreatAxe'), 'GreatAxe');
    check('REC6 healType drift heals to catalog',      grec.healType('Great Axe', 'GreatAxe'), 'GreatAxe');
    check('REC7 healType exact keeps owned',           grec.healType('GreatAxe', 'GreatAxe'), 'GreatAxe');
    check('REC8 healType real difference keeps owned', grec.healType('Sword', 'Dagger'), 'Sword');

    -- weaponfilter's whole bucket vocabulary must resolve through the same canon
    -- (a key gearrecord did not know would silently stop healing that bucket).
    local wf = dofile('gear/weaponfilter.lua');
    for slot, cfg in pairs(wf.SLOTS) do
        for _, key in ipairs(cfg.order) do
            if key ~= '__trinket' then   -- presentation sentinel, not a Type
                check('REC9 vocabulary closure ' .. slot .. '/' .. key, grec.canonType(key), key);
            end
        end
    end

    -- Shield/Grip by name (GUI-side mirror of utils.classifySub)
    check('REC10 grip by name',  grec.subTypeFromName('Pole Grip'), 'Grip');
    check('REC11 strap by name', grec.subTypeFromName('Claymore Strap'), 'Grip');
    check('REC12 else shield',   grec.subTypeFromName("Genbu's Shield"), 'Shield');

    -- effectiveRSlot: the rule itself (TR1-TR4 pin the gearimport delegate)
    check('REC13 trinket completion',   grec.effectiveRSlot({ Type = 'Ammo' }), 4);
    check('REC14 explicit RSlot wins',  grec.effectiveRSlot({ Type = 'Ammo', RSlot = 8 }), 8);
    check('REC15 fired ammo untouched', grec.effectiveRSlot({ Type = 'Ammo', AmmoType = 'Archery' }), nil);
    check('REC15b Animator-fed oil exempt', grec.effectiveRSlot({ Type = 'Ammo', Id = 18731 }), nil);

    -- enrich: owned overrides, catalog fills; legacy Type heals; Stats merge
    local rec = { Name = 'Savagery', Type = 'Great Axe', Stats = { STR = 2 } };
    local cat = { Name = 'Savagery', Type = 'GreatAxe', OneHanded = false, Model = 123,
                  Stats = { STR = 1, DEX = 3 } };
    grec.enrich(rec, cat);
    check('REC16 enrich heals legacy Type',         rec.Type, 'GreatAxe');
    check('REC17 enrich fills OneHanded',           rec.OneHanded, false);
    check('REC18 enrich fills Model',               rec.Model, 123);
    check('REC19 enrich merge: owned stat wins',    rec.Stats.STR, 2);
    check('REC20 enrich merge: catalog fills',      rec.Stats.DEX, 3);
    check('REC21 catalog Stats untouched by merge', cat.Stats.STR, 1);

    -- a statless record SHARES the catalog Stats table (the documented in-place
    -- semantics consumers' copy-on-write discipline depends on -- do not "fix")
    local thin = { Name = 'X' };
    grec.enrich(thin, cat);
    check('REC22 statless record shares catalog Stats table', thin.Stats == cat.Stats, true);

    -- mergedStats read-only (gearexport's precedence)
    local r2 = { Stats = { ACC = 5 } };
    local m = grec.mergedStats(r2, { Stats = { ACC = 1, EVA = 2 } });
    check('REC23 mergedStats owned wins',        m.ACC, 5);
    check('REC24 mergedStats catalog fills',     m.EVA, 2);
    check('REC25 mergedStats fresh table',       r2.Stats.EVA, nil);
    check('REC26 mergedStats both empty -> nil', grec.mergedStats({}, {}), nil);

    -- healOneHanded: H2H pins FALSE by Type -- the catalog's flag lies for
    -- H2H (apicrawl ONE-set bug 2026-07-22); everything else passes through,
    -- false and nil intact.
    check('REC27 healOneHanded: H2H pinned false',    grec.healOneHanded('HandToHand', true), false);
    check('REC28 healOneHanded: legacy spelling too', grec.healOneHanded('Hand-to-Hand', true), false);
    check('REC29 healOneHanded: 1H passes through',   grec.healOneHanded('Sword', true), true);
    check('REC30 healOneHanded: 2H false intact',     grec.healOneHanded('GreatSword', false), false);
    check('REC31 healOneHanded: nil flag stays nil',  grec.healOneHanded('Sword', nil), nil);
    local h2hRec = { Name = 'Beat Cesti', Type = 'HandToHand', OneHanded = true };
    grec.enrich(h2hRec, { Name = 'Beat Cesti', Type = 'HandToHand', OneHanded = true });
    check('REC32 enrich corrects the H2H lie in memory', h2hRec.OneHanded, false);
    local swd = { Name = 'Joyeuse', Type = 'Sword', OneHanded = true };
    grec.enrich(swd, { Name = 'Joyeuse', Type = 'Sword', OneHanded = true });
    check('REC33 enrich: a real 1H flag survives the rule', swd.OneHanded, true);
end)();

-- ---------------------------------------------------------------------------
-- SW. lib\safewrite -- the safe file-replacement ladder, written once (both
--     gear.lua writers ride replaceLua; profiles' deleters ride verifiedMove).
--     Real files under tests\ (cwd = addon root), removed at section end.
-- ---------------------------------------------------------------------------
(function()
    local sw = package.loaded['dlac\\lib\\safewrite'];
    check('SW0 module seeded', type(sw), 'table');
    local base = 'tests\\';
    local target = base .. 'sw_target.lua';
    local function put(p, t) local f = io.open(p, 'w'); f:write(t); f:close(); end
    local function get(p) local f = io.open(p, 'r'); if f == nil then return nil; end local t = f:read('*a'); f:close(); return t; end

    -- happy path: replace lands, tmp gone
    put(target, 'return { old = true }\n');
    check('SW1 replace succeeds', sw.replaceLua(target, 'return { new = true }\n', { origText = 'return { old = true }\n' }), true);
    check('SW2 new content live', get(target), 'return { new = true }\n');
    check('SW3 tmp cleaned',      get(target .. '.tmp'), nil);

    -- parse failure: refused before anything is written
    check('SW4 bad text refused',  (sw.replaceLua(target, 'return {', {})), nil);
    check('SW5 target untouched',  get(target), 'return { new = true }\n');

    -- validator failure: tmp removed, target untouched, reason carried
    local ok2, err2 = sw.replaceLua(target, 'return { v = 2 }\n', {
        origText = get(target),
        validate = function() return nil, 'nope'; end });
    check('SW6 validator can refuse', ok2, nil);
    check('SW6b reason carried',      err2 ~= nil and err2:find('nope', 1, true) ~= nil, true);
    check('SW7 target untouched on validate fail', get(target), 'return { new = true }\n');
    check('SW8 tmp cleaned on validate fail',      get(target .. '.tmp'), nil);

    -- the validator receives the loaded (unrun) chunk -- the sandbox-run shape
    -- gearimport's gearLoadValidator uses
    local seen = nil;
    sw.replaceLua(target, 'return 42\n', { validate = function(chunk) seen = chunk(); return true; end });
    check('SW9 validator gets runnable chunk', seen, 42);
    check('SW9b validated write landed',       get(target), 'return 42\n');

    -- timestampBackup (ashita.fs absent headless -> guarded dir creation skipped)
    local bp = sw.timestampBackup(base, 'swb_', 'content');
    check('SW10 backup written', bp ~= nil and get(bp), 'content');

    -- verifiedMove: copy + read-back verify + remove; missing source flagged
    put(base .. 'sw_src.lua', 'MOVE ME');
    check('SW11 verified move ok', sw.verifiedMove(base .. 'sw_src.lua', base .. 'sw_dst.lua'), true);
    check('SW12 dst holds content', get(base .. 'sw_dst.lua'), 'MOVE ME');
    check('SW13 src removed',       get(base .. 'sw_src.lua'), nil);
    local m2, _, missing = sw.verifiedMove(base .. 'sw_missing.lua', base .. 'sw_dst2.lua');
    check('SW14 missing source flagged', (m2 == nil and missing == true), true);

    os.remove(target); if bp then os.remove(bp); end os.remove(base .. 'sw_dst.lua');
end)();

-- ---------------------------------------------------------------------------
-- CI. gear\catalogindex -- Catalog access, one walker (raw id index + the
--     flattened browse copies + the generic gear-shaped flattener). Fresh
--     dofile instances per case so the lazy-load cache starts clean.
-- ---------------------------------------------------------------------------
(function()
    package.loaded['dlac\\data\\catalog'] = {
        Head = { TestCap = { Id = 11, Name = 'Test Cap', Level = 10, Stats = { HP = 5 } } },
        Main = { Sword = { Wax = { Id = 22, Name = 'Wax Sword', Level = 1, Type = 'Sword', OneHanded = true } } },
        Ammo = { Stone = { Id = 33, Name = 'Cinder Test', Level = 60, Type = 'Ammo' } },
        NameToObject = { ['Test Cap'] = { Id = 999, Name = 'DECOY' } },   -- aliases: must be skipped
    };
    local ci = dofile('gear/catalogindex.lua');
    check('CI0 available with catalog seeded', ci.available(), true);
    local raw = ci.rawIndex();
    check('CI1 raw ids indexed',        raw[11].Name, 'Test Cap');
    check('CI2 NameToObject skipped',   raw[999], nil);
    check('CI3 nested weapon reached',  raw[22].Type, 'Sword');
    check('CI4 rawById',                ci.rawById(33).Name, 'Cinder Test');
    local list, byId, byName = ci.flat();
    check('CI5 flat copies carry Slot',        byId[11].Slot, 'Head');
    check('CI6 flat Category from nesting',    byId[22].Category, 'Sword');
    check('CI7 byName lowercased',             byName['wax sword'].Id, 22);
    check('CI8 flat records are COPIES',       byId[11] ~= raw[11], true);
    check('CI9 flatten generic over gear-shaped tables',
        (select(2, ci.flatten({ Head = { C = { Id = 7, Name = 'C' } } })))[7].Slot, 'Head');

    -- missing catalog degrades quietly (guarded callers behave as before)
    package.loaded['dlac\\data\\catalog'] = nil;
    local ci2 = dofile('gear/catalogindex.lua');
    check('CI10 unavailable without catalog', ci2.available(), false);
    check('CI11 rawIndex empty, not nil',     next(ci2.rawIndex()), nil);
    check('CI12 flat empty, not nil',         #(ci2.flat()), 0);
end)();

-- ---------------------------------------------------------------------------
-- AV. ownedcache -- the availability verdict (ADR 0005: Owned vs Available are
--     two facts; stored beats locked beats ok) + the whereText caption builder.
--     First test reach this module has ever had, via the _splitOverride seam.
-- ---------------------------------------------------------------------------
(function()
    local oc = dofile('gear/ownedcache.lua');
    oc._splitOverride = {
        avail = { [1] = 1, [3] = 2 },              -- id 1, 3 equippable now
        total = { [1] = 1, [2] = 1, [3] = 2 },     -- id 2 owned but parked
        where = { [2] = { [1] = 1, [4] = 2 } },    -- id 2: container 1 x1, container 4 x2
    };
    check('AV1 available -> ok',        oc.verdict({ Id = 1 }), 'ok');
    check('AV2 stored beats usable',    oc.verdict({ Id = 2 }, true), 'stored');
    check('AV3 stored beats locked',    oc.verdict({ Id = 2 }, false), 'stored');
    check('AV4 locked when not usable', oc.verdict({ Id = 1 }, false), 'locked');
    check('AV5 nil usable reads ok',    oc.verdict({ Id = 3 }), 'ok');
    check('AV6 unowned never stored',   oc.verdict({ Id = 99 }, true), 'ok');
    check('AV7 isStored fact',          oc.isStored({ Id = 2 }), true);
    check('AV8 haveInBags stored copy', oc.haveInBags({ Id = 2 }), true);
    check('AV9 haveInBags unowned',     oc.haveInBags({ Id = 99 }), false);

    -- whereText: sorted container names via gearimport.containerName (faked,
    -- restored -- keep the swap contained to this closure)
    local saved = package.loaded['dlac\\gear\\gearimport'];
    package.loaded['dlac\\gear\\gearimport'] = { containerName = function(cid) return 'C' .. cid; end };
    check('AV10 whereText sorted with counts', oc.whereText({ Id = 2 }), 'C1, C4 x2');
    package.loaded['dlac\\gear\\gearimport'] = saved;
    check('AV11 whereText unowned empty', oc.whereText({ Id = 99 }), '');

    -- the safe fallback (documented): an empty scan hides NOTHING -- availability
    -- is colour, ownership gates visibility, and no data means no gating
    local oc2 = dofile('gear/ownedcache.lua');
    oc2._splitOverride = { avail = {}, total = {} };
    check('AV12 empty scan: haveInBags stays true', oc2.haveInBags({ Id = 5 }), true);
    check('AV13 empty scan: nothing stored',        oc2.verdict({ Id = 5 }, true), 'ok');
end)();

-- ---------------------------------------------------------------------------
-- VG. Virtual-decision gates, pure halves (engine v69): resolveObi and
--     resolveOneiros mirror resolveStaff -- data in, decision out; the rims in
--     resolveVirtual only read env/nativemp/vitals. These were the ONLY two
--     virtual decisions no test could reach, and both carry field-calibrated
--     rules (positive day/weather sign; the Mindie-pinned 50% inclusive MP
--     boundary) that now cannot drift silently.
-- ---------------------------------------------------------------------------
(function()
    local ro = dispatchM._resolveObi;
    local a = { obi = { Fire = { name = 'Karin Obi', level = 71 },
                        Ice  = { name = 'Hyorin Obi', level = 71 } },
                obiUniversal = { name = 'Hachirin-no-obi', level = 61 } };
    check('VG1 elemental obi on positive sign', ro(a, 'Fire', 75, 1), 'Karin Obi');
    local n2, w2 = ro(a, 'Fire', 75, 0);
    check('VG2 zero sign refused',  n2, nil);
    check('VG2b reason',            w2, 'day/weather not positive');
    check('VG3 negative sign refused', (ro(a, 'Fire', 75, -1)), nil);
    check('VG4 under-level elemental falls to universal', ro(a, 'Ice', 70, 1), 'Hachirin-no-obi');
    check('VG5 no elemental -> universal', ro({ obi = {}, obiUniversal = { name = 'Hachirin-no-obi', level = 61 } }, 'Earth', 75, 2), 'Hachirin-no-obi');
    check('VG6 elementless action refused', select(2, ro(a, nil, 75, 1)), 'no element');
    check('VG7 legacy string obi shape', ro({ obi = { Wind = 'Furin Obi' } }, 'Wind', 75, 1), 'Furin Obi');
    check('VG8 nothing usable reason', select(2, ro({ obi = {} }, 'Dark', 75, 1)), 'no usable obi for Dark at Lv75');

    local rg = dispatchM._resolveOneiros;
    local g = { name = 'Oneiros Grip', level = 75 };
    -- THE field pin (Mindie 2026-07-18): base 714 -> threshold 357, equality ACTIVE.
    check('VG9 at the boundary the latent is LIVE', rg(g, 75, 714, 357), 'Oneiros Grip');
    local n10, w10 = rg(g, 75, 714, 358);
    check('VG10 one MP above -> refused', n10, nil);
    check('VG10b threshold spelled in the reason', w10, 'MP 358 above the latent threshold 357 (half of base 714)');
    check('VG11 not owned',      select(2, rg(nil, 75, 714, 100)), 'Oneiros Grip not owned (the Automations tab rescans itself)');
    check('VG12 under level',    select(2, rg(g, 74, 714, 100)), 'under level for Oneiros Grip (Lv75)');
    check('VG13 base unreadable', select(2, rg(g, 75, nil, 100)), 'native MP unreadable (login settle?)');
    check('VG14 no pool',        select(2, rg(g, 75, 0, 0)), 'no native MP pool on this job');
    check('VG15 cur unreadable', select(2, rg(g, 75, 714, nil)), 'current MP unreadable');
end)();

-- ---------------------------------------------------------------------------
-- SF. The statefile seam (engine v70): ONE cached reader (ensureStateFile)
--     behind the auto/acc/craft/helm/fish/pin caches -- they were six
--     near-identical clones and had drifted (pin dropped corrupt writes, the
--     others kept the last good table glued on forever). Policy pinned HERE,
--     once, for all of them; _charDirOverride makes the file-driven surface
--     run headless for the first time.
-- ---------------------------------------------------------------------------
(function()
    local esf = dispatchM._ensureStateFile;
    check('SF0 helper exported', type(esf), 'function');
    local function put(p, t) local f = io.open(p, 'w'); f:write(t); f:close(); end
    dispatchM._charDirOverride = 'tests\\';
    local cache = { raw = nil, data = nil, lastCheck = -1 };

    put('tests\\sf_state.lua', 'return { enabled = true, craft = "Alchemy" }');
    local d = esf(cache, 'sf_state.lua');
    check('SF1 file read + parsed', d ~= nil and d.craft, 'Alchemy');

    -- same-second throttle: a changed file is not re-read until the clock moves
    put('tests\\sf_state.lua', 'return { craft = "Smithing" }');
    cache.lastCheck = os.time();
    check('SF2 throttled within the second', esf(cache, 'sf_state.lua').craft, 'Alchemy');

    -- THE POLICY: corrupt write -> DROP (not last-good); re-reads stay dropped
    cache.lastCheck = -1;
    put('tests\\sf_state.lua', 'return {');
    check('SF3 corrupt write drops the state', esf(cache, 'sf_state.lua'), nil);
    cache.lastCheck = -1;
    check('SF4 corrupt stays dropped on re-read', esf(cache, 'sf_state.lua'), nil);

    -- the next good write self-heals
    cache.lastCheck = -1;
    put('tests\\sf_state.lua', 'return { craft = "Bonecraft" }');
    check('SF5 good write self-heals', esf(cache, 'sf_state.lua').craft, 'Bonecraft');

    -- a file that parses but ERRORS on run drops too
    cache.lastCheck = -1;
    put('tests\\sf_state.lua', 'error("boom")');
    check('SF6 run-error drops the state', esf(cache, 'sf_state.lua'), nil);

    -- missing file = state off
    cache.lastCheck = -1;
    os.remove('tests\\sf_state.lua');
    check('SF7 missing file = state off', esf(cache, 'sf_state.lua'), nil);

    -- pre-login (no char dir) keeps whatever is cached
    cache.lastCheck = -1; cache.data = { keep = true };
    dispatchM._charDirOverride = nil;
    check('SF8 no char dir keeps cache', esf(cache, 'sf_state.lua').keep, true);

    -- WIRING: with no test override, the auto manifest reads through the seam.
    -- The _auto singleton's 1s throttle may have been armed by an earlier
    -- section in this same second -- cross the boundary so the read is live.
    dispatchM._charDirOverride = 'tests\\';
    dispatchM._autoOverride = nil;
    put('tests\\autogear.lua', 'return { universal = { name = "Chatoyant Staff", tier = 2, level = 51 } }');
    local t0 = os.time(); repeat until os.time() ~= t0;
    check('SF9 resolveVirtual reads the manifest through the seam',
        dispatchM._resolveVirtual('dlac:AutoStaff', { player = { MainJobSync = 75 } }), 'Chatoyant Staff');
    os.remove('tests\\autogear.lua');
    dispatchM._charDirOverride = nil;
end)();

-- ---------------------------------------------------------------------------
-- PL. equipResolved's post-pass order is DATA (engine v71): the five
--     whole-table passes run in M._postPassOrder. A reorder must edit BOTH the
--     list and this pin -- which is the point: the ADR 0010 constraint
--     (trinket-vs-ranged strictly before reserved-drops, or the loser gets to
--     reserve and the result flaps) is now checkable instead of prose.
-- ---------------------------------------------------------------------------
(function()
    local po = dispatchM._postPassOrder;
    check('PL1 order exported', type(po), 'table');
    check('PL2 exact order', table.concat(po, '>'),
        'mp-stage>craft-sub-guard>sync-hold-ammo>trinket-vs-ranged>reserved-drops');
    local ti, ri = nil, nil;
    for i, nm in ipairs(po) do
        if nm == 'trinket-vs-ranged' then ti = i; end
        if nm == 'reserved-drops' then ri = i; end
    end
    check('PL3 ADR 0010: trinket strictly before reserved', ti ~= nil and ri ~= nil and ti < ri, true);
end)();

-- ---------------------------------------------------------------------------
-- AR. THE ARBITER, step 1 (engine v97, ADR 0012). One data-driven claim
--     registry orders every Claim's application, replacing the hardcoded
--     overlay sequence. This section is the ORDER-PINNING test (a reorder of
--     the built-in default must edit BOTH the constant and this pin), the pure
--     resolve core (claims + rank + floor -> winners + attribution), arbstate
--     sanitization + the Statefile drop policy, MaxMP's rank-consult (ceded
--     slots), and the ONE deliberate change wired through equipResolved
--     (AutoAmmo's projectile beats a battery in Ammo).
-- ---------------------------------------------------------------------------
(function()
    -- AR1: the built-in default rank, highest first. Pinned so an accidental
    -- reorder fails loudly (the POST_ORDER precedent, PL2).
    local def = dispatchM._arbDefaultOrder;
    check('AR1 default order exported', type(def), 'table');
    check('AR1b exact default rank', table.concat(def, '>'),
        'Disabled>Naked>Pins>Locks>AutoAmmo>MaxMP>Craft>HELM>Fishing>Chocobo>Triggers');
    -- AR1c: the ADR 0012 laws the order encodes, checked as adjacency (not prose)
    local rank = {}; for i, n in ipairs(def) do rank[n] = i; end
    -- Naked (ADR 0021) is the ONE row above Pins: "naked" must mean naked, and a
    -- player who wants "naked except my pins" drags Pins over it. Do not "fix"
    -- this back to Pins == 1.
    check('AR1d Naked outranks every RANKED row (the Disabled ceiling is not one -- ADR 0024)',
        rank['Disabled'] == 1 and rank['Naked'] == 2 and rank['Pins'] == 3, true);
    check('AR1e Locks veto sits under Pins', rank['Locks'] == rank['Pins'] + 1, true);
    check('AR1f AutoAmmo outranks MaxMP (the deliberate change)', rank['AutoAmmo'] < rank['MaxMP'], true);
    check('AR1g MaxMP outranks Craft/HELM/Fishing (batteries over their armor)',
        rank['MaxMP'] < rank['Craft'] and rank['Craft'] < rank['HELM'] and rank['HELM'] < rank['Fishing'], true);
    check('AR1h Triggers is the floor (last)', rank['Triggers'], #def);

    -- AR2: arbOrder sanitizes. Missing/torn -> default; unknown dropped, missing
    -- known rows restored AT THEIR DEFAULT POSITION (v122 -- see NK8/NK9; the old
    -- law appended them, which is right only for a row that belongs last); a valid
    -- reorder is preserved.
    check('AR2 nil -> default', table.concat(dispatchM.arbOrder(nil), '>'),
        'Disabled>Naked>Pins>Locks>AutoAmmo>MaxMP>Craft>HELM>Fishing>Chocobo>Triggers');
    check('AR2b no order field -> default', table.concat(dispatchM.arbOrder({ foo = 1 }), '>'),
        'Disabled>Naked>Pins>Locks>AutoAmmo>MaxMP>Craft>HELM>Fishing>Chocobo>Triggers');
    check('AR2c a valid reorder is preserved',
        table.concat(dispatchM.arbOrder({ order = { 'MaxMP', 'AutoAmmo', 'Pins', 'Locks', 'Craft', 'HELM', 'Fishing', 'Triggers' } }), '>'),
        'Disabled>Naked>MaxMP>AutoAmmo>Pins>Locks>Craft>HELM>Fishing>Chocobo>Triggers');
    -- Listed rows keep the user's order absolutely (Fishing still above Pins);
    -- every unlisted row lands where it sits by default RELATIVE to them --
    -- Naked before Fishing, Chocobo after Pins because nothing outranks it.
    check('AR2d unknown rows dropped, missing known rows restored at their default position',
        table.concat(dispatchM.arbOrder({ order = { 'Fishing', 'Nonsense', 'Pins' } }), '>'),
        'Disabled>Naked>Locks>AutoAmmo>MaxMP>Craft>HELM>Fishing>Pins>Chocobo>Triggers');
    check('AR2e duplicates collapse',
        table.concat(dispatchM.arbOrder({ order = { 'Pins', 'Pins', 'AutoAmmo' } }), '>'),
        'Disabled>Naked>Pins>Locks>AutoAmmo>MaxMP>Craft>HELM>Fishing>Chocobo>Triggers');

    -- AR3: the PURE resolve core -- claims + rank + floor -> winners + by.
    local order = dispatchM.arbOrder(nil);
    local floor = { Head = 'Idle Hat', Body = 'Idle Robe', Ammo = 'Iron Arrow' };
    -- floor only
    local w0, by0 = dispatchM.arbResolve({}, order, floor);
    check('AR3 floor flows when no claims', w0.Body, 'Idle Robe');
    check('AR3b floor attribution', by0.Body, 'Triggers');
    -- pins over everything (default-order equivalence: pins over craft over floor)
    local w1, by1 = dispatchM.arbResolve({
        Pins  = { Head = 'Pinned Crown' },
        Craft = { Head = 'Craft Cap', Hands = 'Craft Gloves' },
    }, order, floor);
    check('AR4 pins win the contested slot',   w1.Head, 'Pinned Crown');
    check('AR4b attribution names the pin',    by1.Head, 'Pins');
    check('AR4c craft wins where pins are silent', w1.Hands, 'Craft Gloves');
    check('AR4d craft over the floor',         by1.Hands, 'Craft');
    check('AR4e the floor still shows through', w1.Body, 'Idle Robe');
    -- reorder changes winners: move Craft above Pins and craft takes Head
    local reordered = dispatchM.arbOrder({ order = { 'Craft', 'Pins', 'Locks', 'AutoAmmo', 'MaxMP', 'HELM', 'Fishing', 'Triggers' } });
    local w2 = dispatchM.arbResolve({
        Pins  = { Head = 'Pinned Crown' },
        Craft = { Head = 'Craft Cap' },
    }, reordered, floor);
    check('AR5 a reorder changes the winner (craft over pins)', w2.Head, 'Craft Cap');

    -- AR6: arbCededAbove -- the slots woven MaxMP must not contest. At default
    -- rank the ceded set is Pins' and AutoAmmo's slots; Craft/HELM/Fishing rank
    -- BELOW MaxMP so their slots are never ceded (batteries keep overriding
    -- their armor). Reorder MaxMP above AutoAmmo and Ammo is no longer ceded.
    local ceded = dispatchM.arbCededAbove({
        Pins     = { Head = 'Pinned Crown' },
        AutoAmmo = { Ammo = 'Fire Bomblet' },
        Craft    = { Hands = 'Craft Gloves', Neck = 'Craft Torque' },
    }, order, 'MaxMP');
    check('AR6 Ammo ceded to AutoAmmo',        ceded['ammo'], 'AutoAmmo');
    check('AR6b Head ceded to Pins',           ceded['head'], 'Pins');
    check('AR6c Craft slots NOT ceded (below MaxMP)', ceded['hands'], nil);
    check('AR6d Craft neck NOT ceded',         ceded['neck'], nil);
    local cededReord = dispatchM.arbCededAbove({
        AutoAmmo = { Ammo = 'Fire Bomblet' },
    }, dispatchM.arbOrder({ order = { 'Pins', 'Locks', 'MaxMP', 'AutoAmmo', 'Craft', 'HELM', 'Fishing', 'Triggers' } }), 'MaxMP');
    check('AR6e reorder MaxMP above AutoAmmo -> Ammo no longer ceded', cededReord['ammo'], nil);
    check('AR6f who not in the order -> nothing ceded',
        next(dispatchM.arbCededAbove({ Pins = { Head = 'x' } }, order, 'Nobody')), nil);

    -- AR7: arbstate as a Statefile through the shared reader -- a hand-edited
    -- reorder changes the order; a torn write drops to the default (the SF
    -- policy). Driven through _ensureStateFile like the SF section.
    local esf = dispatchM._ensureStateFile;
    local function put(p, t) local f = io.open(p, 'w'); f:write(t); f:close(); end
    dispatchM._charDirOverride = 'tests\\';
    local cache = { raw = nil, data = nil, lastCheck = -1 };
    put('tests\\arbstate.lua', 'return { order = { "MaxMP", "AutoAmmo", "Pins", "Locks", "Craft", "HELM", "Fishing", "Triggers" } }');
    check('AR7 hand-edited reorder is read + sanitized',
        table.concat(dispatchM.arbOrder(esf(cache, 'arbstate.lua')), '>'),
        'Disabled>Naked>MaxMP>AutoAmmo>Pins>Locks>Craft>HELM>Fishing>Chocobo>Triggers');
    cache.lastCheck = -1;
    put('tests\\arbstate.lua', 'return { order = {');   -- torn write
    check('AR7b torn write drops to default',
        table.concat(dispatchM.arbOrder(esf(cache, 'arbstate.lua')), '>'),
        'Disabled>Naked>Pins>Locks>AutoAmmo>MaxMP>Craft>HELM>Fishing>Chocobo>Triggers');
    os.remove('tests\\arbstate.lua');
    dispatchM._charDirOverride = nil;

    -- AR8: activities CO-CLAIM (ADR 0012 amendment, step 1.5). The newest-armed
    -- (`at` stamp) exclusivity that stood the others down whole is retired: with
    -- two OR three of Craft/HELM/Fishing armed, EVERY armed activity claims and
    -- the rank list settles each overlapping slot PER SLOT. Pinned at the resolve
    -- seam -- arbResolve is blind to any `at` field, which is exactly the point:
    -- arming one activity does not affect the others' claims. (The exclusivity
    -- lived inline in M.dispatch, never at a pure seam, so there was no old
    -- exclusivity-pin test to invert -- these ADD the co-claim law it replaced.)
    do
        local ord = dispatchM.arbOrder(nil);   -- ...Craft>HELM>Fishing...
        -- Two armed: Craft + HELM share Head/Hands; Craft ranks above HELM.
        local w, by = dispatchM.arbResolve({
            Craft = { Head = 'Craft Cap', Hands = 'Craft Gloves', Neck = 'Craft Torque' },
            HELM  = { Head = 'Field Hat', Hands = 'Field Gloves', Waist = 'Field Belt' },
        }, ord, { Body = 'Idle Robe' });
        check('AR8 both armed -> both claim, no whole stand-down (craft neck kept)', w.Neck, 'Craft Torque');
        check('AR8b HELM keeps its own slot (waist)', w.Waist, 'Field Belt');
        check('AR8c rank settles the shared slot per slot (Craft > HELM on Head)', w.Head, 'Craft Cap');
        check('AR8d shared Hands also to Craft', by.Hands, 'Craft');
        check('AR8e floor still shows where none claim', w.Body, 'Idle Robe');
        -- Three armed at once: each keeps its own exclusive slot; the shared one
        -- goes to the highest rank. Nothing stands down.
        local w3 = dispatchM.arbResolve({
            Craft   = { Hands = 'Craft Gloves' },
            HELM    = { Neck  = 'Field Torque' },
            Fishing = { Range = 'Lu Shangs Rod', Hands = 'Fishing Gloves' },
        }, ord, {});
        check('AR9 three armed: craft keeps Hands (ranked top of the three)', w3.Hands, 'Craft Gloves');
        check('AR9b HELM keeps Neck',   w3.Neck, 'Field Torque');
        check('AR9c Fishing keeps Range (no other claims it)', w3.Range, 'Lu Shangs Rod');
    end

    -- AR10: the PUP field case that drove the ruling, VERBATIM (issue #53). PUP
    -- idle floor names Range = Animator. Fishing armed -> rod in Range. HELM also
    -- armed (ranked ABOVE Fishing) wins only its seven armor slots; HELM never
    -- claims weapons/Range/rings/Ammo, so the ROD STAYS IN RANGE. The Animator
    -- returns only when Fishing itself is disarmed.
    do
        local ord = dispatchM.arbOrder(nil);   -- default: HELM ranks above Fishing
        -- PUP idle floor (the trigger overlay result the claims dress over).
        local floor = {
            Main = 'Animator P', Sub = 'Animator P II', Range = 'Animator',
            Head = 'Idle Head', Body = 'Idle Body', Hands = 'Idle Hands',
            Legs = 'Idle Legs', Feet = 'Idle Feet', Neck = 'Idle Neck',
            Waist = 'Idle Waist', Ring1 = 'Idle Ring1', Ring2 = 'Idle Ring2',
        };
        -- Fishing armed: rod in Range, spear in Main, bait in Ammo, fishing armor.
        local fishing = {
            Main = 'Halieutica', Range = 'Lu Shangs Rod', Ammo = 'Little Worm',
            Head = 'Fish Head', Body = 'Fish Body', Hands = 'Fish Hands',
            Legs = 'Fish Legs', Feet = 'Fish Feet',
        };
        -- HELM armed: its seven armor slots ONLY (armor + neck + waist).
        local helm = {
            Head = 'Helm Head', Body = 'Helm Body', Hands = 'Helm Hands',
            Legs = 'Helm Legs', Feet = 'Helm Feet', Neck = 'Helm Neck',
            Waist = 'Helm Waist',
        };
        local w, by = dispatchM.arbResolve({ HELM = helm, Fishing = fishing }, ord, floor);
        check('AR10 the rod stays in Range (HELM never claims it)', w.Range, 'Lu Shangs Rod');
        check('AR10b Range attributed to Fishing, not the floor Animator', by.Range, 'Fishing');
        check('AR10c HELM wins its seven armor slots (Head)', by.Head, 'HELM');
        check('AR10d HELM wins Neck', w.Neck, 'Helm Neck');
        check('AR10e HELM wins Waist', w.Waist, 'Helm Waist');
        check('AR10f fishing Main spear survives (HELM never claims weapons)', w.Main, 'Halieutica');
        check('AR10g fishing bait survives in Ammo (HELM never claims Ammo)', w.Ammo, 'Little Worm');
        check('AR10h rings fall to the floor (neither claims them)', w.Ring1, 'Idle Ring1');
        -- Disarm Fishing (drop its claim): the Animator returns to Range.
        local w2, by2 = dispatchM.arbResolve({ HELM = helm }, ord, floor);
        check('AR10i Fishing disarmed -> Animator returns to Range', w2.Range, 'Animator');
        check('AR10j and Range is the floor again', by2.Range, 'Triggers');
    end
end)();

-- ---------------------------------------------------------------------------
-- AR11/AR12. THE ARBITER, step 4 (ADR 0012 / issue #51). The registry is the
--      SINGLE precedence authority, so the pure resolve that decides winners
--      ALSO explains them (/dl why). AR11 pins the whole claim path -- every
--      claimant (incl. the MaxMP battery claim + the Locks veto) resolved in
--      ONE rank walk via arbExplain. AR12 pins the /dl why line format:
--      'Ammo: AutoAmmo (rank 3) over MaxMP (rank 4)', veto slots 'stopped by
--      Locks', floor-only slots 'Triggers (floor)', in canonical LAC order.
-- ---------------------------------------------------------------------------
(function()
    local ord = dispatchM.arbOrder(nil);  -- Naked>Pins>Locks>AutoAmmo>MaxMP>Craft>HELM>Fishing>Chocobo>Triggers
    -- The whole claim path in one resolve. MaxMP is a proper CLAIM now (step 4):
    -- its battery targets a claim table, ranked below AutoAmmo (the deliberate
    -- cede) and above Craft (batteries over craft armor).
    local claims = {
        Pins     = { Head = 'Pinned Crown' },
        AutoAmmo = { Ammo = 'Orichalc. Bullet' },
        MaxMP    = { Ammo = 'MP Bullet', Ring1 = 'MP Ring', Head = 'MP Crown' },
        Craft    = { Head = 'Craft Cap', Hands = 'Craft Gloves' },
        Locks    = dispatchM.arbLockClaim({ 'Legs' }),
    };
    local floor = { Head = 'Idle Hat', Ammo = 'Idle Ammo', Ring1 = 'Idle Ring',
                    Hands = 'Idle Hands', Legs = 'Idle Legs', Body = 'Idle Body' };
    local ex = dispatchM.arbExplain(claims, ord, floor);
    -- Ammo: AutoAmmo(4) > MaxMP(5) > Triggers(10) -- the issue's headline contest.
    check('AR11 Ammo winner is AutoAmmo',            ex.Ammo[1].name, 'AutoAmmo');
    check('AR11b Ammo winner rank is 5 (the Disabled ceiling took 1, Naked 2)', ex.Ammo[1].rank, 5);
    check('AR11c Ammo runner-up is the MaxMP battery (the deliberate cede)', ex.Ammo[2].name, 'MaxMP');
    check('AR11d Ammo third is the floor',           ex.Ammo[3].name, 'Triggers');
    -- Head: Pins(2) > MaxMP(5) > Craft(6) > Triggers(10).
    check('AR11e Head winner is the pin',            ex.Head[1].name, 'Pins');
    check('AR11f Head second is MaxMP (battery over craft armor)', ex.Head[2].name, 'MaxMP');
    check('AR11g Head third is Craft',               ex.Head[3].name, 'Craft');
    -- Ring1: a MaxMP battery in a bare ring over the floor.
    check('AR11h Ring1 winner is MaxMP',             ex.Ring1[1].name, 'MaxMP');
    check('AR11i Ring1 second is the floor',         ex.Ring1[2].name, 'Triggers');
    -- Hands: only Craft claims it.
    check('AR11j Hands winner is Craft',             ex.Hands[1].name, 'Craft');
    -- Legs: the Locks veto (rank 3) wins; nothing claims above it.
    check('AR11k Legs winner is the Locks veto',     ex.Legs[1].name, 'Locks');
    check('AR11l Legs veto held off the floor',      ex.Legs[2].name, 'Triggers');
    -- Body: floor-only.
    check('AR11m Body is floor-only Triggers',       ex.Body[1].name, 'Triggers');
    check('AR11n Body has no other opinion',         #ex.Body, 1);
end)();

(function()
    local ord = dispatchM.arbOrder(nil);
    local claims = {
        AutoAmmo = { Ammo = 'Orichalc. Bullet' },
        MaxMP    = { Ammo = 'MP Bullet', Ring1 = 'MP Ring' },
        Craft    = { Hands = 'Craft Gloves' },
        Locks    = dispatchM.arbLockClaim({ 'legs' }),   -- lowercase key (the live M.locks shape)
    };
    local floor = { Ammo = 'Idle Ammo', Ring1 = 'Idle Ring', Hands = 'Idle Hands',
                    Legs = 'Idle Legs', Body = 'Idle Body' };
    local joined = table.concat(dispatchM.arbWhyLines(claims, ord, floor), '\n');
    check('AR12 the Ammo contest line names winner over runner-up (the issue example)',
        joined:find('Ammo: AutoAmmo (rank 5)  over MaxMP (rank 6)', 1, true) ~= nil, true);
    check('AR12b a MaxMP-only slot reads MaxMP over the floor',
        joined:find('Ring1: MaxMP (rank 6)  over Triggers (rank 11)', 1, true) ~= nil, true);
    check('AR12c a veto slot reads stopped by Locks (even from a lowercase key)',
        joined:find('Legs: stopped by Locks (rank 4)', 1, true) ~= nil, true);
    check('AR12d floor-only slots collapse into one named Triggers-floor summary',
        joined:find('Triggers floor (rank 11, uncontested):', 1, true) ~= nil
        and joined:find('Body', 1, true) ~= nil, true);
    -- Contested slots emit individually in canonical LAC order (ammo 4 < hands 10
    -- < ring1 11), BEFORE the trailing floor summary.
    local iAmmo, iHands, iRing = joined:find('Ammo:', 1, true), joined:find('Hands:', 1, true), joined:find('Ring1:', 1, true);
    check('AR12e contested slots emit in canonical LAC order (Ammo < Hands < Ring1)',
        iAmmo < iHands and iHands < iRing, true);
end)();

-- ---------------------------------------------------------------------------
-- ARE. The Arbiter's ONE deliberate change wired through equipResolved (v97):
--      with an ON battery band and an AutoAmmo plan both wanting Ammo, the
--      named projectile wins -- Ammo is ceded to AutoAmmo (ranked above MaxMP),
--      so woven MaxMP stands down on that slot. Stubs M.mpBands so the MP path
--      is reachable headless without the whole manifest (the mpbands core has
--      its own MB* tests); the ceding GUARD is what this exercises.
-- ---------------------------------------------------------------------------
(function()
    local savedAC, savedBands = AshitaCore, dispatchM.mpBands;
    AshitaCore = nil;                                   -- wornItemName -> nil everywhere
    for k in pairs(dispatchM.locks) do dispatchM.locks[k] = nil; end
    dispatchM.modes['maxmp'] = true;
    -- A band that WANTS a 20-MP battery in Ammo. mpBandFind reads .bands ({} ->
    -- nil, harmless); mpStickyPairs reads .mpBest (nil-safe for ammo).
    dispatchM.mpBands = function()
        return {
            mpMap = { ['mp bullet'] = 20, ['fire bomblet'] = 0 },
            target = { ammo = 'MP Bullet' },
            bands = {}, mpBest = {}, moveYield = false, moving = false, mvMap = {},
        };
    end;

    -- No ceding: the battery band takes Ammo (today's behavior).
    local _, wOn = dispatchM._equipResolved({ Ammo = 'Fire Bomblet' }, { mpCeded = {} });
    check('ARE1 with no ceding the battery wins Ammo', wOn.Ammo, 'MP Bullet');
    -- Ammo ceded to AutoAmmo (the default rank): the projectile survives.
    local _, wCede = dispatchM._equipResolved({ Ammo = 'Fire Bomblet' },
        { mpCeded = { ammo = 'AutoAmmo' } });
    check('ARE2 Ammo ceded -> the named projectile wins', wCede.Ammo, 'Fire Bomblet');
    -- A NON-ceded MP slot still gets its battery (ceding is per-slot, not global).
    dispatchM.mpBands = function()
        return {
            mpMap = { ['mp ring'] = 15, ['plain ring'] = 0 },
            target = { ring1 = 'MP Ring' },
            bands = {}, mpBest = {}, moveYield = false, moving = false, mvMap = {},
        };
    end;
    local _, wRing = dispatchM._equipResolved({ Ring1 = 'Plain Ring' },
        { mpCeded = { ammo = 'AutoAmmo' } });
    check('ARE3 an un-ceded slot still takes its battery', wRing.Ring1, 'MP Ring');

    dispatchM.modes['maxmp'] = nil;
    dispatchM.mpBands = savedBands;
    AshitaCore = savedAC;
end)();

-- ---------------------------------------------------------------------------
-- LV. LOCKS ARE THE DRAGGABLE VETO ROW (ADR 0012, step 3 / issue #50). Two
--     pinned surfaces: (a) the PURE resolve model -- Locks passed to arbResolve
--     as a veto claim (arbLockClaim -> the LOCK_HELD sentinel), so its rank
--     decides who punches through and who stops; (b) the LIVE wiring -- the
--     per-layer respectLocks flag through equipResolved, and woven MaxMP's own
--     rank vs Locks via ctx.mpRespectLocks (band build + mp-stage placement).
-- ---------------------------------------------------------------------------
(function()
    -- (a) The pure resolve model. arbLockClaim builds the veto table.
    local lc = dispatchM.arbLockClaim({ head = true, ring2 = false });
    check('LV0 arbLockClaim maps only truthy slots to the veto sentinel',
        lc.head == dispatchM.LOCK_HELD and lc.ring2 == nil, true);
    check('LV0b arbLockClaim accepts an array of slot keys',
        dispatchM.arbLockClaim({ 'Head', 'Ring1' }).Ring1, dispatchM.LOCK_HELD);

    local order = dispatchM.arbOrder(nil);  -- Naked>Pins>Locks>AutoAmmo>MaxMP>Craft>HELM>Fishing>Chocobo>Triggers
    local floor = { Head = 'Idle Hat', Ring1 = 'Idle Ring' };
    local locked = dispatchM.arbLockClaim({ 'Head', 'Ring1' });  -- both slots locked

    -- Default position: pins (above Locks) punch through; craft + floor (below) stop.
    local w1, by1 = dispatchM.arbResolve({
        Pins  = { Head = 'Pinned Crown' },
        Craft = { Head = 'Craft Cap', Ring1 = 'Craft Ring' },
        Locks = locked,
    }, order, floor);
    check('LV1 a pin above Locks punches through the locked slot', w1.Head, 'Pinned Crown');
    check('LV1b that slot is attributed to the pin', by1.Head, 'Pins');
    check('LV1c craft below Locks stops at the lock (kept worn)', w1.Ring1, dispatchM.LOCK_HELD);
    check('LV1d the locked-stop is attributed to Locks', by1.Ring1, 'Locks');

    -- Locks dragged to the TOP: an absolute veto, pins included.
    local topLocks = dispatchM.arbOrder({ order = {
        'Locks', 'Pins', 'AutoAmmo', 'MaxMP', 'Craft', 'HELM', 'Fishing', 'Triggers' } });
    local w2, by2 = dispatchM.arbResolve({
        Pins = { Head = 'Pinned Crown' }, Locks = locked,
    }, topLocks, floor);
    check('LV2 Locks at the top vetoes even pins', w2.Head, dispatchM.LOCK_HELD);
    check('LV2b attributed to Locks', by2.Head, 'Locks');

    -- Locks dragged LOWER: everyone above punches through, everyone below stops.
    local lowLocks = dispatchM.arbOrder({ order = {
        'Pins', 'AutoAmmo', 'MaxMP', 'Craft', 'Locks', 'HELM', 'Fishing', 'Triggers' } });
    local w3, by3 = dispatchM.arbResolve({
        Craft = { Head = 'Craft Cap' },   -- rank 4, above the lowered Locks (5): punches through
        HELM  = { Ring1 = 'Helm Ring' },  -- rank 6, below Locks: stops
        Locks = locked,
    }, lowLocks, floor);
    check('LV3 a claimant above the lowered Locks punches through', w3.Head, 'Craft Cap');
    check('LV3b a claimant below the lowered Locks stops', w3.Ring1, dispatchM.LOCK_HELD);
    check('LV3c the below-Locks stop is attributed to Locks', by3.Ring1, 'Locks');

    -- (b) The LIVE wiring through equipResolved: the per-layer respectLocks flag.
    local savedAC = AshitaCore;
    AshitaCore = nil;                                   -- wornItemName -> nil
    for k in pairs(dispatchM.locks) do dispatchM.locks[k] = nil; end
    dispatchM.locks['head'] = true;
    -- respectLocks default (nil == true): the locked slot is stripped (held worn).
    local _, wResp = dispatchM._equipResolved({ Head = 'Some Hat', Body = 'Some Body' }, {});
    check('LV4 respectLocks default strips the locked slot', wResp.Head, nil);
    check('LV4b an unlocked slot still equips', wResp.Body, 'Some Body');
    check('LV4c the strip is still traced', (function()
        local note = dispatchM._equipResolved({ Head = 'Some Hat' }, {});
        return string.find(note, 'LOCKED', 1, true) ~= nil;
    end)(), true);
    -- respectLocks = false: a layer ranked ABOVE Locks punches through.
    local _, wPunch = dispatchM._equipResolved({ Head = 'Some Hat', Body = 'Some Body' }, {}, false);
    check('LV5 respectLocks=false punches the layer through the lock', wPunch.Head, 'Some Hat');
    check('LV5b explicit respectLocks=true stops (== the default)',
        select(2, dispatchM._equipResolved({ Head = 'Some Hat' }, {}, true)).Head, nil);

    -- (b) woven MaxMP vs Locks -- its OWN rank via ctx.mpRespectLocks. mp-stage
    -- must not dress a locked UNCOVERED slot while MaxMP ranks below Locks, and
    -- must punch through when it ranks above. Stub mpBands (the MB* tests own the
    -- band core); the veto guard is what this exercises.
    local savedBands = dispatchM.mpBands;
    dispatchM.modes['maxmp'] = true;
    for k in pairs(dispatchM.locks) do dispatchM.locks[k] = nil; end
    dispatchM.locks['ring1'] = true;
    dispatchM.mpBands = function()
        return { mpMap = { ['mp ring'] = 15 }, target = { ring1 = 'MP Ring' },
                 bands = {}, mpBest = {}, moveYield = false, moving = false, mvMap = {} };
    end;
    local _, wRespMp = dispatchM._equipResolved({ Head = 'Idle Hat' },
        { mpCeded = {}, mpRespectLocks = true });
    check('LV6 MaxMP staging respects a locked slot while below Locks', wRespMp.Ring1, nil);
    local _, wPunchMp = dispatchM._equipResolved({ Head = 'Idle Hat' },
        { mpCeded = {}, mpRespectLocks = false });
    check('LV7 MaxMP staging punches through a locked slot while above Locks', wPunchMp.Ring1, 'MP Ring');

    dispatchM.modes['maxmp'] = nil;
    dispatchM.mpBands = savedBands;
    for k in pairs(dispatchM.locks) do dispatchM.locks[k] = nil; end
    AshitaCore = savedAC;
end)();

-- ---------------------------------------------------------------------------
-- NK. NAKED (ADR 0021) -- /dl naked strips every slot and HOLDS it empty, as an
--     ordinary Arbiter claimant ranked first, not as a lock.
--
--     Why a claim: a lock only WITHHOLDS (it deletes a slot from a layer's plan
--     -- it cannot take a piece off), it is wiped by every engine self-swap,
--     Pins punch through it by default, and three unrelated buttons release it.
--     A claim is recomputed every dispatch, so a strip the server refuses heals
--     itself -- and precedence becomes the player's, for free.
--
--     The two traps these pin, both of which would ship silently:
--       NK3  the claim must use PROPER-CASE slot keys. equipcore.SLOT_ID is
--            case-sensitive and LuaAshitacast's is not, so a lowercase claim
--            works in LAC and strips NOTHING natively -- broken only in the
--            mode that actually ships.
--       NK8  a row missing from an existing arbstate file must land at its
--            DEFAULT position, not the bottom. Appended, Naked would rank under
--            Locks for every character who ever opened the Priority list.
-- ---------------------------------------------------------------------------
(function()
    local canon = dispatchM._lacSlotsCanon;
    check('NK1 the canonical slot list is the 16', type(canon) == 'table' and #canon, 16);
    -- The equip vocabulary and the /dl lock vocabulary must name the SAME slots.
    -- Compared as SETS, not concatenated: gear\equipcore.lua's SLOT_NAMES is a
    -- third order again, so order equality would be a lie that happens to hold.
    check('NK1b lowercasing the equip vocabulary yields the lock vocabulary', (function()
        for _, s in ipairs(canon) do
            if dispatchM.setLock(string.lower(s), false) == nil then return 'missing ' .. s; end
        end
        return true;
    end)(), true);

    local claim = dispatchM.nakedClaim();
    local n, allRemove = 0, true;
    for _, v in pairs(claim) do n = n + 1; if v ~= 'remove' then allRemove = false; end end
    check('NK2 the claim names all 16 slots', n, 16);
    check('NK2b every value is the unequip literal', allRemove, true);
    check('NK3 keys are PROPER case (a lowercase key is dropped by the native engine)',
        claim.Main == 'remove' and claim.main == nil and claim.Ring1 == 'remove', true);
    claim.Main = 'mutated';
    check('NK4 each call returns a fresh table', dispatchM.nakedClaim().Main, 'remove');

    -- The flag. setNaked is the ONE door; nakedOn the ONE reader.
    dispatchM.nakedArmed = false;
    check('NK5 off by default', dispatchM.nakedOn(), false);
    check('NK5b setNaked(true) returns the new state', dispatchM.setNaked(true), true);
    check('NK5c and arms the flag', dispatchM.nakedOn(), true);
    check('NK5d arming twice is idempotent', dispatchM.setNaked(true), true);
    dispatchM.nakedArmed = 'yes';                     -- a truthy non-true must not count
    check('NK5e only a literal true is armed', dispatchM.nakedOn(), false);
    dispatchM.setNaked(false);
    check('NK5f setNaked(false) disarms', dispatchM.nakedOn(), false);

    -- The rank row.
    local def = dispatchM._arbDefaultOrder;
    local rank = {}; for i, nm in ipairs(def) do rank[nm] = i; end
    check('NK6 exact default rank', table.concat(def, '>'),
        'Disabled>Naked>Pins>Locks>AutoAmmo>MaxMP>Craft>HELM>Fishing>Chocobo>Triggers');
    check('NK7 Naked outranks Pins, which outranks Locks',
        rank['Naked'] < rank['Pins'] and rank['Pins'] < rank['Locks'], true);

    -- TRAP: every arbstate file written before v122 lists nine rows and no Naked.
    -- Index 2, not 1: the Disabled ceiling is pinned above every RANKED row
    -- (ADR 0024), so "the top" for a claimant means directly under it.
    check('NK8 a pre-v122 file gets Naked at the TOP, not the bottom',
        dispatchM.arbOrder({ order = { 'Pins', 'Locks', 'AutoAmmo', 'MaxMP',
                                       'Craft', 'HELM', 'Fishing', 'Chocobo', 'Triggers' } })[2], 'Naked');
    check('NK9 a file that places Naked LOW keeps it there (the user has spoken)',
        table.concat(dispatchM.arbOrder({ order = { 'Pins', 'Locks', 'Naked', 'Triggers' } }), '>'),
        'Disabled>Pins>Locks>Naked>AutoAmmo>MaxMP>Craft>HELM>Fishing>Chocobo>Triggers');
    check('NK10 the restore never duplicates a row', (function()
        local seen = 0;
        for _, nm in ipairs(dispatchM.arbOrder(nil)) do if nm == 'Naked' then seen = seen + 1; end end
        return seen;
    end)(), 1);
    -- The same law from the other end: Chocobo still lands LAST (it did when it
    -- was the new row), so the positional rule did not regress the append case.
    check('NK10b a missing bottom row still lands just above the floor',
        table.concat(dispatchM.arbOrder({ order = { 'Naked', 'Pins', 'Locks', 'AutoAmmo',
                                                    'MaxMP', 'Craft', 'HELM', 'Fishing', 'Triggers' } }), '>'),
        'Disabled>Naked>Pins>Locks>AutoAmmo>MaxMP>Craft>HELM>Fishing>Chocobo>Triggers');

    -- The pure resolve: Naked beats everything, and the rank list is the ONLY
    -- exception mechanism (this is the "naked except my pins" contract).
    local ord = dispatchM.arbOrder(nil);
    local floor = { Head = 'Idle Hat', Body = 'Idle Robe' };
    local wN, byN = dispatchM.arbResolve(
        { Naked = dispatchM.nakedClaim(), Pins = { Head = 'Pinned Crown' } }, ord, floor);
    check('NK11 Naked wins a pinned slot',       wN.Head, 'remove');
    check('NK11b attributed to Naked',           byN.Head, 'Naked');
    check('NK11c and a floor-only slot',         wN.Body, 'remove');
    local pinTop = dispatchM.arbOrder({ order = { 'Pins', 'Naked', 'Locks', 'AutoAmmo', 'MaxMP',
                                                  'Craft', 'HELM', 'Fishing', 'Chocobo', 'Triggers' } });
    local wP, byP = dispatchM.arbResolve(
        { Naked = dispatchM.nakedClaim(), Pins = { Head = 'Pinned Crown' } }, pinTop, floor);
    check('NK12 drag Pins above Naked -> naked EXCEPT the pin', wP.Head, 'Pinned Crown');
    check('NK12b attributed to Pins',                           byP.Head, 'Pins');
    check('NK12c every other slot is still stripped',           wP.Body, 'remove');
    local lockTop = dispatchM.arbOrder({ order = { 'Locks', 'Naked', 'Pins', 'AutoAmmo', 'MaxMP',
                                                   'Craft', 'HELM', 'Fishing', 'Chocobo', 'Triggers' } });
    local wL = dispatchM.arbResolve(
        { Naked = dispatchM.nakedClaim(), Locks = dispatchM.arbLockClaim({ 'Head' }) }, lockTop, floor);
    check('NK13 drag Locks above Naked -> a locked slot keeps what it wears',
        wL.Head, dispatchM.LOCK_HELD);

    -- Woven MaxMP stands down for free: registering the claim is the whole fix.
    local ceded = dispatchM.arbCededAbove({ Naked = dispatchM.nakedClaim() }, ord, 'MaxMP');
    local nCede = 0;
    for _, who in pairs(ceded) do if who == 'Naked' then nCede = nCede + 1; end end
    check('NK14 MaxMP cedes all 16 slots to Naked (lowercase keys)', nCede, 16);
    check('NK14b including the Ammo slot it would otherwise battery', ceded['ammo'], 'Naked');

    -- The pinReserved void. A hold placed on behalf of a claimant Naked outranks
    -- is void; one placed on behalf of a claimant that outranks Naked stands.
    check('NK15 Naked above Pins voids the pin reservation',
        dispatchM.nakedVoidsPinReserve({ Naked = 1, Pins = 2 }), true);
    check('NK16 Pins above Naked keeps it',
        dispatchM.nakedVoidsPinReserve({ Naked = 3, Pins = 1 }), false);
    check('NK17 no Naked row -> nothing is voided',
        dispatchM.nakedVoidsPinReserve({ Pins = 1 }), false);
    check('NK17b a bad rank table never throws',
        dispatchM.nakedVoidsPinReserve(nil), false);

    -- THE LIVE EQUIP LAYER. The claim has to survive equipResolved's five post
    -- passes intact -- an all-'remove' table is an input none of them were
    -- written for.
    local savedAC = AshitaCore;
    AshitaCore = nil;                                   -- wornItemName -> nil
    for k in pairs(dispatchM.locks) do dispatchM.locks[k] = nil; end
    local _, wNak = dispatchM._equipResolved(dispatchM.nakedClaim(), {});
    local kept = 0;
    for _, v in pairs(wNak) do if v == 'remove' then kept = kept + 1; end end
    check('NK18 all 16 removes survive the post-passes', kept, 16);
    -- Locked + punching through (Naked ranks above Locks by default).
    dispatchM.setLock('all', true);
    local _, wPunch = dispatchM._equipResolved(dispatchM.nakedClaim(), {}, false);
    local kept2 = 0;
    for _, v in pairs(wPunch) do if v == 'remove' then kept2 = kept2 + 1; end end
    check('NK19 punch-through keeps all 16 even with every slot locked', kept2, 16);
    -- ...and respecting locks (the "drag Locks above Naked" composition) strips them.
    local _, wStop = dispatchM._equipResolved(dispatchM.nakedClaim(), {}, true);
    check('NK20 respecting locks, a locked slot is left alone', wStop.Head, nil);
    for k in pairs(dispatchM.locks) do dispatchM.locks[k] = nil; end

    -- The craft Sub-vs-Main guard DOES run over the naked table (it rides the
    -- shared ctx, which carries craftMainGuard whenever craft is armed). It is
    -- harmless only because 'remove' resolves to no gear record -- so pin that,
    -- or the day the guard learns the literal, naked silently stops taking your
    -- weapon off while a craft Sub is armed.
    local askedWith = nil;
    local _, wGuard = dispatchM._equipResolved(dispatchM.nakedClaim(),
        { craftMainGuard = function(mainName) askedWith = mainName; return true; end });
    check('NK21 the guard IS consulted on the naked table', askedWith, 'remove');
    check('NK21b and a guard that holds would keep the weapon on', wGuard.Main, nil);
    -- What actually saves us is that 'remove' is not a gear record, so the real
    -- guard's early-out fires. Pin the fact itself, not the accident.
    check('NK21c "remove" resolves to no gear record (why the real guard returns false)',
        type(utils.resolveGearName('remove')) == 'table', false);
    local _, wGuard2 = dispatchM._equipResolved(dispatchM.nakedClaim(),
        { craftMainGuard = function(mainName)
              return type(utils.resolveGearName(mainName)) == 'table';   -- the real guard's early-out
          end });
    check('NK21d so Main comes off even with a craft Sub armed', wGuard2.Main, 'remove');
    AshitaCore = savedAC;

    -- /dl why: sixteen identical winner lines would bury everything else it says,
    -- so a whole-sweep Naked collapses to one line -- naming who it beat.
    local why = table.concat(dispatchM.arbWhyLines(
        { Naked = dispatchM.nakedClaim(), Pins = { Head = 'Pinned Crown' } }, ord, floor), '\n');
    check('NK22 /dl why collapses the sweep into ONE line',
        select(2, why:gsub('NAKED %(rank 2%)', '')), 1);
    check('NK22b it counts the slots',   why:find('holds 16 slots empty', 1, true) ~= nil, true);
    check('NK22c and names who it beat', why:find('over Pins (rank 3)', 1, true) ~= nil, true);
    check('NK22d no per-slot Naked line survives', why:find('Head: Naked', 1, true), nil);

    -- The command tokens. dispatch's handler only registers inside engineActive(),
    -- which is false headlessly, so the whitelist cannot be driven -- pin it as
    -- SOURCE instead (the v46 trap: a subcommand missing from the whitelist
    -- returns in silence and looks like the command does not exist).
    local src = (function() local f = io.open('dispatch.lua', 'r'); local d = f:read('*a'); f:close(); return d; end)();
    local wl = src:match("\n%s*if sub ~= 'mode'[^\n]*\n");
    check('NK23 the command whitelist is findable', wl ~= nil, true);
    check('NK23b naked is whitelisted', wl and wl:find("sub ~= 'naked'", 1, true) ~= nil, true);
    check('NK23c dress is whitelisted',  wl and wl:find("sub ~= 'dress'", 1, true) ~= nil, true);
    check('NK24 the strip flag is carried across a self-swap, not reset',
        src:find('M.nakedArmed = (M.nakedArmed == true);', 1, true) ~= nil, true);

    -- arbwatch's headless fallback is DEAD whenever dispatch loads -- which is
    -- both Lua states and every other AB check -- so a drifting mirror ships
    -- green. Force the branch by hiding dispatch from the require.
    local savedDsp = package.loaded['dlac\\dispatch'];
    package.loaded['dlac\\dispatch'] = nil;
    local awNo = dofile('feature/arbwatch.lua');
    package.loaded['dlac\\dispatch'] = savedDsp;
    check('NK25 the no-dispatch fallback agrees on the default order',
        table.concat(awNo.defaultOrder(), '>'), table.concat(def, '>'));
    check('NK25b and on the positional restore',
        table.concat(awNo.sanitize({ order = { 'Pins', 'Locks', 'AutoAmmo', 'MaxMP',
                                               'Craft', 'HELM', 'Fishing', 'Chocobo', 'Triggers' } }), '>'),
        table.concat(dispatchM.arbOrder({ order = { 'Pins', 'Locks', 'AutoAmmo', 'MaxMP',
                                               'Craft', 'HELM', 'Fishing', 'Chocobo', 'Triggers' } }), '>'));

    -- NK26. END TO END through the REAL M.dispatch.
    --
    -- Worth its own note: until this check, M.dispatch was called ZERO times by
    -- the suite -- every other test drives a pure seam under it. So the wiring
    -- BETWEEN the seams (the bail guard, the claims table, the rank walk, the
    -- apply closure) was covered by nothing, and a local that fell out of scope
    -- would not be an error in Lua -- it would silently become a nil GLOBAL and
    -- the strip would just not happen. Naked is the cheapest possible driver for
    -- it: with the flag on and NOTHING else armed -- no triggers, no pins, no
    -- hobby, no ammo -- a bare dispatch must still produce all 16 removes, which
    -- is exactly the path the bail guard has to let through.
    local savedPlayer, savedFunc, savedState = TEST_PLAYER, rawget(_G, 'gFunc'), rawget(_G, 'gState');
    TEST_PLAYER = { MainJob = 'WHM', MainJobLevel = 75, SubJob = 'BLM', SubJobLevel = 37,
                    MainJobSync = 75, SubJobSync = 37, Status = 'Idle', IsMoving = false };
    local wrote = {};
    _G.gFunc  = { EquipSet = function(t) for k, v in pairs(t or {}) do wrote[k] = v; end end };
    _G.gState = { CurrentCall = 'N/A', Disabled = {} };
    dispatchM.nakedArmed = true;
    local okDisp, dispErr = pcall(dispatchM.dispatch, 'Default');
    check('NK26 a bare Default dispatch with only naked armed does not throw', okDisp, true);
    if not okDisp then print('NK26 error: ' .. tostring(dispErr)); end
    local nWrote, allRm = 0, true;
    for _, v in pairs(wrote) do nWrote = nWrote + 1; if v ~= 'remove' then allRm = false; end end
    check('NK26b it reaches the equip door with all 16 slots', nWrote, 16);
    check('NK26c every one of them is an unequip', allRm, true);
    check('NK26d proper case survives the whole path', wrote.Ring1, 'remove');
    -- A local that escaped its block would show up here as a nil-valued global
    -- turned real -- the failure mode the check above cannot see on its own.
    local leaked = nil;
    for _, nm in ipairs({ 'nakedOn', 'nEquip', 'nSig', 'rankOf', 'claims', 'nakedSlots' }) do
        if rawget(_G, nm) ~= nil then leaked = nm; break; end
    end
    check('NK26e no dispatch local leaked to the globals', leaked, nil);
    -- ...and with the flag OFF the same bare dispatch writes nothing at all.
    dispatchM.nakedArmed = false;
    wrote = {};
    pcall(dispatchM.dispatch, 'Default');
    check('NK26f released, a bare dispatch writes nothing', next(wrote), nil);

    -- NK27. The __naked mirror, through the REAL saveModeState onto disk. It must
    -- be written even when nothing changed: an early return there strands a stale
    -- mirror -- quit the client while naked and the next launch is genuinely
    -- dressed, but the file still says true, so the GUI draws the red NAKED button
    -- and clicking it (setNaked(false) on an already-false flag) would write
    -- nothing and never clear it.
    dispatchM._charDirOverride = 'tests' .. string.char(92);
    local function readMirror()
        local f = io.open('tests' .. string.char(92) .. 'modestate.lua', 'r');
        if f == nil then return nil; end
        local d = f:read('*a'); f:close(); return d;
    end
    os.remove('tests' .. string.char(92) .. 'modestate.lua');
    dispatchM.nakedArmed = false;
    dispatchM.setNaked(false);                                  -- no change at all
    local m0 = readMirror();
    check('NK27 setNaked writes the mirror even when nothing changed', m0 ~= nil, true);
    check('NK27b and it reads false', m0 and m0:find('["__naked"] = false', 1, true) ~= nil, true);
    dispatchM.setNaked(true);
    check('NK27c arming flips it to true',
        (readMirror() or ''):find('["__naked"] = true', 1, true) ~= nil, true);
    check('NK27d the flag lives OUTSIDE M.modes (no collision with a user Mode)',
        dispatchM.modes['naked'], nil);

    -- NK28. THE DISARM WATCH -- the relog guard the ADR calls the worst possible
    -- outcome to get wrong, plus the job-change drop (Henrik, 07-25). M.nakedArmed
    -- rides across a relog on its own (an Ashita addon survives a logout, and LAC
    -- never clears package.loaded), so this watch is what actually clears it.
    check('NK28 same job, in the world -> stays armed', dispatchM.nakedWorldWatch(7, 7), nil);
    check('NK28b and the flag is untouched',    dispatchM.nakedOn(), true);
    check('NK28c job 0 (character select) disarms', dispatchM.nakedWorldWatch(0, 7), 'world');
    check('NK28d you come back dressed',        dispatchM.nakedOn(), false);
    check('NK28e the mirror follows it down',
        (readMirror() or ''):find('["__naked"] = false', 1, true) ~= nil, true);
    dispatchM.setNaked(true);
    check('NK28f a nil job read disarms too',   dispatchM.nakedWorldWatch(nil, 7), 'world');
    dispatchM.setNaked(true);
    check('NK28g a JOB CHANGE disarms',         dispatchM.nakedWorldWatch(3, 7), 'job');
    check('NK28h ...and dresses you',           dispatchM.nakedOn(), false);
    -- The first in-world read of a session has no previous job to compare
    -- against; latching it must not read as a change and strip you at login.
    dispatchM.setNaked(true);
    check('NK28i the first job latch is not a change', dispatchM.nakedWorldWatch(7, nil), nil);
    check('NK28j nor is coming back from character select',
        dispatchM.nakedWorldWatch(7, 0), nil);
    check('NK28k still armed through both',     dispatchM.nakedOn(), true);
    check('NK28l it only ever CLEARS, never arms', (function()
        dispatchM.nakedWorldWatch(0, 7);                     -- disarm
        return dispatchM.nakedWorldWatch(0, 7) == nil and dispatchM.nakedOn() == false;
    end)(), true);
    -- NK29. THE LOCKSTYLE REFUSAL, on the door that actually runs.
    --
    -- lockstyleapply freezes every slot the box does not name to the WORN id --
    -- which is 0 while stripped, and style 0 renders the slot EMPTY. The server
    -- keeps styles per slot, so that outlives /dl dress, and because a style
    -- survives having no armor the player never sees it happen.
    --
    -- The refusal must sit in feature/lockstyle._applyDirect, NOT only in the
    -- engine's apply half: _applyDirect is the addon-resident executor that the
    -- GUI Apply button, the native typed handler and every SCRIPTED apply (town
    -- transitions, OnLoad restore, keep-on-subjob) funnel into -- and those last
    -- three fire with NO user action, so a naked player zoning into town would
    -- otherwise style themselves permanently bare.
    (function()
        local lsN = dofile('feature/lockstyle.lua');
        check('NK29 lockstyle exposes the naked read', type(lsN._nakedArmed), 'function');
        local applied = 0;
        local savedCap = lsN._capNote;
        local notes = {};
        lsN._capNote = function(t) notes[#notes + 1] = tostring(t); end
        -- Stand in for the naked read (the real one asks dispatch natively, or the
        -- __naked mirror in legacy -- neither is reachable headless).
        local armed = true;
        lsN._nakedArmed = function() return armed; end
        -- Re-point the module's own reference so _applyDirect sees the stub: the
        -- upvalue is a file-local, so the test drives the exported seam instead.
        local okRefuse = pcall(lsN._applyDirect, 1);
        check('NK29b applying while naked does not throw', okRefuse, true);
        local refused = false;
        for _, n in ipairs(notes) do if n:find('naked', 1, true) then refused = true; end end
        check('NK29c ...and is recorded as a refusal', refused, true);
        lsN._capNote = savedCap;
    end)();

    os.remove('tests' .. string.char(92) .. 'modestate.lua');
    dispatchM._charDirOverride = nil;

    TEST_PLAYER = savedPlayer;
    _G.gFunc, _G.gState = savedFunc, savedState;
    dispatchM.nakedArmed = false;
end)();

-- ---------------------------------------------------------------------------
-- AB. arbwatch -- the ADDON-SIDE writer of the arbstate rank Statefile (ADR
--     0012, step 2 / issue #49). The engine's read side is AR* above; these pin
--     the WRITER's pure seams: the default/sanitize reuse the engine's one
--     truth, serialize round-trips through arbOrder, and moveClaimant encodes
--     the drag rules (only the Triggers floor refuses the drag and stays last;
--     every other row -- claimants AND the Locks veto (step 3) -- moves freely).
-- ---------------------------------------------------------------------------
(function()
    local aw = dofile('feature/arbwatch.lua');
    check('AB0 arbwatch loads', type(aw), 'table');

    -- Default + sanitize delegate to the engine (one vocabulary, no drift).
    check('AB1 default order matches the engine default',
        table.concat(aw.defaultOrder(), '>'), 'Disabled>Naked>Pins>Locks>AutoAmmo>MaxMP>Craft>HELM>Fishing>Chocobo>Triggers');
    check('AB1b defaultOrder is a fresh copy (mutating it does not stick)',
        (function() local d = aw.defaultOrder(); d[1] = 'X'; return aw.defaultOrder()[1]; end)(), 'Disabled');
    check('AB2 sanitize nil -> default',
        table.concat(aw.sanitize(nil), '>'), 'Disabled>Naked>Pins>Locks>AutoAmmo>MaxMP>Craft>HELM>Fishing>Chocobo>Triggers');
    check('AB2b sanitize drops unknown, restores missing at its default position',
        table.concat(aw.sanitize({ order = { 'Fishing', 'Nonsense', 'Pins' } }), '>'),
        'Disabled>Naked>Locks>AutoAmmo>MaxMP>Craft>HELM>Fishing>Pins>Chocobo>Triggers');

    -- serialize -> the engine's file shape; round-trips through arbOrder.
    local txt = aw.serialize({ 'MaxMP', 'AutoAmmo', 'Pins', 'Locks', 'Craft', 'HELM', 'Fishing', 'Triggers' });
    check('AB3 serialize is a return { order = {...} } file',
        txt:match('^return { order = {') ~= nil, true);
    local chunk = (loadstring or load)(txt);
    check('AB3b serialized file parses', type(chunk), 'function');
    local roundtrip = dispatchM.arbOrder(chunk());
    check('AB3c serialize -> arbOrder round-trips a valid reorder',
        table.concat(roundtrip, '>'),
        'Disabled>Naked>MaxMP>AutoAmmo>Pins>Locks>Craft>HELM>Fishing>Chocobo>Triggers');
    check('AB3d serialize skips non-string / empty entries',
        aw.serialize({ 'Pins', '', 42, 'Triggers' }), 'return { order = { "Pins", "Triggers" } }\n');

    -- moveClaimant: the step-2 drag rules, pure.
    -- Indices are 1-based over the default order, which since v129 (ADR 0024)
    -- opens with the Disabled ceiling: Disabled Naked Pins Locks AutoAmmo MaxMP
    -- Craft HELM Fishing Chocobo Triggers.
    local def = aw.defaultOrder();
    check('AB4 a claimant moves up one (AutoAmmo #5 -> #4, crossing the Locks veto)',
        table.concat(aw.moveClaimant(def, 5, -1), '>'),
        'Disabled>Naked>Pins>AutoAmmo>Locks>MaxMP>Craft>HELM>Fishing>Chocobo>Triggers');
    check('AB4b a claimant moves down one (AutoAmmo #5 -> #6)',
        table.concat(aw.moveClaimant(def, 5, 1), '>'),
        'Disabled>Naked>Pins>Locks>MaxMP>AutoAmmo>Craft>HELM>Fishing>Chocobo>Triggers');
    check('AB4c the input order is not mutated', table.concat(def, '>'), 'Disabled>Naked>Pins>Locks>AutoAmmo>MaxMP>Craft>HELM>Fishing>Chocobo>Triggers');
    -- Step 3: the Locks veto row now DRAGS (only the Triggers floor is fixed).
    check('AB5 Locks drags down one (#4 -> #5, under AutoAmmo)',
        table.concat(aw.moveClaimant(def, 4, 1), '>'),
        'Disabled>Naked>Pins>AutoAmmo>Locks>MaxMP>Craft>HELM>Fishing>Chocobo>Triggers');
    check('AB5a Locks drags up one, over Pins (Naked still above it)',
        table.concat(aw.moveClaimant(def, 4, -1), '>'),
        'Disabled>Naked>Locks>Pins>AutoAmmo>MaxMP>Craft>HELM>Fishing>Chocobo>Triggers');
    check('AB5b Triggers refuses the drag (the floor)', aw.moveClaimant(def, 11, -1), nil);
    check('AB6 the floor-adjacent claimant (Chocobo #10) cannot move down into the Triggers floor (stays last)',
        aw.moveClaimant(def, 10, 1), nil);
    check('AB6b Fishing CAN move up (HELM #8 <-> Fishing #9)',
        table.concat(aw.moveClaimant(def, 9, -1), '>'),
        'Disabled>Naked>Pins>Locks>AutoAmmo>MaxMP>Craft>Fishing>HELM>Chocobo>Triggers');
    -- Naked is an ORDINARY draggable row: "naked except my pins" is a drag, not
    -- a code path, so the day it becomes fixed the feature loses its escape hatch.
    check('AB6c Naked drags down (Pins takes the top -- naked except pins)',
        table.concat(aw.moveClaimant(def, 2, 1), '>'),
        'Disabled>Pins>Naked>Locks>AutoAmmo>MaxMP>Craft>HELM>Fishing>Chocobo>Triggers');
    check('AB6d Naked is not a FIXED row', aw.FIXED['Naked'], nil);
    check('AB7 out-of-range / bad args are nil, never a throw',
        aw.moveClaimant(def, 1, -1) == nil and aw.moveClaimant(def, 0, 1) == nil
        and aw.moveClaimant(def, 3, 0) == nil and aw.moveClaimant(nil, 1, 1) == nil, true);
end)();

-- ---------------------------------------------------------------------------
-- GS. Groups auto-import scanner (Item 1): the pure `scan(fileText) -> candidates, notes`
--     transform (groupscan.lua). Text-scans a LuaAshitacast file for top-level
--     `[local] NAME = T?{...}` blocks and surfaces every group-shaped table (a flat string
--     array, or a container of them) as an import candidate, skipping gear sets / settings.
--     Reuses groupimport's sandbox eval + flat-list heuristic; hostile blocks error safely.
-- ---------------------------------------------------------------------------
package.loaded['dlac\\gear\\groupimport'] = dofile('gear/groupimport.lua');
(function()
    local gscan = dofile('gear/groupscan.lua');
    check('GS0 module loads',  type(gscan),      'table');
    check('GS0b scan exported', type(gscan.scan), 'function');

    local sample = [[
-- my BLU setup { this comment has an unbalanced brace
local Settings = { TpVariant = 1, ATKCAP = false }
local IdleVariantTable = { [1] = 'Refresh/Regen', [2] = 'Learn' }
local BlueSpells = {
    STR_DEX = T{'Foot Kick', 'Wild Oats', 'Queasyshroom'},
    VIT     = {'Cannonball', 'Tail Slap'},
    Debuff  = T{'Filamented Hold',},
}
local sets = {
    ['Idle'] = { Ammo = 'Tiphia Sting', Head = 'Mirage Keffiyeh +1' },
    ['TP']   = { Main = 'Maple Sugar', Sub = { Name = 'X', Augment = {'a'} } },
}
local Evil = { bad = os.execute('rm -rf /') }
]];
    local cands, notes = gscan.scan(sample);
    local byName = {};
    for _, c in ipairs(cands) do byName[c.name] = c.members; end

    -- a container of flat lists expands to one candidate per inner key
    check('GS1 BlueSpells expands to its inner groups',
        (byName.STR_DEX ~= nil and byName.VIT ~= nil and byName.Debuff ~= nil), true);
    check('GS1b STR_DEX member count',  byName.STR_DEX and #byName.STR_DEX, 3);
    check('GS1c member order preserved', byName.STR_DEX and byName.STR_DEX[1], 'Foot Kick');
    check('GS1d single-elem + trailing comma', byName.Debuff and #byName.Debuff, 1);
    check('GS1e plain {...} parses too (no T)',  byName.VIT and #byName.VIT, 2);
    -- the container name itself is NOT a candidate (only its group-shaped children are)
    check('GS2 container name not a candidate', byName.BlueSpells, nil);
    -- gear sets are skipped, not mistaken for groups
    check('GS3 gear-set keys not candidates', (byName.Idle == nil and byName.TP == nil), true);
    -- a flat variant/config table IS surfaced (the player deselects it in the preview)
    check('GS4 flat variant table surfaced', byName.IdleVariantTable ~= nil, true);

    -- hostile / unreadable blocks are skipped SAFELY (os is nil in the sandbox -> eval errors,
    -- os.execute never runs) and named in the notes; gear sets are noted too.
    local noteText = table.concat(notes, ' | ');
    check('GS5 hostile os.execute block skipped safely', string.find(noteText, 'Evil', 1, true) ~= nil, true);
    check('GS6 gear-set block noted',                    string.find(noteText, 'sets', 1, true) ~= nil, true);

    -- the candidates feed groupimport.classify / apply verbatim (the reuse contract)
    local gimp = package.loaded['dlac\\gear\\groupimport'];
    local groupsMap = {};
    for _, c in ipairs(cands) do groupsMap[c.name] = c.members; end
    local _, overwritten = gimp.classify(groupsMap, { STR_DEX = { 'old' } });
    check('GS7 classify sees the STR_DEX collision',
        (function() for _, n in ipairs(overwritten) do if n == 'STR_DEX' then return true; end end return false; end)(), true);

    -- duplicate names collapse to one candidate (first spelling wins)
    local dup = gscan.scan("local A = T{'x'}\nlocal A = T{'y'}\n");
    check('GS8 duplicate names dedup to one', #dup, 1);
    -- nil / non-string input is safe
    local c9 = gscan.scan(nil);
    check('GS9 nil input -> no candidates', #c9, 0);
end)();

-- ---------------------------------------------------------------------------
-- LS. Level-sync settle hold (dispatch.syncSettleStep + the equipResolved
--     ctx.syncHold branch, v56): a level jump on the SAME job arms a short
--     (SYNC_SETTLE_S) weapon hold -- an Incursion boss pop re-syncing the
--     party must not swap
--     Main mid-transition and zero saved TP. Job changes and first reads adopt
--     instantly; not-ready readings (level 0, job '?'/'NON') never touch the
--     tracker. While the hold is live, ONLY Main/Sub/Range are kept as worn --
--     armor and Ammo (no TP cost) dispatch normally.
-- ---------------------------------------------------------------------------
(function()
    check('LS0 pure rule exported',    type(dispatchM.syncSettleStep), 'function');
    check('LS0b live consult exported', type(dispatchM.syncSettleHold), 'function');
    local W = dispatchM.SYNC_SETTLE_S;
    check('LS0c settle window is a positive number', type(W) == 'number' and W > 0, true);

    local st = { job = nil, lv = nil, holdUntil = 0 };
    check('LS1 first read adopts, no hold',   dispatchM.syncSettleStep(st, 'WAR', 75, 100.0), false);
    check('LS2 stable level stays free',      dispatchM.syncSettleStep(st, 'WAR', 75, 101.0), false);
    check('LS3 sync lands -> hold arms',      dispatchM.syncSettleStep(st, 'WAR', 60, 102.0), true);
    check('LS4 still holding inside window',  dispatchM.syncSettleStep(st, 'WAR', 60, 102.0 + W - 0.1), true);
    check('LS5 window passed -> released',    dispatchM.syncSettleStep(st, 'WAR', 60, 102.0 + W), false);
    -- a staged transition (server re-syncs in steps) keeps extending the window
    check('LS6 second sync re-arms',          dispatchM.syncSettleStep(st, 'WAR', 50, 110.0), true);
    check('LS6b next stage extends',          dispatchM.syncSettleStep(st, 'WAR', 55, 111.0), true);
    check('LS6c still live past the FIRST deadline', dispatchM.syncSettleStep(st, 'WAR', 55, 110.0 + W + 0.5), true);
    -- job change: adopt instantly AND drop any live hold (new job must re-gear now)
    dispatchM.syncSettleStep(st, 'WAR', 40, 120.0);   -- arm
    check('LS7 job change adopts instantly',  dispatchM.syncSettleStep(st, 'NIN', 37, 120.5), false);
    check('LS7b job change drops the hold',   st.holdUntil, 0);
    -- not-ready readings leave the tracker (and a live hold) untouched
    dispatchM.syncSettleStep(st, 'NIN', 30, 130.0);   -- arm
    check('LS8 level 0 ignored (hold stays)',  dispatchM.syncSettleStep(st, nil,  0,  130.5), true);
    check('LS8b NON job ignored (hold stays)', dispatchM.syncSettleStep(st, 'NON', 75, 130.6), true);
    check('LS8c "?" job ignored (hold stays)', dispatchM.syncSettleStep(st, '?',  75, 130.7), true);
    check('LS8d junk never adopted into the tracker', st.lv, 30);

    -- equipResolved rides ctx.syncHold: weapons held as worn, the rest dispatches
    local lsSet = { Main = 'Joyeuse', Sub = 'GenbusShield', Range = 'Power Bow',
                    Ammo = 'Tiphia Sting', Body = 'Gaudy Harness' };
    local lsNote, lsTbl = dispatchM._equipResolved(lsSet, { syncHold = true });
    check('LS9 Main held',   lsTbl.Main,  nil);
    check('LS10 Sub held',   lsTbl.Sub,   nil);
    check('LS11 Range held', lsTbl.Range, nil);
    check('LS12 Ammo NOT held (no TP cost)', lsTbl.Ammo, 'Tiphia Sting');
    check('LS13 armor unaffected',           lsTbl.Body, 'Gaudy Harness');
    check('LS14 the hold is traced for /dl why', string.find(lsNote, 'SYNC-HOLD', 1, true) ~= nil, true);
    local _, lsTbl2 = dispatchM._equipResolved(lsSet, { syncHold = false });
    check('LS15 no hold: weapons dispatch',  lsTbl2.Main, 'Joyeuse');
    local _, lsTbl3 = dispatchM._equipResolved(lsSet, {});
    check('LS16 absent flag: weapons dispatch (old ctx shape)', lsTbl3.Main, 'Joyeuse');

    -- ROOT CAUSE pin: a level-driven VIRTUAL in a weapon slot must be held
    -- UNRESOLVED -- resolving it at the transient level IS the field bug. This
    -- kills the "refactor the hold into a post-pass on final names" mutant:
    -- only the branch's position ABOVE the dlac: branch guarantees it.
    local lsV = { Main = 'dlac:AutoStaff|Fallback Staff', Sub = 'dlac:AutoGrip|Fallback Grip' };
    local lsVNote, lsVTbl = dispatchM._equipResolved(lsV, { syncHold = true });
    check('LS17 virtual Main held unresolved',  lsVTbl.Main, nil);
    check('LS17b virtual Sub held unresolved',  lsVTbl.Sub, nil);
    check('LS18 the hold is what got traced',   string.find(lsVNote, 'SYNC-HOLD', 1, true) ~= nil, true);
    check('LS18b no virtual resolution leaked', string.find(lsVNote, 'AutoStaff', 1, true), nil);
    local _, lsVFree = dispatchM._equipResolved(lsV, {});
    check('LS19 no hold: virtual resolves (fallback rides)', lsVFree.Main ~= nil, true);

    -- Sync-hold companion rule (ADR 0010): with Range held, a stat-stick Ammo
    -- whose RSlot reserves Range must hold too -- otherwise it lands and the
    -- SERVER strips the worn ranged weapon mid-window. Fired ammo (no Range
    -- bit, like LS12's recordless Tiphia Sting) keeps dispatching.
    local gearLS = package.loaded['dlac\\gear'];
    gearLS.NameToObject['Aureole'] = { Name = 'Aureole', RSlot = 0x0004 + 0x0008, Level = 70 };
    local lsTrink = { Range = 'Power Bow', Ammo = 'Aureole', Body = 'Gaudy Harness' };
    local lsTNote, lsTTbl = dispatchM._equipResolved(lsTrink, { syncHold = true });
    check('LS20 Range held',                    lsTTbl.Range, nil);
    check('LS20b Range-reserving Ammo held too', lsTTbl.Ammo, nil);
    check('LS20c armor still dispatches',        lsTTbl.Body, 'Gaudy Harness');
    check('LS20d companion hold traced',
        string.find(lsTNote, 'reserves Range', 1, true) ~= nil, true);
    -- no hold: ADR 0010 behavior unchanged (trinket vs ranged decided by Level)
    local _, lsTFree = dispatchM._equipResolved(lsTrink, {});
    check('LS21 no hold: trinket rule decides (higher Level wins)', lsTFree.Ammo, 'Aureole');
    check('LS21b no hold: the lower-Level ranged weapon dropped',   lsTFree.Range, nil);
    gearLS.NameToObject['Aureole'] = nil;

    -- The LIVE consult: the gData glue (field names, tonumber, pcall) and the
    -- shared tracker on M. Deterministic: arming and the truth test share one
    -- os.clock() read inside each call; the job change zeroes holdUntil.
    TEST_PLAYER = { MainJob = 'WAR', SubJob = 'NIN', MainJobSync = 75, SubJobSync = 37 };
    dispatchM.syncSettleHold();                       -- first good read adopts silently
    check('LS22 live: stable reading, no hold',   dispatchM.syncSettleHold(), false);
    TEST_PLAYER.MainJobSync = 60;                     -- a level sync lands
    check('LS23 live: sync jump arms the hold',   dispatchM.syncSettleHold(), true);
    check('LS23b live: tracker parked on M (survives self-swap)',
        type(dispatchM._syncSt) == 'table' and dispatchM._syncSt.lv, 60);
    TEST_PLAYER.MainJob = 'NIN';                      -- job change adopts instantly
    check('LS24 live: job change drops the hold', dispatchM.syncSettleHold(), false);
    TEST_PLAYER = nil;                                -- not-ready read: tracker untouched
    check('LS25 live: nil player never arms',     dispatchM.syncSettleHold(), false);

    -- The Default gate (M.defaultGateHold): what the HandleEquipEvent wrap
    -- consults AT CALL TIME. Pet hold first, then the sync settle hold.
    TEST_PLAYER = { MainJob = 'BLM', SubJob = 'WHM', MainJobSync = 37, SubJobSync = 18 };
    dispatchM.syncSettleHold();                       -- job differs from LS24's NIN: adopt, no hold
    check('LS26 gate: idle -> not held',          dispatchM.defaultGateHold(), false);
    _G.gState = { PetAction = { Completion = os.clock() + 5 } };
    check('LS27 gate: pet action in flight -> held', dispatchM.defaultGateHold(), true);
    _G.gState.PetAction = nil;
    TEST_PLAYER.MainJobSync = 30;                     -- a sync lands (same job BLM)
    check('LS28 gate: sync settling -> held',     dispatchM.defaultGateHold(), true);
    TEST_PLAYER.MainJob = 'WAR';                      -- job change releases
    check('LS29 gate: job change releases',       dispatchM.defaultGateHold(), false);
    _G.gState = nil;

    -- The wrap SHELL, driven for real: a fresh engine load with gFunc + a stub
    -- gState installs the thin shell (WRAP_GEN); HandleDefault is gated while
    -- the fresh module's tracker is armed, Precast always flows. Also pins the
    -- generational re-install: a v55-shaped pre-wrap (_dlacPetHold=true, no
    -- _dlacWrapGen) must be wrapped OVER, not skipped -- the hot-swap gap.
    local reached = nil;
    local stStub = {
        HandleEquipEvent = function(ev, style) reached = ev; end,
        _dlacPetHold = true,                          -- the v55 boolean is already set
    };
    _G.gFunc, _G.gState = {}, stStub;
    TEST_PLAYER = { MainJob = 'WAR', SubJob = 'NIN', MainJobSync = 75, SubJobSync = 37 };
    local freshM = dofile('dispatch.lua');
    check('LS30 shell installed OVER a v55-shaped wrap', stStub.HandleEquipEvent ~= nil
        and type(stStub._dlacWrapGen) == 'number', true);
    stStub.HandleEquipEvent('HandleDefault');         -- first pass adopts the level
    check('LS31 stable level: Default flows',     reached, 'HandleDefault');
    reached = nil;
    TEST_PLAYER.MainJobSync = 60;                     -- a sync lands
    stStub.HandleEquipEvent('HandleDefault');
    check('LS32 settling: Default gated',         reached, nil);
    stStub.HandleEquipEvent('HandlePrecast');
    check('LS33 settling: action events flow',    reached, 'HandlePrecast');
    freshM.SYNC_SETTLE_S = 0;                         -- release without sleeping
    reached = nil;
    TEST_PLAYER.MainJobSync = 50;                     -- re-arm under a 0s window
    stStub.HandleEquipEvent('HandleDefault');
    check('LS34 window over: Default flows again', reached, 'HandleDefault');
    _G.gFunc, _G.gState = nil, nil;
    TEST_PLAYER = nil;
end)();

-- ---------------------------------------------------------------------------
-- PL. paired-slot dynamic ladders (gearoptim.pairLadders) -- Ear/Ring pairs
--     ladder as one running TOP-2 walk so BOTH physical slots fill. Field case
--     (Henrik, 2026-07-17): under Cure Potency weights, Curates' Earring (30)
--     and Roundel Earring (73) both laddered onto Ear1 and Ear2 stayed empty --
--     the pair must wear both once both are owned. The scores here are the
--     caller's weighted scores at the build level; pairLadders is pure.
-- ---------------------------------------------------------------------------
(function()
    local optim = dofile('gear/gearoptim.lua');
    local function names(chain)
        local t = {};
        for _, c in ipairs(chain) do t[#t + 1] = tostring(c.name); end
        return table.concat(t, ',');
    end

    -- The field case: both earrings owned -> one per ear, not both on Ear1.
    local curates = { ref = 'C', name = "Curates' Earring", id = 1, level = 30, score = 30, copies = 1 };
    local roundel = { ref = 'R', name = 'Roundel Earring',  id = 2, level = 73, score = 50, copies = 1 };
    local c1, c2 = optim.pairLadders({ curates, roundel });
    check('PL1 field case: first ear keeps the early earring', names(c1), "Curates' Earring");
    check('PL2 field case: second ear gets the late earring',  names(c2), 'Roundel Earring');

    -- joint pins matching the chain tops (in either order -- the two physical
    -- slots are interchangeable) claim the chains untouched
    c1, c2 = optim.pairLadders({ curates, roundel }, { pins = { roundel, curates } });
    check('PL3 top pins claim chains untouched (1)', names(c1), "Curates' Earring");
    check('PL4 top pins claim chains untouched (2)', names(c2), 'Roundel Earring');

    -- a strictly-improving upgrade run ALTERNATES between the chains: at every
    -- level the two flattens together wear the best two owned pieces (the old
    -- shape put all four on slot 1 and starved slot 2 completely)
    local A = { ref = 'A', name = 'A', id = 11, level = 10, score = 5  };
    local B = { ref = 'B', name = 'B', id = 12, level = 20, score = 10 };
    local C = { ref = 'C', name = 'C', id = 13, level = 30, score = 12 };
    local D = { ref = 'D', name = 'D', id = 14, level = 40, score = 20 };
    c1, c2 = optim.pairLadders({ A, B, C, D });
    check('PL5 running top-2: chain 1', names(c1), 'A,C');
    check('PL6 running top-2: chain 2', names(c2), 'B,D');

    -- same-level pieces fill both slots at once
    local X = { ref = 'X', name = 'X', id = 51, level = 30, score = 20 };
    local Y = { ref = 'Y', name = 'Y', id = 52, level = 30, score = 15 };
    c1, c2 = optim.pairLadders({ Y, X });                     -- input order shuffled on purpose
    check('PL7 same-level pair fills both slots', names(c1) .. '|' .. names(c2), 'X|Y');

    -- a single copy never fills both slots ...
    local solo = { ref = 'S', name = 'Solo Ring', id = 21, level = 30, score = 40 };
    c1, c2 = optim.pairLadders({ solo });
    check('PL8 one copy -> one chain only', names(c1) .. '|' .. names(c2), 'Solo Ring|');

    -- ... but TWO owned copies do (Auto-build passes live owned counts)
    local twin = { ref = 'T', name = 'Twin Ring', id = 22, level = 30, score = 40, copies = 2 };
    c1, c2 = optim.pairLadders({ twin });
    check('PL9 two copies -> both chains', names(c1) .. '|' .. names(c2), 'Twin Ring|Twin Ring');

    -- same-NAME legacy duplicates are ONE physical item (optimizePicks' rule)
    local dupA = { ref = 'd1', name = "Jalzahn's Ring", id = 31, level = 50, score = 40 };
    local dupB = { ref = 'd2', name = "jalzahn's ring",           level = 50, score = 40 };
    c1, c2 = optim.pairLadders({ dupA, dupB });
    check('PL10 same-name duplicate fills one slot only', #c1 + #c2, 1);

    -- zero scorers are never kept (the seed-at-0 rule: no junk padding)
    c1, c2 = optim.pairLadders({ { ref = 'z', name = 'Junk', id = 41, level = 10, score = 0 } });
    check('PL11 zero score never padded', #c1 + #c2, 0);

    -- a leftover pin (not a chain top -- the cap optimizer preferred a lower
    -- piece) trims its chain like the single-slot ladder cap, and a single-copy
    -- pin is STRIPPED from the other chain -- leaving it would double-equip at
    -- the levels where both chains flatten to it
    c1, c2 = optim.pairLadders({ A, B, C, D }, { pins = { D, B } });
    check('PL12 leftover pin trims its chain',                 names(c1), 'A,B');
    check('PL13 single-copy pin stripped from the other chain', names(c2), 'D');
end)();

-- ---------------------------------------------------------------------------
-- LL. level-banded single-slot ladders (gearoptim.levelLadder) -- Auto-build
--     re-scores candidates at every band edge (adoption level + levelstats
--     thresholds) and emits between-level windows where value changes. Field
--     case (Henrik, 2026-07-19): Garrison Tunica +1's Refresh+1 dies past
--     Lv.50 -- its points must stop at 50 and the next body take over at 51.
--     Monotone slots must come back as the classic unranged chain (parity).
-- ---------------------------------------------------------------------------
(function()
    local optim = dofile('gear/gearoptim.lua');
    local function fmt(lad)
        local t = {};
        for _, e in ipairs(lad) do
            t[#t + 1] = tostring(e.ref) .. '[' .. tostring(e.minLevel or '') .. '-' .. tostring(e.maxLevel or '') .. ']';
        end
        return table.concat(t, ',');
    end
    local function ladder(items, scores, joint, cap)
        return optim.levelLadder(items, {
            cap = cap or 75,
            scoreAt = function(ref, L) return scores[ref](L); end,
            joint = joint,
        });
    end

    -- monotone upgrades: classic chain, zero windows -- today's output verbatim
    local lad = ladder(
        { { ref = 'A', level = 1 }, { ref = 'B', level = 20 } },
        { A = function() return 5; end, B = function() return 9; end });
    check('LL1 monotone slot keeps the classic unranged chain', fmt(lad), 'A[-],B[-]');

    -- THE tunica shape: A is worth 10 up to 50 then decays to 4; B (worth 6,
    -- wearable at 30) must own 51+ -- and A's window must CLOSE at 50 even
    -- though B's adoption level is lower than the handover level
    lad = ladder(
        { { ref = 'A', level = 20, breaks = { 51 } }, { ref = 'B', level = 30 } },
        { A = function(L) return (L < 51) and 10 or 4; end, B = function() return 6; end });
    check('LL2 decay closes the window and hands over', fmt(lad), 'A[-50],B[51-]');

    -- joint pick (set-level choice, per-item score irrelevant) trims exactly
    -- like the classic chain: lower rungs stay, output unranged (parity)
    lad = ladder(
        { { ref = 'A', level = 20 }, { ref = 'C', level = 40 } },
        { A = function() return 10; end, C = function() return 3; end }, 'C');
    check('LL3 joint trim stays classic', fmt(lad), 'A[-],C[-]');

    -- zero scorers are never kept (the seed-at-0 rule)
    lad = ladder({ { ref = 'Z', level = 10 } }, { Z = function() return 0; end });
    check('LL4 zero score never kept', fmt(lad), '');

    -- a `from` gainer can win, lose the middle, and win again: the SAME item
    -- appears twice with disjoint windows
    lad = ladder(
        { { ref = 'B', level = 10, breaks = { 40 } }, { ref = 'A', level = 30 } },
        { B = function(L) return (L < 40) and 2 or 9; end, A = function() return 5; end });
    check('LL5 regain emits the item twice with disjoint windows', fmt(lad), 'B[-29],A[30-39],B[40-]');

    -- a winner-less gap (everything scores 0 there) inherits the previous
    -- winner: unweighted stats still count, the slot is never bared
    lad = ladder(
        { { ref = 'A', level = 20, breaks = { 41 } }, { ref = 'B', level = 30, breaks = { 50 } } },
        { A = function(L) return (L < 41) and 10 or 0; end, B = function(L) return (L < 50) and 0 or 7; end });
    check('LL6 winner-less gap extends the previous winner', fmt(lad), 'A[-49],B[50-]');

    -- thresholds above the build cap are ignored: below it the tunica never
    -- decays, so the slot is a single classic entry
    lad = ladder(
        { { ref = 'A', level = 20, breaks = { 51 } }, { ref = 'B', level = 30 } },
        { A = function(L) return (L < 51) and 10 or 4; end, B = function() return 6; end },
        nil, 40);
    check('LL7 breaks beyond the cap are ignored', fmt(lad), 'A[-]');
end)();

-- ---------------------------------------------------------------------------
-- PLL. level-banded PAIR ladders (gearoptim.pairLevelLadders) -- the Ear/Ring
--      twin of levelLadder: at every band the pair wears the true top-2 by
--      score-at-that-level. Flat scores must reproduce pairLadders' chains
--      verbatim (PL5/6, PL12/13 parity); a decaying piece hands its slot over
--      at the breakpoint with a between-level window.
-- ---------------------------------------------------------------------------
(function()
    local optim = dofile('gear/gearoptim.lua');
    local function fmt(lad)
        local t = {};
        for _, e in ipairs(lad) do
            t[#t + 1] = tostring(e.ref) .. '[' .. tostring(e.minLevel or '') .. '-' .. tostring(e.maxLevel or '') .. ']';
        end
        return table.concat(t, ',');
    end
    local function pair(cands, scores, pins, cap)
        local cA, cB = optim.pairLevelLadders(cands, {
            cap = cap or 75,
            scoreAt = function(ref, L) return scores[ref](L); end,
            pins = pins,
        });
        return fmt(cA), fmt(cB);
    end
    local flat = {
        A = function() return 5; end,  B = function() return 10; end,
        C = function() return 12; end, D = function() return 20; end,
    };
    local A = { ref = 'A', name = 'A', id = 11, level = 10 };
    local B = { ref = 'B', name = 'B', id = 12, level = 20 };
    local C = { ref = 'C', name = 'C', id = 13, level = 30 };
    local D = { ref = 'D', name = 'D', id = 14, level = 40 };

    -- flat scores: byte-for-byte the classic running top-2 chains (PL5/6)
    local a, b = pair({ A, B, C, D }, flat);
    check('PLL1 flat scores keep pairLadders chains (1)', a, 'A[-],C[-]');
    check('PLL2 flat scores keep pairLadders chains (2)', b, 'B[-],D[-]');

    -- decay handover on a pair: E1 (Refresh-style, dies past 50) owns a slot to
    -- 50, then the SECOND-best remaining piece takes that slot with a window
    local E1 = { ref = 'E1', name = 'E1', id = 21, level = 20, breaks = { 51 } };
    local E2 = { ref = 'E2', name = 'E2', id = 22, level = 20 };
    local E3 = { ref = 'E3', name = 'E3', id = 23, level = 30 };
    a, b = pair({ E1, E2, E3 }, {
        E1 = function(L) return (L < 51) and 10 or 2; end,
        E2 = function() return 6; end,
        E3 = function() return 5; end,
    });
    check('PLL3 decaying piece hands its slot over at 51', a, 'E1[-50],E3[51-]');
    check('PLL4 partner slot undisturbed', b, 'E2[-]');

    -- one owned copy fills one slot; two copies fill both
    local S = { ref = 'S', name = 'Solo', id = 31, level = 30 };
    a, b = pair({ S }, { S = function() return 8; end });
    check('PLL5 one copy -> one chain only', a .. '|' .. b, 'S[-]|');
    local T = { ref = 'T', name = 'Twin', id = 32, level = 30, copies = 2 };
    a, b = pair({ T }, { T = function() return 8; end });
    check('PLL6 two copies -> both chains', a .. '|' .. b, 'T[-]|T[-]');

    -- pin reconciliation parity (PL12/13): a leftover pin trims its chain, a
    -- single-copy pin is swept from the other chain
    a, b = pair({ A, B, C, D }, flat, { D, B });
    check('PLL7 leftover pin trims its chain',                  a, 'A[-],B[-]');
    check('PLL8 single-copy pin swept from the other chain',    b, 'D[-]');

    -- zero scorers are never kept
    a, b = pair({ A }, { A = function() return 0; end });
    check('PLL9 zero score never kept', a .. '|' .. b, '|');
end)();

-- ---------------------------------------------------------------------------
-- HELM: helmwatch state + parsers + the engine's dlac:AutoHelm overlay (v59)
-- -- docs/design/helm-gear.md. Idle-only is STRUCTURAL (the overlay is only
-- consulted on Default, same gate as craft); these cover resolution + rules.
-- ---------------------------------------------------------------------------
(function()
    local helmwatch = dofile('feature/helmwatch.lua');

    -- state rules (the craftwatch model: select does not enable; fishing is
    -- deliberately not a category -- it gets its own automation someday)
    check('H0 fresh state defaults to Harvesting (first-timer rule: an armed switch must never sit categoryless)',
                                           helmwatch.getGather(), 'Harvesting');
    helmwatch.selectGather('Mining');
    check('H1 selectGather sets active',   helmwatch.getGather(), 'Mining');
    check('H2 select does NOT enable',     helmwatch.isEnabled(), false);
    helmwatch.selectGather('logging');
    check('H3 lowercase tolerated',        helmwatch.getGather(), 'Logging');
    helmwatch.selectGather('Fishing');
    check('H4 fishing rejected',           helmwatch.getGather(), 'Logging');
    helmwatch.setEnabled(true);
    check('H5 switch turns on',            helmwatch.isEnabled(), true);
    helmwatch.setEnabled(false);
    check('H6 switch off',                 helmwatch.isEnabled(), false);

    -- category from NPC name + the 0x034 result-event detect. The event bytes
    -- are the REAL Ghelsba Outpost capture (2026-07-17, Mindie's swing that
    -- chopped an Arrowwood Log): ActIndex 319 @0x28, zone 140 @0x2A.
    check('H7 Mining Point -> Mining',     helmwatch.gatherFromNpcName('Mining Point'), 'Mining');
    check('H8 Harvesting Point',           helmwatch.gatherFromNpcName('Harvesting Point'), 'Harvesting');
    check('H9 unrelated npc -> nil',       helmwatch.gatherFromNpcName('Goblin Miner'), nil);
    check('H10 nil npc -> nil',            helmwatch.gatherFromNpcName(nil), nil);
    local evt = string.char(0x34, 0x1A, 0x8D, 0x06, 0x3F, 0xC1, 0x08, 0x01, 0xB0, 0x02, 0, 0)
        .. string.rep('\0', 28)
        .. string.char(0x3F, 0x01, 0x8C, 0x00, 0x64, 0x00, 0x08, 0x00, 0x8C, 0x00, 0x00, 0x00);
    check('H10b result-event npc index (real capture)', helmwatch.eventNpcIndex(evt), 319);
    check('H10c short packet -> nil',      helmwatch.eventNpcIndex('short'), nil);
    helmwatch.onEventNum(evt, function(i) return (i == 319) and 'Logging Point' or nil; end);
    check('H10d detection from result event',
        helmwatch.lastDetect ~= nil and helmwatch.lastDetect.gather or nil, 'Logging');
    helmwatch.onEventNum(evt, function(i) return 'Fantoccini'; end);   -- ordinary NPC event
    check('H10e non-Point event leaves detect alone',
        helmwatch.lastDetect ~= nil and helmwatch.lastDetect.gather or nil, 'Logging');

    -- 0x1A4 POINTS_ENTRY wire format (trove protocol): group@0x08 (19b) |
    -- label@0x1C (23b) | i32 value@0x34; CLEAR/END_LIST commits the stream.
    local function zi32(v) return string.char(v % 256, math.floor(v/256)%256, math.floor(v/65536)%256, math.floor(v/16777216)%256); end
    local function zfield(s, width) return s .. string.rep('\0', width - #s); end
    local function pointsEntry(group, label, value)
        return string.char(0xA4, 0, 0, 0) .. string.char(7) .. string.rep('\0', 3)
            .. zfield(group, 20) .. zfield(label, 24) .. zi32(value);
    end
    local endList = string.char(0xA4, 0, 0, 0) .. string.char(2) .. '\0';
    check('H11 entry consumed',  helmwatch.on1A4(pointsEntry('Ventures', 'Mining', 3200)), true);
    check('H12 no commit before END', helmwatch.pointsFor('Mining'), nil);
    helmwatch.on1A4(pointsEntry('Ventures', 'Harvesting', 150));
    helmwatch.on1A4(pointsEntry('Ventures', 'Dynamis', 999));
    check('H13 END commits stream', helmwatch.on1A4(endList), true);
    check('H14 exact label match',  helmwatch.pointsFor('Mining'), 3200);
    check('H15 second category',    helmwatch.pointsFor('Harvesting'), 150);
    check('H16 absent category',    helmwatch.pointsFor('Excavation'), nil);
    check('H17 pointsReady',        helmwatch.pointsReady(), true);

    -- !ventures reply parse -- format PINNED by field capture 2026-07-17:
    --   Mining: (Low) Ordelles Caves, (Mid) Garlaige Citadel [S], (High) Grauberg [S]
    local vg, vl = helmwatch.parseVentureLine(
        'Mining: (Low) Ordelles Caves, (Mid) Garlaige Citadel [S], (High) Grauberg [S]');
    check('H18 venture line category',  vg, 'Mining');
    check('H18b tier count',            vl ~= nil and #vl or 0, 3);
    check('H18c low tier',              vl ~= nil and vl[1], 'Low:  Ordelles Caves');
    check('H18d high tier keeps [S]',   vl ~= nil and vl[3], 'High: Grauberg [S]');
    local dg, dl = helmwatch.parseVentureLine('Harvesting: something the server changed');
    check('H19 drifted format keeps raw tail', dg, 'Harvesting');
    check('H19b drifted tail content',  dl ~= nil and dl[1], 'something the server changed');
    check('H20 party chatter -> nil',   helmwatch.parseVentureLine('do i go to M or go to J?'), nil);
    check('H20b unknown category -> nil', helmwatch.parseVentureLine('Fishing: (Low) Port Windurst'), nil);
    check('H21 control bytes scrubbed', helmwatch.cleanLine('a\1\2b  c\127'), 'a b c');
    check('H22 jst day rollover', helmwatch.jstDay(15 * 3600) - helmwatch.jstDay(0), 1);

    -- Engine overlay: dlac:AutoHelm resolves the manifest helm block -- the
    -- category hat first for Head (semantic map), the generic ladder as the
    -- fallback (another category's hat still carries Surveyor), best-first
    -- level-gated rungs everywhere else. Armor+neck+waist only by design.
    dispatchM._autoOverride = { helm = {
        hats = { Mining = { name = 'Miners Helmet', level = 1, surv = 1 } },
        head = { { name = 'Lumberjacks Beret', score = 10, level = 1, helm = 0, surv = 1 } },
        body = { { name = 'Plain Tunica +1', score = 21, level = 40, helm = 1, surv = 2 },
                 { name = 'Field Tunica',    score = 1,  level = 1,  helm = 1, surv = 0 } },
        neck = { { name = 'Field Torque',    score = 1,  level = 65, helm = 1, surv = 0 } },
    } };
    local hov = dispatchM._helmOverlayFor({ gather = 'Mining', enabled = true, at = 1 },
        { player = { MainJobSync = 75 } });
    check('H23 hat resolves for category',   hov and hov.Head, 'Miners Helmet');
    check('H24 body best rung',              hov and hov.Body, 'Plain Tunica +1');
    check('H25 neck usable at 75',           hov and hov.Neck, 'Field Torque');
    local hov2 = dispatchM._helmOverlayFor({ gather = 'Harvesting', enabled = true },
        { player = { MainJobSync = 75 } });
    check('H26 missing hat -> head ladder',  hov2 and hov2.Head, 'Lumberjacks Beret');
    local hov3 = dispatchM._helmOverlayFor({ gather = 'Mining', enabled = true },
        { player = { MainJobSync = 30 } });
    check('H27 underlevel rung falls through', hov3 and hov3.Body, 'Field Tunica');
    check('H28 underlevel neck -> slot empty', hov3 and hov3.Neck, nil);
    local hoff = dispatchM._helmOverlayFor({ gather = 'Mining', enabled = false },
        { player = { MainJobSync = 75 } });
    check('H29 disabled -> no overlay',      hoff, nil);
    local hnog = dispatchM._helmOverlayFor({ gather = '', enabled = true },
        { player = { MainJobSync = 75 } });
    check('H30 no category -> no overlay',   hnog, nil);
    dispatchM._autoOverride = nil;

    -- rating / preview (helmwatch reads the same manifest shape itself for
    -- the bar display: HELM sum over non-Head picks, >=5 = break-proof)
    helmwatch._setManifest({ helm = {
        hats  = { Mining = { name = 'Miners Helmet', level = 1, surv = 1 } },
        body  = { { name = 'Plain Tunica', score = 11, level = 30, helm = 1, surv = 1 } },
        hands = { { name = 'Field Gloves', score = 1,  level = 1,  helm = 1, surv = 0 } },
        neck  = { { name = 'Field Torque', score = 1,  level = 65, helm = 1, surv = 0 } },
        waist = { { name = 'Field Rope',   score = 1,  level = 65, helm = 1, surv = 0 } },
        legs  = { { name = 'Plain Hose',   score = 11, level = 30, helm = 1, surv = 1 } },
        feet  = { { name = 'Plain Boots',  score = 11, level = 30, helm = 1, surv = 1 } },
    } });
    local pv = helmwatch.preview('Mining', 75);
    check('H31 preview head is the hat',  pv.Head ~= nil and pv.Head.name, 'Miners Helmet');
    check('H32 preview body',             pv.Body ~= nil and pv.Body.name, 'Plain Tunica');
    local hr, hs, hbp = helmwatch.rating('Mining', 75);
    check('H33 rating sums HELM (no head)', hr, 6);
    check('H34 surveyor total',             hs, 4);
    check('H35 break-proof at >= 5',        hbp, true);
    local lr = select(1, helmwatch.rating('Mining', 20));
    check('H36 level gating trims rating',  lr, 1);

    -- Auto HELM (Henrik's split): the detection-armed temporary overlay.
    -- Default off; a Point result while armed opens a hold; the engine wears
    -- the gear only while the hold runs (idle switch stays independent).
    check('H37 auto default off',           helmwatch.isAutoHelm(), false);
    helmwatch.onEventNum(evt, function(i) return 'Logging Point'; end);
    check('H38 unarmed swing -> no hold',   helmwatch.autoActive(), false);
    helmwatch.setAutoHelm(true);
    check('H39 auto arms',                  helmwatch.isAutoHelm(), true);
    helmwatch.onEventNum(evt, function(i) return 'Logging Point'; end);
    check('H40 armed swing opens the hold', helmwatch.autoActive(), true);
    check('H41 armed swing sets category',  helmwatch.getGather(), 'Logging');
    helmwatch.setAutoHelm(false);
    check('H42 disarm ends the hold',       helmwatch.autoActive(), false);

    -- Engine: helmStateActive is the single truth for both ways in.
    local act = dispatchM._helmStateActive;
    check('H43 idle switch active',    act({ gather = 'Mining', enabled = true }), true);
    check('H44 auto + live hold',      act({ gather = 'Mining', enabled = false, auto = true, autoUntil = os.time() + 60 }), true);
    check('H45 auto + expired hold',   act({ gather = 'Mining', enabled = false, auto = true, autoUntil = os.time() - 1 }), false);
    check('H46 auto without hold',     act({ gather = 'Mining', enabled = false, auto = true }), false);
    check('H47 hold without auto',     act({ gather = 'Mining', enabled = false, autoUntil = os.time() + 60 }), false);
    check('H48 no category never active', act({ gather = '', enabled = true, auto = true, autoUntil = os.time() + 60 }), false);
    dispatchM._autoOverride = { helm = {
        body = { { name = 'Field Tunica', score = 1, level = 1, helm = 1, surv = 0 } },
    } };
    local aov = dispatchM._helmOverlayFor(
        { gather = 'Mining', enabled = false, auto = true, autoUntil = os.time() + 60 },
        { player = { MainJobSync = 75 } });
    check('H49 hold resolves the overlay',  aov and aov.Body, 'Field Tunica');
    local aoff = dispatchM._helmOverlayFor(
        { gather = 'Mining', enabled = false, auto = true, autoUntil = os.time() - 1 },
        { player = { MainJobSync = 75 } });
    check('H50 expired hold -> no overlay', aoff, nil);
    dispatchM._autoOverride = nil;

    -- Proximity hold via the CENTRAL entity watcher (entwatch migration --
    -- was the targeting anchor): Auto HELM tracks the four "* Point" names
    -- itself, so ANY point within range holds the gear on -- no targeting.
    -- The probe is the watcher seam: nearest('<Cat> Point') -> yalms | nil.
    local world = { points = {} };   -- ['Mining Point'] = nearest dist (yalms)
    local probe = { nearest = function(nm) return world.points[nm]; end };
    helmwatch.setAutoHelm(true);
    helmwatch.setProxRange(6);   -- pin the 6y/8y geometry for H51-H64
    world.points['Mining Point'] = 5;
    check('H51 point in range holds, no target', helmwatch.proximityStep(probe), true);
    check('H52 hold equips (live)',            helmwatch.autoActive(), true);
    check('H53 nearest point selects category', helmwatch.getGather(), 'Mining');
    world.points['Mining Point'] = 7;              -- inside the 8y leash
    check('H54 leash keeps the active category', helmwatch.proximityStep(probe), true);
    world.points['Mining Point'] = 10;             -- walked away
    check('H55 out of leash drops the hold',   helmwatch.proximityStep(probe), false);
    world.points['Mining Point'] = 5;              -- wandered back
    check('H56 re-acquires without any target', helmwatch.proximityStep(probe), true);
    world.points['Mining Point'] = nil;            -- mined out (despawn)...
    world.points['Logging Point'] = 1;             -- ...stacked twin on the spot
    check('H57 stacked spawn: hold survives',  helmwatch.proximityStep(probe), true);
    check('H58 and follows what is there',     helmwatch.getGather(), 'Logging');
    world.points['Logging Point'] = nil;
    world.points['Harvesting Point'] = 7;          -- leash range, but a SWITCH
    check('H59 category switch needs enter range', helmwatch.proximityStep(probe), false);
    world.points['Harvesting Point'] = nil;
    -- the swing result stays the category authority + latches the hold
    helmwatch.onEventNum(evt, function(i) return (i == 319) and 'Logging Point' or nil; end);
    check('H60 swing result opens the hold',   helmwatch.autoActive(), true);
    check('H61 swing result picks category',   helmwatch.getGather(), 'Logging');
    world.points['Logging Point'] = 7;             -- sweep caught up: leash applies
    check('H62 post-swing leash holds',        helmwatch.proximityStep(probe), true);
    world.points['Logging Point'] = nil;
    check('H63 all points gone -> hold drops', helmwatch.proximityStep(probe), false);
    helmwatch.setAutoHelm(false);
    world.points['Mining Point'] = 5;
    check('H64 disarmed: never holds',         helmwatch.proximityStep(probe), false);

    -- Configurable detect range (Henrik: default 10 for macro-spam-at-range
    -- and lag; panel setting clamped 3..20, keep-wearing leash = range+2).
    check('H70 default range is 10',        helmwatch.PROX_DEFAULT, 10);
    helmwatch.setProxRange(25);
    check('H71 clamps high to 20',          helmwatch.proxEnter(), 20);
    helmwatch.setProxRange(1);
    check('H72 clamps low to 3',            helmwatch.proxEnter(), 3);
    helmwatch.setProxRange(10);
    helmwatch.setAutoHelm(true);
    world.points = { ['Harvesting Point'] = 9 };   -- outside 6, inside 10
    check('H73 wider range acquires at 9y', helmwatch.proximityStep(probe), true);
    world.points['Harvesting Point'] = 11.9;       -- just inside the 12y leash
    check('H74 leash follows range (+2y)',  helmwatch.proximityStep(probe), true);
    world.points['Harvesting Point'] = 12.1;       -- just past it
    check('H75 past the leash drops',       helmwatch.proximityStep(probe), false);
    helmwatch.setAutoHelm(false);

    -- Combat gate (v61): "Default" is NOT "idle" -- HandleDefault runs every
    -- frame including combat, so the overlay itself must stand aside while
    -- Engaged/Dead. 'Event' stays dressed (the swing animation is an event).
    dispatchM._autoOverride = { helm = {
        body = { { name = 'Field Tunica', score = 1, level = 1, helm = 1, surv = 0 } },
    } };
    local hsOn = { gather = 'Mining', enabled = true };
    local function stCtx(st) return { player = { MainJobSync = 75, Status = st } }; end
    check('H65 engaged -> overlay stands aside', dispatchM._helmOverlayFor(hsOn, stCtx('Engaged')), nil);
    check('H66 dead -> stands aside', dispatchM._helmOverlayFor(hsOn, stCtx('Dead')), nil);
    local hIdle = dispatchM._helmOverlayFor(hsOn, stCtx('Idle'));
    check('H67 idle -> dressed',      hIdle and hIdle.Body, 'Field Tunica');
    local hEvt = dispatchM._helmOverlayFor(hsOn, stCtx('Event'));
    check('H68 event -> stays dressed (no per-swing churn)', hEvt and hEvt.Body, 'Field Tunica');
    local hNoP = dispatchM._helmOverlayFor(hsOn, { player = nil });
    check('H69 unreadable status -> dressed (idle assumption)', hNoP and hNoP.Body, 'Field Tunica');
    dispatchM._autoOverride = nil;
end)();

-- ---------------------------------------------------------------------------
-- GD. shipped conditional-effects data pins (data\gearsets.lua +
--     data\latentstats.lua) -- regeneration guards, the smoke_ui S21 style.
--     Shapes verified against the server source 2026-07-17 (design Appendix C).
-- ---------------------------------------------------------------------------
(function()
    local gsD = dofile('data/gearsets.lua');
    local nSets, nFlat, nTiered = 0, 0, 0;
    local census = {};
    local tierKeysOk, piecesOk = true, true;
    for _, e in pairs(gsD) do
        nSets = nSets + 1;
        local tn = 0;
        for c in pairs(e.tiers) do
            tn = tn + 1;
            if c < e.min or c > e.max then tierKeysOk = false; end
        end
        if tn == 1 then nFlat = nFlat + 1; else nTiered = nTiered + 1; end
        census[e.min .. '/' .. e.max] = (census[e.min .. '/' .. e.max] or 0) + 1;
        for _, pid in ipairs(e.pieces) do
            if type(pid) ~= 'number' or pid <= 0 then piecesOk = false; end
        end
    end
    check('GD1 126 gear sets ship', nSets, 126);
    check('GD2 flat/tiered split', nFlat .. '/' .. nTiered, '39/87');
    check('GD3 min/max shape census', (census['2/2'] or 0) .. ',' .. (census['2/4'] or 0) .. ','
        .. (census['2/5'] or 0) .. ',' .. (census['5/5'] or 0), '20,1,86,19');
    check('GD4 every tier key within [min,max]', tierKeysOk, true);
    check('GD5 every piece id is a positive number', piecesOk, true);
    local s70 = gsD[70];   -- Lava's + Kusha's, THE reference set
    check('GD6 [70] pieces', s70 ~= nil and (s70.pieces[1] .. ',' .. s70.pieces[2]), '15850,15851');
    check('GD7 [70] min/max', s70 ~= nil and (s70.min .. '/' .. s70.max), '2/2');
    check('GD8 [70] tier values', s70 ~= nil and (s70.tiers[2].Attack .. ',' .. s70.tiers[2].Accuracy
        .. ',' .. s70.tiers[2].DEF), '6,12,6');
    local s43 = gsD[43];   -- Paramount: alternates -- MORE pieces than the cap
    check('GD9 [43] alternate-piece shape (9 pieces, min2/max2)',
        s43 ~= nil and (#s43.pieces .. '/' .. s43.min .. '/' .. s43.max), '9/2/2');

    local lsD = dofile('data/latentstats.lua');
    local rows, items, levelLeak = 0, 0, false;
    for _, rr in pairs(lsD) do
        items = items + 1;
        for _, r in ipairs(rr) do
            rows = rows + 1;
            -- latent 50/51 rows belong to levelscaling.lua, NEVER here (the
            -- routing boundary -- gen_levelscaling.py's old latent-52 bug class)
            if r.cond == 'JOB_LEVEL_ABOVE' or r.cond == 'JOB_LEVEL_BELOW' then levelLeak = true; end
        end
    end
    -- windows re-pinned 2026-07-19: generator now unions the live API's per-item
    -- latents (tools/api_cache) with the repo SQL -- live-only content (the CEXI
    -- "+1" leveling line, Malphas set, ...) added ~470 rows.
    check('GD10 latentstats rows in range', rows >= 2100 and rows <= 2500, true);
    check('GD11 latentstats items in range', items >= 850 and items <= 980, true);
    check('GD12 zero level-latent rows leaked', levelLeak, false);
    local spot = lsD[11312];
    check('GD13 spot row 11312 (STR +5 while TP > 100)', spot ~= nil
        and (spot[1].stat .. '/' .. spot[1].add .. '/' .. spot[1].cond .. '/' .. spot[1].param),
        'STR/5/TP_OVER/100');
end)();

-- ---------------------------------------------------------------------------
-- GE. geareffects -- the pure set-bonus evaluator (conditional-effects P1).
--     Semantics pinned to the server applier: value-at-count replacement tiers,
--     tiers[min(count,max)] with nil below min, per-SLOT counting (duplicates
--     twice), and the level gate (a piece above ctx.level stops counting while
--     its stats still sum).
-- ---------------------------------------------------------------------------
(function()
    local gfe = dofile('gear/geareffects.lua');
    gfe.configure({ gearsets = {
        [1] = { pieces = { 1001, 1002 }, min = 2, max = 2,          -- the Lava/Kusha shape
                tiers = { [2] = { Attack = 6, Accuracy = 12, DEF = 6 } } },
        [2] = { pieces = { 1101, 1102, 1103, 1104, 1105 }, min = 2, max = 5,   -- Iron Ram shape
                tiers = { [2] = { FireMagicEva = 5 }, [3] = { FireMagicEva = 10 },
                          [4] = { FireMagicEva = 15 }, [5] = { FireMagicEva = 30 } } },
        [3] = { pieces = { 1201, 1202, 1203, 1204, 1205, 1206, 1207, 1208, 1209 },
                min = 2, max = 2, tiers = { [2] = { STR = 3 } } },  -- alternates (any 2 of 9)
        [4] = { pieces = { 1001, 1301 }, min = 2, max = 2,          -- 1001 is in TWO sets
                tiers = { [2] = { VIT = 2 } } },
        [5] = { pieces = { 1401, 1402, 1403, 1404, 1405 }, min = 5, max = 5,   -- the min-5 JSE shape
                tiers = { [5] = { Haste = 5 } } },
    } });
    local so = gfe.setsOf(1001);
    check('GE1 multi-set membership, sorted', so ~= nil and (#so .. ':' .. so[1] .. ',' .. so[2]), '2:1,4');
    check('GE2 non-member items return nil (zero-alloc)', gfe.setsOf(9999), nil);
    check('GE3 below min -> no tier', gfe.setTier(1, 1), nil);
    check('GE4 tier at count', gfe.setTier(1, 2).Accuracy, 12);
    check('GE5 count clamps at max', gfe.setTier(1, 5).Accuracy, 12);
    check('GE6 tier value is the TOTAL at that count (replacement)', gfe.setTier(2, 3).FireMagicEva, 10);

    local lava  = { Id = 1001, Name = 'Lava Ring',  Level = 30, Stats = { Accuracy = 5 } };
    local kusha = { Id = 1002, Name = 'Kusha Ring', Level = 30, Stats = { Attack = 2 } };
    local res = gfe.comboStats({ Ring1 = lava, Ring2 = kusha }, { level = 75 });
    check('GE7 combo folds item stats + bonus (Accuracy)', res.stats.Accuracy, 17);
    check('GE8 combo folds item stats + bonus (Attack)', res.stats.Attack, 8);
    check('GE9 bonus-only stat appears', res.stats.DEF, 6);
    local sb1, sb4;
    for _, sb in ipairs(res.setBonuses) do
        if sb.setId == 1 then sb1 = sb; end
        if sb.setId == 4 then sb4 = sb; end
    end
    check('GE10 active bonus row (count/tier/active)',
        sb1 ~= nil and (sb1.count .. '/' .. sb1.tier .. '/' .. tostring(sb1.active)), '2/2/true');
    check('GE11 partial set listed inactive (the "one more piece" row)',
        sb4 ~= nil and (sb4.count .. '/' .. tostring(sb4.active)), '1/false');

    -- per-SLOT counting: the SAME record in both ring slots counts twice
    local dup = gfe.comboStats({ Ring1 = lava, Ring2 = lava }, { level = 75 });
    local dupRow;
    for _, sb in ipairs(dup.setBonuses) do if sb.setId == 1 then dupRow = sb; end end
    check('GE12 duplicates count per slot (server-verified)',
        dupRow ~= nil and (dupRow.count .. '/' .. tostring(dupRow.active)), '2/true');

    -- level gate: an over-level piece stops COUNTING; its stats still sum
    local high = { Id = 1002, Name = 'Kusha Ring', Level = 70, Stats = { Attack = 2 } };
    local sync = gfe.comboStats({ Ring1 = lava, Ring2 = high }, { level = 50 });
    local syncRow;
    for _, sb in ipairs(sync.setBonuses) do if sb.setId == 1 then syncRow = sb; end end
    check('GE13 level-sync gate strips the count', syncRow ~= nil and syncRow.count, 1);
    check('GE14 ...but never the item stats', sync.stats.Attack, 2);
    local nilctx = gfe.comboStats({ Ring1 = lava, Ring2 = high }, nil);
    local nilRow;
    for _, sb in ipairs(nilctx.setBonuses) do if sb.setId == 1 then nilRow = sb; end end
    check('GE15 nil ctx -> no gate', nilRow ~= nil and nilRow.count, 2);

    -- alternates activate on ANY two pieces -- weapon+weapon included
    local alt = gfe.comboStats({
        Main = { Id = 1201, Name = 'Alt A', Level = 1, Stats = {} },
        Sub  = { Id = 1205, Name = 'Alt B', Level = 1, Stats = {} },
    }, { level = 75 });
    local altRow;
    for _, sb in ipairs(alt.setBonuses) do if sb.setId == 3 then altRow = sb; end end
    check('GE16 alternates: any 2 of 9 activates', altRow ~= nil and tostring(altRow.active) .. '/'
        .. tostring(alt.stats.STR), 'true/3');

    -- itemStats stays the zero-copy levelstats passthrough
    local plain = { Name = 'Plain Ring', Level = 1, Stats = { MND = 2 } };
    check('GE17 itemStats zero-copy passthrough', gfe.itemStats(plain, { level = 75 }) == plain.Stats, true);

    -- THE threshold rule (Henrik, 2026-07-18): below a set's minimum the bonus
    -- does not exist AT ALL -- no halves, no per-piece fractions. A min-5 set at
    -- four pieces grants nothing anywhere (display marks it inactive; totals and
    -- the optimizer see zero).
    check('GE19 min-5 set at 4 pieces: no tier at all', gfe.setTier(5, 4), nil);
    local function jse(n)
        local comp = {};
        for i = 1, n do
            comp['S' .. i] = { Id = 1400 + i, Name = 'JSE ' .. i, Level = 30, Stats = {} };
        end
        return gfe.comboStats(comp, { level = 75 });
    end
    local four, five = jse(4), jse(5);
    local fourRow, fiveRow;
    for _, sb in ipairs(four.setBonuses) do if sb.setId == 5 then fourRow = sb; end end
    for _, sb in ipairs(five.setBonuses) do if sb.setId == 5 then fiveRow = sb; end end
    check('GE20 four of five: zero bonus in totals, row inactive',
        tostring(four.stats.Haste) .. '/' .. tostring(fourRow ~= nil and fourRow.active), 'nil/false');
    check('GE21 all five: the full bonus, whole', five.stats.Haste .. '/' .. tostring(fiveRow.active), '5/true');

    -- augment fold (ctx.augStats = { itemId -> deltas }): the caller's private
    -- augments ride THE evaluator, so Set totals, the weighted score, and every
    -- future consumer read identical numbers (Henrik's field case: Refresh+1
    -- body native + Refresh+1 legs augment showed "+1" in Set totals while the
    -- score already counted +2).
    local body = { Id = 2001, Name = 'Refresh Body', Level = 40, Stats = { Refresh = 1 } };
    local legs = { Id = 2002, Name = 'Plain Legs',   Level = 40, Stats = {} };
    local augd = gfe.comboStats({ Body = body, Legs = legs },
        { level = 75, augStats = { [2002] = { Refresh = 1, Note = 'hq' } } });
    check('GE22 augStats folds private augment deltas (base+aug)', augd.stats.Refresh, 2);
    check('GE23 non-numeric augment values never leak into totals', augd.stats.Note, nil);
    local noaug = gfe.comboStats({ Body = body, Legs = legs }, { level = 75 });
    check('GE24 no augStats -> base only (back-compat)', noaug.stats.Refresh, 1);
    -- per-SLOT like everything else: the same augmented ring worn twice folds twice
    local dupA = gfe.comboStats({ Ring1 = lava, Ring2 = lava },
        { level = 75, augStats = { [1001] = { Accuracy = 3 } } });
    check('GE25 augment deltas count per SLOT (5+5 base, 12 set, 3+3 aug)', dupA.stats.Accuracy, 28);

    -- the REAL shipped data end-to-end: worn Lava's + Kusha's (ids 15850/15851)
    local gfe2 = dofile('gear/geareffects.lua');
    gfe2.configure({ gearsets = dofile('data/gearsets.lua') });
    local worn = gfe2.comboStats({
        Ring1 = { Id = 15850, Name = "Lava's Ring",  Level = 30, Stats = {} },
        Ring2 = { Id = 15851, Name = "Kusha's Ring", Level = 30, Stats = {} },
    }, { level = 75 });
    check('GE18 shipped data: Lava+Kusha bonus', (worn.stats.Attack or 0) .. '/'
        .. (worn.stats.Accuracy or 0) .. '/' .. (worn.stats.DEF or 0), '6/12/6');
end)();

-- ---------------------------------------------------------------------------
-- HB. optimizePicks gear-set crediting (conditional-effects P3, ADR 0011):
--     the bonus term inside the capped objective, incremental per-slot counts,
--     and the set-seeded restarts that find pairs single-slot climbing cannot.
-- ---------------------------------------------------------------------------
(function()
    -- synthetic effects seam (no geareffects needed: optimizePicks only sees fns)
    local SETS = {
        [1] = { pieces = { 101, 102 }, min = 2, max = 2, tiers = { [2] = { Accuracy = 12 } } },
        [2] = { pieces = { 201, 202, 203, 204, 205 }, min = 2, max = 5,
                tiers = { [2] = { Accuracy = 4 }, [3] = { Accuracy = 6 },
                          [4] = { Accuracy = 6 }, [5] = { Accuracy = 30 } } },
        [3] = { pieces = { 301, 302 }, min = 2, max = 2, tiers = { [2] = { Haste = 5 } } },
    };
    local BYITEM = {};
    for sid, e in pairs(SETS) do
        for _, pid in ipairs(e.pieces) do
            BYITEM[pid] = BYITEM[pid] or {};
            table.insert(BYITEM[pid], sid);
        end
    end
    local fx = {
        setsOf  = function(id) return BYITEM[id]; end,
        setTier = function(sid, c)
            local e = SETS[sid];
            if e == nil or c < e.min then return nil; end
            return e.tiers[math.min(c, e.max)];
        end,
    };
    local W3 = { Accuracy = { perUnit = 3 } };
    local function mk(id, name, stats) return { stats = stats, ref = { Id = id, Name = name } }; end

    -- HB1: the numeric objective pin (H3-style): both set rings placed, bonus in
    local p1, p2 = mk(101, 'SetRing A', { Accuracy = 2 }), mk(102, 'SetRing B', { Accuracy = 2 });
    local hb1 = optim.optimizePicks({ Ring1 = { p1 }, Ring2 = { p2 } }, W3, { effects = fx });
    check('HB1 bonus inside the objective', hb1.total, 3 * (2 + 2 + 12));

    -- HB2: pair discovery -- each piece is a solo LOSS vs its rival; only a
    -- seeded restart can enter the bonus
    local z1, z2 = mk(101, 'SetRing A', { Accuracy = 0 }), mk(102, 'SetRing B', { Accuracy = 0 });
    local rvA, rvB = mk(901, 'Rival A', { Accuracy = 5 }), mk(902, 'Rival B', { Accuracy = 5 });
    local hb2 = optim.optimizePicks({ Ring1 = { rvA, z1 }, Ring2 = { rvB, z2 } }, W3,
        { effects = fx, conflict = function(a, b) return a == b; end });
    check('HB2 seeded restart finds the pair', hb2.total, 3 * 12);
    check('HB2b ...both set pieces picked', tostring(hb2.picks.Ring1) .. ',' .. tostring(hb2.picks.Ring2), '2,2');

    -- HB3: a bonus that exactly offsets stays EMPTY (strict improvement + the
    -- EMPTY tie preference survive the bonus term); partner via baseComposition
    local neg = mk(101, 'SetRing A', { Accuracy = -12 });
    local hb3 = optim.optimizePicks({ Ring1 = { neg } }, W3,
        { effects = { setsOf = fx.setsOf, setTier = fx.setTier,
                      baseComposition = { { Id = 102, Name = 'SetRing B' } } } });
    check('HB3 exact offset keeps EMPTY', hb3.picks.Ring1, nil);

    -- HB4: one owned copy -- the conflict beats the set (count stays 1, no bonus)
    local cA, cB = mk(101, 'SetRing A', { Accuracy = 2 }), mk(101, 'SetRing A', { Accuracy = 2 });
    local oneCopy = function(a, b)
        if a == b or (a.Id ~= nil and a.Id == b.Id) then return true; end
        return false;
    end
    local hb4 = optim.optimizePicks({ Ring1 = { cA }, Ring2 = { cB } }, W3,
        { effects = fx, conflict = oneCopy });
    local filled4 = (hb4.picks.Ring1 and 1 or 0) + (hb4.picks.Ring2 and 1 or 0);
    check('HB4 conflict beats set: one slot, no bonus', filled4 .. '/' .. hb4.total, '1/' .. (3 * 2));
    -- HB4b: two owned copies -- per-slot counting credits the SAME item twice
    local hb4b = optim.optimizePicks({ Ring1 = { cA }, Ring2 = { cB } }, W3,
        { effects = fx, conflict = function() return false; end });
    check('HB4b two copies activate the set', hb4b.total, 3 * (2 + 2 + 12));

    -- HB5: seed eviction + monotone acceptance -- a dominated set dissolves back
    local i1, i2 = mk(911, 'Indep A', { Accuracy = 10 }), mk(912, 'Indep B', { Accuracy = 10 });
    local w1, w2 = mk(101, 'SetRing A', { Accuracy = 1 }), mk(102, 'SetRing B', { Accuracy = 1 });
    local hb5 = optim.optimizePicks({ Ring1 = { i1, w1 }, Ring2 = { i2, w2 } }, W3,
        { effects = { setsOf = fx.setsOf,
                      setTier = function(sid, c) return (sid == 1 and c >= 2) and { Accuracy = 5 } or nil; end },
          conflict = function(a, b) return a == b; end });
    check('HB5 dominated seed dissolves to the baseline', hb5.total, 3 * 20);
    check('HB5b independents kept', tostring(hb5.picks.Ring1) .. ',' .. tostring(hb5.picks.Ring2), '1,1');

    -- HB6: cap sharing -- a bonus above the cap adds nothing, so a cap-redundant
    -- set stays home (H5's analog through the bonus fold)
    local WH = { Haste = { perUnit = 100, cap = 5 } };
    local hHat = mk(920, 'Haste Hat', { Haste = 5 });
    local s1, s2 = mk(301, 'SetPiece A', { Haste = 0 }), mk(302, 'SetPiece B', { Haste = 0 });
    local hb6 = optim.optimizePicks({ Head = { hHat }, Ring1 = { s1 }, Ring2 = { s2 } }, WH, { effects = fx });
    check('HB6 capped bonus stays home', tostring(hb6.picks.Ring1) .. '/' .. hb6.total, 'nil/500');

    -- HB7: effects present but nothing set-carrying -> bit-identical totals
    local W = { Haste = { perUnit = 100, cap = 5 }, SwordSkill = { perUnit = 2 }, Accuracy = { perUnit = 3 } };
    local hasteHat  = { stats = { Haste = 5 },                               ref = 'HasteHat'  };
    local statHat   = { stats = { Accuracy = 5 },                            ref = 'StatHat'   };
    local greatFeet = { stats = { Haste = 5, SwordSkill = 7, Accuracy = 5 }, ref = 'GreatFeet' };
    local weakFeet  = { stats = { Accuracy = 2 },                            ref = 'WeakFeet'  };
    local hb7 = optim.optimizePicks({ Head = { hasteHat, statHat }, Feet = { greatFeet, weakFeet } }, W,
        { effects = fx });
    check('HB7 no set-carrying candidate: H3 total bit-identical', hb7.total, 100 * 5 + 2 * 7 + 3 * (5 + 5));

    -- HB8: tiered marginal -- 3 pieces credit tiers[3], the 4th enters only when
    -- its tier step pays (tiers[4]-tiers[3] = 0 here -> stays home)
    local t1, t2, t3 = mk(201, 'Tier A', { Accuracy = 1 }), mk(202, 'Tier B', { Accuracy = 1 }),
                       mk(203, 'Tier C', { Accuracy = 1 });
    local t4 = mk(204, 'Tier D', { Accuracy = 0 });
    local hb8 = optim.optimizePicks({ Ring1 = { t1 }, Ring2 = { t2 }, Neck = { t3 }, Head = { t4 } },
        W3, { effects = fx });
    check('HB8 three pieces credit tiers[3]', hb8.total, 3 * (3 + 6));
    check('HB8b zero-step 4th piece stays home', hb8.picks.Head, nil);
    -- ...and a PAYING tier step pulls the 4th piece in (private tier fn: step +14)
    local fx4 = { setsOf = fx.setsOf, setTier = function(sid, c)
        if sid ~= 2 or c < 2 then return nil; end
        return ({ [2] = { Accuracy = 4 }, [3] = { Accuracy = 6 }, [4] = { Accuracy = 20 } })[math.min(c, 4)];
    end };
    local hb8c = optim.optimizePicks({ Ring1 = { t1 }, Ring2 = { t2 }, Neck = { t3 }, Head = { t4 } },
        W3, { effects = fx4 });
    check('HB8c paying tier step pulls the 4th piece', hb8c.picks.Head ~= nil and hb8c.total, 3 * (3 + 20));

    -- HB9: baseComposition partner -- a lone worthless pool piece is credited
    -- the bonus its already-chosen partner completes (the Sub marginal case)
    local lone = mk(101, 'SetRing A', { Accuracy = 0 });
    local hb9 = optim.optimizePicks({ Ring1 = { lone } }, W3,
        { effects = { setsOf = fx.setsOf, setTier = fx.setTier,
                      baseComposition = { { Id = 102, Name = 'SetRing B' } } } });
    check('HB9 baseComposition partner credits the bonus',
        tostring(hb9.picks.Ring1) .. '/' .. hb9.total, '1/' .. (3 * 12));
end)();

-- ---------------------------------------------------------------------------
-- HB10+. buildBestSet through a geareffects-wired gearoptim instance: the
--        append-only pool augmentation + seeding, end to end -- and the greedy
--        Range/Ammo path staying set-blind (a bonus never legalizes a pairing).
-- ---------------------------------------------------------------------------
(function()
    local savedGfx = package.loaded['dlac\\gear\\geareffects'];
    local savedGear = package.loaded['dlac\\gear'];
    local gfe = dofile('gear/geareffects.lua');
    gfe.configure({ gearsets = {
        [7] = { pieces = { 610, 611 }, min = 2, max = 2, tiers = { [2] = { Accuracy = 50 } } },
        [8] = { pieces = { 601, 602 }, min = 2, max = 2, tiers = { [2] = { Accuracy = 99 } } },
    } });
    package.loaded['dlac\\gear\\geareffects'] = gfe;

    -- 21 Head fillers rank ABOVE the set piece, pushing it past the top-20
    -- prune: only the augmentation can put it in front of the optimizer.
    local G2 = { NameToObject = {}, Head = {}, Neck = {} };
    for i = 1, 21 do
        G2.Head['Filler ' .. i] = { Name = 'Filler ' .. string.char(64 + i), Level = 1, Id = 700 + i,
                                    Jobs = { 'All' }, Stats = { Accuracy = 4 + i } };
    end
    G2.Head['Set Sallet'] = { Name = 'Set Sallet', Level = 1, Id = 610, Jobs = { 'All' },
                              Stats = { Accuracy = 0 } };
    G2.Neck['Set Gorget'] = { Name = 'Set Gorget', Level = 1, Id = 611, Jobs = { 'All' },
                              Stats = { Accuracy = 0 } };
    package.loaded['dlac\\gear'] = G2;
    local optB = dofile('gear/gearoptim.lua');
    local hb11 = optB.buildBestSet({ job = 'WAR', level = 75, weights = { Accuracy = { perUnit = 3 } } });
    check('HB11 augmented pool + seeding win the set pair',
        tostring(hb11.slots.Head) .. '+' .. tostring(hb11.slots.Neck), 'Set Sallet+Set Gorget');
    check('HB11b whole-set total is the bonus', hb11.total, 3 * 50);

    -- HB10: the greedy single-stat path stays SET-BLIND (ADR 0011): an unfirable
    -- stat stick still wins the Ammo slot and Range still empties, set data or not
    local function it(name, acc, extra)
        local e = { Name = name, Level = 1, Id = 0, Jobs = { 'All' }, Stats = { Accuracy = acc } };
        for k, v in pairs(extra or {}) do e[k] = v; end
        return e;
    end
    G2.Range = { Archery = { it('Test Bow', 10, { Type = 'Archery', Id = 601 }) } };
    G2.Ammo  = { stick = it('Cinderstone', 20, { Id = 602 }) };
    local r = optB.buildMaxStatSet('Accuracy', { job = 'WAR', level = 99 });
    check('HB10 greedy path set-blind: unfirable ammo still wins', r.slots.Ammo, 'Cinderstone');
    check('HB10b ...and Range stays EMPTY despite the set', r.slots.Range, nil);

    package.loaded['dlac\\gear'] = savedGear;
    package.loaded['dlac\\gear\\geareffects'] = savedGfx;
end)();

-- ---------------------------------------------------------------------------
-- FISHING: fishcalc verdict math (server formulas, hand-computed cases) +
-- fishdb integrity + fishwatch state/pick rules + the engine's dlac:AutoFish
-- overlay (v64) -- docs/design/fishing-gear.md. The fail-chance expectations
-- below are derived BY HAND from fishingutils.cpp CalculateLoseChance :719 /
-- CalculateSnapChance :784 / CalculateBreakChance :828 -- if a port edit
-- moves one of these numbers, re-derive from the C++ before touching the test.
-- ---------------------------------------------------------------------------
(function()
    package.loaded['dlac\\data\\fishdb'] = dofile('data/fishdb.lua');
    local fcalc = dofile('feature/fishcalc.lua');
    package.loaded['dlac\\feature\\fishcalc'] = fcalc;

    -- pure verdict math on synthetic records (no db involved)
    local marlin  = { sk = 61, rank = 23, sz = 1 };
    local halcyon = { sz = 0, minR = 1, maxR = 18, brk = 1 };
    local ebisuR  = { sz = 0, minR = 1, maxR = 30, leg = 1 };
    local v = fcalc.verdictFor(marlin, halcyon, 50);
    check('F1 big fish, small rod: lose=toobig 50', v.lose .. '/' .. tostring(v.loseWhy), '50/toobig');
    check('F2 big fish, small rod: snap capped 55', v.snap, 55);
    check('F3 big fish, small rod: break 9',        v.brk, 9);
    v = fcalc.verdictFor(marlin, ebisuR, 50);
    check('F4 same fish on Ebisu: lose=lowskill 3', v.lose .. '/' .. tostring(v.loseWhy), '3/lowskill');
    check('F5 Ebisu: no snap',  v.snap, 0);
    check('F6 Ebisu never breaks', v.brk, 0);
    local legFish = { sk = 100, rank = 30, sz = 1, leg = 1 };
    local luShang = { sz = 0, minR = 1, maxR = 28, brk = 1, leg = 1 };
    v = fcalc.verdictFor(legFish, luShang, 100);
    check('F7 legendary on legendary rod at skill: SAFE', v.ok, true);
    v = fcalc.verdictFor(legFish, halcyon, 100);
    check('F8 legendary on normal rod: lose toobig', tostring(v.loseWhy), 'toobig');
    check('F9 legendary on normal rod: snap 55',     v.snap, 55);
    check('F10 legendary on normal rod: break 19',   v.brk, 19);
    -- the uint8-wrap quirk: over-skill "rebate" past zero wraps high -> 50
    v = fcalc.verdictFor({ sk = 5, rank = 10, sz = 1 }, { sz = 0, minR = 1, maxR = 5, brk = 1 }, 100);
    check('F11 toobig uint8 wrap clamps to 50', v.lose .. '/' .. tostring(v.loseWhy), '50/toobig');
    -- tooSmall has the guarded subtraction (source :753) -> floors at zero
    local largeRod = { sz = 1, minR = 8, maxR = 18, brk = 1 };
    v = fcalc.verdictFor({ sk = 5, rank = 1, sz = 0 }, largeRod, 100);
    check('F12 toosmall guarded to zero at high skill', v.lose, 0);
    v = fcalc.verdictFor({ sk = 5, rank = 1, sz = 0 }, largeRod, 30);
    check('F13 toosmall mid-skill', v.lose .. '/' .. tostring(v.loseWhy), '25/toosmall');
    v = fcalc.verdictFor({ sk = 99, rank = 1, sz = 0 }, { sz = 0, minR = 1, maxR = 5, brk = 1 }, 1);
    check('F14 lowskill capped at 55', v.lose .. '/' .. tostring(v.loseWhy), '55/lowskill');

    -- fishdb integrity (the shipped data the panel trusts)
    local db = fcalc.db();
    check('F15 fishdb loads through fishcalc', db ~= nil, true);
    local nFish = 0; for _ in pairs(db.fish) do nFish = nFish + 1; end
    local nRods = 0; for _ in pairs(db.rods) do nRods = nRods + 1; end
    local nBaits = 0; for _ in pairs(db.baits) do nBaits = nBaits + 1; end
    check('F16 fish table populated (>=120)', nFish >= 120, true);
    check('F17 all 20 public rods', nRods, 20);
    check('F18 all 39 baits', nBaits, 39);
    check('F19 Moat Carp', db.fish[4401] ~= nil and db.fish[4401].n, 'Moat Carp');
    check('F20 Moat Carp hook level', db.fish[4401].sk, 11);
    check('F21 Ebisu legendary + unbreakable', (db.rods[17011].leg or 0) == 1 and (db.rods[17011].brk or 0) == 0, true);
    check('F22 Lu Shang breaks to 489', db.rods[17386].brokenId, 489);
    check('F23 Little Worm hooks Moat Carp', db.aff[17396] ~= nil and db.aff[17396][4401] ~= nil, true);
    check('F24 search finds the carp', (fcalc.searchFish('moat')[1] or {}).id, 4401);
    check('F25 carp takes baits', #fcalc.baitsFor(4401) > 0, true);
    local iso = fcalc.isolationFor(4291);   -- Sandfish: the generator-verified case
    check('F26 sandfish has isolation rows', #iso > 0, true);
    check('F27 cleanest row first', iso[1].clean, true);
    check('F28 gearBonus: Ebisu cx4', (db.gearBonus[17011] or {}).cx4, 10);
    check('F29 gearBonus: Halieutica is a Main', (db.gearBonus[20945] or {}).sl, 'Main');
    check('F30 gearBonus: Eyepatch carries only cx', (db.gearBonus[28443] or {}).fish == nil
        and (db.gearBonus[28443] or {}).cx4 == 20, true);
    check('F31 guild rank 1 test fish is the carp', db.guild.rankFish[1], 4401);
    check('F32 eleven guild ranks', #db.guild.ranks, 11);
    -- a legendary fish exists and Ebisu beats a twig for it
    local legId = nil;
    for id, f in pairs(db.fish) do if (f.leg or 0) == 1 then legId = id; break; end end
    check('F33 a legendary fish ships', legId ~= nil, true);
    if legId ~= nil then
        local best = fcalc.bestOwnedRod(db.fish[legId], 100, { [17391] = true, [17011] = true });
        check('F34 legendary target -> Ebisu over Willow', best ~= nil and best.id, 17011);
    end
    check('F35 gearScore: verified Fish beats unverified cx', fcalc.gearScore(1, nil) > fcalc.gearScore(0, { cx4 = 50, cx5 = 5 }), true);

    -- fishwatch: state rules + rod/bait auto-pick (headless seams)
    local fw = dofile('feature/fishwatch.lua');
    check('F36 pill starts off', fw.isEnabled(), false);
    local lines = fw.parseVentureLine('Fishing: (Low) Selbina, (Mid) Qufim Island, (High) Sea of Shadows');
    check('F37 fishing venture line: 3 tiers', lines ~= nil and #lines or 0, 3);
    check('F37b low tier', lines ~= nil and lines[1], 'Low:  Selbina');
    check('F38 helm categories are not ours', fw.parseVentureLine('Mining: (Low) Ordelles Caves, (Mid) X, (High) Y'), nil);
    local drift = fw.parseVentureLine('Fishing: something new the server said');
    check('F39 drifted format keeps raw tail', drift ~= nil and drift[1], 'something new the server said');
    check('F40 chatter -> nil', fw.parseVentureLine('gone fishing brb'), nil);
    check('F41 jst rollover', fw.jstDay(15 * 3600) - fw.jstDay(0), 1);
    fw._clientName = function(id)
        return ({ [17390] = 'Yew Fishing Rod', [17391] = 'Willow Fish. Rod',
                  [17396] = 'Little Worm' })[id];
    end
    fw._ownedAvail = { [17391] = 1, [17390] = 1, [17396] = 99 };
    fw.setTarget(4401);
    local rid = select(1, fw.getRod());
    check('F42 target set', select(2, fw.getTarget()), 'Moat Carp');
    -- at skill 0 the Yew (durability 6) out-risks the Willow (5) on a rank-7
    -- carp: snap 8 vs 17 -- the verdict sort must prefer it
    check('F43 rod pick minimizes risk (Yew over Willow)', rid, 17390);
    check('F44 rod stamped with the CLIENT name', select(2, fw.getRod()), 'Yew Fishing Rod');
    check('F45 bait picked from owned affinity', select(1, fw.getBait()), 17396);
    -- explicit bait choice survives re-picks while stocked
    local carpBaits = fcalc.baitsFor(4401);
    local altBait = nil;
    for _, e in ipairs(carpBaits) do if e.id ~= 17396 then altBait = e.id; break; end end
    if altBait ~= nil then
        fw._ownedAvail[altBait] = 12;
        fw.setTarget(4401, altBait);
        check('F46 explicit bait honoured', select(1, fw.getBait()), altBait);
        fw.autoPick(true);
        check('F47 explicit bait survives autoPick(keep)', select(1, fw.getBait()), altBait);
        fw._ownedAvail[altBait] = nil;
    end
    -- THE ISOLATION RULE under the bag heartbeat: a rod-only loss must re-pick
    -- the ROD and leave the user's explicit (lower-power) isolation bait alone.
    -- revalidate passed keepBait=false, silently trading it up to the strongest
    -- stocked bait -- and saying nothing, because the bait announcement only
    -- fires when the BAIT stack emptied (review find, 2026-07-18).
    local topBait = (carpBaits[1] or {}).id;
    local lowBait = (carpBaits[#carpBaits] or {}).id;
    if lowBait ~= nil and topBait ~= nil and lowBait ~= topBait then
        fw._ownedAvail = { [17391] = 1, [17390] = 1, [topBait] = 50, [lowBait] = 12 };
        fw.setTarget(4401, lowBait);              -- the user's isolation pick
        fw.setEnabled(true);
        fw._ownedAvail[17390] = nil;              -- the worn Yew vanishes; Willow remains
        fw.revalidate();
        check('F47b rod-only heartbeat re-picks the rod', select(1, fw.getRod()), 17391);
        check('F47c ...and the explicit ISOLATION bait survives (never traded for power)',
            select(1, fw.getBait()), lowBait);
        fw.setEnabled(false);
        fw._ownedAvail = { [17391] = 1, [17390] = 1, [17396] = 99 };
        fw.setTarget(4401);                       -- re-arm the exhaustion flow below
    end
    fw.setEnabled(true);
    check('F48 pill on', fw.isEnabled(), true);
    fw._ownedAvail = { [17390] = 1 };   -- bait stack gone, rod still here
    fw.revalidate();
    check('F49 exhausted bait cleared (nothing suitable left)', select(1, fw.getBait()), nil);
    fw._ownedAvail = {};                -- rod gone too
    fw.revalidate();
    check('F50 vanished rod cleared', select(1, fw.getRod()), nil);
    fw.setEnabled(false);

    -- engine: fishStateActive + the dlac:AutoFish overlay
    local act = dispatchM._fishStateActive;
    check('F51 enabled state active', act({ enabled = true }), true);
    check('F52 disabled state inactive', act({ enabled = false }), false);
    check('F53 nil state inactive', act(nil), false);
    dispatchM._autoOverride = { fish = {
        main = { { name = 'Halieutica', score = 2105, level = 1, fish = 2 } },
        body = { { name = 'Anglers Tunica', score = 1000, level = 15, fish = 1 },
                 { name = 'Fsh. Tunica',    score = 1000, level = 1,  fish = 1 } },
        ring1 = { { name = 'Anglers Ring', score = 2000, level = 75, fish = 2 } },
    } };
    local fs = { enabled = true, at = 1, rod = 'Willow Fish. Rod', bait = 'Little Worm' };
    local fov = dispatchM._fishOverlayFor(fs, { player = { MainJobSync = 75, Status = 'Idle' } });
    check('F54 rod worn from state', fov and fov.Range, 'Willow Fish. Rod');
    check('F55 bait worn from state', fov and fov.Ammo, 'Little Worm');
    check('F56 Main ladder (Halieutica)', fov and fov.Main, 'Halieutica');
    check('F57 body best rung', fov and fov.Body, 'Anglers Tunica');
    check('F58 ring ladder', fov and fov.Ring1, 'Anglers Ring');
    local fovLow = dispatchM._fishOverlayFor(fs, { player = { MainJobSync = 10, Status = 'Idle' } });
    check('F59 underlevel rung falls through', fovLow and fovLow.Body, 'Fsh. Tunica');
    check('F60 underlevel ring -> slot empty', fovLow and fovLow.Ring1, nil);
    check('F61 engaged -> stands aside', dispatchM._fishOverlayFor(fs, { player = { MainJobSync = 75, Status = 'Engaged' } }), nil);
    check('F62 dead -> stands aside', dispatchM._fishOverlayFor(fs, { player = { MainJobSync = 75, Status = 'Dead' } }), nil);
    local fovEvt = dispatchM._fishOverlayFor(fs, { player = { MainJobSync = 75, Status = 'Event' } });
    check('F63 event stays dressed', fovEvt and fovEvt.Range, 'Willow Fish. Rod');
    check('F64 disabled -> no overlay', dispatchM._fishOverlayFor({ enabled = false, rod = 'X' }, { player = { MainJobSync = 75 } }), nil);
    local fsNoGear = { enabled = true };
    local fovNoRod = dispatchM._fishOverlayFor(fsNoGear, { player = { MainJobSync = 75, Status = 'Idle' } });
    check('F65 no rod picked -> Range untouched, ladders still dress',
        (fovNoRod and fovNoRod.Range) == nil and (fovNoRod and fovNoRod.Body) ~= nil, true);
    -- v91: the rod brings an Ammo claim even with NO bait ('remove') -- an
    -- unclaimed Ammo lets an idle set's stat-stick trinket land beside the
    -- rod and the server strips the rod (ADR 0010), forever.
    local fsNoBait = { enabled = true, at = 1, rod = 'Willow Fish. Rod' };
    local fovNoBait = dispatchM._fishOverlayFor(fsNoBait, { player = { MainJobSync = 75, Status = 'Idle' } });
    check('F68 rod with no bait -> Ammo claimed empty', fovNoBait and fovNoBait.Ammo, 'remove');
    check('F69 ... and the rod still equips', fovNoBait and fovNoBait.Range, 'Willow Fish. Rod');
    check('F70 no rod AND no bait -> Ammo left alone', fovNoRod and fovNoRod.Ammo, nil);
    local fsBaitOnly = { enabled = true, at = 1, bait = 'Little Worm' };
    local fovBaitOnly = dispatchM._fishOverlayFor(fsBaitOnly, { player = { MainJobSync = 75, Status = 'Idle' } });
    check('F71 bait without a rod rides as itself', fovBaitOnly and fovBaitOnly.Ammo, 'Little Worm');
    check('F66 resolveVirtual dlac:AutoFish body', dispatchM._resolveVirtual('dlac:AutoFish',
        { player = { MainJobSync = 75 } }, 'Body'), 'Anglers Tunica');
    check('F67 resolveVirtual unknown fish slot -> nil', dispatchM._resolveVirtual('dlac:AutoFish',
        { player = { MainJobSync = 75 } }, 'Sub'), nil);
    dispatchM._autoOverride = nil;

    -- craftwatch: the fishing guild points offset (0x20) now parses
    local cw2 = dofile('feature/craftwatch.lua');
    local function fi32(v) return string.char(v % 256, math.floor(v/256)%256, math.floor(v/65536)%256, math.floor(v/16777216)%256); end
    local pkt = string.rep('\0', 0x20) .. fi32(1111) .. fi32(2555) .. fi32(6536) .. fi32(10990)
        .. fi32(540) .. fi32(23539) .. fi32(0) .. fi32(75200) .. fi32(4325);
    cw2.onCurrencyPacket(pkt);
    check('F68 fishing GP parsed at 0x20', cw2.guildPointsFor('Fishing'), 1111);
    check('F69 craft offsets unmoved', cw2.guildPointsFor('Woodworking'), 2555);

    -- field round 5 (2026-07-18): the legendary tier, manual pins, and the
    -- upgrade heartbeat. Henrik's ruling: "Lu Shang's always beats base rods,
    -- Ebisu always beats Lu Shang's" -- and no pill toggle to get there.

    -- the live bug verbatim: Moat Carp at high skill is risk-0 on everything,
    -- and the old sort let Clothespole's raw attack outrank Lu Shang's
    local poleId = nil;
    for id, r in pairs(db.rods) do
        if (r.n or ''):lower() == 'clothespole' then poleId = id; break; end
    end
    check('F70 Clothespole ships', poleId ~= nil, true);
    if poleId ~= nil then
        local best5 = fcalc.bestOwnedRod(db.fish[4401], 100, { [poleId] = true, [17386] = true });
        check('F70b Lu Shang over Clothespole on the carp', best5 and best5.id, 17386);
    end
    local bestLeg = fcalc.bestOwnedRod(db.fish[4401], 100, { [17386] = true, [17011] = true });
    check('F71 Ebisu over Lu Shang', bestLeg and bestLeg.id, 17011);
    check('F72 legRank tiers ordered', fcalc.legRank(17011) > fcalc.legRank(17386)
        and fcalc.legRank(17386) > fcalc.legRank(17390), true);
    -- risk STILL beats the tier: a fish that would snap Lu Shang's gets the
    -- safe base rod recommended (the whole point of the verdict system)
    local realDb = db;
    fcalc._setDb({ fish = { [1] = { n = 'Brutus', sk = 10, rank = 40, sz = 1 } },
                   rods = { [17386] = { n = 'Lu', leg = 1, brk = 1, sz = 0, minR = 1, maxR = 28 },
                            [900] = { n = 'Big Safe Rod', sz = 1, minR = 1, maxR = 45, brk = 1 } },
                   baits = {}, aff = {}, pools = {}, zones = {}, mobs = {} });
    local rRisk = fcalc.rodsFor(fcalc.db().fish[1], 100, { [17386] = true, [900] = true });
    check('F73 risk beats the legendary tier', rRisk[1] and rRisk[1].id, 900);
    fcalc._setDb(realDb);

    -- manual pins (the fish bar dropdowns): a pin holds through the heartbeat,
    -- falls back to auto when the item vanishes, and target changes unpin
    fw._ownedAvail = { [17391] = 1, [17390] = 1, [17396] = 99 };
    fw.setTarget(4401);
    fw.setEnabled(true);
    check('F74 auto rod first (least-risk Yew)', select(1, fw.getRod()), 17390);
    fw.setRod(17391);                          -- the user says Willow
    check('F75 manual rod set + pinned', select(1, fw.getRod()) == 17391 and fw.rodPinned(), true);
    fw.revalidate();                           -- the beat must NOT trade it back
    check('F76 pinned rod survives the heartbeat', select(1, fw.getRod()), 17391);
    fw._ownedAvail[17391] = nil;               -- the pinned rod vanishes
    fw.revalidate();
    check('F77 vanished pin falls back to auto', select(1, fw.getRod()) == 17390 and not fw.rodPinned(), true);
    fw._ownedAvail = { [17391] = 1, [17396] = 99 };   -- Yew gone, only Willow
    fw.revalidate();
    check('F78 vanish still re-picks what exists', select(1, fw.getRod()), 17391);
    fw._ownedAvail[17390] = 1;                 -- the better (least-risk) Yew RETURNS
    fw.revalidate();                           -- no vanish, no toggle -- just the beat
    check('F79 better rod adopted on the beat (the Lu Shang bug)', select(1, fw.getRod()), 17390);
    fw.setRod(17391);                          -- pin Willow again...
    fw.setTarget(4401);                        -- ...then change target
    check('F80 target change unpins', fw.rodPinned(), false);
    -- pinned bait is absolute while stocked -- even off-affinity (the user
    -- may know something fishdb doesn't)
    local offBait = nil;
    for id in pairs(db.baits) do if (db.aff[id] or {})[4401] == nil then offBait = id; break; end end
    check('F81 an off-affinity bait exists', offBait ~= nil, true);
    if offBait ~= nil then
        fw._ownedAvail[offBait] = 3;
        fw.setBait(offBait);
        check('F81b off-affinity manual bait honoured', select(1, fw.getBait()), offBait);
        fw.revalidate();
        check('F82 pinned bait survives the heartbeat', select(1, fw.getBait()), offBait);
        fw.setBait(nil);
        check('F83 AUTO returns the affine pick', select(1, fw.getBait()), 17396);
        fw._ownedAvail[offBait] = nil;
    end
    fw.setEnabled(false);

    -- wornFishTotal moved into fishcalc (fishui + fishbar share it)
    fcalc._setDb({ gearBonus = { [1] = { sl = 'Body', fish = 2 }, [2] = { sl = 'Body', fish = 1 },
                                 [3] = { sl = 'Ring', fish = 1 }, [4] = { sl = 'Range', fish = 5 } },
                   fish = {}, rods = {}, baits = {}, aff = {}, pools = {} });
    check('F84 wornFishTotal: best body + doubled ring, rod excluded',
        fcalc.wornFishTotal({ [1] = 1, [2] = 1, [3] = 2, [4] = 1 }), 4);
    fcalc._setDb(realDb);
end)();

-- ---------------------------------------------------------------------------
-- CHOCOBO riding-gear overlay (issue #95, engine v120 -- docs/design/chocobo-
-- gear.md). The fourth idle-only sibling: chocoStateActive is enabled-only;
-- chocoOverlayFor resolves the manifest `choco` block through dlac:AutoChoco
-- for Main/Neck/Body/Hands/Legs/Feet (the Chocobo Wand rides Main), stands
-- aside Engaged/Dead, and level-gates each rung like HELM/Fishing.
-- ---------------------------------------------------------------------------
(function()
    local act = dispatchM._chocoStateActive;
    check('CH1 enabled state active',   act({ enabled = true }), true);
    check('CH2 disabled state inactive', act({ enabled = false }), false);
    check('CH3 nil state inactive',     act(nil), false);

    dispatchM._autoOverride = { choco = {
        main = { { name = 'Chocobo Wand', score = 30, level = 1, ride = 30 } },
        neck = { { name = 'Chocobo Torque', score = 4, level = 1, ride = 4 } },
        body = { { name = 'Orange Race Silks', score = 10, level = 1, ride = 10 } },
        legs = { { name = 'Riders Hose', score = 4, level = 55, ride = 4 } },
    } };
    local cs = { enabled = true, at = 1 };
    local cov = dispatchM._chocoOverlayFor(cs, { player = { MainJobSync = 75, Status = 'Idle' } });
    check('CH4 Main is the Chocobo Wand (weapon slot included)', cov and cov.Main, 'Chocobo Wand');
    check('CH5 Neck resolves',  cov and cov.Neck, 'Chocobo Torque');
    check('CH6 Body resolves',  cov and cov.Body, 'Orange Race Silks');
    check('CH7 Legs usable at 75', cov and cov.Legs, 'Riders Hose');
    -- slots the ladder has no gear for are simply absent from the overlay.
    check('CH8 Hands with no owned rung -> slot absent', cov and cov.Hands, nil);
    local covLow = dispatchM._chocoOverlayFor(cs, { player = { MainJobSync = 10, Status = 'Idle' } });
    check('CH9 underlevel Legs rung -> slot empty', covLow and covLow.Legs, nil);
    check('CH10 low-level Main still resolves',      covLow and covLow.Main, 'Chocobo Wand');
    -- idle-only: Engaged/Dead stand the whole overlay down.
    check('CH11 engaged -> stands aside',
        dispatchM._chocoOverlayFor(cs, { player = { MainJobSync = 75, Status = 'Engaged' } }), nil);
    check('CH12 dead -> stands aside',
        dispatchM._chocoOverlayFor(cs, { player = { MainJobSync = 75, Status = 'Dead' } }), nil);
    check('CH13 disabled -> no overlay',
        dispatchM._chocoOverlayFor({ enabled = false }, { player = { MainJobSync = 75, Status = 'Idle' } }), nil);
    check('CH14 resolveVirtual dlac:AutoChoco Main', dispatchM._resolveVirtual('dlac:AutoChoco',
        { player = { MainJobSync = 75 } }, 'Main'), 'Chocobo Wand');
    check('CH15 resolveVirtual unclaimed choco slot -> nil', dispatchM._resolveVirtual('dlac:AutoChoco',
        { player = { MainJobSync = 75 } }, 'Ring1'), nil);
    dispatchM._autoOverride = nil;
end)();

-- ---------------------------------------------------------------------------
-- section GM: game-mode icon detection (feature/gamemode.lua)
-- Field truth 2026-07-18 Tavnazian Safehold (dlacprobe ICON dump): crystal
-- players (UCW Mindie idx 1107, CW Skincrawler idx 1055) carry RenderFlags4
-- 0x1000; Wings (Askar idx 1029) carries 0x4000; ACE (Tcb idx 1074) neither.
-- ---------------------------------------------------------------------------
(function()
    local gamemode = dofile('feature/gamemode.lua');

    AshitaCore = nil;
    check('GM1 headless get -> nil', gamemode.get(), nil);

    -- fake entity table straight from the field capture
    local flagsByIdx = {
        [1107] = 0x40001000,    -- Mindie (UCW, local in the capture)
        [1055] = 0x40001000,    -- Skincrawler (CW)
        [1029] = 0x41004000,    -- Askar (Wings)
        [1074] = 0x41000000,    -- Tcb (ACE)
    };
    local function ashitaWithIcons(selfIdx)
        local em = {
            GetRawEntity    = function(self, i) if flagsByIdx[i] ~= nil then return {}; end return nil; end,
            GetRenderFlags4 = function(self, i) return flagsByIdx[i]; end,
        };
        local party = { GetMemberTargetIndex = function(self, n) return selfIdx; end };
        return { GetMemoryManager = function(self)
            return {
                GetEntity = function(self) return em; end,
                GetParty  = function(self) return party; end,
            };
        end };
    end

    AshitaCore = ashitaWithIcons(1107);
    check('GM2 self (UCW capture) -> CW', gamemode.get(), 'CW');
    check('GM3 remote CW by idx -> CW', gamemode.get(1055), 'CW');
    check('GM4 Wings by idx', gamemode.get(1029), 'Wings');
    check('GM5 ACE by idx', gamemode.get(1074), 'ACE');
    check('GM6 unrendered idx -> nil', gamemode.get(1500), nil);

    AshitaCore = ashitaWithIcons(0);        -- empty party slot: no self index
    check('GM7 no self index -> nil', gamemode.get(), nil);

    -- Ashita hands back SIGNED dwords: a sign-bit flags word must normalize
    flagsByIdx[1107] = 0xC0001000 - 4294967296;
    AshitaCore = ashitaWithIcons(1107);
    check('GM8 negative dword normalized -> CW', gamemode.get(), 'CW');

    AshitaCore = nil;
end)();

-- ---------------------------------------------------------------------------
-- section NMP: native max MP (data/nativemp.lua)
-- Server-formula port (charutils.cpp CalculateStats MP + grades.cpp, stable
-- branch 2026-07-18). Expectations are HAND-computed from the server tables,
-- not from the module -- a table typo fails here. Field pin, FULLY resolved
-- (Henrik 2026-07-18: menu reads 10/10): Mindie Hume WHM75/SCH37 shows 724
-- naked = 614 formula + 100 merits (10 x 10, merit.cpp cap[75]) + 10 SCH-sub
-- Max MP Boost -- the trait rides health.modmp (DISPLAY); health.maxmp = 714.
-- ---------------------------------------------------------------------------
(function()
    local nmp = dofile('data/nativemp.lua');
    local g = nmp.get;

    -- the field pin: race D 10+3*59+4*15=247, WHM C 12+4*59+4*15=308,
    -- sub SCH D (10+3*36)/2=59 -> 614; +100 merit = maxmp 714 (the latent
    -- denominator; the on-screen 724 adds the DISPLAY-side SCH trait)
    check('NMP1 field pin Hume WHM75/SCH37 base', g(1, 3, 75, 20, 37), 614);
    check('NMP2 field pin + 10 merit levels = maxmp 714', g(1, 3, 75, 20, 37, 100), 714);
    check('NMP3 Hume female = same row', g(2, 3, 75, 20, 37), 614);

    check('NMP4 Taru BLM75/WHM37 (430+369+78)', g(5, 4, 75, 3, 37), 877);
    check('NMP5 no pool anywhere: Galka WAR75/NIN37', g(8, 1, 75, 13, 37), 0);
    -- main without MP, sub with: race rides the SUB level, halved
    check('NMP6 Hume NIN75/WHM37 (59+0+78)', g(1, 13, 75, 3, 37), 137);
    -- Galka G-grade half-point rate: 48.5+95+97 = 240.5 truncates like (int16)
    check('NMP7 truncation: Galka DRK75/BLM37', g(8, 8, 75, 4, 37), 240);

    check('NMP8 under 60, no sub: Elvaan RDM50 (106+157)', g(3, 5, 50), 263);
    check('NMP9 over-60 kink: Hume WHM61 (191+252)', g(1, 3, 61), 443);
    check('NMP10 level 1 Hume WHM (10+12)', g(1, 3, 1), 22);
    check('NMP11 slvl 0 = subless: Hume WHM75 (247+308)', g(1, 3, 75, 20, 0), 555);

    check('NMP12 nil race -> nil', g(nil, 3, 75), nil);
    check('NMP13 nil level -> nil', g(1, 3, nil), nil);

    AshitaCore = nil;
    check('NMP14 headless self -> nil', nmp.self(), nil);

    -- live-read seam: Taru female BLM75/WHM37 through the stubbed managers
    local player = {
        GetMainJob      = function(self) return 4; end,
        GetMainJobLevel = function(self) return 75; end,
        GetSubJob       = function(self) return 3; end,
        GetSubJobLevel  = function(self) return 37; end,
    };
    local em    = { GetRace = function(self, i) return (i == 1234) and 6 or nil; end };
    local party = { GetMemberTargetIndex = function(self, n) return 1234; end };
    AshitaCore = { GetMemoryManager = function(self)
        return {
            GetEntity = function(self) return em; end,
            GetParty  = function(self) return party; end,
            GetPlayer = function(self) return player; end,
        };
    end };
    check('NMP15 self() live reads -> Taru BLM75/WHM37', nmp.self(), 877);
    check('NMP16 self(meritMP) forwards', nmp.self(110), 987);

    AshitaCore = nil;
end)();

-- ---------------------------------------------------------------------------
-- section AO: Auto Oneiros Grip (dlac:AutoOneiros, engine v67)
-- Denominator (stable latent_effect_container.cpp + item_latents 18811 =
-- latent id 4 MP_UNDER_PERCENT): health.maxmp = CalculateStats' race/job/sub
-- formula + merit MP, NO gear (weapon/grip MP and Max MP Boost traits ride
-- health.MODMP -- the display -- never the denominator; BG-wiki's retail
-- visible-gear rule is a DIFFERENT latent id, commented out here). The
-- PERCENT is field truth, not repo truth: Henrik's tick test broke at
-- MP 357/358 on maxmp 714 = exactly 50.0%, equality ACTIVE -- live runs 50
-- where the repo sql says 75 (docs/server-questions.md #6). Threshold =
-- floor(base * 0.50), boundary inclusive. Usable merits cap at merit.cpp
-- cap[75] = 10 -> the resolver clamps. Mindie's shape (Hume WHM75/SCH37,
-- 10/10 merits): maxmp 714 -> fires at MP <= 357; meritless 614 -> 307.
-- ---------------------------------------------------------------------------
(function()
    local nmpM = package.loaded['dlac\\data\\nativemp'];   -- THE instance dispatch captured
    local rv = dispatchM._resolveVirtual;
    local ctx75 = { player = { MainJobSync = 75 } };

    -- live-reader stubs: Mindie's shape -- Hume(1) WHM75/SCH37
    local oldIdx, oldRace, oldJobs = nmpM.selfIndex, nmpM.readRace, nmpM.readJobs;
    nmpM.selfIndex = function() return 42; end
    nmpM.readRace  = function(idx) return (idx == 42) and 1 or nil; end
    nmpM.readJobs  = function() return 3, 75, 20, 37; end

    dispatchM._autoOverride = { oneiros = { name = 'Oneiros Grip', level = 75 }, mpMerits = 10 };

    TEST_PLAYER = { MP = 357 };
    check('AO1 field pin: MP 357 of maxmp 714 -> grip', rv('dlac:AutoOneiros', ctx75, 'Sub'), 'Oneiros Grip');
    TEST_PLAYER = { MP = 358 };
    local nm, why = rv('dlac:AutoOneiros', ctx75, 'Sub');
    check('AO2 field pin: 358 -> fallback', nm, nil);
    check('AO2b reason carries the threshold', string.find(tostring(why), '357', 1, true) ~= nil, true);
    -- over-cap merit input (sql headroom, hand-edited manifest): clamped to
    -- the usable 10 -- the threshold must NOT move
    dispatchM._autoOverride = { oneiros = { name = 'Oneiros Grip', level = 75 }, mpMerits = 15 };
    TEST_PLAYER = { MP = 357 };
    check('AO2c merit clamp: 15 acts as 10', rv('dlac:AutoOneiros', ctx75, 'Sub'), 'Oneiros Grip');
    TEST_PLAYER = { MP = 358 };
    check('AO2d merit clamp: threshold unmoved', (rv('dlac:AutoOneiros', ctx75, 'Sub')), nil);

    dispatchM._autoOverride = { oneiros = { name = 'Oneiros Grip', level = 75 }, mpMerits = 0 };
    TEST_PLAYER = { MP = 307 };
    check('AO3 meritless base 614 -> fires at 307', rv('dlac:AutoOneiros', ctx75, 'Sub'), 'Oneiros Grip');
    TEST_PLAYER = { MP = 308 };
    check('AO4 meritless 308 stays off', (rv('dlac:AutoOneiros', ctx75, 'Sub')), nil);

    -- second FIELD-VERIFIED shape (Henrik 2026-07-18, post-shutdown login):
    -- WHM75/BLM37, wire-learned 10 merits -> 652 + 100 = 752 -> aim 376,
    -- reported by /dl merits and MP-checked live. Pins the sub-swap re-aim.
    dispatchM._autoOverride = { oneiros = { name = 'Oneiros Grip', level = 75 }, mpMerits = 10 };
    nmpM.readJobs = function() return 3, 75, 4, 37; end   -- WHM75/BLM37
    TEST_PLAYER = { MP = 376 };
    check('AO13 field pin 2: /BLM37 base 752 -> grip at 376', rv('dlac:AutoOneiros', ctx75, 'Sub'), 'Oneiros Grip');
    TEST_PLAYER = { MP = 377 };
    check('AO14 field pin 2: 377 -> fallback', (rv('dlac:AutoOneiros', ctx75, 'Sub')), nil);
    nmpM.readJobs = function() return 3, 75, 20, 37; end  -- back to /SCH for anything below

    TEST_PLAYER = { MP = 100 };
    check('AO5 under the grip level -> unresolved',
        (rv('dlac:AutoOneiros', { player = { MainJobSync = 70 } }, 'Sub')), nil);

    dispatchM._autoOverride = { oneiros = false };
    check('AO6 not owned -> unresolved', (rv('dlac:AutoOneiros', ctx75, 'Sub')), nil);

    dispatchM._autoOverride = { oneiros = { name = 'Oneiros Grip', level = 75 } };
    nmpM.readRace = function() return 8; end               -- Galka...
    nmpM.readJobs = function() return 1, 75, 13, 37; end   -- ...WAR/NIN: no pool anywhere
    check('AO7 no native pool on this job -> unresolved', (rv('dlac:AutoOneiros', ctx75, 'Sub')), nil);

    nmpM.selfIndex = function() return nil; end            -- self unreadable (login settle)
    check('AO8 native unreadable -> unresolved', (rv('dlac:AutoOneiros', ctx75, 'Sub')), nil);

    -- the marker is a Lv75 ladder rung (the grip's level), composite form too
    check('AO9 virtualMinLevel = grip level', dispatchM.virtualMinLevel('dlac:AutoOneiros'), 75);
    check('AO10 composite form tolerated', dispatchM.virtualMinLevel('dlac:AutoOneiros|GenbusShield'), 75);
    -- the grip is one FIXED Lv75 item: a manifest that has not learned it yet
    -- still answers 75 -- never a Lv0 always-adopt wildcard (v68)
    dispatchM._autoOverride = {};
    check('AO10b unlearned manifest: still a Lv75 rung', dispatchM.virtualMinLevel('dlac:AutoOneiros'), 75);
    dispatchM._autoOverride = { oneiros = { name = 'Oneiros Grip', level = 75 } };

    nmpM.selfIndex, nmpM.readRace, nmpM.readJobs = oldIdx, oldRace, oldJobs;

    -- flatten pairing: the marker IS a grip -- a 2H main composes it with the
    -- slot's regular grip as fallback (a shield would itself be illegal under
    -- a 2H, so it can't serve); a 1H main vetoes the marker outright and the
    -- shield wins the slot (shared subSlotAllowed rule both ways)
    TEST_PLAYER = { MainJob = 'WHM', SubJob = 'SCH', MainJobSync = 75, SubJobSync = 37 };
    AshitaCore = ashitaWithDW(false);
    local s2H = utils.BuildDynamicSets({ Dynamic = { TP = {
        Main = { gsword2H }, Sub = { 'dlac:AutoOneiros', grip } } } });
    check('AO11 2H main: marker + grip fallback', s2H.TP and s2H.TP.Sub, 'dlac:AutoOneiros|PoleGrip');
    local s1H = utils.BuildDynamicSets({ Dynamic = { TP = {
        Main = { dagger1H }, Sub = { 'dlac:AutoOneiros', shield } } } });
    check('AO12 1H main: marker vetoed, shield wins', s1H.TP and s1H.TP.Sub, 'GenbusShield');
    AshitaCore = nil;

    dispatchM._autoOverride = nil;
    TEST_PLAYER = nil;
end)();

-- ---------------------------------------------------------------------------
-- section MW: merit auto-learn (feature/meritwatch.lua, s2c 0x08C)
-- Layout from the server's own packets/s2c/0x08c_merit.h: u16 merit_count,
-- u16 pad, then {u16 id, u8 next, u8 count} entries -- full menu chunks AND
-- the single-entry spend update parse identically. max_mp = merits.sql 66.
-- ---------------------------------------------------------------------------
(function()
    local mw = dofile('feature/meritwatch.lua');
    local function pkt(count, entries)
        local t = { string.char(0x8C, 0x00, 0x00, 0x00, count % 256, math.floor(count / 256), 0, 0) };
        for _, e in ipairs(entries) do
            t[#t + 1] = string.char(e[1] % 256, math.floor(e[1] / 256) % 256, e[2], e[3]);
        end
        return table.concat(t);
    end
    check('MW1 full form: max_mp found', mw.parse08C(pkt(3, { { 64, 5, 8 }, { 66, 7, 10 }, { 128, 3, 5 } })), 10);
    check('MW2 single-update form', mw.parse08C(pkt(1, { { 66, 9, 7 } })), 7);
    check('MW3 chunk without max_mp -> nil', mw.parse08C(pkt(2, { { 64, 5, 8 }, { 68, 1, 3 } })), nil);
    check('MW4 truncated claim reads safely', mw.parse08C(pkt(5, { { 64, 5, 8 } })), nil);
    check('MW5 garbage -> nil', mw.parse08C('xx'), nil);
    -- XiPackets usage 3: the LAST point removed -> index arrives as id|1
    -- (67) and the merit is back to zero, whatever the count byte claims
    check('MW5b full removal: odd index 67 -> 0', mw.parse08C(pkt(1, { { 67, 0, 9 } })), 0);
    check('MW5c other merits removal flag ignored', mw.parse08C(pkt(1, { { 129, 0, 4 } })), nil);

    -- the write path: same instance meritwatch will require at packet time
    local aui = dofile('ui/automationsui.lua');
    package.loaded['dlac\\ui\\automationsui'] = aui;
    check('MW10 getter nil before any write', aui.getMpMerits(), nil);
    check('MW6 setMpMerits clamps 15 -> 10 + reports change', aui.setMpMerits(15), true);
    check('MW7 clamped value current: 10 = no change', aui.setMpMerits(10), false);
    check('MW11 getter reads the clamped value', aui.getMpMerits(), 10);
    mw.onMeritPacket(pkt(1, { { 66, 0, 4 } }));
    check('MW8 packet write landed (4 = no change now)', aui.setMpMerits(4), false);
    check('MW9 session mirror holds the wire count', mw.learned, 4);
    check('MW12 getter tracks the packet write', aui.getMpMerits(), 4);
    package.loaded['dlac\\ui\\automationsui'] = nil;
end)();

-- ---------------------------------------------------------------------------
-- section MS: Sets-tab mode sections (gear/gearfmt.lua modeSections)
-- Henrik 2026-07-18: mode ladders (many Caster rungs + many Club rungs in one
-- Main list) drown the flat display. A mode gating 2+ rows earns a collapsed
-- section; a row whose EVERY gate is sectioned leaves the root; a row ungated
-- or alone on ANY gate stays in the root (and still shows under its sectioned
-- gates); an OR list means membership in every sectioned gate.
-- ---------------------------------------------------------------------------
(function()
    local gf = dofile('gear/gearfmt.lua');
    check('MS0 modeSections exported', type(gf.modeSections), 'function');
    local A = { rec = { Name = 'Yew Wand',      Level = 18 }, mode = 'Weapon:Caster' };
    local B = { rec = { Name = 'Chestnut Wand', Level = 30 }, mode = { 'Weapon:Caster', 'Weapon:Club' } };
    local C = { rec = { Name = 'Warp Cudgel',   Level = 51 }, mode = { 'weapon:club', 'DT' } };  -- spelling drift + a solo gate
    local D = { rec = { Name = 'Pilgrim Wand',  Level = 7  } };                                  -- ungated
    local E = { rec = { Name = 'Kraken Club',   Level = 63 }, mode = 'Solo:Only' };              -- solo gate only
    local root, secs = gf.modeSections({ A, B, C, D, E });
    local function has(list, x) for _, v in ipairs(list) do if v == x then return true; end end return false; end
    check('MS1 two sections form (caster, club)', #secs, 2);
    check('MS2 alpha order + first-seen spelling names', secs[1].name .. '/' .. secs[2].name, 'Weapon:Caster/Weapon:Club');
    check('MS3 caster section holds its two rows', has(secs[1].items, A) and has(secs[1].items, B), true);
    check('MS4 club groups case-insensitively (B + drifted C)', has(secs[2].items, B) and has(secs[2].items, C), true);
    check('MS5 ungated row stays in the root', has(root, D), true);
    check('MS6 solo-gated row stays in the root', has(root, E), true);
    check('MS7 fully-sectioned rows leave the root', has(root, A) or has(root, B), false);
    check('MS8 sectioned + solo gate -> root AND section', has(root, C) and has(secs[2].items, C), true);
    check('MS9 root keeps display order', root[1] == C and root[2] == D and root[3] == E, true);
    check('MS10 header ladder ascends', table.concat(secs[1].levels, ','), '18,30');
    check('MS11 ladder sorts across spelling drift', table.concat(secs[2].levels, ','), '30,51');
    -- a duplicated gate inside ONE row's OR list must not fake a 2-row section
    local F = { rec = { Name = 'X', Level = 5 }, mode = { 'Zerg', 'zerg' } };
    local r2, s2 = gf.modeSections({ F });
    check('MS12 dup gate in one row makes no section', #s2, 0);
    check('MS13 ...and that row stays in the root', r2[1], F);
    -- two rows at the SAME item level: one ladder entry, not two
    local G1 = { rec = { Name = 'G1', Level = 40 }, mode = 'M' };
    local G2 = { rec = { Name = 'G2', Level = 40 }, mode = 'M' };
    local r3, s3 = gf.modeSections({ G1, G2 });
    check('MS14 same-level rows dedup in the ladder', table.concat(s3[1].levels, ','), '40');
    check('MS15 ...and the root is empty (both rows sectioned)', #r3, 0);
    -- degenerate inputs stay safe
    local r4, s4 = gf.modeSections(nil);
    check('MS16 nil input -> empty root + no sections', #r4 + #s4, 0);

    -- stripGate: the section x removes ONE gate, never the row (Henrik
    -- 2026-07-18: Harpoon gated Base + Polearm lost the whole row to one x).
    check('MS17 stripGate exported', type(gf.stripGate), 'function');
    check('MS18 pair loses one -> the survivor as a plain string',
        gf.stripGate({ 'Weapon:Base', 'Weapon:Polearm' }, 'weapon:polearm'), 'Weapon:Base');
    check('MS19 sole gate strips to nil (row turns unconditional)',
        gf.stripGate('Weapon:Polearm', 'weapon:polearm'), nil);
    check('MS20 case-insensitive match', gf.stripGate('WEAPON:Polearm', 'weapon:polearm'), nil);
    local left = gf.stripGate({ 'A', 'B', 'C' }, 'b');
    check('MS21 three gates keep the other two, still a list',
        type(left) == 'table' and left[1] .. '/' .. left[2], 'A/C');
    check('MS22 unrelated key is a no-op', gf.stripGate('DT', 'weapon:polearm'), 'DT');
end)();

-- ---------------------------------------------------------------------------
-- section PM: pet-channel gear stats (petmods.lua -> oracle.petStats -> gearfmt)
-- The server grants pet-targeted gear stats (Drachen Brais "Wyvern: HP+10%")
-- through item_mods_pet -- a channel the live API NEVER serializes, so these
-- stats exist beside catalog Stats in data/petmods.lua (tools/gen_petmods.py).
-- The ORACLE is the one door that answers them (petStats -- a deliberately
-- SEPARATE answer from stats(): pet values never fold into master stats, the
-- golden gate pins that); gearfmt only composes the display. Pins: the
-- generated table's field-case rows, the door's answer, the display composition
-- (petLines for tooltips, statSummary's leftover-budget tokens), and -- via a
-- package.loaded swap, honoured because the oracle requires FRESH each call --
-- that the display truly flows THROUGH the door, not a private copy. Since
-- 07-22 evening the channel is also PRICED: petScoreStats ('Pet:' namespace,
-- All + best named type), petStatKeys (the stat-menu source), statdefs' Pet:
-- namespace and gearoptim's pricing/negation are pinned below (PM17+).
-- ---------------------------------------------------------------------------
(function()
    local pm = dofile('data/petmods.lua');
    check('PM0 petmods loads', type(pm), 'table');
    check('PM1 Drachen Brais wyvern HP% (the field case)',
        pm[14227] ~= nil and pm[14227].Wyvern ~= nil and pm[14227].Wyvern.HPP, 10);
    check('PM2 Drachen Brais +1 rides the ladder',
        pm[15574] ~= nil and pm[15574].Wyvern ~= nil and pm[15574].Wyvern.HPP, 15);
    check('PM3 Wyvern Mail hidden wyvern HP',
        pm[14405] ~= nil and pm[14405].Wyvern ~= nil and pm[14405].Wyvern.HP, 65);
    check('PM4 ...and its HHP partner stat', pm[14405] ~= nil and pm[14405].Wyvern.HHP, 65);
    check('PM5 all-pets rows keyed All (Sabong DA)',
        pm[10299] ~= nil and pm[10299].All ~= nil and pm[10299].All.DoubleAttack, 2);

    -- the door's answer (oracle.petStats): rec or bare id, nil-safe
    package.loaded['dlac\\data\\petmods'] = pm;
    local oracle = package.loaded['dlac\\gear\\gearoracle'];
    check('PM6 oracle answers pet stats', type(oracle.petStats), 'function');
    check('PM6a by bare id', oracle.petStats(14227).Wyvern.HPP, 10);
    check('PM6b by record', oracle.petStats({ Id = 14405 }).Wyvern.HP, 65);
    check('PM6c unknown id -> nil', oracle.petStats(4096), nil);
    check('PM6d nil -> nil', oracle.petStats(nil), nil);

    -- display composition through gearfmt (which asks the oracle)
    local gf = dofile('gear/gearfmt.lua');
    check('PM7 petLines exported', type(gf.petLines), 'function');
    local lines = gf.petLines({ Id = 14227 });
    check('PM7a one line per pet type', #lines, 1);
    check('PM8 composed tooltip line', lines[1], 'Wyvern: HPP+10');
    check('PM9 All reads as Pet', gf.petLines({ Id = 10299 })[1], 'Pet: DoubleAttack+2');
    check('PM10 priority order inside a line (HP first, rest alpha)',
        gf.petLines({ Id = 14405 })[1], 'Wyvern: HP+65 HHP+65');
    check('PM11 item without pet data -> empty list', #gf.petLines({ Id = 4096 }), 0);
    check('PM12 nil rec safe', #gf.petLines(nil), 0);

    -- statSummary: pet tokens ride ONLY the leftover <=4-token budget
    gf.configure({ effStats = function(rec) return rec.Stats; end });
    check('PM13 row summary appends a pet token',
        gf.statSummary({ Id = 14227, Stats = { DEF = 27 } }), 'DEF+27 Wyvern:HPP+10');
    check('PM14 a full budget leaves pet tokens out',
        gf.statSummary({ Id = 14227, Stats = { DEF = 1, HP = 1, MP = 1, Accuracy = 1 } }),
        'DEF+1 HP+1 MP+1 Accuracy+1');

    -- THE DOOR PROOF: swap the data table under the oracle; the already-loaded
    -- gearfmt must see the swap (it holds no private petmods binding -- the
    -- oracle's fresh-each-call require is what makes this observable).
    package.loaded['dlac\\data\\petmods'] = { [777] = { Wyvern = { HP = 1 } } };
    check('PM15 petLines flows through the door (swap honoured)',
        gf.petLines({ Id = 777 })[1], 'Wyvern: HP+1');
    check('PM16 ...and the old table is truly gone', #gf.petLines({ Id = 14227 }), 0);

    -- WEIGHTS-facing answers (2026-07-22, "pet stats become stat weights"): the
    -- pet channel FLATTENED under 'Pet:' keys (petScoreStats) + the stat-menu
    -- key list (petStatKeys). The flatten rule is the pin that matters: per stat
    -- All + the BEST named type -- a pet is exactly ONE type, so summing across
    -- named types would credit mutually exclusive pets. Same fresh-each-call
    -- door, so a swap table pins the rule exactly.
    package.loaded['dlac\\data\\petmods'] = {
        [1] = { All = { Haste = 2 }, Wyvern = { Haste = 3 }, Avatar = { Haste = 1, Attack = 4 } },
        [2] = { Automaton = { RangedAccuracy = 5 } },
    };
    check('PM17 petScoreStats: All + BEST named type, never the cross-pet sum',
        oracle.petScoreStats(1)['Pet:Haste'], 5);
    check('PM17a a stat one named type carries', oracle.petScoreStats(1)['Pet:Attack'], 4);
    check('PM17b named-only item', oracle.petScoreStats(2)['Pet:RangedAccuracy'], 5);
    check('PM17c keys are namespaced -- no bare master key ever leaks',
        oracle.petScoreStats(1).Haste, nil);
    check('PM17d rec form works', oracle.petScoreStats({ Id = 2 })['Pet:RangedAccuracy'], 5);
    check('PM17e non-pet item -> nil', oracle.petScoreStats(4096), nil);
    check('PM17f nil-safe', oracle.petScoreStats(nil), nil);
    check('PM18 petStatKeys: distinct + sorted (the stat-menu source)',
        table.concat(oracle.petStatKeys(), ','), 'Attack,Haste,RangedAccuracy');
    local _, ptypes = oracle.petStatKeys();
    check('PM18a ...second return names the carrying pet types (search terms:',
        table.concat(ptypes.Haste, ','), 'All,Avatar,Wyvern');
    check('PM18b ...per stat, sorted ("wyvern" finds Pet:HP% -- the field case)',
        table.concat(ptypes.RangedAccuracy, ','), 'Automaton');

    -- statdefs speaks the namespace: derived label/section, canon keeps the prefix
    local sd = dofile('data/statdefs.lua');
    check('PM19 Pet: label derives from the inner stat', sd.get('Pet:Haste').label, 'Pet: Haste');
    check('PM19a ...and lands in the Pet section', sd.get('Pet:Haste').section, 'Pet');
    check('PM19b inner aliases resolve through (MagicAttackBonus -> MAB)',
        sd.get('Pet:MagicAttackBonus').label, 'Pet: ' .. sd.get('MagicAttackBonus').label);
    check('PM20 canon: case-insensitive prefix, canonical inner',
        sd.canon('PET:Haste'), 'Pet:Haste');
    check('PM20a canon: inner alias canonicalizes', sd.canon('Pet:MagicAttackBonus'), 'Pet:MAB');
    check('PM20b a non-pet unknown still passes through', sd.canon('NoSuchStat'), 'NoSuchStat');

    -- and the scorer prices the namespace: exact keys, case-insensitive spelling
    -- (statSpellings learns 'pet:haste' from the oracle), negative-good inner
    -- stats keep their lower-is-better rule (Pet:PDT scores like PDT).
    local optim = dofile('gear/gearoptim.lua');
    check('PM21 score prices a Pet: weight',
        optim.score({ ['Pet:Haste'] = 5 }, { ['Pet:Haste'] = { perUnit = 2 } }), 10);
    check('PM21a typed-lowercase weight still hits (spelling table via the oracle)',
        optim.score({ ['Pet:Haste'] = 5 }, { ['pet:haste'] = { perUnit = 2 } }), 10);
    check('PM21b Pet:PDT is negative-good like PDT (-3 taken as +3 goodness)',
        optim.score({ ['Pet:PDT'] = -3 }, { ['Pet:PDT'] = { perUnit = 1 } }), 3);
    check('PM21c a Pet: weight never touches the master stat',
        optim.score({ Haste = 9 }, { ['Pet:Haste'] = { perUnit = 2 } }), 0);

    package.loaded['dlac\\data\\petmods'] = nil;
end)();

-- ---------------------------------------------------------------------------
-- section MC: dead mode-condition sweep (triggersui._modeCondRefs)
-- Henrik 2026-07-18: editing a cycle left nonexistent 'Name:Value' gates on
-- weapons/rules. The sweep takes a whole mode ('X' -> 'X' + every 'X:*') or
-- ONE value ('X:V', exact); v54 legs are honoured -- a rule fires on (ALL of
-- when) OR (ANY whenAny entry), so: a mode list loses just the dead name; a
-- leg whose mode list empties dies (an & leg collapses to OR-only, a | entry
-- is removed); a rule with no live leg is removed whole.
-- ---------------------------------------------------------------------------
(function()
    local tui = dofile('ui/triggersui.lua');
    check('MC0 sweep seam exported', type(tui._modeCondRefs), 'function');
    local f = tui._modeCondRefs;

    -- whole-mode target: bare gate, valued gate, list gate
    local d = { Default = {
        { when = { mode = 'Inc' },              set = 'A' },
        { when = { mode = 'Inc:Wpn' },          set = 'B' },
        { when = { mode = { 'Inc', 'DT' } },    set = 'C' },
        { when = { mode = 'DT' },               set = 'D' },
    } };
    local r = f(d, 'Inc', true);
    check('MC1 whole-mode: bare + valued gates removed, list trimmed', r.removedRules .. '/' .. r.editedRules, '2/1');
    check('MC2 survivors: trimmed rule + unrelated rule', #d.Default, 2);
    check('MC3 list gate collapses to the surviving mode (plain string)', d.Default[1].when.mode, 'DT');
    check('MC4 unrelated DT rule untouched', d.Default[2].set, 'D');

    -- value-level target: exact only -- sibling values and the BARE name survive
    d = { Default = {
        { when = { mode = 'Weapon:Club' },                     set = 'A' },
        { when = { mode = 'weapon:club' },                     set = 'B' },   -- case drift
        { when = { mode = 'Weapon:Caster' },                   set = 'C' },
        { when = { mode = 'Weapon' },                          set = 'D' },
        { when = { mode = { 'Weapon:Club', 'Weapon:Caster' }}, set = 'E' },
    } };
    r = f(d, 'Weapon:Club', true);
    check('MC5 value target: both spellings removed, list trimmed', r.removedRules .. '/' .. r.editedRules, '2/1');
    check('MC6 sibling value survives', d.Default[1].set, 'C');
    check('MC7 bare cycle gate survives a value removal', d.Default[2].set, 'D');
    check('MC8 trimmed list keeps the sibling', d.Default[3].when.mode, 'Weapon:Caster');

    -- load-bearing: the mode was one of several & conditions -> rule removed whole
    d = { Default = { { when = { mode = 'X', spell = 'Cure' }, set = 'A' } } };
    r = f(d, 'X', true);
    check('MC9 load-bearing & rule removed despite other conditions', #d.Default .. '/' .. r.removedRules, '0/1');

    -- v54 legs
    d = { Default = {
        { when = { spell = 'Cure' }, whenAny = { { mode = 'X' }, { buff = 'Sleep' } }, set = 'A' },
        { when = {},                 whenAny = { { mode = 'X' } },                     set = 'B' },
        { when = { mode = 'X' },     whenAny = { { buff = 'Sleep' } },                 set = 'C' },
        { when = { mode = 'X' },     whenAny = { { mode = 'X:1' } },                   set = 'D' },
        { when = { spell = 'Fire' }, whenAny = { { mode = 'X' } },                     set = 'E' },
        { when = {},                 whenAny = { { mode = { 'X', 'DT' } } },           set = 'F' },
    } };
    r = f(d, 'X', true);
    check('MC10 counts: OR-only + both-legs-dead removed, rest edited', r.removedRules .. '/' .. r.editedRules, '2/4');
    check('MC11 dead | entry removed, sibling entry stays', #d.Default[1].whenAny .. '/' .. tostring(d.Default[1].whenAny[1].buff), '1/Sleep');
    check('MC12 dead & leg collapses to OR-only (when emptied, | kept)',
        next(d.Default[2].when) == nil and d.Default[2].whenAny[1].buff, 'Sleep');
    check('MC13 emptied whenAny drops to nil, & leg carries on',
        d.Default[3].set == 'E' and d.Default[3].whenAny, nil);
    check('MC14 | entry mode list keeps its other mode', d.Default[4].whenAny[1].mode, 'DT');
    check('MC15 the removed rules are the right ones', (function()
        for _, rule in ipairs(d.Default) do
            if rule.set == 'B' or rule.set == 'D' then return rule.set; end
        end
        return true;
    end)(), true);

    -- report mode: counts without mutating
    d = { Default = {
        { when = { mode = 'X' }, set = 'A' },
        { when = { spell = 'Cure' }, whenAny = { { mode = 'X' } }, set = 'B' },
    } };
    r = f(d, 'X', false);
    check('MC16 report lists every referencing rule', #r.rules, 2);
    check('MC17 report mutates nothing', #d.Default == 2 and d.Default[1].when.mode .. '/' .. tostring(d.Default[2].whenAny[1].mode), 'X/X');
    check('MC18 near-name mode never matches (Incog vs Inc)',
        #f({ Default = { { when = { mode = 'Incog' }, set = 'A' } } }, 'Inc', false).rules, 0);

    -- issue #126: the sweep extends into CASES with the SAME narrow/empty/remove
    -- ladder -- a case's mode list narrows, a case whose load-bearing leg empties
    -- is removed whole, and a rule with nothing left (body + all cases gone) goes.
    d = { Default = {
        -- (1) an & case's mode list narrows, keeping the sibling; rule survives
        { when = { magictype = 'Black Magic' }, cases = { { op = '&', when = { mode = { 'X', 'DT' } } } }, set = 'A' },
        -- (2) an & case whose ONLY content is the dead mode -> case removed; body
        --     (magicType) keeps the rule alive
        { when = { magictype = 'Black Magic' }, cases = { { op = '&', when = { mode = 'X' } } }, set = 'B' },
        -- (3) body IS the dead mode + the only case dies too -> rule removed whole
        { when = { mode = 'X' }, cases = { { op = '|', when = { mode = 'X' } } }, set = 'C' },
        -- (4) empty body, a single | case on the dead mode -> nothing left -> removed
        { when = {}, cases = { { op = '|', when = { mode = 'X' } } }, set = 'D' },
    } };
    r = f(d, 'X', true);
    check('MC19 case sweep: removed 2 (C,D), edited 2 (A,B)', r.removedRules .. '/' .. r.editedRules, '2/2');
    check('MC20 & case mode list narrows to the sibling', d.Default[1].cases[1].when.mode, 'DT');
    check('MC21 emptied case dropped, body keeps the rule',
        d.Default[2].cases == nil and d.Default[2].set, 'B');
    check('MC22 the survivors are exactly A and B', (function()
        for _, rule in ipairs(d.Default) do if rule.set == 'C' or rule.set == 'D' then return rule.set; end end
        return #d.Default;
    end)(), 2);

    -- report mode counts a case reference without mutating it
    local rc = f({ Default = { { when = { magictype = 'Black Magic' },
        cases = { { op = '|', when = { mode = 'X' }, whenAny = { { element = 'Fire' } } } }, set = 'Z' } } }, 'X', false);
    check('MC23 report mode names a case reference', #rc.rules, 1);

    -- RS: set-rename reference rewrite (2026-07-20, the Sets tab Rename).
    -- EXACT match only; string and multi-set list actions; every handler
    -- section including Default's mode overlays; equip rules untouched.
    check('RS0 rename seam exported', type(tui._renameSetRefsIn), 'function');
    local rd = {
        Default = {
            { when = { mode = 'DT' }, set = 'Idle' },
            { when = { mode = 'X' },  set = { 'Idle', 'Tp' } },
        },
        Midcast = {
            { when = { name = 'Cure' }, set = 'Idle' },
            { when = { name = 'Dia' },  set = 'idle' },   -- case drift = already broken; stays visibly broken
            { when = { group = 'G' },   equip = { Head = 'Hat' } },
        },
    };
    local rsn = tui._renameSetRefsIn(rd, 'Idle', 'Field');
    check('RS1 three rules rewritten', rsn, 3);
    check('RS2 string action follows', rd.Default[1].set, 'Field');
    check('RS3 list entry follows, sibling kept', rd.Default[2].set[1] .. '/' .. rd.Default[2].set[2], 'Field/Tp');
    check('RS4 other sections follow too', rd.Midcast[1].set, 'Field');
    check('RS5 case-drifted ref untouched', rd.Midcast[2].set, 'idle');
    check('RS6 equip rule untouched', rd.Midcast[3].equip.Head, 'Hat');
    check('RS7 no match = zero, nothing mutated', tui._renameSetRefsIn(rd, 'Nope', 'X'), 0);
end)();

-- ---------------------------------------------------------------------------
-- LOC. location service (v45) -- the central town/zone answer (feature/
--      location.lua) behind the lockstyle Disable-in-town option (and a future
--      home for the inTown read). Town membership is data/zones.lua's .town
--      flag; the live read is injectable (M.reader) and nils out on failure.
-- ---------------------------------------------------------------------------
(function()
    local loc = dofile('feature/location.lua');
    check('LOC0 module loads', type(loc), 'table');
    -- isTown: the curated town set (server CITY + Nashmau - combat zones).
    check('LOC1 isTown city (S. San dOria 230)',      loc.isTown(230), true);
    check('LOC2 isTown Nashmau 53 (curated ADD)',     loc.isTown(53), true);
    check('LOC3 isTown Celennia 284 (Wings hub)',     loc.isTown(284), true);
    check('LOC4 isTown Sealions Den 32 (curated DROP)', loc.isTown(32), false);
    check('LOC5 isTown field zone (Phanauet 1)',      loc.isTown(1), false);
    check('LOC6 isTown nil-safe',                     loc.isTown(nil), false);
    -- inTown() folds the live read through isTown; reader is the injected seam.
    loc.reader = function() return 230; end;
    check('LOC7 inTown true in a city', loc.inTown(), true);
    check('LOC8 zoneId reads the seam', loc.zoneId(), 230);
    loc.reader = function() return 1; end;
    check('LOC9 inTown false in the field', loc.inTown(), false);
    loc.reader = function() return nil; end;
    check('LOC10 inTown nil on unknown zone', loc.inTown(), nil);
    check('LOC11 zoneId nil on unknown', loc.zoneId(), nil);
end)();

-- ---------------------------------------------------------------------------
-- LG. lockstyle zone-in guard (v43) -- the pure decision half of the packet
--     watcher in feature\lockstyle.lua. Field-pinned 2026-07-19 (/probe ls):
--     the retail client re-asserts ITS private lockstyle flag to the server
--     after every zone-in -- CONTINUE when it thinks the lock is on, DISABLE
--     when it thinks it is off -- and dlac's injected SET never turns that
--     flag on, so the client killed our lockstyle ~0.6s after each zone-in.
--     The guard blocks exactly that DISABLE: in-window, lockstyle live, not
--     player-typed. Everything else must pass or retire the live flag.
-- ---------------------------------------------------------------------------
(function()
    local ls = dofile('feature/lockstyle.lua');
    check('LG0 _lsGuard exported', type(ls._lsGuard), 'function');
    if type(ls._lsGuard) ~= 'function' then return; end
    local f = ls._lsGuard;
    local FAR = -1e9;   -- "never happened" stamp
    -- mode, now, zoneInAt, active, userOffAt
    check('LG1 SET arms the guard',    f(3, 100, FAR, false, FAR), 'activate');
    check('LG2 native ENABLE adopts: guard arms, box memory must clear (worn gear stomped the box)',
        f(4, 100, FAR, false, FAR), 'adopt');
    check('LG3 THE BUG: in-window DISABLE while live -> blocked',
        f(0, 100.6, 100, true, FAR), 'block');
    check('LG4 late unasked DISABLE -> guard yields, keep memory survives',
        f(0, 111, 100, true, FAR), 'deactivate');
    check('LG5 window edge: 10s is already late', f(0, 110, 100, true, FAR), 'deactivate');
    check('LG6 in-window but nothing live -> pass through',
        f(0, 100.6, 100, false, FAR), 'deactivate');
    check('LG7 player typed /lockstyle off -> RETIRE, never blocked, box memory clears',
        f(0, 100.6, 100, true, 100.5), 'retire');
    check('LG7b typed off outside any window is still retire', f(0, 500, 100, false, 499), 'retire');
    check('LG8 stale intent stamp does not shield the auto-disable',
        f(0, 100.6, 100, true, 90), 'block');
    check('LG9 CONTINUE passes untouched', f(1, 100.6, 100, true, FAR), 'pass');
    check('LG10 QUERY passes untouched',   f(2, 100.6, 100, true, FAR), 'pass');
    check('LG11 garbage mode passes',      f(-1, 100.6, 100, true, FAR), 'pass');
    check('LG12 nil stamps never block an inactive guard', f(0, 5, nil, false, nil), 'deactivate');
    -- v45 disable-in-town: with suppressTown, dlac WANTS the lock off in a town,
    -- so ANY disable -> 'suppress' (let through, keep the box, book no keep-heal),
    -- EXCEPT a player-typed off, which still 'retire's (explicit intent wins).
    check('LG12a town-suppress: in-window disable is NOT blocked -> suppress',
        f(0, 100.6, 100, true, FAR, true), 'suppress');
    check('LG12b town-suppress: out-of-window disable -> suppress, not deactivate (no keep-heal)',
        f(0, 500, 100, false, FAR, true), 'suppress');
    check('LG12c town-suppress still yields to a typed /lockstyle off -> retire',
        f(0, 100.6, 100, true, 100.5, true), 'retire');
    check('LG12d suppressTown does not disturb SET', f(3, 100, FAR, false, FAR, true), 'activate');
    check('LG12e _wantTownOff = townOff AND inTown',   ls._wantTownOff(true, true), true);
    check('LG12f _wantTownOff false when not in town',  ls._wantTownOff(true, false), false);
    check('LG12g _wantTownOff false when option off',   ls._wantTownOff(false, true), false);
    check('LG12h _wantTownOff false on unknown (nil)',  ls._wantTownOff(true, nil), false);
    -- v46 town lockstyle pick: 'off' (disable-in-town) | a box number | nil.
    check('LG12i townPick nil when not in town',    ls._townPick(false, true, 5), nil);
    check('LG12j townPick off-mode is off',         ls._townPick(true, true, nil), 'off');
    check('LG12k townPick replace-mode = the box',  ls._townPick(true, nil, 5), 5);
    check('LG12l townPick None (no options) = nil', ls._townPick(true, nil, nil), nil);
    check('LG12m townPick off beats box (safety)',  ls._townPick(true, true, 5), 'off');
    check('LG12n townPick unknown zone (nil) = nil', ls._townPick(nil, nil, 5), nil);
    -- v46 leave-town clear: drop the town box only when there's no base to restore.
    check('LG12o townLeaveClear: had a box, no base -> clear',   ls._townLeaveClear(5, nil), true);
    check('LG12p townLeaveClear: has a base -> restore not clear', ls._townLeaveClear(5, 3), false);
    check('LG12q townLeaveClear: off-mode (not a box) -> no clear', ls._townLeaveClear('off', nil), false);
    check('LG12r townLeaveClear: no prior town style -> no clear', ls._townLeaveClear(nil, nil), false);
    check('LG13 user-off stamp is exported for the command handler',
        type(ls._guardUserOff), 'function');

    -- v44 keep-on-subjob: the option's storage seams. The game clears style
    -- lock server-side on ANY job change (0x100 handler), so this one is a
    -- re-apply, not a block -- the pump half is live-only; the pure seams are
    -- the serializer, the loader default and the job-entry filter.
    local txt = ls._serialize({ active = 2, keepSub = true, onload = {}, slots = {} });
    check('LG14 serializer writes keepSub', txt:find('keepSub = true', 1, true) ~= nil, true);
    local back = (loadstring or load)(txt)();
    check('LG15 round-trip keeps it', back.keepSub, true);
    check('LG16 absent option is not written',
        ls._serialize({ active = 1, onload = {}, slots = {} }):find('keepSub = true', 1, true), nil);
    local ed = ls._entryData({ active = 1, slots = {}, onload = { DRK = 2 }, keepSub = true }, 'DRK');
    check('LG17 _entryData carries the option whole', ed.keepSub, true);
    check('LG18 _entryData without it stays absent',
        ls._entryData({ active = 1, slots = {}, onload = {} }, 'DRK').keepSub, nil);
    -- v46 townBox rides the same storage seams as keepSub/townOff.
    check('LG18a serializer writes townBox',
        ls._serialize({ active = 1, townBox = 7, onload = {}, slots = {} }):find('townBox = 7', 1, true) ~= nil, true);
    check('LG18b round-trip keeps townBox',
        ((loadstring or load)(ls._serialize({ active = 1, townBox = 7, onload = {}, slots = {} }))()).townBox, 7);
    check('LG18c _entryData carries townBox',
        ls._entryData({ active = 1, townBox = 7, slots = {}, onload = {} }).townBox, 7);
    check('LG18d absent townBox writes no field (header note aside)',
        ls._serialize({ active = 1, onload = {}, slots = {} }):find('townBox = %d'), nil);
    check('LG19 guard-arm (the subjob-flip window) exported for the pump',
        type(ls._guardArm), 'function');

    -- round 3: the 0x100 job-change packet is the keep trigger of record --
    -- it leaves BEFORE the client's DISABLE (field capture 07-19 11:27), so
    -- arming off it wins the race the memory poll lost. 0 = unchanged field.
    local k = ls._jobPktKind;
    check('LG20 _jobPktKind exported', type(k), 'function');
    if type(k) == 'function' then
        check('LG21 sub-only change (incl. re-selecting the same sub)', k(0, 5), 'sub');
        check('LG22 main change is not ours to keep', k(7, 0), 'main');
        check('LG23 main+sub together is still a main change', k(7, 5), 'main');
        check('LG24 nothing changed', k(0, 0), 'none');
        check('LG25 nil-safe', k(nil, nil), 'none');
    end

    -- round 6: the queue sites write the keep memory directly -- a command
    -- queued from the addon's own state never re-enters that state's command
    -- event (field: 'keep4: box -' after button applies), so the event
    -- observation covers only hand-typed applies.
    check('LG32 _noteApplied exported', type(ls._noteApplied), 'function');
    if type(ls._noteApplied) == 'function' then
        ls._noteApplied(9);
        check('LG33 the queue site writes what the readout reads', ls._lastBox(), 9);
        ls._noteApplied('nonsense');
        check('LG34 a non-number never corrupts the memory', ls._lastBox(), 9);
    end

    -- round 4: the unasked DISABLE itself books the heal (field 11:34 -- it
    -- precedes the 0x100 on the wire, so round 3's arm-first plan was
    -- backwards; the kill is the one event every capture shows).
    local h = ls._keepHeal;
    check('LG26 _keepHeal exported', type(h), 'function');
    if type(h) == 'function' then
        check('LG27 unasked disable + keep on + box remembered -> heal', h('deactivate', true, 7), true);
        check('LG28 player-meant retire never heals',   h('retire', true, 7), false);
        check('LG29 keep off -> no heal',               h('deactivate', false, 7), false);
        check('LG30 no box remembered -> no heal',      h('deactivate', true, nil), false);
        check('LG31 blocked disable needs no heal',     h('block', true, 7), false);
    end
end)();

-- ---------------------------------------------------------------------------
-- LGF. keep-on-subjob FULL FLOW -- the whole addon-state chain driven
--      headlessly through the REAL registered handlers, in the exact wire
--      order of the 11:34 field capture (client DISABLE first, 0x100 second,
--      player struct flips after). Born in field round 4: every pure seam
--      was green while the assembled chain sat unproven -- this is the
--      assembled chain. Fixture: tests\fixtures\keepflow (legacy-tier file,
--      box 3, keepSub on).
-- ---------------------------------------------------------------------------
(function()
    local savedReg, savedClock, savedCore = ashita.events.register, os.clock, AshitaCore;
    local savedProf = package.loaded['dlac\\profiles'];
    package.loaded['dlac\\profiles'] = nil;   -- force the legacy-tier read (restored below)

    local handlers, queued = {}, {};
    ashita.events.register = function(ev, nm, fn) handlers[ev .. '/' .. nm] = fn; end
    local t = { v = 100 };
    os.clock = function() return t.v; end
    local subId = 1;   -- WAR -> RDM at the "moogle"
    local ABBR = { [1] = 'WAR', [5] = 'RDM', [8] = 'DRK' };
    AshitaCore = {
        GetInstallPath = function() return 'tests\\fixtures\\keepflow\\'; end,
        GetMemoryManager = function()
            return {
                GetParty = function() return {
                    GetMemberName = function() return 'Testy'; end,
                    GetMemberServerId = function() return 1234; end,
                }; end,
                GetPlayer = function() return {
                    GetMainJob = function() return 8; end,
                    GetSubJob = function() return subId; end,
                }; end,
            };
        end,
        GetResourceManager = function()
            return { GetString = function(_, _, id) return ABBR[id]; end };
        end,
        GetChatManager = function()
            return { QueueCommand = function(_, _, c) queued[#queued + 1] = c; end };
        end,
    };

    local ls = dofile('feature/lockstyle.lua');
    local cmd, pout, pin = handlers['command/dlac-lockstyle'],
                           handlers['packet_out/dlac-lockstyle-pout'],
                           handlers['packet_in/dlac-lockstyle-pin'];
    check('LGF0 all three handlers registered', cmd ~= nil and pout ~= nil and pin ~= nil, true);
    if cmd == nil or pout == nil or pin == nil then
        ashita.events.register, os.clock, AshitaCore = savedReg, savedClock, savedCore;
        package.loaded['dlac\\profiles'] = savedProf;
        return;
    end
    local function pkt(id, bytes)
        local d = {};
        for i = 1, 136 do d[i] = string.char(0); end
        for off, v in pairs(bytes) do d[off] = string.char(v); end
        return { id = id, data = table.concat(d), blocked = false };
    end

    ls.pump(); t.v = 107; ls.pump();   -- login settle (6s grace resolves)

    -- apply box 3, engine SET follows
    cmd({ command = '/dl ls apply 3', blocked = false });
    pout(pkt(0x053, { [6] = 3 }));
    check('LGF1 apply remembered', ls._lastBox(), 3);
    check('LGF2 guard live after SET', ls._guardOn(), true);

    -- the moogle subjob switch, field wire order
    t.v = 200;
    local dis = pkt(0x053, { [6] = 0 });
    pout(dis);
    check('LGF3 pre-0x100 DISABLE passes (nothing armed yet)', dis.blocked, false);
    check('LGF4 ...but it books the heal', ls._healDue() ~= nil, true);
    pout(pkt(0x100, { [5] = 0, [6] = 5 }));   -- sub-only request
    check('LGF5 box memory survives the change', ls._lastBox(), 3);
    subId = 5;                                 -- player struct catches up
    t.v = 202; ls.pump();
    t.v = 210; ls.pump();
    check('LGF6 THE FEATURE: the heal re-applies the box', queued[#queued], '/dl ls apply 3');
    check('LGF7 heal timer consumed', ls._healDue(), nil);
    pout(pkt(0x053, { [6] = 3 }));             -- the healing SET goes out
    local straggler = pkt(0x053, { [6] = 0 });
    pout(straggler);
    check('LGF8 straggler DISABLE after the heal is swallowed (window armed)', straggler.blocked, true);

    -- main-job change cancels the keep
    t.v = 300;
    local dis2 = pkt(0x053, { [6] = 0 });
    pout(dis2);                                -- client reflex first, books a heal
    pout(pkt(0x100, { [5] = 5, [6] = 0 }));    -- ...then the MAIN change lands
    check('LGF9 main change forgets the box', ls._lastBox(), nil);
    check('LGF10 ...and cancels the booked heal', ls._healDue(), nil);

    -- typed /lockstyle off ends it for real
    t.v = 400;
    cmd({ command = '/dl ls apply 3', blocked = false });
    pout(pkt(0x053, { [6] = 3 }));
    cmd({ command = '/lockstyle off', blocked = false });
    local dis3 = pkt(0x053, { [6] = 0 });
    pout(dis3);
    check('LGF11 typed off is never blocked', dis3.blocked, false);
    check('LGF12 typed off forgets the box', ls._lastBox(), nil);
    check('LGF13 typed off books no heal', ls._healDue(), nil);

    ashita.events.register, os.clock, AshitaCore = savedReg, savedClock, savedCore;
    package.loaded['dlac\\profiles'] = savedProf;
end)();

-- ---------------------------------------------------------------------------
-- LAD. _applyDirect conditions its bookkeeping on the executor's result
--      (issue #88). The GUI Apply button's direct executor call USED to note
--      lastBox + arm the zone guard unconditionally, before the call, inside a
--      swallowing pcall that discarded { ok, ... }. Now a REFUSED apply (empty
--      box, inject failure) must touch neither -- and name the refusal in the
--      window's _status line -- while a SUCCESSFUL apply keeps the old order and
--      effect (note lastBox, then arm). Driven with a STUB executor so the ok
--      flag is controlled, not derived from headless inject quirks.
-- ---------------------------------------------------------------------------
(function()
    local savedLap = package.loaded['dlac\\feature\\lockstyleapply'];
    local savedLs  = package.loaded['dlac\\feature\\lockstyle'];
    local stub = { result = nil, calls = 0 };
    stub.apply = function(_, b) stub.calls = stub.calls + 1; stub.box = b; return stub.result; end
    package.loaded['dlac\\feature\\lockstyleapply'] = stub;
    package.loaded['dlac\\feature\\lockstyle'] = nil;
    local ls = dofile('feature/lockstyle.lua');

    check('LAD0 module loads', type(ls), 'table');
    check('LAD1 clean start: no box remembered', ls._lastBox(), nil);
    check('LAD2 clean start: guard not armed', ls._guardOn(), false);

    -- REFUSED apply: the executor says no. Bookkeeping must stay put.
    stub.result = { ok = false, why = 'lockstyle box 2 has no items' };
    ls._applyDirect(2);
    check('LAD3 refusal called the executor', stub.calls, 1);
    check('LAD4 refusal leaves lastBox unchanged', ls._lastBox(), nil);
    check('LAD5 refusal does NOT arm the guard', ls._guardOn(), false);
    check('LAD6 refusal names the reason in _status',
        ls._statusLine(), 'apply failed -- lockstyle box 2 has no items.');

    -- SUCCESSFUL apply: same order and effect as before -- note lastBox, arm.
    stub.result = { ok = true, box = 2, name = 'box 2', styled = 1 };
    ls._applyDirect(2);
    check('LAD7 success called the executor with the box', stub.box, 2);
    check('LAD8 success remembers the box (keep-on-sub memory)', ls._lastBox(), 2);
    check('LAD9 success arms the zone guard', ls._guardOn(), true);

    -- A pcall'd executor ERROR is a refusal too: it surfaces in _status and
    -- leaves the prior good apply's memory (lastBox 2, guard armed) untouched.
    stub.apply = function() error('kaboom'); end
    ls._applyDirect(2);
    check('LAD10 executor error surfaces in _status',
        ls._statusLine(), 'apply failed -- apply executor error.');
    check('LAD11 error refusal leaves lastBox untouched', ls._lastBox(), 2);
    check('LAD12 error refusal leaves the guard untouched', ls._guardOn(), true);

    package.loaded['dlac\\feature\\lockstyleapply'] = savedLap;
    package.loaded['dlac\\feature\\lockstyle'] = savedLs;
end)();

-- ---------------------------------------------------------------------------
-- WI/SN. weights import (weightimport.parse/classify -> gearoptim.
-- importNamedWeights) and non-identifier set names through setmanager --
-- the Midcast_STR-VIT field bug: a dashed name must serialize bracket-quoted,
-- re-splice via the bracket form, and delete cleanly; identifiers stay bare.
-- ---------------------------------------------------------------------------
(function()
    package.loaded['dlac\\gear\\groupimport'] = package.loaded['dlac\\gear\\groupimport'] or dofile('gear/groupimport.lua');
    local wimpT = dofile('gear/weightimport.lua');

    local wprof, werr = wimpT.parse([[
        STR_DEX = T{ Accuracy = 12, Attack = { 10 }, STR = { perUnit = 10, cap = 60 }, BlueMagicSkill = { 3, 330 } },
        Debuff = { MACC = 12 },
        Bad1 = { 'Accuracy' },
        Bad2 = { Accuracy = 'twelve' },
        Empty = {},
        NotTable = 5,
    ]]);
    check('WI1 parse returns profiles', type(wprof) == 'table', true);
    check('WI2 bare number form', wprof.STR_DEX ~= nil and wprof.STR_DEX.Accuracy.perUnit, 12);
    check('WI3 array form, no cap', wprof.STR_DEX.Attack.perUnit == 10 and wprof.STR_DEX.Attack.cap == nil, true);
    check('WI4 explicit-field form keeps cap', wprof.STR_DEX.STR.cap, 60);
    check('WI5 array form keeps cap', wprof.STR_DEX.BlueMagicSkill.cap, 330);
    check('WI6 second profile lands', wprof.Debuff ~= nil and wprof.Debuff.MACC.perUnit, 12);
    check('WI7 list-entry profile skipped', wprof.Bad1, nil);
    check('WI8 bad stat value skips profile', wprof.Bad2, nil);
    check('WI9 empty profile skipped', wprof.Empty, nil);
    check('WI10 non-table value skipped', wprof.NotTable, nil);
    check('WI11 one skip reason per bad key', #werr, 4);
    local nilp = wimpT.parse('not lua at all }{');
    check('WI12 total parse failure returns nil', nilp, nil);

    local cre, ovr = wimpT.classify(wprof, { 'Debuff', 'SomethingElse' });
    check('WI13 classify created', table.concat(cre, ','), 'STR_DEX');
    check('WI14 classify overwritten (exact match)', table.concat(ovr, ','), 'Debuff');

    -- the applier: lands in the NAMED store, no set binding required
    local sum1 = optim.importNamedWeights({ STR_DEX = wprof.STR_DEX, Debuff = wprof.Debuff });
    check('WI15 import created 2', sum1.created, 2);
    check('WI16 named store readable', optim.peekWeights('named', 'Debuff').MACC.perUnit, 12);
    check('WI17 stat rows counted', sum1.stats, 5);
    local sum2 = optim.importNamedWeights({ Debuff = { INT = { perUnit = 10 } } });
    check('WI18 same name = update', sum2.updated, 1);
    check('WI19 update replaces, not merges', optim.peekWeights('named', 'Debuff').INT.perUnit == 10
        and optim.peekWeights('named', 'Debuff').MACC == nil, true);
    local inNamed = false;
    for _, n in ipairs(optim.namedKeys()) do if n == 'STR_DEX' then inNamed = true; end end
    check('WI20 imports list under Saved Sets', inNamed, true);

    -- non-identifier set names (setmanager)
    local sm = dofile('gear/setmanager.lua');
    check('SN1 identifier renders bare', sm.renderKey('Midcast_STRDEX'), 'Midcast_STRDEX');
    check('SN2 dash renders bracket-quoted', sm.renderKey('Midcast_STR-VIT'), '["Midcast_STR-VIT"]');
    check('SN3 keyword renders bracket-quoted', sm.renderKey('end'), '["end"]');
    check('SN4 leading digit renders bracket-quoted', sm.renderKey('2HSet'), '["2HSet"]');

    local base = 'local sets = {\n    Dynamic = {\n    },\n};\nreturn sets;\n';
    local STUB; STUB = setmetatable({}, { __index = function() return STUB; end });
    local t1, a1 = sm.spliceSet(base, 'Midcast_STR-VIT', {
        { name = 'Head', items = { { path = 'gear.Head.X' } } },
    });
    check('SN5 dashed name inserts', a1, 'inserted');
    check('SN6 dashed insert PARSES (the field bug)', (loadstring or load)(t1 or '') ~= nil, true);
    local t2, a2 = sm.spliceSet(t1, 'Midcast_STR-VIT', {
        { name = 'Body', items = { { path = 'gear.Body.Y' } } },
    });
    check('SN7 dashed re-splice replaces via the bracket form', a2, 'replaced');
    local _, ncopies = tostring(t2):gsub('Midcast_STR%-VIT', '');
    check('SN8 exactly one copy after replace', ncopies, 1);
    local c2 = loadWithEnv(t2, setmetatable({ gear = STUB }, { __index = _G }));
    local sok, sres = pcall(c2);
    check('SN9 dashed set reachable at runtime', sok and type(sres) == 'table'
        and type(sres.Dynamic['Midcast_STR-VIT']) == 'table', true);
    check('SN10 replace swapped the content', sok and sres.Dynamic['Midcast_STR-VIT'].Body ~= nil
        and sres.Dynamic['Midcast_STR-VIT'].Head == nil, true);
    local t3, a3 = sm.deleteSetText(t2, 'Midcast_STR-VIT');
    check('SN11 dashed delete', a3, 'deleted');
    check('SN12 delete removed it', tostring(t3):find('Midcast', 1, true), nil);
    local t4 = sm.spliceSet(base, 'Tp_Default', {
        { name = 'Head', items = { { path = 'gear.Head.X' } } },
    });
    check('SN13 identifier still renders bare', tostring(t4):find('        Tp_Default = {', 1, true) ~= nil, true);

    -- renameSetText (2026-07-20, the Sets tab Rename): re-key only, content
    -- untouched; a dashed new name bracket-quotes itself; unknown names and
    -- collisions refuse with the file untouched.
    local rt = sm.spliceSet(base, 'Idle', { { name = 'Head', items = { { path = 'gear.Head.X' } } } });
    rt = sm.spliceSet(rt, 'Tp', { { name = 'Body', items = { { path = 'gear.Body.Y' } } } });
    local rn, ra = sm.renameSetText(rt, 'Idle', 'Field');
    check('SN14 rename re-keys', ra, 'renamed');
    check('SN15 renamed text parses', (loadstring or load)(rn or '') ~= nil, true);
    check('SN16 old key gone, content kept', rn:find('Idle', 1, true) == nil
        and rn:find('gear.Head.X', 1, true) ~= nil, true);
    local rn2 = sm.renameSetText(rn, 'Field', 'STR-VIT');
    check('SN17 dashed new name bracket-quotes', tostring(rn2):find('["STR-VIT"] = {', 1, true) ~= nil, true);
    local _, rerr1 = sm.renameSetText(rn, 'Nope', 'X');
    check('SN18 unknown set refuses', tostring(rerr1):find('set not found', 1, true) ~= nil, true);
    local _, rerr2 = sm.renameSetText(rn, 'Field', 'Tp');
    check('SN19 collision refuses', tostring(rerr2):find('already exists', 1, true) ~= nil, true);

    -- priority-list twin: ordered parse, entry forms, order preserved
    local plists, perr = wimpT.parsePrio([[
        Debuff = { 'MACC', 'BlueMagicSkill', { 'INT', 60 } },
        Phys = T{ { stat = 'Accuracy' }, 'Attack' },
        BadEntry = { 'MACC', 5 },
        Mapish = { MACC = 1 },
        EmptyL = {},
    ]]);
    check('WP1 parsePrio returns lists', type(plists) == 'table', true);
    check('WP2 order preserved', plists.Debuff[1].stat == 'MACC' and plists.Debuff[2].stat == 'BlueMagicSkill'
        and plists.Debuff[3].stat == 'INT', true);
    check('WP3 pair-form cap lands', plists.Debuff[3].cap, 60);
    check('WP4 stat= form + bare string both work', plists.Phys[1].stat == 'Accuracy' and plists.Phys[2].stat == 'Attack', true);
    check('WP5 non-stat entry skips the list', plists.BadEntry, nil);
    check('WP6 named fields skip the list', plists.Mapish, nil);
    check('WP7 empty list skipped', plists.EmptyL, nil);
    check('WP8 one reason per bad key', #perr, 3);

    local psum = optim.importNamedPrio({ DebuffL = plists.Debuff });
    check('WP9 prio import created', psum.created, 1);
    check('WP10 rows counted', psum.stats, 3);
    local pn = false;
    for _, n in ipairs(optim.prioNamedKeys()) do if n == 'DebuffL' then pn = true; end end
    check('WP11 lands under Saved Lists', pn, true);
    local psum2 = optim.importNamedPrio({ DebuffL = { { stat = 'MND' } } });
    check('WP12 same name = update', psum2.updated, 1);

    -- export round trips: render -> matching parse -> identical data
    local namedFix = {
        ['STR_DEX']  = { Accuracy = { perUnit = 12 }, BlueMagicSkill = { perUnit = 3, cap = 40 } },
        ['Odd-Name'] = { MACC = { perUnit = 8 } },
    };
    local ptext = wimpT.renderPoints(namedFix);
    local back = wimpT.parse(ptext);
    check('WX1 points roundtrip: perUnit', back ~= nil and back.STR_DEX.Accuracy.perUnit, 12);
    check('WX2 points roundtrip: cap', back ~= nil and back.STR_DEX.BlueMagicSkill.cap, 40);
    check('WX3 points roundtrip: non-identifier profile name', back ~= nil and back['Odd-Name'] ~= nil
        and back['Odd-Name'].MACC.perUnit, 8);
    local prioFix = {
        ['DebuffL'] = { { stat = 'MACC' }, { stat = 'INT', cap = 60 } },
    };
    local prtext = wimpT.renderPrio(prioFix);
    local pback = wimpT.parsePrio(prtext);
    check('WX4 prio roundtrip: order survives', pback ~= nil and pback.DebuffL[1].stat == 'MACC'
        and pback.DebuffL[2].stat == 'INT', true);
    check('WX5 prio roundtrip: cap survives', pback ~= nil and pback.DebuffL[2].cap, 60);

    -- LOCAL (per-set) import (2026-07-20): ONE nameless table for the bound
    -- set. A single Name = wrapper is ignored; two+ named tables are refused
    -- (that shape belongs to the shared import); the appliers replace the
    -- BOUND set's tuning behind the copy-from revert snapshot and never touch
    -- the named stores.
    local lmap, lerr = wimpT.parseLocal('{ Accuracy = 12, Attack = 10, BlueMagicSkill = { 3, 40 } }');
    check('LW1 pure table parses clean', type(lmap) == 'table' and #lerr == 0, true);
    check('LW2 bare number row', lmap.Accuracy.perUnit, 12);
    check('LW3 capped pair row', lmap.BlueMagicSkill.perUnit == 3 and lmap.BlueMagicSkill.cap == 40, true);
    local wmap = wimpT.parseLocal('STR_DEX = { Accuracy = 12, STR = 10 },');
    check('LW4 single name wrapper ignored', wmap ~= nil and wmap.Accuracy.perUnit == 12
        and wmap.STR_DEX == nil, true);
    local two, twoErr = wimpT.parseLocal('A = { Accuracy = 12 },\nB = { Attack = 10 },');
    check('LW5 two named tables refused', two, nil);
    check('LW6 refusal names the rule', tostring(twoErr[1]):find('exactly ONE', 1, true) ~= nil, true);
    check('LW7 garbage refused', (wimpT.parseLocal('}{')), nil);

    local llist, llerr = wimpT.parsePrioLocal("{ 'MACC', 'BlueMagicSkill', { 'INT', 60 } }");
    check('LP1 pure list parses in order', #llerr == 0 and llist ~= nil and llist[1].stat == 'MACC'
        and llist[2].stat == 'BlueMagicSkill' and llist[3].stat == 'INT', true);
    check('LP2 pair cap lands', llist[3].cap, 60);
    local wlist = wimpT.parsePrioLocal("Debuff = { 'MACC', 'INT' },");
    check('LP3 single name wrapper ignored', wlist ~= nil and wlist[1].stat == 'MACC'
        and wlist[2].stat == 'INT', true);
    check('LP4 two named lists refused', (wimpT.parsePrioLocal("A = { 'MACC' }, B = { 'INT' },")), nil);

    optim.bindSetWeights('IMP', 'LocalSet');
    optim.setWeight('VIT', 5);
    local namedBefore = #optim.namedKeys();
    local okw, nw = optim.importSetWeights(lmap);
    check('LW8 set import applies', okw == true and nw, 3);
    local cur = optim.getPointWeights();
    check('LW9 replaces, not merges', cur.Accuracy ~= nil and cur.Accuracy.perUnit == 12
        and cur.VIT == nil, true);
    check('LW10 revert snapshot taken', optim.copyUndoAvailable(), true);
    check('LW11 mode lands on points', optim.weightsMode(), 'points');
    check('LW12 named store untouched', #optim.namedKeys(), namedBefore);

    local dupList = wimpT.parsePrioLocal("{ 'MACC', { 'INT', 60 }, 'MACC' }");
    local okp, np = optim.importSetPrio(dupList);
    check('LP5 set import applies + dedups', okp == true and np, 2);
    local plNow = optim.getPrio();
    check('LP6 order + cap survive', plNow[1].stat == 'MACC' and plNow[2].stat == 'INT'
        and plNow[2].cap == 60, true);
    check('LP7 mode lands on priority', optim.weightsMode(), 'priority');

    -- renameSetKey (2026-07-20, the Sets tab Rename): every per-set store and
    -- the live binding follow the new name; the actives keep working.
    check('RK1 rename returns true', optim.renameSetKey('IMP', 'LocalSet', 'LocalSet2'), true);
    check('RK2 binding follows', optim.weightsBoundTo(), 'IMP|LocalSet2');
    check('RK3 point weights ride along', optim.getPointWeights().Accuracy.perUnit, 12);
    check('RK4 old key gone from perSet', (function()
        for _, k in ipairs(optim.perSetKeys()) do if k == 'IMP|LocalSet' then return k; end end
        return nil;
    end)(), nil);
    check('RK5 prio list rides along', optim.getPrio()[1].stat, 'MACC');
    check('RK6 build mode rides along', optim.weightsMode(), 'priority');
end)();

-- ---------------------------------------------------------------------------
-- PX. selective profile export (gear/profileexport.lua + profiles weights key
-- + gearoptim per-job weights render/import) -- the export dialog's engine.
-- ---------------------------------------------------------------------------
(function()
    package.loaded['dlac\\gear\\setmanager'] = package.loaded['dlac\\gear\\setmanager'] or dofile('gear/setmanager.lua');
    package.loaded['dlac\\gear\\gearoptim'] = package.loaded['dlac\\gear\\gearoptim'] or optim;
    local pexp = dofile('gear/profileexport.lua');

    -- equipment strip: names (incl. a dashed one) survive as EMPTY shells
    local setsSrc = profilesM.frameSetsText('Dynamic = {\n'
        .. '        Idle = {\n            Head = {\n                {gear.Head.PoetsCirclet},\n            },\n        },\n'
        .. '        ["Midcast_STR-VIT"] = {\n            Body = {\n                {gear.Body.X},\n            },\n        },\n'
        .. '    }');
    local shell = pexp.stripEquipment(setsSrc);
    check('PX1 shells build', type(shell) == 'string', true);
    check('PX2 shells parse', (loadstring or load)(shell or '') ~= nil, true);
    local sc = loadWithEnv(shell or '', setmetatable({}, { __index = _G }));
    local sok, sres = pcall(sc);
    check('PX3 both names survive (dashed included)', sok and type(sres.Dynamic.Idle) == 'table'
        and type(sres.Dynamic['Midcast_STR-VIT']) == 'table', true);
    check('PX4 shells are EMPTY', sok and next(sres.Dynamic.Idle) == nil
        and next(sres.Dynamic['Midcast_STR-VIT']) == nil, true);
    check('PX5 no gear refs travel', (shell or ''):find('PoetsCirclet', 1, true), nil);

    -- triggers filter: sections drop independently; the ONE serializer round-trips
    local raw = {
        Midcast = { { when = { group = 'Debuff' }, set = 'Midcast_Debuff' } },
        Groups = { Debuff = { 'Sheep Song' } },
        Modes = { DT = { values = { 'On', 'Off' } } },
    };
    local outT = pexp.filterTriggersRaw(raw, { triggers = true }, dispatchM.canonEvent);
    check('PX6 triggers only', outT.Midcast ~= nil and outT.Groups == nil and outT.Modes == nil, true);
    local outG = pexp.filterTriggersRaw(raw, { groups = true, modes = true }, dispatchM.canonEvent);
    check('PX7 groups+modes only', outG.Midcast == nil and outG.Groups ~= nil and outG.Modes ~= nil, true);
    local ser = dispatchM.serializeTriggers(outG);
    local tok, tres = pcall((loadstring or load)(ser));
    check('PX8 filtered file parses', tok and type(tres) == 'table', true);
    check('PX9 filtered file: groups+modes, no rules', tok and tres.Midcast == nil
        and type(tres.Groups) == 'table' and tres.Groups.Debuff[1] == 'Sheep Song'
        and type(tres.Modes) == 'table' and tres.Modes.DT ~= nil, true);

    -- export format: the weights key rides job-export v1 and round-trips
    local ex = profilesM.buildExportText('BLU', 'Default', 'Mindie', 'return {};', nil, nil, '-- w\nreturn { perSet = {} };\n');
    local meta = profilesM.parseExportText(ex);
    check('PX10 weights key round-trips', meta ~= nil and type(meta.weights) == 'string', true);
    check('PX11 weights-only export is valid', (profilesM.parseExportText(
        profilesM.buildExportText('BLU', 'P', 'X', nil, nil, nil, 'return { perSet = {} };'))) ~= nil, true);

    -- per-job weights render/import (headless paths resolve nil -> LIVE stores)
    optim.bindSetWeights('BLU', 'PXSet');
    optim.setWeight('Accuracy', 12, 60);
    local wtext, wn = optim.renderJobWeightsTextAt('Whoever_1', 'BLU');
    check('PX12 render finds exactly the job\'s set', wn, 1);
    check('PX13 payload is gearweights-shaped', type(wtext) == 'string'
        and wtext:find('["BLU|PXSet"]', 1, true) ~= nil, true);
    local iN = optim.importJobWeightsTextAt('Whoever_1', wtext, 'BLU', 'BLU2');
    check('PX14 import re-keys to the imported job name', iN, 1);
    local got = optim._perSet['BLU2|PXSet'];
    check('PX15 imported weights land intact', got ~= nil and got.Accuracy ~= nil
        and got.Accuracy.perUnit == 12 and got.Accuracy.cap == 60, true);
    check('PX16 payload without the named job refuses',
        (select(2, optim.importJobWeightsTextAt('Whoever_1', wtext, 'DRK', 'DRK'))) ~= nil, true);
    -- Live-branch persist failures are LOUD (2026-07-20, the field case of a
    -- friend's weightless import): headless saveWeights cannot resolve a
    -- path, so the import must return its count PLUS the warning -- losing
    -- the merge silently on the next reload was the failure mode.
    local iN2, iWarn = optim.importJobWeightsTextAt('Whoever_1', wtext, 'BLU', 'BLU3');
    check('PX16b live merge still counts', iN2, 1);
    check('PX16c persist failure surfaces as a warning', type(iWarn) == 'string'
        and iWarn:find('saving gearweights', 1, true) ~= nil, true);
    optim.bindSetWeights(nil, nil);

    -- dependency analysis: what the data references (the form's gating input)
    local rawDeps = {
        Midcast = { { when = { group = 'Debuff' }, set = 'A' } },
        Precast = { { when = { name = 'Cure' }, whenAny = { { mode = 'DT' }, { status = 'Engaged' } }, set = 'B' } },
    };
    local refs = pexp.triggerRefs(rawDeps, dispatchM.canonEvent);
    check('PX17 group condition detected', refs.groups, true);
    check('PX18 mode condition detected inside whenAny', refs.modes, true);
    check('PX18b set action is a dependency', refs.sets, true);
    local refs2 = pexp.triggerRefs({ Midcast = { { when = { name = 'Cure' }, set = 'A' } } }, dispatchM.canonEvent);
    check('PX19 no group/mode refs when rules use neither', refs2.modes == false and refs2.groups == false, true);
    -- an EMPTY-condition rule still depends on its set; an inline-equip rule does not
    local refsE = pexp.triggerRefs({ Precast = { { when = {}, set = 'Cure_Fast' } } }, dispatchM.canonEvent);
    check('PX19b empty condition still needs its set', refsE.sets == true and refsE.modes == false and refsE.groups == false, true);
    local refsQ = pexp.triggerRefs({ Precast = { { when = { name = 'X' }, equip = { Head = 'Y' } } } }, dispatchM.canonEvent);
    check('PX19c inline-equip rule carries no set dep', refsQ.sets, false);
    local gated = profilesM.frameSetsText('Dynamic = {\n        Idle = {\n            Body = {\n                {gear.Body.X, mode = "DT"},\n            },\n        },\n    }');
    check('PX20 mode-gated gear detected', pexp.setsUseModes(gated), true);
    check('PX21 plain gear carries no mode dep', pexp.setsUseModes(setsSrc), false);
end)();

-- ---------------------------------------------------------------------------
-- AM. AutoAmmo (engine v73) -- the pure decision core M.resolveAmmoPlan
--     (docs/design/auto-ammo.md). The strictness contract pinned headless:
--     special ammo is never planned where a shot could consume it; windows
--     open only on AFFIRMATIVE facts (unlimited == nil is "unknown" and opens
--     nothing); picks are count-verified; with a special worn and nothing
--     enabled in stock the answer is 'remove' (an empty gun is server-blocked
--     -- the shot refuses instead of eating the bullet).
-- ---------------------------------------------------------------------------
(function()
    local rap = dispatchM.resolveAmmoPlan;
    local CFG = {
        enabled = true,
        jobs = { COR = true },
        ammo = {   -- array order = fallback priority
            { name = 'Bronze Bullet',   id = 1, type = 'Marksmanship', ranged = true,  ws = false, special = false },
            { name = 'Ruszor Bullet',   id = 2, type = 'Marksmanship', ranged = false, ws = true,  special = false },
            { name = 'Animikii Bullet', id = 3, type = 'Marksmanship', ranged = false, ws = false,
              special = { unlimited = true, quickdraw = true, freews = true } },
        },
    };
    -- `nil` in an override table is not a value, it is an ABSENT KEY -- so a plain
    -- { rangeWorn = nil } cannot clear a default. NONE is the explicit eraser.
    local NONE = setmetatable({}, { __tostring = function() return 'NONE'; end });
    -- facts builder: stock is id -> count; everything else overridable.
    -- A GUN is worn by default (v128): this COR's whole list is Marksmanship, and
    -- AutoAmmo now does nothing at all with an empty Range slot -- so "a gun is
    -- equipped" is the premise every one of these cases always silently assumed.
    -- 26:1 pairs with every bullet below; override rangeWorn/rangePair to vary it.
    local function F(over, stock)
        local f = { event = 'Preshot', job = 'COR',
                    rangeWorn = 'Hexagun', rangePair = '26:1',
                    count = function(e) return (stock or { [1] = 12, [2] = 12, [3] = 1 })[e.id] or 0; end };
        for k, v in pairs(over or {}) do f[k] = (v ~= NONE) and v or nil; end
        return f;
    end

    -- Preshot / Midshot (normal ranged attacks)
    check('AM1 Preshot picks the first ranged-enabled with stock', rap(CFG, F()), 'Bronze Bullet');
    check('AM2 Midshot same law', rap(CFG, F({ event = 'Midshot' })), 'Bronze Bullet');
    local p3, w3 = rap(CFG, F({ worn = 'Animikii Bullet' }, { [3] = 1 }));
    check('AM3 worn special + nothing stocked = remove', p3, 'remove');
    check('AM3b the reason names the protected bullet', (w3 or ''):find('Animikii Bullet', 1, true) ~= nil, true);
    check('AM4 worn normal + nothing stocked = hold (server refuses the empty shot)',
        rap(CFG, F({ worn = 'Bronze Bullet' }, { [3] = 1 })), nil);
    check('AM5 Unlimited Shot window opens the special', rap(CFG, F({ unlimited = true })), 'Animikii Bullet');
    check('AM5b unknown buff state opens NOTHING (affirmative-only)',
        rap(CFG, F({ unlimited = nil })), 'Bronze Bullet');
    check('AM6 US window but special unowned -> ranged pick',
        rap(CFG, F({ unlimited = true }, { [1] = 12 })), 'Bronze Bullet');
    local CFG2 = { enabled = true, ammo = {
        { name = 'Cheap A', id = 1, type = 'Marksmanship', ranged = true, ws = false, special = false },
        { name = 'Cheap B', id = 2, type = 'Marksmanship', ranged = true, ws = false, special = false },
    } };
    check('AM7 priority = list order: first out of stock falls to second',
        rap(CFG2, F(nil, { [2] = 5 })), 'Cheap B');

    -- Weaponskill: the three free magical ranged WS (217/218/220)
    check('AM8 Leaden Salute (218) opens the free-WS window',
        rap(CFG, F({ event = 'Weaponskill', wsId = 218 })), 'Animikii Bullet');
    local CFGnf = { enabled = true, jobs = { COR = true }, ammo = {
        { name = 'Bronze Bullet', id = 1, type = 'Marksmanship', ranged = true, ws = false, special = false },
        { name = 'Ruszor Bullet', id = 2, type = 'Marksmanship', ranged = false, ws = true, special = false },
        { name = 'Animikii Bullet', id = 3, type = 'Marksmanship', ranged = false, ws = false,
          special = { unlimited = true, quickdraw = true, freews = false } },
    } };
    check('AM8b freews unticked -> the WS pick instead',
        rap(CFGnf, F({ event = 'Weaponskill', wsId = 218 })), 'Ruszor Bullet');
    check('AM8c free WS with no special and no WS ammo -> ranged pick (nothing is consumed)',
        rap(CFGnf, F({ event = 'Weaponskill', wsId = 220 }, { [1] = 12 })), 'Bronze Bullet');

    -- Weaponskill: consuming physical ranged WS
    check('AM9 Last Stand (221) takes the WS pick',
        rap(CFG, F({ event = 'Weaponskill', wsId = 221 })), 'Ruszor Bullet');
    check('AM10 consuming WS, WS ammo dry, special worn -> falls to ranged',
        rap(CFG, F({ event = 'Weaponskill', wsId = 212, worn = 'Animikii Bullet' }, { [1] = 12, [3] = 1 })),
        'Bronze Bullet');
    check('AM10b consuming WS, everything dry, special worn -> remove',
        rap(CFG, F({ event = 'Weaponskill', wsId = 212, worn = 'Animikii Bullet' }, { [3] = 1 })),
        'remove');
    check('AM11 consuming WS, no WS ammo, worn normal -> hold',
        rap(CFG, F({ event = 'Weaponskill', wsId = 212, worn = 'Bronze Bullet' }, { [1] = 12 })), nil);
    check('AM12 melee/unknown WS never touches ammo, even with the special worn',
        rap(CFG, F({ event = 'Weaponskill', wsId = 33, worn = 'Animikii Bullet' })), nil);

    -- Ability: Quick Draw
    check('AM13 QD by LAC ability type', rap(CFG, F({ event = 'Ability', abilityType = 'Quick Draw' })), 'Animikii Bullet');
    check('AM13b QD by shot name (type fallback)',
        rap(CFG, F({ event = 'Ability', abilityName = 'Fire Shot' })), 'Animikii Bullet');
    local CFGarrow = { enabled = true, ammo = {
        { name = 'Wing Arrow', id = 9, type = 'Archery', ranged = false, ws = false,
          special = { quickdraw = true } },
    } };
    check('AM13c QD never offers a non-Marksmanship special (the server gate)',
        rap(CFGarrow, F({ event = 'Ability', abilityType = 'Quick Draw' }, { [9] = 99 })), nil);
    check('AM13d any other ability is not ours',
        rap(CFG, F({ event = 'Ability', abilityName = 'Provoke' })), nil);

    -- Default: the protection sweep + reload
    check('AM14 sweep: worn special outside every window -> ranged pick',
        rap(CFG, F({ event = 'Default', worn = 'Animikii Bullet' })), 'Bronze Bullet');
    check('AM14b sweep with nothing stocked -> remove',
        rap(CFG, F({ event = 'Default', worn = 'Animikii Bullet' }, { [3] = 1 })), 'remove');
    check('AM15 US window at Default pre-loads/keeps the special',
        rap(CFG, F({ event = 'Default', worn = 'Animikii Bullet', unlimited = true })), 'Animikii Bullet');
    check('AM16 fishing owns Ammo at Default -> stand down',
        rap(CFG, F({ event = 'Default', worn = 'Animikii Bullet', fishing = true })), nil);
    check('AM17 empty slot reloads the ranged pick (the marquee LAC fix)',
        rap(CFG, F({ event = 'Default' })), 'Bronze Bullet');
    check('AM17b sets planned an owned ammo -> theirs',
        rap(CFG, F({ event = 'Default', plannedAmmo = true })), nil);
    check('AM17c worn unconfigured trinket -> never touched',
        rap(CFG, F({ event = 'Default', worn = 'Tiphia Sting' })), nil);

    -- Gates
    check('AM18 jobs gate: unticked job does nothing', rap(CFG, F({ job = 'WHM' })), nil);
    check('AM18b not-ready job (nil) does nothing',   -- built by hand: pairs() skips a nil override
        rap(CFG, { event = 'Preshot', count = function() return 99; end }), nil);
    local CFGnojobs = { enabled = true, ammo = CFG.ammo };
    check('AM18c hand-written file without a jobs map is ungated', rap(CFGnojobs, F()), 'Bronze Bullet');
    check('AM19 disabled -> nil', rap({ enabled = false, ammo = CFG.ammo }, F()), nil);
    check('AM19b empty config -> nil', rap({ enabled = true, ammo = {} }, F()), nil);
    check('AM20 no counter: picks never fire but protection still does',
        rap(CFG, F({ worn = 'Animikii Bullet', count = false })), 'remove');
    check('AM20b no counter, nothing to protect -> hold',
        rap(CFG, F({ worn = 'Bronze Bullet', count = false })), nil);
    check('AM21 worn match is case-insensitive',
        rap(CFG, F({ event = 'Default', worn = 'ANIMIKII bullet' })), 'Bronze Bullet');

    -- The baked server-truth tables (seam _ammoWs): the three free ids and a
    -- consuming spot-check cannot drift silently.
    check('AM22 free set = Trueflight/Leaden/Wildfire',
        dispatchM._ammoWs.free[217] == true and dispatchM._ammoWs.free[218] == true
        and dispatchM._ammoWs.free[220] == true, true);
    check('AM22b free ids are not in the consuming set',
        dispatchM._ammoWs.consume[218], nil);
    check('AM22c Coronach consumes', dispatchM._ammoWs.consume[216], true);
    check('AM23 ammoStateOn wants enabled + a non-empty list',
        dispatchM._ammoStateOn({ enabled = true, ammo = CFG.ammo }), true);
    check('AM23b enabled with no list is OFF',
        dispatchM._ammoStateOn({ enabled = true, ammo = {} }), false);

    -- -----------------------------------------------------------------------
    -- AM40+. THE RANGE SLOT DECIDES THE TYPE (v128; Henrik 2026-07-26). The
    -- field bug: list order alone chose the ammo, so a bolt above your arrows
    -- won with a bow equipped -- and the server answered by stripping the bow.
    -- -----------------------------------------------------------------------
    -- No ranged weapon = do nothing at all, on every event. Nothing can be
    -- consumed with Range empty, so there is nothing to dress for or protect.
    check('AM40 no ranged weapon worn -> hold (Preshot)',
        rap(CFG, F({ rangeWorn = NONE, rangePair = NONE })), nil);
    check('AM41 no ranged weapon worn -> the Default sweep does not fire either',
        rap(CFG, F({ event = 'Default', rangeWorn = NONE, rangePair = NONE,
                     worn = 'Animikii Bullet' })), nil);
    check('AM42 no ranged weapon: even an open Unlimited Shot window stays shut',
        rap(CFG, F({ rangeWorn = NONE, rangePair = NONE, unlimited = true })), nil);
    check('AM43 no ranged weapon: a consuming WS plans nothing',
        rap(CFG, F({ event = 'Weaponskill', wsId = 221,
                     rangeWorn = NONE, rangePair = NONE })), nil);

    -- A BOW over a bullets-only list: nothing pairs, so AutoAmmo ignores it
    -- ("Hold, if no matching ammo for the range type" -- Henrik). Critically it
    -- does NOT fall through to 'remove' and empty the slot.
    check('AM44 bow worn, list is all bullets -> hold, never a mismatch',
        rap(CFG, F({ rangeWorn = 'Longbow', rangePair = '25:4' })), nil);
    check('AM44b bow worn, bullets-only, special worn -> still no forced remove',
        rap(CFG, F({ rangeWorn = 'Longbow', rangePair = '25:4',
                     worn = 'Animikii Bullet' })), nil);

    -- The exact field case: an arrow sits ABOVE the bullet in priority order and
    -- a GUN is equipped. Before v128 list order won and the gun came off.
    local MIX = { enabled = true, jobs = { COR = true }, ammo = {
        { name = 'Gold Arrow',   id = 10, type = 'Archery',      pair = '25:0', ranged = true, ws = false, special = false },
        { name = 'Rusty Bolt',   id = 11, type = 'Marksmanship', pair = '26:0', ranged = true, ws = false, special = false },
        { name = 'Gold Bullet',  id = 12, type = 'Marksmanship', pair = '26:1', ranged = true, ws = true,  special = false },
    } };
    local function FM(over)
        local f = { event = 'Preshot', job = 'COR', rangeWorn = 'Hexagun', rangePair = '26:1',
                    count = function() return 99; end };
        for k, v in pairs(over or {}) do f[k] = (v ~= NONE) and v or nil; end
        return f;
    end
    check('AM45 gun worn: the arrow ABOVE it in priority is skipped for the bullet',
        rap(MIX, FM()), 'Gold Bullet');
    check('AM45b crossbow worn: the same list yields the BOLT, not the bullet',
        rap(MIX, FM({ rangeWorn = 'Crossbow', rangePair = '26:0' })), 'Rusty Bolt');
    check('AM45c bow worn: the arrow wins even though two Marksmanship rows outrank nothing',
        rap(MIX, FM({ rangeWorn = 'Longbow', rangePair = '25:4' })), 'Gold Arrow');
    check('AM45d culverin worn: nothing in the list is 26:2 -> hold',
        rap(MIX, FM({ rangeWorn = 'Culverin', rangePair = '26:2' })), nil);
    check('AM46 a consuming WS respects the weapon too',
        rap(MIX, FM({ event = 'Weaponskill', wsId = 221 })), 'Gold Bullet');

    -- Graceful degradation: an UNKNOWN pair on either side never constrains, or a
    -- missing data field would read as "AutoAmmo stopped working".
    check('AM47 unknown weapon pair -> unconstrained (pre-Pair manifest)',
        rap(MIX, FM({ rangePair = NONE })), 'Gold Arrow');
    local NOPAIR = { enabled = true, jobs = { COR = true }, ammo = {
        { name = 'Gold Arrow',  id = 10, type = 'Archery',      ranged = true, ws = false, special = false },
        { name = 'Gold Bullet', id = 12, type = 'Marksmanship', ranged = true, ws = false, special = false },
    } };
    check('AM48 entry with no Pair falls back to its AmmoType skill (arrow vs gun)',
        rap(NOPAIR, FM()), 'Gold Bullet');
    check('AM48b ...and to the bow the other way round',
        rap(NOPAIR, FM({ rangeWorn = 'Longbow', rangePair = '25:4' })), 'Gold Arrow');
    check('AM48c AmmoType alone cannot split bolt from bullet -- both pair with a gun',
        rap({ enabled = true, jobs = { COR = true }, ammo = {
            { name = 'Rusty Bolt', id = 11, type = 'Marksmanship', ranged = true, ws = false, special = false },
        } }, FM()), 'Rusty Bolt');
    check('AM48d ...but a stamped Pair does split them',
        rap({ enabled = true, jobs = { COR = true }, ammo = {
            { name = 'Rusty Bolt', id = 11, type = 'Marksmanship', pair = '26:0', ranged = true, ws = false, special = false },
        } }, FM()), nil);

    -- Skill-only weapon key ("26" -- the client resource's Skill, no subskill):
    -- separates a bow from a gun, cannot separate gun from crossbow.
    check('AM49 skill-only weapon key still keeps arrows out of a gun',
        rap(MIX, FM({ rangePair = '26' })), 'Rusty Bolt');
    check('AM49b skill-only weapon key still admits the arrow to a bow',
        rap(MIX, FM({ rangePair = '25' })), 'Gold Arrow');

    -- Special behaviours are filtered by the weapon exactly like the plain picks.
    local SPEC = { enabled = true, jobs = { COR = true }, ammo = {
        { name = 'Yoru Shuriken',   id = 20, type = 'Throwing',     pair = '27:3',
          ranged = false, ws = false, special = { unlimited = true, quickdraw = true, freews = true } },
        { name = 'Animikii Bullet', id = 21, type = 'Marksmanship', pair = '26:1',
          ranged = false, ws = false, special = { unlimited = true, quickdraw = true, freews = true } },
    } };
    check('AM50 Unlimited Shot window skips the special that cannot pair',
        rap(SPEC, FM({ unlimited = true })), 'Animikii Bullet');
    check('AM50b free WS likewise',
        rap(SPEC, FM({ event = 'Weaponskill', wsId = 218 })), 'Animikii Bullet');
    check('AM50c Quick Draw likewise (and QD still demands Marksmanship)',
        rap(SPEC, FM({ event = 'Ability', abilityType = 'Quick Draw' })), 'Animikii Bullet');
    check('AM50d a bow opens NEITHER special -> hold',
        rap(SPEC, FM({ rangeWorn = 'Longbow', rangePair = '25:4', unlimited = true })), nil);
end)();

-- ---------------------------------------------------------------------------
-- PW. M.pairsWith -- the Range/Ammo compatibility law, exactly as the server
--     writes it (charutils.cpp EquipItem): same skill, and -- for every skill
--     but ARCHERY -- the same subskill, or it UNEQUIPS THE OTHER SLOT. Three-
--     valued: true / false / nil(unknown), and nil must never read as false.
-- ---------------------------------------------------------------------------
(function()
    local pw = dispatchM.pairsWith;
    check('PW1 gun + bullet pair', pw('26:1', '26:1'), true);
    check('PW2 gun + BOLT do not -- the field bug that stripped the gun', pw('26:1', '26:0'), false);
    check('PW3 crossbow + bolt pair', pw('26:0', '26:0'), true);
    check('PW4 culverin + shell pair', pw('26:2', '26:2'), true);
    check('PW4b culverin + bullet do not', pw('26:2', '26:1'), false);
    -- THE exemption. A Longbow is 25:4 and a Shortbow 25:0, yet both fire every
    -- arrow -- the server writes this case out by hand. Matching subskill here
    -- would break every bow in the game.
    check('PW5 longbow + a shortbow-class arrow STILL pair (Archery exemption)', pw('25:4', '25:0'), true);
    check('PW5b shortbow + arrow pair', pw('25:0', '25:0'), true);
    check('PW6 bow + bullet do not (different skill)', pw('25:4', '26:1'), false);
    check('PW7 boomerang + pebble pair', pw('27:0', '27:0'), true);
    check('PW8 boomerang + SHURIKEN do not (Throwing is subskill-checked)', pw('27:0', '27:3'), false);
    -- The three standing special cases, all falling out of the one rule.
    check('PW9 Animator + Automaton Oil pair (0:10 -- the ANIMATOR_FED case)', pw('0:10', '0:10'), true);
    check('PW9b Animator P II refuses the same oil (0:11 vs 0:10)', pw('0:11', '0:10'), false);
    check('PW10 a stat stick matches no real ranged weapon', pw('0:0', '26:1'), false);
    check('PW10b ...nor a Coiste-class 1:0 one', pw('1:0', '25:4'), false);
    check('PW11 fishing rod + bait pair', pw('48:0', '48:0'), true);
    -- Unknown is nil, NOT false: every pre-Pair manifest and uncrawled custom
    -- lands here, and constraining on it would switch AutoAmmo off for them.
    check('PW12 unknown on the left is nil', pw(nil, '26:1'), nil);
    check('PW12b unknown on the right is nil', pw('26:1', nil), nil);
    check('PW12c garbage is nil, never false', pw('gun', '26:1'), nil);
    -- Skill-only keys ("26"): the client resource carries Skill but no subskill.
    check('PW13 skill-only vs full: same skill cannot PROVE a mismatch', pw('26', '26:0'), true);
    check('PW13b skill-only vs full: a different skill still proves one', pw('26', '25:0'), false);
    check('PW13c skill-only both sides', pw('27', '27'), true);
    local sk, ss = dispatchM._splitPair('26:1');
    check('PW14 splitPair reads both halves', tostring(sk) .. '/' .. tostring(ss), '26/1');
    local sk2, ss2 = dispatchM._splitPair('26');
    check('PW14b skill-only leaves the subskill nil', tostring(sk2) .. '/' .. tostring(ss2), '26/nil');
    check('PW14c Archery is the exempt skill id', dispatchM.SKILL_ARCHERY, 25);

    -- -----------------------------------------------------------------------
    -- The IMPURE RIM. resolveAmmoPlan is pinned to death above, but it is
    -- ammoOverlayFor that gathers rangeWorn/rangePair -- and if that wiring
    -- ever breaks, f.rangeWorn is nil, the gate shuts, and AutoAmmo silently
    -- does NOTHING FOREVER with no error anywhere. Drive the real rim against
    -- a stub client so the wiring itself is a test, not an assumption.
    -- -----------------------------------------------------------------------
    local savedAshita = AshitaCore;
    -- equip slot 2 = Range, 3 = Ammo; Index packs container*256 + slot.
    local RANGE_ID, AMMO_ID = 17222, 12;   -- Hexagun (a gun), Gold Bullet
    local RES = {
        [17222] = { Name = { 'Hexagun' },     Skill = 26 },
        [17160] = { Name = { 'Longbow' },     Skill = 25 },
        [12]    = { Name = { 'Gold Bullet' }, Skill = 26 },
    };
    RES[10] = { Name = { 'Gold Arrow' }, Skill = 25 };
    -- Ammo slot EMPTY on purpose: with the planned bullet already worn the rim
    -- correctly holds, which would make this whole section pass for the wrong
    -- reason. Both ammos sit in the bag so the counter can find them.
    local bag = { [1] = { Id = RANGE_ID, Count = 1 },
                  [2] = { Id = AMMO_ID,  Count = 40 },
                  [3] = { Id = 10,       Count = 99 } };
    AshitaCore = {
        GetMemoryManager = function() return { GetInventory = function() return {
            GetEquippedItem = function(_, slot)
                if slot == 2 and RANGE_ID ~= nil then return { Index = 1 }; end
                return { Index = 0 };   -- Ammo (3) and everything else: empty
            end,
            GetContainerItem = function(_, cid, idx) return (cid == 0) and bag[idx] or nil; end,
            GetContainerCountMax = function(_, cid) return (cid == 0) and 3 or 0; end,
        }; end }; end,
        GetResourceManager = function() return { GetItemById = function(_, id) return RES[id]; end }; end,
    };
    local AS = { fmt = 2, jobs = { COR = { enabled = true, at = 0, ammo = {
        { name = 'Gold Arrow',  id = 10, type = 'Archery',      pair = '25:0', ranged = true, ws = false, special = false },
        { name = 'Gold Bullet', id = 12, type = 'Marksmanship', pair = '26:1', ranged = true, ws = false, special = false },
    } } } };
    local ctx = { player = { MainJob = 'COR' } };

    local pair, nm = dispatchM._wornPair('range');
    check('PW15 wornPair reads the Range slot through the client', nm, 'Hexagun');
    check('PW15b ...and falls back to the resource Skill with no manifest Pair', pair, '26');
    local eq = dispatchM._ammoOverlayFor(AS, ctx, 'Preshot', nil, false);
    check('PW16 the rim reaches a plan at all (the silent-death guard)',
        type(eq) == 'table' and eq.Ammo or nil, 'Gold Bullet');
    -- The arrow is FIRST in the list and in stock; only the gun keeps it out.
    check('PW16b ...and it is the weapon, not the order, that chose it',
        (type(eq) == 'table' and eq.Ammo) ~= 'Gold Arrow', true);

    RANGE_ID = nil; bag[1] = nil;   -- unequip the gun
    check('PW17 no ranged weapon -> the rim plans nothing',
        dispatchM._ammoOverlayFor(AS, ctx, 'Preshot', nil, false), nil);

    RANGE_ID = 17160; bag[1] = { Id = 17160, Count = 1 };   -- a bow instead
    local eq2 = dispatchM._ammoOverlayFor(AS, ctx, 'Preshot', nil, false);
    check('PW18 swapping to a bow re-aims the pick with no config change',
        type(eq2) == 'table' and eq2.Ammo or nil, 'Gold Arrow');
    AshitaCore = savedAshita;
end)();

-- ---------------------------------------------------------------------------
-- AW. ammowatch -- the GUI's half of AutoAmmo: the fmt-2 PER-JOB serializer
--     (round-trips through the engine's reader shape), the fmt-1 migration
--     (every ticked job gets its own copy; an unowned list becomes the
--     orphan the first job in adopts), and the mutator invariants (special
--     is exclusive; priority moves stay in bounds; jobs never cross-read).
--     Headless: charDir is nil, so every save is a silent no-op -- the
--     in-memory jobsData is what's under test.
-- ---------------------------------------------------------------------------
(function()
    local aw = dofile('feature/ammowatch.lua');   -- the harness has no addons/ on package.path

    local corSec = {
        enabled = true, at = 1753000000,
        ammo = {
            { name = 'Bronze Bullet', id = 21306, type = 'Marksmanship', level = 5, ranged = true, ws = false, special = false },
            { name = "Animikii Bullet", id = 21334, type = 'Marksmanship', level = 75, ranged = false, ws = false,
              special = { unlimited = true, quickdraw = true, freews = false } },
        },
    };
    local txt = aw._serialize({ COR = corSec, RNG = { enabled = false, at = 0, ammo = {} } });
    local back = (loadstring or load)(txt)();
    check('AW1 fmt 2 on the wire', back.fmt, 2);
    check('AW2 per-job enabled + at survive',
        back.jobs.COR.enabled == true and back.jobs.COR.at == 1753000000
        and back.jobs.RNG.enabled == false, true);
    check('AW4 entry order preserved', back.jobs.COR.ammo[1].name, 'Bronze Bullet');
    check('AW5 normal entry: special = false', back.jobs.COR.ammo[1].special, false);
    check('AW5b level survives', back.jobs.COR.ammo[2].level, 75);
    check('AW6 special table survives with only true bits',
        back.jobs.COR.ammo[2].special.unlimited == true and back.jobs.COR.ammo[2].special.quickdraw == true
        and back.jobs.COR.ammo[2].special.freews == nil, true);
    check('AW7 the engine gate accepts the round-trip', dispatchM._ammoStateOn(back), true);
    check('AW7b the engine gate refuses all-off sections',
        dispatchM._ammoStateOn({ fmt = 2, jobs = { RNG = { enabled = false, ammo = corSec.ammo } } }), false);
    check('AW7c the engine gate refuses an enabled EMPTY section',
        dispatchM._ammoStateOn({ fmt = 2, jobs = { RNG = { enabled = true, ammo = {} } } }), false);

    -- fmt-1 migration: every ticked job gets its OWN COPY; no ticked job = orphan
    local old = { enabled = true, at = 9, jobs = { COR = true, RNG = true, WAR = false },
                  ammo = { { name = 'Bullet', id = 1, type = 'Marksmanship', ranged = true, ws = false, special = false } } };
    local jd, orph = aw._migrate(old);
    check('AW18 fmt-1 ticked jobs each get a section',
        jd.COR ~= nil and jd.RNG ~= nil and jd.WAR == nil, true);
    check('AW18b sections carry the old switch + list',
        jd.COR.enabled == true and jd.COR.ammo[1].name == 'Bullet', true);
    check('AW18c no orphan when jobs were ticked', orph, nil);
    jd.COR.ammo[1].ranged = false;
    check('AW18d sections are COPIES (jobs diverge independently)', jd.RNG.ammo[1].ranged, true);
    local jd2, orph2 = aw._migrate({ enabled = true, jobs = {}, ammo = old.ammo });
    check('AW19 fmt-1 with no ticked job -> orphan (nothing lost)',
        next(jd2) == nil and orph2 ~= nil and orph2.ammo[1].name == 'Bullet', true);
    check('AW19b orphan comes back disarmed', orph2.enabled, false);
    aw.jobsData = {};
    aw._setOrphan(orph2);
    aw.selectJob('WAR');
    check('AW19c first job in adopts the orphan', aw.jobsData.WAR ~= nil and #aw.list == 1, true);

    -- mutators (in-memory; saves no-op headless) + per-job isolation
    aw.jobsData = {};
    aw.selectJob('COR');
    check('AW8 addAmmo', aw.addAmmo({ Name = 'Iron Bullet', Id = 21310, AmmoType = 'Marksmanship' }), true);
    check('AW8b dedup by name (ci)', aw.addAmmo({ Name = 'IRON bullet', Id = 21310, AmmoType = 'Marksmanship' }), false);
    aw.addAmmo({ Name = 'Bomb Core', Id = 5309, AmmoType = 'Throwing' });
    aw.setEnabled(true, 'COR');
    aw.selectJob('RNG');
    check('AW20 another job reads EMPTY and OFF (per-job isolation)',
        #aw.list == 0 and aw.enabled == false, true);
    aw.addAmmo({ Name = 'Wing Arrow', Id = 9000, AmmoType = 'Archery' });
    aw.selectJob('COR');
    check('AW20b the first job kept its own list and switch',
        #aw.list == 2 and aw.enabled == true and aw.list[1].name == 'Iron Bullet', true);
    check('AW20c jobSummary sees both jobs', #aw.jobSummary(), 2);
    aw.moveAmmo(2, -1);
    check('AW9 moveAmmo reorders', aw.list[1].name, 'Bomb Core');
    aw.moveAmmo(1, -1);
    check('AW9b out-of-bounds move is a no-op', aw.list[1].name, 'Bomb Core');
    aw.setFlag(1, 'ranged', true);
    check('AW10 setFlag ranged', aw.list[1].ranged, true);
    aw.setSpecial(1, true);
    check('AW11 special is exclusive: ranged cleared', aw.list[1].ranged, false);
    check('AW11b behaviours default off',
        aw.list[1].special.unlimited == false and aw.list[1].special.quickdraw == false, true);
    aw.setFlag(1, 'ranged', true);
    check('AW12 setFlag refused on a special entry', aw.list[1].ranged, false);
    aw.setBehaviour(1, 'freews', true);
    check('AW13 setBehaviour', aw.list[1].special.freews, true);
    aw.setBehaviour(1, 'nonsense', true);
    check('AW13b unknown behaviour refused', aw.list[1].special.nonsense, nil);
    aw.setSpecial(1, false);
    check('AW14 special off restores a normal entry', aw.list[1].special, false);
    aw.removeAmmo(1);
    check('AW15 removeAmmo', #aw.list == 1 and aw.list[1].name == 'Iron Bullet', true);

    -- EB. eboxammo -- now a THIN ADAPTER over the one client (ADR 0016). The
    -- wire itself is tested on the client (EBC*); these checks pin the ADAPTER:
    -- delegation + the cat-15 mirror ui/ammoui reads. A fresh client is injected
    -- (require fails headless) and driven THROUGH the adapter. pk/msgAt build the
    -- synthetic packets (also used by EBC/RS below).
    local eb  = dofile('feature/eboxammo.lua');
    local ebc = dofile('feature/eboxclient.lua');
    eb._setClient(ebc);
    ebc._now = function() return 4000; end
    local function pk(bytes)
        local t = {};
        for off = 0, 63 do t[off + 1] = string.char(bytes[off] or 0); end
        return table.concat(t);
    end
    local function msgAt(t, off, s)
        for k = 1, #s do t[off + k - 1] = string.byte(s, k); end
        return t;
    end
    check('EB1 clamp: none in box -> 0', eb._clampQty(99, 0), 0);
    check('EB1b clamp to what the box holds', eb._clampQty(99, 12), 12);
    check('EB1c junk qty -> 0', eb._clampQty('x', 5), 0);
    check('EB1d floors fractions', eb._clampQty(3.7, 5), 3);

    check('EB2 ITEM outside our stream is not ours (party line)',
        eb._onPacket(pk({ [0x04] = 1, [0x08] = 10 })), false);
    eb._beginStream();   -- delegates to the client's cat-15 request
    check('EB3 CLEAR consumed while pending', eb._onPacket(pk({ [0x04] = 0 })), true);
    eb._onPacket(pk({ [0x04] = 1, [0x08] = 0x36, [0x09] = 0x53, [0x0C] = 200 }));   -- id 21302 x200
    eb._onPacket(pk({ [0x04] = 1, [0x08] = 0x56, [0x09] = 0x53, [0x0C] = 1 }));     -- id 21334 x1
    check('EB3b END_LIST from another source does not commit',
        eb._onPacket(pk({ [0x04] = 2, [0x05] = 3 })), false);
    check('EB3c END_LIST source 0 commits', eb._onPacket(pk({ [0x04] = 2, [0x05] = 0 })), true);
    check('EB3d counts mirror the committed cat-15 stream',
        eb.counts ~= nil and eb.counts[21302] == 200 and eb.counts[21334] == 1, true);
    check('EB4 stream closed: a late ITEM is not ours',
        eb._onPacket(pk({ [0x04] = 1, [0x08] = 10 })), false);

    -- withdraw ACK: stage the batch on the client, drive it through the adapter
    ebc._beginBatch(1);
    check('EB5 ACK for someone else\'s action is not ours',
        eb._onPacket(pk({ [0x04] = 3, [0x05] = 15, [0x06] = 1 })), false);
    check('EB5b withdraw ACK success consumed + busy mirror clears',
        eb._onPacket(pk({ [0x04] = 3, [0x05] = 2, [0x06] = 1 })) == true and eb.busy == false, true);
    check('EB5c success status is not an error', eb.statusErr, false);
    ebc._beginBatch(1);
    eb._onPacket(pk(msgAt({ [0x04] = 3, [0x05] = 2, [0x06] = 0 }, 0x10, 'Inventory full.')));
    check('EB5d refusal carries the server\'s words', eb.status, 'Inventory full.');
    check('EB5e refusal is an error', eb.statusErr, true);
    check('EB5f ACK with nothing in flight is not ours',
        eb._onPacket(pk({ [0x04] = 3, [0x05] = 2, [0x06] = 1 })), false);

    check('EB6 unsolicited LOCKED is not ours (must not shut the panel)',
        eb._onPacket(pk({ [0x04] = 4, [0x05] = 1 })), false);
    eb._beginStream();
    eb._onPacket(pk({ [0x04] = 4, [0x05] = 1 }));
    check('EB6b LOCKED reason 1 while pending = not a Crystal Warrior', eb.lockedReason, 'cw');
    ebc.lockedReason = nil; eb._sync();
    eb._beginStream();
    eb._onPacket(pk(msgAt({ [0x04] = 4, [0x05] = 2 }, 0x10, 'Locked.')));
    check('EB6c LOCKED reason 2 = box not unlocked', eb.lockedReason == 'locked' and eb.lockedMsg == 'Locked.', true);
    ebc.lockedReason = nil; eb._sync();

    check('EB7 refresh refuses headless (not CW -- the affirmative-only gate)', eb.refresh(), false);
    check('EB7b withdraw refuses headless too', eb.withdraw(21334, 1), false);

    -- EW. lib/entwatch -- the CENTRAL entity watcher (field round 6; built
    -- from this feature's scan lessons, eboxammo is consumer #1). Injected
    -- probe + clock; the padded/cased names, index 0 and the 0x802 dynamic
    -- slot pin the field lessons (rounds 2-4: exact-name compare never
    -- matched GetName's trailing whitespace; the 0-1023 static sweep could
    -- never reach a dynamically spawned box) forever.
    local ew = dofile('lib/entwatch.lua');
    local ewNow = 1000;
    ew._now = function() return ewNow; end;
    local world = { [12]   = { name = 'Ephemeral Box   ', d2 = 100 },   -- padded: the live shape
                    [40]   = { name = 'EPHEMERAL box',    d2 = 25 },    -- case must not matter
                    [0]    = { name = 'Ephemeral Box',    d2 = 3600 },  -- slot 0 is scanned too
                    [2050] = { name = 'Ephemeral Box ',   d2 = 16 },    -- 0x802: the live dynamic slot
                    [77]   = { name = 'Nomad Moogle',     d2 = 4 } };
    local probe = {
        present = function(idx) return world[idx] ~= nil; end,
        name    = function(idx) return world[idx] and world[idx].name; end,
        distSq  = function(idx) return world[idx] and world[idx].d2; end,
    };
    check('EW1 nearest before any watch = nil', ew.nearest('Ephemeral Box'), nil);
    local cbN = {};
    check('EW2 watch registers', ew.watch('t_ebox', 'Ephemeral Box', function(m) cbN[#cbN + 1] = #m; end), true);
    check('EW2b a callback watch is active without polling', ew._sweep(probe, ewNow), true);
    check('EW2c the callback fired with the sorted match set', cbN[1], 4);
    local d1, i1 = ew.nearest('Ephemeral Box');
    check('EW3 nearest despite padding/case, in yalms', d1, 4.0);
    check('EW3b ...and it is the dynamic 0x802 slot', i1, 2050);
    local ms = ew.matches('Ephemeral Box');
    check('EW4 matches sorted nearest-first', ms[1].idx == 2050 and ms[#ms].idx == 0, true);
    check('EW5 sweep cadence: not due again yet', ew._sweep(probe, ewNow + 1), false);
    -- fast refresh: distance moves WITHOUT a sweep; slot reuse gets evicted
    world[2050].d2 = 9;
    world[40] = { name = 'Goblin Digger', d2 = 1 };   -- slot REUSED by a stranger
    ew._refresh(probe, ewNow + 1);
    check('EW6 tracked distance refreshed between sweeps', (ew.nearest('Ephemeral Box')), 3.0);
    check('EW6b reused slot evicted (name re-verified)', #ew.matches('Ephemeral Box'), 3);
    -- change detection: the next due sweep sees the same 3 -> no new callback
    ewNow = ewNow + 3;
    ew._sweep(probe, ewNow);
    check('EW7 unchanged match set fires no callback', #cbN, 2);   -- 1 initial + 1 for the eviction round
    ew._sweep(probe, ewNow + 3);
    check('EW7b (still none without a change)', #cbN, 2);
    -- demand window: a POLLED watch sleeps IDLE_S after its last ask
    ew.unwatch('t_ebox');
    check('EW8 last subscriber leaving tears the entry down', ew.nearest('Ephemeral Box'), nil);
    ew.watch('t_poll', 'Ephemeral Box');
    ewNow = ewNow + 100;                              -- stale ask: inactive
    check('EW8b idle polled watch sweeps nothing', ew._sweep(probe, ewNow), false);
    ew.nearest('Ephemeral Box');                      -- the ask IS the demand
    check('EW8c a fresh ask wakes it', ew._sweep(probe, ewNow), true);
    -- poke: cache-bust ahead of the cadence (the panel's rescan button)
    check('EW9 not due again', ew._sweep(probe, ewNow + 1), false);
    ew.poke('Ephemeral Box');
    check('EW9b poke forces the next sweep', ew._sweep(probe, ewNow + 1), true);
    ew.unwatch('t_poll');
    check('EW10 empty registry reports empty', #ew.debugState(), 0);

    check('EB9 box range is FIELD-PINNED at 5 yalms (Henrik 2026-07-20)', eb.BOX_RANGE, 5);
    check('EB10 boxDistance is headless-safe through the watcher', eb.boxDistance(), nil);

    -- EBC. eboxclient -- THE one 0x1A4 client (ADR 0016). Same wire as eboxammo,
    -- reimplemented with a MULTI-category shared counts cache + batch withdraw +
    -- search + throttle; every future E-Box feature consumes this, never a second
    -- speaker. Injected clock; the pk/msgAt helpers above build synthetic packets.
    local ec = dofile('feature/eboxclient.lua');
    ec._now = function() return 5000; end

    check('EBC1 clamp: none in box -> 0', ec._clampQty(99, 0), 0);
    check('EBC1b clamp to what the box holds', ec._clampQty(99, 12), 12);
    check('EBC1c junk qty -> 0', ec._clampQty('x', 5), 0);
    check('EBC1d floors fractions', ec._clampQty(3.7, 5), 3);

    check('EBC2 ITEM outside our stream is not ours (party line)',
        ec._onPacket(pk({ [0x04] = 1, [0x08] = 10 })), false);

    -- a category stream: CLEAR -> ITEM* -> END_LIST(source 0)
    ec._beginRequest('category', 15);
    check('EBC3 CLEAR consumed while pending', ec._onPacket(pk({ [0x04] = 0 })), true);
    ec._onPacket(pk({ [0x04] = 1, [0x08] = 0x36, [0x09] = 0x53, [0x0A] = 15, [0x0C] = 200 }));  -- 21302 x200
    ec._onPacket(pk({ [0x04] = 1, [0x08] = 0x56, [0x09] = 0x53, [0x0A] = 15, [0x0C] = 1 }));    -- 21334 x1
    check('EBC3b END_LIST from another source does not commit',
        ec._onPacket(pk({ [0x04] = 2, [0x05] = 3 })), false);
    check('EBC3c END_LIST source 0 commits', ec._onPacket(pk({ [0x04] = 2, [0x05] = 0 })), true);
    check('EBC3d category counts committed (narrowed to the ahCat)',
        ec.boxCount(21302, 15) == 200 and ec.boxCount(21334, 15) == 1, true);
    check('EBC3e flat merged view reads without an ahCat', ec.boxCount(21302), 200);
    check('EBC3f the fetched category is fresh', ec.categoryFresh(15, 20), true);

    -- a SECOND category merges into the flat view (both categories coexist)
    ec._beginRequest('category', 6);
    ec._onPacket(pk({ [0x04] = 0 }));
    ec._onPacket(pk({ [0x04] = 1, [0x08] = 0x34, [0x09] = 0x10, [0x0A] = 6, [0x0C] = 30 }));    -- 4148 x30
    ec._onPacket(pk({ [0x04] = 2, [0x05] = 0 }));
    check('EBC4 flat view holds both categories at once',
        ec.boxCount(21302) == 200 and ec.boxCount(4148) == 30, true);

    -- re-fetching category 15 REPLACES only its own rows (a drained item drops)
    ec._beginRequest('category', 15);
    ec._onPacket(pk({ [0x04] = 0 }));
    ec._onPacket(pk({ [0x04] = 1, [0x08] = 0x36, [0x09] = 0x53, [0x0A] = 15, [0x0C] = 150 }));  -- 21302 now 150
    ec._onPacket(pk({ [0x04] = 2, [0x05] = 0 }));
    check('EBC4b re-fetch replaces cat 15 (21334 drained), cat 6 untouched',
        ec.boxCount(21334, 15) == 0 and ec.boxCount(21302) == 150 and ec.boxCount(4148) == 30, true);
    check('EBC4c a late ITEM after the stream closed is not ours',
        ec._onPacket(pk({ [0x04] = 1, [0x08] = 10 })), false);

    -- SEARCH stream: rows carry id/qty/ahCat/name; must NOT touch the counts cache
    ec._beginRequest('search');
    ec._onPacket(pk({ [0x04] = 0 }));
    ec._onPacket(pk(msgAt({ [0x04] = 1, [0x08] = 0x36, [0x09] = 0x53, [0x0A] = 15, [0x0C] = 5 }, 0x10, 'Bronze Bullet')));
    ec._onPacket(pk({ [0x04] = 2, [0x05] = 0 }));
    check('EBC5 search results captured (id/ahCat/name/qty)',
        ec.searchResults ~= nil and #ec.searchResults == 1
        and ec.searchResults[1].id == 21302 and ec.searchResults[1].ahCat == 15
        and ec.searchResults[1].name == 'Bronze Bullet' and ec.searchResults[1].qty == 5, true);
    check('EBC5b search did not pollute the counts cache', ec.boxCount(21302, 15), 150);

    -- batch withdraw ACK counting (the seam stages N in-flight ACKs)
    ec._beginBatch(2);
    check('EBC6 ACK for someone else\'s action is not ours',
        ec._onPacket(pk({ [0x04] = 3, [0x05] = 15, [0x06] = 1 })), false);
    check('EBC6b first withdraw ACK consumed, still busy (1 left)',
        ec._onPacket(pk({ [0x04] = 3, [0x05] = 2, [0x06] = 1 })) == true and ec.isBusy() == true, true);
    check('EBC6c second ACK completes the batch (busy clears)',
        ec._onPacket(pk({ [0x04] = 3, [0x05] = 2, [0x06] = 1 })) == true and ec.isBusy() == false, true);
    -- v2 (2026-07-25): completing a batch NO LONGER re-counts. We debited what we
    -- asked for at send time, so re-asking would be exactly the poll that model
    -- deleted. Only a REFUSAL (below, EBC13) says our number was wrong.
    check('EBC6d a completed batch leaves the counts believed (arithmetic did it)',
        ec.categoryFresh(15, 20), true);
    check('EBC6e ACK with nothing in flight is not ours',
        ec._onPacket(pk({ [0x04] = 3, [0x05] = 2, [0x06] = 1 })), false);
    ec._beginBatch(1);
    ec._onPacket(pk(msgAt({ [0x04] = 3, [0x05] = 2, [0x06] = 0 }, 0x10, 'Inventory full.')));
    check('EBC6f refusal carries the server\'s words',
        ec.status == 'Inventory full.' and ec.statusErr == true, true);

    -- LOCKED gates
    check('EBC7 unsolicited LOCKED is not ours (nothing pending)',
        ec._onPacket(pk({ [0x04] = 4, [0x05] = 1 })), false);
    ec._beginRequest('category', 15);
    ec._onPacket(pk({ [0x04] = 4, [0x05] = 1 }));
    check('EBC7b LOCKED reason 1 while pending = not a Crystal Warrior', ec.lockedReason, 'cw');
    ec.lockedReason = nil;
    ec._beginRequest('search');
    ec._onPacket(pk(msgAt({ [0x04] = 4, [0x05] = 2 }, 0x10, 'Locked.')));
    check('EBC7c LOCKED reason 2 = box not unlocked',
        ec.lockedReason == 'locked' and ec.lockedMsg == 'Locked.', true);
    ec.lockedReason = nil;

    -- SUMMARY (single packet, not a stream): entryCount@0x05, 7-byte rows @0x08
    ec._beginRequest('summary');
    check('EBC8 SUMMARY parsed into per-category totals',
        ec._onPacket(pk({ [0x04] = 5, [0x05] = 1, [0x08] = 15, [0x09] = 2, [0x0B] = 3 })) == true
        and ec.summary ~= nil and #ec.summary == 1
        and ec.summary[1].ahCat == 15 and ec.summary[1].count == 2 and ec.summary[1].qty == 3, true);

    -- headless gates: no CW -> every request refuses, nothing hits the wire
    check('EBC9 ensureCategory refuses headless (affirmative-only CW gate)', ec.ensureCategory(15), false);
    check('EBC9b search refuses headless', ec.search('bullet'), false);
    check('EBC9c withdraw refuses headless', ec.withdraw(21302, 1), false);
    check('EBC9d withdrawBatch refuses headless', ec.withdrawBatch({ { id = 21302, qty = 1 } }), 0);

    -- proximity (headless-safe through the watcher)
    check('EBC10 box range is FIELD-PINNED at 5 yalms', ec.BOX_RANGE, 5);
    check('EBC10b boxDistance headless -> nil, nearBox -> false',
        ec.boxDistance() == nil and ec.nearBox() == false, true);

    -- EBC11-16. THE v2 MODEL (grill 2026-07-25, docs/design/ebox-restock-v2-grill-
    -- 2026-07-25.md): the box is a number we already know. Verify once, DEBIT our
    -- own withdraws, and re-count only when something we cannot see changed it --
    -- so crafting next to a box costs zero packets.
    local function ecCount(cat, id, qty)          -- commit one category by hand
        ec._beginRequest('category', cat);
        ec._onPacket(pk({ [0x04] = 0 }));
        ec._onPacket(pk({ [0x04] = 1, [0x08] = id % 256, [0x09] = math.floor(id / 256),
                          [0x0A] = cat, [0x0C] = qty }));
        ec._onPacket(pk({ [0x04] = 2, [0x05] = 0 }));
    end

    ecCount(15, 21302, 40);
    check('EBC11 a counted category is believed at ANY window (no clock)',
        ec.categoryFresh(15, math.huge), true);
    ec.markDirty(15);
    check('EBC11b a dirty category is fresh at NO window', ec.categoryFresh(15, math.huge), false);
    ecCount(15, 21302, 40);
    check('EBC11c re-counting believes it again', ec.categoryFresh(15, math.huge), true);
    ec.markDirty(99);
    check('EBC11d marking a category we never counted is a no-op (already unfresh)',
        ec.dirty[99] == nil and ec.categoryFresh(99, math.huge) == false, true);
    ec.markAllDirty();
    check('EBC11e markAllDirty stops believing every counted category',
        ec.categoryFresh(15, math.huge) == false and ec.categoryFresh(6, math.huge) == false, true);
    check('EBC11f verifyCategories is just "no clock" -- headless it still refuses',
        ec.verifyCategories({ 15 }), false);
    check('EBC11g categoriesVerified is false while anything is dirty',
        ec.categoriesVerified({ 15, 6 }), false);

    -- the debit: we sent it, so we know what is left. No packet involved.
    ecCount(15, 21302, 40);
    ec._debit(21302, 12);
    check('EBC12 debit subtracts what we asked for (40 - 12)', ec.boxCount(21302, 15), 28);
    check('EBC12b the flat merged view follows the debit', ec.boxCount(21302), 28);
    ec._debit(21302, 999);
    check('EBC12c debit floors at zero, never negative', ec.boxCount(21302), 0);
    check('EBC12d debiting an item the box never held is a no-op', ec._debit(4242, 5), nil);
    check('EBC12e a debit does NOT dirty the category (that is the whole point)',
        ec.categoryFresh(15, math.huge), true);

    -- the ONE repair arithmetic cannot do itself: the server refused us
    ecCount(15, 21302, 40);
    ec._beginBatch(1, { [15] = true });
    ec._onPacket(pk(msgAt({ [0x04] = 3, [0x05] = 2, [0x06] = 0 }, 0x10, 'Inventory full.')));
    check('EBC13 a REFUSED withdraw stops us believing exactly that category',
        ec.categoryFresh(15, math.huge) == false and ec.statusErr == true, true);
    ecCount(15, 21302, 40);
    ec._beginBatch(1, { [15] = true });
    ec._onPacket(pk({ [0x04] = 3, [0x05] = 2, [0x06] = 1 }));
    check('EBC13b a SUCCESSFUL withdraw leaves the belief intact',
        ec.categoryFresh(15, math.huge), true);
    ec.rescan();
    check('EBC13c Rescan is the manual repair -- nothing believed',
        ec.categoryFresh(15, math.huge), false);

    -- search: one question at a time, and the answer knows what it answers
    ec.clearSearch();
    check('EBC14 clearSearch forgets the hits AND the question',
        ec.searchResults == nil and ec.searchFor == nil, true);
    ec._beginRequest('search');
    check('EBC14b searchBusy while our search is on the wire', ec.searchBusy(), true);
    ec._onPacket(pk({ [0x04] = 0 }));
    ec._onPacket(pk(msgAt({ [0x04] = 1, [0x08] = 0x36, [0x09] = 0x53, [0x0A] = 15, [0x0C] = 5 }, 0x10, 'Bronze Bullet')));
    ec._onPacket(pk({ [0x04] = 2, [0x05] = 0 }));
    check('EBC14c the answer clears searchBusy',
        ec.searchBusy() == false and #ec.searchResults == 1, true);
    check('EBC14d a category request is not a search', (function()
        ec._beginRequest('category', 15); return ec.searchBusy();
    end)(), false);

    -- headless gates for the new doors
    check('EBC15 boxStore refuses headless (the CW gate, before any command)', ec.boxStore(), false);
    check('EBC15b canQuery is public and headless-false', ec.canQuery(), false);

    -- the lost-answer timeout: ONE dropped reply must not wedge every future
    -- query. Under the dirty-only discipline there is no poll to paper over it.
    local ecNow = 5000;
    ec._now = function() return ecNow; end
    ec._beginRequest('search');
    check('EBC16 a request in flight holds the one-at-a-time slot', ec.searchBusy(), true);
    ecNow = ecNow + ec.PEND_HOLD + 1;
    check('EBC16b PEND_HOLD releases a request whose answer never came',
        ec.searchBusy(), false);

    -- EBC17-22. What the timeout in EBC16 costs if left naive, and the three
    -- other holes a poll used to hide. All five found by the adversarial review
    -- of this build (2026-07-25) -- every one of them permanent under the
    -- dirty-only discipline, because there is no longer a clock to age it out.

    -- A late answer the timeout gave up on must NOT commit under whichever
    -- request took the slot next. The wire has no request id; a row's own ahCat
    -- is the only correlator there is.
    ec.cat, ec.counts, ec.dirty = {}, {}, {};
    ecNow = ecNow + 100;
    ecCount(15, 21302, 40);
    ec._beginRequest('category', 6);        -- a NEW request takes the slot...
    ec._onPacket(pk({ [0x04] = 0 }));
    ec._onPacket(pk({ [0x04] = 1, [0x08] = 0x36, [0x09] = 0x53, [0x0A] = 15, [0x0C] = 99 }));  -- ...cat-15 rows arrive
    check('EBC17 a stream whose rows name another category is consumed, NOT committed',
        ec._onPacket(pk({ [0x04] = 2, [0x05] = 0 })) == true
        and ec.cat[6] == nil and ec.categoryFresh(6, math.huge) == false, true);
    check('EBC17b ...and the category those rows really belong to is left alone',
        ec.boxCount(21302, 15), 40);
    ec._beginRequest('category', 6);
    ec._onPacket(pk({ [0x04] = 0 }));
    ec._onPacket(pk({ [0x04] = 1, [0x08] = 0x34, [0x09] = 0x10, [0x0A] = 0, [0x0C] = 30 }));
    ec._onPacket(pk({ [0x04] = 2, [0x05] = 0 }));
    check('EBC17c a row that names no category is still accepted (never re-ask forever)',
        ec.boxCount(4148, 6), 30);

    -- A long list streams for a while: each row is progress, so the deadline
    -- moves. Otherwise a big category is abandoned MID-stream, forever.
    ec._beginRequest('category', 15);
    ecNow = ecNow + (ec.PEND_HOLD - 2);
    ec._onPacket(pk({ [0x04] = 1, [0x08] = 0x36, [0x09] = 0x53, [0x0A] = 15, [0x0C] = 7 }));
    ecNow = ecNow + (ec.PEND_HOLD - 2);
    ec.searchBusy();     -- the render thread polls: THIS is what applies the timeout
    ec._onPacket(pk({ [0x04] = 2, [0x05] = 0 }));
    check('EBC18 rows refresh the deadline -- a slow stream still commits',
        ec.boxCount(21302, 15), 7);

    -- A dirty mark raised while an answer is in flight must survive that
    -- answer's commit: the server computed it BEFORE the box changed.
    ec.dirty = {};
    ec._beginRequest('category', 15);
    ec._onPacket(pk({ [0x04] = 0 }));
    ec._onPacket(pk({ [0x04] = 1, [0x08] = 0x36, [0x09] = 0x53, [0x0A] = 15, [0x0C] = 40 }));
    ec.markAllDirty();                      -- e.g. a `!box store` lands right here
    ec._onPacket(pk({ [0x04] = 2, [0x05] = 0 }));
    check('EBC19 a mark landing mid-flight is not wiped by the pre-change answer',
        ec.categoryFresh(15, math.huge), false);

    -- EBC24. THE PARTY LINE. trove speaks the same protocol on the same opcode,
    -- and the wire has no request id -- so a foreign stream landing while our
    -- GET_CATEGORY is out is consumed as OUR answer. A zero-match search in
    -- trove's Box tab therefore writes "this category is empty" over real counts,
    -- and the ahCat guard cannot see it: an empty stream has no rows to check.
    -- It cannot be PREVENTED. It has to be self-correcting, because v2 deleted
    -- the clock that used to age a wrong number out.
    ec.cat, ec.counts, ec.dirty = {}, {}, {};
    ecNow = ecNow + 100;
    ecCount(15, 21302, 40);
    ec._beginRequest('category', 15);               -- our verify goes out...
    ec._onPacket(pk({ [0x04] = 0 }));               -- ...and a FOREIGN empty stream lands
    ec._onPacket(pk({ [0x04] = 2, [0x05] = 0 }));
    check('EBC24 a zero-row stream does commit -- we cannot tell it from our own',
        ec.boxCount(21302, 15), 0);
    check('EBC24b ...but the next unsolicited stream is the TELL, and repairs it',
        ec._onPacket(pk({ [0x04] = 0 })) == false
        and ec.categoryFresh(15, math.huge) == false, true);
    ec.dirty = {};
    check('EBC24c the repair is one-shot per commit, not once per foreign packet',
        ec._onPacket(pk({ [0x04] = 0 })) == false
        and ec.categoryFresh(15, math.huge) == true, true);

    -- ...and the interleaved case, which IS detectable: two CLEARs inside one
    -- request means two streams, so the answer is taken but not believed.
    ecCount(15, 21302, 40);
    ec.dirty = {};
    ec._beginRequest('category', 15);
    ec._onPacket(pk({ [0x04] = 0 }));
    ec._onPacket(pk({ [0x04] = 1, [0x08] = 0x36, [0x09] = 0x53, [0x0A] = 15, [0x0C] = 5 }));
    ec._onPacket(pk({ [0x04] = 0 }));               -- a SECOND CLEAR: not one stream
    ec._onPacket(pk({ [0x04] = 1, [0x08] = 0x36, [0x09] = 0x53, [0x0A] = 15, [0x0C] = 9 }));
    ec._onPacket(pk({ [0x04] = 2, [0x05] = 0 }));
    check('EBC24d two interleaved streams: the answer is taken but NOT believed',
        ec.boxCount(21302, 15) == 9 and ec.categoryFresh(15, math.huge) == false, true);

    -- EBC25. THE MENU RULE (Henrik, field 2026-07-25). `!box ammo` does not
    -- withdraw -- it opens a MENU. He may browse for a minute, take one thing,
    -- take several, or cancel. So the command dirties nothing; it ARMS, and
    -- inventory movement inside that window is the proof. Cancel it and the
    -- whole episode costs zero packets.
    local ecCW3 = ec.isCW;
    ec.isCW = function() return true; end
    ec.lockedReason = nil;
    ec.cat, ec.counts, ec.dirty = {}, {}, {};
    ecNow = ecNow + 200;
    ecCount(15, 21302, 40);
    ec.dirty = {};
    ec._armMenu();
    check('EBC25 the command alone dirties NOTHING -- a menu is not a withdrawal',
        ec.categoryFresh(15, math.huge) == true and ec.menuOpen() == true, true);
    ec.markDirty(15, 'test');
    check('EBC25b while the menu is open we stay OFF the wire, dirty or not (its own\n'
       .. '      list traffic would answer our request)', ec.ensureCategory(15, math.huge), false);
    ecNow = ecNow + ec.MENU_ARM + 1;
    check('EBC25c once the menu is forgotten, the re-count goes out',
        ec.ensureCategory(15, math.huge), true);
    ecCount(15, 21302, 40);
    ec.dirty = {};
    ec._armMenu();
    check('EBC25d items actually moving is the proof we act on',
        ec._onInventoryChange() == true and ec.categoryFresh(15, math.huge) == false, true);
    -- One withdrawal is SEVERAL inventory packets (field log: two marks either
    -- side of a single "You obtain" line). A burst must read as one event --
    -- and as exactly one, not zero: the mark still has to happen.
    ecNow = ecNow + 100;               -- clear of the settle EBC25d opened
    ecCount(15, 21302, 40);
    ec.dirty = {};
    ec._armMenu();
    ec.traceReset();
    ec._onInventoryChange();
    ec._onInventoryChange();
    ec._onInventoryChange();
    local ecMarks = 0;
    for _, e in ipairs(ec.trace) do
        if e.what:find('items moved after', 1, true) ~= nil then ecMarks = ecMarks + 1; end
    end
    check('EBC25d2 a burst of inventory packets is ONE mark, not one per packet',
        ecMarks == 1 and ec.categoryFresh(15, math.huge) == false, true);
    ecCount(15, 21302, 40);
    ec.dirty = {};
    ec._armMenu();
    ecNow = ecNow + ec.MENU_ARM + 1;
    check('EBC25e a CANCELLED menu just expires, having dirtied nothing',
        ec.categoryFresh(15, math.huge) == true and ec.menuOpen() == false, true);
    check('EBC25f an inventory change with no menu armed is not our business at all',
        ec._onInventoryChange() == false and ec.categoryFresh(15, math.huge) == true, true);
    ec._armMenu();
    ec.rescan();
    check('EBC25g Rescan outranks an open menu', ec.menuOpen(), false);

    -- EBC26. The party-line repair, BRAKED. The field log showed it firing about
    -- once a second in a loop: repair -> re-count -> overlapped again -> repair.
    -- A menu being open explains the traffic, and outside that one repair per
    -- REPAIR_GAP is enough -- a repair loop is the spam this design exists to avoid.
    ec.cat, ec.counts, ec.dirty = {}, {}, {};
    ecNow = ecNow + 200;
    ecCount(15, 21302, 40);
    ec._armMenu();
    ec._onPacket(pk({ [0x04] = 0 }));                  -- foreign stream, menu open
    check('EBC26 no repair while a menu is open: that traffic is the menu, not a thief',
        ec.categoryFresh(15, math.huge), true);
    ecNow = ecNow + ec.MENU_ARM + 1;
    ecCount(15, 21302, 40);
    ec.dirty = {};
    ec._onPacket(pk({ [0x04] = 0 }));
    check('EBC26b outside a menu, a foreign stream repairs the commit it may have stolen',
        ec.categoryFresh(15, math.huge), false);
    ecCount(15, 21302, 40);
    ec.dirty = {};
    ec._onPacket(pk({ [0x04] = 0 }));
    check('EBC26c ...but at most once per REPAIR_GAP', ec.categoryFresh(15, math.huge), true);
    ecNow = ecNow + ec.REPAIR_GAP + 1;
    ecCount(15, 21302, 40);
    ec.dirty = {};
    ec._onPacket(pk({ [0x04] = 0 }));
    check('EBC26d after the gap it protects again', ec.categoryFresh(15, math.huge), false);
    ec.traceReset();
    ec._onPacket(pk({ [0x04] = 0 }));
    ec._onPacket(pk({ [0x04] = 1, [0x08] = 0x36, [0x09] = 0x53, [0x0A] = 15, [0x0C] = 5 }));
    ec._onPacket(pk({ [0x04] = 2, [0x05] = 0 }));
    check('EBC26e a foreign stream is NAMED in the log -- rows + source, so the next\n'
       .. '      field run can identify whose it is', (function()
            for _, e in ipairs(ec.trace) do
                if e.what:find('^foreign list ended: rows=1 source=0') ~= nil then return true; end
            end
            return false;
        end)(), true);
    ec.isCW = ecCW3;

    -- The gates, with the CW door propped open. Headless has no AshitaCore, so
    -- the send is a guarded no-op -- these pin the DECISION, not the wire.
    local ecCW = ec.isCW;
    ec.isCW = function() return true; end
    ec.lockedReason = nil;
    ec.cat, ec.counts, ec.dirty = {}, {}, {};
    ecNow = ecNow + 100;
    ecCount(15, 21302, 40);
    ecNow = ecNow + 100;
    check('EBC20 a believed category is not re-asked', ec.ensureCategory(15, math.huge), false);
    ec.markAllDirty(ec.SETTLE);
    check('EBC20b dirty, but the settle window holds the re-count back until the\n'
       .. '      `!box ...` we just saw can reach the server',
        ec.ensureCategory(15, math.huge), false);
    ecNow = ecNow + ec.SETTLE + 0.1;
    check('EBC20c once it has had time to land, the re-count goes out',
        ec.ensureCategory(15, math.huge), true);
    ecCount(15, 21302, 40);
    ecNow = ecNow + 100;
    ec.markAllDirty(ec.SETTLE);
    ec.rescan();
    check('EBC20d Rescan outranks the settle window (a click means count NOW)',
        ec.ensureCategory(15, math.huge), true);

    -- The ACK is the ONLY repair for a send-time debit. If it never comes, we
    -- must stop believing what we debited rather than keep a number we cannot
    -- defend. (Crafting fires no withdraws, so this costs nothing there.)
    ecCount(15, 21302, 40);
    ec.dirty = {};
    -- Driven through the REAL withdraw (not the _beginBatch seam): the categories
    -- a repair dirties are the ones the send-time debit filled in, so the fill
    -- has to be on the tested path too.
    check('EBC21pre a real withdraw fires and debits (40 - 5)',
        ec.withdraw(21302, 5) == true and ec.boxCount(21302, 15) == 35, true);
    ecNow = ecNow + ec.BUSY_HOLD + 1;
    check('EBC21 a batch that never ACKed stops believing the categories it debited',
        ec.isBusy() == false and ec.categoryFresh(15, math.huge) == false, true);
    ecCount(15, 21302, 40);
    ec.dirty = {};
    check('EBC21b withdrawBatch fires and debits the same way',
        ec.withdrawBatch({ { id = 21302, qty = 5 } }) == 1 and ec.boxCount(21302, 15) == 35, true);
    ecNow = ecNow + ec.BUSY_HOLD + 1;
    check('EBC21c a lost ACK repairs what the BATCH debited',
        ec.isBusy() == false and ec.categoryFresh(15, math.huge) == false, true);
    ec.isCW = ecCW;

    -- Source shape, because no runtime check can see this one: a local declared
    -- AFTER its use compiles to a nil GLOBAL read, silently. M.rescan uses the
    -- entwatch handle, so the require must come first -- it did not, and the box
    -- re-sweep half of Rescan had never run.
    local ecFh = io.open('feature/eboxclient.lua', 'r');
    local ecSrc = ecFh:read('*a'); ecFh:close();
    check('EBC22 entwatch is required BEFORE M.rescan reaches for it',
        (ecSrc:find('local _ewok, _ew = pcall%(require') or math.huge)
            < (ecSrc:find('function M%.rescan') or 0), true);

    -- EBC23. The traffic trace (/dl debug ebox). A design whose whole claim is
    -- "this barely sends anything" needs to be watchable, or the claim is a
    -- hope. RECORDING is all the packet thread may do; printing is eboxtrace's.
    ec.traceReset();
    for i = 1, ec.TRACE_MAX + 5 do ec._trace('>', 'GET_CATEGORY cat=' .. i); end
    check('EBC23 the ring is bounded -- a long session cannot grow it forever',
        #ec.trace, ec.TRACE_MAX);
    check('EBC23b the OLDEST lines fall off the front', ec.trace[1].what, 'GET_CATEGORY cat=6');
    check('EBC23c sends are counted, and split by kind',
        ec.stats.out == ec.TRACE_MAX + 5
        and ec.stats.byKind.GET_CATEGORY == ec.TRACE_MAX + 5, true);
    ec._trace('<', 'LIST cat=15 rows=3');
    ec._trace('*', 'dirty ALL (zone-in 0x00A)');
    check('EBC23d receives count separately; an event is neither',
        ec.stats.inn == 1 and ec.stats.out == ec.TRACE_MAX + 5, true);
    ec.traceReset();
    check('EBC23e reset clears the log AND the counters',
        #ec.trace == 0 and ec.stats.out == 0 and ec.stats.inn == 0
        and next(ec.stats.byKind) == nil, true);

    -- The PRODUCTION call sites, not just the _trace seam. Everything above
    -- drives _trace by hand, so it pins the arithmetic and nothing else: every
    -- M._trace in eboxclient could be deleted and this suite would still be
    -- green. That matters more here than usual, because the readout IS the E5-2
    -- field test -- "synth at a box, confirm zero traffic" PASSES by showing an
    -- empty log, which is exactly what a silently dead instrument shows.
    local function ecTraced(dir, pat)
        for _, e in ipairs(ec.trace) do
            if e.dir == dir and e.what:find(pat) then return true; end
        end
        return false;
    end
    local ecCW2 = ec.isCW;
    ec.isCW = function() return true; end
    ec.lockedReason = nil;
    ec.cat, ec.counts, ec.dirty = {}, {}, {};
    ecNow = ecNow + 100;
    ec.traceReset();
    check('EBC23f a real GET_CATEGORY goes out', ec.ensureCategory(15, math.huge), true);
    ecCount(15, 21302, 40);          -- a real CLEAR -> ITEM -> END_LIST commit
    ec.withdraw(21302, 5);           -- a real WITHDRAW
    ec.markDirty(15, 'EBC23g');      -- a real dirty event
    ec.isCW = ecCW2;
    check('EBC23g every production trace point records: send, inbound, dirty',
        ecTraced('>', '^GET_CATEGORY cat=15') and ecTraced('<', '^LIST cat=15')
        and ecTraced('>', '^WITHDRAW id=21302 x5') and ecTraced('*', '^dirty cat=15')
        and ec.stats.byKind.GET_CATEGORY == 1 and ec.stats.byKind.WITHDRAW == 1
        and ec.stats.inn >= 1, true);

    -- EBT. eboxtrace -- the readout itself. Pure over a stand-in client, so the
    -- shape of what Henrik reads in the field is pinned without a game.
    local et = dofile('feature/eboxtrace.lua');
    check('EBT1 ages read as time, not float noise',
        et._dur(0.4) .. '/' .. et._dur(12.34) .. '/' .. et._dur(124) .. '/' .. et._dur(3725),
        '0.4s/12.3s/2m04s/1h02m');
    check('EBT2 the argument is the SECOND word (the first is the topic name)',
        et._word('ebox on') .. '|' .. et._word('EBOX Reset') .. '|'
            .. et._word('ebox') .. '|' .. et._word(nil), 'on|reset||');

    local etFake = {
        _now        = function() return 1000; end,
        BOX_RANGE   = 5,
        busy        = false,
        isCW        = function() return true; end,
        boxDistance = function() return 3.25; end,
        searchBusy  = function() return false; end,
        cat   = { [15] = {}, [6] = {} },
        dirty = { [6] = true },
        stats = { out = 3, inn = 2, byKind = { GET_CATEGORY = 2, WITHDRAW = 1 },
                  since = 940, lastOutAt = 985 },
        trace = { { at = 985, dir = '>', what = 'GET_CATEGORY cat=15 (verify)' },
                  { at = 986, dir = '<', what = 'LIST cat=15 rows=7' } },
        echo  = false,
    };
    local etL = table.concat(et.lines(etFake), '\n');
    check('EBT3 the headline is how much, over how long',
        etL:find('3 packets sent, 2 received, over 1m00s', 1, true) ~= nil, true);
    check('EBT4 split by kind, so "what is it sending" is answerable',
        etL:find('GET_CATEGORY x2', 1, true) ~= nil and etL:find('WITHDRAW x1', 1, true) ~= nil, true);
    check('EBT5 the gates line answers "why is it quiet"',
        etL:find('Crystal Warrior', 1, true) ~= nil
        and etL:find('IN RANGE', 1, true) ~= nil
        and etL:find('last sent 15.0s ago', 1, true) ~= nil, true);
    check('EBT6 believed vs dirty = what the next verify will spend a packet on',
        etL:find('believed 15 | dirty, will re-count: 6', 1, true) ~= nil, true);
    check('EBT7 the log carries age and direction',
        etL:find('15.0s ago  > GET_CATEGORY cat=15 (verify)', 1, true) ~= nil, true);
    check('EBT8 a client that failed to load says so rather than erroring',
        et.lines(nil)[1]:find('failed to load', 1, true) ~= nil, true);

    -- RS. restockwatch -- E-Box Restock config + the two PURE cores (ADR 0016;
    -- docs/design/ebox-restock.md). No packets/engine: the union+override and the
    -- slot-safety planner are arithmetic, so the panel and the nudge share ONE answer.
    local rs = dofile('feature/restockwatch.lua');

    -- _fromTable defaults: settings default TRUE; only an explicit false turns off
    local rsd = rs._fromTable(nil);
    check('RS1 defaults: master/showNudge/onlyWhenNeeded ON, empty lists',
        rsd.master == true and rsd.showNudge == true and rsd.onlyWhenNeeded == true
        and #rsd.character == 0, true);
    local rsd2 = rs._fromTable({ master = false, character = {
        { id = 4148, name = 'Echo Drops', ahCat = 8, stack = 12, target = 12 } } });
    check('RS1b explicit master=false honored; others still default ON',
        rsd2.master == false and rsd2.showNudge == true and #rsd2.character == 1
        and rsd2.character[1].id == 4148, true);
    check('RS1c junk entries dropped (needs id AND name)',
        #rs._readList({ { name = 'x' }, { id = 5 }, { id = 9, name = 'ok' } }), 1);

    -- _merge: job overrides character on the same id; job entries come first
    local rsChar = { { id = 1, name = 'Food', ahCat = 6, stack = 12, target = 12 },
                     { id = 2, name = 'Oil',  ahCat = 8, stack = 12, target = 12 } };
    local rsRng  = { { id = 2, name = 'Oil',  ahCat = 8,  stack = 12, target = 30 },
                     { id = 3, name = 'Arrow', ahCat = 15, stack = 99, target = 99 } };
    local rsEff = rs._merge(rsChar, rsRng);
    check('RS2 effective set = job entries first, then unshadowed character',
        #rsEff == 3 and rsEff[1].id == 2 and rsEff[2].id == 3 and rsEff[3].id == 1, true);
    check('RS2b job entry overrides the character target', rsEff[1].target, 30);
    check('RS2c the override records the shadowed baseline', rsEff[1].shadow, 12);
    check('RS2d the shadowed character entry is not listed twice',
        rsEff[3].id == 1 and rsEff[3].scope == 'character', true);
    check('RS2e job with no list = plain character set', #rs._merge(rsChar, nil), 2);
    check('RS2f categoriesOf dedupes ahCats', #rs.categoriesOf(rsEff), 3);   -- 8, 15, 6

    -- plan: the worked example from the design doc (3 free Inventory slots)
    local rsOn  = { [10] = 0,  [11] = 4,  [12] = 0 };
    local rsBox = { [10] = 40, [11] = 12, [12] = 99 };
    local rsCtx = { freeSlots = 3,
        onHand  = function(id) return rsOn[id]  or 0; end,
        inBox   = function(id) return rsBox[id] or 0; end,
        stackOf = function()   return 12; end };
    local rsEntries = { { id = 10, name = 'Fire Crystal', target = 24, stack = 12 },
                        { id = 11, name = 'Sole Sushi',   target = 12, stack = 12 },
                        { id = 12, name = 'Silent Oil',   target = 24, stack = 12 } };
    local rp = rs.plan(rsEntries, rsCtx);
    check('RS3 greedy fill: two items fetched, third deferred',
        #rp.fetches == 2 and #rp.remainder == 1, true);
    check('RS3b Fire Crystal: 24 fetched = 2 stacks/slots',
        rp.fetches[1].qty == 24 and rp.fetches[1].slots == 2, true);
    check('RS3c Sole Sushi: shortfall 8 fetched = 1 slot',
        rp.fetches[2].qty == 8 and rp.fetches[2].slots == 1, true);
    check('RS3d Silent Oil deferred whole (no room left)',
        rp.remainder[1].id == 12 and rp.remainder[1].want == 24, true);
    check('RS3e all 3 slots consumed', rp.freeLeft, 0);
    check('RS3f badge counts every box-fillable shortfall (space-independent)', rp.badge, 3);
    check('RS3g pulls split into <= stack packets (12, 12, 8)',
        #rp.pulls == 3 and rp.pulls[1].qty == 12 and rp.pulls[2].qty == 12 and rp.pulls[3].qty == 8, true);

    -- plan: single-item partial fill ("space for 2 -> fetch 2, no more")
    local rp2 = rs.plan({ { id = 10, name = 'Fire Crystal', target = 24, stack = 12 } },
        { freeSlots = 1, onHand = function() return 0; end,
          inBox = function() return 40; end, stackOf = function() return 12; end });
    check('RS4 one free slot -> one stack fetched, remainder reported',
        rp2.fetches[1].qty == 12 and rp2.remainder[1].want == 12, true);

    -- plan: multi-stack split (150 of a stack-99 item -> 99 + 51 = 2 slots)
    local rp3 = rs.plan({ { id = 20, name = 'Arrow', target = 150, stack = 99 } },
        { freeSlots = 10, onHand = function() return 0; end,
          inBox = function() return 200; end, stackOf = function() return 99; end });
    check('RS5 150 @ stack 99 = 2 slots, packets 99 + 51',
        rp3.fetches[1].slots == 2 and #rp3.pulls == 2
        and rp3.pulls[1].qty == 99 and rp3.pulls[2].qty == 51, true);

    -- plan: nothing to do (at target, or box empty) -> no fetch, no badge
    local rp4 = rs.plan({ { id = 10, name = 'x', target = 5, stack = 12 } },
        { freeSlots = 9, onHand = function() return 5; end,
          inBox = function() return 40; end, stackOf = function() return 12; end });
    check('RS6 at target -> no fetch, badge 0', #rp4.fetches == 0 and rp4.badge == 0, true);
    check('RS6b box empty -> no fetch (nothing box-fillable)',
        rs.needsFetch({ { id = 10, target = 12 } },
            { freeSlots = 9, onHand = function() return 0; end,
              inBox = function() return 0; end, stackOf = function() return 12; end }), false);

    -- serialize round-trips settings + both lists
    local rsCfg = { master = false, showNudge = true, onlyWhenNeeded = false,
        character = { { id = 1, name = 'Food', ahCat = 6, stack = 12, target = 12 } },
        jobs = { RNG = { { id = 3, name = 'Arrow', ahCat = 15, stack = 99, target = 99 } } } };
    local rsBack = assert((loadstring or load)(rs._serialize(rsCfg)))();
    local rsRt = rs._fromTable(rsBack);
    check('RS7 serialize round-trips settings + lists',
        rsRt.master == false and rsRt.onlyWhenNeeded == false and rsRt.showNudge == true
        and #rsRt.character == 1 and rsRt.character[1].name == 'Food'
        and rsRt.jobs.RNG ~= nil and rsRt.jobs.RNG[1].target == 99, true);

    -- mutators (saveState no-ops headless: statePath nil pre-login)
    rs.character = {}; rs.jobs = {};
    check('RS8 addItem to the character list', rs.addItem('character', nil,
        { id = 1, name = 'Food', ahCat = 6, stack = 12 }), true);
    check('RS8b addItem defaults target to one stack', rs.character[1].target, 12);
    check('RS8c addItem dedupes by id',
        rs.addItem('character', nil, { id = 1, name = 'Food', ahCat = 6, stack = 12 }), false);
    check('RS8d addItem to a job list creates the section',
        rs.addItem('job', 'RNG', { id = 3, name = 'Arrow', ahCat = 15, stack = 99, target = 50 })
        and rs.jobs.RNG[1].target == 50, true);
    check('RS8e setTarget updates',
        rs.setTarget('character', nil, 1, 24) and rs.character[1].target == 24, true);
    check('RS8f removeItem drops it',
        rs.removeItem('job', 'RNG', 3) and #rs.jobs.RNG == 0, true);

    -- RS9. otherBagNeed -- the YELLOW icon's question (v2 grill C2): which
    -- tracked items do you already own, but not where you can use them? It
    -- qualifies only when Inventory alone is short AND another field bag holds
    -- some, which is exactly when the Inventory-only plan differs from the
    -- field-bag plan. Equal plans would mean a second icon doing the first's job.
    local rsInv   = { [1] = 1,  [2] = 12, [3] = 0 };
    local rsOther = { [1] = 11, [2] = 0,  [3] = 0 };
    local rsYCtx  = { inv   = function(id) return rsInv[id]   or 0; end,
                      other = function(id) return rsOther[id] or 0; end };
    local rsYEnt  = { { id = 1, name = 'Grape Daifuku', target = 12 },
                      { id = 2, name = 'Silent Oil',    target = 12 },
                      { id = 3, name = 'Echo Drops',    target = 12 } };
    local rsYn = rs.otherBagNeed(rsYEnt, rsYCtx);
    check('RS9 only the item short in Inventory AND held in another bag', #rsYn, 1);
    check('RS9b it reports where it is and what the box must cover',
        rsYn[1].id == 1 and rsYn[1].inv == 1 and rsYn[1].other == 11 and rsYn[1].want == 11, true);
    check('RS9c at target in Inventory -> nothing to do',
        rs.needsOtherBag({ rsYEnt[2] }, rsYCtx), false);
    check('RS9d short but nothing in the other bags -> the green icon covers it',
        rs.needsOtherBag({ rsYEnt[3] }, rsYCtx), false);
    check('RS9e the divergence itself: field-bag plan fetches nothing, Inventory-only plan fetches 11',
        (function()
            local box = function() return 99; end;
            local st  = function() return 12;  end;
            local green = rs.plan({ rsYEnt[1] }, { freeSlots = 9, inBox = box, stackOf = st,
                onHand = function(id) return (rsInv[id] or 0) + (rsOther[id] or 0); end });
            local yellow = rs.plan({ rsYEnt[1] }, { freeSlots = 9, inBox = box, stackOf = st,
                onHand = function(id) return rsInv[id] or 0; end });
            return #green.fetches == 0 and yellow.fetches[1].qty == 11;
        end)(), true);
    check('RS9f no ctx = no claims (never invent a reason to show the icon)',
        #rs.otherBagNeed(rsYEnt, nil), 0);

    -- AC. data/ammocontainers -- the quiver/pouch pairing (Henrik, field
    -- 2026-07-25). `!box ammo` hands back CONTAINERS: a Blind Bolt withdrawal
    -- arrives as a Blind Bolt Quiver, stack 12, each worth 99 bolts -- so one
    -- Inventory slot holds 1188 and NONE of it reads as "Blind Bolt". Restock
    -- saw on-hand 0 and kept offering to fetch more. Generated from the server's
    -- own item scripts, because the naming is irregular ("Beetle Arrow" ->
    -- "Beetle Quiver" drops the word, "Blind Bolt" -> "Blind Bolt Quiver"
    -- appends it) and the catalog abbreviates the containers on top of that.
    local ac = dofile('data/ammocontainers.lua');
    local acN = 0; for _ in pairs(ac) do acN = acN + 1; end
    check('AC1 the generated pairing table loads with rows', acN > 50, true);
    check('AC2 a bolt quiver names its ammo and its multiplier',
        ac[5334] ~= nil and ac[5334].id == 18150 and ac[5334].qty == 99, true);
    check('AC3 an arrow quiver too -- whose name DROPS the word "Arrow"',
        ac[4221] ~= nil and ac[4221].name == 'Beetle Quiver' and ac[4221].qty == 99, true);
    check('AC4 bullets use pouches, and dweomer/oberon are distinct ids -- the\n'
       .. '      oberon script header claims 5822 (dweomer\'s); item_basic.sql is the authority',
        ac[5822] ~= nil and ac[5823] ~= nil
        and ac[5822].id == 19198 and ac[5823].id == 19199, true);
    check('AC5 every row is usable: real container id, real ammo id, positive qty, a name',
        (function()
            for cid, r in pairs(ac) do
                if type(cid) ~= 'number' or cid <= 0 then return 'bad container id'; end
                if type(r) ~= 'table' or (tonumber(r.id) or 0) <= 0
                   or (tonumber(r.qty) or 0) <= 0
                   or type(r.name) ~= 'string' or r.name == '' then
                    return 'bad row for container ' .. tostring(cid);
                end
            end
            return true;
        end)(), true);

    -- ...and the arithmetic the panel and the nudge share. Containers count
    -- toward "do I have enough", never toward "is it in my Inventory" -- you
    -- cannot shoot a quiver, so the yellow icon must not treat one as ammo.
    local rui = dofile('ui/restockui.lua');
    check('AC6 stock = loose + what the containers hold',
        rui._stockOf({ [18150] = 12 }, { [18150] = { qty = 198, n = 2 } }, 18150), 210);
    check('AC6b no containers -> just the loose count',
        rui._stockOf({ [18150] = 12 }, {}, 18150), 12);
    check('AC6c containers only -> the whole stock is boxed',
        rui._stockOf({}, { [18150] = { qty = 1188, n = 12 } }, 18150), 1188);
    check('AC6d nothing at all -> 0', rui._stockOf({}, {}, 18150), 0);

    -- level: persisted per entry (GUI sort data; the engine ignores it --
    -- the fmt-2 round-trip above pins the serializer side)
    aw.jobsData.COR.ammo = {};
    aw.selectJob('COR');
    aw.addAmmo({ Name = 'Lv-carrier', Id = 7, AmmoType = 'Marksmanship', Level = 40 });
    check('AW16 addAmmo stores the catalog level', aw.list[1].level, 40);

    -- Sort by level: DESC, stable on ties, catalog backfill for old entries
    aw.jobsData.COR.ammo = {
        { name = 'Old NoLv',  id = 1, type = 'Marksmanship', level = 0,  ranged = true, ws = false, special = false },
        { name = 'Mid A',     id = 2, type = 'Marksmanship', level = 50, ranged = true, ws = false, special = false },
        { name = 'Top',       id = 3, type = 'Marksmanship', level = 99, ranged = true, ws = false, special = false },
        { name = 'Mid B',     id = 4, type = 'Marksmanship', level = 50, ranged = true, ws = false, special = false },
    };
    aw.selectJob('COR');   -- re-point the proxy at the fresh table
    local changed = aw.sortByLevel(function(e) return (e.name == 'Old NoLv') and 75 or 0; end);
    check('AW17 sort reordered (and said so)', changed, true);
    check('AW17b highest first', aw.list[1].name, 'Top');
    check('AW17c backfilled level slots in by its looked-up value', aw.list[2].name, 'Old NoLv');
    check('AW17d the backfill is written onto the entry', aw.list[2].level, 75);
    check('AW17e ties keep their original order (stable)',
        aw.list[3].name == 'Mid A' and aw.list[4].name == 'Mid B', true);
    check('AW17f already-sorted list reports no change', aw.sortByLevel(nil), false);

    -- Categories (field round 5): DERIVED from AmmoType + name -- the catalog
    -- lumps bullets and bolts under Marksmanship, the name splits them.
    check('AW21 bullets by name', aw.categoryOf('Bronze Bullet', 'Marksmanship'), 'Bullets');
    check('AW21b bolts by name', aw.categoryOf('Bloody Bolt', 'Marksmanship'), 'Bolts');
    check('AW21c name match is ci', aw.categoryOf('SPARTAN BULLET', 'Marksmanship'), 'Bullets');
    check('AW21d archery = arrows regardless of name', aw.categoryOf('Kabura Arrow', 'Archery'), 'Arrows');
    check('AW21e throwing keeps its own bucket', aw.categoryOf('Fuma Shuriken', 'Throwing'), 'Throwing');
    check('AW21f unmatched marksmanship falls to Other', aw.categoryOf('Gold Quarrel', 'Marksmanship'), 'Other');
    check('AW21g trinket-ish types fall to Other', aw.categoryOf('Tiphia Sting', ''), 'Other');
    -- v128: the EXACT split, from the server's own subskill, with the name kept only
    -- as the fallback for entries added before Pair existed.
    check('AW21h pair beats the name split -- bullets', aw.categoryOf('Whatsit', 'Marksmanship', '26:1'), 'Bullets');
    check('AW21i pair beats the name split -- bolts',   aw.categoryOf('Whatsit', 'Marksmanship', '26:0'), 'Bolts');
    -- The real datum that proves the name heuristic was never enough: Hauksbok
    -- Bullet is server skill 26 SUBSKILL 0, i.e. a bolt. The name says Bullets and
    -- is wrong; a crossbow is what actually fires it.
    check('AW21j Hauksbok Bullet is a BOLT by subskill, whatever its name says',
        aw.categoryOf('Hauksbok Bullet', 'Marksmanship', '26:0'), 'Bolts');
    check('AW21k ...and the name alone still gets it wrong (why Pair wins)',
        aw.categoryOf('Hauksbok Bullet', 'Marksmanship'), 'Bullets');
    check('AW21l culverin shells have no tab of their own', aw.categoryOf('Cannon Shell', 'Marksmanship', '26:2'), 'Other');
    -- categoryForPair answers for the RANGE weapon too -- one key space, both sides.
    check('AW21m a gun fires Bullets',      aw.categoryForPair('26:1'), 'Bullets');
    check('AW21n a crossbow fires Bolts',   aw.categoryForPair('26:0'), 'Bolts');
    check('AW21o a longbow fires Arrows',   aw.categoryForPair('25:4'), 'Arrows');
    check('AW21p a shortbow fires Arrows',  aw.categoryForPair('25:0'), 'Arrows');
    check('AW21q a boomerang fires Throwing', aw.categoryForPair('27:0'), 'Throwing');
    check('AW21r a harp fires nothing we tab', aw.categoryForPair('41:0'), nil);
    check('AW21s a skill-only key cannot pick gun-vs-crossbow', aw.categoryForPair('26'), nil);
    check('AW21t no key at all is nil, never a guess', aw.categoryForPair(nil), nil);
    -- The pair must survive the file: it is what the engine pairs against Range.
    do
        local round = (loadstring or load)(aw._serialize({ COR = { enabled = true, at = 7, ammo = {
            { name = 'Gold Bullet', id = 12, type = 'Marksmanship', pair = '26:1',
              level = 40, ranged = true, ws = false, special = false },
            { name = 'Old Entry',   id = 13, type = 'Marksmanship',
              level = 1,  ranged = true, ws = false, special = false },
        } } }))();
        -- backfillPairs: the GUI teaching pre-v128 entries their key, across EVERY job.
    do
        local savedJobs, savedJob = aw.jobsData, aw.job;
        aw.jobsData = {
            RNG = { enabled = true, at = 0, ammo = {
                { name = 'Iron Bullet', id = 17312, type = 'Marksmanship', ranged = true,  ws = false, special = false },
                { name = 'Venom Bolt',  id = 18152, type = 'Marksmanship', ranged = false, ws = false, special = false },
            } },
            COR = { enabled = false, at = 0, ammo = {
                { name = 'Gold Bullet', id = 12, type = 'Marksmanship', pair = '26:1', ranged = true, ws = false, special = false },
            } },
        };
        local KEY = { [17312] = '26:1', [18152] = '26:0', [12] = '26:1' };
        local n = aw.backfillPairs(function(id) return KEY[id]; end);
        check('AW21w backfill stamps every job, not just the selected one', n, 2);
        check('AW21x the bullet learns 26:1', aw.jobsData.RNG.ammo[1].pair, '26:1');
        check('AW21y ...and the bolt learns 26:0, which is the whole point',
              aw.jobsData.RNG.ammo[2].pair, '26:0');
        check('AW21z a second sweep finds nothing (insert-only, idempotent)',
              aw.backfillPairs(function(id) return KEY[id]; end), 0);
        aw.jobsData, aw.job = savedJobs, savedJob;
    end
    check('AW21u serialize/load round-trips the pair', round.jobs.COR.ammo[1].pair, '26:1');
        check('AW21v an entry with no pair stays without one (never invented)',
            round.jobs.COR.ammo[2].pair, nil);
    end

    -- swapAmmo: the filtered view's move (non-adjacent underneath)
    aw.jobsData.COR.ammo = {
        { name = 'A', id = 1, type = 'Marksmanship', level = 1, ranged = true, ws = false, special = false },
        { name = 'B', id = 2, type = 'Archery',      level = 1, ranged = true, ws = false, special = false },
        { name = 'C', id = 3, type = 'Marksmanship', level = 1, ranged = true, ws = false, special = false },
    };
    aw.selectJob('COR');
    aw.swapAmmo(1, 3);
    check('AW22 swapAmmo swaps non-adjacent positions',
        aw.list[1].name == 'C' and aw.list[3].name == 'A' and aw.list[2].name == 'B', true);
    aw.swapAmmo(1, 9);
    check('AW22b out-of-bounds swap is a no-op', aw.list[1].name, 'C');
end)();

-- ---------------------------------------------------------------------------
-- UR. useitem exp rings -- Venture Ring is the LAST exp ring (issue #62).
--     Data-shape pin: name + position (after Echad Ring) + alias resolution.
--     useitem loads headlessly (its Ashita bindings are pcall-guarded); a tiny
--     inventory stub reports Echad + Venture owned so the owned-only xp menu
--     rows surface, and the /dl xp venture command path proves the alias.
-- ---------------------------------------------------------------------------
(function()
    local savedReg = ashita.events.register;
    local cmdHandler = nil;
    ashita.events.register = function(evt, name, fn)   -- capture the /dl command handler
        if evt == 'command' then cmdHandler = fn; end
    end;
    package.loaded['dlac\\chatfmt'] = { print = function() end };   -- silence module output

    -- minimal AshitaCore: an inventory holding the two exp rings we assert on,
    -- plus the chat manager start() queues its /equip through.
    local nameById = { [1001] = 'Echad Ring', [1002] = 'Venture Ring' };
    local bag0 = { { Id = 1001, Count = 1, Extra = '' }, { Id = 1002, Count = 1, Extra = '' } };
    local inv = {
        GetContainerCountMax = function(self, bag) return (bag == 0) and #bag0 or 0; end,
        GetContainerItem = function(self, bag, i) return (bag == 0) and bag0[i] or nil; end,
    };
    AshitaCore = {
        GetMemoryManager = function(self) return { GetInventory = function() return inv; end }; end,
        GetResourceManager = function(self) return {
            GetItemById = function(self2, id) return { Name = { nameById[id] }, MaxCharges = 0 }; end,
        }; end,
        GetChatManager = function(self) return { QueueCommand = function() end }; end,
    };

    local useitem = dofile('feature/useitem.lua');
    ashita.events.register = savedReg;   -- restore

    -- data shape: the xp-group menu rows, in menu order (== EXPRINGS order)
    local xp = {};
    for _, row in ipairs(useitem.menu()) do
        if row.grp == 'xp' then xp[#xp + 1] = row; end
    end
    local last = xp[#xp];
    check('UR1 last exp ring is Venture Ring', last and last.name, 'Venture Ring');
    check('UR1b ...labelled Venture', last and last.label, 'Venture');
    check('UR1c ...aliased venture (menu cmd)', last and last.cmd, '/dl xp venture');
    check('UR1d ...positioned after Echad Ring', xp[#xp - 1] and xp[#xp - 1].name, 'Echad Ring');

    -- alias resolution: /dl xp venture resolves the ring and stages it
    check('UR2 command handler registered', type(cmdHandler), 'function');
    if cmdHandler ~= nil then cmdHandler({ command = '/dl xp venture' }); end
    local pend = useitem.pending();
    check('UR3 /dl xp venture staged the ring', pend and pend.name, 'Venture Ring');

    AshitaCore = nil;   -- leave the harness as we found it
end)();

-- ---------------------------------------------------------------------------
-- UT. useitem utility teleports (Henrik, 2026-07-23): the 'util' family
--     (Maat's Cap, Ducal Guard's Ring, stables gear, the Purgonorgo suits...)
--     is owned-only in the menu, Kazham Earring joins the ear cascade as a
--     dim-able row, Maat's Cap alone stays visible to the set-building picker
--     (+7 all stats = real gear), and a multi-hit /dl t query narrows to the
--     item you OWN (8 suits share dest 'Purgonorgo'; 4 stables destinations
--     share the substring 'stables'). Stub inventory: Maat's Cap + Custom
--     Top +1 + Republic Stables Medal, real ids so the load-time id->name
--     resolution exercises too.
-- ---------------------------------------------------------------------------
(function()
    local savedReg = ashita.events.register;
    local cmdHandler = nil;
    ashita.events.register = function(evt, name, fn)
        if evt == 'command' then cmdHandler = fn; end
    end;
    package.loaded['dlac\\chatfmt'] = { print = function() end };

    local nameById = {
        [15194] = "Maat's Cap",              -- head, keepInPicker
        [11274] = 'Custom Top +1',           -- body, one of the 8 Purgonorgo suits
        [13180] = 'Republic Stables Medal',  -- neck, one of 4 'stables' dests
        [11538] = 'Nexus Cape',              -- moved off the top strip 2026-07-26
        [26517] = 'Shadow Lord Shirt',       -- ditto
    };
    local bag0 = {
        { Id = 15194, Count = 1, Extra = '' },
        { Id = 11274, Count = 1, Extra = '' },
        { Id = 13180, Count = 1, Extra = '' },
        { Id = 11538, Count = 1, Extra = '' },
        { Id = 26517, Count = 1, Extra = '' },
    };
    local inv = {
        GetContainerCountMax = function(self, bag) return (bag == 0) and #bag0 or 0; end,
        GetContainerItem = function(self, bag, i) return (bag == 0) and bag0[i] or nil; end,
    };
    AshitaCore = {
        GetMemoryManager = function(self) return { GetInventory = function() return inv; end }; end,
        GetResourceManager = function(self) return {
            GetItemById = function(self2, id)
                if nameById[id] == nil then return nil; end   -- unstubbed ids: fallback literals stand
                return { Name = { nameById[id] }, MaxCharges = 0 };
            end,
        }; end,
        GetChatManager = function(self) return { QueueCommand = function() end }; end,
    };

    local useitem = dofile('feature/useitem.lua');
    ashita.events.register = savedReg;

    -- menu shape: util rows are owned-only -- exactly the five stubbed items
    local util, earNames, topNames = {}, {}, {};
    for _, row in ipairs(useitem.menu()) do
        if row.grp == 'util' then util[#util + 1] = row; end
        if row.grp == 'ear' then earNames[#earNames + 1] = row.name; end
        if row.grp == nil then topNames[#topNames + 1] = row.name; end
    end
    check('UT1 util tier is owned-only (5 rows)', #util, 5);
    local haveMaat = false;
    for _, r in ipairs(util) do if r.name == "Maat's Cap" then haveMaat = true; end end
    check('UT1b Maat\'s Cap surfaced', haveMaat, true);
    -- Nexus Cape + Shadow Lord Shirt moved OFF the instant/panic strip into the
    -- "Other Teleports" cascade (Henrik, 2026-07-26) -- they are 30s enchants to a
    -- fixed destination, not instant options. They LEAD the cascade (MENU order).
    check('UT1c Nexus Cape leads the util tier',   util[1] and util[1].name, 'Nexus Cape');
    check('UT1d Shadow Lord Shirt follows it',     util[2] and util[2].name, 'Shadow Lord Shirt');
    check('UT1e neither is left on the top strip',
        (function()
            for _, n in ipairs(topNames) do
                if n == 'Nexus Cape' or n == 'Shadow Lord Shirt' then return n; end
            end
            return '';
        end)(), '');
    -- Kazham Earring: a dim not-owned row INSIDE the ear cascade, after Norg
    local kazhamAt, norgAt = nil, nil;
    for i, n in ipairs(earNames) do
        if n == 'Kazham Earring' then kazhamAt = i; end
        if n == 'Norg Earring' then norgAt = i; end
    end
    check('UT2 Kazham Earring rides the ear cascade', kazhamAt ~= nil, true);
    check('UT2b ...right after Norg', kazhamAt, (norgAt or 0) + 1);
    -- picker hide: Maat's Cap is EXEMPT (real gear), the trinketry is hidden
    local hide = useitem.menuNames();
    check('UT3 Maat\'s Cap stays in the picker', hide["maat's cap"], nil);
    check('UT3b Tavnazian Ring hidden from the picker', hide['tavnazian ring'], true);
    check('UT3c suits hidden from the picker', hide['custom top +1'], true);
    check('UT3d earrings still hidden', hide['kazham earring'], true);

    -- command narrowing
    check('UT4 command handler registered', type(cmdHandler), 'function');
    if cmdHandler ~= nil then
        cmdHandler({ command = '/dl t maat' });
        local p = useitem.pending();
        check('UT5 /dl t maat stages Maat\'s Cap', p and p.name, "Maat's Cap");
        cmdHandler({ command = '/dl t purgonorgo' });
        p = useitem.pending();
        check('UT6 /dl t purgonorgo narrows 8 suits to the owned one', p and p.name, 'Custom Top +1');
        cmdHandler({ command = '/dl t stables' });
        p = useitem.pending();
        check('UT7 /dl t stables narrows 4 stables to the owned one', p and p.name, 'Republic Stables Medal');
        cmdHandler({ command = '/dl t outpost' });   -- Return+Homing share the dest, neither owned
        p = useitem.pending();
        check('UT8 unowned same-dest pair refuses (pending unchanged)', p and p.name, 'Republic Stables Medal');
        cmdHandler({ command = '/dl t off' });
        check('UT9 /dl t off releases', useitem.pending(), nil);
    end

    AshitaCore = nil;
end)();

-- ---------------------------------------------------------------------------
-- RLD. /dl reload targets DLAC (Henrik, 2026-07-26): utils.lua's reload
--      branch queued '/addon reload luashitacast' from the LAC-hosted era --
--      on a migrated (native) install that RESURRECTED LuaAshitacast and
--      fired the coexistence tripwire (the field limbo of 2026-07-26). It now
--      reloads dlac itself. Drive the REAL /dl handler utils.lua registers at
--      load; a recording chat manager proves what got queued. Heavy deps are
--      pre-seeded (and restored) so the re-load exercises only the handler --
--      pcall'd requires resolving from disk with '\\' paths would break the
--      WSL parity run.
-- ---------------------------------------------------------------------------
(function()
    local savedReg = ashita.events.register;
    local cmdHandler = nil;
    ashita.events.register = function(evt, name, fn)
        if evt == 'command' and name == 'dlac' then cmdHandler = fn; end
    end;
    local savedLoaded = {
        ['dlac\\gear']     = package.loaded['dlac\\gear'],
        ['dlac\\chatfmt']  = package.loaded['dlac\\chatfmt'],
        ['dlac\\dispatch'] = package.loaded['dlac\\dispatch'],
    };
    package.loaded['dlac\\gear']     = savedLoaded['dlac\\gear'] or {};
    package.loaded['dlac\\chatfmt']  = { print = function() end };
    package.loaded['dlac\\dispatch'] = { dispatch = function() end };

    local sent = {};
    local savedCore = AshitaCore;
    AshitaCore = {
        GetChatManager = function(self)
            return { QueueCommand = function(_, mode, cmd) sent[#sent + 1] = cmd; end };
        end,
    };

    dofile('utils.lua');
    ashita.events.register = savedReg;
    for k, v in pairs(savedLoaded) do package.loaded[k] = v; end

    check('RLD1 /dl command handler registered', type(cmdHandler), 'function');
    if cmdHandler ~= nil then
        cmdHandler({ command = '/dl reload' });
        check('RLD2 /dl reload queues a dlac reload', sent[#sent], '/addon reload dlac');
        cmdHandler({ command = '/dl r' });
        check('RLD3 /dl r is the same reload', sent[#sent], '/addon reload dlac');
        check('RLD4 nothing queued touches luashitacast',
              table.concat(sent, ' | '):find('luashitacast', 1, true), nil);
        local n = #sent;
        cmdHandler({ command = '/dl why' });   -- an unrelated /dl word queues nothing here
        check('RLD5 other subcommands queue nothing', #sent, n);
    end

    AshitaCore = savedCore;
end)();

-- ---------------------------------------------------------------------------
-- FW. GUI content-follow (2026-07-22): a Profiles-menu import rewrites the
--     ACTIVE profile's files for the CURRENT job -- same cache keys, new
--     bytes. The engine already follows (queued reloads + its own content
--     watches); these pin the three ADDON-state readers that used to serve
--     the PREVIOUS profile until a job flip (field case: importing a BLU
--     export while ON BLU left the Triggers tab listing the old profile's
--     sets as [missing], and a stale Commit could write the old rules back
--     over the import).
-- ---------------------------------------------------------------------------

-- TGW. Triggers tab follow decision (ui/triggersui.lua : M._followTriggers).
--      The tab is an EDITOR: clean models follow the disk; a dirty model is
--      never clobbered and never silently clobbers -- 'drift' renders the red
--      banner (Commit = yours wins, Revert = disk wins).
(function()
    local tri = dofile('ui/triggersui.lua');
    check('TGW0 triggersui loads headless', type(tri), 'table');
    local f = tri._followTriggers;
    check('TGW1 pure decision exported', type(f), 'function');
    check('TGW2 same bytes keep (clean)', f('A', 'A', false), 'keep');
    check('TGW3 same bytes keep (dirty)', f('A', 'A', true), 'keep');
    check('TGW4 changed bytes + clean tab reload', f('B', 'A', false), 'reload');
    check('TGW5 changed bytes + dirty tab DRIFT (never clobber edits)', f('B', 'A', true), 'drift');
    check('TGW6 file deleted + clean tab reload', f(nil, 'A', false), 'reload');
    check('TGW7 file deleted + dirty tab drift', f(nil, 'A', true), 'drift');
    check('TGW8 file appeared under an empty tab reloads', f('A', nil, false), 'reload');
end)();

-- PSW. profilesets content-follow: changed Dynamic-source bytes rebuild the
--      cached root WITHOUT an explicit invalidate() call (the import path
--      never had one). Headless there is no char dir, so the profile-storage
--      tier reads absent and the legacy job-file branch carries the test --
--      the watch mechanism is the same for both sources.
(function()
    local ps = dofile('gear/profilesets.lua');
    check('PSW0 profilesets loads headless', type(ps), 'table');
    local TMP = 'tests/_tmp_psw_job.lua';
    local function writeTmp(setName)
        local f = assert(io.open(TMP, 'w'));
        f:write('local profile = {};\nlocal sets = { Dynamic = { ' .. setName
            .. ' = {} } };\nprofile.Sets = sets;\nreturn profile;\n');
        f:close();
    end
    writeTmp('SetA');
    ps.configure({ jobFile = function() return TMP, 'BLU'; end });
    check('PSW1 initial read sees SetA', ps.liveSetNames()[1], 'SetA');
    writeTmp('SetB');                    -- the "import": same path, new bytes
    ps._recheck();                       -- arm past the 1s throttle (tests)
    local n2 = ps.liveSetNames();
    check('PSW2 changed bytes rebuild the cache (no invalidate call)', n2[1], 'SetB');
    check('PSW2b the old name is gone', #n2, 1);
    ps._recheck();
    check('PSW3 unchanged bytes keep the answer', ps.liveSetNames()[1], 'SetB');
    os.remove(TMP);
end)();

-- LGW. lockstyle boxes follow decision (feature/lockstyle.lua : M._followBoxes).
--      Boxes save on click (no tab-level dirty state), so changed bytes always
--      follow; only the 4x4's mid-edit working copy is carried across.
(function()
    local ls = dofile('feature/lockstyle.lua');
    local f = ls._followBoxes;
    check('LGW1 pure decision exported', type(f), 'function');
    check('LGW2 same bytes keep', f('A', 'A', false), 'keep');
    check('LGW3 same bytes keep (mid-edit)', f('A', 'A', true), 'keep');
    check('LGW4 changed bytes follow', f('B', 'A', false), 'follow');
    check('LGW5 changed bytes mid-edit follow but KEEP the 4x4', f('B', 'A', true), 'follow-keep-edit');
    check('LGW6 file appeared follows', f('A', nil, false), 'follow');
    check('LGW7 file deleted follows (back to defaults)', f(nil, 'A', false), 'follow');
end)();

-- CHK. /dl check -- the general-health readout (feature/check.lua; issue
--      verdict per Henrik 07-23: "good IF it checks the general health of dl
--      and can report issues"): the pure seams. The field case it answers:
--      engine absent from the LAC state = total silence on '/dl ls apply' --
--      so the addon half must SAY that a missing engine line is the diagnosis.
(function()
    local ck = dofile('feature/check.lua');
    check('CHK0 check loads headless', type(ck), 'table');
    check('CHK1 seeded copies current', ck._seededState({
        { name = 'utils.lua', addon = 'x', seeded = 'x' },
        { name = 'dispatch.lua', addon = 'y', seeded = 'y' } }), 'current');
    check('CHK2 stale + missing seeded copies are NAMED', ck._seededState({
        { name = 'utils.lua', addon = 'x', seeded = 'y' },
        { name = 'chatfmt.lua', addon = 'z', seeded = 'z' },
        { name = 'dispatch.lua', addon = 'w', seeded = nil } }), 'STALE: utils.lua, dispatch.lua');
    check('CHK3 unreadable tree copy counts stale', ck._seededState({
        { name = 'utils.lua', addon = nil, seeded = 'x' } }), 'STALE: utils.lua');
    check('CHK4 clean shim word', ck._shimWord('ok'), 'clean dlac shim');
    check('CHK5 wired sends to Setup', ck._shimWord('wired'):find('Setup', 1, true) ~= nil, true);
    check('CHK6 ffxilac sends to Setup', ck._shimWord('ffxilac'):find('Setup', 1, true) ~= nil, true);
    check('CHK7 nofile sends to Setup', ck._shimWord('nofile'):find('Setup', 1, true) ~= nil, true);
    local HEALTHY = { addonVer = '2026.07.23c', fileV = 104, seeded = 'current', shim = 'ok', stampV = 104,
                      modules = { total = 17, failed = {} }, catalogTried = true, catalogN = 14874,
                      gearN = 312, profName = 'Default' };
    local L = ck._lines(HEALTHY);
    check('CHK8 six addon lines', #L, 6);
    check('CHK9 versions on line 1', L[1]:find('2026.07.23c', 1, true) ~= nil and L[1]:find('v104', 1, true) ~= nil, true);
    check('CHK10 the engine line is named verbatim', L[5]:find('[dlac] check (engine): alive', 1, true) ~= nil, true);
    check('CHK11 absence = diagnosis is said', L[5]:find('not running the dlac engine', 1, true) ~= nil, true);
    check('CHK12 stamp rides the engine line', L[5]:find('last stamped v104', 1, true) ~= nil, true);
    check('CHK13 modules line counts', L[3]:find('17/17 loaded', 1, true) ~= nil, true);
    check('CHK14 data line carries catalog/gear/profile', L[4]:find('14874 items', 1, true) ~= nil
          and L[4]:find('312 entries', 1, true) ~= nil and L[4]:find('"Default"', 1, true) ~= nil, true);
    check('CHK15 healthy = NO ISSUES verdict', L[6]:find('NO ISSUES', 1, true) ~= nil, true);
    local L2 = ck._lines({ addonVer = 'x', fileV = nil, seeded = nil, shim = 'nojob', stampV = nil });
    check('CHK16 never-stamped is said', L2[5]:find('NEVER stamped', 1, true) ~= nil, true);
    check('CHK17 pre-login degrades honestly, not as issues', L2[1]:find('not logged in', 1, true) ~= nil
          and L2[6]:find('NO ISSUES', 1, true) ~= nil, true);
    -- the issue hunt (CHKI): each provable problem is NAMED in the verdict.
    -- override helper: `false` means "unset" (a literal nil never survives
    -- pairs -- the classic Lua table trap).
    local function issuesOf(t) local base = {};
        for k, v in pairs(HEALTHY) do base[k] = v; end
        for k, v in pairs(t) do if v == false then base[k] = nil; else base[k] = v; end end
        return ck._issues(base);
    end
    check('CHKI1 healthy hunts nothing', #ck._issues(HEALTHY), 0);
    check('CHKI2 stale seeded is an issue', issuesOf({ seeded = 'STALE: dispatch.lua' })[1]
          :find('STALE', 1, true) ~= nil, true);
    check('CHKI3 stamp behind file -> Reload LAC', issuesOf({ stampV = 98 })[1]
          :find('Reload LAC', 1, true) ~= nil, true);
    check('CHKI4 stamp ahead of file -> stale tree', issuesOf({ fileV = 98 })[1]
          :find('tree is stale', 1, true) ~= nil, true);
    check('CHKI5 module failures named', issuesOf({ modules = { total = 17,
          failed = { { mod = 'feature\\lockstyle', err = 'boom' } } } })[1]
          :find('feature\\lockstyle', 1, true) ~= nil, true);
    check('CHKI6 unreadable catalog is an issue', issuesOf({ catalogN = false })[1]
          :find('UNREADABLE', 1, true) ~= nil, true);
    check('CHKI7 truncated catalog is an issue', issuesOf({ catalogN = 4200 })[1]
          :find('truncated', 1, true) ~= nil, true);
    check('CHKI8 non-shim job file is an issue', issuesOf({ shim = 'wired' })[1]
          :find('Setup', 1, true) ~= nil, true);
    check('CHKI9 nojob is NOT an issue', #issuesOf({ shim = 'nojob' }), 0);
    check('CHKI10 verdict counts multiple issues', ck._lines({ addonVer = 'x', fileV = 104,
          seeded = 'STALE: utils.lua', shim = 'wired', stampV = 98,
          modules = { total = 17, failed = {} }, catalogTried = true, catalogN = 14874 })[6]
          :find('3 ISSUES', 1, true) ~= nil, true);
end)();

-- DBT. the /dl debug section router (feature/debug.lua, v104): topic
--      normalization + the one usage printer.
(function()
    local dbg = dofile('feature/debug.lua');
    check('DBT0 debug router loads headless', type(dbg), 'table');
    check('DBT1 ls is canonical', dbg._topic('ls'), 'ls');
    check('DBT2 lockstyle aliases to ls', dbg._topic('lockstyle'), 'ls');
    check('DBT2b ebox is a topic (alias: box) -- E-Box traffic readout',
        dbg._topic('ebox') == 'ebox' and dbg._topic('BOX') == 'ebox', true);

    -- DBT2c-2h. THE PREFIX. '^/dlac?' is "/dla with an optional c", not "/dl or
    -- /dlac" -- so `/dl debug <topic>` never reached this router at all, and a
    -- handler that does not fire is indistinguishable from a command that does
    -- nothing. Field-found 07-25 (`/dl debug ebox` printed nothing). Pin BOTH
    -- prefixes, and pin that the bare/on/off forms still fall through to
    -- gearui's dev-buttons toggle, the namespace's original tenant.
    check('DBT2c /dl debug <topic> reaches the router', dbg._afterDebug('/dl debug ebox'), 'ebox');
    check('DBT2d /dlac debug <topic> too', dbg._afterDebug('/dlac debug ebox'), 'ebox');
    check('DBT2e arguments ride along', dbg._afterDebug('/dl debug ebox on'), 'ebox on');
    check('DBT2f the bare form is "" (not nil): gearui still owns it',
        dbg._afterDebug('/dl debug') == '' and dbg._afterDebug('/dlac debug  ') == '', true);
    check('DBT2g another command is not ours',
        dbg._afterDebug('/dl check') == nil and dbg._afterDebug('/dldebug ebox') == nil, true);
    check('DBT2h and neither is a longer prefix that merely starts the same way',
        dbg._afterDebug('/dlacx debug ebox'), nil);
    check('DBT3 case-insensitive', dbg._topic('LOCKSTYLE'), 'ls');
    check('DBT4 unknown topic is nil (usage)', dbg._topic('fish'), nil);
    check('DBT5 absent topic is nil (usage)', dbg._topic(nil), nil);
    check('DBT6 usage names ls + the alias', dbg._usage():find('ls', 1, true) ~= nil
          and dbg._usage():find('lockstyle', 1, true) ~= nil, true);

    -- DBF. the transfer-file assembly (Henrik's file rule): engine half by
    --      handoff, freshness by stamp, absence/staleness written INTO the file.
    local now = 1753300000;
    local A = { 'line one', 'line two' };
    local fresh = tostring(now - 2) .. '\nalive v105\nbox 1 ok\n';
    local txt = dbg._mergeSections('debug ls', A, fresh, now, '2026.07.23d');
    check('DBF1 header carries label + version', txt:find('dlac debug ls', 1, true) ~= nil
          and txt:find('2026.07.23d', 1, true) ~= nil, true);
    check('DBF2 both halves sectioned', txt:find('== addon half ==', 1, true) ~= nil
          and txt:find('== engine half ==', 1, true) ~= nil, true);
    check('DBF3 fresh handoff lines ride whole', txt:find('alive v105', 1, true) ~= nil
          and txt:find('box 1 ok', 1, true) ~= nil and txt:find('line two', 1, true) ~= nil, true);
    local txt2 = dbg._mergeSections('debug ls', A, nil, now, 'v');
    check('DBF4 missing handoff = the diagnosis, in the file', txt2:find('ENGINE HALF MISSING', 1, true) ~= nil
          and txt2:find('not running the dlac engine', 1, true) ~= nil, true);
    local txt3 = dbg._mergeSections('debug ls', A, tostring(now - 60) .. '\nold lines\n', now, 'v');
    check('DBF5 stale handoff = stale verdict, old lines withheld', txt3:find('ENGINE HALF STALE', 1, true) ~= nil
          and txt3:find('old lines', 1, true) == nil, true);
    check('DBF6 filenames sanitize to letters/digits', dbg._safeName("O'harra-2"), 'Oharra2');
    check('DBF7 no name = unknown', dbg._safeName(nil), 'unknown');
    local txt4 = dbg._mergeSections('check', A, false, now, 'v');
    check('DBF8 provisional write = PENDING + the tick tripwire', txt4:find('PENDING', 1, true) ~= nil
          and txt4:find('never', 1, true) ~= nil and txt4:find('line two', 1, true) ~= nil, true);

    -- the capture-window length (v106): 30-120 clamp, default 45 -- the
    -- engine's debug branch clamps identically (twin constants).
    check('DBT7 no arg = 45s default', dbg._dur(nil), 45);
    check('DBT8 explicit seconds ride', dbg._dur('60'), 60);
    check('DBT9 short floors to 30', dbg._dur('5'), 30);
    check('DBT10 long caps at 120', dbg._dur('999'), 120);
    check('DBT11 garbage = default', dbg._dur('soon'), 45);

    -- DBW. the command-event fallback decision (07-23: the addon state heard
    --      NO typed /dl while the engine heard every one -- the addon now
    --      follows the engine's handoff stamps).
    local now = 1753300000;
    check('DBW1 no stamp = keep', dbg._watchFire(nil, nil, now, true), 'keep');
    check('DBW2 same stamp = keep', dbg._watchFire(now - 2, now - 2, now, true), 'keep');
    check('DBW3 new stale stamp adopts quietly', dbg._watchFire(now - 300, nil, now, true), 'adopt-quiet');
    check('DBW4 new fresh stamp + commands alive stays quiet', dbg._watchFire(now - 2, nil, now, false), 'adopt-quiet');
    check('DBW5 new fresh stamp + commands dead FIRES', dbg._watchFire(now - 2, nil, now, true), 'adopt-fire');
end)();

-- DBG. '/dl debug ls' engine dry-run report (dispatch M._lsDebugReport):
--      the apply pipeline's outcome as lines, injected resolvers, no send.
(function()
    local t = { active = 1, slots = {
        [1] = { name = 'Look', set = { Body = "Arhat's Gi", Head = 'Ghost Cap', Feet = 'remove' } },
        [2] = { name = 'Empty', set = {} } } };
    local ids = { ["Arhat's Gi"] = 12345 };            -- Ghost Cap does NOT resolve
    local function resolveId(nm) return ids[nm]; end
    local function equippedId(slot) return nil; end
    local L = dispatchM._lsDebugReport(t, nil, resolveId, equippedId, nil);
    check('DBG1 header names box + styled count', L[1]:find('box 1 "Look"', 1, true) ~= nil
          and L[1]:find('1 slot would style', 1, true) ~= nil, true);
    check('DBG2 unresolvable name is listed', L[2]:find('Ghost Cap', 1, true) ~= nil, true);
    check('DBG3 dry-run line is last', L[#L]:find('nothing was sent', 1, true) ~= nil, true);
    local Lg = dispatchM._lsDebugReport(t, 1, resolveId, equippedId,
        function(nm) return nm == "Arhat's Gi"; end);
    local gline = nil;
    for _, l in ipairs(Lg) do if l:find('KEEP OLD LOOK', 1, true) then gline = l; end end
    check('DBG4 gate prediction names slot=piece', gline ~= nil
          and gline:find("Body=Arhat's Gi", 1, true) ~= nil, true);
    check('DBG5 empty box refuses like apply', dispatchM._lsDebugReport(t, 2, resolveId, equippedId, nil)[1],
          'apply would refuse: lockstyle box 2 has no items');
    check('DBG6 no file refuses like apply', dispatchM._lsDebugReport(nil, nil, resolveId, equippedId, nil)[1],
          'apply would refuse: no lockstyle sets saved yet');
    -- the capture-window flush (v106): snapshot + timeline -> handoff lines.
    local F = dispatchM._lsDbgFlushLines({ 'alive v106' }, { 't+  1.0s  apply received' }, 45);
    check('DBG7 flush = snapshot then timeline', F[1] == 'alive v106'
          and F[2]:find('captured events, engine side (45s window)', 1, true) ~= nil
          and F[3]:find('apply received', 1, true) ~= nil, true);
    check('DBG8 empty window says so', dispatchM._lsDbgFlushLines({}, {}, 30)[2],
          '(no lockstyle events reached this engine during the window)');

    -- DBR. the engine's request watch (v108): twin of the addon's
    --      _watchFire -- fires only on a NEW fresh stamp while the engine's
    --      own command handlers sit idle (the friend's starvation direction).
    local rnow = 1753300000;
    check('DBR1 no stamp = keep', dispatchM._reqFire(nil, nil, rnow, true), 'keep');
    check('DBR2 same stamp = keep', dispatchM._reqFire(rnow - 2, rnow - 2, rnow, true), 'keep');
    check('DBR3 fresh + idle FIRES', dispatchM._reqFire(rnow - 2, nil, rnow, true), 'adopt-fire');
    check('DBR4 fresh + commands alive stays quiet', dispatchM._reqFire(rnow - 2, nil, rnow, false), 'adopt-quiet');
    check('DBR5 stale adopts quietly', dispatchM._reqFire(rnow - 300, nil, rnow, true), 'adopt-quiet');
    -- the spec line parser (v109: apply joins check/ls on the request file)
    check('DBR6 check spec', dispatchM._reqSpec('check'), 'check');
    local k7, n7 = dispatchM._reqSpec('ls 60');
    check('DBR7 ls spec carries dur', k7 == 'ls' and n7 == 60, true);
    local k8, n8 = dispatchM._reqSpec('apply 3');
    check('DBR8 apply spec carries box', k8 == 'apply' and n8 == 3, true);
    local k9, n9 = dispatchM._reqSpec('apply');
    check('DBR9 bare apply = marked box', k9 == 'apply' and n9 == nil, true);
    check('DBR10 garbage spec is nil', dispatchM._reqSpec('frobnicate'), nil);
end)();

-- LGD. lockstyle.M.debugLines -- the '/dl debug ls' addon half exists and
--      degrades honestly headless (no char, no boxes: the report still forms).
(function()
    local ls = dofile('feature/lockstyle.lua');
    check('LGD1 debugLines exported', type(ls.debugLines), 'function');
    local ok, L = pcall(ls.debugLines);
    check('LGD2 headless readout does not error', ok, true);
    check('LGD3 at least file/boxes/keep/town/traffic lines', ok and type(L) == 'table' and #L >= 5, true);
    check('LGD4 boxes-file line leads', ok and L[1]:find('boxes file', 1, true) ~= nil, true);
    -- the guard's 0x053 observation line (the "is anything leaving?" witness)
    check('LGD5 empty log says so', ls._outLine({}, 100):find('no 0x053 seen', 1, true) ~= nil, true);
    local line = ls._outLine({ { at = 96, mode = 3, act = 'activate' },
                               { at = 90, mode = 0, act = 'suppress' } }, 100);
    check('LGD6 SET + disable named with age and verdict', line:find('SET 4s ago (activate)', 1, true) ~= nil
          and line:find('disable 10s ago (suppress)', 1, true) ~= nil, true);
    check('LGD7 unknown mode degrades to its number', ls._outLine({ { at = 99, mode = 7, act = 'pass' } }, 100)
          :find('mode 7', 1, true) ~= nil, true);
    -- the capture window, addon half (v106): open -> note -> collect clears.
    check('LGD8 no window = notes are no-ops', (function()
        ls._capNote('before any window');
        return #ls.debugCaptureLog();
    end)(), 0);
    ls.debugCapture(30);
    ls._capNote('first event');
    ls._capNote('second event');
    local cap = ls.debugCaptureLog();
    check('LGD9 window collects stamped events in order', #cap == 2
          and cap[1]:find('t+', 1, true) == 1 and cap[1]:find('first event', 1, true) ~= nil
          and cap[2]:find('second event', 1, true) ~= nil, true);
    check('LGD10 collect clears the window', #ls.debugCaptureLog(), 0);
end)();

-- ---------------------------------------------------------------------------
-- NE. Native-engine storage home (feature/native-engine step 1) -- the flag
-- parse, the mode-aware path authorities, and the migration copy planner.
--
-- All PURE: the flag parse and the copy planner take text/lists; the path
-- composition runs against a stubbed AshitaCore install path with nativeMode
-- overridden per check (no file IO -- the WSL CI parity rule: '\'-joined io
-- paths break on Linux).
-- ---------------------------------------------------------------------------
(function()
    local prof = package.loaded['dlac\\profiles'];

    -- the flag parse: only a well-formed `return { native = true }` reads ON
    check('NE1 flag: native=true is ON',         prof.parseEngineFlag('return { native = true };'), true);
    check('NE2 flag: native=false is OFF',       prof.parseEngineFlag('return { native = false };'), false);
    check('NE3 flag: absent text is OFF',        prof.parseEngineFlag(nil), false);
    check('NE4 flag: damaged text is OFF',       prof.parseEngineFlag('return { native = '), false);
    check('NE5 flag: non-table is OFF',          prof.parseEngineFlag('return 42;'), false);
    check('NE6 flag: truthy-but-not-true is OFF', prof.parseEngineFlag('return { native = 1 };'), false);
    check('NE7 flag: comments + writer shape parse', prof.parseEngineFlag(
        '-- dlac engine flag -- written by /dl engine native on|off.\nreturn { native = true };\n'), true);

    -- path authorities under both modes: stub the install + identity, flip
    -- nativeMode by override (restored after -- the module is shared state).
    local savedAC, savedNative = AshitaCore, prof.nativeMode;
    AshitaCore = {
        GetInstallPath = function() return 'I:\\game\\'; end,
        GetMemoryManager = function() return {
            GetParty = function() return {
                GetMemberName = function() return 'Mindie'; end,
                GetMemberServerId = function() return 12345; end,
            }; end,
        }; end,
    };

    prof.nativeMode = function() return false; end
    -- A DECIDED legacy world (flag on disk, value off): dataDir's native-first
    -- hold (NO50) applies only to the undecided flag-ABSENT boot window.
    local savedFlagStateNE = prof.engineFlagState;
    prof.engineFlagState = function() return 'legacy'; end
    check('NE8 charFolder is <Name>_<Id>',    prof.charFolder(), 'Mindie_12345');
    check('NE9 legacy dataDir rides LAC tree', prof.dataDir(),
          'I:\\game\\config\\addons\\luashitacast\\Mindie_12345\\dlac\\');
    check('NE10 legacy charRoot is the LAC char base', prof.charRoot(),
          'I:\\game\\config\\addons\\luashitacast\\Mindie_12345\\');
    check('NE11 legacy storageRoot is the LAC root', prof.storageRoot(),
          'I:\\game\\config\\addons\\luashitacast\\');
    check('NE12 legacy pointer under dataDir', prof.pointerPath(),
          'I:\\game\\config\\addons\\luashitacast\\Mindie_12345\\dlac\\profile.lua');
    check('NE13 legacy cross-char data dir nests dlac\\', prof.charDataDirAt('Frieda_777'),
          'I:\\game\\config\\addons\\luashitacast\\Frieda_777\\dlac\\');
    check('NE14 legacy has no second exports home', prof.legacyExportsDir(), nil);
    prof.engineFlagState = savedFlagStateNE;

    prof.nativeMode = function() return true; end
    check('NE15 native dataDir is dlac\'s own root, no dlac\\ level', prof.dataDir(),
          'I:\\game\\config\\addons\\dlac\\Mindie_12345\\');
    check('NE16 native charRoot equals the char home', prof.charRoot(),
          'I:\\game\\config\\addons\\dlac\\Mindie_12345\\');
    check('NE17 native storageRoot is the dlac root', prof.storageRoot(),
          'I:\\game\\config\\addons\\dlac\\');
    check('NE18 native pointer under the char home', prof.pointerPath(),
          'I:\\game\\config\\addons\\dlac\\Mindie_12345\\profile.lua');
    check('NE19 native cross-char data dir is flat', prof.charDataDirAt('Frieda_777'),
          'I:\\game\\config\\addons\\dlac\\Frieda_777\\');
    check('NE20 native profilesRoot composes off dataDir', prof.profilesRoot(),
          'I:\\game\\config\\addons\\dlac\\Mindie_12345\\profiles\\');
    check('NE21 native still names the LEGACY exports home', prof.legacyExportsDir(),
          'I:\\game\\config\\addons\\luashitacast\\dlac-exports\\');
    check('NE22 native exports live under the dlac root', prof.exportsDir(),
          'I:\\game\\config\\addons\\dlac\\dlac-exports\\');
    check('NE23 flag file sits at the native root', prof.engineFlagPath(),
          'I:\\game\\config\\addons\\dlac\\engine.lua');
    check('NE24 backups follow the native char home', prof.backupPath('WHM'),
          'I:\\game\\config\\addons\\dlac\\Mindie_12345\\backups\\pre-profiles\\WHM.lua');
    check('NE25 legacy trigger tier rides the data home too', prof.legacyTriggersPath('WHM'),
          'I:\\game\\config\\addons\\dlac\\Mindie_12345\\triggers\\WHM.lua');

    prof.nativeMode = savedNative;
    AshitaCore = savedAC;

    -- the migration copy planner: skip existing, reject escapes, sort output
    local copy, skip = prof.planEngineCopy(
        { 'profiles\\Default\\sets\\WHM.lua', 'gear.lua', 'profile.lua',
          'profiles\\Default\\sets\\WHM.lua' },   -- duplicate rides through (fs never produces one)
        { ['gear.lua'] = true });
    check('NE26 planner copies what the target lacks', table.concat(copy, ','),
          'profile.lua,profiles\\Default\\sets\\WHM.lua,profiles\\Default\\sets\\WHM.lua');
    check('NE27 planner skips what the target has', table.concat(skip, ','), 'gear.lua');
    local c2 = prof.planEngineCopy({ '..\\evil.lua', 'C:\\abs.lua', '\\rooted.lua', '', 'ok.lua' }, {});
    check('NE28 planner rejects escapes and absolutes', table.concat(c2, ','), 'ok.lua');
    local c3, s3 = prof.planEngineCopy(nil, nil);
    check('NE29 planner survives nil args', #c3 + #s3, 0);
end)();

-- ---------------------------------------------------------------------------
-- NO. Native-first onboarding (ADR 0015 ruling 4, issue #87) -- the pure
-- first-run decision (flag presence x legacy-data presence -> action), the
-- LAC-alive ask's once-per-session gate, and the native Setup path (storage +
-- starter files, ZERO writes under config\addons\luashitacast\).
-- ---------------------------------------------------------------------------
(function()
    local prof = package.loaded['dlac\\profiles'];

    -- The pure first-run decision. A flag on disk (either value) is ALWAYS
    -- respected -- boot never rewrites it, never auto-flips an existing user.
    check('NO1 flag native -> respect',        prof.firstRunAction('native', false), 'respect');
    check('NO2 flag native + legacy -> respect', prof.firstRunAction('native', true), 'respect');
    check('NO3 flag legacy -> respect',        prof.firstRunAction('legacy', false), 'respect');
    check('NO4 flag legacy + data -> respect', prof.firstRunAction('legacy', true), 'respect');
    -- No flag: legacy data present = existing user (stay legacy, write nothing);
    -- no legacy data = fresh install (born native).
    check('NO5 absent + legacy data -> legacy',   prof.firstRunAction('absent', true), 'legacy');
    check('NO6 absent + no data -> write-native',  prof.firstRunAction('absent', false), 'write-native');

    -- The once-per-session ask gate: fires the FIRST time LAC is alive, then latches.
    prof._resetAskGate();
    check('NO7 ask gate: no LAC -> silent',    prof.shouldAskUnloadLac(false), false);
    check('NO8 ask gate: LAC alive -> ask',    prof.shouldAskUnloadLac(true), true);
    check('NO9 ask gate: latched after asking', prof.shouldAskUnloadLac(true), false);
    check('NO10 ask gate: stays latched',       prof.shouldAskUnloadLac(true), false);
    prof._resetAskGate();
    check('NO11 ask gate: reset re-arms',       prof.shouldAskUnloadLac(true), true);
    prof._resetAskGate();

    -- The native Setup path. Stub the install + identity, force native mode, and
    -- capture every write: the ACCEPTANCE guarantee is zero <JOB>.lua / shim /
    -- backup writes under LuaAshitacast's tree. IO-touching profiles helpers are
    -- overridden to no-ops (the WSL parity rule: '\'-joined io paths break on
    -- Linux) so the only writes flow through the captured writeFileText.
    local savedAC, savedNative, savedEnsure, savedExists, savedExec =
        AshitaCore, prof.nativeMode, prof.ensureStorage, prof.storageExists, os.execute;
    AshitaCore = {
        GetInstallPath = function() return 'I:\\game\\'; end,
        GetMemoryManager = function() return {
            GetParty = function() return {
                GetMemberName = function() return 'Mindie'; end,
                GetMemberServerId = function() return 12345; end,
            }; end,
        }; end,
    };
    prof.ensureStorage = function() return true; end          -- no real disk
    prof.storageExists = function() return true; end          -- seed into profile storage
    os.execute = function() return true; end                  -- swallow seedGearFile's mkdir

    local setup = dofile('ui/setupui.lua');
    package.loaded['dlac\\ui\\setupui'] = setup;
    local base = 'I:\\game\\config\\addons\\luashitacast\\Mindie_12345\\';
    local jf = base .. 'WHM.lua';
    local writes;
    local function mkDeps()
        return {
            charBase = function() return base; end,
            jobFile  = function() return jf, 'WHM'; end,
            dataDir  = function() return prof.dataDir(); end,
            charRoot = function() return prof.charRoot(); end,
            readFileText  = function() return nil; end,                 -- nothing exists yet
            writeFileText = function(p) writes[#writes + 1] = p; return true; end,
            status = function() end,
            ui = {},
        };
    end
    local function has(sub)
        for _, p in ipairs(writes) do if type(p) == 'string' and p:find(sub, 1, true) then return true; end end
        return false;
    end

    -- NATIVE: setupNative writes storage + starter files, never the LAC tree.
    prof.nativeMode = function() return true; end
    writes = {};
    setup.configure(mkDeps());
    check('NO12 setup reports native mode', setup.isNative(), true);
    setup.setupNative(base, 'WHM');
    check('NO13 native setup wrote something', #writes > 0, true);
    check('NO14 native setup: NO write under luashitacast\\', has('luashitacast'), false);
    check('NO15 native setup: no <JOB>.lua shim written', has('WHM.lua') and has(jf), false);
    check('NO16 native setup: no backup written', has('backups'), false);
    check('NO17 native setup lands under the dlac root', has('config\\addons\\dlac\\'), true);

    -- LEGACY (contrast): the flag-off path still writes the <JOB>.lua shim.
    prof.nativeMode = function() return false; end
    writes = {};
    setup.configure(mkDeps());
    check('NO18 setup reports legacy mode', setup.isNative(), false);
    setup.migrateCurrentJob();   -- state 'nofile' (readFileText nil) -> write the shim
    local wroteShim = false;
    for _, p in ipairs(writes) do if p == jf then wroteShim = true; end end
    check('NO19 legacy setup still writes the shim', wroteShim, true);

    prof.nativeMode, prof.ensureStorage, prof.storageExists = savedNative, savedEnsure, savedExists;
    os.execute, AshitaCore = savedExec, savedAC;
end)();

-- ---------------------------------------------------------------------------
-- NO20+. Onboarding v2 (issue #91): needsSetup v2 (native always false;
-- legacy-with-data true), fresh-install auto-setup (idempotent, zero-clobber,
-- ZERO writes under luashitacast\, never in legacy / before job-ready), a new
-- job auto-seeding its own starters, and the migration Commit's call sequence
-- (engineMigrateStorage -> setNativeMode(true) -> the unload checklist), all
-- captured against a virtual disk -- no real IO.
-- ---------------------------------------------------------------------------
(function()
    local prof = package.loaded['dlac\\profiles'];
    local setup = dofile('ui/setupui.lua');
    package.loaded['dlac\\ui\\setupui'] = setup;

    -- A name->content virtual disk the deps read/write through, so idempotence
    -- and zero-clobber are checkable without touching real files.
    local disk, writes = {}, {};
    local savedAC, savedExec = AshitaCore, os.execute;
    local savedNative, savedEnsure, savedExists = prof.nativeMode, prof.ensureStorage, prof.storageExists;
    local savedSetsP, savedTrigP, savedDataDir = prof.setsPath, prof.triggersPath, prof.dataDir;
    local savedMig, savedSet = prof.engineMigrateStorage, prof.setNativeMode;
    AshitaCore = { GetInstallPath = function() return 'I:\\game\\'; end };
    os.execute = function() return true; end
    prof.ensureStorage = function() return true; end
    -- deterministic native paths (no real charFolder resolution)
    local NROOT = 'I:\\game\\config\\addons\\dlac\\Mindie_12345\\';
    prof.dataDir      = function() return NROOT; end
    prof.setsPath     = function(job) return NROOT .. 'profiles\\Default\\sets\\' .. job .. '.lua'; end
    prof.triggersPath = function(job) return NROOT .. 'profiles\\Default\\triggers\\' .. job .. '.lua'; end
    local storageOn = true;
    prof.storageExists = function() return storageOn; end

    local base = 'I:\\game\\config\\addons\\luashitacast\\Mindie_12345\\';
    local curAbbr = 'WHM';
    local deps = {
        charBase = function() return base; end,
        jobFile  = function() if curAbbr == nil then return nil, nil; end return base .. curAbbr .. '.lua', curAbbr; end,
        dataDir  = function() return NROOT; end,
        charRoot = function() return NROOT; end,
        readFileText  = function(p) return disk[p]; end,
        writeFileText = function(p, c) disk[p] = c or 'x'; writes[#writes + 1] = p; return true; end,
        status = function() end,
        ui = {},
    };
    setup.configure(deps);
    local function has(sub) for _, p in ipairs(writes) do if type(p) == 'string' and p:find(sub, 1, true) then return true; end end return false; end
    -- seedGearFile's last-resort source is the bundled empty template.
    disk['I:\\game\\addons\\dlac\\gear.lua'] = 'return {}\n';

    -- --- needsSetup v2 matrix ---
    prof.nativeMode = function() return true; end
    check('NO20 needsSetup native -> always false',   setup.needsSetup(), false);
    prof.nativeMode = function() return false; end
    storageOn = false;
    check('NO21 needsSetup legacy + NO data -> false', setup.needsSetup(), false);
    storageOn = true;
    check('NO22 needsSetup legacy + data -> true',     setup.needsSetup(), true);

    -- --- auto-setup NEVER fires in legacy mode ---
    writes = {};
    check('NO23 autoSetupNative idles in legacy',      setup.autoSetupNative(), 'idle');
    check('NO24 legacy auto-setup wrote nothing',      #writes, 0);

    -- --- fresh native install: baseline missing -> seed it ---
    prof.nativeMode = function() return true; end
    disk = { ['I:\\game\\addons\\dlac\\gear.lua'] = 'return {}\n' }; writes = {}; storageOn = true;
    check('NO25 fresh native auto-setup seeds',        setup.autoSetupNative(), 'seeded');
    check('NO26 auto-setup wrote gear.lua',            has('gear.lua'), true);
    check('NO27 auto-setup wrote this job\'s sets',    has('sets\\WHM.lua'), true);
    check('NO28 auto-setup wrote this job\'s triggers', has('triggers\\WHM.lua'), true);
    check('NO29 auto-setup: ZERO writes under luashitacast\\', has('luashitacast'), false);

    -- --- idempotent: a second run finds the baseline complete, writes nothing ---
    writes = {};
    check('NO30 re-run reports complete',              setup.autoSetupNative(), 'complete');
    check('NO31 re-run clobbers nothing',              #writes, 0);

    -- --- a later NEW job auto-seeds ITS starters (gear.lua is shared, not rewritten) ---
    curAbbr = 'BLM'; writes = {};
    check('NO32 new job auto-seeds its starters',      setup.autoSetupNative(), 'seeded');
    check('NO33 new job wrote BLM sets + triggers',    has('sets\\BLM.lua') and has('triggers\\BLM.lua'), true);
    check('NO34 new job did NOT rewrite gear.lua',     has('gear.lua'), false);
    curAbbr = 'WHM';

    -- --- job not ready (abbr nil, GetMainJob 0 at login) never seeds (hard rule 11) ---
    curAbbr = nil; writes = {};
    check('NO35 job-not-ready auto-setup idles',       setup.autoSetupNative(), 'idle');
    check('NO36 job-not-ready wrote nothing',          #writes, 0);
    curAbbr = 'WHM';

    -- --- a persistent write failure names itself and returns 'failed' (not latched) ---
    do
        local prevWrite = deps.writeFileText;
        deps.writeFileText = function() return true; end   -- pretend writes "succeed" but land nothing
        disk = { ['I:\\game\\addons\\dlac\\gear.lua'] = 'return {}\n' }; storageOn = true;
        setup.configure(deps);
        local failStatus = nil;
        deps.status = function(s) failStatus = s; end
        setup.configure(deps);
        check('NO37 baseline-never-lands reports failed', setup.autoSetupNative(), 'failed');
        check('NO38 failure names itself in status', type(failStatus) == 'string' and failStatus:find('could not', 1, true) ~= nil, true);
        deps.writeFileText = prevWrite; deps.status = function() end;
        setup.configure(deps);
    end

    -- --- the migration Commit: engineMigrateStorage -> setNativeMode(true) -> checklist ---
    local seq = {};
    prof.engineMigrateStorage = function() seq[#seq + 1] = 'migrate'; return 7, 2, 0; end
    prof.setNativeMode = function(on) seq[#seq + 1] = 'flag:' .. tostring(on); return true; end
    prof.nativeMode = function() return false; end   -- legacy at Commit time
    local msg = nil; deps.status = function(s) msg = s; end
    setup.configure(deps);
    writes = {};
    setup.migrateToNative();
    check('NO39 Commit copies THEN flips the flag',    table.concat(seq, ','), 'migrate,flag:true');
    check('NO40 Commit is copy-only (no JOB.lua/backup write)', has('luashitacast') or has('backups'), false);
    check('NO41 Commit prints the unload checklist',   type(msg) == 'string' and msg:find('unload luashitacast', 1, true) ~= nil, true);
    check('NO42 Commit refuses under native',
          (function() prof.nativeMode = function() return true; end; seq = {}; setup.migrateToNative(); prof.nativeMode = function() return false; end; return #seq; end)(), 0);

    prof.engineMigrateStorage, prof.setNativeMode = savedMig, savedSet;
    prof.nativeMode, prof.ensureStorage, prof.storageExists = savedNative, savedEnsure, savedExists;
    prof.setsPath, prof.triggersPath, prof.dataDir = savedSetsP, savedTrigP, savedDataDir;
    os.execute, AshitaCore = savedExec, savedAC;
end)();

-- ---------------------------------------------------------------------------
-- NO43+. The self-manufactured-evidence bug (field 2026-07-23, Henrik's
-- fresh-install sim): in-game ashita.fs.get_dir returns nil for a MISSING
-- directory (the headless popen fallback returns {} -- the suite masked it),
-- the undecided beat fell through into the LEGACY seeder, and the next scan
-- read dlac's own files as "existing legacy user". Pins: the parent-listing
-- disambiguation (missing root = DEFINITE fresh, not can't-tell), the
-- undecided contract (nil + warn ONCE + never latch), the loud decision lines
-- with their evidence, and the flag-write-failure retry.
-- ---------------------------------------------------------------------------
(function()
    local prof = package.loaded['dlac\\profiles'];
    local savedAC = AshitaCore;
    local savedList, savedProbe = prof._listDirs, prof._legacyProbe;
    local savedFlagState, savedSetNative = prof.engineFlagState, prof.setNativeMode;
    AshitaCore = { GetInstallPath = function() return 'I:\\game\\'; end };

    -- Root listing nil (the in-game missing-dir shape), parent WITHOUT
    -- luashitacast -> a DEFINITE fresh, scanned=true.
    prof._listDirs = function(p)
        if p:find('luashitacast', 1, true) then return nil; end
        return { 'dlac', 'someotheraddon' };
    end
    local pr, sc = prof.legacyDataPresent();
    check('NO43 missing root disambiguated as FRESH (scanned)', sc, true);
    check('NO43b ...and not present', pr, false);

    -- Root nil but the parent SHOWS luashitacast -> genuinely can't tell.
    prof._listDirs = function(p)
        if p:find('luashitacast', 1, true) then return nil; end
        return { 'dlac', 'Luashitacast' };   -- case-insensitive match required
    end
    pr, sc = prof.legacyDataPresent();
    check('NO44 unlistable-but-present root stays can\'t-tell', sc, false);

    -- Both listings nil -> can't tell.
    prof._listDirs = function() return nil; end
    pr, sc = prof.legacyDataPresent();
    check('NO45 both listings failed -> can\'t tell', sc, false);

    -- Evidence: the first char folder with real data rides the third return.
    prof._listDirs = function(p)
        if p:find('luashitacast', 1, true) then return { 'notachar', 'Testy_123' }; end
        return { 'luashitacast' };
    end
    prof._legacyProbe = function(dd) return dd:find('Testy_123', 1, true) ~= nil; end
    local pr2, sc2, ev = prof.legacyDataPresent();
    check('NO46 legacy data found', pr2 and sc2, true);
    check('NO46b ...with the char named as evidence', ev, 'Testy_123');

    -- firstRunInit undecided: nil, warns ONCE, never latches.
    local lines = {};
    local savedPrint = print;
    print = function(s) lines[#lines + 1] = tostring(s); end
    prof.engineFlagState = function() return 'absent'; end
    prof._listDirs = function() return nil; end   -- can't tell
    prof._resetFirstRun();
    check('NO47 undecided returns nil', prof.firstRunInit(), nil);
    check('NO47b ...warns once', #lines, 1);
    check('NO47c ...the warn says it writes nothing', lines[1]:find('WRITING nothing', 1, true) ~= nil, true);
    check('NO47d second beat stays nil silently', prof.firstRunInit() == nil and #lines, 1);

    -- Fresh + flag write FAILS: nil + its own one-time warn; then the write
    -- starts succeeding -> 'write-native' + the loud fresh line.
    lines = {}; prof._resetFirstRun();
    prof._listDirs = function(p)
        if p:find('luashitacast', 1, true) then return nil; end
        return { 'dlac' };   -- parent without luashitacast -> definite fresh
    end
    prof.setNativeMode = function() return nil, 'no dir'; end
    check('NO48 write-fail returns nil', prof.firstRunInit(), nil);
    check('NO48b ...named once', #lines == 1 and lines[1]:find('could not be', 1, true) ~= nil, true);
    prof.setNativeMode = function() return true; end
    check('NO48c write succeeding resolves write-native', prof.firstRunInit(), 'write-native');
    -- A RESOLVED decision is SILENT (Henrik, post-field-confirm: no first-run /
    -- engine narration for the player) -- only the fail warn above ever spoke.
    check('NO48d resolution is silent', #lines, 1);

    -- Legacy verdict: silent too -- the GUI banner + Migrate button carry the
    -- nudge, chat says nothing.
    lines = {}; prof._resetFirstRun();
    prof._listDirs = function(p)
        if p:find('luashitacast', 1, true) then return { 'Testy_123' }; end
        return { 'luashitacast' };
    end
    prof._legacyProbe = function() return true; end
    check('NO49 legacy resolves', prof.firstRunInit(), 'legacy');
    check('NO49b legacy resolution is silent', #lines, 0);

    -- NO50. THE PATH AUTHORITY HOLDS WHILE UNDECIDED (field 2026-07-27, Xvs's
    -- clean reinstall: config\addons\luashitacast AND config\addons\dlac both
    -- deleted, and "migrate to native" still appeared). The 07-23 fix held
    -- maintainStorage's OWN writers, but dataDir kept composing the LEGACY
    -- home during the undecided window (flag absent -> nativeMode false), so
    -- any login-time writer riding it -- the gear scan's commit above all --
    -- could still plant gear.lua under luashitacast\, and the NEXT beat read
    -- dlac's own file back as legacy evidence. dataDir now answers nil until
    -- the decision latches: "not logged in yet", every writer holds.
    local savedCharFolder = prof.charFolder;
    prof.charFolder = function() return 'Testy_123'; end   -- charBase resolves
    prof.invalidateNative();
    prof._resetFirstRun();
    prof.engineFlagState = function() return 'absent'; end
    prof._listDirs = function() return nil; end             -- undecided world
    check('NO50 dataDir holds while the first run is undecided', prof.dataDir(), nil);
    -- A latched LEGACY verdict reopens the legacy home exactly as before.
    prof._listDirs = function(p)
        if p:find('luashitacast', 1, true) then return { 'Testy_123' }; end
        return { 'luashitacast' };
    end
    prof._legacyProbe = function() return true; end
    check('NO50b a latched legacy verdict reopens it',
          prof.firstRunInit() == 'legacy' and type(prof.dataDir()) == 'string', true);
    prof.charFolder = savedCharFolder;

    print = savedPrint;
    prof._listDirs, prof._legacyProbe = savedList, savedProbe;
    prof.engineFlagState, prof.setNativeMode = savedFlagState, savedSetNative;
    prof._resetFirstRun();
    AshitaCore = savedAC;
end)();

-- ---------------------------------------------------------------------------
-- EQC. equipcore (feature/native-engine part 1) -- the pure equip pipeline:
-- entry normalization, the set resolver, and the 0x050/0x051 packet builders.
-- Semantics are LuaAshitacast-parity (equip.lua is the reference); these pins
-- are what "a character flipping to native sees identical equips" MEANS.
-- ---------------------------------------------------------------------------
(function()
    local eqc = dofile('gear/equipcore.lua');
    package.loaded['dlac\\gear\\equipcore'] = eqc;

    -- --- entry normalization (MakeItemTable parity) ---
    local e = eqc.normalizeEntry('Miner\'s Helmet');
    check('EQC1 string entry lowercases',        e and e.Name, 'miner\'s helmet');
    check('EQC2 default priority 0',             e and e.Priority, 0);
    local r = eqc.normalizeEntry('remove');
    check('EQC3 remove pins Index 0 / P-100',    r and r.Index == 0 and r.Priority == -100, true);
    check('EQC4 ignore drops the slot',          eqc.normalizeEntry('ignore'), nil);
    local d = eqc.normalizeEntry('displaced');
    check('EQC5 displaced pins Index -1',        d and d.Index, -1);
    local t = eqc.normalizeEntry({ Name = 'Karin Obi', Bag = 'Wardrobe2', Priority = 3, Junk = 9 });
    check('EQC6 table entry: bag name resolves, junk dropped',
          t and t.Bag == 10 and t.Priority == 3 and t.Junk == nil, true);
    check('EQC7 nil/bad entries reject',         eqc.normalizeEntry(42), nil);

    -- --- fixture helpers ---
    local FULLJOBS = 2 ^ 23 - 1;
    local function mkItem(container, index, name, slot, o)
        o = o or {};
        return {
            Container = container, Index = index, Id = o.Id or 1000 + index,
            Count = o.Count or 1, Flags = o.Flags or 0,
            Name = name, Level = o.Level or 1,
            Jobs = o.Jobs or FULLJOBS,
            Slots = o.Slots or (2 ^ (slot - 1)),
            ResFlags = o.ResFlags or 0x800,
            augment = o.augment,
        };
    end
    local function mkSnap(o)
        o = o or {};
        return { job = o.job or 7, level = o.level or 75,
                 disabled = o.disabled or {}, encumbered = o.encumbered or {},
                 equipped = o.equipped or {}, items = o.items or {} };
    end

    -- --- resolver: the plain equip ---
    local snap = mkSnap({ items = {
        mkItem(8, 3, 'traveler\'s hat', 5),
        mkItem(0, 7, 'brass harness', 6),
    } });
    local plan = eqc.planSet({ Head = 'Traveler\'s Hat', Body = 'Brass Harness' }, snap);
    check('EQC8 two pieces resolve to two equips', #plan.equips, 2);
    check('EQC9 equal priority ties break to the lower slot',
          plan.equips[1].Slot == 4 and plan.equips[2].Slot == 5, true);   -- Head=5th slot -> 4, Body -> 5
    check('EQC10 equips carry index+container',
          plan.equips[1].Index == 3 and plan.equips[1].Container == 8, true);
    check('EQC11 nothing satisfied yet', plan.satisfied, false);

    -- --- already worn: satisfied, silent ---
    local worn = mkSnap({
        equipped = { [5] = mkItem(8, 3, 'traveler\'s hat', 5) },
        items    = { mkItem(8, 3, 'traveler\'s hat', 5) },
    });
    plan = eqc.planSet({ Head = 'Traveler\'s Hat' }, worn);
    check('EQC12 worn match = satisfied, no packets', plan.satisfied == true and #plan.equips == 0, true);

    -- --- remove semantics ---
    plan = eqc.planSet({ Head = 'remove' },
        mkSnap({ equipped = { [5] = mkItem(8, 3, 'traveler\'s hat', 5) } }));
    check('EQC13 remove on worn slot unequips (Index 0, worn container)',
          #plan.equips == 1 and plan.equips[1].Index == 0 and plan.equips[1].Container == 8, true);
    plan = eqc.planSet({ Head = 'remove' }, mkSnap({}));
    check('EQC14 remove on empty slot sends nothing', plan.satisfied == true and #plan.equips == 0, true);

    -- --- frozen slots ---
    plan = eqc.planSet({ Head = 'Traveler\'s Hat' },
        mkSnap({ disabled = { [5] = true }, items = { mkItem(8, 3, 'traveler\'s hat', 5) } }));
    check('EQC15 disabled slot never resolves', #plan.equips, 0);
    plan = eqc.planSet({ Head = 'Traveler\'s Hat' },
        mkSnap({ encumbered = { [5] = true }, items = { mkItem(8, 3, 'traveler\'s hat', 5) } }));
    check('EQC16 encumbered slot never resolves', #plan.equips, 0);

    -- --- priority ordering ---
    plan = eqc.planSet({
        Head = { Name = 'Traveler\'s Hat', Priority = 1 },
        Body = { Name = 'Brass Harness', Priority = 5 },
    }, mkSnap({ items = {
        mkItem(8, 3, 'traveler\'s hat', 5), mkItem(0, 7, 'brass harness', 6),
    } }));
    check('EQC17 higher priority equips first', plan.equips[1].Slot, 5);

    -- --- gates: level, job, slot bit, bag pin, bazaar, count ---
    plan = eqc.planSet({ Head = 'Traveler\'s Hat' },
        mkSnap({ level = 10, items = { mkItem(8, 3, 'traveler\'s hat', 5, { Level = 50 }) } }));
    check('EQC18 level gate drops the piece', #plan.equips, 0);
    plan = eqc.planSet({ Head = 'Traveler\'s Hat' },
        mkSnap({ job = 3, items = { mkItem(8, 3, 'traveler\'s hat', 5, { Jobs = 2 ^ 7 }) } }));
    check('EQC19 job gate drops the piece', #plan.equips, 0);
    plan = eqc.planSet({ Body = 'Traveler\'s Hat' },
        mkSnap({ items = { mkItem(8, 3, 'traveler\'s hat', 5) } }));
    check('EQC20 slot-bit mismatch drops the piece', #plan.equips, 0);
    plan = eqc.planSet({ Head = { Name = 'Traveler\'s Hat', Bag = 'Wardrobe' } },
        mkSnap({ items = { mkItem(0, 3, 'traveler\'s hat', 5) } }));
    check('EQC21 bag pin refuses the wrong bag', #plan.equips, 0);
    plan = eqc.planSet({ Head = 'Traveler\'s Hat' },
        mkSnap({ items = { mkItem(8, 3, 'traveler\'s hat', 5, { Flags = 19 }) } }));
    check('EQC22 bazaared item skipped', #plan.equips, 0);
    plan = eqc.planSet({ Head = 'Traveler\'s Hat' },
        mkSnap({ items = { mkItem(8, 3, 'traveler\'s hat', 5, { Count = 0 }) } }));
    check('EQC23 zero-count item skipped', #plan.equips, 0);
    plan = eqc.planSet({ Head = 'Traveler\'s Hat' },
        mkSnap({ items = { mkItem(8, 3, 'traveler\'s hat', 5, { ResFlags = 0 }) } }));
    check('EQC24 non-equippable flag skipped', #plan.equips, 0);

    -- --- augment pins ---
    local augItem = mkItem(8, 3, 'oneiros ring', 14, { augment = {
        Path = 'A', Rank = 15, Augs = { { String = 'STR+5' }, { String = 'Accuracy+3' } } } });
    plan = eqc.planSet({ Ring1 = { Name = 'Oneiros Ring', AugPath = 'A', AugRank = 15 } },
        mkSnap({ items = { augItem } }));
    check('EQC25 path+rank pin matches', #plan.equips, 1);
    plan = eqc.planSet({ Ring1 = { Name = 'Oneiros Ring', AugPath = 'B' } },
        mkSnap({ items = { augItem } }));
    check('EQC26 wrong path refuses', #plan.equips, 0);
    plan = eqc.planSet({ Ring1 = { Name = 'Oneiros Ring', Augment = { 'STR+5', 'Accuracy+3' } } },
        mkSnap({ items = { augItem } }));
    check('EQC27 augment string list matches', #plan.equips, 1);
    plan = eqc.planSet({ Ring1 = { Name = 'Oneiros Ring', Augment = 'VIT+5' } },
        mkSnap({ items = { augItem } }));
    check('EQC28 missing augment string refuses', #plan.equips, 0);
    plan = eqc.planSet({ Ring1 = { Name = 'Oneiros Ring', AugPath = 'A' } },
        mkSnap({ items = { mkItem(8, 3, 'oneiros ring', 14) } }));
    check('EQC29 pin vs unaugmented item refuses', #plan.equips, 0);

    -- --- one instance never fills two slots; second copy does ---
    plan = eqc.planSet({ Ring1 = 'Reraise Ring', Ring2 = 'Reraise Ring' },
        mkSnap({ items = { mkItem(8, 3, 'reraise ring', 14, { Slots = 2^13 + 2^14 }) } }));
    check('EQC30 single instance fills exactly one ring', #plan.equips, 1);
    plan = eqc.planSet({ Ring1 = 'Reraise Ring', Ring2 = 'Reraise Ring' },
        mkSnap({ items = {
            mkItem(8, 3, 'reraise ring', 14, { Slots = 2^13 + 2^14 }),
            mkItem(8, 4, 'reraise ring', 14, { Slots = 2^13 + 2^14 }),
        } }));
    check('EQC31 two instances fill both rings', #plan.equips, 2);

    -- --- conflicts: claimed instance worn elsewhere unreserved ---
    local swordWorn = mkItem(0, 9, 'bronze sword', 2, { Slots = 2^0 + 2^1 });   -- worn in Sub
    plan = eqc.planSet({ Main = 'Bronze Sword' },
        mkSnap({ equipped = { [2] = swordWorn }, items = { swordWorn } }));
    check('EQC32 worn-elsewhere instance claims produce a conflict unequip',
          #plan.conflicts == 1 and plan.conflicts[1].Slot == 1, true);
    check('EQC33 ...and the equip itself', #plan.equips == 1 and plan.equips[1].Slot == 0, true);
    -- when the worn slot's own entry claims it, it is reserved: not stealable
    plan = eqc.planSet({ Main = 'Bronze Sword', Sub = 'Bronze Sword' },
        mkSnap({ equipped = { [2] = swordWorn }, items = { swordWorn } }));
    check('EQC34 reserved instance is not stealable (Sub keeps it, Main unresolved)',
          #plan.equips == 0 and #plan.conflicts == 0, true);

    -- --- displaced: a stamp, never a packet. LAC parity pin: a set that is
    -- otherwise satisfied early-returns BEFORE displaced handling (equip.lua's
    -- FlagEquippedItems short-circuit), so displaced-only sets do nothing;
    -- the stamp rides only when the set has real work.
    plan = eqc.planSet({ Ammo = 'displaced' }, mkSnap({}));
    check('EQC35a displaced-only set is satisfied silence (LAC parity)',
          plan.satisfied == true and #plan.equips == 0 and #plan.stamps == 0, true);
    plan = eqc.planSet({ Ammo = 'displaced', Head = 'Traveler\'s Hat' },
        mkSnap({ items = { mkItem(8, 3, 'traveler\'s hat', 5) } }));
    check('EQC35b displaced stamps (no packet) when the set does work',
          #plan.equips == 1 and #plan.stamps == 2, true);

    -- --- packet builders (byte goldens) ---
    local p50 = eqc.build0x50(12, 4, 8);
    check('EQC36 0x50 bytes: index/slot/container at 5/6/7',
          p50[5] == 12 and p50[6] == 4 and p50[7] == 8 and #p50 == 8, true);
    local un = eqc.buildUnequip0x50(4, 8);
    check('EQC37 unequip is 0x50 with index 0', un[5] == 0 and un[6] == 4 and un[7] == 8, true);
    local p51 = eqc.build0x51({
        { Slot = 4, Index = 3, Container = 8 },
        { Slot = 5, Index = 7, Container = 0 },
    });
    check('EQC38 0x51 count byte', p51[5], 2);
    check('EQC39 0x51 first entry at offset 9',  p51[9] == 3 and p51[10] == 4 and p51[11] == 8, true);
    check('EQC40 0x51 second entry at offset 13', p51[13] == 7 and p51[14] == 5 and p51[15] == 0, true);
    check('EQC41 0x51 is 72 bytes', #p51, 72);

    -- --- style choice ---
    check('EQC42 auto under 9 = singles', eqc.chooseStyle(8), 'single');
    check('EQC43 auto at 9 = equipset',   eqc.chooseStyle(9), 'set');
    check('EQC44 explicit set wins',      eqc.chooseStyle(2, 'set'), 'set');
    check('EQC45 explicit single wins',   eqc.chooseStyle(12, 'single'), 'single');
end)();

-- ---------------------------------------------------------------------------
-- EQE. equipengine (feature/native-engine part 2) -- the pure half of the
-- action pipeline: byte readers, the chunk parser, the ACTION_ROUTES table,
-- completion math, the 0x028 decode, and the augment header decode.
-- ---------------------------------------------------------------------------
(function()
    local eng = dofile('feature/equipengine.lua');
    package.loaded['dlac\\feature\\equipengine'] = eng;

    -- bit-writer helper: the inverse of bitsAt (LSB-first within bytes)
    local function packStr(len, writes)
        local bytes = {};
        for i = 1, len do bytes[i] = 0; end
        for _, w in ipairs(writes) do
            local bitOff, nbits, value = w[1], w[2], w[3];
            for i = 0, nbits - 1 do
                local bit = math.floor(value / (2 ^ i)) % 2;
                if bit == 1 then
                    local pos = bitOff + i;
                    local bi = math.floor(pos / 8) + 1;
                    bytes[bi] = bytes[bi] + 2 ^ (pos % 8);
                end
            end
        end
        local out = {};
        for i = 1, len do out[i] = string.char(bytes[i]); end
        return table.concat(out);
    end

    -- --- byte readers ---
    local s = string.char(0x34, 0x12, 0x78, 0x56);
    check('EQE1 u16at little-endian', eng.u16at(s, 0), 0x1234);
    check('EQE2 u32at little-endian', eng.u32at(s, 0), 0x56781234);
    check('EQE3 u16at past end reads zeros', eng.u16at(s, 10), 0);
    local bs = packStr(4, { { 10, 4, 9 } });   -- 4 bits at bit 10 = 9
    check('EQE4 bitsAt round-trips the writer', eng.bitsAt(bs, 0, 10, 4), 9);
    check('EQE5 bitsAt with byte offset', eng.bitsAt(bs, 1, 2, 4), 9);   -- same bits, byte-relative

    -- --- chunk parsing: id 9 bits, size 7 bits in 4-byte units ---
    local function header(id, sizeBytes)
        local w = id + math.floor(sizeBytes / 4) * 512;
        return string.char(w % 256, math.floor(w / 256));
    end
    local pkt1 = header(0x1A, 8) .. string.rep('\1', 6);
    local pkt2 = header(0x15, 4) .. string.rep('\2', 2);
    local chunk = pkt1 .. pkt2;
    local parsed = eng.parseChunk(chunk);
    check('EQE6 chunk yields both packets', #parsed, 2);
    check('EQE7 first packet id/size/off', parsed[1].id == 0x1A and parsed[1].size == 8 and parsed[1].off == 0, true);
    check('EQE8 second packet id/off', parsed[2].id == 0x15 and parsed[2].off == 8, true);
    check('EQE9 torn header stops the walk', #eng.parseChunk(string.char(0, 0, 1, 1)), 0);

    -- --- action + item-use field decode ---
    local act = string.rep('\0', 8) .. string.char(0x21, 0x00)   -- target 0x21 at 0x08
        .. string.char(0x03, 0x00)                               -- category 3 at 0x0A
        .. string.char(0x38, 0x00);                              -- action id 0x38 at 0x0C
    local a = eng.parseAction(act);
    check('EQE10 action fields decode', a.target == 0x21 and a.category == 3 and a.actionId == 0x38, true);
    local itm = string.rep('\0', 12) .. string.char(0x44, 0x00)  -- target at 0x0C
        .. string.char(0x07)                                     -- item index at 0x0E
        .. string.char(0x00) .. string.char(0x08);               -- container at 0x10
    local u = eng.parseItemUse(itm);
    check('EQE11 item-use fields decode', u.target == 0x44 and u.itemIndex == 7 and u.container == 8, true);

    -- --- routes: the dispatch-point table ---
    check('EQE12 spell route', eng.routeOf(0x03).pre == 'Precast' and eng.routeOf(0x03).mid == 'Midcast', true);
    check('EQE13 ws route has no midcast', eng.routeOf(0x07).pre == 'Weaponskill' and eng.routeOf(0x07).mid == nil, true);
    check('EQE14 ranged route', eng.routeOf(0x10).pre == 'Preshot' and eng.routeOf(0x10).mid == 'Midshot', true);
    check('EQE15 unhandled category is nil', eng.routeOf(0x0F), nil);
    check('EQE16 precast styles: spell=set, ability=auto',
          eng.routeOf(0x03).preStyle == 'set' and eng.routeOf(0x09).preStyle == 'auto', true);

    -- --- completion math (LAC formulas) ---
    local S = { FastCast = 0, Snapshot = 0, SpellOffset = 1.0, RangedBase = 10.0,
                RangedOffset = 0.5, WeaponskillDelay = 3.0, AbilityDelay = 2.5,
                ItemBase = 8, ItemOffset = 1.0 };
    check('EQE17 spell completion = cast/4 + offset',
          eng.completionOf(eng.routeOf(3), 32, S, 100), 100 + 8 + 1.0);
    S.FastCast = 50;
    check('EQE18 fast cast halves the base', eng.completionOf(eng.routeOf(3), 32, S, 100), 100 + 4 + 1.0);
    check('EQE19 ranged completion', eng.completionOf(eng.routeOf(16), nil, S, 100), 100 + 10 + 0.5);
    S.Snapshot = 50;
    check('EQE20 snapshot halves ranged base', eng.completionOf(eng.routeOf(16), nil, S, 100), 100 + 5 + 0.5);
    check('EQE21 ws fixed delay', eng.completionOf(eng.routeOf(7), nil, S, 100), 103.0);
    check('EQE22 item with cast time', eng.itemCompletionOf(40, S, 100), 100 + 10 + 1.0);
    check('EQE23 item without resource', eng.itemCompletionOf(nil, S, 100), 100 + 8 + 1.0);

    -- --- 0x028 decode ---
    local p28 = packStr(24, {
        { 0x05 * 8, 32, 123456 },   -- userId u32 at byte 5
        { 10 * 8 + 2, 4, 4 },       -- actionType 4 (complete)
    });
    local d28 = eng.parse0x28(p28);
    check('EQE24 0x28 userId + type', d28.userId == 123456 and d28.actionType == 4, true);
    check('EQE25 type 4 is a completion type', eng.ACTION_COMPLETE_TYPES[4], true);
    local p28i = packStr(24, {
        { 0x05 * 8, 32, 123456 },
        { 10 * 8 + 2, 4, 8 },        -- type 8 (ranged/magic)
        { 10 * 8 + 6, 16, 28787 },   -- the interrupt magic
    });
    local d28i = eng.parse0x28(p28i);
    check('EQE26 interrupt magic decodes', d28i.actionType == 8 and d28i.interrupted == true, true);
    local p28n = packStr(24, { { 0x05 * 8, 32, 1 }, { 10 * 8 + 2, 4, 8 }, { 10 * 8 + 6, 16, 100 } });
    check('EQE27 type 8 without magic is not an interrupt', eng.parse0x28(p28n).interrupted, false);

    -- --- augment header decode ---
    check('EQE28 unaugmented extra is nil', eng.parseAugmentHeader(string.char(0, 0, 0, 0)), nil);
    local delve = packStr(24, { { 0, 8, 2 }, { 8, 8, 0x20 }, { 16, 2, 1 }, { 18, 4, 9 } });
    local pa = eng.parseAugmentHeader(delve);
    check('EQE29 delve path+rank', pa.Type == 'Delve' and pa.Path == 'B' and pa.Rank == 9, true);
    local dyna = packStr(24, { { 0, 8, 2 }, { 8, 8, 131 }, { 32, 2, 2 }, { 50, 5, 20 } });
    local da = eng.parseAugmentHeader(dyna);
    check('EQE30 dynamis path+rank', da.Type == 'Dynamis' and da.Path == 'C' and da.Rank == 20, true);
    local magian = packStr(24, { { 0, 8, 3 }, { 8, 8, 0x40 }, { 80, 15, 5432 } });
    local ma = eng.parseAugmentHeader(magian);
    check('EQE31 magian trial', ma.Type == 'Magian' and ma.Trial == 5432, true);
    local oseem = packStr(24, { { 0, 8, 2 }, { 8, 8, 0 } });
    check('EQE32 plain augment type is Oseem', eng.parseAugmentHeader(oseem).Type, 'Oseem');
    check('EQE33 synth-shield flag is nil', eng.parseAugmentHeader(packStr(4, { { 0, 8, 2 }, { 8, 8, 0x08 } })), nil);

    -- --- the buffer merge (through the real equipSet door) ---
    eng.bufferClear();
    eng.equipSet({ Head = 'Cap A' });
    eng.equipSet({ Head = 'Cap B', Body = 'Harness' });
    eng.equipSet({ Body = 'ignore' });
    local buf = eng._bufferPeek();
    check('EQE34 buffer merge: later write wins, ignore clears',
          buf[5] == 'Cap B' and buf[6] == nil, true);
    eng.equipSet({ [11] = 'Karin Obi' });   -- numeric slot keys ride too
    check('EQE35 numeric slot keys accepted', eng._bufferPeek()[11], 'Karin Obi');
    eng.bufferClear();
    check('EQE36 clear empties the buffer', next(eng._bufferPeek()), nil);
end)();

-- ---------------------------------------------------------------------------
-- NEB. native backend wiring (feature/native-engine step 5) -- the arming
-- rules and the pet-stream decode. The dispatch-side seams (engineActive,
-- the native sets store, engineEquipSet) are exercised through the 2600+
-- LAC-state checks above staying green: flag off = byte-identical behavior.
-- ---------------------------------------------------------------------------
(function()
    local eng = package.loaded['dlac\\feature\\equipengine'];
    local prof = package.loaded['dlac\\profiles'];

    -- arming rules: the addon state arms only with the flag on; the LAC state
    -- REFUSES even with the flag on (two interceptors = the hazard); a fired
    -- tripwire disarms.
    local savedNative, savedGFunc = prof.nativeMode, rawget(_G, 'gFunc');
    prof.nativeMode = function() return true; end
    _G.gFunc = nil;
    check('NEB1 addon state + flag on = armed', eng.nativeOn(), true);
    _G.gFunc = {};
    check('NEB2 LAC state refuses even with the flag on', eng.nativeOn(), false);
    _G.gFunc = nil;
    eng.state.tripped = true;
    check('NEB3 tripwire disarms', eng.nativeOn(), false);
    eng.state.tripped = false;
    prof.nativeMode = function() return false; end
    check('NEB4 flag off = not armed', eng.nativeOn(), false);
    prof.nativeMode = savedNative;
    _G.gFunc = savedGFunc;

    -- the pet 0x28 field decode (actionId at bit 213, message at byte 28 bit 6)
    local function packStr(len, writes)
        local bytes = {};
        for i = 1, len do bytes[i] = 0; end
        for _, w in ipairs(writes) do
            for i = 0, w[2] - 1 do
                if math.floor(w[3] / (2 ^ i)) % 2 == 1 then
                    local pos = w[1] + i;
                    bytes[math.floor(pos / 8) + 1] = bytes[math.floor(pos / 8) + 1] + 2 ^ (pos % 8);
                end
            end
        end
        local out = {};
        for i = 1, len do out[i] = string.char(bytes[i]); end
        return table.concat(out);
    end
    local pkt = packStr(40, { { 213, 17, 900 }, { 28 * 8 + 6, 10, 43 } });
    local pp = eng.parse0x28Pet(pkt);
    check('NEB5 pet actionId decodes', pp.actionId, 900);
    check('NEB6 pet mobskill message decodes', pp.message, 43);
end)();

-- ---------------------------------------------------------------------------
-- CHOCOBO DIGGING: digcalc odds math (hand-computed pools) + digdata shape +
-- fail-soft loading -- PRD #93 / issue #94, docs/design/chocobo-dig.md. The
-- odds are derived BY HAND from the PRD formula:
--   mu   = 1.5 - |moonPhase - 50| / 50
--   q_i  = min(1, weight_i / (1000 * mu))   (0 if rank < requirement_i)
--   S    = 1 - PROD_i (1 - q_i)
--   P_i  = q_i * INT_0^1 PROD_{j!=i}(1 - q_j + q_j*t) dt
--   (1) On a hit = P_i / S   (sums to ~1 within a pool)
--   (2) Per dig  = P_i       (sums to S)
-- If a port edit moves one of these numbers, re-derive from the formula before
-- touching the test. The math tests use SYNTHETIC pools (no digdata), mirroring
-- fishcalc's F1-F14; the shape/fail-soft tests exercise the shipped table.
-- ---------------------------------------------------------------------------
(function()
    local dc = dofile('feature/digcalc.lua');
    package.loaded['dlac\\feature\\digcalc'] = dc;
    local function r6(x) return math.floor((tonumber(x) or 0) * 1e6 + 0.5) / 1e6; end

    -- moon multiplier: best (0.5) at new/full, worst (1.5) at half; clamps.
    check('DC1 moon new  -> 0.5', dc.moonMult(0), 0.5);
    check('DC2 moon full -> 0.5', dc.moonMult(100), 0.5);
    check('DC3 moon half -> 1.5', dc.moonMult(50), 1.5);
    check('DC4 moon clamps below 0',  dc.moonMult(-40), 0.5);
    check('DC5 moon clamps above 100', dc.moonMult(140), 0.5);
    check('DC6 moon default (nil) = half', dc.moonMult(nil), 1.5);

    -- qualify probability q = min(1, w/(1000*mu)); best moon lifts a mid weight
    -- to certainty, worst moon thins it.
    check('DC7 qualify neutral', dc.qualify(500, 1), 0.5);
    check('DC8 qualify caps at 1', dc.qualify(1000, 1), 1);
    check('DC9 qualify best moon caps a 500-weight', dc.qualify(500, 0.5), 1);
    check('DC10 qualify worst moon thins to 1/3', r6(dc.qualify(500, 1.5)), r6(1/3));
    check('DC11 qualify zero weight -> 0', dc.qualify(0, 1), 0);

    -- two-item pool {500, 1000} at mu=1: q1=0.5, q2=1 -> S=1, P1=0.25, P2=0.75.
    local two = dc.poolOdds({ { id = 1, n = 'a', w = 500, rank = 0 },
                              { id = 2, n = 'b', w = 1000, rank = 0 } }, 8, 1);
    check('DC12 pool success S = 1', two.S, 1);
    check('DC13 P1 (per dig) = 0.25', r6(two.items[1].perDig), 0.25);
    check('DC14 P2 (per dig) = 0.75', r6(two.items[2].perDig), 0.75);
    check('DC15 on-a-hit share 1', r6(two.items[1].onHit), 0.25);
    check('DC16 on-a-hit share 2', r6(two.items[2].onHit), 0.75);
    local sPerDig = two.items[1].perDig + two.items[2].perDig;
    local sOnHit  = two.items[1].onHit + two.items[2].onHit;
    check('DC17 (2) per-dig sums to S',   r6(sPerDig), r6(two.S));
    check('DC18 (1) on-a-hit sums to ~1', r6(sOnHit), 1);

    -- symmetric three-item pool, w=100 each, mu=1: q=0.1, S=1-0.9^3=0.271,
    -- P_i=0.1*INT(0.9+0.1t)^2 = 0.0903333..., on-a-hit = 1/3 each.
    local three = dc.poolOdds({ { id = 1, n = 'a', w = 100, rank = 0 },
                                { id = 2, n = 'b', w = 100, rank = 0 },
                                { id = 3, n = 'c', w = 100, rank = 0 } }, 8, 1);
    check('DC19 three-item S = 0.271', r6(three.S), 0.271);
    check('DC20 three-item P_i', r6(three.items[1].P), r6(0.0903333333));
    check('DC21 three-item on-a-hit = 1/3', r6(three.items[2].onHit), r6(1/3));
    local t3 = three.items[1].P + three.items[2].P + three.items[3].P;
    check('DC22 three-item per-dig sums to S', r6(t3), r6(three.S));

    -- rank-gating: item 2 needs rank 5, player is rank 3 -> locked, q2=0, it
    -- drops out and reshapes the surviving share to 100%.
    local gated = dc.poolOdds({ { id = 1, n = 'a', w = 500, rank = 0 },
                                { id = 2, n = 'b', w = 1000, rank = 5 } }, 3, 1);
    check('DC23 over-rank item is locked', gated.items[2].locked, true);
    check('DC24 locked item q = 0',        gated.items[2].q, 0);
    check('DC25 locked item per-dig = 0',  gated.items[2].perDig, 0);
    check('DC26 surviving S = 0.5',        r6(gated.S), 0.5);
    check('DC27 surviving on-a-hit reshaped to 1', r6(gated.items[1].onHit), 1);
    check('DC28 active-item count drops to 1', gated.n, 1);

    -- moon applied correctly: a single 500-weight item is a certainty at best
    -- moon (S=1) and thins to 1/3 at worst.
    local mBest  = dc.poolOdds({ { id = 1, n = 'a', w = 500, rank = 0 } }, 8, dc.moonMult(0));
    local mWorst = dc.poolOdds({ { id = 1, n = 'a', w = 500, rank = 0 } }, 8, dc.moonMult(50));
    check('DC29 best moon -> S = 1',        r6(mBest.S), 1);
    check('DC30 worst moon -> S = 1/3',     r6(mWorst.S), r6(1/3));
    check('DC31 best moon beats worst',     mBest.S > mWorst.S, true);

    -- an asymmetric four-item pool at an off-neutral moon: the sum invariants
    -- must still hold exactly (the identity SUM P_i = S).
    local four = dc.poolOdds({ { id = 1, n = 'a', w = 300, rank = 0 },
                               { id = 2, n = 'b', w = 700, rank = 0 },
                               { id = 3, n = 'c', w = 250, rank = 0 },
                               { id = 4, n = 'd', w = 900, rank = 0 } }, 8, 1.2);
    local fp, fh = 0, 0;
    for _, it in ipairs(four.items) do fp = fp + it.perDig; fh = fh + it.onHit; end
    check('DC32 asymmetric per-dig sums to S', r6(fp), r6(four.S));
    check('DC33 asymmetric on-a-hit sums to 1', r6(fh), 1);

    -- digSuccess combines independent pools: two pools each with S=0.5 ->
    -- 1 - 0.5*0.5 = 0.75.
    local half = { { id = 1, n = 'x', w = 500, rank = 0 } };   -- S = 0.5 at mu=1
    check('DC34 general dig-success across pools', r6(dc.digSuccess({ half, half }, 8, 1)), 0.75);

    -- empty pool: S = 0, no items, no divide-by-zero.
    local empty = dc.poolOdds({}, 8, 1);
    check('DC35 empty pool S = 0', empty.S, 0);
    check('DC36 empty pool no items', #empty.items, 0);

    -- ---- digdata shape (the shipped table the guide trusts) ----
    dc._setDb(dofile('data/digdata.lua'));
    local db = dc.db();
    check('DC37 digdata loads', db ~= nil, true);
    check('DC38 rank ladder is 0..10', db.ranks and #db.ranks, 10);   -- [0]..[10] -> #=10
    check('DC38b Expert is rank 10',  db.ranks[10], 'Expert');
    check('DC39 Novice is rank 3',    db.ranks[3], 'Novice');
    check('DC40 Craftsman is rank 6', db.ranks[6], 'Craftsman');
    check('DC41 zones is a table',    type(db.zones), 'table');
    -- conditional rule tables: maps + gates, well-formed.
    local cond = dc.conditionals();
    check('DC42 conditionals present', type(cond), 'table');
    check('DC43 crystal gate ~10%, no rank', cond.crystals.chance == 10 and cond.crystals.minRank == 0, true);
    local nEl = 0; for _ in pairs(cond.crystals.byElement) do nEl = nEl + 1; end
    check('DC44 crystals cover 8 elements', nEl, 8);
    check('DC45 Fire crystal/cluster ids', cond.crystals.byElement.Fire.crystal == 4096
        and cond.crystals.byElement.Fire.cluster == 4104, true);
    check('DC46 Dark crystal/cluster ids', cond.crystals.byElement.Dark.crystal == 4103
        and cond.crystals.byElement.Dark.cluster == 4111, true);
    check('DC47 rock gate ~5% >= Novice', cond.rocks.chance == 5 and cond.rocks.minRank == 3, true);
    check('DC48 rock day->element map (Firesday=Fire)', cond.rocks.byDay.Firesday, 'Fire');
    local nDay = 0; for _ in pairs(cond.rocks.byDay) do nDay = nDay + 1; end
    check('DC49 rock day map has 8 days', nDay, 8);
    check('DC50 ore gate ~10% >= Craftsman', cond.ores.chance == 10 and cond.ores.minRank == 6, true);
    check('DC51 ore needs elemental weather', cond.ores.requiresElementalWeather, true);
    check('DC52 ore moon-phase window 7..21', cond.ores.moonPhaseWindow.min == 7 and cond.ores.moonPhaseWindow.max == 21, true);
    check('DC53 ore day->element map (Darksday=Dark)', cond.ores.byDay.Darksday, 'Dark');
    check('DC54 ore has a zone set', type(cond.ores.zones), 'table');

    -- every zone entry that IS present is well-formed (positive weights, valid
    -- pools, ranks in 0..8) -- guards a bad regeneration; passes vacuously while
    -- `zones` is empty pending the maintainer regen (see digdata's DATA STATUS).
    local VALID_POOL = { Treasure = true, Regular = true, Bore = true, Burrow = true };
    local zoneCount, badZone = 0, nil;
    for zid, z in pairs(db.zones) do
        zoneCount = zoneCount + 1;
        if type(z.n) ~= 'string' or type(z.pools) ~= 'table' then badZone = badZone or zid; end
        for pool, list in pairs(z.pools or {}) do
            if not VALID_POOL[pool] then badZone = badZone or ('pool:' .. tostring(pool)); end
            for _, it in ipairs(list) do
                if type(it.id) ~= 'number' or (tonumber(it.w) or 0) <= 0
                   or (tonumber(it.rank) or -1) < 0 or (tonumber(it.rank) or 99) > 8 then
                    badZone = badZone or ('item@' .. tostring(zid));
                end
            end
        end
    end
    check('DC55 every present zone is well-formed', badZone, nil);
    -- Once regenerated the table must hold exactly the 26 enabled zones; until
    -- then it is empty and the guide's by-zone queries fail soft. This asserts
    -- the invariant is one of those two honest states, never a partial mess.
    check('DC56 zone count is 0 (pending regen) or exactly 26', zoneCount == 0 or zoneCount == 26, true);

    -- ---- fail-soft: absent table disables data queries, never errors ----
    dc._setDb(false);
    check('DC57 absent db -> db() nil',        dc.db(), nil);
    check('DC58 absent db -> zoneIds empty',   #dc.zoneIds(), 0);
    check('DC59 absent db -> zoneOdds nil',    dc.zoneOdds(100, 8, 1), nil);
    check('DC60 absent db -> conditionals nil', dc.conditionals(), nil);
    -- pure math still works with no db (it never touches it)
    check('DC61 math works without a db', dc.poolOdds({ { id = 1, n = 'a', w = 500, rank = 0 } }, 8, 1).S, 0.5);
    dc._setDb(nil);   -- restore lazy load for any later section
end)();

-- ---------------------------------------------------------------------------
-- CHOCOBO DIG RANK + guide scaffold (issue #97, PRD #93): the pure rank
-- estimator (digrank -- ratchet / server-read decode / effective-rank resolve /
-- Obtained parse / item->rank lookup), the pure moon math (vanamoon), and
-- digcalc.averageSuccess for the general dig-success figure. All headless.
-- ---------------------------------------------------------------------------
(function()
    local dr = dofile('feature/digrank.lua');
    local vm = dofile('feature/vanamoon.lua');
    local dc = dofile('feature/digcalc.lua');
    local function r6(x) return math.floor((tonumber(x) or 0) * 1e6 + 0.5) / 1e6; end

    -- ---- digrank.clamp: snaps into 0..10, floors garbage to 0 ----
    check('DR1 clamp keeps in-range', dr.clamp(4), 4);
    check('DR2 clamp floors below 0', dr.clamp(-3), 0);
    check('DR3 clamp caps above 10',  dr.clamp(50), 10);
    check('DR3b MAX_RANK is Expert (10)', dr.MAX_RANK, 10);
    check('DR3c ladder labels Veteran + Expert', tostring(dr.RANKS[9]) .. '/' .. tostring(dr.RANKS[10]), 'Veteran/Expert');
    check('DR4 clamp rounds',         dr.clamp(3.6), 4);
    check('DR5 clamp nil -> 0',       dr.clamp(nil), 0);

    -- ---- ratchet: one-way, never lowers ----
    check('DR6 ratchet raises to a higher requirement', dr.ratchet(2, 5), 5);
    check('DR7 ratchet ignores a lower requirement',    dr.ratchet(5, 2), 5);
    check('DR8 ratchet equal stays',                    dr.ratchet(4, 4), 4);
    check('DR9 ratchet nil req leaves floor',           dr.ratchet(3, nil), 3);
    check('DR10 ratchet clamps a wild requirement',     dr.ratchet(0, 99), 10);
    -- monotonic across a sequence of digs (never dips)
    local floor, mono = 0, true;
    for _, req in ipairs({ 1, 3, 2, 6, 4, 5, 8, 7 }) do
        local nf = dr.ratchet(floor, req);
        if nf < floor then mono = false; end
        floor = nf;
    end
    check('DR11 ratchet is monotonic over a dig sequence', mono and floor, 8);

    -- ---- serverRank: masked read -> nil; real in-range -> rank ----
    check('DR12 masked 0xFFFF -> nil',        dr.serverRank(0xFFFF), nil);
    check('DR13 rank 31 (masked decode) -> nil', dr.serverRank(31), nil);
    check('DR14 a real rank 4 word -> 4',     dr.serverRank(4), 4);
    check('DR15 rank word 8 (Adept) -> 8',    dr.serverRank(8), 8);
    check('DR15b rank word 9 (Veteran) -> 9', dr.serverRank(9), 9);
    check('DR15c rank word 10 (Expert) -> 10', dr.serverRank(10), 10);
    check('DR16 out-of-ladder word 11 -> nil', dr.serverRank(11), nil);
    check('DR17 nil word -> nil',             dr.serverRank(nil), nil);

    -- ---- parseObtained: the dig "Obtained: <item>" line ----
    check('DR18 parses a plain Obtained line', dr.parseObtained('Obtained: Wind Crystal.'), 'Wind Crystal');
    check('DR19 tolerates no trailing period', dr.parseObtained('Obtained: Handful of Sand'), 'Handful of Sand');
    check('DR20 non-Obtained line -> nil',     dr.parseObtained('You dig and you dig...but find nothing.'), nil);
    check('DR21 nil line -> nil',              dr.parseObtained(nil), nil);
    -- inline chat colour/control codes (0x1E/0x1F + palette byte, stray controls)
    -- must not survive into the name -- else the ratchet lookup silently misses.
    check('DR21a strips a colour tag + param', dr._stripCodes('\30\06Wind Crystal\30\01'), 'Wind Crystal');
    check('DR21b strips a stray control byte', dr._stripCodes('Bird\1 Egg'), 'Bird Egg');
    check('DR21c clean text is untouched',     dr._stripCodes('Copper Ore'), 'Copper Ore');
    check('DR21d parse: name wrapped in colour codes', dr.parseObtained('Obtained: \30\06Wind Crystal\30\01.'), 'Wind Crystal');
    check('DR21e parse: a code AFTER the period', dr.parseObtained('Obtained: Maple Log.\31\02'), 'Maple Log');
    -- CASE-INSENSITIVE + prefix (the field bug: an item dig moved no rank because
    -- the tag casing / a leading prefix slipped past the old fixed-case pattern).
    -- The name must come back in its ORIGINAL case (the ratchet norm()s, but the
    -- announce shows it verbatim). Modeled on hgather's string.lower().match().
    check('DR21f ALL-CAPS tag still parses',    dr.parseObtained('OBTAINED: Chunk of Gold Ore.'), 'Chunk of Gold Ore');
    check('DR21g a leading prefix before tag',  dr.parseObtained('You dig and dig! Obtained: Bag of Fruit Seeds.'), 'Bag of Fruit Seeds');
    check('DR21h keeps original display case',  dr.parseObtained('obtained: Chunk of Platinum Ore.'), 'Chunk of Platinum Ore');
    check('DR21i classify ALL-CAPS -> obtained', ({dr.classifyDigLine('OBTAINED: Chunk of Gold Ore.')})[1], 'obtained');

    -- ---- itemRequirement: min rank across every source, fail-soft ----
    local SYNTH = { zones = {
        [100] = { n = 'A', pools = {
            Bore   = { { id = 1, n = 'Copper Ore', w = 500, rank = 2 } },
            Burrow = { { id = 2, n = 'Bird Egg',   w = 300, rank = 0 } },
        } },
        [101] = { n = 'B', pools = {
            Treasure = { { id = 1, n = 'Copper Ore', w = 400, rank = 5 } },   -- same item, harder here
        } },
    } };
    check('DR22 requirement = the MIN across sources', dr.itemRequirement('Copper Ore', SYNTH), 2);
    check('DR23 requirement is name-insensitive',      dr.itemRequirement('copper ORE.', SYNTH), 2);
    check('DR24 a rank-0 item',                        dr.itemRequirement('Bird Egg', SYNTH), 0);
    check('DR25 unknown item -> nil (no ratchet)',     dr.itemRequirement('Adaman Ore', SYNTH), nil);
    check('DR26 nil db -> nil (fail soft)',            dr.itemRequirement('Copper Ore', nil), nil);
    -- the M2 fix end-to-end: a colour-coded name still resolves its requirement
    -- (norm strips codes on BOTH sides), so the ratchet fires instead of missing.
    check('DR26a colour-coded name still resolves', dr.itemRequirement('\30\06Copper Ore\30\01', SYNTH), 2);
    -- itemRequirementById: the fail-safe 0x02A packet carries the id; prefer the
    -- CURRENT zone's requirement (you dug it here), else the cheapest zone.
    check('DR26b by-id = cheapest zone when no zone given', dr.itemRequirementById(1, SYNTH), 2);
    check('DR26c by-id prefers the CURRENT zone (harder here)', dr.itemRequirementById(1, SYNTH, 101), 5);
    check('DR26d by-id current zone (cheaper here)', dr.itemRequirementById(1, SYNTH, 100), 2);
    check('DR26e by-id a rank-0 item', dr.itemRequirementById(2, SYNTH), 0);
    check('DR26f unknown id -> nil (no ratchet)', dr.itemRequirementById(999, SYNTH), nil);
    check('DR26g nil id -> nil', dr.itemRequirementById(nil, SYNTH), nil);
    check('DR26h nil db -> nil (fail soft)', dr.itemRequirementById(1, nil), nil);
    -- ---- conditional (weather/day-gated) drops: crystals / rocks / ores ----
    -- These live in db.cond, NOT the zone pools, so the ratchet must scan them or a
    -- dug rock/ore raises no floor (the field gap). crystals gate at 0 (they are
    -- also rank-0 pool drops), day rocks at Novice(3), elemental ores at Craftsman(6).
    local COND = {
        zones = {
            [100] = { n = 'A', pools = {
                Regular = { { id = 4096, n = 'Fire Crystal', w = 50, rank = 0 } },      -- crystal: pool(0) + cond(0)
            } },
            [101] = { n = 'B', pools = {
                -- pretend Red Rock is ALSO a hard pool drop here (rank 8) to prove the
                -- ratchet takes the SAFE MIN with its rank-3 conditional, not the pool.
                Treasure = { { id = 769, n = 'Red Rock', w = 5, rank = 8 } },
            } },
        },
        cond = {
            crystals = { minRank = 0, byElement = { Fire = { crystal = 4096, cluster = 4104 } } },
            rocks    = { minRank = 3, byElement = { Fire = { id = 769,  n = 'Red Rock' } } },
            ores     = { minRank = 6, byElement = { Fire = { id = 1255, n = 'Chunk of Fire Ore' } } },
        },
    };
    check('DR26i cond by name: rock -> Novice(3)',   dr.condRequirement(COND, nil, 'Red Rock'), 3);
    check('DR26j cond by name: ore -> Craftsman(6)', dr.condRequirement(COND, nil, 'Chunk of Fire Ore'), 6);
    check('DR26k cond by id: rock',                  dr.condRequirement(COND, 769), 3);
    check('DR26l cond by id: ore',                   dr.condRequirement(COND, 1255), 6);
    check('DR26m cond by id: crystal -> 0',          dr.condRequirement(COND, 4096), 0);
    check('DR26n cond by id: cluster -> 0',          dr.condRequirement(COND, 4104), 0);
    check('DR26o crystal has no cond name -> nil',   dr.condRequirement(COND, nil, 'Fire Crystal'), nil);
    check('DR26p cond unknown id -> nil',            dr.condRequirement(COND, 999), nil);
    check('DR26q cond nil db -> nil (fail soft)',    dr.condRequirement(nil, 769), nil);
    -- THE GAP FIX: a conditional-ONLY ore now ratchets (returned nil before)
    check('DR26r ore ratchets by NAME (was nil)',    dr.itemRequirement('Chunk of Fire Ore', COND), 6);
    check('DR26s ore ratchets by ID (was nil)',      dr.itemRequirementById(1255, COND), 6);
    -- Red Rock is BOTH a rank-3 conditional and a (harder) rank-8 pool drop: the
    -- ratchet takes the SAFE MIN, and the zone-aware tighten must NOT over-claim the
    -- pool rank even when you dug it in that very zone.
    check('DR26t rock name = MIN(pool 8, cond 3)',      dr.itemRequirement('Red Rock', COND), 3);
    check('DR26u rock id = MIN(pool 8, cond 3)',        dr.itemRequirementById(769, COND), 3);
    check('DR26v rock id: cond beats the zone tighten', dr.itemRequirementById(769, COND, 101), 3);
    -- crystal is a rank-0 pool drop AND a rank-0 conditional -> 0 (never a floor)
    check('DR26w crystal by id = 0',                 dr.itemRequirementById(4096, COND, 100), 0);
    check('DR26x crystal by name = 0 (via pool)',    dr.itemRequirement('Fire Crystal', COND), 0);

    -- ---- resolve: precedence + honest exact flag ----
    local ranks = { [0]='Amateur',[1]='Recruit',[2]='Initiate',[3]='Novice',[4]='Apprentice',
                    [5]='Journeyman',[6]='Craftsman',[7]='Artisan',[8]='Adept' };
    local rManual = dr.resolve(3, 0, nil, ranks);
    check('DR27 manual seed drives the rank',   rManual.rank, 3);
    check('DR28 manual source labelled',        rManual.source, 'manual');
    check('DR29 manual is NOT exact',           rManual.exact, false);
    check('DR30 rank label resolved',           rManual.label, 'Novice');
    local rRatchet = dr.resolve(2, 5, nil, ranks);
    check('DR31 a floor above the pick wins',   rRatchet.rank, 5);
    check('DR32 ratchet source labelled',       rRatchet.source, 'ratchet');
    check('DR33 ratchet source label text',     rRatchet.sourceLabel, '>= from digs');
    check('DR34 ratchet is an estimate',        rRatchet.exact, false);
    local rBelow = dr.resolve(6, 3, nil, ranks);
    check('DR35 a floor below the pick is ignored', rBelow.rank, 6);
    check('DR36 ...and stays manual',               rBelow.source, 'manual');
    local rServer = dr.resolve(2, 4, 7, ranks);
    check('DR37 a server read beats both estimates', rServer.rank, 7);
    check('DR38 server source labelled',             rServer.source, 'server');
    check('DR39 server read IS exact',               rServer.exact, true);
    check('DR40 server source label text',           rServer.sourceLabel, 'reported by server');

    -- ---- gate: the grey-out verdict, where "never lie" lives ----
    check('DR40a reachable item is ok',            dr.gate(3, rManual), 'ok');   -- req 3 <= rank 3
    check('DR40b over an ESTIMATE -> dimmed',      dr.gate(5, rManual), 'dimmed');
    check('DR40c over an EXACT rank -> locked',    dr.gate(8, rServer), 'locked');  -- req 8 > exact 7
    check('DR40d exact but reachable -> ok',       dr.gate(7, rServer), 'ok');
    check('DR40e a bare rank number works too',    dr.gate(5, 2), 'dimmed');   -- no state = estimate
    check('DR40f a nil requirement is never gated', dr.gate(nil, rServer), 'ok');

    -- ---- timing rank detection (issue #100): classify + invert the first-dig
    --      zone cooldown clamp(60 - 5*rank, 10, 60) ----
    check('DT1 obtained line -> tag + item', (function()
        local t, i = dr.classifyDigLine('Obtained: Wind Crystal.'); return t .. '/' .. tostring(i);
    end)(), 'obtained/Wind Crystal');
    check('DT2 free reject -> wait',        dr.classifyDigLine('You must wait a little while longer.'), 'wait');
    check('DT3 "wait longer" phrasing -> wait', dr.classifyDigLine('You must wait longer to perform that action.'), 'wait');
    check('DT4 nothing-found -> nothing',   dr.classifyDigLine('You dig and you dig...but find nothing.'), 'nothing');
    check('DT5 with-ease -> ease',          dr.classifyDigLine('The chocobo digs with ease.'), 'ease');
    check('DT6 a non-dig line -> nil',      dr.classifyDigLine('Someone casts Fire.'), nil);
    check('DT7 nil line -> nil',            dr.classifyDigLine(nil), nil);
    -- completed-dig predicate (only these carry a usable first-dig timing)
    check('DT8 obtained is a completed dig', dr.isCompletedDig('obtained'), true);
    check('DT9 nothing is a completed dig',  dr.isCompletedDig('nothing'), true);
    check('DT10 ease is a completed dig',    dr.isCompletedDig('ease'), true);
    check('DT11 a reject is NOT a completed dig', dr.isCompletedDig('wait'), false);
    -- invert the cooldown: threshold seconds -> rank (round to the 5s rung)
    check('DT12 60s -> Amateur (0)',   dr.rankFromZoneTiming(60), 0);
    check('DT13 20s -> Adept (8)',     dr.rankFromZoneTiming(20), 8);
    check('DT14 15s -> Veteran (9)',   dr.rankFromZoneTiming(15), 9);
    check('DT15 10s -> Expert (10)',   dr.rankFromZoneTiming(10), 10);
    check('DT16 Henrik: 11s -> Expert (10)', dr.rankFromZoneTiming(11), 10);   -- field data
    check('DT17 sub-floor (<10s) still Expert', dr.rankFromZoneTiming(4), 10);  -- 10s clamp floor
    check('DT18 a late dig reads a low rank (never negative)', dr.rankFromZoneTiming(300), 0);
    -- FLOOR into the 5s rung, never ROUND: lag only ever pushes the observed
    -- delay LATER, so each rank is a [C, C+5) bracket (Henrik field 2026-07-24).
    check('DT19 13s (lagged Expert) FLOORS to Expert, not Veteran', dr.rankFromZoneTiming(13), 10);  -- round gave 9
    check('DT19a 14.9s (top of the Expert bracket) -> Expert', dr.rankFromZoneTiming(14.9), 10);
    check('DT19b 15s (next bracket) -> Veteran',      dr.rankFromZoneTiming(15), 9);
    check('DT19c 17s stays within Veteran',           dr.rankFromZoneTiming(17), 9);
    check('DT19d 19.9s (top of Veteran) -> Veteran',  dr.rankFromZoneTiming(19.9), 9);
    check('DT19e 24.9s (top of Adept) -> Adept',      dr.rankFromZoneTiming(24.9), 8);
    check('DT20 non-number threshold -> nil', dr.rankFromZoneTiming('soon'), nil);
    check('DT21 non-positive threshold -> nil', dr.rankFromZoneTiming(0), nil);

    -- ---- vanamoon: pure moon math ----
    check('VM1 percent in 0..100 across the whole cycle', (function()
        for d = 0, 200 do local p = vm.percent(d); if type(p) ~= 'number' or p < 0 or p > 100 then return false; end end
        return true;
    end)(), true);
    -- symmetric around the Full midpoint: age a and (CYCLE-a) share a percent.
    check('VM2 illumination is symmetric about Full', (function()
        for a = 1, 41 do
            local dayLow  = a - vm.OFFSET;              -- age a
            local dayHigh = (vm.CYCLE - a) - vm.OFFSET; -- age CYCLE-a
            if vm.percent(dayLow) ~= vm.percent(dayHigh) then return false; end
        end
        return true;
    end)(), true);
    check('VM3 New Moon (age 0) is 0%',  vm.percent(0 - vm.OFFSET), 0);
    check('VM4 Full Moon (age 42) is 100%', vm.percent(42 - vm.OFFSET), 100);
    check('VM5 waxing before Full', vm.waxing(10 - vm.OFFSET), true);
    check('VM6 waning after Full',  vm.waxing(60 - vm.OFFSET), false);
    check('VM7 New Moon named',  vm.name(0 - vm.OFFSET),  'New Moon');
    check('VM8 Full Moon named', vm.name(42 - vm.OFFSET), 'Full Moon');
    check('VM9 phase() bundles the fields', (function()
        local ph = vm.phase(42 - vm.OFFSET);
        return type(ph) == 'table' and ph.percent == 100 and ph.name == 'Full Moon';
    end)(), true);
    check('VM10 bad day -> nil (graceful)', vm.phase(nil), nil);
    -- SERVER-CONVENTION pins (absolute day numbers, NOT relative to OFFSET) --
    -- these lock vanamoon to moon::get_phase in src/common/vana_time.h, where
    -- daysmod=(day+26)%84: daysmod 0 (day 58) = 100% Full, daysmod 42 (day 16)
    -- = 0% New, daysmod<42 waning, daysmod>42 waxing. VM1-VM10 only test the
    -- internal curve shape and never caught the epoch being half a cycle off.
    check('VM11 day 58 (daysmod 0) is 100% Full', vm.percent(58), 100);
    check('VM12 day 58 named Full Moon',          vm.name(58),    'Full Moon');
    check('VM13 day 16 (daysmod 42) is 0% New',   vm.percent(16), 0);
    check('VM14 day 16 named New Moon',            vm.name(16),    'New Moon');
    check('VM15 day 79 (daysmod 21) is waning',   vm.waxing(79),  false);
    check('VM16 day 37 (daysmod 63) is waxing',   vm.waxing(37),  true);

    -- ---- digcalc.averageSuccess: the general dig-success figure ----
    dc._setDb(false);
    check('DR41 averageSuccess nil when no data', dc.averageSuccess(8, 1), nil);
    dc._setDb({ zones = {
        [1] = { n = 'X', pools = { Bore = { { id = 1, n = 'a', w = 500, rank = 0 } } } },   -- S = 0.5 at mu=1
        [2] = { n = 'Y', pools = { Bore = { { id = 2, n = 'b', w = 1000, rank = 0 } } } },  -- S = 1   at mu=1
    } });
    local avg, nz = dc.averageSuccess(8, 1);
    check('DR42 averageSuccess = mean of zone S', r6(avg), r6((0.5 + 1) / 2));
    check('DR43 averageSuccess reports zone count', nz, 2);
    -- rank-gating flows through: an over-rank pool zeroes out -> success 0.
    dc._setDb({ zones = { [1] = { n = 'X', pools = { Bore = { { id = 1, n = 'a', w = 500, rank = 5 } } } } } });
    check('DR44 averageSuccess honours rank-gating', r6((dc.averageSuccess(0, 1))), 0);
    dc._setDb(nil);   -- restore lazy load
end)();

-- ---------------------------------------------------------------------------
-- CHOCOBO BY-AREA: the pure data seams the by-area tab composes (issue #98,
-- PRD #93) -- digcalc.zones (the zone-picker source) and digcalc.conditionalDrops
-- (weather crystal / day rock / elemental ore resolved against the live clock,
-- flagged active/inactive). Uses the SHIPPED digdata (26 zones + the FFXI-standard
-- cond tables); the odds math itself is covered by DC1-61. All headless.
-- ---------------------------------------------------------------------------
(function()
    local dc = dofile('feature/digcalc.lua');
    package.loaded['dlac\\feature\\digcalc'] = dc;
    dc._setDb(dofile('data/digdata.lua'));

    -- ---- zones(): the sorted { id, n } zone-picker source ----
    local zl = dc.zones();
    check('BA1 zones() lists the 26 enabled zones', #zl, 26);
    check('BA2 zones() is sorted by name', (function()
        for i = 2, #zl do if tostring(zl[i - 1].n) > tostring(zl[i].n) then return false; end end
        return true;
    end)(), true);
    check('BA3 each zone entry has id + name', (function()
        for _, z in ipairs(zl) do
            if type(z.id) ~= 'number' or type(z.n) ~= 'string' then return false; end
        end
        return true;
    end)(), true);

    -- ---- _normElement: the Thunder/Lightning + non-elemental normalisation ----
    check('BA4 Thunder normalises to Lightning', dc._normElement('Thunder'), 'Lightning');
    check('BA5 an ordinary element passes through', dc._normElement('Fire'), 'Fire');
    check('BA6 None/Clear/empty -> nil (no elemental weather)',
        dc._normElement('None') == nil and dc._normElement('Clear') == nil and dc._normElement('') == nil, true);

    -- ---- conditionalDrops on an ORE zone under a fully-satisfied clock ----
    -- Zone 104 (Jugner Forest) is one of the 9 elemental-ore zones. Firesday +
    -- Fire weather + moon 14% + rank 8 satisfies every gate.
    local clkFull = { dayElement = 'Fire', weatherElement = 'Fire', doubleWeather = false, moonPercent = 14 };
    local cd = dc.conditionalDrops(104, 8, clkFull);
    check('BA7 ore zone lists crystal + rock + ore', #cd, 3);
    local byKind = {}; for _, r in ipairs(cd) do byKind[r.kind] = r; end
    check('BA8 crystal is the Fire Crystal (id + name)',
        byKind.crystal and byKind.crystal.id == 4096 and byKind.crystal.n, 'Fire Crystal');
    check('BA9 crystal active under Fire weather', byKind.crystal.active, true);
    check('BA10 rock is the Fire day rock', byKind.rock and byKind.rock.id == 769 and byKind.rock.n, 'Red Rock');
    check('BA11 rock active at rank 8 (>= Novice)', byKind.rock.active, true);
    check('BA12 ore is the Fire ore', byKind.ore and byKind.ore.id == 1255 and byKind.ore.n, 'Chunk of Fire Ore');
    check('BA13 ore active under the full gate', byKind.ore.active, true);

    -- ---- rank-gating flows through (active is clockActive AND rankOk) ----
    local cdLow = dc.conditionalDrops(104, 0, clkFull);
    local lowByKind = {}; for _, r in ipairs(cdLow) do lowByKind[r.kind] = r; end
    check('BA14 crystal still active at rank 0 (no rank gate)', lowByKind.crystal.active, true);
    check('BA15 rock inactive at rank 0 but the clock condition IS met',
        lowByKind.rock.active == false and lowByKind.rock.clockActive == true, true);
    check('BA16 ore inactive at rank 0 (Craftsman gate) though the clock is met',
        lowByKind.ore.active == false and lowByKind.ore.clockActive == true, true);

    -- ---- the Thunder alias resolves the live weather to the Lightning crystal ----
    local cdThunder = dc.conditionalDrops(2, 8, { dayElement = 'Lightning', weatherElement = 'Thunder', moonPercent = 50 });
    local thByKind = {}; for _, r in ipairs(cdThunder) do thByKind[r.kind] = r; end
    check('BA17 Thunder weather -> Lightning Crystal id 4100',
        thByKind.crystal and thByKind.crystal.id, 4100);

    -- ---- a NON-ore zone omits the ore row entirely ----
    local cdNoOre = dc.conditionalDrops(2, 8, clkFull);   -- zone 2 is not an ore zone
    check('BA18 non-ore zone lists only crystal + rock', #cdNoOre, 2);
    check('BA19 ...and no ore row', (function()
        for _, r in ipairs(cdNoOre) do if r.kind == 'ore' then return 'ore present'; end end
        return true;
    end)(), true);

    -- ---- double weather yields the cluster, not the crystal ----
    local cdDbl = dc.conditionalDrops(2, 8, { dayElement = 'Fire', weatherElement = 'Fire', doubleWeather = true, moonPercent = 50 });
    local dblByKind = {}; for _, r in ipairs(cdDbl) do dblByKind[r.kind] = r; end
    check('BA20 double Fire weather -> Fire Cluster (id 4104)',
        dblByKind.crystal and dblByKind.crystal.id == 4104 and dblByKind.crystal.n, 'Fire Cluster');

    -- ---- the ore gate: weather must match the day, moon must be in-window ----
    local cdMoon = dc.conditionalDrops(104, 8, { dayElement = 'Fire', weatherElement = 'Fire', moonPercent = 50 });
    local moonByKind = {}; for _, r in ipairs(cdMoon) do moonByKind[r.kind] = r; end
    check('BA21 ore inactive when the moon is out of the 7-21% window',
        moonByKind.ore.active == false and moonByKind.ore.clockActive == false, true);
    local cdWeather = dc.conditionalDrops(104, 8, { dayElement = 'Fire', weatherElement = 'Ice', moonPercent = 14 });
    local wByKind = {}; for _, r in ipairs(cdWeather) do wByKind[r.kind] = r; end
    check('BA22 ore inactive when the weather does not match the day', wByKind.ore.clockActive, false);
    check('BA23 ...but that same off-element Ice weather lights the Ice crystal',
        wByKind.crystal and wByKind.crystal.id, 4097);

    -- ---- no elemental weather: the crystal row is inactive, never errors ----
    local cdClear = dc.conditionalDrops(2, 8, { dayElement = 'Fire', weatherElement = 'None', moonPercent = 14 });
    local clByKind = {}; for _, r in ipairs(cdClear) do clByKind[r.kind] = r; end
    check('BA24 no elemental weather -> crystal inactive, no concrete id',
        clByKind.crystal.clockActive == false and clByKind.crystal.id == nil, true);

    -- ---- fail soft: no db -> empty results, never an error ----
    dc._setDb(false);
    check('BA25 absent db -> zones() empty', #dc.zones(), 0);
    check('BA26 absent db -> conditionalDrops() empty', #dc.conditionalDrops(104, 8, clkFull), 0);
    dc._setDb(nil);   -- restore lazy load
end)();

-- ---------------------------------------------------------------------------
-- CHOCOBO BY-ITEM: the pure data seams the by-item tab composes (issue #99,
-- PRD #93) -- digcalc.itemIndex (the fuzzy-search source, pool items PLUS the
-- synthesised conditional crystals/rocks/ores) and digcalc.itemSources (every
-- zone + pool a selected item drops from, priced + flagged). Uses the SHIPPED
-- digdata; the odds math itself is DC1-61. All headless, PURE (clock passed in).
-- ---------------------------------------------------------------------------
(function()
    local dc = dofile('feature/digcalc.lua');
    package.loaded['dlac\\feature\\digcalc'] = dc;
    dc._setDb(dofile('data/digdata.lua'));

    -- ---- itemIndex(): the searchable diggable-item index ----
    local idx = dc.itemIndex();
    check('BI1 itemIndex is non-empty (120 pool items + 32 conditionals)', #idx, 152);
    check('BI2 itemIndex is sorted by name', (function()
        for i = 2, #idx do if tostring(idx[i - 1].n) > tostring(idx[i].n) then return false; end end
        return true;
    end)(), true);
    local byKey = {}; for _, e in ipairs(idx) do byKey[e.key] = e; end
    -- the conditional crystals / clusters / rocks / ores are keyed by condKind:el
    -- (a conditional item can SHARE a name with a static pool drop -- Fire Crystal
    -- is both a weather conditional AND a listed pool item in some zones -- so the
    -- index carries a distinct entry for each; assert by key, not by name).
    check('BI3 Fire Crystal (conditional) is in the index, id 4096',
        byKey['crystal:Fire'] and byKey['crystal:Fire'].id == 4096
        and byKey['crystal:Fire'].n == 'Fire Crystal'
        and byKey['crystal:Fire'].kind == 'conditional'
        and byKey['crystal:Fire'].condKind, 'crystal');
    check('BI4 Fire Cluster is in the index (conditional cluster, id 4104)',
        byKey['cluster:Fire'] and byKey['cluster:Fire'].id == 4104
        and byKey['cluster:Fire'].n == 'Fire Cluster'
        and byKey['cluster:Fire'].condKind, 'cluster');
    check('BI5 Chunk of Fire Ore is in the index (ore, minRank 6)',
        byKey['ore:Fire'] and byKey['ore:Fire'].id == 1255
        and byKey['ore:Fire'].n == 'Chunk of Fire Ore'
        and byKey['ore:Fire'].condKind == 'ore'
        and byKey['ore:Fire'].minRank, 6);
    check('BI6 Red Rock is in the index (rock, minRank 3 = Novice)',
        byKey['rock:Fire'] and byKey['rock:Fire'].n == 'Red Rock'
        and byKey['rock:Fire'].condKind == 'rock'
        and byKey['rock:Fire'].minRank, 3);
    check('BI7 exactly 32 conditional entries (8 each: crystal/cluster/rock/ore)', (function()
        local c = 0; for _, e in ipairs(idx) do if e.kind == 'conditional' then c = c + 1; end end
        return c;
    end)(), 32);
    check('BI8 a pool entry carries a pool key + kind', (function()
        local e = byKey['pool:3509'];   -- Plate of Heavy Metal
        return e and e.kind == 'pool' and e.n or false;
    end)(), 'Plate of Heavy Metal');

    -- ---- itemSources() on a POOL item present in many zones ----
    -- Plate of Heavy Metal (3509) drops in 22 zones; price at rank 8, neutral moon.
    local plate = byKey['pool:3509'];
    local ps = dc.itemSources(plate, 8, dc.moonMult(50), {});
    check('BI9 pool itemSources returns a pool view', type(ps) == 'table'
        and ps.kind == 'pool' and ps.allZones == false, true);
    check('BI10 pool sources cover the 22 zones it drops in', #ps.sources, 22);
    check('BI11 each pool source carries zone + pool + the two odds', (function()
        for _, s in ipairs(ps.sources) do
            if type(s.zoneId) ~= 'number' or type(s.zoneName) ~= 'string'
               or type(s.pool) ~= 'string' or type(s.onHit) ~= 'number'
               or type(s.perDig) ~= 'number' then return false; end
        end
        return true;
    end)(), true);
    check('BI12 pool sources are sorted by per-dig descending', (function()
        for i = 2, #ps.sources do
            if (ps.sources[i - 1].perDig or 0) < (ps.sources[i].perDig or 0) then return false; end
        end
        return true;
    end)(), true);

    -- ---- itemSources() on a CONDITIONAL crystal: EVERY digging zone ----
    -- Fire Crystal under Fire weather (single) is active in all 26 zones.
    local fc = byKey['crystal:Fire'];
    local cs = dc.itemSources(fc, 8, dc.moonMult(50),
        { weatherElement = 'Fire', dayElement = 'Ice', doubleWeather = false, moonPercent = 50 });
    check('BI13 crystal itemSources spans every enabled zone (allZones)', cs.allZones == true and #cs.sources, 26);
    check('BI14 crystal active now under matching single weather', cs.active, true);
    check('BI15 crystal condition is spelled out', cs.condition, 'Fire weather up');
    -- double Fire weather yields the CLUSTER, so the single crystal is inactive.
    local csDbl = dc.itemSources(fc, 8, dc.moonMult(50),
        { weatherElement = 'Fire', doubleWeather = true, moonPercent = 50 });
    check('BI16 single crystal inactive under DOUBLE weather (that is the cluster)', csDbl.active, false);
    -- the Thunder/Lightning alias resolves the live weather to the Lightning crystal.
    local lc = byKey['crystal:Lightning'];
    local ls = dc.itemSources(lc, 8, dc.moonMult(50), { weatherElement = 'Thunder', moonPercent = 50 });
    check('BI17 Thunder weather activates the Lightning Crystal', ls.active, true);

    -- ---- itemSources() on the CLUSTER: active only under double weather ----
    local fcl = byKey['cluster:Fire'];
    local cls = dc.itemSources(fcl, 8, dc.moonMult(50), { weatherElement = 'Fire', doubleWeather = true, moonPercent = 50 });
    check('BI18 cluster active under double weather', cls.active, true);
    check('BI19 cluster condition names the double weather', cls.condition, 'double Fire weather');

    -- ---- itemSources() on an ORE: only the 9 elemental-ore zones ----
    local ore = byKey['ore:Fire'];
    local os = dc.itemSources(ore, 8, dc.moonMult(14),
        { dayElement = 'Fire', weatherElement = 'Fire', moonPercent = 14 });
    check('BI20 ore itemSources spans only the ore zones (not all-zone)', os.allZones == false and #os.sources, 9);
    check('BI21 ore active under the full gate (rank 8, Fire day+weather, moon 14%)', os.active, true);
    -- rank gate: below Craftsman the ore is not reachable though the clock is met.
    local osLow = dc.itemSources(ore, 0, dc.moonMult(14),
        { dayElement = 'Fire', weatherElement = 'Fire', moonPercent = 14 });
    check('BI22 ore rankOk false at rank 0 though the clock is met',
        osLow.rankOk == false and osLow.clockActive == true and osLow.active == false, true);
    -- moon out of window closes the clock gate.
    local osMoon = dc.itemSources(ore, 8, dc.moonMult(50),
        { dayElement = 'Fire', weatherElement = 'Fire', moonPercent = 50 });
    check('BI23 ore clock closes when the moon is out of the 7-21% window', osMoon.clockActive, false);

    -- ---- a locked pool item over-rank: the row carries the locked flag ----
    -- King Truffle (Carpenters Landing Treasure) needs rank 8; at rank 0 it locks.
    local kt = byKey['pool:4386'];
    if kt ~= nil then
        local kts = dc.itemSources(kt, 0, dc.moonMult(50), {});
        check('BI24 an over-rank pool item marks its source locked', (function()
            for _, s in ipairs(kts.sources) do if s.locked ~= true then return false; end end
            return #kts.sources > 0;
        end)(), true);
    end

    -- ---- fail soft: no db / nil entry -> empty index, nil sources ----
    dc._setDb(false);
    check('BI25 absent db -> itemIndex empty', #dc.itemIndex(), 0);
    check('BI26 absent db -> itemSources nil', dc.itemSources(plate, 8, 1, {}), nil);
    dc._setDb(dofile('data/digdata.lua'));
    check('BI27 nil entry -> itemSources nil', dc.itemSources(nil, 8, 1, {}), nil);
    dc._setDb(nil);   -- restore lazy load
end)();

-- ---------------------------------------------------------------------------
-- ML. modeslibrary -- the Mode library pure core (ADR 0019, 2026-07-24).
-- Own function scope (a do-block's locals share the chunk's 200 budget).
-- ---------------------------------------------------------------------------
;(function()
    local ml = dofile('gear/modeslibrary.lua');
    -- A broken plan can hand back nil where a list is expected. table.concat would
    -- then CRASH the whole suite and hide every later check, so render nil instead --
    -- a regression must fail loudly and locally, not take the run down with it.
    local function join(t)
        if type(t) ~= 'table' then return '(nil)'; end
        return table.concat(t, ',');
    end
    check('ML1 module loads headless', type(ml), 'table');

    -- Entry construction. kind is DERIVED from the values, never trusted, because
    -- `def.values ~= nil` is the sole cycle test everywhere else in dlac.
    local tog = ml.makeEntry('DT', nil, 'F9');
    check('ML2 no values -> toggle',    tog.kind, 'toggle');
    check('ML3 toggle keeps its bind',  tog.bind, 'F9');
    local cyc = ml.makeEntry('Weapon', { 'Melee', 'Ranged', 'Caster' }, '^F3');
    check('ML4 values -> cycle',        cyc.kind, 'cycle');
    check('ML5 cycle keeps order',      join(cyc.values), 'Melee,Ranged,Caster');
    check('ML6 blank name refused',     (select(2, ml.makeEntry('  ', nil, nil))), 'A mode needs a name.');
    check('ML7 one-value cycle refused',(select(2, ml.makeEntry('X', { 'Only' }, nil))), 'A cycle needs at least two values.');
    check('ML8 values dedupe case-insensitively',
        join(ml.makeEntry('W', { 'Melee', 'melee', 'Ranged' }).values), 'Melee,Ranged');
    check('ML9 blank values dropped',
        join(ml.makeEntry('W', { 'A', '', '  ', 'B' }).values), 'A,B');

    -- Engine-owned names must never become library entries.
    check('ML10 maxmp is reserved',     ml.isReserved('maxmp'), true);
    check('ML11 craft is reserved',     ml.isReserved('CRAFT'), true);
    check('ML12 craftgoal is reserved', ml.isReserved('craftgoal'), true);
    check('ML13 ordinary name is not',  ml.isReserved('Weapon'), false);
    check('ML14 reserved name refused at capture',
        (ml.makeEntry('maxmp', nil, nil) == nil), true);

    -- toDef: a bare toggle MUST serialize as {} and not nil -- an empty definition is
    -- load-bearing (it is what keeps a plain toggle listed across a commit round-trip).
    local d = ml.toDef(ml.makeEntry('DT'));
    check('ML15 bare toggle def is a table', type(d), 'table');
    check('ML16 bare toggle def is empty',   next(d), nil);

    -- ---- THE STAMP ----
    local job = {
        Weapon = { values = { 'Melee', 'Ranged', 'Caster' }, bind = '^F3' },
        DT = {},
    };

    -- create
    local p = ml.stampPlan(ml.makeEntry('TH', nil, nil), job, 'append');
    check('ML17 new name is a create', p.action, 'create');
    check('ML18 create collides with nothing', p.collides, false);
    check('ML19 create strands nothing', #p.dead, 0);

    -- append merges and NEVER drops
    p = ml.stampPlan(ml.makeEntry('Weapon', { 'Ranged', 'Tank' }), job, 'append');
    check('ML20 append action',            p.action, 'append');
    check('ML21 append keeps every old value', join(p.after), 'Melee,Ranged,Caster,Tank');
    check('ML22 append strands nothing',   #p.dead, 0);
    check('ML23 append reports what is new', join(p.added), 'Tank');
    check('ML24 append keeps the existing bind', p.bindTo, '^F3');

    -- overwrite drops, and names exactly what died
    p = ml.stampPlan(ml.makeEntry('Weapon', { 'Melee', 'Tank' }), job, 'overwrite');
    check('ML25 overwrite action',       p.action, 'overwrite');
    check('ML26 overwrite replaces',     join(p.after), 'Melee,Tank');
    check('ML27 overwrite names the dead', join(p.dead), 'Ranged,Caster');
    check('ML28 dead targets are Name:Value',
        table.concat(ml.deadTargets(p), ' '), 'Weapon:Ranged Weapon:Caster');
    -- (Every cycle below needs >= 2 values or makeEntry refuses it and stampPlan gets
    -- a nil -- which would make these pass for the wrong reason. ML29a proves the
    -- plan actually exists before ML29 trusts its emptiness.)
    local appendPlan = ml.stampPlan(ml.makeEntry('Weapon', { 'Tank', 'Melee' }), job, 'append');
    check('ML29a append plan really exists', type(appendPlan), 'table');
    check('ML29 append produces no strip targets', #ml.deadTargets(appendPlan), 0);

    -- THE REGRESSION THIS EXISTS FOR: a TOGGLE stamped onto a CYCLE. Under Append the
    -- cycle must KEEP its values -- demoting it would silently kill every Name:Value
    -- reference, which is the exact thing Append promises not to do. Overwrite is how
    -- you demote on purpose, and then every value is correctly reported dead.
    p = ml.stampPlan(ml.makeEntry('Weapon', nil, nil), job, 'append');
    check('ML30 append refuses to demote a cycle', p.kind, 'cycle');
    check('ML31 append demote strands nothing',    #p.dead, 0);
    check('ML32 append demote keeps values', join(p.after), 'Melee,Ranged,Caster');
    p = ml.stampPlan(ml.makeEntry('Weapon', nil, nil), job, 'overwrite');
    check('ML33 overwrite CAN demote a cycle', p.kind, 'toggle');
    check('ML34 demotion kills every value',
        join(p.dead), 'Melee,Ranged,Caster');

    -- adding values to an existing TOGGLE deletes nothing
    p = ml.stampPlan(ml.makeEntry('DT', { 'Low', 'High' }), job, 'append');
    check('ML35 toggle -> cycle is not destructive', #p.dead, 0);
    check('ML36 toggle -> cycle takes the values', join(p.after), 'Low,High');

    -- the EXISTING spelling wins, so references keep pointing at the same key
    p = ml.stampPlan(ml.makeEntry('weapon', { 'Melee', 'Ranged' }), job, 'append');
    check('ML37 collision keeps the stored spelling', p.name, 'Weapon');

    -- a stamp that changes literally nothing says so
    p = ml.stampPlan(ml.makeEntry('Weapon', { 'Melee', 'Ranged', 'Caster' }, '^F3'), job, 'append');
    check('ML38 no-op stamp is flagged', p.action, 'rebind');

    -- applyStamp never mutates the caller's map (so a plan can be abandoned)
    local before = ml.stampPlan(ml.makeEntry('Weapon', { 'Zzz', 'Yyy' }), job, 'overwrite');
    local newMap = ml.applyStamp(ml.makeEntry('Weapon', { 'Zzz', 'Yyy' }), job, 'overwrite');
    check('ML39 original map untouched',
        join(job.Weapon.values), 'Melee,Ranged,Caster');
    check('ML40 new map has the new values',
        join(newMap.Weapon.values), 'Zzz,Yyy');
    check('ML41 untouched modes survive', type(newMap.DT), 'table');
    check('ML42 plan and apply agree', before.action, 'overwrite');
    -- a differently-cased duplicate key must not survive the write
    local dup = ml.applyStamp(ml.makeEntry('weapon', { 'A', 'B' }), { Weapon = { values = { 'A' } } }, 'overwrite');
    check('ML43 no duplicate-cased key', (dup['weapon'] == nil), true);
    check('ML44 canonical key kept',     type(dup['Weapon']), 'table');

    -- ---- capture from a job ----
    local caps, refused = ml.captureAll({ Weapon = { values = { 'A', 'B' } }, DT = {}, maxmp = {} });
    check('ML45 captures both real modes', #caps, 2);
    check('ML46 sorted by name',           caps[1].name, 'DT');
    check('ML47 reserved name refused, not dropped silently', #refused, 1);
    check('ML48 refusal names the mode',   refused[1].name, 'maxmp');

    -- ---- round-trip ----
    local lib = {};
    ml.add(lib, ml.makeEntry('Weapon', { 'Melee', 'Ranged' }, '^F3'));
    ml.add(lib, ml.makeEntry('DT', nil, 'F9'));
    local text = ml.serialize(lib);
    local back, perr = ml.parse(text);
    check('ML49 serialize/parse round-trips', perr, nil);
    check('ML50 count survives',   #back, 2);
    check('ML51 values survive',   join(back[1].values), 'Melee,Ranged');
    check('ML52 bind survives',    back[2].bind, 'F9');
    check('ML53 kind survives',    back[2].kind, 'toggle');
    check('ML54 deterministic',    ml.serialize(back), text);

    -- hostile / torn input is reported, never executed
    check('ML55 empty input refused', (select(2, ml.parse(''))), 'empty input');
    check('ML56 garbage refused',     (ml.parse('this is not lua') == nil), true);
    check('ML57 non-table refused',   (select(2, ml.parse('return 5'))), 'did not return a table');
    check('ML58 sandbox blocks os.exit', (function()
        local r, e = ml.parse('os.exit(1) return {}');
        return r == nil and e ~= nil;
    end)(), true);
    check('ML59 sandbox blocks io', (function()
        local r = ml.parse('return { modes = { { name = io.open("x") } } }');
        return r == nil or #r == 0;
    end)(), true);
    check('ML60 quotes/newlines survive a round-trip', (function()
        local l = { ml.makeEntry('We"ird\nName', { 'A', 'B' }) };
        local rt = ml.parse(ml.serialize(l));
        return rt ~= nil and rt[1] ~= nil and rt[1].name;
    end)(), 'We"ird\nName');

    -- ---- library CRUD + import ----
    check('ML61 duplicate add refused', (ml.add(lib, ml.makeEntry('DT'))), false);
    check('ML62 replace add allowed',   (ml.add(lib, ml.makeEntry('DT', nil, 'F10'), true)), true);
    check('ML63 replace took effect',   lib[ml.findEntryCI(lib, 'DT')].bind, 'F10');
    check('ML64 rename to a taken name refused', (ml.rename(lib, 1, 'DT')), false);
    check('ML65 rename to reserved refused',     (ml.rename(lib, 1, 'craft')), false);
    check('ML66 rename works',                   (ml.rename(lib, 1, 'Arms')), true);

    local created, collided = ml.classifyImport(
        { ml.makeEntry('Arms', { 'X', 'Y' }), ml.makeEntry('Brand New') }, lib);
    check('ML67 collision detected', table.concat(collided, ','), 'Arms');
    check('ML68 new entry detected', table.concat(created, ','), 'Brand New');

    local res = ml.applyImport(lib, { ml.makeEntry('Arms', { 'X', 'Y' }) }, false);
    check('ML69 collision refused without confirmation', res.refused, 1);
    check('ML70 ...and nothing changed', join(lib[1].values), 'Melee,Ranged');
    res = ml.applyImport(lib, { ml.makeEntry('Arms', { 'X', 'Y' }) }, true);
    check('ML71 confirmed overwrite updates', res.updated, 1);
    check('ML72 ...and the values changed', join(lib[1].values), 'X,Y');
    res = ml.applyImport(lib, { { name = 'maxmp' } }, true);
    check('ML73 import cannot smuggle in a reserved name', res.refused, 1);

    -- ---- MG. set-entry gate walk (lifted out of gearui so it can be tested) ----
    -- This is the half of the cascade that DELETES gear rows. It had no headless
    -- coverage at all while it lived as a gearui chunk-local.
    check('MG1 exact value hits itself',  ml.gateMatches('Weapon:Caster', 'Weapon:Caster'), true);
    check('MG2 whole mode hits a value',  ml.gateMatches('Weapon:Caster', 'Weapon'), true);
    check('MG3 whole mode hits the bare gate', ml.gateMatches('Weapon', 'Weapon'), true);
    check('MG4 exact value MISSES the bare gate', ml.gateMatches('Weapon', 'Weapon:Caster'), false);
    check('MG5 case-insensitive',         ml.gateMatches('weapon:caster', 'Weapon:Caster'), true);
    check('MG6 near-name is not a prefix hit', ml.gateMatches('WeaponX:A', 'Weapon'), false);
    check('MG7 empty target hits nothing', ml.gateMatches('Weapon', ''), false);

    local function mkWorking()
        return {
            Main = {
                { mode = 'Weapon:Caster', rec = { Name = 'Staff' } },      -- only gate -> row dies
                { mode = { 'Weapon:Caster', 'DT' }, rec = { Name = 'Club' } }, -- keeps DT
                { mode = 'Weapon', rec = { Name = 'Bare' } },              -- bare: NEVER touched
                { rec = { Name = 'Plain' } },                              -- ungated
            },
        };
    end

    -- preview (strip = false) must report without changing anything
    local w = mkWorking();
    local r = ml.gateRefsInSet('TP', w, 'Weapon:Caster', false);
    check('MG8 preview finds both gated rows', #r.refs, 2);
    check('MG9 preview changes nothing',       r.changed, false);
    check('MG10 preview left the rows in place', #w.Main, 4);
    check('MG11 sole-gate row flagged gone',   (function()
        for _, x in ipairs(r.refs) do if x.item == 'Staff' then return x.gone; end end
    end)(), true);
    check('MG12 multi-gate row NOT flagged gone', (function()
        for _, x in ipairs(r.refs) do if x.item == 'Club' then return x.gone; end end
    end)(), false);
    check('MG13 preview names the set',  r.refs[1].set, 'TP');
    check('MG14 preview names the slot', r.refs[1].slot, 'Main');

    -- strip = true: the sole-gate row is REMOVED, the multi-gate row is TRIMMED,
    -- and the bare `mode = 'Weapon'` gate survives untouched (the ADR's rule).
    w = mkWorking();
    r = ml.gateRefsInSet('TP', w, 'Weapon:Caster', true);
    check('MG15 strip reports changed', r.changed, true);
    check('MG16 one row removed',       #w.Main, 3);
    check('MG17 remaining names', (function()
        local n = {}; for _, it in ipairs(w.Main) do n[#n + 1] = it.rec.Name; end
        return table.concat(n, ',');
    end)(), 'Club,Bare,Plain');
    check('MG18 multi-gate row trimmed to its survivor', (function()
        for _, it in ipairs(w.Main) do if it.rec.Name == 'Club' then return it.mode; end end
    end)(), 'DT');
    check('MG19 bare mode gate untouched', (function()
        for _, it in ipairs(w.Main) do if it.rec.Name == 'Bare' then return it.mode; end end
    end)(), 'Weapon');
    check('MG20 ungated row untouched', (function()
        for _, it in ipairs(w.Main) do if it.rec.Name == 'Plain' then return it.mode; end end
    end)(), nil);

    -- targeting the WHOLE mode takes the bare gate too (that is the delete path,
    -- not the cascade -- the cascade always passes Name:Value)
    w = mkWorking();
    r = ml.gateRefsInSet('TP', w, 'Weapon', true);
    check('MG21 whole-mode target hits all three gated rows', #r.refs, 3);
    -- NOT one survivor: the multi-gate row keeps its OTHER gate (DT) and stays. Only
    -- rows whose every gate died are removed -- losing a gate is not losing the piece.
    check('MG22 rows keeping another gate survive', #w.Main, 2);
    check('MG22a ...and it is the trimmed one plus the ungated one', (function()
        local n = {}; for _, it in ipairs(w.Main) do n[#n + 1] = it.rec.Name; end
        return table.concat(n, ',');
    end)(), 'Club,Plain');
    check('MG22b the survivor kept its other gate', (function()
        for _, it in ipairs(w.Main) do if it.rec.Name == 'Club' then return it.mode; end end
    end)(), 'DT');

    -- a target nothing matches must not report or change anything
    w = mkWorking();
    r = ml.gateRefsInSet('TP', w, 'Weapon:Nonexistent', true);
    check('MG23 unmatched target finds nothing', #r.refs, 0);
    check('MG24 unmatched target changes nothing', r.changed, false);
    check('MG25 unmatched target keeps every row', #w.Main, 4);
    check('MG26 nil working table is safe', #ml.gateRefsInSet('TP', nil, 'X', true).refs, 0);
end)();

-- ---------------------------------------------------------------------------
-- SET. menuui -- the header Menu + Settings pure cores (2026-07-24).
-- Own function scope: a do-block's locals share the chunk's 200 budget.
-- ---------------------------------------------------------------------------
;(function()
    local mn = dofile('ui/menuui.lua');
    check('SET1 module loads headless', type(mn), 'table');

    -- The 3-value open setting. Anything unrecognised must read as 'never' --
    -- uiflags.lua is a plain Lua file a player may hand-edit, and the surprising
    -- failure mode is a window that pops up uninvited.
    check('SET2 never normalizes',        mn._normalizeOpenMode('never'), 'never');
    check('SET3 login normalizes',        mn._normalizeOpenMode('login'), 'login');
    check('SET4 job normalizes',          mn._normalizeOpenMode('job'),   'job');
    check('SET5 case-insensitive',        mn._normalizeOpenMode('LOGIN'), 'login');
    check('SET6 nil -> never',            mn._normalizeOpenMode(nil),     'never');
    check('SET7 garbage -> never',        mn._normalizeOpenMode('yes please'), 'never');
    check('SET8 number -> never',         mn._normalizeOpenMode(3),       'never');
    check('SET9 true -> never',           mn._normalizeOpenMode(true),    'never');

    -- Auto-open. 'never' never fires; nothing fires before a real job exists
    -- (job nil/0 = not logged in); 'login' fires exactly once per session;
    -- 'job' fires again only when the job actually CHANGES, so a manual close
    -- is never fought frame after frame.
    check('SET10 never mode never opens',      mn._shouldAutoOpen('never', 5, nil, false), false);
    check('SET11 no job yet -> hold',          mn._shouldAutoOpen('login', nil, nil, false), false);
    check('SET12 job 0 -> hold',               mn._shouldAutoOpen('login', 0, nil, false),   false);
    check('SET13 login fires once',            mn._shouldAutoOpen('login', 5, nil, false),   true);
    check('SET14 login does not re-fire',      mn._shouldAutoOpen('login', 5, 5, true),      false);
    check('SET15 login ignores a job change',  mn._shouldAutoOpen('login', 7, 5, true),      false);
    check('SET16 job mode fires at login',     mn._shouldAutoOpen('job', 5, nil, false),     true);
    check('SET17 job mode re-fires on change', mn._shouldAutoOpen('job', 7, 5, true),        true);
    check('SET18 job mode holds on same job',  mn._shouldAutoOpen('job', 5, 5, true),        false);
    check('SET19 garbage mode never opens',    mn._shouldAutoOpen('sometimes', 5, nil, false), false);

    -- The typed level override. nil = "not a number, do nothing", so a half-typed
    -- box never commits; 0 = back to live; everything else clamps into 1..75.
    check('SET20 plain number',        mn._parseLevel('37'),   37);
    check('SET21 whitespace tolerated',mn._parseLevel('  60 '),60);
    check('SET22 clamps above 75',     mn._parseLevel('120'),  75);
    check('SET23 zero = back to live', mn._parseLevel('0'),    0);
    check('SET24 negative = live',     mn._parseLevel('-4'),   0);
    check('SET25 empty -> nil',        mn._parseLevel(''),     nil);
    check('SET26 nil -> nil',          mn._parseLevel(nil),    nil);
    check('SET27 letters -> nil',      mn._parseLevel('abc'),  nil);
    check('SET28 partial -> nil',      mn._parseLevel('7x'),   nil);
    check('SET29 decimal -> nil',      mn._parseLevel('37.5'), nil);
    check('SET30 lower bound kept',    mn._parseLevel('1'),    1);
    check('SET31 upper bound kept',    mn._parseLevel('75'),   75);

    -- The row roster: order is stable, and the developer quartet exists ONLY
    -- under /dl debug on.
    local plain = mn._menuRows(false);
    local dbg   = mn._menuRows(true);
    check('SET32 six rows when not debugging', #plain, 6);
    check('SET33 first row is lockstyle',      plain[1], 'lockstyle');
    check('SET34 settings is the last plain row', plain[#plain], 'settings');
    check('SET35 debug adds exactly four',     #dbg - #plain, 4);
    check('SET36 augs only under debug',       dbg[#dbg], 'augs');
    check('SET37 no augs row when not debugging',
        (function() for _, k in ipairs(plain) do if k == 'augs' then return true; end end return false; end)(), false);

    -- The icon column is reserved whether or not a PNG exists -- that is what lets
    -- Henrik drop art in later without shifting the layout.
    check('SET38 icon column width exported', type(mn._ICON_W), 'number');
    check('SET39 label x clears the icon',    mn._LABEL_X > mn._ICON_W, true);
    -- The layout invariant: the label column must clear the icon GUTTER, not merely
    -- the icon width. Bump _ICON_W on its own and labels print over the art -- which
    -- is exactly what nearly happened growing the icons from 16 to 24.
    check('SET51 label clears the whole icon gutter',
        mn._LABEL_X >= mn._ICON_GAP + mn._ICON_W, true);
    -- The taller row needs a taller HIT AREA, or the bottom of every row goes dead.
    check('SET52 row height covers the icon', mn._ROW_H >= mn._ICON_W, true);
    -- The header button's declared width must actually fit its icon: gearui
    -- right-aligns the header by summing b.w, so a lying width shifts the whole row.
    check('SET53 header button width fits its icon',
        mn._MENU_BTN_W > mn._MENU_ICON_W, true);
    -- Henrik's call: the entry-point button wears the art at the SAME size the rows
    -- do, so it reads identically in both places. Pinned so a later row-icon bump
    -- does not silently leave the header behind.
    check('SET54 header icon matches the row icon size', mn._MENU_ICON_W, mn._ICON_W);

    -- activate() is inert until configure() runs: no deps, no action, no crash.
    check('SET40 activate inert unconfigured', mn.activate('lockstyle'), false);
    check('SET41 unknown key refused',         mn.activate('nonsense'),  false);

    -- Every row icon must exist as assets\<name>.png. filetex returns nil for a
    -- missing file and the row just draws a blank cell of the right width -- correct
    -- behaviour, but it means a typo or a rename is INVISIBLE in game. Pin it here.
    -- Six row icons + the header button + the Developer section heading.
    local icons = mn._menuIcons();
    check('SET42 every icon slot is named', #icons, 8);
    local missing = {};
    for _, name in ipairs(icons) do
        local f = io.open('assets/' .. name .. '.png', 'rb');
        if f == nil then missing[#missing + 1] = name; else f:close(); end
    end
    check('SET43 every row icon exists on disk', table.concat(missing, ','), '');
    -- The floating Teleports button shares the Menu row's art (Henrik: "replace the
    -- ring floating icon with this as well"), so it is the same one file.
    check('SET44 teleports art is the shared one', (function()
        for _, n in ipairs(icons) do if n == 'teleports' then return true; end end
        return false;
    end)(), true);
    -- The header button and the Developer heading are covered by the same guard --
    -- they are the two icons that are NOT row icons, so they are the easiest to
    -- forget when the roster changes.
    check('SET45 header button icon is guarded', (function()
        for _, n in ipairs(icons) do if n == mn._MENU_ICON then return true; end end
        return false;
    end)(), true);
    check('SET46 developer heading icon is guarded', (function()
        for _, n in ipairs(icons) do if n == mn._DEBUG_ICON then return true; end end
        return false;
    end)(), true);

    -- headerButton adapts to whether the art loaded. Headless, filetex has no
    -- texture, so it MUST fall back to the labelled wide text button -- a failed
    -- texture load must never leave a mystery 26px square.
    local hb = mn.headerButton();
    check('SET47 no art -> labelled text button', hb.l, 'Menu');
    check('SET48 no art -> the wide width', hb.w, mn._MENU_W);
    check('SET49 no art -> declarative (no render fn)', hb.render, nil);
    check('SET50 fallback still carries the tooltip', type(hb.tip), 'string');

    -- SET55-58: the Teleports popup's QUICK WINDOW rows (Henrik, 2026-07-26 --
    -- Hobby bar + Lockstyle, replacing the Automations/HELM/Fishing cascades).
    -- Each row hands its key to menuui.activate and asks filetex for assets\<key>.png,
    -- and BOTH lookups fail SILENTLY: a renamed row key makes the row a no-op, a
    -- renamed asset makes it a blank cell. Neither is visible from a load test, so
    -- the source is parsed and both halves pinned here.
    local gsrc = nil;
    do
        local f = io.open('ui/gearui.lua', 'r');
        if f ~= nil then gsrc = f:read('*a'); f:close(); end
    end
    check('SET55 gearui is readable', gsrc ~= nil, true);
    local qkeys = {};
    for k in tostring(gsrc or ''):gmatch("renderQuickWindowRow%('([%w_]+)'") do
        qkeys[#qkeys + 1] = k;
    end
    check('SET56 two quick-window rows', table.concat(qkeys, ','), 'hobbybar,lockstyle');
    local known, badKey, badArt = {}, {}, {};
    for _, k in ipairs(mn._menuRows(true)) do known[k] = true; end
    for _, k in ipairs(qkeys) do
        if not known[k] then badKey[#badKey + 1] = k; end
        local f = io.open('assets/' .. k .. '.png', 'rb');
        if f == nil then badArt[#badArt + 1] = k; else f:close(); end
    end
    check('SET57 every quick row is a real Menu row key', table.concat(badKey, ','), '');
    check('SET58 every quick row has its art on disk',    table.concat(badArt, ','), '');
end)();

-- ---------------------------------------------------------------------------
-- UIF. gear/syncflags -- the uiflags.lua round-trip. This file had NO behavioural
-- test before 2026-07-24: a dropped key would have shipped silently.
-- ---------------------------------------------------------------------------
;(function()
    package.loaded['dlac\\lib\\cmdqueue'] = { enqueue = function() end, frame = function() return 0; end };
    local sf = dofile('gear/syncflags.lua');
    check('UIF1 module loads headless', type(sf), 'table');

    local wrote = {};
    local ui = { showAll = { false }, _openMode = 'job', _tgMon = true, _gfScale = 1.25 };
    sf.configure({
        dataDir = function() return 'X:\\char\\dlac\\'; end,
        charBase = function() return 'X:\\char\\'; end,
        writeFileText = function(p, t) wrote.path, wrote.text = p, t; return true; end,
        refreshGear = function() end,
        ui = ui,
    });
    sf.flags.debug, sf.flags.autosync, sf.flags.viewids = true, false, true;
    sf.saveUiFlags();
    check('UIF2 wrote to the mode-aware home', wrote.path, 'X:\\char\\dlac\\uiflags.lua');
    check('UIF3 emitted text parses', (function()
        local f = (loadstring or load)(wrote.text); return f ~= nil;
    end)(), true);

    local t = (loadstring or load)(wrote.text)();
    check('UIF4 debug round-trips',    t.debug,    true);
    check('UIF5 autosync round-trips', t.autosync, false);
    check('UIF6 viewids round-trips',  t.viewids,  true);
    check('UIF7 openui round-trips',   t.openui,   'job');
    check('UIF8 openui is a STRING',   type(t.openui), 'string');
    check('UIF9 showall round-trips',  t.showall,  false);
    check('UIF10 tgmon round-trips',   t.tgmon,    true);
    check('UIF11 gfscale round-trips', t.gfscale,  1.25);

    -- A hand-edited openui must not be able to inject Lua: %q quotes and escapes it.
    ui._openMode = 'ne"ver\nrm -rf';
    sf.saveUiFlags();
    check('UIF12 hostile openui still parses', (function()
        local f = (loadstring or load)(wrote.text); return f ~= nil;
    end)(), true);
    check('UIF13 hostile openui reads back verbatim',
        ((loadstring or load)(wrote.text)()).openui, 'ne"ver\nrm -rf');
    check('UIF14 ...and menuui normalizes it away',
        dofile('ui/menuui.lua')._normalizeOpenMode(((loadstring or load)(wrote.text)()).openui), 'never');

    -- The reader. loadUiFlags is a one-shot latch, so this needs a FRESH instance
    -- (dofile returns one) with _G.loadfile stubbed to hand back our table.
    local sf2 = dofile('gear/syncflags.lua');
    local ui2 = { showAll = { false } };
    local realLoadfile = loadfile;
    _G.loadfile = function() return function()
        return { debug = false, autosync = true, viewids = false,
                 openui = 'login', showall = true, gfscale = 2.0 };
    end; end
    sf2.configure({
        dataDir = function() return 'X:\\char\\dlac\\'; end,
        charBase = function() return 'X:\\char\\'; end,
        writeFileText = function() return true; end,
        refreshGear = function() end,
        ui = ui2,
    });
    sf2.loadUiFlags();
    _G.loadfile = realLoadfile;
    check('UIF15 openui loads',   ui2._openMode, 'login');
    check('UIF16 showall loads',  ui2.showAll[1], true);
    check('UIF17 autosync loads', sf2.flags.autosync, true);
    check('UIF18 viewids loads',  sf2.flags.viewids,  false);

    -- Absent keys keep their defaults -- an old uiflags.lua written before this
    -- slice must not start opening windows or flipping Show all.
    local sf3 = dofile('gear/syncflags.lua');
    local ui3 = { showAll = { false } };
    _G.loadfile = function() return function() return { debug = true }; end; end
    sf3.configure({
        dataDir = function() return 'X:\\char\\dlac\\'; end,
        charBase = function() return 'X:\\char\\'; end,
        writeFileText = function() return true; end,
        refreshGear = function() end,
        ui = ui3,
    });
    sf3.loadUiFlags();
    _G.loadfile = realLoadfile;
    check('UIF19 absent openui stays nil',  ui3._openMode, nil);
    check('UIF20 ...which normalizes to never',
        dofile('ui/menuui.lua')._normalizeOpenMode(ui3._openMode), 'never');
    check('UIF21 absent showall stays off', ui3.showAll[1], false);

    package.loaded['dlac\\lib\\cmdqueue'] = nil;
end)();

-- ---------------------------------------------------------------------------
-- LS. THE LOCKED SET (ADR 0022) -- `/dl lock set ...` as a frozen Claim.
--
-- Four commands that differ ONLY in which slots they freeze. That difference is
-- invisible to a source pin and costs four Incursion runs to check by hand, so
-- it is pinned here through the pure builder, and end-to-end through the real
-- M.dispatch below (the NK26 pattern -- the wiring BETWEEN the seams is what
-- has no other coverage).
-- ---------------------------------------------------------------------------
(function()
    local D = dispatchM;
    local B = D.buildLockedClaim;

    -- the injected seams: no Ashita, no bags, no game
    local WORN = { Main = 'Worn Sword', Head = 'Worn Hat', Ammo = nil, Ring1 = 'Worn Ring' };
    local function wornOf(slot) return WORN[slot]; end
    local BAGS = { ['set sword'] = 1, ['set hat'] = 1, ['worn sword'] = 1,
                   ['worn hat'] = 1, ['worn ring'] = 1, ['karin obi'] = 1 };
    local function locate(entry)
        local nm = D._setEntryName(entry);
        if nm == nil then return false, nil; end
        if BAGS[string.lower(nm)] then return true, nil; end
        if string.lower(nm) == 'parked hat' then return false, 'Mog Satchel'; end
        return false, nil;                      -- nowhere this character can see
    end
    local function resolve(v)                   -- the dlac: marker collapser
        local nm = string.lower(D._setEntryName(v) or '');
        if nm == 'dlac:autoobi' then return 'Karin Obi'; end
        return nil;                             -- everything else: no answer today
    end
    local function count(t) local n = 0; for _ in pairs(t) do n = n + 1; end return n; end

    -- LS1. the four words are DATA -- the command branch, the /dl lock help and
    -- these checks all read one table, so a fifth variant cannot drift.
    check('LS1 four lock-set words, in help order',
        table.concat(D._lockSetOrder, ','), 'set,set-loose,set-snapshot,set-current');
    check('LS1b strict fills unnamed slots with remove', D._lockSetModes['set'].fill, 'remove');
    check('LS1c loose fills nothing',                    D._lockSetModes['set-loose'].fill, nil);
    check('LS1d snapshot fills from what is worn',       D._lockSetModes['set-snapshot'].fill, 'worn');
    check('LS1e set-current is the only one needing no name',
        D._lockSetModes['set-current'].needsName, false);

    local SET = { Main = 'Set Sword', Head = 'Set Hat' };

    -- LS2. STRICT: "hard reserve EVERYTHING, even empty slots" (Henrik).
    local c2, m2, n2 = B(SET, 'remove', resolve, locate, wornOf);
    check('LS2 strict claims all 16 slots',        n2, 16);
    check('LS2b ...the set is what it names',      c2.Main, 'Set Sword');
    check('LS2c ...and every other slot is EMPTIED', c2.Ammo, 'remove');
    check('LS2d ...nothing is reported missing',   #m2, 0);
    -- The NK3 lesson, on a new producer: a lowercase key is dropped by the
    -- native engine's SLOT_ID map, so it would work in LAC and hold NOTHING
    -- natively -- the divergence that ships broken in the mode people run.
    check('LS2e keys are PROPER case',             c2.main, nil);

    -- LS3. LOOSE: "reserve ONLY the slots that have anything on them, the rest
    -- gets free use for any other claimants."
    local c3, m3, n3 = B(SET, nil, resolve, locate, wornOf);
    check('LS3 loose claims only the named slots', n3, 2);
    check('LS3b ...and leaves the rest available', c3.Ammo, nil);
    check('LS3c ...still holding what it named',   c3.Head, 'Set Hat');
    check('LS3d ...with nothing missing',          #m3, 0);

    -- LS4. SNAPSHOT: the set, plus what is worn everywhere else.
    local c4, _, n4 = B(SET, 'worn', resolve, locate, wornOf);
    check('LS4 snapshot claims all 16',            n4, 16);
    check('LS4b the set still wins its own slots', c4.Main, 'Set Sword');
    check('LS4c an unnamed slot takes what is worn', c4.Ring1, 'Worn Ring');
    check('LS4d an unnamed EMPTY slot is held empty', c4.Ammo, 'remove');

    -- LS5. set-current: no set at all, every slot from what is worn, strictly.
    local c5, m5, n5 = B(nil, 'worn', resolve, locate, wornOf);
    check('LS5 set-current claims all 16',         n5, 16);
    check('LS5b ...from what is worn',             c5.Head, 'Worn Hat');
    check('LS5c ...empty stays empty',             c5.Ammo, 'remove');
    check('LS5d ...and it can never report a miss', #m5, 0);

    -- LS6. sets are authored in any case; the claim is not.
    local c6 = B({ main = 'Set Sword', HEAD = 'Set Hat' }, nil, resolve, locate, wornOf);
    check('LS6 a lowercase set key is matched',    c6.Main, 'Set Sword');
    check('LS6b ...and an uppercase one',          c6.Head, 'Set Hat');

    -- LS7. dlac: markers are COLLAPSED at arm -- the reason a locked obi cannot
    -- follow the weather any more (Henrik: "Once you lock, it shall be constant").
    local c7 = B({ Waist = 'dlac:AutoObi' }, nil, resolve, locate, wornOf);
    check('LS7 a virtual is frozen to its answer', c7.Waist, 'Karin Obi');

    -- LS8. a marker with NO answer right now: the slot goes loose, and the
    -- marker is named rather than silently dropped.
    local c8, m8 = B({ Main = 'dlac:AutoStaff' }, 'remove', resolve, locate, wornOf);
    check('LS8 an unresolvable marker is not held', c8.Main, nil);
    check('LS8b ...it is reported',                 #m8, 1);
    check('LS8c ...by marker name',                 m8[1] and m8[1].item, 'dlac:AutoStaff');
    check('LS8d ...and strict does NOT empty it instead', c8.Main, nil);

    -- LS9. THE INCURSION CASE: a named piece that is not on you. The slot goes
    -- LOOSE (available), and we say where the gear actually is.
    local c9, m9, n9 = B({ Main = 'Set Sword', Head = 'Parked Hat', Body = 'Gone Forever' },
                         'remove', resolve, locate, wornOf);
    check('LS9 the piece we have is held',          c9.Main, 'Set Sword');
    check('LS9b a parked piece is NOT held',        c9.Head, nil);
    check('LS9c ...and is not emptied either -- it is LOOSE', c9.Head, nil);
    check('LS9d two pieces are reported',           #m9, 2);
    check('LS9e ...one located',                    m9[1] and m9[1].where, 'Mog Satchel');
    check('LS9f ...one nowhere to be found',        m9[2] and m9[2].where, nil);
    check('LS9g and the other 13 slots still emptied strictly', n9, 14);

    -- LS10. 'remove' and 'displaced' are equip LITERALS, not item names: they
    -- can never be missing from your bags, so they skip the locate check.
    local c10, m10 = B({ Ammo = 'remove', Range = 'displaced' }, nil, resolve, locate, wornOf);
    check('LS10 a remove entry is held as written', c10.Ammo, 'remove');
    check('LS10b displaced too',                    c10.Range, 'displaced');
    check('LS10c neither counts as missing',        #m10, 0);

    -- LS11. 'ignore' is the set author saying "not mine": leave the slot alone,
    -- and do NOT report it -- nothing is missing.
    local c11, m11 = B({ Ammo = 'ignore' }, nil, resolve, locate, wornOf);
    check('LS11 an ignore entry is not claimed',    c11.Ammo, nil);
    check('LS11b ...and is not reported missing',   #m11, 0);

    -- LS12. an entry TABLE (augment / Bag spec) survives whole -- freezing to a
    -- bare name would let planSet pick the wrong copy of a ring you own twice.
    local aug = { Name = 'Set Sword', Augment = { 'Attack+5' } };
    local c12 = B({ Main = aug }, nil, resolve, locate, wornOf);
    check('LS12 an augment spec is frozen intact',  c12.Main, aug);

    -- LS13. the stored record + its accessors
    local savedLocked = D.lockedSet;
    check('LS13 nothing locked to begin with',      D.lockedSetOn(), false);
    check('LS13b ...so there is no claim',          D.lockedSetClaim(), nil);
    check('LS13c ...and no label',                  D.lockedSetLabel(), nil);
    D.setLockedSet({ name = 'Incursion T3', mode = 'set', claim = { Head = 'Set Hat' }, n = 1 });
    check('LS13d armed',                            D.lockedSetOn(), true);
    check('LS13e ...labelled by set name',          D.lockedSetLabel(), 'Incursion T3');
    local claimA = D.lockedSetClaim();
    claimA.Head = 'TAMPERED';
    check('LS13f the claim is a COPY -- the apply path cannot reach the frozen one',
        D.lockedSetClaim().Head, 'Set Hat');
    D.setLockedSet({ name = nil, mode = 'set-current', claim = { Head = 'Worn Hat' }, n = 1 });
    check('LS13g set-current has no set name, so it says what it is',
        D.lockedSetLabel(), 'your gear as it was');
    check('LS13h releasing hands back the label',   D.clearLockedSet(), 'your gear as it was');
    check('LS13i ...and it is gone',                D.lockedSetOn(), false);
    check('LS13j releasing nothing returns nothing', D.clearLockedSet(), nil);

    -- LS14. LIFETIME -- it shares nakedWorldWatch (ADR 0022). Logging in locked
    -- to last night's set is the relog failure ADR 0021 calls the worst outcome,
    -- wearing different clothes: a naked player knows instantly, a locked one
    -- just finds their gear mysteriously stuck.
    local savedNaked = D.nakedArmed;
    D.nakedArmed = false;
    D.setLockedSet({ name = 'Incursion T3', mode = 'set', claim = { Head = 'Set Hat' }, n = 1 });
    check('LS14 same job, in the world -> stays locked', D.nakedWorldWatch(7, 7), nil);
    check('LS14b ...and it is still armed',              D.lockedSetOn(), true);
    local why14, drop14 = D.nakedWorldWatch(0, 7);
    check('LS14c character select releases it',          why14, 'world');
    check('LS14d ...and it is gone',                     D.lockedSetOn(), false);
    check('LS14e ...the caller is told what dropped',    drop14 and drop14.locked, 'Incursion T3');
    check('LS14f ...and that naked was not part of it',  drop14 and drop14.naked, false);
    D.setLockedSet({ name = 'Incursion T3', mode = 'set', claim = { Head = 'Set Hat' }, n = 1 });
    local why14b, drop14b = D.nakedWorldWatch(3, 7);
    check('LS14g a JOB CHANGE releases it too',          why14b, 'job');
    check('LS14h ...naming it, because someone is there to read the line',
        drop14b and drop14b.locked, 'Incursion T3');
    -- both can drop in one pass, and the watch only ever CLEARS
    D.setLockedSet({ name = 'Incursion T3', mode = 'set', claim = { Head = 'Set Hat' }, n = 1 });
    D.nakedArmed = true;
    local _, drop14c = D.nakedWorldWatch(0, 7);
    check('LS14i both drop together',
        (drop14c and drop14c.naked == true and drop14c.locked == 'Incursion T3'), true);
    check('LS14j ...and neither is re-armed', D.nakedOn() == false and D.lockedSetOn() == false, true);
    -- LS14k. SLOT LOCKS SHARE IT TOO (v124, Henrik: "I don't want locks to
    -- outlive a relog, it should not outlive a main job change nor a log").
    -- Nothing used to watch them, so they rode straight through character select
    -- -- an Ashita addon survives a logout. Before v123 the engine self-swap
    -- happened to wipe them, which looked like a lifetime rule and was really a
    -- bug; removing that accident left the real gap visible.
    D.nakedArmed = false;
    D.lockedSet  = nil;
    D.locks['head'], D.locks['ammo'] = true, true;
    check('LS14k a lock alone is enough to arm the watch', D.worldWatch(7, 7), nil);
    check('LS14l ...and it survives standing still',       D.locks['head'], true);
    local why14d, drop14d = D.worldWatch(3, 7);
    check('LS14m a JOB CHANGE releases slot locks',        why14d, 'job');
    check('LS14n ...all of them',                          next(D.locks), nil);
    check('LS14o ...counted for the chat line',            drop14d and drop14d.locks, 2);
    D.locks['head'] = true;
    check('LS14p leaving the world releases them too',     D.worldWatch(0, 7), 'world');
    check('LS14q ...leaving nothing behind',               next(D.locks), nil);
    -- ...and with nothing held at all the watch stays silent, so the tick does
    -- not write the mirror on every frame of character select.
    check('LS14r nothing held -> the watch does nothing',  D.worldWatch(0, 7), nil);
    check('LS14s the pre-v124 name is the same function',
        rawequal(D.nakedWorldWatch, D.worldWatch), true);

    D.nakedArmed = savedNaked;
    D.lockedSet  = savedLocked;

    -- LS15. PRECEDENCE, from the one authority. The locked set rides the EXISTING
    -- Locks row, so "a locked slot moves for Naked and Pins, nothing else" is a
    -- statement about the default rank order -- not about new code.
    local def = D._arbDefaultOrder;
    local rank = {};
    for i, n in ipairs(def) do rank[n] = i; end
    check('LS15 Naked outranks a lock', rank['Naked'] < rank['Locks'], true);
    check('LS15b Pins outrank a lock (on demand, universally understood)',
        rank['Pins'] < rank['Locks'], true);
    check('LS15c no CLAIMANT else does', (function()
        for _, n in ipairs(def) do
            if n == 'Locks' then return true; end
            -- Disabled (ADR 0024) is above Locks and always will be: it is the
            -- CEILING, not a claimant -- it dresses nothing and cannot be dragged.
            -- The law this pins is about claimants, so it is named, not counted.
            if n ~= 'Naked' and n ~= 'Pins' and n ~= 'Disabled' then return n; end
        end
        return 'Locks row missing';
    end)(), true);
    check('LS15d no new CLAIMANT row was added (11 = the 10 ranked rows + the ADR 0024 ceiling)',
        #def, 11);

    -- LS16. END TO END through the REAL M.dispatch (the NK26 pattern). A locked
    -- set with NOTHING else armed -- no triggers, no pins, no hobby, no ammo --
    -- must still reach the equip door, which is the path BOTH bail guards have to
    -- let through. This is the check that would have caught the original bug.
    local savedPlayer, savedFunc, savedState = TEST_PLAYER, rawget(_G, 'gFunc'), rawget(_G, 'gState');
    TEST_PLAYER = { MainJob = 'WHM', MainJobLevel = 75, SubJob = 'BLM', SubJobLevel = 37,
                    MainJobSync = 75, SubJobSync = 37, Status = 'Idle', IsMoving = false };
    local wrote = {};
    _G.gFunc  = { EquipSet = function(t) for k, v in pairs(t or {}) do wrote[k] = v; end end };
    _G.gState = { CurrentCall = 'N/A', Disabled = {} };

    local strictClaim = B({ Main = 'Set Sword', Head = 'Set Hat' }, 'remove', resolve, locate, wornOf);
    D.setLockedSet({ name = 'Incursion T3', mode = 'set', claim = strictClaim, n = 16 });
    local okD, errD = pcall(D.dispatch, 'Default');
    check('LS16 a bare Default with only a locked set does not throw', okD, true);
    if not okD then print('LS16 error: ' .. tostring(errD)); end
    check('LS16b it reaches the equip door with all 16 slots', count(wrote), 16);
    check('LS16c the set holds its own slots',                 wrote.Main, 'Set Sword');
    check('LS16d ...and strict empties the rest',              wrote.Ammo, 'remove');

    -- LS17. A plain slot lock can never sabotage the hold. layerRespectsLocks
    -- asks `rank > lockRank` about the Locks row ITSELF, which is false -- so the
    -- hold punches through M.locks. That is exactly why arming no longer has to
    -- destroy the player's own locks first (ADR 0021 listed doing so as a defect).
    wrote = {};
    D.locks['head'] = true;
    pcall(D.dispatch, 'Default');
    check('LS17 a stale lock does not strip the slot out of the hold', wrote.Head, 'Set Hat');
    check('LS17b ...and the player keeps their lock',                  D.locks['head'], true);
    D.locks['head'] = nil;

    -- LS18. LOOSE really is available: the slots the hold left alone are simply
    -- not written by this layer.
    wrote = {};
    local looseClaim = B({ Main = 'Set Sword', Head = 'Set Hat' }, nil, resolve, locate, wornOf);
    D.setLockedSet({ name = 'Incursion T3', mode = 'set-loose', claim = looseClaim, n = 2 });
    pcall(D.dispatch, 'Default');
    check('LS18 loose writes only the slots it holds', count(wrote), 2);
    check('LS18b ...and nothing lands in the rest',    wrote.Ammo, nil);

    -- LS19. NAKED OUTRANKS IT (Henrik: "Naked means naked, whatever everyone
    -- else thinks"). The hold genuinely tries and the Arbiter genuinely blocks
    -- it -- Locks applies first, Naked overwrites all 16 -- so releasing the
    -- strip hands the slots straight back on the next pass.
    wrote = {};
    D.nakedArmed = true;
    pcall(D.dispatch, 'Default');
    check('LS19 naked beats the locked set in every slot', count(wrote), 16);
    check('LS19b ...including one the hold named',         wrote.Main, 'remove');
    D.nakedArmed = false;
    wrote = {};
    pcall(D.dispatch, 'Default');
    check('LS19c dressed again, the hold takes its slots back', wrote.Main, 'Set Sword');

    D.setLockedSet(nil);
    wrote = {};
    pcall(D.dispatch, 'Default');
    check('LS20 released, a bare dispatch writes nothing at all', next(wrote), nil);

    -- -----------------------------------------------------------------------
    -- DS. FREE EQUIP -- the DISABLED CEILING (ADR 0024), end to end through the
    --     REAL M.dispatch on the harness LS16 built. These are the checks that
    --     matter: everything else about this feature is a chat line.
    --
    --     The point of doing it here rather than at a pure seam is that the
    --     ceiling is enforced at engineEquipSet, BELOW equipResolved and below
    --     every whole-table post-pass -- so only a real dispatch can show that a
    --     disabled slot produces no write no matter who claimed it.
    -- -----------------------------------------------------------------------
    D.setLockedSet({ name = 'Incursion T3', mode = 'set', claim = strictClaim, n = 16 });

    wrote = {};
    D.setDisabled('main', true);
    pcall(D.dispatch, 'Default');
    check('DS1 a disabled slot is not written at all',   wrote.Main, nil);
    check('DS1b ...and the other 15 still are',          count(wrote), 15);
    check('DS1c ...specifically the ones the hold named', wrote.Head, 'Set Hat');

    -- THE ONE THAT MATTERS: the ceiling outranks the strip. A lock cannot do
    -- this -- Naked ranks above Locks and punches straight through it.
    wrote = {};
    D.nakedArmed = true;
    pcall(D.dispatch, 'Default');
    check('DS2 NAKED cannot strip a disabled slot',      wrote.Main, nil);
    check('DS2b ...and still strips every other one',    wrote.Head, 'remove');
    D.nakedArmed = false;

    wrote = {};
    D.setDisabled('all', true);
    pcall(D.dispatch, 'Default');
    check('DS3 all 16 disabled -> dlac writes nothing whatsoever', next(wrote), nil);

    wrote = {};
    D.setDisabled('all', false);
    pcall(D.dispatch, 'Default');
    check('DS4 re-enabled, the very next pass dresses them again', count(wrote), 16);
    check('DS4b ...with the held set back in Main',      wrote.Main, 'Set Sword');

    -- setDisabled's vocabulary, shaped exactly like setLock's.
    check('DS5 an unknown slot name is nil, never a throw', D.setDisabled('nosuchslot', true), nil);
    check('DS5b ...and disables nothing',                D.disabledOn(), false);
    check('DS6 nil state toggles a single slot',         D.setDisabled('ammo'), true);
    check('DS6b ...and toggles it back',                 D.setDisabled('ammo'), false);
    check('DS6c disabledOn(slot) answers per slot', (function()
        D.setDisabled('ear1', true);
        local a, b = D.disabledOn('ear1'), D.disabledOn('ear2');
        D.setDisabled('ear1', false);
        return a == true and b == false;
    end)(), true);
    check('DS7 disabledList is in canonical LAC order, not hash order', (function()
        D.setDisabled('feet', true); D.setDisabled('main', true); D.setDisabled('head', true);
        local l = table.concat(D.disabledList(), ',');
        D.setDisabled('all', false);
        return l;
    end)(), 'main,head,feet');

    -- stripDisabled: the seam itself. Case-insensitive on purpose -- claims are
    -- canonical ('Main'), the command vocabulary is lac-case ('main'), and
    -- equipcore's SLOT_ID map is case-SENSITIVE, so a case-blind compare would
    -- work in one engine and silently miss in the other.
    D.setDisabled('main', true);
    local src = { Main = 'A', Head = 'B', main = 'C', __meta = 'keep' };
    local out = D._stripDisabled(src);
    check('DS8 the canonical key is stripped',           out.Main, nil);
    check('DS8b the lac-case key is stripped too',       out.main, nil);
    check('DS8c an unrelated slot survives',             out.Head, 'B');
    check('DS8d __ metadata is never treated as a slot', out.__meta, 'keep');
    check('DS8e the caller\'s table is not mutated',     src.Main, 'A');
    D.setDisabled('all', false);
    local same = { Main = 'A' };
    check('DS9 with nothing disabled the set passes through by IDENTITY',
        D._stripDisabled(same) == same, true);

    -- Attribution. The claim exists ONLY so /dl why and the panel can name it.
    check('DS10 no claim when nothing is disabled',      D.disabledClaim(), nil);
    D.setDisabled('head', true);
    local dzc = D.disabledClaim();
    check('DS10b the claim is keyed CANONICALLY',        dzc and dzc.Head, D.DISABLED_FREE);
    check('DS10c ...and claims only the disabled slots', (function()
        local n = 0; for _ in pairs(dzc or {}) do n = n + 1; end; return n;
    end)(), 1);
    local dzWhy = table.concat(D.arbWhyLines(
        { Disabled = dzc, Naked = D.nakedClaim() }, D.arbOrder(nil), {}), '\n');
    check('DS11 /dl why collapses the ceiling into ONE line',
        select(2, dzWhy:gsub('FREE EQUIP %(ceiling', '')), 1);
    check('DS11b ...naming the slot',                    dzWhy:find('Head', 1, true) ~= nil, true);
    check('DS11c ...and who it beat',                    dzWhy:find('over Naked', 1, true) ~= nil, true);
    -- Woven MaxMP cedes a disabled slot for free -- that is what registering the
    -- claim above the mpCeded computation buys.
    local dzCede = D.arbCededAbove({ Disabled = dzc }, D.arbOrder(nil), 'MaxMP');
    check('DS12 MaxMP cedes a disabled slot',            dzCede['head'], 'Disabled');
    D.setDisabled('all', false);

    -- LIFETIME (Henrik, 2026-07-26): the same watch as the strip, a locked set
    -- and slot locks. A job change or leaving the world releases it; nothing
    -- persists it. Standing on a new job with a slot silently not swapping, and
    -- nothing on screen to explain it, is the failure this closes.
    D.setDisabled('back', true);
    check('DS13 free equip alone is enough to arm the watch', D.worldWatch(7, 7), nil);
    local dzWhy2, dzDrop = D.worldWatch(1, 7);
    check('DS13b a main job change releases it',         dzWhy2, 'job');
    check('DS13c ...and reports how many slots',         dzDrop and dzDrop.disabled, 1);
    check('DS13d ...leaving nothing behind',             D.disabledOn(), false);
    D.setDisabled('waist', true);
    check('DS14 leaving the world releases it too',      (D.worldWatch(nil, 7)), 'world');
    check('DS14b ...and it is gone',                     D.disabledOn(), false);

    D.setLockedSet(nil);
    TEST_PLAYER = savedPlayer;
    _G.gFunc, _G.gState = savedFunc, savedState;
    D.nakedArmed = savedNaked;
    D.lockedSet  = savedLocked;
end)();

-- ---------------------------------------------------------------------------
-- CMD. THE /dl COMMAND SURFACE, DRIVEN FOR REAL (2026-07-26).
--
-- Until this section every /dl subcommand was tested by SEARCHING dispatch.lua
-- for its own name. NK23 records why: "dispatch's handler only registers inside
-- engineActive(), which is false headlessly, so the whitelist cannot be driven
-- -- pin it as SOURCE instead." A source pin proves a command is spelled right
-- and sits in the whitelist. It cannot see what the command DOES -- which is
-- exactly how `/dl lock set` shipped present, correctly spelled, whitelisted,
-- and INERT in native mode: its rawget(_G,'gEquip') bracket is nil in the addon
-- state, so the equip fell to the unbracketed path, landed in equipengine's
-- buffer, and the next fireEvent's bufferClear wiped it before it could send.
--
-- engineActive() is `inLac() or nativeEngine() ~= nil`, so the ADDON-state copy
-- of the engine -- inert since v1 -- becomes the LIVE one when the native flag
-- is on (the arming rule NEB1 pins). Arm it, re-load dispatch, and the real
-- command handler registers and is callable.
--
-- THIS LOADS A SECOND dispatch MODULE into a suite whose other checks hold a
-- reference to the first, so every shared thing it touches is saved and put
-- back: package.loaded (dispatch + chatfmt), gFunc/gState, profiles.nativeMode
-- and profiles.dataDir, ashita.events, equipengine's onEvent and tripwire.
-- dataDir is redirected to tests\ because the engineActive block runs
-- loadModeState/saveModeState AT LOAD -- unredirected, a plain test run would
-- write modestate.lua into a real character's folder.
--
-- chatfmt is stubbed BEFORE the load, never after: dispatch.lua:139 binds its
-- shadowed `print` once at load time, so a later _G.print override is not seen.
-- ---------------------------------------------------------------------------
(function()
    local SEP  = string.char(92);
    local prof = package.loaded['dlac\\profiles'];
    local eng  = package.loaded['dlac\\feature\\equipengine'];
    check('CMD0 profiles is loaded',     type(prof), 'table');
    check('CMD0b equipengine is loaded', type(eng),  'table');
    if type(prof) ~= 'table' or type(eng) ~= 'table' then return; end

    local saved = {
        nativeMode = prof.nativeMode,        dataDir = prof.dataDir,
        dispatch   = package.loaded['dlac\\dispatch'],
        chatfmt    = package.loaded['dlac\\chatfmt'],
        gFunc      = rawget(_G, 'gFunc'),    gState  = rawget(_G, 'gState'),
        reg        = ashita.events.register, unreg   = ashita.events.unregister,
        player     = TEST_PLAYER,
        onEvent    = eng.onEvent,            tripped = eng.state.tripped,
    };

    -- Captured chat. `said` is REASSIGNED per command and the stub closes over
    -- the variable rather than the table, so each run reads only its own lines.
    local said = {};
    local function capture(...)
        local parts = {};
        for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))); end
        said[#said + 1] = table.concat(parts, ' ');
    end
    package.loaded['dlac\\chatfmt'] = { print = capture, warn = capture, err = capture };

    -- Arm the native engine: addon state (no gFunc) + flag on + tripwire clear.
    prof.nativeMode = function() return true; end
    prof.dataDir    = function() return 'tests' .. SEP; end
    _G.gFunc, _G.gState = nil, nil;
    eng.state.tripped = false;

    local handlers = {};
    ashita.events.register   = function(ev, nm, fn) handlers[ev] = fn; end
    ashita.events.unregister = function() end
    local okLoad, D = pcall(dofile, 'dispatch.lua');
    ashita.events.register, ashita.events.unregister = saved.reg, saved.unreg;

    check('CMD1 dispatch re-loads with the native engine armed', okLoad, true);
    if not okLoad then print('CMD1 error: ' .. tostring(D)); end
    check('CMD2 ...and the command handler registers for real',
          okLoad and type(handlers['command']), 'function');
    check('CMD2b ...alongside the frame tick',
          okLoad and type(handlers['d3d_present']), 'function');

    if okLoad and type(handlers['command']) == 'function' then
        TEST_PLAYER = { MainJob = 'WHM', MainJobLevel = 75, SubJob = 'BLM', SubJobLevel = 37,
                        MainJobSync = 75, SubJobSync = 37, Status = 'Idle', IsMoving = false };

        -- One /dl line, driven exactly as Ashita delivers it: an event table
        -- whose `blocked` field the handler sets when it owns the command.
        local function run(line)
            said = {};
            local e = { command = line, blocked = false };
            local ok, err = pcall(handlers['command'], e);
            if not ok then said[#said + 1] = 'ERROR: ' .. tostring(err); end
            return e, ok;
        end
        local function saidHas(frag)
            for _, l in ipairs(said) do
                if string.find(l, frag, 1, true) ~= nil then return true; end
            end
            return false;
        end
        local function saidText() return table.concat(said, ' | '); end

        -- This is the fact the whole section rests on: the command answered
        -- with NO gFunc in the state, so it is the addon-side native engine
        -- replying, not LuaAshitacast's copy.
        check('CMD3 no gFunc present -- this is the addon-state engine',
              rawget(_G, 'gFunc'), nil);

        -- The whitelist, driven instead of grepped (the v46 trap NK23 pins as
        -- source): an unknown subcommand must fall through UNBLOCKED and silent,
        -- or it looks like the command does not exist.
        local e4 = run('/dl bogus');
        check('CMD4 an unknown subcommand is not blocked', e4.blocked, false);
        check('CMD4b ...and prints nothing',               #said, 0);

        local e5 = run('/dl lock');
        check('CMD5 /dl lock is owned (blocked)',   e5.blocked, true);
        check('CMD5b ...and reports the lock state', saidHas('locked slots:'), true);

        -- slot locks, round trip through the REAL command
        run('/dl lock head on');
        check('CMD6 /dl lock head on sets the lock', D.locks['head'], true);
        check('CMD6b ...and says so',                saidHas('lock head ON'), true);
        run('/dl lock head off');
        check('CMD6c /dl lock head off releases it', D.locks['head'], nil);
        run('/dl lock all on');
        local nAll = 0;
        for _ in pairs(D.locks) do nAll = nAll + 1; end
        check('CMD6d /dl lock all on locks all 16',  nAll, 16);
        run('/dl lock all off');
        check('CMD6e /dl lock all off clears them',  next(D.locks), nil);
        local e6 = run('/dl lock nosuchslot');
        check('CMD6f an unknown slot is named back', saidHas('unknown slot: nosuchslot'), true);
        check('CMD6g ...and still owns the command', e6.blocked, true);

        -- the strip (ADR 0021), through the command rather than the flag
        run('/dl naked');
        check('CMD7 /dl naked arms the strip',        D.nakedOn(), true);
        check('CMD7b ...and states the TP wipe once', saidHas('zeroes your TP'), true);
        run('/dl naked');
        check('CMD7c a second /dl naked never dresses you', D.nakedOn(), true);
        check('CMD7d ...it says you already are',     saidHas('already naked'), true);
        run('/dl dress');
        check('CMD7e /dl dress releases it',          D.nakedOn(), false);
        run('/dl naked');
        run('/dl naked off');
        check('CMD7f /dl naked off releases it too',  D.nakedOn(), false);

        -- /dl lock set: the name check, which must refuse BEFORE it touches
        -- anything (a failed name that had already cleared the locks would
        -- leave the player half-unlocked with nothing equipped).
        run('/dl lock head on');
        local e8 = run('/dl lock set NoSuchSetName');
        check('CMD8 /dl lock set owns the command',   e8.blocked, true);
        check('CMD8b an unknown set is refused by name',
              saidHas('no committed set named'), true);
        check('CMD8c ...and the refusal leaves existing locks alone',
              D.locks['head'], true);
        run('/dl lock all off');
        run('/dl lock set');
        check('CMD9 /dl lock set with no name prints usage',
              saidHas('usage: /dl lock set'), true);

        if not saidHas('usage: /dl lock set') then print('CMD9 said: ' .. saidText()); end

        -- THE LOCKED SET (ADR 0022), through the real commands. Headless there
        -- is no AshitaCore, so wornItemName answers nil for every slot and
        -- set-current freezes sixteen empties -- which is still the whole arm ->
        -- claim -> release path, and the only one that proves the four command
        -- words reach the builder at all.
        run('/dl lock set-current');
        check('CMD10 /dl lock set-current arms a hold', D.lockedSetOn(), true);
        check('CMD10b ...strictly, all 16 slots',       D.lockedSet.n, 16);
        check('CMD10c ...and says what it locked',      saidHas('LOCKED to'), true);
        check('CMD10d ...naming the release door',      saidHas('/dl lock set off'), true);

        -- The state readout + the four-variant help Henrik asked for by name.
        run('/dl lock');
        check('CMD11 /dl lock reports the held set',    saidHas('locked set:'), true);
        local allFour = true;
        for _, w in ipairs(D._lockSetOrder) do
            if not saidHas('/dl lock ' .. w) then allFour = false; end
        end
        check('CMD11b ...and lists every variant',      allFour, true);
        check('CMD11c ...with the slot-lock line too',  saidHas('/dl lock <slot|all>'), true);

        -- The narrow door.
        run('/dl lock set off');
        check('CMD12 /dl lock set off releases it',     D.lockedSetOn(), false);
        check('CMD12b ...and says which set it was',    saidHas('released'), true);
        run('/dl lock set off');
        check('CMD12c releasing nothing is not an error', saidHas('no set is locked'), true);

        -- COEXISTENCE (Henrik, 2026-07-26): arming must no longer destroy the
        -- player's own locks. Today's code cleared them because they would strip
        -- slots out of the one-shot equip; a claim outranks them instead, so the
        -- lock is merely outranked while held and is still there on release.
        run('/dl lock ammo on');
        run('/dl lock set-current');
        check('CMD13 arming a hold leaves plain locks alone', D.locks['ammo'], true);
        check('CMD13b ...and the hold is armed anyway',       D.lockedSetOn(), true);

        -- The universal door: "/dl lock all off" is one word to the player, so
        -- it lets go of everything that word covers -- and says so.
        run('/dl lock all off');
        check('CMD14 /dl lock all off clears the slot locks', next(D.locks), nil);
        check('CMD14b ...and releases the held set too',      D.lockedSetOn(), false);
        check('CMD14c ...saying it did',                      saidHas('released the locked set'), true);

        -- Every variant refuses an unknown set BY NAME, before touching state.
        run('/dl lock ring1 on');
        local e15 = run('/dl lock set-loose NoSuchSetName');
        check('CMD15 set-loose owns the command',        e15.blocked, true);
        check('CMD15b ...refuses an unknown name',       saidHas('no committed set named'), true);
        check('CMD15c ...arms nothing',                  D.lockedSetOn(), false);
        check('CMD15d ...and leaves existing locks alone', D.locks['ring1'], true);
        run('/dl lock snapshot');   -- not a word: falls through to the slot branch
        check('CMD15e a near-miss word is an unknown SLOT, not a silent no-op',
              saidHas('unknown slot: snapshot'), true);
        run('/dl lock all off');

        -- FREE EQUIP (ADR 0024), through the REAL command handler. The whitelist
        -- half is the v46 trap NK23 records: a subcommand missing from it returns
        -- in SILENCE and looks like the command does not exist -- so `blocked` is
        -- checked on every one of these, not just the output.
        local e16 = run('/dl disable');
        check('CMD16 /dl disable is owned (whitelisted, not silently dropped)', e16.blocked, true);
        check('CMD16b bare /dl disable takes all 16',  #D.disabledList(), 16);
        -- ONE LINE (Henrik, 2026-07-26: "please remove all the text"). It still
        -- has to carry the release door -- an ack you cannot undo is worse than
        -- a paragraph -- so that is what is pinned, plus the line COUNT, because
        -- "terse" is the requirement and only a count can regress silently.
        check('CMD16c ...in one line',                 #said, 1);
        check('CMD16d ...naming the release door',     saidHas('/dlac enable'), true);
        check('CMD16e ...and reading as Henrik asked', said[1], '[dlac] All slots disabled - enable by /dlac enable');
        local e17 = run('/dl enable');
        check('CMD17 /dl enable is owned too',         e17.blocked, true);
        check('CMD17b ...and releases everything',     D.disabledOn(), false);

        -- THE LONG PREFIX IS REAL (Henrik, 2026-07-26: "do we have /dlac enable
        -- and such as well? If so, we need it"). argStart accepts both, and the
        -- chat lines say /dlac, so a player who copies what they are told back
        -- into the box must land somewhere. Driven, not read off argStart.
        local e17c = run('/dlac disable feet');
        check('CMD17c /dlac disable <slot> works', e17c.blocked and D.disabledOn('feet'), true);
        local e17d = run('/dlac enable feet');
        check('CMD17d /dlac enable <slot> works',  e17d.blocked and not D.disabledOn('feet'), true);
        run('/dlac disable');
        check('CMD17e /dlac disable bare works',   #D.disabledList(), 16);
        run('/dlac enable');
        check('CMD17f /dlac enable bare works',    D.disabledOn(), false);

        run('/dl disable head');
        check('CMD18 a single slot disables alone',    D.disabledList()[1], 'head');
        check('CMD18b ...only that one',               #D.disabledList(), 1);
        run('/dl disable ammo');
        check('CMD18c a second slot joins it',         #D.disabledList(), 2);
        run('/dl enable head');
        check('CMD18d ...and one can be released alone', D.disabledList()[1], 'ammo');
        check('CMD18e ...with the rest still named back', said[1], '[dlac] Head enabled - still disabled: ammo');
        check('CMD18f ...still one line',                 #said, 1);
        run('/dl enable all');
        check('CMD18g the all-clear is one line too', said[1], '[dlac] All slots enabled');

        -- The two off-forms, so nobody has to guess which release word works.
        run('/dl disable all');
        run('/dl disable off');
        check('CMD19 /dl disable off means enable all', D.disabledOn(), false);
        run('/dl disable legs');
        run('/dl disable legs off');
        check('CMD19b /dl disable <slot> off releases that slot', D.disabledOn('legs'), false);

        local e20 = run('/dl disable nosuchslot');
        check('CMD20 an unknown slot is named back',    said[1], '[dlac] "nosuchslot" is not a slot');
        check('CMD20b ...and still owns the command',   e20.blocked, true);
        check('CMD20c ...having disabled nothing',      D.disabledOn(), false);

        -- Two switches that both read as "stop moving my gear", one beating the
        -- other, is worth a line every time (the /lac disable precedent).
        run('/dl disable hands');
        run('/dl naked');
        check('CMD21 /dl naked warns that free equip outranks it', saidHas('Free equip is on'), true);
        check('CMD21b ...naming the slot it cannot strip',         saidHas('hands stay dressed'), true);
        run('/dl dress');
        run('/dl enable all');

        -- The GUI is a DIFFERENT Lua state and reads the engine's state through
        -- modestate's reserved __ namespace. No mirror = a checkbox that never
        -- moves, and no way to see free equip at all outside chat.
        run('/dl disable back');
        local ms = nil;
        pcall(function() ms = dofile('tests' .. SEP .. 'modestate.lua'); end);
        check('CMD22 the mirror carries __disabled',
              type(ms) == 'table' and type(ms.__disabled) == 'table', true);
        check('CMD22b ...naming the slot', ms and ms.__disabled and ms.__disabled.back, true);
        run('/dl enable all');
        ms = nil;
        pcall(function() ms = dofile('tests' .. SEP .. 'modestate.lua'); end);
        check('CMD22c ...and empties on release',
              ms and ms.__disabled and next(ms.__disabled), nil);
    end

    -- put every shared thing back exactly as it was
    prof.nativeMode, prof.dataDir   = saved.nativeMode, saved.dataDir;
    package.loaded['dlac\\dispatch'] = saved.dispatch;
    package.loaded['dlac\\chatfmt']  = saved.chatfmt;
    _G.gFunc, _G.gState             = saved.gFunc, saved.gState;
    eng.onEvent, eng.state.tripped  = saved.onEvent, saved.tripped;
    TEST_PLAYER                     = saved.player;
    os.remove('tests' .. SEP .. 'modestate.lua');
    os.remove('tests' .. SEP .. 'arbstate.lua');
end)();

-- ---------------------------------------------------------------------------
-- TRC. THE TRACE MUST NOT OUTLIVE THE WORLD IT DESCRIBED (field, 2026-07-26).
--
-- Mindie's boot: the install latch refused for ~2s (world not settled), the
-- Default dispatch built its trace lines against the EMPTY store -- "[NOT
-- FOUND in profile Sets]", true at that moment -- then the install landed,
-- equips worked, and /dl why kept printing the stale NOT FOUND lines with a
-- FRESH timestamp for the rest of the session. Cause: the retrace gate's sig
-- carries rules, locks and every overlay, but nothing about the SETS STORE,
-- and installSets' own re-dispatch therefore found the sig unchanged.
-- The law already exists as v118's "THE INSTALL INVALIDATES THE BELIEF";
-- M.modesRev is bumped by every install and re-flatten -- it belongs in the
-- sig. This section drives the real handler + dispatch exactly like CMD.
-- ---------------------------------------------------------------------------
(function()
    local SEP  = string.char(92);
    local prof = package.loaded['dlac\\profiles'];
    local eng  = package.loaded['dlac\\feature\\equipengine'];
    if type(prof) ~= 'table' or type(eng) ~= 'table' then return; end

    local saved = {
        nativeMode = prof.nativeMode,        dataDir = prof.dataDir,
        dispatch   = package.loaded['dlac\\dispatch'],
        chatfmt    = package.loaded['dlac\\chatfmt'],
        gFunc      = rawget(_G, 'gFunc'),    gState  = rawget(_G, 'gState'),
        gProfile   = rawget(_G, 'gProfile'),
        reg        = ashita.events.register, unreg   = ashita.events.unregister,
        player     = TEST_PLAYER,
        onEvent    = eng.onEvent,            tripped = eng.state.tripped,
    };

    local said = {};
    local function capture(...)
        local parts = {};
        for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))); end
        said[#said + 1] = table.concat(parts, ' ');
    end
    package.loaded['dlac\\chatfmt'] = { print = capture, warn = capture, err = capture };

    -- The world: WHM idle, native armed, no LAC state, no stray gProfile.
    prof.nativeMode = function() return true; end
    prof.dataDir    = function() return 'tests' .. SEP; end
    _G.gFunc, _G.gState, _G.gProfile = nil, nil, nil;
    eng.state.tripped = false;
    TEST_PLAYER = { MainJob = 'WHM', MainJobLevel = 75, SubJob = 'BLM', SubJobLevel = 37,
                    MainJobSync = 75, SubJobSync = 37, Status = 'Idle', IsMoving = false };

    -- One Default rule aimed at a set that does not exist yet: the exact boot
    -- shape (rules load before the install latch lands).
    local trigDir  = 'tests' .. SEP .. 'triggers';
    local trigPath = trigDir .. SEP .. 'WHM.lua';
    -- Windows needs the directory made; on Linux `tests\triggers\WHM.lua` is ONE
    -- filename (backslash is an ordinary character there), so there is nothing to
    -- make. Guard the SHELL, not just the path: `2>nul` is cmd.exe's null device,
    -- but under sh -- the WSL CI-parity run -- it is a literal FILE named `nul`,
    -- dropped in the repo root every run (it broke a `git add`). Same guarded shape
    -- goldenfixtures and smoke_ui already use.
    if package.config:sub(1, 1) == '\\' then
        pcall(function() os.execute('mkdir "' .. trigDir .. '" >nul 2>&1'); end);
    end
    local tf = io.open(trigPath, 'w');
    if tf ~= nil then
        tf:write("return { Default = { { when = { status = 'Idle' }, set = 'Idle' } } };\n");
        tf:close();
    end

    local handlers = {};
    ashita.events.register   = function(ev, nm, fn) handlers[ev] = fn; end
    ashita.events.unregister = function() end
    local okLoad, D = pcall(dofile, 'dispatch.lua');
    ashita.events.register, ashita.events.unregister = saved.reg, saved.unreg;

    check('TRC0 dispatch loads native-armed', okLoad, true);
    if okLoad and type(handlers['command']) == 'function' then
        local function run(line)
            said = {};
            local e = { command = line, blocked = false };
            local ok, err = pcall(handlers['command'], e);
            if not ok then said[#said + 1] = 'ERROR: ' .. tostring(err); end
            return e, ok;
        end
        local function saidHas(frag)
            for _, l in ipairs(said) do
                if string.find(l, frag, 1, true) ~= nil then return true; end
            end
            return false;
        end

        -- Boot window: empty store. The NOT FOUND line is TRUE here.
        D._nativeSets = nil;
        pcall(D.dispatch, 'Default');
        run('/dl why');
        check('TRC1 empty store: the trace says NOT FOUND (true today)',
              saidHas('NOT FOUND in profile Sets'), true);
        check('TRC1b ...for the rule that matched', saidHas('set Idle'), true);

        -- The install lands: the store is swapped and modesRev bumped -- the
        -- two things EVERY installSets branch does (5668/5714). The next
        -- dispatch must rebuild the trace against the new world.
        D._nativeSets = { Dynamic = { Idle = { Body = 'Test Robe' } },
                          Idle    = { Body = 'Test Robe' } };
        D.modesRev = (D.modesRev or 0) + 1;
        pcall(D.dispatch, 'Default');
        run('/dl why');
        check('TRC2 after the install, the trace tells the truth',
              saidHas('NOT FOUND in profile Sets'), false);
        check('TRC2b ...still tracing the same rule', saidHas('set Idle'), true);

        -- And the reverse: the store DIES (a refused install empties it --
        -- 5689 -- after bumping modesRev at 5668). The trace must go stale
        -- honestly: NOT FOUND returns.
        D._nativeSets = nil;
        D.modesRev = (D.modesRev or 0) + 1;
        pcall(D.dispatch, 'Default');
        run('/dl why');
        check('TRC3 a dying store un-tells it too',
              saidHas('NOT FOUND in profile Sets'), true);
    end

    -- put every shared thing back exactly as it was
    prof.nativeMode, prof.dataDir    = saved.nativeMode, saved.dataDir;
    package.loaded['dlac\\dispatch'] = saved.dispatch;
    package.loaded['dlac\\chatfmt']  = saved.chatfmt;
    _G.gFunc, _G.gState              = saved.gFunc, saved.gState;
    _G.gProfile                      = saved.gProfile;
    eng.onEvent, eng.state.tripped   = saved.onEvent, saved.tripped;
    TEST_PLAYER                      = saved.player;
    os.remove(trigPath);
    os.remove('tests' .. SEP .. 'modestate.lua');
    os.remove('tests' .. SEP .. 'arbstate.lua');
end)();

-- ---------------------------------------------------------------------------
-- RQU. THE ENGINE MUST NOT WAIT FOR THE GUI TO LOAD ITS FLATTENER (field,
-- 2026-07-27, Xvs).
--
-- Every utils lookup in dispatch read package.loaded['dlac\\utils'] bare --
-- "loaded first in the LAC state" (the job shim's own first require). The
-- NATIVE state has no shim and nothing else loads utils at boot: the install
-- latch flattened NOTHING, refused every 0.4s as "world not settled", a
-- commit-time refusal nuked the store (nothing equips, /dl lock set finds no
-- set), and a session healed only when a GUI picker's lazy pcall(require)
-- happened to run -- which is why it read as per-JOB in the field (the healed
-- session's job "worked"; a game reload broke that job too). dispatch's
-- utilsModule() now requires lazily at call time. These drive the REAL
-- '/dl sets reload' handler through the exact boot shape: utils ABSENT from
-- package.loaded (package.preload stands in for the addon path, so the heal
-- needs no filesystem require headless).
-- ---------------------------------------------------------------------------
(function()
    local SEP  = string.char(92);
    local prof = package.loaded['dlac\\profiles'];
    local eng  = package.loaded['dlac\\feature\\equipengine'];
    if type(prof) ~= 'table' or type(eng) ~= 'table' then return; end

    local saved = {
        nativeMode = prof.nativeMode,        dataDir = prof.dataDir,
        dispatch   = package.loaded['dlac\\dispatch'],
        chatfmt    = package.loaded['dlac\\chatfmt'],
        utils      = package.loaded['dlac\\utils'],
        preload    = package.preload['dlac\\utils'],
        gFunc      = rawget(_G, 'gFunc'),    gState  = rawget(_G, 'gState'),
        gProfile   = rawget(_G, 'gProfile'),
        reg        = ashita.events.register, unreg   = ashita.events.unregister,
        player     = TEST_PLAYER,
        onEvent    = eng.onEvent,            tripped = eng.state.tripped,
    };
    local savedDM = saved.utils and saved.utils.dispatchModule or nil;

    local said = {};
    local function capture(...)
        local parts = {};
        for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))); end
        said[#said + 1] = table.concat(parts, ' ');
    end
    package.loaded['dlac\\chatfmt'] = { print = capture, warn = capture, err = capture };

    -- The world: WHM idle, native armed, no LAC state, no stray gProfile.
    prof.nativeMode = function() return true; end
    prof.dataDir    = function() return 'tests' .. SEP; end
    _G.gFunc, _G.gState, _G.gProfile = nil, nil, nil;
    eng.state.tripped = false;
    -- Level 63: no earlier section leaves utils' rebuild cache there, so the
    -- level delta alone forces a re-flatten even before the modesRev wire below.
    TEST_PLAYER = { MainJob = 'WHM', MainJobLevel = 63, SubJob = 'BLM', SubJobLevel = 31,
                    MainJobSync = 63, SubJobSync = 31, Status = 'Idle', IsMoving = false };

    -- The active profile's sets file, where readSetsSource looks. Inline
    -- records (Name+Level), so the harness's empty NameToObject never matters.
    local setsDir  = 'tests' .. SEP .. 'profiles' .. SEP .. 'Default' .. SEP .. 'sets';
    local setsPath = setsDir .. SEP .. 'WHM.lua';
    if package.config:sub(1, 1) == '\\' then
        pcall(function() os.execute('mkdir "' .. setsDir .. '" >nul 2>&1'); end);
    end
    local sf = io.open(setsPath, 'w');
    if sf ~= nil then
        sf:write("return { Dynamic = { Idle = { Body = { { Name = 'Test Robe', Level = 1 } } } } };\n");
        sf:close();
    end

    local handlers = {};
    ashita.events.register   = function(ev, nm, fn) handlers[ev] = fn; end
    ashita.events.unregister = function() end
    local okLoad, D = pcall(dofile, 'dispatch.lua');
    ashita.events.register, ashita.events.unregister = saved.reg, saved.unreg;

    check('RQU0 dispatch loads native-armed', okLoad, true);
    if okLoad and type(handlers['command']) == 'function' then
        -- In the game the lazy require executes utils.lua fresh, whose own
        -- require('dlac\\dispatch') binds the LIVE engine instance. The harness
        -- preload hands back the long-loaded utils instead, so wire its
        -- dispatchModule to THIS dispatch copy to mirror that binding.
        if saved.utils ~= nil then saved.utils.dispatchModule = D; end

        local function run(line)
            said = {};
            local e = { command = line, blocked = false };
            local ok, err = pcall(handlers['command'], e);
            if not ok then said[#said + 1] = 'ERROR: ' .. tostring(err); end
            return e, ok;
        end
        local function saidHas(frag)
            for _, l in ipairs(said) do
                if string.find(l, frag, 1, true) ~= nil then return true; end
            end
            return false;
        end

        -- The native boot shape: NOTHING has loaded utils in this state yet.
        package.loaded['dlac\\utils'] = nil;
        package.preload['dlac\\utils'] = function() return saved.utils; end
        run('/dl sets reload');
        check('RQU1 utils absent: the reload flattens and lands', saidHas('sets hot-swapped'), true);
        check('RQU1b ...never the world-not-settled refusal', saidHas('flatten produced no sets'), false);
        check('RQU1c ...and the lazy require left utils loaded',
              package.loaded['dlac\\utils'], saved.utils);

        -- utils truly unresolvable: the refusal stays a refusal (safe, no
        -- crash) -- the pre-fix behavior is the fallback, never an error.
        -- package.path is emptied for the run: earlier sections leave paths
        -- that CAN resolve dlac\utils (exactly as the game's addons\?.lua
        -- does), and this case is specifically about the require FAILING.
        -- The store is cleared first -- that is the boot shape, and a store
        -- RQU1 already flattened would satisfy the count with no flatten.
        D._nativeSets = nil;
        package.loaded['dlac\\utils'] = nil;
        package.preload['dlac\\utils'] = nil;
        local savedPath = package.path;
        package.path = '';
        run('/dl sets reload');
        package.path = savedPath;
        check('RQU2 utils unresolvable: still the honest refusal, no crash',
              saidHas('flatten produced no sets'), true);
    end

    -- put every shared thing back exactly as it was
    package.loaded['dlac\\utils']  = saved.utils;
    package.preload['dlac\\utils'] = saved.preload;
    if saved.utils ~= nil then saved.utils.dispatchModule = savedDM; end
    prof.nativeMode, prof.dataDir    = saved.nativeMode, saved.dataDir;
    package.loaded['dlac\\dispatch'] = saved.dispatch;
    package.loaded['dlac\\chatfmt']  = saved.chatfmt;
    _G.gFunc, _G.gState              = saved.gFunc, saved.gState;
    _G.gProfile                      = saved.gProfile;
    eng.onEvent, eng.state.tripped   = saved.onEvent, saved.tripped;
    TEST_PLAYER                      = saved.player;
    os.remove(setsPath);
    os.remove('tests' .. SEP .. 'modestate.lua');
    os.remove('tests' .. SEP .. 'arbstate.lua');
end)();

-- ---------------------------------------------------------------------------
-- verdict
-- ---------------------------------------------------------------------------
if #failures == 0 then
    print(string.format('OK -- %d checks passed', count));
    os.exit(0);
end
print(string.format('FAIL -- %d of %d checks failed:', #failures, count));
for _, f in ipairs(failures) do print('  ' .. f); end
os.exit(1);
