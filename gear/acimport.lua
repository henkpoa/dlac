--[[
    dlac/acimport.lua -- the pure Ashitacast (LegacyAC) XML -> sets transform.

    The third source in the Sets tab's "Copy from" picker, beside LuaAshitacast's
    statics and dlac's own pre-profile `sets.Dynamic` block. ASHITACAST is the
    legacy XML gear-swap format; on Ashita v4 it is served by the LegacyAC PLUGIN
    (plugins\LegacyAC.dll), whose swap files live one per character AND job at
    <install>\config\legacyac\<CharacterName>_<JOB>.xml. Schema authority ships
    with the install: Ashita\docs\LegacyAC\XML Structure.xml + readme.txt.

      parse(xmlText) -> ( sets  { name -> { slotLabel -> 'Item Name', ... } },
                          info  { name -> { base, augments, locks, slots } },
                          notes { string, ... } )

    Only <sets> is in scope. Everything else in such a file (premagic, midmagic,
    idlegear, inputcommands, init, variables, settings) is RULE logic -- dlac's
    Triggers/Automation territory, not the set importer's -- and is read past.

    The output is deliberately the shape dlac\gear\setimport.importStaticSet
    already eats: a plain `label -> value` table. A one-item-per-slot XML slot
    becomes a ONE-CANDIDATE list there, and gearui's resolveSetItem already
    resolves a bare NAME string against this character's owned gear
    (case-insensitively -- which the format needs: set and equipment names are
    explicitly NOT case sensitive, and real files are full of `hlr. cap +1`).
    So nothing downstream changed to accept these; a piece the player does not
    own is skipped exactly as it is for every other import source.

    Pure: no ImGui, no Ashita, no file IO -- the caller passes the file text.
    Addon-state only, and READ-ONLY: dlac never writes into the LegacyAC tree.
]]--

local M = {};

-- dlac slot label per Ashitacast slot tag. BOTH dialects are live: the spec
-- offers lear/rear + lring/rring and says "Ear1, Ear2, Ring1, Ring2 also work",
-- and a real file uses both at once (the WHM xml that drove this: ear1/ear2
-- inside <sets>, lring/rring in its <idlegear> rules). Any tag not in here --
-- <include>, <item>, <event>, a typo -- is simply not a slot and is ignored.
local SLOT = {
    main  = 'Main',  sub   = 'Sub',   range = 'Range', ammo  = 'Ammo',
    head  = 'Head',  neck  = 'Neck',  body  = 'Body',  hands = 'Hands',
    back  = 'Back',  waist = 'Waist', legs  = 'Legs',  feet  = 'Feet',
    lear  = 'Ear1',  rear  = 'Ear2',  ear1  = 'Ear1',  ear2  = 'Ear2',
    lring = 'Ring1', rring = 'Ring2', ring1 = 'Ring1', ring2 = 'Ring2',
};
M.SLOT = SLOT;

local function trim(s)
    return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''));
end

-- The five XML entities plus the numeric escapes. `&amp;` is decoded LAST or
-- `&amp;lt;` would decode twice into a literal '<'. The numeric forms are not
-- theoretical here: FFXI item names are full of apostrophes ("Genbu's Shield",
-- and gear.lua stores them WITH the apostrophe), so a generator that writes
-- &#39; would otherwise miss every owned record it names. Out-of-range code
-- points are left as written rather than folded into garbage.
local function unescape(s)
    local function chr(n)
        if n == nil or n < 0 or n > 255 then return nil; end
        return string.char(n);
    end
    s = s:gsub('&#[xX](%x+);', function(h) return chr(tonumber(h, 16)); end);
    s = s:gsub('&#(%d+);',     function(d) return chr(tonumber(d)); end);
    s = s:gsub('&lt;', '<'):gsub('&gt;', '>'):gsub('&quot;', '"'):gsub('&apos;', "'");
    s = s:gsub('&amp;', '&');
    return s;
end

-- Comments FIRST: these files are densely commented and the comments contain
-- tag-shaped text (the shipped spec sample comments out whole <equip> blocks),
-- so anything that scans tags before stripping them reads furniture as data.
-- The XML declaration and any doctype go the same way.
local function stripComments(text)
    text = text:gsub('<!%-%-.-%-%->', ' ');
    text = text:gsub('<%?.-%?>', ' ');
    text = text:gsub('<!DOCTYPE[^>]*>', ' ');
    return text;
end

