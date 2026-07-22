-- ===========================================================================
-- Gear Oracle -- golden-output harness (issue #72, PRD #69 Phase 2 gate)
-- ===========================================================================
-- THE safety gate for the Phase 2 stat-glue migration. PRD #69 splits the Gear
-- Oracle into two phases: Phase 1 (step 1, #70) moved the mechanical fetch layer
-- behind one door; Phase 2 (step 5, #74 -- SHIPPED) migrated the manifest builders
-- that hand-glued "effective stats = level-scaled stats + augment fold" onto the
-- shared oracle.stats()/setStats() recipe. PRD phasing decision: "Phase 2 must not
-- begin until [the field] rounds clear ... migration is proven byte-identical, not
-- assumed."
--
-- This module captures the EXACT output of every stat-glue builder from a set of
-- deterministic, synthetic, headless fixtures (no live client) -- the same fixture
-- style tests/smoke_ui.lua section 9 already uses. The captured strings are
-- committed as goldens under tests/golden/. A suite test (smoke_ui section 12)
-- asserts the builders reproduce those goldens BYTE-IDENTICALLY. The #74 migration
-- routed the SAME fixtures through the oracle and produced the SAME goldens -- so a
-- later field failure can never be misattributed to the migration. The gate STAYS:
-- any future stat-glue change must keep these goldens byte-identical or justify the
-- diff.
--
-- The builders captured (issue #72):
--   * the MaxMP battery ladder derivation -- MP / Refresh / Convert batteries,
--     the movement map, AND the augment fold (autogear.lua: mp/rf/mv/mpBest);
--   * the HELM gear ladders (autogear.lua: helm + the semantic hat map);
--   * the fishing ladders (autogear.lua: fish) AND the rod-ranking gear reads
--     (fishcalc: rodsFor / bestOwnedRod, wornFishTotal, gearScore);
--   * the craft-skill item lists -- the full owned-gear walk per craft
--     (autogear.lua: craft).
-- The manifest text is the builder's own output verbatim; the only value dropped
-- is the `written = "<timestamp>"` clock stamp (normalized to a fixed string), so
-- the capture is deterministic run to run.
--
-- To (re)generate the goldens after an INTENTIONAL builder/format change, run:
--     lua5.4 tests/gen_goldens.lua
-- and review the diff -- a golden change is a claim that a field-tuned ladder's
-- output moved, which Phase 2 by definition must NOT do.
-- ===========================================================================

local M = {};

-- ---------------------------------------------------------------------------
-- Env: the smoke_ui/run_tests headless stubs. Idempotent, so it is a no-op when
-- the host suite already installed them (smoke_ui) and a full setup when a bare
-- script requires this module (gen_goldens.lua).
-- ---------------------------------------------------------------------------
function M.ensureEnv()
    if package.loaded['dlac\\ui\\automationsui'] == nil then
        -- resolve require('dlac\\X') -> ./X.lua (the smoke_ui shim; '\'->'/' so it
        -- also loads off Windows, where '\' is not a path separator).
        local haveShim = false;
        for _, s in ipairs(package.searchers or package.loaders) do
            if s == M._shim then haveShim = true; break; end
        end
        if not haveShim then
            M._shim = M._shim or function(name)
                local rel = name:match('^dlac\\(.+)$');
                if rel == nil then return nil; end
                local chunk = loadfile((rel:gsub('\\', '/')) .. '.lua');
                if chunk == nil then return nil; end
                return chunk;
            end
            table.insert(package.searchers or package.loaders, 1, M._shim);
        end
    end
    if package.loaded['bit'] == nil then
        package.loaded['bit'] = {
            band   = function(a, b) return a & b; end,
            bor    = function(a, b) return a | b; end,
            bxor   = function(a, b) return a ~ b; end,
            bnot   = function(a) return ~a; end,
            lshift = function(a, n) return a << n; end,
            rshift = function(a, n) return a >> n; end,
            arshift= function(a, n) return a >> n; end,
        };
    end
    if rawget(_G, 'ashita') == nil then
        ashita = { events = { register = function() end, unregister = function() end } };
    end
    if rawget(_G, 'gData') == nil then
        gData = { GetPlayer = function() return nil; end };
    end
end

-- ---------------------------------------------------------------------------
-- Deterministic canonical serializer for the fishcalc capture (sorted keys,
-- arrays in order). Not used for the manifest -- that is the builder's own text.
-- ---------------------------------------------------------------------------
local function isArray(t)
    local n = 0;
    for _ in pairs(t) do n = n + 1; end
    return n == #t and n > 0;
end
local function canon(v, indent)
    indent = indent or '';
    local ty = type(v);
    if ty == 'number' then
        if v == math.floor(v) then return string.format('%d', v); end
        return string.format('%.6g', v);
    elseif ty == 'string' then
        return string.format('%q', v);
    elseif ty == 'boolean' then
        return tostring(v);
    elseif ty == 'nil' then
        return 'nil';
    elseif ty == 'table' then
        local inner = indent .. '  ';
        local parts = {};
        if isArray(v) then
            for _, e in ipairs(v) do
                parts[#parts + 1] = inner .. canon(e, inner);
            end
        else
            local keys = {};
            for k in pairs(v) do keys[#keys + 1] = k; end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b); end);
            for _, k in ipairs(keys) do
                parts[#parts + 1] = string.format('%s[%s] = %s', inner, canon(k), canon(v[k], inner));
            end
        end
        if #parts == 0 then return '{}'; end
        return '{\n' .. table.concat(parts, ',\n') .. '\n' .. indent .. '}';
    end
    return string.format('%q', tostring(v));
end
M.canon = canon;

-- ---------------------------------------------------------------------------
-- The manifest fixture: one BLM character at level 74, one curated bag. Every
-- stat-glue builder gets a decisive, hand-checkable case; the interesting cases
-- issue #72 calls for are commented at the item that carries them.
-- ---------------------------------------------------------------------------
local INV = {
    -- MaxMP batteries + Convert + Refresh + augment fold ---------------------
    { Name = 'Astral Ring',       Id = 90010, Level = 10, Slot = 'Ring',  Jobs = { 'All' }, Stats = { MP = 12 } },            -- x2 -> BOTH ring ladders
    { Name = 'Uggalepih Pendant', Id = 90011, Level = 70, Slot = 'Neck',  Jobs = { 'All' }, Stats = { ConvertHPtoMP = 25 } }, -- Convert counts as +MP
    { Name = 'Mana Club',         Id = 90012, Level = 40, Slot = 'Main',  Jobs = { 'All' }, Stats = { MP = 10 } },            -- Main: hold map only, TP rule keeps it OUT of mpBest
    { Name = 'Hlr. Bliaut +1',    Id = 90013, Level = 70, Slot = 'Body',  Jobs = { 'All' }, Stats = { MP = 35 } },            -- AUGMENT FOLD: +MP 18 -> 53
    { Name = 'Clr. Bliaut +1',    Id = 90014, Level = 74, Slot = 'Body',  Jobs = { 'All' }, Stats = { MP = 29, Refresh = 1 } }, -- AUGMENT FOLD: Refresh 1 native + 1 aug -> rf 2
    { Name = 'Pegasus Collar',    Id = 90016, Level = 60, Slot = 'Neck',  Jobs = { 'All' }, Stats = { MovementSpeed = 12 } }, -- movement map; no MP -> OUT of mpBest
    -- LEVEL-SCALING: Id 15545 scales MP with level (data/levelscaling.lua) -----
    { Name = 'Tamas Ring',        Id = 15545, Level = 74, Slot = 'Ring',  Jobs = { 'All' }, Stats = { MP = 15 } },            -- MP 15 base -> 29 at char Lv74 (NOT the base value)
    -- HELM ladders ----------------------------------------------------------
    { Name = 'Field Tunica',      Id = 90030, Level = 1,  Slot = 'Body',  Jobs = { 'All' }, Stats = { HELM = 2, Surveyor = 1 } },
    { Name = "Miner's Helmet",    Id = 25560, Level = 1,  Slot = 'Head',  Jobs = { 'All' }, Stats = { Surveyor = 1 } },       -- + semantic hat map (Mining): REAL id -- the map is id-PINNED, and the CLIENT name carries the apostrophe the catalog drops (the 07-22 field bug)
    -- Craft-skill lists (the full owned-gear walk per craft) ----------------
    { Name = 'Chefs Hat',         Id = 90020, Level = 1,  Slot = 'Head',  Jobs = { 'All' }, Stats = { CookingSkill = 1 } },   -- tops the hq ladder
    { Name = 'Chefs Ring',        Id = 90021, Level = 1,  Slot = 'Ring',  Jobs = { 'All' }, Stats = { AntiHQCooking = 1 } },  -- nq only; BLOCKED from hq
    { Name = 'Bonze Cape',        Id = 90022, Level = 1,  Slot = 'Back',  Jobs = { 'All' }, Stats = { SynthSkillGain = 4 } }, -- skillup goal + hq/nq filler
    -- Fishing ladders -------------------------------------------------------
    { Name = 'Fishermans Tunica', Id = 90040, Level = 1,  Slot = 'Body',  Jobs = { 'All' }, Stats = { FishingSkill = 1 } },
    { Name = 'Halieutica',        Id = 90041, Level = 49, Slot = 'Main',  Jobs = { 'All' }, Stats = { FishingSkill = 2 } },   -- fishing weapon rides the Main fish ladder
    -- ONE item across MULTIPLE ladders --------------------------------------
    { Name = 'Survey Sash',       Id = 90050, Level = 50, Slot = 'Waist', Jobs = { 'All' }, Stats = { MP = 8, Surveyor = 1, FishingSkill = 1 } }, -- mpBest.waist + helm.waist + fish.waist
    -- Staves / obis / universals (Iridescence tiering) ----------------------
    { Name = 'Fire Staff',        Id = 90001, Level = 51, Slot = 'Main',  Jobs = { 'All' } },  -- NQ Fire
    { Name = "Vulcan's Staff",    Id = 90002, Level = 51, Slot = 'Main',  Jobs = { 'All' } },  -- HQ Fire -> tier 2
    { Name = 'Ice Staff',         Id = 90003, Level = 51, Slot = 'Main',  Jobs = { 'All' } },  -- NQ Ice -> tier 1
    { Name = 'Chatoyant Staff',   Id = 90005, Level = 75, Slot = 'Main',  Jobs = { 'All' } },  -- universal +2
    { Name = 'Iridal Staff',      Id = 90006, Level = 71, Slot = 'Main',  Jobs = { 'All' } },  -- universal +1
    { Name = 'Karin Obi',         Id = 90007, Level = 71, Slot = 'Waist', Jobs = { 'All' } },  -- Fire obi
    { Name = 'Hachirin-no-obi',   Id = 90008, Level = 71, Slot = 'Waist', Jobs = { 'All' } },  -- universal obi
};
local AUG = { [90013] = { MP = 18 }, [90014] = { Refresh = 1 } };   -- private augments on the owned copies
local CHAR_LEVEL = 74;

-- ---------------------------------------------------------------------------
-- Capture 1: the automation manifest text (staves/obis/universals, MaxMP, craft,
-- HELM, fish) -- the builder's own output, with the clock stamp normalized.
-- ---------------------------------------------------------------------------
local function captureManifest()
    local aui = require('dlac\\ui\\automationsui');

    local sep = package.config:sub(1, 1);
    local root = 'tests' .. sep .. 'tmp_golden' .. sep;
    -- autoPath appends the literal 'dlac\autogear.lua'. On Linux that is ONE
    -- filename (backslash inside the name); on Windows the same string is a
    -- subpath, so the dlac\ directory must exist or the write silently fails.
    if sep == '\\' then os.execute('mkdir "tests\\tmp_golden\\dlac" >nul 2>&1');
    else os.execute('mkdir -p "tests/tmp_golden" >/dev/null 2>&1'); end
    local mpath = root .. 'dlac\\autogear.lua';   -- matches autoPath verbatim
    os.remove(mpath);

    local byName, byId, counts = {}, {}, {};
    for _, r in ipairs(INV) do
        byName[r.Name] = r; byId[r.Id] = r;
        counts[r.Id] = (r.Name == 'Astral Ring') and 2 or 1;
    end
    aui.init({
        charBase     = function() return root; end,
        lookupByName = function(n) return byName[n]; end,
        lookupById   = function(id) return byId[id]; end,
        ownedCounts  = function() return counts; end,
        ownedList    = function() return INV; end,
        allEquipList = function() return INV; end,
        haveInBags   = function() return true; end,
        playerJob    = function() return 'BLM'; end,
    });

    -- pin the character level (level-scaling reads GetMainJobLevel) and the
    -- augment fold; save/restore so the host suite is left as it was found.
    local savedAshita = AshitaCore;
    local savedAug    = package.loaded['dlac\\feature\\augments'];
    AshitaCore = { GetMemoryManager = function()
        return { GetPlayer = function()
            return { GetMainJobLevel = function() return CHAR_LEVEL; end };
        end };
    end };
    package.loaded['dlac\\feature\\augments'] = { ownedAugStats = function() return AUG; end };

    aui.rescanAutogear();

    AshitaCore = savedAshita;
    package.loaded['dlac\\feature\\augments'] = savedAug;

    local f = io.open(mpath, 'r');
    local text = f and f:read('*a') or nil;
    if f then f:close(); end
    os.remove(mpath);
    -- Windows: the tree is tmp_golden\dlac\ (two levels), so /s /q; the file is
    -- already removed, so this only ever deletes the empty scaffold dirs.
    if sep == '\\' then os.execute('rmdir /s /q "tests\\tmp_golden" >nul 2>&1');
    else os.execute('rmdir "tests/tmp_golden" >/dev/null 2>&1'); end

    if text == nil then return nil; end
    -- Drop the only non-deterministic value: the clock stamp.
    text = text:gsub('(\n    written = )"[^"]*"', '%1"<golden -- normalized>"');
    return text;
end

-- ---------------------------------------------------------------------------
-- Capture 2: the fishcalc rod-ranking gear reads. A synthetic rod/gear db is
-- injected (fishcalc._setDb) so the ranking, worn-total and gear-score math run
-- against fully deterministic, synthetic inputs -- no shipped-data dependency.
-- ---------------------------------------------------------------------------
local FISH_DB = {
    rods = {
        [17386] = { n = "Lu Shang's Fishing Rod", sz = 0, minR = 1, maxR = 30, brk = 1, leg = 0, atk = 5, tim = 10, rating = 7 },
        [17011] = { n = 'Ebisu Fishing Rod',      sz = 0, minR = 1, maxR = 35, brk = 0, leg = 1, atk = 8, tim = 12, rating = 9 },
        [7001]  = { n = 'Composite Fishing Rod',  sz = 0, minR = 1, maxR = 20, brk = 1, leg = 0, atk = 2, tim = 5,  rating = 4 },
        [7002]  = { n = 'Halcyon Rod',            sz = 0, minR = 1, maxR = 25, brk = 1, leg = 0, atk = 3, tim = 6,  rating = 5 },
    },
    gearBonus = {
        [8001] = { fish = 1, sl = 'Body' },
        [8002] = { fish = 1, sl = 'Ring' },
        [8003] = { fish = 2, sl = 'Head', cx4 = 1, cx5 = 3 },
        [8004] = { fish = 3, sl = 'Range' },   -- Range is the pick, not a worn bonus -> excluded
    },
    aff = {}, pools = {}, mobs = {}, guild = {},
};
local FISH   = { sk = 50, sz = 1, leg = 0, rank = 40 };   -- a large fish
local SKILL  = 45;
local OWNED  = { [17386] = true, [7001] = true };         -- own Lu Shang's + Composite, not Ebisu/Halcyon
local WORN_COUNTS = { [8001] = 1, [8002] = 2, [8003] = 1, [8004] = 5 };  -- ring x2 (both fingers)

local function captureFishcalc()
    local fc = require('dlac\\feature\\fishcalc');
    local origDb = fc.db();          -- capture the real shipped db to restore
    fc._setDb(FISH_DB);

    local rank = {};
    for i, r in ipairs(fc.rodsFor(FISH, SKILL, OWNED)) do
        rank[i] = { pos = i, id = r.id, name = r.rod.n, owned = r.owned, ok = r.v.ok,
                    lose = r.v.lose, loseWhy = r.v.loseWhy, snap = r.v.snap, brk = r.v.brk,
                    risk = r.risk };
    end
    local best = fc.bestOwnedRod(FISH, SKILL, OWNED);
    local out = {
        fish = FISH, skill = SKILL, ownedRods = OWNED,
        rodRanking = rank,
        bestOwnedRod = best and { id = best.id, name = best.rod.n, ok = best.v.ok } or false,
        wornFishTotal = fc.wornFishTotal(WORN_COUNTS),
        gearScore = {
            ['fish=0,no-bonus']  = fc.gearScore(0, nil),
            ['fish=1,no-bonus']  = fc.gearScore(1, nil),
            ['fish=2,cx4=1cx5=3'] = fc.gearScore(2, { cx4 = 1, cx5 = 3 }),
            ['fish=3,cx4=1cx5=3'] = fc.gearScore(3, { cx4 = 1, cx5 = 3 }),
        },
    };

    fc._setDb(origDb);   -- leave fishcalc as we found it

    return '-- fishcalc rod-ranking gear reads (golden -- issue #72)\n'
        .. 'return ' .. canon(out) .. '\n';
end

-- ---------------------------------------------------------------------------
-- Public: capture every golden. Returns { filename = text, ... }.
-- ---------------------------------------------------------------------------
function M.capture()
    M.ensureEnv();
    return {
        ['autogear.golden'] = captureManifest(),
        ['fishcalc.golden'] = captureFishcalc(),
    };
end

-- Where the committed goldens live (relative to the addon root).
M.dir = 'tests' .. package.config:sub(1, 1) .. 'golden' .. package.config:sub(1, 1);
function M.pathFor(name) return M.dir .. name; end

return M;
