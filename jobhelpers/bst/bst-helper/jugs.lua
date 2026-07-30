--[[
    dlac/jobhelpers/bst/jugs.lua -- the BST Helper's JUG data (issue #141, PRD
    #135: "the jug->pet-name mapping ships as module data").

    Two tables, and they answer two different questions:

      * M.PETS -- the JUG PET ROSTER. "Is a pet with this name a jug pet?" is
        the whole of the death classifier's jug-vs-charm rule: jug pets carry
        unique pet names, charmed pets keep their MOB names, so a name that is
        not on this roster is a charmed mob and the helper does nothing for it.
        Source: docs/reference/catseyexi-jobs.md, which is this SERVER's own
        published BST tables (28 pets, 14 families of NQ + HQ).

      * M.MAP -- the JUG -> PET mapping the picker shows. "Which pet does this
        broth call?" Nothing acts on this: it is the label beside the jug in the
        picker, so the player summons the pet they mean.

    WHAT IS NOT HERE, on purpose: the jugs themselves. The broth list, its item
    ids and its equip levels are the CATALOG's (gear\catalogindex -- the "what is
    this item?" central service), and a jug is exactly a BST-only Ammo item.
    Copying 98 rows of that in here would be a second catalog to keep in step.

    DATA AUTHORITY (hard rule 9, and the maintainer's ruling on this slice:
    live > wiki > repo, repo SQL is INHERITED BASE ONLY):
      * Levels come from the catalog (repo SQL = inherited base). A LIVE-OBSERVED
        level goes in M.LEVEL below as one row and wins -- CatsEyeXI tunes BST
        (its own wiki says Call Beast is acquired at 10 where the repo SQL says
        23, and the field tester HAS it at 21), so a catalog level is a starting
        point, never the answer.
      * The MAPPING is hand-transcribed and **FIELD-VERIFY BEFORE TRUST**. Each
        row carries where it came from: `cexi` = anchored by this server's own
        published tables (the Beast Raising HQ families, plus the enmity/stat
        tables that pair each NQ pet with its HQ); `era` = the 75-era jug table,
        consistent with those pairs but not independently confirmed here. Rows
        that could not be placed honestly are ABSENT rather than guessed -- the
        picker shows those jugs with no pet name, which is the true statement.
      * CatsEyeXI additionally advertises "Custom Jugs", which nothing in this
        repo describes. Another reason no row here is presented as fact.

    Pure at load; every require is call-time under pcall.
]]--

local M = {};

-- ---------------------------------------------------------------------------
-- the jug pet ROSTER -- the classifier's name authority
-- ---------------------------------------------------------------------------
--
-- The 14 NQ pets and their 14 HQ counterparts, verbatim from the server's own
-- BST tables. A pet name NOT on this list is a charmed mob (or a jug this list
-- has not caught up with, which is the same answer: the helper does nothing).
M.PETS = {
    'Sheep Familiar',   'Lullaby Melodia',
    'Hare Familiar',    'Keeneared Steffi',
    'Crab Familiar',    'Courier Carrie',
    'Tiger Familiar',   'Saber Siravarde',
    'Flowerpot Bill',   'Flowerpot Ben',
    'Lizard Familiar',  'Coldblood Como',
    'Mayfly Familiar',  'Shellbuster Orob',
    'Flytrap Familiar', 'Voracious Audrey',
    'Eft Familiar',     'Turbid Toloi',
    'Beetle Familiar',  'Panzer Galahad',
    'Mite Familiar',    'Lifedrinker Lars',
    'Antlion Familiar', 'Ambusher Allie',
    'Funguar Familiar', 'Chopsuey Chucky',
    'Homunculus',       'Amigo Sabotender',
};

