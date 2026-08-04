local gear = require("dlac\\gear");

-- utils is the lean, profile-side rebuild engine (BuildDynamicSets + level scaling),
-- required by your <JOB>.lua in HandleDefault. The GUI / import / optimizer / setmanager
-- modules are loaded by the dlac ADDON (dlac.lua), NOT here -- so requiring utils from a
-- profile never double-loads the GUI when the dlac addon is also running.

-- (gcinclude is a LuaAshitacast-side config include, not part of dlac. Profiles that
-- use it load it from their own LAC setup -- dlac neither bundles nor loads it.)

staticMainLevel = 0; -- This will override your in-game level for testing purposes
staticSubLevel = 0; -- This will override your in-game sub job level for testing purposes

local M = {}

-- Colored [dlac] chat output (chatfmt): the shadowed `print` re-heads
-- "[dlac] ..."-prefixed lines with the colored header; plain when unavailable.
local _cfmtok, _cfmt = pcall(require, 'dlac\\chatfmt');
local print = (_cfmtok and type(_cfmt) == 'table' and type(_cfmt.print) == 'function') and _cfmt.print or print;

-- Re-export the gear inventory so a migrated profile needs only one require:
--   local utils = require("dlac\\utils"); local gear = utils.gear;
M.gear = gear;

-- The trigger dispatch engine (docs/design/trigger-system.md). Profiles call
-- utils.dispatch('<Handler>') as the LAST line of each Handle* function; the engine
-- reads <char>\dlac\triggers\<JOB>.lua and equips every matching rule. Guarded so a
-- missing/broken dispatch.lua degrades to a no-op and can never break profile loading.
local _dok, _dispatch = pcall(require, "dlac\\dispatch");
if _dok and type(_dispatch) == 'table' and type(_dispatch.dispatch) == 'function' then
    M.dispatchModule = _dispatch;   -- direct access (modes, traces) for advanced use
    M.dispatch = function(event) pcall(_dispatch.dispatch, event); end
    -- THE central equip-eligibility check lives in dispatch (loadable from both
    -- Lua states); re-exported here so profiles and addon modules share ONE rule.
    M.jobCanEquip = _dispatch.jobCanEquip;
    M.canWear     = _dispatch.canWear;
else
    M.dispatch = function() end;
end


-- Remove all your gear, each key value pair represent what your base MP is without gear with that SJ.
-- Oneiros Grip unfortunately only activates based off of your base MP, which differ depending on SJ.
-- For example, if you're a Hume WHM75/BLM37, my base MP is 752.
-- This would make Oneiros Grip latent effect acivate AT half (376) or lower MP.

BaseMPLevel75 = {
    
}

function M.ChecDayAndWeatherBonus(spell)
    local weather = gData.GetWeather();
    local day = gData.GetDay();

    local weatherBonus = false;
    local dayBonus = false;

    if weather == spell.Element or weather == gData.GetElementalOpposition(spell.Element) then
        weatherBonus = true;
    end

    if day == spell.Element or day == gData.GetElementalOpposition(spell.Element) then
        dayBonus = true;
    end

    return dayBonus, weatherBonus;
end

function M.determineLevels()
    local player = gData.GetPlayer();
    local mainLevel = 0;
    local subLevel = 0;

    if staticMainLevel ~= nil and staticMainLevel > 0 then
        mainLevel = staticMainLevel;
    else
        mainLevel = player.MainJobSync;
    end

    if staticSubLevel ~= nil and staticSubLevel > 0 then
        subLevel = staticSubLevel;
    else
        subLevel = player.SubJobSync;
    end

    return mainLevel, subLevel;
end

function M.checkRebuildNeeded(player, lastLevel, lastSJLevel, lastSJ)
    currentLevel, currentSJLevel = M.determineLevels();

    local currentSJ = player.SubJob;
    local shouldRebuild = false;

    if lastLevel ~= currentLevel or lastSJLevel ~= currentSJLevel or lastSJ ~= currentSJ then
        shouldRebuild = true;
    end
    
    -- Return everything needed to update the main file's state
    return shouldRebuild, currentLevel, currentSJLevel, currentSJ;
end

-- If you want a single wrapper function, you can create M.rebuildSetsIfNeeded:
function M.rebuildSetsIfNeeded(player, sets, lastLevel, lastSJLevel, lastSJ)
    -- This function encapsulates the rebuild check and the building logic
    local shouldRebuild, newLevel, newSJLevel, newSJ = M.checkRebuildNeeded(player, lastLevel, lastSJLevel, lastSJ);
    
    if shouldRebuild then
        sets = M.BuildDynamicSets(sets);
    end
    
    -- Return the updated data (sets, and the new 'last known' state)
    return sets, newLevel, newSJLevel, newSJ;
end

-- === Simplified one-call API (recommended for new / migrating profiles) ===
-- Module-level rebuild state, so a profile no longer needs its own local
-- lastKnownLevel / lastKnownSJLevel / lastKnownSJ bookkeeping. utils is required
-- once and cached, so this persists across HandleDefault calls.
local _lastLevel, _lastSJLevel, _lastSJ = 0, 0, nil;