-- Start index of the next `<name` open tag at/after `from`, where the character
-- after the name is not a name character. That last part is the whole point:
-- a plain find for '<set' also hits `<sets>` AND `<setvar name="macrobook">`,
-- and both ship in one real file (the latter inside its <init> block).
local function findTag(text, name, from)
    local i = from or 1;
    while true do
        local s = text:find('<' .. name, i, true);
        if s == nil then return nil; end
        local nxt = text:sub(s + #name + 1, s + #name + 1);
        if nxt == '' or nxt:match('[%s/>]') ~= nil then return s; end
        i = s + 1;
    end
end

-- One attribute off an open tag's inner text. Whitespace around '=' is legal
-- and appears in the wild (`baseset = "PrecastGeneral"`), and both quote styles
-- are accepted. The leading %s anchors the key so `set=` can never be read out
-- of `baseset=`.
local function attr(inner, key)
    local v = inner:match('%s' .. key .. '%s*=%s*"([^"]*)"');
    if v == nil then v = inner:match('%s' .. key .. "%s*=%s*'([^']*)'"); end
    return v;
end

-- The <sets> block, or nil when the file has no wrapper (then the caller scans
-- the whole document -- findTag already keeps <setvar> out of the results).
local function setsBlock(text)
    local s = findTag(text, 'sets', 1);
    if s == nil then return nil; end
    local e = text:find('>', s + 1, true);
    if e == nil then return nil; end
    local c = text:find('</sets', e + 1, true);
    return text:sub(e + 1, (c or (#text + 1)) - 1);
end

-- Walk each <set> in a block as (openTagInner, body). <set> elements never
-- nest, so the next `</set` closes the current one -- and because `</sets>`
-- matches that too, an unterminated final set is closed by the block's end
-- instead of swallowing the rest of the document.
local function eachSet(block, fn)
    local i = 1;
    while true do
        local s = findTag(block, 'set', i);
        if s == nil then break; end
        local e = block:find('>', s + 1, true);
        if e == nil then break; end
        local inner = block:sub(s + 1, e - 1);
        if trim(inner):sub(-1) == '/' then           -- <set name="DT" baseset="idle"/>
            fn(inner, '');
            i = e + 1;
        else
            local c = block:find('</set', e + 1, true);
            fn(inner, block:sub(e + 1, (c or (#block + 1)) - 1));
            i = (c ~= nil) and (c + 5) or (#block + 1);
        end
    end
end

-- Walk a <set> body's child elements as (lowercased tag, content, openTagInner).
-- Slot elements never nest, so CONTENT is everything up to the next '<' -- which
-- is also what makes this tolerant of the mis-nested closing tags the format is
-- riddled with. That tolerance is not defensive padding: the spec sample SHIPPED
-- with the plugin contains `<statusupdate>true</statuspdate>` and `</petsspell>`,
-- so a strict parser would reject files LegacyAC itself loads happily.
local function eachElement(body, fn)
    local i, n = 1, #body;
    while i <= n do
        local s = body:find('<', i, true);
        if s == nil then break; end
        local e = body:find('>', s + 1, true);
        if e == nil then break; end
        local inner = body:sub(s + 1, e - 1);
        local lead = inner:sub(1, 1);
        if lead ~= '/' and lead ~= '!' and lead ~= '?' then
            local tag = inner:match('^(%a[%w_%-]*)');
            if tag ~= nil then
                local content = '';
                if trim(inner):sub(-1) ~= '/' then       -- self-closing <range /> has none
                    local nxt = body:find('<', e + 1, true);
                    content = body:sub(e + 1, (nxt or (n + 1)) - 1);
                end
                fn(string.lower(tag), content, inner);
            end
        end
        i = e + 1;
    end
end

-- The pure transform. See the header. `sets` is never nil (an unreadable or
-- set-less file yields {} plus a note), so callers never branch on nil.
function M.parse(text)
    local sets, info, notes = {}, {}, {};
    if type(text) ~= 'string' or trim(text) == '' then
        notes[#notes + 1] = 'The file is empty.';
        return sets, info, notes;
    end
    local clean = stripComments(text);
    local block = setsBlock(clean) or clean;

    -- Pass 1: every <set> verbatim, own slots only.
    --   slots : label -> item name
    --   clear : label -> true, for a slot the set EMPTIES. `none` is a keyword,
    --           not an item (spec: <range>none</range> unequips), and an empty
    --           element says the same. This has to be a separate table, not an
    --           absent key: with a baseset, "not mentioned" inherits and
    --           "explicitly empty" must not.
    --   aug/lk: labels carrying an augment= fingerprint / a lock= attribute,
    --           tracked per slot so inheritance carries them and the count
    --           reported is the RESOLVED set's, not the tag soup's.
    local raw, order = {}, {};
    eachSet(block, function(inner, body)
        local name = trim(unescape(attr(inner, 'name') or ''));
        if name == '' then
            notes[#notes + 1] = 'Skipped a <set> with no name.';
            return;
        end
        local base = trim(attr(inner, 'baseset') or '');
        local rec = { name = name, base = (base ~= '') and base or nil,
                      slots = {}, clear = {}, aug = {}, lk = {} };
        if attr(inner, 'lock') ~= nil then rec.setLock = true; end
        eachElement(body, function(tag, content, sInner)
            local label = SLOT[tag];
            if label == nil then return; end
            local item = trim(unescape(content));
            if item == '' or string.lower(item) == 'none' then
                rec.slots[label] = nil;
                rec.clear[label] = true;
                rec.aug[label], rec.lk[label] = nil, nil;
                return;
            end
            rec.slots[label] = item;
            rec.clear[label] = nil;
            rec.aug[label] = (attr(sInner, 'augment') ~= nil) or nil;
            rec.lk[label]  = (attr(sInner, 'lock') ~= nil) or nil;
        end);
        local lk = string.lower(name);
        if raw[lk] == nil then
            order[#order + 1] = lk;
        else
            notes[#notes + 1] = string.format('"%s" is defined more than once -- the LAST one was imported.', name);
        end
        raw[lk] = rec;
    end);

    -- Pass 2: baseset. Deliberately a SECOND pass -- a base may be declared
    -- later in the file (the WHM xml inherits PrecastGeneral four sets before
    -- defining it) and chains are legal (MidcastCursna -> MidcastHeal). Names
    -- are compared case-insensitively, like every name rule in the format
    -- (`baseset="idle"` -> the set named `Idle`).
    local memo = {};
    local function resolve(lk, seen)
        if memo[lk] ~= nil then return memo[lk]; end
        local rec = raw[lk];
        if rec == nil then return nil; end
        local slots, aug, lock = {}, {}, {};
        if rec.base ~= nil then
            local bk = string.lower(rec.base);
            if seen[bk] then
                notes[#notes + 1] = string.format('"%s": its baseset chain loops back on itself (%s) -- the inherited half was dropped.', rec.name, rec.base);
            elseif raw[bk] == nil then
                notes[#notes + 1] = string.format('"%s": baseset "%s" is not in this file -- only its own slots were imported.', rec.name, rec.base);
            else
                seen[bk] = true;
                local b = resolve(bk, seen);
                seen[bk] = nil;
                if b ~= nil then
                    for k, v in pairs(b.slots) do slots[k] = v; end
                    for k, v in pairs(b.aug)   do aug[k]   = v; end
                    for k, v in pairs(b.lock)  do lock[k]  = v; end
                end
            end
        end
        for k, v in pairs(rec.slots) do slots[k] = v; end
        for k, v in pairs(rec.aug)   do aug[k]   = v; end
        for k, v in pairs(rec.lk)    do lock[k]  = v; end
        for k in pairs(rec.clear) do slots[k], aug[k], lock[k] = nil, nil, nil; end
        memo[lk] = { slots = slots, aug = aug, lock = lock };
        return memo[lk];
    end

    for _, lk in ipairs(order) do
        local rec = raw[lk];
        local r = resolve(lk, { [lk] = true }) or { slots = {}, aug = {}, lock = {} };
        local nSlots, nAug, nLock = 0, 0, 0;
        for _ in pairs(r.slots) do nSlots = nSlots + 1; end
        for _ in pairs(r.aug)   do nAug   = nAug + 1;   end
        for _ in pairs(r.lock)  do nLock  = nLock + 1;  end
        if rec.setLock then nLock = nLock + 1; end
        sets[rec.name] = r.slots;
        info[rec.name] = { base = rec.base, slots = nSlots, augments = nAug, locks = nLock };
    end

    if #order == 0 then
        notes[#notes + 1] = 'No <set> entries found -- is this an Ashitacast/LegacyAC swap file?';
    end
    table.sort(notes);   -- pairs() order is undefined; a stable display (hard rule 8)
    return sets, info, notes;
end

-- Sorted array of the parsed set names -- the picker's Ashitacast column.
function M.setNames(sets)
    local names = {};
    if type(sets) ~= 'table' then return names; end
    for k in pairs(sets) do names[#names + 1] = tostring(k); end
    table.sort(names, function(a, b)
        local la, lb = string.lower(a), string.lower(b);
        if la ~= lb then return la < lb; end
        return a < b;
    end);
    return names;
end

-- One player-facing sentence about what an imported set could NOT carry, or nil
-- when there is nothing to say. Two things in this format have no dlac
-- equivalent at import time:
--   augment=  a LegacyAC augment fingerprint (`/la print augs`) -- an opaque
--             plugin-internal code, not decodable against dlac's augment table,
--             so the BASE item is imported and the filter is lost.
--   lock=     LegacyAC's per-slot equip lock; in dlac a lock is an Arbiter claim,
--             not a property of a set.
-- Dropping either silently is the failure mode (hard rule 12), not the drop
-- itself -- a set that exists ONLY to pin an augment (the WHM xml has two)
-- otherwise arrives looking like a pointless one-piece set.
function M.dropNote(inf)
    if type(inf) ~= 'table' then return nil; end
    local bits = {};
    local a, l = tonumber(inf.augments) or 0, tonumber(inf.locks) or 0;
    if a > 0 then
        bits[#bits + 1] = string.format('%d piece%s had an augment filter (imported as the base item)',
            a, (a == 1) and '' or 's');
    end
    if l > 0 then
        bits[#bits + 1] = string.format('%d lock attribute%s dropped (a dlac lock is an Arbiter claim, not part of a set)',
            l, (l == 1) and '' or 's');
    end
    if #bits == 0 then return nil; end
    return table.concat(bits, '; ') .. '.';
end

return M;
