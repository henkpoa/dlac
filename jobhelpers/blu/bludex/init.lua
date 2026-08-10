--[[
    Bludex as a dlac Job helper module -- the api = 2 contract adapter.

    THIS FILE IS AUTHORED IN THE BLUDEX REPO (dlacmodule/init.lua) and lands
    in dlac at jobhelpers\blu\bludex\init.lua via the sync workflow, next to
    the vendored library (lib/ ui/ data/ icons/). Do not hand-edit the copy
    in dlac; see VENDORED.md there.

    The approval envelope (what this module DOES) is documented for review
    in README.md beside this file. In one breath: it renders the Blue Magic
    codex/set-planner Panel, reads the client's own BLU structs, and -- only
    on the player's explicit Apply, or the level-change rule carried by the
    set they last applied (Restore / Lvl Set Switch / Manual) -- sets/unsets
    Blue Magic spells through the client's own 0x102 path, one spell per
    packet, paced. Nothing acts until a set has been applied by hand at least
    once. It never equips gear and never opens an Action sequence.

    Contract notes, per the authoring guide:
    - Panels may not open windows: the library renders with embedded = true
      (the codex detail becomes an in-panel pane).
    - The framework store is scalars-only: saved sets and the last-applied
      snapshot are encoded as strings by the codec below.
    - The library UI is bludex's own kit over ctx.imgui (the host's handle;
      never a required copy). The kit carries the same field laws as
      panelkit -- printf-escape on every drawn string, presence-guards,
      measured widths -- it is dlac's craftbar lineage, blue-shifted.
    - All player-facing strings: PROPOSED, pending maintainer sign-off.
]]--