-- ---------------------------------------------------------------------------
-- the JUG -> PET mapping (display only)
-- ---------------------------------------------------------------------------
--
-- Keyed by the catalog's own item Name. `src` records provenance (see the
-- header); NOTHING here is field-confirmed yet.
M.MAP = {
    -- anchored by this server's published tables (NQ/HQ family pairs)
    ['Carrot Broth']     = { pet = 'Hare Familiar',    src = 'cexi' },
    ['F. Carrot Broth']  = { pet = 'Keeneared Steffi', src = 'cexi' },
    ['Herbal Broth']     = { pet = 'Sheep Familiar',   src = 'cexi' },
    ['S. Herbal Broth']  = { pet = 'Lullaby Melodia',  src = 'cexi' },
    ['Humus']            = { pet = 'Flowerpot Bill',   src = 'cexi' },
    ['Rich Humus']       = { pet = 'Flowerpot Ben',    src = 'cexi' },
    ['Meat Broth']       = { pet = 'Tiger Familiar',   src = 'cexi' },
    ['W. Meat Broth']    = { pet = 'Saber Siravarde',  src = 'cexi' },
    ['Carrion Broth']    = { pet = 'Lizard Familiar',  src = 'cexi' },
    ['C. Carrion Broth'] = { pet = 'Coldblood Como',   src = 'cexi' },
    ['Bug Broth']        = { pet = 'Mayfly Familiar',  src = 'cexi' },
    ['Qdv. Bug Broth']   = { pet = 'Shellbuster Orob', src = 'cexi' },
    ['Fish Broth']       = { pet = 'Crab Familiar',    src = 'cexi' },
    ['Fish Oil Broth']   = { pet = 'Courier Carrie',   src = 'cexi' },
    ['Tree Sap']         = { pet = 'Beetle Familiar',  src = 'cexi' },
    ['Scarlet Sap']      = { pet = 'Panzer Galahad',   src = 'cexi' },
    ['Blood Broth']      = { pet = 'Mite Familiar',    src = 'cexi' },
    ['C. Blood Broth']   = { pet = 'Lifedrinker Lars', src = 'cexi' },
    -- 75-era transcription, consistent with those pairs, not confirmed here
    ['Grass. Broth']     = { pet = 'Flytrap Familiar', src = 'era' },
    ['N. Grass. Broth']  = { pet = 'Voracious Audrey', src = 'era' },
    ['Antica Broth']     = { pet = 'Antlion Familiar', src = 'era' },
    ['F. Antica Broth']  = { pet = 'Ambusher Allie',   src = 'era' },
    ['Mole Broth']       = { pet = 'Eft Familiar',     src = 'era' },
    ['L. Mole Broth']    = { pet = 'Turbid Toloi',     src = 'era' },
    ['Seedbed Soil']     = { pet = 'Funguar Familiar', src = 'era' },
    ['Alchemist Water']  = { pet = 'Homunculus',       src = 'era' },
};

-- LIVE-OBSERVED equip levels, item name -> level. Empty by design: not one
-- broth level has been read off the live server yet, so the catalog's
-- inherited-base level stands for all of them. A field session that finds a jug
-- equippable below (or above) its catalog level adds ONE row here and it wins
-- everywhere -- picker, gate and hover.
M.LEVEL = {};