-- Call `sets = utils.rebuildSets(sets)` at the top of HandleDefault. Fetches the
-- player and manages rebuild state internally; returns the (possibly rebuilt) sets.
local _lastModesRev = nil;
local _lastDW = nil;
function M.rebuildSets(sets)
    local player = gData.GetPlayer();
    if player == nil then return sets; end
    local shouldRebuild, newLevel, newSJLevel, newSJ = M.checkRebuildNeeded(player, _lastLevel, _lastSJLevel, _lastSJ);
    -- Mode flips must re-flatten too: mode-gated entries pick differently, and
    -- level/sub-job alone would leave the flattened sets stale forever.
    local mrev = (M.dispatchModule ~= nil) and M.dispatchModule.modesRev or nil;
    if mrev ~= nil and mrev ~= _lastModesRev then
        shouldRebuild = true;
        _lastModesRev = mrev;
    end
    -- The Dual Wield trait bit is a rebuild signal of its own: dw-ruled entries
    -- and the Sub off-hand pairing both flatten against it, and it can flip
    -- with NO level/sub-job change (a BLU trait-set swap) -- or arrive a beat
    -- AFTER the sub-change rebuild already ran (the 0x0AC trait packet races
    -- the job change; without this, that rebuild reads the OLD trait list and
    -- the flatten stays wrong until the next unrelated signal).
    local dwNow = M.isDualWieldAvailable(player.MainJob, newLevel, player.SubJob, newSJLevel) == true;
    if dwNow ~= _lastDW then
        shouldRebuild = true;
        _lastDW = dwNow;
    end
    if shouldRebuild then
        sets = M.BuildDynamicSets(sets);
        _lastLevel, _lastSJLevel, _lastSJ = newLevel, newSJLevel, newSJ;
    end
    return sets;
end

function M.isDualWieldAvailable(mj, mjLevel, sj, sjLevel)
    -- Plan A: ask the game whether the character HAS the Dual Wield trait right now.
    -- The CatsEyeXI server computes each character's trait list from its own
    -- sql/traits.sql (main job + sub job, and BLU via blue-magic trait sets) and
    -- ships that bitmask to the client in packet 0x0AC (GP_SERV_COMMAND_COMMAND_DATA
    -- copies m_TraitList into CommandDataTbl.Traits alongside WeaponSkills /
    -- JobAbilities / PetAbilities). Ashita's Player:HasAbility() indexes that same
    -- command table, where job traits start at id 1536 (0x600) and Dual Wield is
    -- id 1554 = 1536 + trait_id 18 (server repo: documentation/player_abilities.txt
    -- "1554  Dual Wield  Job Trait"; sql/traits.sql keeps every Dual Wield tier on
    -- trait_id 18, so one bit covers all tiers). Trusting this bit means CatsEyeXI's
    -- custom job balance can never desync us -- e.g. their THF gets Dual Wield at
    -- level 83 (Abyssea-tagged), so the old hardcoded THF>=20 row below over-promised
    -- on this server.
    local ok, hasDW = pcall(function()
        local p = AshitaCore:GetMemoryManager():GetPlayer();
        if p == nil then return nil; end
        local job = p:GetMainJob();
        if type(job) ~= 'number' or job < 1 or job > 22 then
            return nil; -- char select / zoning: player block not populated yet
        end
        return p:HasAbility(1554) == true; -- 1554 = Dual Wield trait (any tier)
    end);
    if ok and type(hasDW) == 'boolean' then
        return hasDW;
    end

    -- Fallback (memory unavailable or player not ready): legacy job/level table.
    local THFDWLevel = 20;
    local NINDWLevel = 10;
    local DNCDWLevel = 20;

    if (mj == "THF" and mjLevel >= THFDWLevel) or (sj == "THF" and sjLevel >= THFDWLevel) then
        return true;
    elseif (mj == "NIN" and mjLevel >= NINDWLevel) or (sj == "NIN" and sjLevel >= NINDWLevel) then
        return true;
    elseif (mj == "DNC" and mjLevel >= DNCDWLevel) or (sj == "DNC" and sjLevel >= DNCDWLevel) then
        return true;
    end
    return false;
end

-- Grip vs shield for a Sub-only record. Hand-authored gear.lua says Type="Grip" /
-- "Shield"; the catalog labels BOTH just Type="Sub", so those classify by name --
-- every grip/strap is named "* Grip" / "* Strap". nil = not a Sub-only item.
function M.classifySub(rec)
    local t = rec.Type;
    if t == 'Grip' or t == 'Shield' then return t; end
    if t == 'Sub' then
        local n = string.lower(tostring(rec.Name or ''));
        if n:find('grip', 1, true) ~= nil or n:find('strap', 1, true) ~= nil then return 'Grip'; end
        return 'Shield';
    end
    return nil;
end

