--[[
    dlac/gear/unusedgear.lua -- THE WARDROBE AUDIT: what is sitting in a Mog
    Wardrobe that nothing in dlac ever asks for?

    Henrik, 2026-08-03: "Mog Wardrobe space is limited and very important... it
    would be nice to know which pieces you have in mog wardrobes that are
    actively not being used at all, so you can put them in another container
    with less value, like mog safe, locker etc."

    This is gear/gearcheck.lua read backwards. Gearcheck starts from the sets
    your triggers use and asks "is every piece equippable right now?"; this
    starts from the BAG and asks "does anything reference this piece at all?" --
    across EVERY profile and EVERY job entry, not just the job you are on.

    THE WALK (all of it is existing machinery; nothing here re-derives storage):
      profiles.listProfilesAt / listProfileFilesAt   every profile x job entry,
                                                     dormant archives included
      -> triggers\<name>.lua   which SET NAMES the rules point at (+ inline equip)
      -> profiles.readSetsFile which items those sets name -- sandbox-loaded with
                               the real gear table, so `gear.Head.Faceguard_1`
                               arrives as the record with its Id (no text parsing)
      -> lockstyles\<name>.lua the boxes' pieces, by name
      -> the helper manifests  autogear.lua picks, ammostate ammo, fishstate
                               rod/bait, job-helper pins
      -> gearimport.ownedSplit().where   the LIVE per-container counts

    FOUR RULINGS (Henrik, 2026-08-03), each visible in the output:

    1. A set that NO rule points at does not make its pieces "used" -- but it
       does not make them junk either. Those pieces get their own section
       ("only in a set nothing triggers"), never the unused list.

    2. LOCKSTYLE PIECES DO NOT NEED A WARDROBE. Henrik: "you can lockstyle to
       pieces that are in the mog house etc." Confirmed in the server source, in
       TWO halves that must not be collapsed into one:
         * c2s/0x053_lockstyle.cpp (Set) stores the id after checking only that
           it is real equipment that fits the slot -- no ownership, no container.
         * charutils.cpp UpdateArmorStyle gates the RENDER on HasItem(PChar, id)
           + canEquipItemOnAnyJob -- and HasItem walks EVERY container
           (0..MAX_CONTAINER_ID), so where the piece sits is irrelevant while
           still OWNING it is not. Sell it and the slot renders empty.
       So a piece whose only job is a lockstyle box gets its own section and is
       REPORTED AS MOVEABLE -- move it anywhere, just keep it.

    3. Helper picks COUNT AS USE, named by helper: the MaxMP ladder, auto-staff /
       obi / grip, craft, HELM, fishing, chocobo, the per-job ammo lists, the
       fishing rod + bait, and a job helper's pinned item. dlac equips these
       without any set naming them, so calling them unused would be a lie.

    4. The window shows the LAST SAVED report and refreshes on request (a bag
       walk plus every profile's files is not a per-frame read), so the report
       is written to <char>\unusedreport.lua and survives a reload.

    WHAT IS DELIBERATELY NOT COUNTED AS USE (the no-silent-caps law -- every one
    of these is also a line in the report):
      * autogear's `mp` / `rf` / `mv` tables. They are name->value STAT CACHES
        the ladders score with, not pick lists (dispatch reads them as maps);
        `mpBest` is the pick list and IS counted.
      * E-Box restock staples and food history -- consumables. A Mog Wardrobe
        holds equipment only, so nothing they name can be in this report anyway.
      * Pins. pinwatch clears them on load: a pin is a this-session answer.
      * Other characters' profiles. A wardrobe belongs to one character.

    Pure data core: the walkers take tables and an id resolver, so the headless
    suite (UNU*) drives the whole classification with no Ashita at all. Every
    live read goes through M._src, the one seam (feature/report.lua's _fs idiom).

    ITERATION 1, ON PURPOSE (Henrik, 2026-08-03: "this is just a first iteration,
    we will most likely work on this more and combine features, especially when /
    if storage move is accepted"). Today the report only TELLS you; the obvious
    join is docs/design/storage-move.md -- the right-click "Move To ->" work,
    researched and designed but not built -- which would let a flagged row move
    itself to the Mog Safe from here. Nothing in this module assumes read-only:
    the rows carry id + container + copy count, which is exactly what a move
    needs. Keep new "what asks for an item" sources joining M.collect's buckets
    (and HELPER_PINS) rather than growing a second walk.
]]--

local M = {};

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

local _cfok, _cfmt = pcall(require, 'dlac\\chatfmt');
_cfok = _cfok and type(_cfmt) == 'table';
local function sayMsg(s)  if _cfok and _cfmt.msg  then _cfmt.msg(s);  else print('[dlac] ' .. s); end end
local function sayWarn(s) if _cfok and _cfmt.warn then _cfmt.warn(s); else print('[dlac] ' .. s); end end
local function sayGood(s) if _cfok and _cfmt.good then _cfmt.good(s); else print('[dlac] ' .. s); end end

M.FILE = 'unusedreport.lua';   -- the saved report, under the char's data home
M.VERSION = 1;                 -- report format

-- Reason lists are capped when they are STORED (an item can sit in forty sets;
-- the fortieth name tells the player nothing the first six did not).
M.MAX_WHY = 6;

-- ---------------------------------------------------------------------------
-- THE SOURCE SEAM. Every live read the audit makes, in one table, so the whole
-- walk is drivable headless. Tests swap members; production never touches them.
-- ---------------------------------------------------------------------------

M._src = {};

function M._src.profiles() return try('dlac\\profiles'); end
function M._src.gearTable() return try('dlac\\gear'); end

function M._src.now() return os.time(); end
function M._src.stamp() return os.date('%Y-%m-%d %H:%M:%S'); end

function M._src.charName()
    local prof = M._src.profiles();
    if prof ~= nil and type(prof.charName) == 'function' then
        local ok, n = pcall(prof.charName);
        if ok and type(n) == 'string' then return n; end
    end
    return 'unknown';
end

-- The live bag facts: { total, avail, where } in one pass (gearimport).
function M._src.split()
    local gi = try('dlac\\gear\\gearimport');
    if gi == nil or type(gi.ownedSplit) ~= 'function' then return nil; end
    local ok, s = pcall(gi.ownedSplit);
    return (ok and type(s) == 'table') and s or nil;
end

function M._src.containerName(cid)
    local gi = try('dlac\\gear\\gearimport');
    if gi ~= nil and type(gi.containerName) == 'function' then
        local ok, n = pcall(gi.containerName, cid);
        if ok and type(n) == 'string' then return n; end
    end
    return 'container ' .. tostring(cid);
end

-- THE WARDROBES: the equip-eligible bags that are not Inventory. Sourced from
-- the Gear Oracle's one list (issue #70) rather than re-stated here -- the
-- wardrobe ids are exactly "equippable, but not the bag you carry".
function M._src.wardrobeIds()
    local or_ = try('dlac\\gear\\gearoracle');
    local out = {};
    if or_ == nil or type(or_.equipBags) ~= 'function' then return out; end
    local ok, bags = pcall(or_.equipBags);
    if not ok or type(bags) ~= 'table' then return out; end
    for _, cid in ipairs(bags) do
        if cid ~= 0 then out[#out + 1] = cid; end
    end
    return out;
end

-- A dlac state file under this character's data home, loaded. nil when absent,
-- unreadable or not a table -- every caller treats that as "nothing pinned".
function M._src.stateTable(file)
    local prof = M._src.profiles();
    if prof == nil or type(prof.dataDir) ~= 'function' then return nil; end
    local d = nil;
    pcall(function() d = prof.dataDir(); end);
    if d == nil then return nil; end
    local chunk = loadfile(d .. file);
    if chunk == nil then return nil; end
    local ok, t = pcall(chunk);
    return (ok and type(t) == 'table') and t or nil;
end

-- What you are WEARING right now, through the oracle's door (never a raw
-- equipped-item read -- GRD1/GRD2). 16 slots; a slot that cannot be read is a
-- skip, not a zero.
function M._src.wornIds()
    local or_ = try('dlac\\gear\\gearoracle');
    local out = {};
    if or_ == nil or type(or_.wornItem) ~= 'function' then return out; end
    for i = 0, 15 do
        local ok, w = pcall(or_.wornItem, i);
        if ok and type(w) == 'table' and tonumber(w.id) ~= nil then out[#out + 1] = tonumber(w.id); end
    end
    return out;
end

-- The client's own item table -- the last resort for a name gear.lua has never
-- indexed, and for naming a bag id the character never scanned.
function M._src.resourceId(name)
    local id = nil;
    pcall(function()
        local r = AshitaCore:GetResourceManager():GetItemByName(name, 2)
               or AshitaCore:GetResourceManager():GetItemByName(name, 0);
        if r ~= nil then id = tonumber(r.Id); end
    end);
    return id;
end

function M._src.resourceName(id)
    local nm = nil;
    pcall(function()
        local r = AshitaCore:GetResourceManager():GetItemById(id);
        if r ~= nil and type(r.Name) == 'table' then nm = r.Name[1]; end
    end);
    return nm;
end

function M._src.write(path, text)
    local f = io.open(path, 'w');
    if f == nil then return false; end
    f:write(text); f:close();
    return true;
end

-- ---------------------------------------------------------------------------
-- name -> id, the house way (utils.resolveGearName's index, rebuilt per audit
-- so a scan mid-session is picked up). Lowercased, with an apostrophe-stripped
-- second tier -- set files and lockstyle boxes both carry hand-typed names
-- ("Garrison boots +1", "Warriors Axe").
-- ---------------------------------------------------------------------------

function M.buildResolver(gearTbl, fallback)
    local idx = {};
    local byId = {};
    if type(gearTbl) == 'table' and type(gearTbl.NameToObject) == 'table' then
        for k, v in pairs(gearTbl.NameToObject) do
            if type(k) == 'string' and type(v) == 'table' and tonumber(v.Id) ~= nil then
                local lc = string.lower(k);
                if idx[lc] == nil then idx[lc] = v; end
                local stripped = (string.gsub(lc, "'", ''));
                if idx[stripped] == nil then idx[stripped] = v; end
                if byId[tonumber(v.Id)] == nil then byId[tonumber(v.Id)] = v; end
            end
        end
    end
    local function idOf(name)
        if type(name) ~= 'string' or name == '' then return nil; end
        local lc = string.lower(name);
        local rec = idx[lc] or idx[(string.gsub(lc, "'", ''))];
        if rec ~= nil then return tonumber(rec.Id); end
        if type(fallback) == 'function' then
            local ok, id = pcall(fallback, name);
            if ok then return tonumber(id); end
        end
        return nil;
    end
    return idOf, byId;
end

-- ---------------------------------------------------------------------------
-- THE PURE WALKERS
-- ---------------------------------------------------------------------------

local VIRT_LEN = 5;   -- #'dlac:'

-- One authored slot entry -> item ids. The entry grammar is utils.slotLadder's
-- (that is the authority): a gear RECORD, a { gear = <ref>, mode/minLevel/... }
-- WRAPPER, a plain NAME string, or a 'dlac:<marker>|<fallback>' VIRTUAL -- and a
-- slot may hold a LIST of any of those. A marker alone names no item (what it
-- resolves to is the helper manifest's business, counted separately); its
-- composed fallback does.
local function entryIds(v, idOf, emit, depth)
    depth = (depth or 0) + 1;
    if depth > 5 then return; end
    local t = type(v);
    if t == 'string' then
        local nm = v;
        if string.lower(string.sub(nm, 1, VIRT_LEN)) == 'dlac:' then
            nm = string.match(nm, '|(.+)$');
        end
        if nm ~= nil and nm ~= '' then
            local id = idOf(nm);
            if id ~= nil then emit(id); end
        end
        return;
    end
    if t ~= 'table' then return; end
    -- wrapper first: utils treats a table with .gear and no .Name as one
    if v.gear ~= nil and v.Name == nil then
        entryIds(v.gear, idOf, emit, depth);
        return;
    end
    if v.Id ~= nil or v.Name ~= nil then
        local id = tonumber(v.Id);
        if id == nil and type(v.Name) == 'string' then id = idOf(v.Name); end
        if id ~= nil then emit(id); end
        return;
    end
    for _, e in pairs(v) do entryIds(e, idOf, emit, depth); end
end
M._entryIds = entryIds;

-- Every item id one SET names (slot -> entry | list of entries).
function M.setIds(setTbl, idOf, emit)
    if type(setTbl) ~= 'table' then return; end
    for _, slotVal in pairs(setTbl) do entryIds(slotVal, idOf, emit, 0); end
end

-- Which SET NAMES a trigger file points at, and its inline equip tables.
-- Returns (setNames map, inline array). Modes/Groups carry no gear.
function M.triggerRefs(raw)
    local sets, inline = {}, {};
    if type(raw) ~= 'table' then return sets, inline; end
    for h, rules in pairs(raw) do
        if h ~= 'Modes' and h ~= 'Groups' and type(rules) == 'table' then
            for i, r in ipairs(rules) do
                if type(r) == 'table' then
                    local sn = r.set;
                    if type(sn) == 'string' then
                        sets[sn] = true;
                    elseif type(sn) == 'table' then
                        for _, s in ipairs(sn) do
                            if type(s) == 'string' then sets[s] = true; end
                        end
                    end
                    if type(r.equip) == 'table' then
                        inline[#inline + 1] = { handler = tostring(h), idx = i, equip = r.equip };
                    end
                end
            end
        end
    end
    return sets, inline;
end

-- Every piece named by a lockstyle boxes file -> emit(id, 'box N').
function M.lockstyleIds(raw, idOf, emit)
    if type(raw) ~= 'table' or type(raw.slots) ~= 'table' then return; end
    for n, box in pairs(raw.slots) do
        if type(box) == 'table' and type(box.set) == 'table' then
            local label = 'box ' .. tostring(n);
            if type(box.name) == 'string' and box.name ~= '' then
                label = label .. ' "' .. box.name .. '"';
            end
            for _, nm in pairs(box.set) do
                if type(nm) == 'string' and nm ~= '' then
                    local id = idOf(nm);
                    if id ~= nil then emit(id, label); end
                end
            end
        end
    end
end

-- The gear-helper manifest (autogear.lua) -> emit(id, 'helper label').
-- ONLY the pick lists; the name->value stat caches (mp / rf / mv) are not use.
function M.manifestIds(auto, idOf, emit)
    if type(auto) ~= 'table' then return; end
    local function one(rec, label)
        if type(rec) ~= 'table' or type(rec.name) ~= 'string' then return; end
        local id = idOf(rec.name);
        if id ~= nil then emit(id, label); end
    end
    local function list(l, label)
        if type(l) ~= 'table' then return; end
        for _, rec in pairs(l) do one(rec, label); end
    end
    one(auto.oneiros,      'auto-grip');
    one(auto.universal,    'auto-staff');
    one(auto.obiUniversal, 'auto-obi');
    list(auto.universals,  'auto-staff');
    if type(auto.staff) == 'table' then
        for el, rec in pairs(auto.staff) do one(rec, 'auto-staff (' .. tostring(el) .. ')'); end
    end
    if type(auto.obi) == 'table' then
        for el, rec in pairs(auto.obi) do one(rec, 'auto-obi (' .. tostring(el) .. ')'); end
    end
    if type(auto.mpBest) == 'table' then
        for _, l in pairs(auto.mpBest) do list(l, 'MaxMP ladder'); end
    end
    if type(auto.craft) == 'table' then
        for _, byCraft in pairs(auto.craft) do
            if type(byCraft) == 'table' then
                for craft, byGoal in pairs(byCraft) do
                    if type(byGoal) == 'table' then
                        for _, l in pairs(byGoal) do list(l, 'craft gear (' .. tostring(craft) .. ')'); end
                    end
                end
            end
        end
    end
    if type(auto.helm) == 'table' then
        for k, v in pairs(auto.helm) do
            if k == 'hats' and type(v) == 'table' then
                for g, rec in pairs(v) do one(rec, 'HELM gear (' .. tostring(g) .. ')'); end
            else
                list(v, 'HELM gear');
            end
        end
    end
    if type(auto.fish) == 'table' then
        for _, l in pairs(auto.fish) do list(l, 'fishing gear'); end
    end
    if type(auto.choco) == 'table' then
        for _, l in pairs(auto.choco) do list(l, 'chocobo gear'); end
    end
end

-- The per-job ammo rule lists (ammostate.lua) -> emit(id, 'ammo list (JOB)').
function M.ammoIds(state, emit)
    if type(state) ~= 'table' or type(state.jobs) ~= 'table' then return; end
    for job, entry in pairs(state.jobs) do
        if type(entry) == 'table' and type(entry.ammo) == 'table' then
            for _, a in ipairs(entry.ammo) do
                if type(a) == 'table' and tonumber(a.id) ~= nil then
                    emit(tonumber(a.id), 'ammo list (' .. tostring(job) .. ')');
                end
            end
        end
    end
end

-- The fishing rod + bait (fishstate.lua). Ids are stamped at pick time; the
-- names are the fallback for a state file written before they were.
function M.fishIds(state, idOf, emit)
    if type(state) ~= 'table' then return; end
    local function pick(id, name, label)
        local n = tonumber(id);
        if n == nil and type(name) == 'string' then n = idOf(name); end
        if n ~= nil then emit(n, label); end
    end
    pick(state.rodId,  state.rod,  'fishing rod');
    pick(state.baitId, state.bait, 'fishing bait');
end

-- Job-helper state pins. DECLARED, not sniffed: a helper's config is free-form,
-- so each pinned field is named here with what it means. `items` are item names,
-- `sets` are set names the helper equips without any trigger rule naming them
-- (BST's summonSet is exactly that -- it would otherwise read as an orphan set).
-- A new helper with pins adds a row; nothing else changes.
M.HELPER_PINS = {
    { file = 'jobhelper-bst.lua', label = 'BST helper',
      items = { 'resummonJug' }, sets = { 'summonSet' } },
};

-- ---------------------------------------------------------------------------
-- THE COLLECTOR (pure). Everything that can ask for an item, folded into three
-- buckets keyed by item id:
--    live   -- a set a rule points at, an inline equip, a helper, worn now
--    orphan -- ONLY a set that no rule points at (ruling 1)
--    style  -- ONLY a lockstyle box (ruling 2)
-- ---------------------------------------------------------------------------

local function note(bucket, id, why)
    local l = bucket[id];
    if l == nil then l = {}; bucket[id] = l; end
    l[#l + 1] = why;
end

-- input = {
--   entries  = { { profile, name, sets, triggers, lockstyles } ... }
--   autogear, ammo, fish, helpers = { { label, items = {name}, sets = {name} } }
--   worn     = { id ... }
--   pairSets = { setName ... }   -- named by config, not by a rule (mpPairIdle)
--   idOf     = function(name) -> id
-- }
function M.collect(input)
    input = (type(input) == 'table') and input or {};
    local idOf = (type(input.idOf) == 'function') and input.idOf or function() return nil; end;
    local out = {
        live = {}, orphan = {}, style = {},
        stats = { profiles = 0, entries = 0, sets = 0, usedSets = 0, orphanSets = 0,
                  rules = 0, boxes = 0, missingSets = 0 },
    };

    -- Set names claimed by configuration rather than by a rule (the MaxMP pair
    -- home, a job helper's summon set): they are as live as a triggered set.
    local configSets = {};
    for _, s in ipairs(input.pairSets or {}) do
        if type(s) == 'string' then configSets[s] = 'the MaxMP ladder pairs into it'; end
    end
    for _, h in ipairs(input.helpers or {}) do
        for _, s in ipairs(h.sets or {}) do
            if type(s) == 'string' then configSets[s] = tostring(h.label) .. ' equips it'; end
        end
    end

    local seenProfiles = {};
    for _, e in ipairs(input.entries or {}) do
        out.stats.entries = out.stats.entries + 1;
        if e.profile ~= nil and not seenProfiles[e.profile] then
            seenProfiles[e.profile] = true;
            out.stats.profiles = out.stats.profiles + 1;
        end
        local where = tostring(e.profile or '?') .. '/' .. tostring(e.name or '?');

        local refs, inline = M.triggerRefs(e.triggers);
        for _, iv in ipairs(inline) do
            out.stats.rules = out.stats.rules + 1;
            M.setIds(iv.equip, idOf, function(id)
                note(out.live, id, where .. ' inline rule #' .. tostring(iv.idx)
                     .. ' (' .. tostring(iv.handler) .. ')');
            end);
        end

        if type(e.sets) == 'table' then
            for setName, setTbl in pairs(e.sets) do
                if type(setTbl) == 'table' then
                    out.stats.sets = out.stats.sets + 1;
                    local cfg = configSets[setName];
                    if refs[setName] or cfg ~= nil then
                        out.stats.usedSets = out.stats.usedSets + 1;
                        local why = where .. ' set ' .. tostring(setName)
                                    .. ((cfg ~= nil and not refs[setName]) and (' -- ' .. cfg) or '');
                        M.setIds(setTbl, idOf, function(id) note(out.live, id, why); end);
                    else
                        out.stats.orphanSets = out.stats.orphanSets + 1;
                        local why = where .. ' set ' .. tostring(setName);
                        M.setIds(setTbl, idOf, function(id) note(out.orphan, id, why); end);
                    end
                end
            end
        end
        -- A rule pointing at a set that is not in the file is gearcheck's
        -- business (it warns), but it is counted here so the header's set
        -- numbers add up to what the player can see.
        for setName in pairs(refs) do
            if type(e.sets) ~= 'table' or type(e.sets[setName]) ~= 'table' then
                out.stats.missingSets = out.stats.missingSets + 1;
            end
        end

        if e.lockstyles ~= nil then
            M.lockstyleIds(e.lockstyles, idOf, function(id, label)
                out.stats.boxes = out.stats.boxes + 1;
                note(out.style, id, where .. ' lockstyle ' .. tostring(label));
            end);
        end
    end

    M.manifestIds(input.autogear, idOf, function(id, label) note(out.live, id, label); end);
    M.ammoIds(input.ammo, function(id, label) note(out.live, id, label); end);
    M.fishIds(input.fish, idOf, function(id, label) note(out.live, id, label); end);
    for _, h in ipairs(input.helpers or {}) do
        for _, nm in ipairs(h.items or {}) do
            local id = idOf(nm);
            if id ~= nil then note(out.live, id, tostring(h.label) .. ' pin'); end
        end
    end
    for _, id in ipairs(input.worn or {}) do
        if tonumber(id) ~= nil then note(out.live, tonumber(id), 'worn right now'); end
    end
    return out;
end

-- ---------------------------------------------------------------------------
-- CLASSIFY. `bags` is { [id] = { [cid] = n } } for WARDROBE containers only.
-- Rows come back sorted: wardrobe id, then item name.
-- ---------------------------------------------------------------------------

local function capped(list)
    local out, n = {}, #list;
    for i = 1, math.min(n, M.MAX_WHY) do out[i] = list[i]; end
    if n > M.MAX_WHY then out[#out + 1] = string.format('...and %d more', n - M.MAX_WHY); end
    return out;
end

function M.classify(collected, bags, nameOf, recOf)
    collected = (type(collected) == 'table') and collected or { live = {}, orphan = {}, style = {} };
    local rows, counts = {}, { total = 0, used = 0, unused = 0, orphan = 0, style = 0 };
    for id, where in pairs(bags or {}) do
        counts.total = counts.total + 1;
        local cls, why = nil, nil;
        if collected.live[id] ~= nil then
            cls = 'used'; why = collected.live[id];
        elseif collected.orphan[id] ~= nil then
            cls = 'orphan'; why = collected.orphan[id];
        elseif collected.style[id] ~= nil then
            cls = 'style'; why = collected.style[id];
        else
            cls = 'unused'; why = {};
        end
        counts[cls] = (counts[cls] or 0) + 1;
        if cls ~= 'used' then
            local rec = (type(recOf) == 'function') and recOf(id) or nil;
            local locs = {};
            for cid, n in pairs(where) do locs[#locs + 1] = { cid = cid, n = n }; end
            table.sort(locs, function(a, b) return a.cid < b.cid; end);
            -- a lockstyle-only piece is ALSO worth showing when the same piece
            -- sits in an orphan set: both reasons travel, the class is the
            -- stronger one.
            local extra = (cls == 'orphan') and collected.style[id] or nil;
            local all = why;
            if extra ~= nil then
                all = {};
                for _, w in ipairs(why) do all[#all + 1] = w; end
                for _, w in ipairs(extra) do all[#all + 1] = w; end
            end
            rows[#rows + 1] = {
                id = id,
                name = ((type(nameOf) == 'function') and nameOf(id)) or ('item ' .. tostring(id)),
                cls = cls,
                lv = (type(rec) == 'table') and tonumber(rec.Level) or nil,
                jobs = (type(rec) == 'table' and type(rec.Jobs) == 'table')
                       and table.concat(rec.Jobs, ',') or nil,
                where = locs,
                why = capped(all),
            };
        end
    end
    table.sort(rows, function(a, b)
        local ca = (a.where[1] ~= nil) and a.where[1].cid or 99;
        local cb = (b.where[1] ~= nil) and b.where[1].cid or 99;
        if ca ~= cb then return ca < cb; end
        if a.name ~= b.name then return a.name < b.name; end
        return (a.id or 0) < (b.id or 0);
    end);
    return rows, counts;
end

-- ---------------------------------------------------------------------------
-- THE LIVE AUDIT
-- ---------------------------------------------------------------------------

-- Every job entry of every profile on THIS character, with its three files
-- loaded. listProfileFilesAt is the real listing (dormant archives included);
-- when the listing API fails it falls back to profiles' deterministic 22-job
-- probe, so a broken get_dir costs the archives, never the whole audit.
function M.readEntries()
    local prof = M._src.profiles();
    if prof == nil then return {}, 'the profiles module is not loaded'; end
    local cur = nil;
    pcall(function() cur = prof.currentCharFolder(); end);
    if cur == nil then return {}, 'not logged in yet'; end

    local names = nil;
    pcall(function() names = prof.listProfilesAt(cur); end);
    if type(names) ~= 'table' or #names == 0 then
        local act = nil;
        pcall(function() act = prof.activeName(); end);
        names = { act or 'Default' };
    end

    local function loadTable(path)
        if path == nil then return nil; end
        local chunk = loadfile(path);
        if chunk == nil then return nil; end
        local ok, t = pcall(chunk);
        return (ok and type(t) == 'table') and t or nil;
    end

    local out = {};
    for _, pname in ipairs(names) do
        local files = nil;
        pcall(function() files = prof.listProfileFilesAt(cur, pname); end);
        if type(files) ~= 'table' or #files == 0 then
            local probe = nil;
            pcall(function() probe = prof.profileJobsAt(cur, pname); end);
            files = {};
            for _, e in ipairs(probe or {}) do
                files[#files + 1] = { name = e.job, sets = e.sets, trig = e.trig, ls = e.ls };
            end
        end
        for _, f in ipairs(files) do
            local e = { profile = pname, name = f.name };
            if f.sets then
                pcall(function() e.sets = prof.readSetsFile(f.name, pname); end);
            end
            if f.trig then
                pcall(function() e.triggers = loadTable(prof.triggersPath(f.name, pname)); end);
            else
                -- the engine's own read fallback: a job with no profile trigger
                -- file still runs the pre-storage-layer one
                pcall(function() e.triggers = loadTable(prof.legacyTriggersPath(f.name)); end);
            end
            if f.ls then
                pcall(function() e.lockstyles = loadTable(prof.lockstylesPath(f.name, pname)); end);
            end
            out[#out + 1] = e;
        end
    end
    return out, nil;
end

-- Build the report. Returns report | nil, why.
function M.build()
    local split = M._src.split();
    if split == nil or type(split.where) ~= 'table' then
        return nil, 'your bags could not be read (log in first?)';
    end
    -- No wardrobe list = the oracle could not answer, and an empty report would
    -- read as "everything you own is in use" -- the one wrong answer this
    -- command must never give. Refuse instead.
    local wardIds = M._src.wardrobeIds();
    if type(wardIds) ~= 'table' or #wardIds == 0 then
        return nil, 'the wardrobe list is unavailable (the gear oracle could not answer)';
    end
    local entries, why = M.readEntries();
    if why ~= nil then return nil, why; end

    local gearTbl = M._src.gearTable();
    local idOf, byId = M.buildResolver(gearTbl, M._src.resourceId);

    local auto = M._src.stateTable('autogear.lua');
    local helpers = {};
    for _, pin in ipairs(M.HELPER_PINS) do
        local st = M._src.stateTable(pin.file);
        if st ~= nil then
            local h = { label = pin.label, items = {}, sets = {} };
            for _, k in ipairs(pin.items or {}) do
                if type(st[k]) == 'string' then h.items[#h.items + 1] = st[k]; end
            end
            for _, k in ipairs(pin.sets or {}) do
                if type(st[k]) == 'string' then h.sets[#h.sets + 1] = st[k]; end
            end
            helpers[#helpers + 1] = h;
        end
    end

    local pairSets = {};
    if type(auto) == 'table' then
        if type(auto.mpPairIdle) == 'string' then pairSets[#pairSets + 1] = auto.mpPairIdle; end
        if type(auto.mpPairIdleOverride) == 'string' then pairSets[#pairSets + 1] = auto.mpPairIdleOverride; end
    end

    local collected = M.collect({
        entries  = entries,
        autogear = auto,
        ammo     = M._src.stateTable('ammostate.lua'),
        fish     = M._src.stateTable('fishstate.lua'),
        helpers  = helpers,
        pairSets = pairSets,
        worn     = M._src.wornIds(),
        idOf     = idOf,
    });

    -- The wardrobe slice of the bag walk.
    local wardrobes, bags = {}, {};
    for _, cid in ipairs(wardIds) do
        wardrobes[#wardrobes + 1] = { cid = cid, name = M._src.containerName(cid), items = 0, flagged = 0 };
    end
    local wIndex = {};
    for _, w in ipairs(wardrobes) do wIndex[w.cid] = w; end
    for id, where in pairs(split.where) do
        local mine = nil;
        for cid, n in pairs(where) do
            if wIndex[cid] ~= nil then
                mine = mine or {};
                mine[cid] = n;
                wIndex[cid].items = wIndex[cid].items + n;
            end
        end
        if mine ~= nil then bags[id] = mine; end
    end

    local function nameOf(id)
        local rec = byId[id];
        if type(rec) == 'table' and type(rec.Name) == 'string' then return rec.Name; end
        local rn = M._src.resourceName(id);
        if type(rn) == 'string' and rn ~= '' then return rn; end
        return 'item ' .. tostring(id);
    end
    local rows, counts = M.classify(collected, bags, nameOf, function(id) return byId[id]; end);
    for _, r in ipairs(rows) do
        for _, w in ipairs(r.where) do
            if wIndex[w.cid] ~= nil then wIndex[w.cid].flagged = wIndex[w.cid].flagged + w.n; end
        end
    end

    return {
        v       = M.VERSION,
        at      = M._src.now(),
        stamp   = M._src.stamp(),
        char    = M._src.charName(),
        stats   = collected.stats,
        counts  = counts,
        wardrobes = wardrobes,
        rows    = rows,
    }, nil;
end

-- ---------------------------------------------------------------------------
-- PERSISTENCE. A plain Lua table beside the other per-character state files, so
-- the window has something to show the moment it opens (ruling 4) and a player
-- can read it without dlac running.
-- ---------------------------------------------------------------------------

function M.path()
    local prof = M._src.profiles();
    if prof == nil or type(prof.dataDir) ~= 'function' then return nil; end
    local d = nil;
    pcall(function() d = prof.dataDir(); end);
    return d and (d .. M.FILE) or nil;
end

function M.serialize(rep)
    local L = {};
    L[#L + 1] = '-- dlac wardrobe audit -- written by /dl unused. Regenerated on every Refresh.';
    L[#L + 1] = '-- Lockstyle-only pieces are listed as MOVEABLE: the server checks that you still';
    L[#L + 1] = '-- OWN the piece (any container at all), never which container it is in.';
    L[#L + 1] = 'return {';
    L[#L + 1] = string.format('    v = %d, at = %d, stamp = %q, char = %q,',
        tonumber(rep.v) or M.VERSION, tonumber(rep.at) or 0, tostring(rep.stamp or ''), tostring(rep.char or ''));
    local st = rep.stats or {};
    L[#L + 1] = string.format('    stats = { profiles = %d, entries = %d, sets = %d, usedSets = %d, orphanSets = %d, rules = %d, boxes = %d, missingSets = %d },',
        st.profiles or 0, st.entries or 0, st.sets or 0, st.usedSets or 0, st.orphanSets or 0,
        st.rules or 0, st.boxes or 0, st.missingSets or 0);
    local c = rep.counts or {};
    L[#L + 1] = string.format('    counts = { total = %d, used = %d, unused = %d, orphan = %d, style = %d },',
        c.total or 0, c.used or 0, c.unused or 0, c.orphan or 0, c.style or 0);
    L[#L + 1] = '    wardrobes = {';
    for _, w in ipairs(rep.wardrobes or {}) do
        L[#L + 1] = string.format('        { cid = %d, name = %q, items = %d, flagged = %d },',
            w.cid or 0, tostring(w.name or ''), w.items or 0, w.flagged or 0);
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '    rows = {';
    for _, r in ipairs(rep.rows or {}) do
        local locs = {};
        for _, w in ipairs(r.where or {}) do
            locs[#locs + 1] = string.format('{ cid = %d, n = %d }', w.cid or 0, w.n or 1);
        end
        local whys = {};
        for _, w in ipairs(r.why or {}) do whys[#whys + 1] = string.format('%q', tostring(w)); end
        L[#L + 1] = string.format('        { id = %d, name = %q, cls = %q, lv = %s, jobs = %s, where = { %s }, why = { %s } },',
            r.id or 0, tostring(r.name or ''), tostring(r.cls or 'unused'),
            (r.lv ~= nil) and tostring(r.lv) or 'nil',
            (r.jobs ~= nil) and string.format('%q', r.jobs) or 'nil',
            table.concat(locs, ', '), table.concat(whys, ', '));
    end
    L[#L + 1] = '    },';
    L[#L + 1] = '};';
    return table.concat(L, '\n') .. '\n';
end

function M.save(rep)
    if type(rep) ~= 'table' then return false, 'nothing to save'; end
    local p = M.path();
    if p == nil then return false, 'not logged in'; end
    local ok = M._src.write(p, M.serialize(rep));
    return ok, ok and p or ('could not write ' .. p);
end

-- The saved report, or nil. Cached in memory so the window's per-frame read is
-- free; M.forget() drops it (a Refresh replaces it outright).
--
-- The cache is keyed by CHARACTER. The addon state outlives a character switch,
-- and a wardrobe belongs to one character -- a cache that did not notice would
-- show someone else's bags, which is the worst thing this window could do.
local _cache, _cacheFor = nil, nil;
local function whoFor()
    local prof = M._src.profiles();
    if prof == nil or type(prof.charFolder) ~= 'function' then return nil; end
    local cf = nil;
    pcall(function() cf = prof.charFolder(); end);
    return cf;
end
function M.load()
    local who = whoFor();
    if _cache ~= nil and _cacheFor == who then return _cache; end
    _cache, _cacheFor = nil, who;
    local p = M.path();
    if p == nil then return nil; end
    local chunk = loadfile(p);
    if chunk == nil then return nil; end
    local ok, t = pcall(chunk);
    if ok and type(t) == 'table' and type(t.rows) == 'table' then _cache = t; end
    return _cache;
end
function M.forget() _cache, _cacheFor = nil, nil; end
function M.cached() return _cache; end

-- Build + save + cache. Returns report | nil, why.
function M.refresh()
    local rep, why = M.build();
    if rep == nil then return nil, why; end
    _cache, _cacheFor = rep, whoFor();
    local ok, err = M.save(rep);
    if not ok then rep.saveError = err; end
    return rep, nil;
end

-- ---------------------------------------------------------------------------
-- chat
-- ---------------------------------------------------------------------------

function M.summaryLines(rep)
    if type(rep) ~= 'table' then return { 'no wardrobe report yet -- /dl unused scan builds one.' }; end
    local c = rep.counts or {};
    local s = rep.stats or {};
    local out = {};
    out[#out + 1] = string.format('wardrobe audit (%s): %d items across your wardrobes, %d of them referenced.',
        tostring(rep.stamp or '?'), c.total or 0, c.used or 0);
    out[#out + 1] = string.format('  %d used by nothing at all | %d only in a set no rule triggers | %d only in a lockstyle box.',
        c.unused or 0, c.orphan or 0, c.style or 0);
    out[#out + 1] = string.format('  read %d profile(s), %d job entr(ies), %d set(s) -- %d triggered, %d untriggered.',
        s.profiles or 0, s.entries or 0, s.sets or 0, s.usedSets or 0, s.orphanSets or 0);
    if (c.style or 0) > 0 then
        out[#out + 1] = '  lockstyle-only pieces are safe to MOVE (any container works) -- but keep them: the style needs you to own it.';
    end
    return out;
end

-- ---------------------------------------------------------------------------
-- /dl unused [scan]
--   bare  -- open (or close) the window on the LAST SAVED report; builds one
--            the first time, because an empty window would say nothing.
--   scan  -- rebuild now, save, and answer in chat as well.
-- ---------------------------------------------------------------------------

function M.command(word)
    word = tostring(word or '');
    if word == 'scan' or word == 'refresh' or word == 'now' or word == 'rescan' then
        local rep, why = M.refresh();
        if rep == nil then
            sayWarn('wardrobe audit: ' .. tostring(why));
            return;
        end
        for i, line in ipairs(M.summaryLines(rep)) do
            if i == 1 then sayGood(line); else sayMsg(line); end
        end
        if rep.saveError ~= nil then sayWarn('  (the report could not be saved: ' .. tostring(rep.saveError) .. ')'); end
        return;
    end
    -- bare: the window
    local ui = try('dlac\\ui\\unusedui');
    if ui == nil or type(ui.toggle) ~= 'function' or ui.degraded == true then
        -- no GUI (headless / a broken ui module): answer in chat rather than nothing
        local rep = M.load() or M.refresh();
        for _, line in ipairs(M.summaryLines(rep)) do sayMsg(line); end
        return;
    end
    local open = ui.toggle();
    if open and M.load() == nil then
        local rep, why = M.refresh();
        if rep == nil then sayWarn('wardrobe audit: ' .. tostring(why)); end
    end
end

ashita.events.register('command', 'dlac-unusedgear-cmd', function(e)
    pcall(function()
        local raw = string.lower(e.command or '');
        local a, b = raw:match('^/dl%s+(%S+)%s*(%S*)');
        if a == nil then a, b = raw:match('^/dlac%s+(%S+)%s*(%S*)'); end
        if a ~= 'unused' and a ~= 'wardrobe' then return; end
        e.blocked = true;
        M.command(b);
    end);
end);

return M;