-- THE LEVEL CEILING. CatsEyeXI is a 75-cap server, and the catalog is not: it
-- carries the full retail broth list, so 65 of its 98 BST-only Ammo rows are
-- Lv76-99 jugs nobody here can equip -- two thirds of the picker, none of them
-- mapped to a pet, all of them between the player and the jug they wanted
-- (maintainer's ruling 2026-07-30: "remove any jugs from the list that is above
-- level 75").
--
-- Applied against the level the row REPORTS, which is M.LEVEL's live-observed
-- value when there is one -- so a jug this server re-tuned down into reach is
-- kept by adding its one row above, not by moving this number. If the cap ever
-- rises, this is the single line to change.
M.MAX_LEVEL = 75;

-- ---------------------------------------------------------------------------
-- the roster question -- "is this pet a jug pet?"
-- ---------------------------------------------------------------------------

-- SQUASH a display name for COMPARISON ONLY: NULs out, every space removed,
-- lowercased.
--
-- THE SPACE IS THE WHOLE REASON THIS EXISTS (field, 2026-07-30, from a chat
-- line in a screenshot: *"The SheepFamiliar defeats the Clipper."*). The
-- client's entity name for a jug pet carries **no space** -- `SheepFamiliar` --
-- while every published table, this roster included, writes `Sheep Familiar`.
-- Compared raw, not one jug pet on this server matched its own roster entry, so
-- the loss classifier called every one of them a CHARMED pet and the Resummon
-- rule refused exactly as it is designed to for charm. A silent, total failure
-- of the feature, from one space.
--
-- Squashing rather than "inserting the spaces back" because the direction of the
-- difference is not ours to guess: whether a name is written apart or together
-- is a rendering choice on either side, and the letters are what identify a pet.
local function squash(s)
    if type(s) ~= 'string' then return nil; end
    local t = s:gsub('%z', ''):gsub('%s+', '');
    if t == '' then return nil; end
    return string.lower(t);
end
M._squash = squash;   -- test seam

local _roster = nil;
local function roster()
    if _roster == nil then
        _roster = {};
        for _, n in ipairs(M.PETS) do
            local k = squash(n);
            if k ~= nil then _roster[k] = true; end
        end
    end
    return _roster;
end

-- true = a jug pet, false = not one (a charmed mob keeps its mob name), nil =
-- no name to judge. `alsoPet` is one extra name that counts as a jug pet -- the
-- player's own configured jug maps to it, so a jug this roster has not caught
-- up with is still recognised when the player named it themselves.
function M.isJugPet(name, alsoPet)
    local n = squash(name);
    if n == nil then return nil; end
    if roster()[n] == true then return true; end
    local also = squash(alsoPet);
    if also ~= nil and also == n then return true; end
    return false;
end

-- The pet a jug calls, or nil when this jug is not mapped yet.
function M.petFor(itemName)
    if type(itemName) ~= 'string' then return nil; end
    local row = M.MAP[itemName];
    if type(row) ~= 'table' then return nil; end
    return row.pet;
end

-- Where a mapping row came from ('cexi' / 'era'), or nil for an unmapped jug.
function M.sourceFor(itemName)
    if type(itemName) ~= 'string' then return nil; end
    local row = M.MAP[itemName];
    if type(row) ~= 'table' then return nil; end
    return row.src;
end

-- ---------------------------------------------------------------------------
-- the jug LIST -- the catalog joined with the mapping (the picker's rows)
-- ---------------------------------------------------------------------------
--
-- A jug is a BST-only Ammo item AT OR UNDER THIS SERVER'S CAP (M.MAX_LEVEL):
-- BST-only Ammo is exactly the set of broths, humus, saps, soils and waters
-- Call Beast reads, and nothing else in the catalog matches it (pet food is
-- "All" jobs) -- but the catalog is retail's, so two thirds of that set is
-- Lv76-99 and unusable here. Reads are injected as a whole:
--   reads = { index = function() -> { [id] = raw catalog record }, .. }
-- so the whole list builds headlessly off a fixture.
--
-- Returns rows { id, name, level, pet, src }, sorted by level then name -- the
-- order a BST thinks in ("what can I use at my level?"), never catalog order.
--
-- The LIVE list is built once and kept: the catalog is a generated, static
-- table, and this walk is the whole of it -- the Panel redraws its picker every
-- frame and the stock read looks a jug up by name, so re-walking would be a
-- five-thousand-entry loop per frame for an answer that cannot change. An
-- INJECTED `reads` never touches the memo (tests get a fresh build every time).
local _liveList = nil;

function M.list(reads)
    if reads == nil and _liveList ~= nil then return _liveList; end
    local live = (reads == nil);
    reads = (type(reads) == 'table') and reads or M.liveReads();
    local index = (type(reads.index) == 'function') and reads.index or function() return {}; end
    local ok, byId = pcall(index);
    if not ok or type(byId) ~= 'table' then return {}; end

    local out = {};
    for id, rec in pairs(byId) do
        if type(rec) == 'table' and rec.Type == 'Ammo' and type(rec.Name) == 'string'
           and type(rec.Jobs) == 'table' and #rec.Jobs == 1 and rec.Jobs[1] == 'BST' then
            local lvl = tonumber(M.LEVEL[rec.Name]) or tonumber(rec.Level) or 0;
            -- Above this server's cap = not a jug anyone here can equip (see
            -- M.MAX_LEVEL). Dropped from the LIST, not hidden in the picker, so
            -- every consumer of the roster agrees about what exists.
            if lvl <= M.MAX_LEVEL then
                out[#out + 1] = { id = tonumber(id) or rec.Id, name = rec.Name, level = lvl,
                                  pet = M.petFor(rec.Name), src = M.sourceFor(rec.Name) };
            end
        end
    end
    -- Explicit ordering, never pairs() order (hard rule 8): level, then name,
    -- then id -- so two same-name rows (the catalog carries one duplicate name
    -- at two ids) still sort deterministically.
    table.sort(out, function(a, b)
        if a.level ~= b.level then return a.level < b.level; end
        if a.name  ~= b.name  then return a.name  < b.name;  end
        return (a.id or 0) < (b.id or 0);
    end);
    -- Only cache a list the CATALOG produced. An empty one means the catalog
    -- was not loadable yet (pre-login, headless) -- never latch that (hard rule
    -- 11: never latch a question you could not answer).
    if live and #out > 0 then _liveList = out; end
    return out;
end

-- Drop the cached live list (test seam; also the honest answer to a catalog
-- that has only just become loadable).
function M.forget() _liveList = nil; end

-- One jug by item NAME, or nil. Case-insensitive: the name travels through a
-- config file and a claim table, and a stored 'carrot broth' must still find
-- the row the picker wrote.
function M.find(itemName, reads)
    if type(itemName) ~= 'string' or itemName == '' then return nil; end
    local want = string.lower(itemName);
    for _, row in ipairs(M.list(reads)) do
        if string.lower(row.name) == want then return row; end
    end
    return nil;
end

function M.liveReads()
    return {
        index = function()
            local byId = {};
            pcall(function()
                local ci = require('dlac\\gear\\catalogindex');
                if type(ci) == 'table' and type(ci.rawIndex) == 'function' then byId = ci.rawIndex(); end
            end);
            return byId;
        end,
    };
end

return M;