local ROOT = (...):sub(1, -#('init') - 1);   -- rename-safe, like S.sibling

-- ---------------------------------------------------------------------------
-- the vendored library, loaded lazily and contained
-- ---------------------------------------------------------------------------
local lib = nil;

local function loadLib()
    if lib ~= nil then return lib; end
    local ok, t = pcall(function()
        return {
            host = require(ROOT .. 'ui\\host'),
            book = require(ROOT .. 'lib\\spellbook'),
            blu  = require(ROOT .. 'lib\\blu'),
            sets = require(ROOT .. 'lib\\setmodel'),
        };
    end);
    if ok then lib = t; end
    return lib;
end

-- ---------------------------------------------------------------------------
-- scalar codec: the framework store holds strings/numbers/booleans only.
--
-- THREE GRAMMARS live side by side (docs/set-types-plan.md 4, which the
-- timeline-only docs/timeline-sets-plan.md 7 pair predates):
--
--   'sets' (legacy)   'name<TAB>id,id,...' per line -- a FLAT list, plus
--                     the levels-era extras ('name<TAB>level<TAB>ids',
--                     'name<TAB>rule<TAB>key'). Still WRITTEN on every save
--                     so an older module reading this store sees usable
--                     sets instead of nothing: the old decoder turns any
--                     unknown token into 0, so changing this grammar in
--                     place would silently EMPTY every set.
--   'sets2' (v2)      the timeline sets only. '#v2' header line, then per
--                     set: name<TAB>builtFor<TAB>chains
--                     chains = 20 ';'-joined chain tokens (empties kept);
--                     chain  = ','-joined entries; entry = id@from
--                     (id 0 = the deliberate empty marker).
--   'sets3' (v3)      THE TRUTH -- every set, kind-tagged (see the codec).
--   'sets2bak'        backups, one per line, newest first, <= 5 per set
--                     name -- KIND-SHAPED since 2026-08-10 (see the
--                     encodeBackups grammar; a timeline backup's line is
--                     unchanged from the v2 days).
--   'lastApplied2'    'level<TAB>id,id,...' -- the level the apply was FOR.
--                     'lastApplied' (bare csv) stays dual-written.
--
-- Readers prefer v3, then v2, then legacy; every decode is tolerant -- a
-- bad token drops the entry, never the file.
-- ---------------------------------------------------------------------------
local codec = {};

function codec.encodeIds(ids)
    local parts = {};
    for i = 1, 20 do parts[i] = tostring(tonumber(ids and ids[i]) or 0); end
    return table.concat(parts, ',');
end

function codec.decodeIds(s)
    local ids, i = {}, 0;
    for tok in tostring(s or ''):gmatch('[^,]+') do
        i = i + 1;
        if i > 20 then break; end
        ids[i] = tonumber(tok) or 0;
    end
    for k = i + 1, 20 do ids[k] = 0; end
    return ids;
end

function codec.encodeSets(list)
    local recs = {};
    for _, e in ipairs(list or {}) do
        local name = tostring(e.name or '?'):gsub('[\t\n]', ' ');
        recs[#recs + 1] = name .. '\t' .. codec.encodeIds(e.ids);   -- flat
        if e.rule ~= nil then
            recs[#recs + 1] = ('%s\trule\t%s'):format(name, tostring(e.rule));
        end
        for _, t in ipairs(e.builds or {}) do
            recs[#recs + 1] = ('%s\t%d\t%s'):format(
                name, tonumber(t.level) or 71, codec.encodeIds(t.ids));
        end
    end
    return table.concat(recs, '\n');
end

function codec.decodeSets(s)
    local out, byName = {}, {};
    local function group(name)
        local g = byName[name];
        if g == nil then
            g = { name = name, ids = codec.decodeIds(''), builds = {} };
            byName[name] = g;
            out[#out + 1] = g;
        end
        return g;
    end
    for line in tostring(s or ''):gmatch('[^\n]+') do
        local f = {};
        for tok in (line .. '\t'):gmatch('([^\t]*)\t') do f[#f + 1] = tok; end
        local name = f[1];
        if name ~= nil and name ~= '' then
            local g = group(name);
            if #f >= 3 and f[2] == 'rule' then
                g.rule = f[3];                          -- the set's level rule
            elseif #f >= 3 then
                local lvl = tonumber(f[2]) or 0;
                if lvl > 0 then
                    g.builds[#g.builds + 1] = { level = lvl, ids = codec.decodeIds(f[3]) };
                end
            elseif #f == 2 then
                g.ids = codec.decodeIds(f[2]);          -- the flat build
            end
        end
    end
    -- the kinds law (docs/set-types-plan.md): a set with no build lines and
    -- no rule is a FLAT set and must decode as one -- an empty builds table
    -- would read as the levels kind downstream
    for _, g in ipairs(out) do
        if #g.builds == 0 and g.rule == nil then g.builds = nil; end
    end
    return out;
end

-- split preserving EMPTY tokens (gmatch('[^;]+') would swallow them, and an
-- empty chain token is meaningful: that slot has no entries)
local function splitKeep(s, sep)
    local out, pos = {}, 1;
    s = tostring(s or '');
    while true do
        local i = s:find(sep, pos, true);
        if i == nil then
            out[#out + 1] = s:sub(pos);
            return out;
        end
        out[#out + 1] = s:sub(pos, i - 1);
        pos = i + 1;
    end
end

function codec.encodeChains(chains)
    local slots = {};
    for i = 1, 20 do
        local parts = {};
        for _, e in ipairs(chains and chains[i] or {}) do
            parts[#parts + 1] = ('%d@%d'):format(tonumber(e.id) or 0, tonumber(e.from) or 1);
        end
        slots[i] = table.concat(parts, ',');
    end
    return table.concat(slots, ';');
end

function codec.decodeChains(s)
    local chains = {};
    local slots = splitKeep(s, ';');
    for i = 1, 20 do
        chains[i] = {};
        local tok = slots[i] or '';
        if tok ~= '' then
            for entry in tok:gmatch('[^,]+') do
                local id, from = entry:match('^(%-?%d+)@(%-?%d+)$');
                id, from = tonumber(id), tonumber(from);
                if id ~= nil and from ~= nil and from >= 1 and from <= 75 then
                    chains[i][#chains[i] + 1] = { id = id, from = from };
                end
            end
            -- restore the ascending-activation invariant every consumer
            -- assumes (resolveAtLevel breaks at the first later entry) --
            -- a hand-edited or corrupted line must not misresolve silently
            table.sort(chains[i], function(a, b) return a.from < b.from; end);
        end
    end
    return chains;
end

function codec.encodeSets2(list)
    local recs = { '#v2' };
    for _, e in ipairs(list or {}) do
        -- timeline sets only: this key's grammar is chains, and the flat /
        -- levels kinds have no honest line in it -- the 'sets' mirror is
        -- what an older module reads for those (no field module ever
        -- shipped a sets2 reader, so nothing is losing data here)
        if e.chains ~= nil then
            local name = tostring(e.name or '?'):gsub('[\t\n]', ' ');
            recs[#recs + 1] = name .. '\t' .. tostring(tonumber(e.builtFor) or 75)
                .. '\t' .. codec.encodeChains(e.chains);
        end
    end
    return table.concat(recs, '\n');
end

function codec.decodeSets2(s)
    local out = {};
    for line in tostring(s or ''):gmatch('[^\n]+') do
        if line:sub(1, 1) ~= '#' then
            local name, bf, chains = line:match('^(.-)\t(%d+)\t(.*)$');
            if name ~= nil and name ~= '' then
                -- clamp builtFor into 1-75: a corrupt 0 would enforce every
                -- band and a corrupt 200 would enforce none -- tolerance
                -- means neither flip, not garbage-in-semantics-out
                local n = tonumber(bf) or 75;
                if n < 1 or n > 75 then n = 75; end
                out[#out + 1] = {
                    name = name,
                    builtFor = n,
                    chains = codec.decodeChains(chains),
                };
            end
        end
    end
    return out;
end

-- THE v3 GRAMMAR (docs/set-types-plan.md 4): one line per set, the KIND is
-- the first token, '#v3' header. Kind-specific tails:
--   flat<TAB>name<TAB>id,id,...
--   levels<TAB>name<TAB>id,id,...[<TAB>rule:key][<TAB>41:id,id,...]...
--   timeline<TAB>name<TAB>builtFor<TAB>chains      (the sets2 line, tagged)
-- Decode is tolerant per line and per token: an unknown kind drops the
-- line, a bad build token drops the token, never the file.
function codec.encodeSets3(list)
    local recs = { '#v3' };
    for _, e in ipairs(list or {}) do
        local name = tostring(e.name or '?'):gsub('[\t\n]', ' ');
        if e.chains ~= nil then
            recs[#recs + 1] = 'timeline\t' .. name
                .. '\t' .. tostring(tonumber(e.builtFor) or 75)
                .. '\t' .. codec.encodeChains(e.chains);
        elseif e.builds ~= nil or e.rule ~= nil then
            local parts = { 'levels', name, codec.encodeIds(e.ids) };
            if e.rule ~= nil then
                parts[#parts + 1] = 'rule:' .. tostring(e.rule);
            end
            for _, t in ipairs(e.builds or {}) do
                parts[#parts + 1] = ('%d:%s'):format(
                    tonumber(t.level) or 71, codec.encodeIds(t.ids));
            end
            recs[#recs + 1] = table.concat(parts, '\t');
        else
            recs[#recs + 1] = 'flat\t' .. name .. '\t' .. codec.encodeIds(e.ids);
        end
    end
    return table.concat(recs, '\n');
end

function codec.decodeSets3(s)
    local out = {};
    for line in tostring(s or ''):gmatch('[^\n]+') do
        if line:sub(1, 1) ~= '#' then
            local f = {};
            for tok in (line .. '\t'):gmatch('([^\t]*)\t') do f[#f + 1] = tok; end
            local kind, name = f[1], f[2];
            if name ~= nil and name ~= '' then
                if kind == 'flat' and f[3] ~= nil then
                    out[#out + 1] = { kind = 'flat', name = name,
                        ids = codec.decodeIds(f[3]) };
                elseif kind == 'levels' and f[3] ~= nil then
                    local e = { kind = 'levels', name = name,
                        ids = codec.decodeIds(f[3]), builds = {} };
                    for i = 4, #f do
                        local rule = f[i]:match('^rule:(%a+)$');
                        local lvl, csv = f[i]:match('^(%d+):(.*)$');
                        if rule ~= nil then
                            e.rule = rule;
                        elseif lvl ~= nil then
                            e.builds[#e.builds + 1] = {
                                level = tonumber(lvl),
                                ids = codec.decodeIds(csv),
                            };
                        end
                    end
                    out[#out + 1] = e;
                elseif kind == 'timeline' and f[4] ~= nil then
                    local n = tonumber(f[3]) or 75;
                    if n < 1 or n > 75 then n = 75; end
                    out[#out + 1] = { kind = 'timeline', name = name,
                        builtFor = n, chains = codec.decodeChains(f[4]) };
                end
            end
        end
    end
    return out;
end

-- backups travel on their own key, attached to sets by NAME (names are the
-- identity keys everywhere else too -- activeSetName restores by them).
-- KIND-SHAPED since 2026-08-10, discriminated by the THIRD token:
--   name<TAB>ts<TAB>builtFor<TAB>chains       a timeline backup (unchanged)
--   name<TAB>ts<TAB>flat<TAB>id,id,...        a flat backup
--   name<TAB>ts<TAB>levels<TAB>ids[<TAB>rule:key][<TAB>41:ids]...
-- (the old reader took the third token as a number; no field store carries
-- the new lines, so nothing older ever has to read one)
function codec.encodeBackups(list)
    local recs = {};
    for _, e in ipairs(list or {}) do
        local name = tostring(e.name or '?'):gsub('[\t\n]', ' ');
        for _, b in ipairs(e.backups or {}) do
            local head = name .. '\t' .. tostring(tonumber(b.ts) or 0);
            if b.chains ~= nil then
                recs[#recs + 1] = head
                    .. '\t' .. tostring(tonumber(b.builtFor) or 75)
                    .. '\t' .. codec.encodeChains(b.chains);
            elseif b.builds ~= nil or b.rule ~= nil then
                local parts = { head, 'levels', codec.encodeIds(b.ids) };
                if b.rule ~= nil then
                    parts[#parts + 1] = 'rule:' .. tostring(b.rule);
                end
                for _, t in ipairs(b.builds or {}) do
                    parts[#parts + 1] = ('%d:%s'):format(
                        tonumber(t.level) or 71, codec.encodeIds(t.ids));
                end
                recs[#recs + 1] = table.concat(parts, '\t');
            else
                recs[#recs + 1] = head .. '\tflat\t' .. codec.encodeIds(b.ids);
            end
        end
    end
    return table.concat(recs, '\n');
end

-- the ring depth mirrors setmodel.BACKUP_CAP; read it from the vendored
-- library when it is loaded (the headless codec tests run before that and
-- fall back to the same number)
local function backupCap()
    if lib ~= nil and lib.sets ~= nil and lib.sets.BACKUP_CAP ~= nil then
        return lib.sets.BACKUP_CAP;
    end
    return 5;
end

function codec.attachBackups(list, s)
    local byName = {};
    -- FIRST match wins on a duplicate name -- the same rule activeSetName
    -- resolution uses -- so a name collision cannot silently move every
    -- backup onto the later set
    for _, e in ipairs(list or {}) do
        local key = tostring(e.name);
        if byName[key] == nil then byName[key] = e; end
    end
    local cap = backupCap();
    for line in tostring(s or ''):gmatch('[^\n]+') do
        local name, ts, third, rest = line:match('^(.-)\t(%d+)\t([^\t]*)\t?(.*)$');
        local e = name ~= nil and byName[name] or nil;
        if e ~= nil and #(e.backups or {}) < cap then
            local b = nil;
            if third == 'flat' then
                b = { kind = 'flat', ids = codec.decodeIds(rest) };
            elseif third == 'levels' then
                local f = {};
                for tok in (rest .. '\t'):gmatch('([^\t]*)\t') do f[#f + 1] = tok; end
                b = { kind = 'levels', ids = codec.decodeIds(f[1]), builds = {} };
                for i = 2, #f do
                    local rule = f[i]:match('^rule:(%a+)$');
                    local lvl, csv = f[i]:match('^(%d+):(.*)$');
                    if rule ~= nil then
                        b.rule = rule;
                    elseif lvl ~= nil then
                        b.builds[#b.builds + 1] = {
                            level = tonumber(lvl),
                            ids = codec.decodeIds(csv),
                        };
                    end
                end
            elseif tonumber(third) ~= nil then
                b = { kind = 'timeline', builtFor = tonumber(third) or 75,
                      chains = codec.decodeChains(rest) };
            end
            if b ~= nil then
                b.ts = tonumber(ts) or 0;
                b.name = name;
                e.backups = e.backups or {};
                e.backups[#e.backups + 1] = b;
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- the cfg bridge: the library mutates one live table and calls save();
-- save() re-encodes into the framework store (mutation-only underneath)
-- ---------------------------------------------------------------------------
local cfg, Sref = nil, nil;
local _panelAt = nil;   -- last frame the Panel rendered: the fresh-click detector

local function loadCfg(S)
    -- v2 first; a store that predates the timeline (empty sets2) falls back
    -- to the legacy flat key, and host.adoptCfg upgrades the entries after
    -- the swap. The first save then writes both grammars.
    -- readers prefer the newest grammar: sets3 (kinds) -> sets2 (timeline)
    -- -> sets (the legacy lines, levels grammar included)
    local sets3raw = S.cfg.get('sets3');
    local sets2raw = S.cfg.get('sets2');
    local setsList;
    if type(sets3raw) == 'string' and sets3raw ~= '' then
        setsList = codec.decodeSets3(sets3raw);
        codec.attachBackups(setsList, S.cfg.get('sets2bak'));
    elseif type(sets2raw) == 'string' and sets2raw ~= '' then
        setsList = codec.decodeSets2(sets2raw);
        codec.attachBackups(setsList, S.cfg.get('sets2bak'));
    else
        setsList = codec.decodeSets(S.cfg.get('sets'));
    end
    local lastApplied;
    local la2 = S.cfg.get('lastApplied2');
    if type(la2) == 'string' and la2 ~= '' then
        local lvl, csv = la2:match('^(%d*)\t(.*)$');
        lastApplied = { ids = codec.decodeIds(csv), level = tonumber(lvl) };
    else
        lastApplied = { ids = codec.decodeIds(S.cfg.get('lastApplied')) };
    end
    cfg = {
        sets           = setsList,
        lastApplied    = lastApplied,
        activeSetName  = S.cfg.get('activeSetName'),
        lastAppliedSet = S.cfg.get('lastAppliedSet'),
        newSetKind     = S.cfg.get('newSetKind'),
        tooltipDelay   = S.cfg.get('tooltipDelay'),
        codexDensity   = S.cfg.get('codexDensity'),
        traitsDensity  = S.cfg.get('traitsDensity'),
        setsLayout     = S.cfg.get('setsLayout'),
        applyMode      = S.cfg.get('applyMode'),
        applyDelay     = S.cfg.get('applyDelay'),
        budgetOverride = S.cfg.get('budgetOverride'),
        replan         = S.cfg.get('replan'),
        autoRestore    = S.cfg.get('autoRestore'),
        setsModelVer    = S.cfg.get('setsModelVer'),
        capModelVer     = S.cfg.get('capModelVer'),
        capLearnedBonus = S.cfg.get('capLearnedBonus'),
        capMeritPoints  = S.cfg.get('capMeritPoints'),
    };
    local any = false;
    for i = 1, 20 do
        if cfg.lastApplied.ids[i] ~= 0 then any = true; break; end
    end
    if not any then cfg.lastApplied = {}; end   -- 'never applied yet'
    return cfg;
end

local function saveCfg()
    if cfg == nil or Sref == nil or Sref.cfg == nil then return; end
    pcall(function()
        -- every grammar, every save: sets3 is the truth; sets2 carries the
        -- timeline sets for the one unreleased module generation that reads
        -- it; the legacy key is each set's flat/levels lines so an OLDER
        -- module reading this store still sees usable sets (its decoder
        -- zeroes unknown tokens)
        Sref.cfg.set('sets3', codec.encodeSets3(cfg.sets));
        Sref.cfg.set('sets2', codec.encodeSets2(cfg.sets));
        Sref.cfg.set('sets2bak', codec.encodeBackups(cfg.sets));
        Sref.cfg.set('sets', codec.encodeSets(cfg.sets));
        local la = cfg.lastApplied;
        Sref.cfg.set('lastApplied2', (la and la.ids)
            and (tostring(tonumber(la.level) or '') .. '\t' .. codec.encodeIds(la.ids)) or '');
        Sref.cfg.set('lastApplied',
            (la and la.ids) and codec.encodeIds(la.ids) or '');
        Sref.cfg.set('activeSetName', tostring(cfg.activeSetName or ''));
        Sref.cfg.set('lastAppliedSet', tostring(cfg.lastAppliedSet or ''));
        Sref.cfg.set('newSetKind', tostring(cfg.newSetKind or 'levels'));
        Sref.cfg.set('tooltipDelay', tonumber(cfg.tooltipDelay) or 0.5);
        Sref.cfg.set('codexDensity', tostring(cfg.codexDensity or 'normal'));
        Sref.cfg.set('traitsDensity', tostring(cfg.traitsDensity or 'normal'));
        Sref.cfg.set('setsLayout', tostring(cfg.setsLayout or 'grid'));
        Sref.cfg.set('applyMode', tostring(cfg.applyMode or 'safe'));
        Sref.cfg.set('applyDelay', tonumber(cfg.applyDelay) or 1.1);
        Sref.cfg.set('budgetOverride', tonumber(cfg.budgetOverride) or 0);
        Sref.cfg.set('replan', tostring(cfg.replan or 'manual'));
        Sref.cfg.set('autoRestore', cfg.autoRestore == true);
        Sref.cfg.set('setsModelVer', tonumber(cfg.setsModelVer) or 4);
        Sref.cfg.set('capModelVer', tonumber(cfg.capModelVer) or 3);
        Sref.cfg.set('capLearnedBonus', tonumber(cfg.capLearnedBonus) or -1);
        Sref.cfg.set('capMeritPoints', tonumber(cfg.capMeritPoints) or -1);
    end);
end

-- ---------------------------------------------------------------------------
-- the store watch: the bridge is a snapshot, the store is per-character
-- ---------------------------------------------------------------------------
--
-- dlac loads modules at addon load -- BEFORE login -- and its store serves
-- declared defaults until the character directory exists. So the snapshot
-- loadCfg takes at init holds an EMPTY set list, and without a re-read the
-- session's first save would write that emptiness over the character's real
-- file: the dlac flavor of the save-after-logoff bug. Watch the one fact
-- that names the store's identity -- the file it would write (S.cfg.path(),
-- per-character, nil pre-login) -- and re-decode the bridge the moment it
-- changes: the first login, and every character switch. The fresh table
-- goes through host.onSettingsSwap, which keeps or drops the working state
-- by character exactly as the standalone flavor does. Runs at every beat
-- and at the top of every render, so no save-capable surface can act on a
-- stale bridge first.
local _storeAt = nil;   -- the store path the bridge was decoded from

local function syncStore()
    if Sref == nil or Sref.cfg == nil or lib == nil or cfg == nil then return; end
    local p = nil;
    pcall(function() p = Sref.cfg.path(); end);
    if p == nil or p == _storeAt then return; end
    _storeAt = p;
    loadCfg(Sref);
    lib.blu.delay = tonumber(cfg.applyDelay) or 1.1;
    lib.blu.mode  = tostring(cfg.applyMode or 'safe');
    if type(lib.host.onSettingsSwap) == 'function' then
        lib.host.onSettingsSwap(cfg, p);
    elseif lib.host.deps ~= nil then
        lib.host.deps.cfg = cfg;    -- an older vendored host: rebind at least
    end
end

-- ---------------------------------------------------------------------------
-- the contract
-- ---------------------------------------------------------------------------
return {
    api   = 2,
    label = 'Bludex',                    -- PROPOSED
    jobs  = { 'BLU' },

    config = {
        keys = {
            -- sets3 is the kinds grammar (the truth); sets2/sets2bak/
            -- lastApplied2 are the timeline grammar; sets and lastApplied
            -- stay dual-written so an older module still reads a usable
            -- list (see the codec block). setsLayout and autoRestore are
            -- retired, kept one release for tolerance.
            sets = 'string', sets2 = 'string', sets3 = 'string',
            sets2bak = 'string',
            lastApplied = 'string', lastApplied2 = 'string',
            lastAppliedSet = 'string',
            activeSetName = 'string',
            newSetKind = 'string',
            tooltipDelay = 'number',
            codexDensity = 'string', traitsDensity = 'string', setsLayout = 'string',
            applyMode = 'string', replan = 'string',
            applyDelay = 'number', budgetOverride = 'number',
            autoRestore = 'boolean',
            setsModelVer = 'number',
            -- the point-budget model (see ui/settingsui.lua). This flavor
            -- has no packet hook, so the 0x063 cross-check never arrives
            -- here -- both figures come from readings or the Settings tab.
            capModelVer = 'number',
            capLearnedBonus = 'number', capMeritPoints = 'number',
        },
        defaults = {
            sets = '', sets2 = '', sets3 = '', sets2bak = '',
            lastApplied = '', lastApplied2 = '',
            lastAppliedSet = '',
            activeSetName = '',
            newSetKind = 'levels',
            tooltipDelay = 0.5,
            codexDensity = 'normal', traitsDensity = 'normal', setsLayout = 'grid',
            applyMode = 'safe', replan = 'manual',
            applyDelay = 1.1, budgetOverride = 0,
            autoRestore = false,
            setsModelVer = 4,
            capModelVer = 3, capLearnedBonus = -1, capMeritPoints = -1,
        },
    },

    init = function(S)
        Sref = S;
        local L = loadLib();
        if L == nil then
            pcall(S.say.err, 'the vendored library failed to load; the Panel will say so.');
            return;
        end
        loadCfg(S);
        -- a mid-session load (/addon reload dlac) already has the character
        -- directory: record it so the watch only fires on a real change
        pcall(function() _storeAt = S.cfg.path(); end);
        L.blu.delay = tonumber(cfg.applyDelay) or 1.1;
        L.blu.mode  = tostring(cfg.applyMode or 'safe');
        L.host.init({
            im = nil,                    -- the host handle arrives with panel ctx
            book = L.book, blu = L.blu, sets = L.sets,
            cfg = cfg, save = saveCfg,
        });
        pcall(function()
            if type(L.host.noteChar) == 'function' then L.host.noteChar(_storeAt); end
        end);
        -- the level-change watch + armed Restore ride the framework beat,
        -- Panel open or not, gated on the one activity predicate. A read we
        -- could not make is not permission: '~= true' stays inert. The store
        -- watch runs FIRST and ungated -- login detection cannot depend on
        -- the module being 'active'.
        pcall(function()
            S.combat.subscribe('tick', function()
                syncStore();
                if S.me.acting().active == true then
                    pcall(L.host.tick);
                end
            end);
        end);
    end,

    panel = function(ctx)
        local L = lib;
        if L == nil then
            if ctx.ui and ctx.ui.err then
                ctx.ui.err('bludex: the vendored library did not load (see /dl check).');
            end
            return;
        end
        syncStore();                     -- never render (or save) a stale bridge
        L.host.deps.im = ctx.imgui;      -- always the HOST's handle
        if L.host.deps.floatWindow == true then
            -- The float surface is live (this dlac has the window hook), so
            -- Bludex runs as its OWN window and this Panel is the launcher.
            -- A FRESH row click (no Panel render for a while) pops the
            -- window; while the Panel stays selected, a window the player
            -- closed stays closed.
            local now = os.clock();
            if _panelAt == nil or (now - _panelAt) > 1.0 then L.host.open(); end
            _panelAt = now;
            local ui = ctx.ui;
            if ui == nil then return; end
            ui.dim('Bludex runs in its own window -- it stays up even while this one is closed.');
            ui.space();
            if L.host.isOpen() then
                if ui.button('bdxwin_close', 'Close the Bludex window',
                             'Close it; the row keeps working.', 220, 26) then
                    L.host.toggle();
                end
            else
                if ui.button('bdxwin_open', 'Open the Bludex window',
                             'Codex, sets and traits, in a window of its own.', 220, 26) then
                    L.host.open();
                end
            end
        else
            -- an older dlac without the hook: the full body renders here
            L.host.renderEmbedded();
        end
    end,

    -- The WHOLE Bludex window through the framework's float surface (ADR 0028
    -- amendment 2026-08-04): drawn at dlac's one float draw site, so it
    -- survives the main window closing. Self-gates on its own open flag --
    -- the Panel above is the launcher. On an older dlac that ignores this
    -- hook, deps.floatWindow never sets and the Panel renders the embedded
    -- body instead.
    window = function(ctx)
        local L = lib;
        if L == nil then return; end
        syncStore();                     -- never render (or save) a stale bridge
        L.host.deps.im = ctx.imgui;
        L.host.renderWindowFloat();
    end,

    -- The quick menu's verb (guide 2.9): choosing Bludex in the Job helpers
    -- cascade pops the window (with the usual open-refresh of the BLU structs).
    open = function(S)
        local L = lib;
        if L == nil then return; end
        L.host.open();
    end,

    status = function(ctx)
        local L = lib;
        if L == nil then return; end
        local ok, max, spent = pcall(L.blu.points);
        if ok and max then
            ctx.ui.dim(('%d / %d pts set'):format(spent or 0, max));
        end
    end,

    -- not part of the loader contract; exposed for the headless smoke suite
    -- (_forceLib seeds the lazy lib cache: the repo layout lacks the vendored
    -- sibling dirs, so require-based loadLib cannot resolve there)
    _codec = codec,
    _syncStore = syncStore,
    _forceLib = function(t) lib = t; end,
};