-- Sub-slot pairing rule, shared by the rebuild engine and the GUI set builder.
--
-- >>> HARD RULE (Henrik, 2026-07-12 -- reverted THREE times before this; do not
-- >>> "fix" it back. See docs/adr/0006 addendum + HANDOFF hard rule 6.)
-- ctx.building == true means COMPOSING A SET -- a plan, not an equip. While
-- building, the Sub list must NEVER adapt to the Main pick, the Dual Wield
-- trait, or any other live game state: every Sub-capable item (shield, grip,
-- ONE-HANDED weapon) is offered, always -- even with a 2H main planned, even
-- with NO Main planned, even without DW. Sets feed TRIGGERS (e.g. a dual-wield
-- set for when DW is up); gating the builder on today's main/DW makes exactly
-- those sets impossible to compose. The only building-time exclusions are
-- physical impossibilities: a 2H or H2H weapon never fits the Sub slot, and a
-- same-name off-hand needs a provable second copy (a copy count >= 2 --
-- that's item identity, not game state).
--
-- Equip-time (ctx.building falsy) keeps the strict pairing: H2H main -> NOTHING
-- pairs (the server knocks even a grip off, unlike 2H); 2H main -> Grip only;
-- 1H main -> Shield always, a 1H weapon only while ctx.dw (the engine makes
-- this call per cast; the list's shield is the fallback).

-- Hand-to-Hand detection BY TYPE, never by the OneHanded flag: H2H records
-- carry every flag shape in the wild (fresh scans stamp false via TWO_HANDED;
-- the catalog said true -- apicrawl's ONE set, fixed 2026-07-22 -- and /dl fix
-- backfilled that true into files; legacy entries carry none), so the flag
-- cannot decide. Server law (charutils.cpp EquipItem): an H2H main knocks ANY
-- Sub off -- grips included, unlike 2H -- and a shield equipped onto an H2H
-- main knocks the MAIN off; the pair flaps forever (field case 2026-07-22: a
-- monk's H2H Main vs the craft overlay's Kupo Shield). Spellings: imports
-- write 'HandToHand', legacy files 'Hand-to-Hand' (same normalization as
-- gearrecord.canonType -- inlined, utils is LAC-side and cannot require
-- addon modules).
local function isH2H(rec)
    local t = type(rec) == 'table' and rec.Type or nil;
    if type(t) ~= 'string' then return false; end
    t = string.lower((t:gsub('%W', '')));
    return t == 'handtohand' or t == 'h2h';
end

function M.subSlotAllowed(subRec, mainRec, ctx)
    if type(subRec) ~= 'table' then return false; end
    ctx = ctx or {};
    -- Same-name second copy: best of ctx.copies (live bag count -- the GUI
    -- passes ownedcache) and the record's scanned Count (the gear.lua fact,
    -- and the ONLY source in the LAC state, which has no bag scanner).
    -- Replaces the legacy InBothHands flag (removed 2026-07-13).
    local function twoCopies()
        local n = tonumber(ctx.copies) or 0;
        local fc = tonumber(subRec.Count) or 0;
        return ((fc > n) and fc or n) >= 2;
    end
    local kind = M.classifySub(subRec);
    if isH2H(subRec) then return false; end   -- H2H never sits in Sub (physical -- both modes)
    if ctx.building == true then
        if kind ~= nil then return true; end               -- shield / grip: always offered
        if subRec.OneHanded ~= true then return false; end -- 2H or metadata-less: never an off-hand
        if type(mainRec) == 'table' and subRec.Name == mainRec.Name then
            return twoCopies();
        end
        return true;                                        -- 1H weapon: ALWAYS offered
    end
    if type(mainRec) ~= 'table' then return false; end
    if isH2H(mainRec) then return false; end  -- H2H main: NOTHING pairs -- grips too, unlike 2H
    if mainRec.OneHanded == false then
        return kind == 'Grip';
    end
    if mainRec.OneHanded ~= true then return false; end
    if kind == 'Shield' then return true; end
    if kind ~= nil then return false; end                 -- a grip on a 1H main
    if subRec.OneHanded ~= true then return false; end    -- 2H / metadata-less: no off-hand
    if ctx.dw ~= true then return false; end
    if subRec.Name == mainRec.Name then
        return twoCopies();
    end
    return true;
end

-- Resolve a set-entry NAME to its gear.lua record. Exact match first, then
-- case-insensitive: hand-written / static-migrated sets say "Solid wand" while
-- the client names in gear.lua read "Solid Wand" -- a rebuild must not fail on
-- caps. The lowercase index is built lazily once per Lua state (gear.lua is
-- static until a LAC reload rebuilds this state anyway; tests use _resetNameIndex).
-- ...and apostrophe-insensitive on top of that, because the two spellings of an
-- item name in this project come from two sources that disagree: the CatsEyeXI
-- API drops the possessive apostrophe, so catalog.lua says "Arhats Gi" where the
-- client (and therefore gear.lua) says "Arhat's Gi". Anything sourced from the
-- catalog -- a wishlisted piece parked in a set until you own it (ADR 0026) --
-- would otherwise still fail to resolve on the day you finally got it, which is
-- precisely when it is supposed to start working. The API is not even consistent
-- about it (it KEEPS the one in "San D'Orian"), so the strip runs on both sides.
--
-- Built as a FALLBACK layer, never a replacement: every plain lowercase key goes
-- in first and an apostrophe-stripped key is only added where nothing already
-- sits. Exact-lowercase therefore always wins and no lookup that resolves today
-- can start resolving differently.
-- (feature\wishlist.normName carries the same transform for its own comparisons;
-- it is duplicated rather than shared so this rebuild path gains no load-time
-- dependency on a feature module. Change one, change the other.)
local _lcIndex = nil;
local function resolveGearName(name)
    local hit = gear.NameToObject[name];
    if hit ~= nil then return hit; end
    if _lcIndex == nil then
        _lcIndex = {};
        for k, v in pairs(gear.NameToObject) do
            if type(k) == 'string' then _lcIndex[string.lower(k)] = v; end
        end
        for k, v in pairs(gear.NameToObject) do
            if type(k) == 'string' then
                local stripped = string.gsub(string.lower(k), "'", "");
                if _lcIndex[stripped] == nil then _lcIndex[stripped] = v; end
            end
        end
    end
    local lc = string.lower(name);
    return _lcIndex[lc] or _lcIndex[(string.gsub(lc, "'", ""))];
end
function M._resetNameIndex() _lcIndex = nil; end
M.resolveGearName = resolveGearName;   -- the house name->record resolver (dispatch's
                                       -- craft Sub guard pairs records through it)

-- One warning per unique missing name per state: a commit hot-swap rebuilds
-- EVERY dynamic set, and per-occurrence prints flooded the chat log (field
-- case: 30+ lines from three migrated SMN sets).
local _warnedMissing = {};
local function warnMissingGear(name)
    if _warnedMissing[name] then return; end
    -- A WISHLISTED name is unresolvable on purpose (ADR 0026): you parked a piece
    -- you do not own yet in a set so it starts working the day you get it. The
    -- skip above already does the right thing -- the slot's real best-by-level
    -- pick wins -- so the only thing left to get right is the noise. Warning
    -- about it on every commit would read as a bug dlac introduced.
    --
    -- Lazily required, at call time, and swallowed on failure: this runs in the
    -- rebuild path, so it must not gain a load-time dependency on a feature
    -- module, and a broken/absent wishlist must LOSE THE SUPPRESSION rather than
    -- the warning. A name that is neither resolvable nor wishlisted is still a
    -- typo, and still says so.
    local wished = false;
    pcall(function()
        local wl = require('dlac\\feature\\wishlist');
        wished = (type(wl) == 'table') and wl.isWished(name) == true;
    end);
    _warnedMissing[name] = true;
    if wished then return; end
    print('[dlac] set entry "' .. tostring(name) .. '" is not in the gear table -- typo, or not yet indexed (/dl sync).');
end

-- Live copies of a candidate, for subSlotAllowed's same-name off-hand rule.
-- The rule takes the BEST of ctx.copies and the record's Count, so a live read
-- can only ever ADD evidence: a stamped Count = 2 still wins when the bags
-- cannot be read, and nothing that equips today can stop equipping.
-- Through M.dispatchModule (the engine's per-second bag cache) rather than a
-- second scanner here -- utils cannot require addon modules, and one bag
-- reader is the point. nil = unknown; the file stamp answers alone.
local function liveCopies(rec)
    if type(rec) ~= 'table' or rec.Id == nil then return nil; end
    local dsp = M.dispatchModule;
    if dsp == nil or type(dsp.bagCopies) ~= 'function' then return nil; end
    local ok, n = pcall(dsp.bagCopies, rec.Id);
    if ok and type(n) == 'number' then return n; end
    return nil;
end

-- ---------------------------------------------------------------------------
-- THE SLOT LADDER (ADR 0027, stage 1 -- docs/design/two-way-arbiter.md). ONE
-- evaluator produces each slot's ORDERED candidate list, and BuildDynamicSets
-- below derives its pick from the ladder's head -- so the flatten and the
-- ladder cannot drift: the rung order IS the field-proven pick comparator,
-- kept as a sort instead of a truncation. Nothing consumes the tail yet;
-- stage 2 (an ineligible piece falls to its next rung) is the first consumer.
--
-- The comparator, verbatim from the old two-pass walk (tests LD*):
--   * an ACTIVE mode-gated entry outranks every unconditional one (specific
--     beats generic -- the old pass-1/pass-2 split, now a tier); an INACTIVE
--     one is excluded outright;
--   * an entry with an explicit level RANGE that is live right now OUTRANKS
--     every unbounded entry (a range is an instruction, not a hint -- the
--     Garrison Tunica field case);
--   * within the same tier the highest item level wins; on an exact tie the
--     EARLIER list entry keeps its place.
--
-- cctx = { mjLevel, isDW, modeOk } -- the flatten's own context, stamped per
-- rebuild as M._lastFlattenCtx so on-demand ladders (dispatch.candidatesFor)
-- answer AS OF the flatten they accompany. modeActive/virtualMinLevel stay
-- LIVE reads of M.dispatchModule, exactly as the old walk read them --
-- unless the caller supplies its OWN mode judge as cctx.modeOk (stage 5:
-- the Sets-tab preview passes its display-truth judge), the one way a
-- preview may legitimately answer differently.
--
-- Returns { items = {rung...}, accs = {rung...}, virt = marker|nil }:
--   item rung -- { name, level, rank, modeTier, ord, gear = <resolved obj> }
--   acc rung  -- { name, prio, acc, level, rank, modeTier, ord }  (the
--                AutoAcc pool competes only among itself -- pool split law)
--   virt      -- the winning marker STRING (composition is flattenHead's job)
function M.slotLadder(slotTable, slotName, currentMain, cctx)
    local out = { items = {}, accs = {} };
    if type(slotTable) ~= 'table' or type(cctx) ~= 'table' then return out; end
    local mjLv = tonumber(cctx.mjLevel) or 0;
    local dwCtx = { dw = (cctx.isDW == true) };
    local function modeOk(mode)
        if type(cctx.modeOk) == 'function' then return cctx.modeOk(mode) == true; end
        local dsp = M.dispatchModule;
        return dsp ~= nil and type(dsp.modeActive) == 'function' and dsp.modeActive(mode) == true;
    end
    local lastVirt, lastBareVirt = nil, nil;
    local ord = 0;
    -- pairs(), not ipairs(), on purpose: the old walk iterated pairs() and the
    -- tie law ("earlier entry keeps the slot") rode that order. Authored slot
    -- lists are arrays, where the walk is numeric in practice; changing the
    -- iterator here would be a silent behavior change, not a cleanup.
    for _, gearVar in pairs(slotTable) do
        ord = ord + 1;
        repeat
            -- Virtual slot entry ('dlac:AutoStaff' / 'dlac:AutoObi'), bare OR
            -- wrapped -- the Sets tab commits a GATED virtual in wrapper form
            -- ({ gear = 'dlac:AutoIridescence', mode = 'Weapon:Caster' }). The
            -- dispatch engine resolves it at equip time (ADR 0004). A wrapped
            -- virtual honours its mode gate like any entry (field case: only
            -- bare strings were recognised, so WHM's Caster-gated marker
            -- flattened to NOTHING). Remember it, but KEEP walking the slot's
            -- real items -- the best-by-level pick becomes the FALLBACK when
            -- the virtual can't resolve.
            local virt, vmode = nil, nil;
            if type(gearVar) == "string" then
                virt = gearVar;
            elseif type(gearVar) == "table" and type(gearVar.gear) == "string" then
                virt, vmode = gearVar.gear, gearVar.mode;
            end
            if virt ~= nil and string.lower(string.sub(virt, 1, 5)) == "dlac:" then
                if vmode ~= nil and not modeOk(vmode) then break; end
                -- A marker is a ladder RUNG at the level of the lowest item
                -- it can resolve to (dispatch.virtualMinLevel), not a Lv0
                -- wildcard: below that level it is SKIPPED, so the slot's
                -- real best-by-level pick owns the flattened set outright
                -- (Henrik's field case: a leveling WHM's set showed
                -- dlac:AutoIridescence while actually wearing Pilgrim's
                -- Wand -- the marker is a Lv51 rung, his Chatoyant Staff).
                -- nil (no manifest / legacy shapes) keeps always-adopt.
                local dsp = M.dispatchModule;
                if dsp ~= nil and type(dsp.virtualMinLevel) == 'function' then
                    local vok, vlv = pcall(dsp.virtualMinLevel, virt);
                    if vok and type(vlv) == 'number' and vlv > mjLv then break; end
                end
                -- A Sub-slot GRIP marker (dlac:AutoOneiros) obeys the shared
                -- pairing rule at flatten time exactly like a real grip:
                -- 2H main -> legal, 1H or no main -> the slot's real items
                -- win the slot (the engine would only resolve the marker to
                -- a grip the server then refuses to equip).
                if slotName == 'Sub'
                   and string.sub(string.lower(virt), 1, 16) == 'dlac:autooneiros'
                   and not M.subSlotAllowed({ Name = virt, Type = 'Grip', OneHanded = false, Level = 0 },
                                            currentMain, dwCtx) then
                    break;
                end
                lastVirt = virt;
                if vmode == nil then lastBareVirt = virt; end
                break;
            end

            local maxLevel = 75; -- If you have passed the max level for the slot, set high so it won't be limiting if it's not specified.
            local minLevel = 0;
            local gearVarObject = gearVar;

            -- Wrapper form { gear = <ref>, minLevel/maxLevel/mode, ... }: build a
            -- COPY of the gear object with the wrapper's fields applied on top --
            -- individualize augments, override attributes, gate on level or mode.
            -- (The old in-place merge mutated the SHARED gear.lua record, so one
            -- item wrapped differently in two sets leaked fields between them.)
            if type(gearVarObject) == "table" and gearVarObject.gear ~= nil and gearVarObject.Name == nil then
                local ref = gearVarObject.gear;
                if type(ref) == "string" then ref = resolveGearName(ref); end
                local merged = {};
                if type(ref) == "table" then
                    for k, v in pairs(ref) do merged[k] = v; end
                end
                for k, v in pairs(gearVarObject) do
                    if k ~= "gear" then merged[k] = v; end
                end
                gearVarObject = merged;
            end

            local gearObject;
            if type(gearVarObject) == "string" then
                gearObject = resolveGearName(gearVarObject);
                if gearObject == nil then
                    warnMissingGear(gearVarObject);
                    break;
                end
            else
                gearObject = gearVarObject;
            end

            -- The AutoAcc pool split (pool law): typed entries compete only
            -- among themselves; everything else is the normal pick.
            local isAuto = type(gearObject.autoType) == "string"
                       and string.lower(gearObject.autoType) == "autoacc";

            -- The mode tier: an ACTIVE mode-gated entry outranks every
            -- unconditional one; an INACTIVE one is excluded outright (the
            -- old pass-1/pass-2 split as a comparator tier).
            local modeTier = 0;
            if gearObject.mode ~= nil then
                if not modeOk(gearObject.mode) then break; end
                modeTier = 1;
            end

            -- The Dual Wield gear rule (dw = true on the wrapper): the piece is
            -- a CANDIDATE only while the trait is actually up (cctx.isDW -- the
            -- server's own trait bit, same answer the Sub pairing trusts). A
            -- gate, not a tier: with the trait up it ranks like any other entry
            -- (Suppanomimi's high item level usually wins on its own), without
            -- it the slot's next-best piece owns the slot.
            if gearObject.dw == true and cctx.isDW ~= true then break; end

            if gearObject.maxLevel ~= nil then
                maxLevel = gearObject.maxLevel;
            end
            if gearObject.minLevel ~= nil then
                minLevel = gearObject.minLevel;
            end

            -- Seems like when loading in, it can't parse items properly at times, so this check will avoid errors.
            if gearObject.Level == nil then break; end
            -- if gear level is over Main job level, ignore.
            if gearObject.Level > mjLv then break; end
            -- if Main Job level is outside the entry's declared window, ignore.
            if mjLv > maxLevel then break; end
            if mjLv < minLevel then break; end

            -- Sub-slot pairing (shared rule, applied per CANDIDATE): DW
            -- decides whether a 1H off-hand is legal; the list's shield/grip
            -- is the fallback. H2H mains pair with NOTHING (ADR 0006).
            -- The same-name case (two of one weapon) additionally needs proof
            -- of a second copy -- read LIVE, and only when the names actually
            -- match, so the ordinary candidate costs no bag lookup at all.
            if slotName == "Sub" then
                dwCtx.copies = nil;
                if type(currentMain) == 'table' and gearObject.Name == currentMain.Name then
                    dwCtx.copies = liveCopies(gearObject);
                end
                if not M.subSlotAllowed(gearObject, currentMain, dwCtx) then
                    break;
                end
            end

            -- RANKING (see the comparator note above): a live explicit range
            -- is tier 1, unbounded is tier 0.
            local rank = (gearObject.minLevel ~= nil or gearObject.maxLevel ~= nil) and 1 or 0;
            if isAuto then
                out.accs[#out.accs + 1] = {
                    name = gearObject.Name,
                    prio = math.floor(tonumber(gearObject.removePrio) or 1),
                    acc  = math.floor(tonumber(gearObject.acc) or 0),
                    level = gearObject.Level, rank = rank,
                    modeTier = modeTier, ord = ord,
                };
            else
                out.items[#out.items + 1] = {
                    name = gearObject.Name, level = gearObject.Level,
                    rank = rank, modeTier = modeTier, ord = ord,
                    gear = gearObject,
                };
            end
        until true;
    end
    local function better(a, b)
        if a.modeTier ~= b.modeTier then return a.modeTier > b.modeTier; end
        if a.rank ~= b.rank then return a.rank > b.rank; end
        if a.level ~= b.level then return a.level > b.level; end
        return a.ord < b.ord;
    end
    table.sort(out.items, better);
    table.sort(out.accs, better);
    -- The virtual winner. Almost always "the last eligible virtual in file
    -- order" -- but the old pass structure carried a QUIRK, preserved here
    -- and pinned by LD8 so it can only ever change on purpose: pass 2 (which
    -- ran only when NO mode item was eligible) re-adopted BARE virtuals in
    -- file order, so with no eligible mode item and any bare virtual present,
    -- the last BARE virtual beat a later mode-gated one.
    local anyModeItem = (out.items[1] ~= nil and out.items[1].modeTier == 1);
    if not anyModeItem and lastBareVirt ~= nil then
        out.virt = lastBareVirt;
    else
        out.virt = lastVirt;
    end
    return out;
end

-- The flatten's pick, derived from a ladder (stage 1: the ONE composition
-- site -- the 'marker|fallback' and 'dlac:AutoAcc:prio:acc:Name|fallback'
-- encodings live here and nowhere else). Returns (head, mainObj):
--   head    -- the string BuildDynamicSets stores for the slot, or nil
--   mainObj -- the gear object Sub-pairing judges against when this slot is
--              Main: the winning item's object, OVERRIDDEN by the synthetic
--              2H-staff table when a Main STAFF MARKER composes (a staff
--              marker always resolves to a two-handed staff, so the Sub
--              pairing must treat it as one -- otherwise 'no main -> no sub'
--              vetoes the grip that belongs with it; field case: a
--              Weapon:Caster grip sat unequipped under dlac:AutoIridescence).
function M.flattenHead(ladder, slotName)
    if type(ladder) ~= 'table' then return nil, nil; end
    local itemHead = (type(ladder.items) == 'table') and ladder.items[1] or nil;
    local head = nil;
    local mainObj = (itemHead ~= nil) and itemHead.gear or nil;
    if ladder.virt ~= nil then
        -- Compose the virtual with its fallback: 'dlac:AutoStaff|<bestName>'.
        -- The engine tries the virtual first and equips the fallback when it
        -- can't resolve; with no fallback the slot is left untouched at
        -- resolve time.
        if itemHead ~= nil then
            head = ladder.virt .. '|' .. itemHead.name;
        else
            head = ladder.virt;
        end
        if slotName == 'Main' then
            local lv = string.lower(ladder.virt);
            if string.sub(lv, 1, 14) == 'dlac:autostaff'
               or string.sub(lv, 1, 21) == 'dlac:autoiridescence' then
                mainObj = { Name = ladder.virt, Type = 'Staff', OneHanded = false, Level = 0 };
            end
        end
    elseif type(ladder.accs) == 'table' and ladder.accs[1] ~= nil then
        -- Type automation (AutoAcc): compose the marker the engine budgets
        -- with at equip time. Name goes LAST in the marker half so the
        -- parser survives any item name; prio/acc are baked here because
        -- the equip-time resolver has no catalog to look them up in.
        -- 'dlac:AutoAcc:<removePrio>:<acc>:<Name>|<fallback>'
        local a = ladder.accs[1];
        local mk = string.format('dlac:AutoAcc:%d:%d:%s', a.prio, a.acc, a.name);
        if itemHead ~= nil then
            head = mk .. '|' .. itemHead.name;
        else
            head = mk;
        end
    elseif itemHead ~= nil then
        head = itemHead.name;
    end
    return head, mainObj;
end

-- The Sets-tab preview's pick, through THE evaluator (ADR 0027, stage 5 --
-- the GUI's hand-mirrored comparator retired into this). `list` is the
-- editor's WORKING model ({ rec = <record>, minLevel, maxLevel, mode,
-- autoType, removePrio, acc } per entry; rec.Virtual = a marker); each entry
-- is shaped into its authored form INDEX-ALIGNED (a rung's ord maps back to
-- the working entry) and judged by slotLadder -- same comparator, same
-- virtual-adoption law (the LD8 quirk included), same Sub pairing against
-- the planned Main. cctx is the caller's: its preview level and its own
-- mode judge (cctx.modeOk), the two ways a preview may differ from the
-- live flatten. Returns (entry, ladder): the winning WORKING entry --
-- virtual > AutoAcc > item, flattenHead's composition order -- and the
-- ladder itself (rung 2+ = what the piece would fall to).
function M.workingPick(list, slotName, currentMain, cctx)
    if type(list) ~= 'table' or list[1] == nil then return nil, nil; end
    local authored = {};
    for i, it in ipairs(list) do
        local a = {};   -- an unresolvable entry stays a HOLE (no Level -> skipped)
        if type(it) == 'table' and type(it.rec) == 'table' then
            if it.rec.Virtual == true and type(it.rec.Name) == 'string' then
                a = (it.mode ~= nil) and { gear = it.rec.Name, mode = it.mode } or it.rec.Name;
            else
                a = { gear = it.rec, minLevel = it.minLevel, maxLevel = it.maxLevel,
                      mode = it.mode, dw = it.dw, autoType = it.autoType,
                      removePrio = it.removePrio, acc = it.acc };
            end
        end
        authored[i] = a;
    end
    local lad = M.slotLadder(authored, slotName, currentMain, cctx);
    if lad.virt ~= nil then
        for _, it in ipairs(list) do
            if type(it) == 'table' and type(it.rec) == 'table'
               and it.rec.Virtual == true and it.rec.Name == lad.virt then
                return it, lad;
            end
        end
    end
    local head = (type(lad.accs) == 'table') and lad.accs[1] or nil;
    if head == nil then head = (type(lad.items) == 'table') and lad.items[1] or nil; end
    if head ~= nil then return list[head.ord], lad; end
    return nil, lad;
end

function M.BuildDynamicSets(sets)
    local player = gData.GetPlayer();

    -- Safety check for player data
    if not player then return sets end

    -- (bare assignment on purpose: the pre-stage-1 code leaked these two as
    -- globals; kept assigned so any external reader keeps its answer)
    mjLevel, sjLevel = M.determineLevels();

    local mj = player.MainJob;
    local sj = player.SubJob;

    local isDW = M.isDualWieldAvailable(mj, mjLevel, sj, sjLevel);

    -- The ladder epoch (ADR 0027 stage 1): bumped per rebuild; on-demand
    -- ladders (dispatch.candidatesFor) memoize against it and answer with
    -- THIS flatten's context, so a ladder and the flatten it accompanies can
    -- never disagree about level or Dual Wield.
    M._laddersRev = (M._laddersRev or 0) + 1;
    local cctx = { mjLevel = mjLevel, isDW = isDW };
    M._lastFlattenCtx = cctx;

    -- Each dynamic set: every slot's pick IS its ladder's head (stage 1 --
    -- one evaluator, two consumers; parity pinned by LD9).
    for setName, setTable in pairs(sets.Dynamic) do
        local currentSet = {};
        local currentMain = nil; -- Nil for proper checks

        -- Main MUST resolve before Sub (the pairing rule reads currentMain),
        -- and pairs() order is undefined -- so walk Main first, then the rest.
        local slotNames = {};
        if setTable.Main ~= nil then slotNames[#slotNames + 1] = 'Main'; end
        for slotName in pairs(setTable) do
            if slotName ~= 'Main' then slotNames[#slotNames + 1] = slotName; end
        end
        for _, slotName in ipairs(slotNames) do
            local lad = M.slotLadder(setTable[slotName], slotName, currentMain, cctx);
            local head, mainObj = M.flattenHead(lad, slotName);
            if head ~= nil then currentSet[slotName] = head; end
            -- Store reference to the main hand item for sub slot logic
            if slotName == 'Main' then currentMain = mainObj; end
        end

        -- (Reserved slots -- a Body that takes Head away, like the Ryl.Ftm. Tunic --
        -- are resolved by the ENGINE at equip time, not here. The ffxi-lac original
        -- stripped Head during the build, keyed off a hand-authored
        -- CannotEquipHeadgear flag; both halves were wrong for dlac. Building is the
        -- wrong altitude: sets overlay, so a Head this set owns is perfectly legal
        -- under a higher-priority trigger that swaps the Body out -- stripping it
        -- here would lose it. And the flag was never a dlac field, so the check was
        -- dead code that always read nil. See dispatch.reservedDrops / ADR 0006.)
        sets[setName] = currentSet;
    end
    return sets;
end

STORAGES = {
    [9] = { id=8, name='Wardrobe' },
    [11]= { id=10, name='Wardrobe 2' },
    [12]= { id=11, name='Wardrobe 3' },
    [13]= { id=12, name='Wardrobe 4' },
    [14]= { id=13, name='Wardrobe 5' },
    [15]= { id=14, name='Wardrobe 6' },
    [16]= { id=15, name='Wardrobe 7' },
    [17]= { id=16, name='Wardrobe 8' }
};

M.Test = function()
    print ("Running Tests...");
    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    local resources = AshitaCore:GetResourceManager();
    for k,v in pairs(STORAGES) do
        local itemEntry = inventory:GetItem(v.id, j);
        print (itemEntry);
        break
    end
end


ashita.events.register('command', 'dlac', function (e)
    local raw_command = string.lower(e.command);
    local prefix = "/dlac";
    local shortPrefix = "/dl";
    local args = {};
    local start_index = 0;

    -- If the command does not start with the prefix, ignore it.
    if string.sub(raw_command, 1, #prefix) == prefix then
        start_index = #prefix + 2
    elseif string.sub(raw_command, 1, #shortPrefix) == shortPrefix then
        start_index = #shortPrefix + 2
    else
        return;
    end

    -- Get starting index for arguments.
    

    -- Fetch out the string starting from the start index, so we can parse the actual arguments while ignoring prefix.
    local raw_args_string = string.sub(raw_command, start_index)

    -- Loop through and split arguments by spaces and insert into args table.
    for arg in string.gmatch(raw_args_string, "[^%s]+") do
                table.insert(args, arg)
    end
    
    -- Simple check to see if there is even a sub-command present before I try to use it.
    if args[1] == nil then return; end

    sub_command = args[1];

    if sub_command == "set" then
        if args[2] == nil then return; end

        set_command = args[2];

        if set_command == "level" then
            if args[3] == nil then return; end

            local level_type = args[3];

            if level_type == "main" or "sub" then
                if args[4] == nil then return; end

                local new_level = tonumber(args[4]);

                if new_level == nil then return; end

                if level_type == "main" then
                    staticMainLevel = new_level;
                    print("Main job level set to " .. tostring(staticMainLevel) .. ".");
                elseif level_type == "sub" then
                    staticSubLevel = new_level;
                    print("Sub job level set to " .. tostring(staticSubLevel) .. ".");
                end
            end
        end
    elseif sub_command == "dw" then
        -- Field probe for the Dual Wield trait bit (docs/reference/catseyexi-jobs.md):
        -- shows the raw HasAbility(1554) answer next to what the engine concludes.
        local bit = 'n/a';
        pcall(function()
            local p = AshitaCore:GetMemoryManager():GetPlayer();
            if p ~= nil then bit = tostring(p:HasAbility(1554)); end
        end);
        local mj, sj, mlv, slv = '?', '?', 0, 0;
        pcall(function()
            local p = gData.GetPlayer();
            mj = p.MainJob or '?'; sj = p.SubJob or '?';
            mlv, slv = M.determineLevels();
        end);
        print(string.format('[dlac] DW probe: HasAbility(1554)=%s  %s%s/%s%s  -> isDualWieldAvailable=%s',
            bit, tostring(mj), tostring(mlv), tostring(sj), tostring(slv),
            tostring(M.isDualWieldAvailable(mj, mlv, sj, slv))));
    elseif sub_command == "recalc" then
        sets = M.BuildDynamicSets(sets);
    elseif sub_command == "test" then
        M.Test();
    elseif sub_command == "reload" or sub_command == "r" then
        -- Reloads DLAC (Henrik, 2026-07-26). This queued '/addon reload
        -- luashitacast' from the LAC-hosted era; on a migrated (native) install
        -- that RESURRECTED LuaAshitacast and fired the coexistence tripwire,
        -- which disarms the native engine for the rest of the session.
        AshitaCore:GetChatManager():QueueCommand(1, '/addon reload dlac');
    end
end);






return M;