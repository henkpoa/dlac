--[[
    Bludex as a dlac Job helper module -- the api = 2 contract adapter.

    THIS FILE IS AUTHORED IN THE BLUDEX REPO (dlacmodule/init.lua) and lands
    in dlac at jobhelpers\blu\bludex\init.lua via the sync workflow, next to
    the vendored library (lib/ ui/ data/ icons/). Do not hand-edit the copy
    in dlac; see VENDORED.md there.

    The approval envelope (what this module DOES) is documented for review
    in README.md beside this file. In one breath: it renders the Blue Magic
    codex/set-planner Panel, reads the client's own BLU structs, and -- only
    on the player's explicit Apply or their armed level-change Restore rule
    -- sets/unsets Blue Magic spells through the client's own 0x102 path,
    one spell per packet, paced. It never equips gear and never opens an
    Action sequence.

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
-- Saved sets serialize as one string ('name<TAB>id,id,...' per line); the
-- last-applied snapshot as one 'id,id,...' line. Tolerant on the way in.
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
        recs[#recs + 1] = name .. '\t' .. codec.encodeIds(e.ids);
    end
    return table.concat(recs, '\n');
end

function codec.decodeSets(s)
    local out = {};
    for line in tostring(s or ''):gmatch('[^\n]+') do
        local name, idcsv = line:match('^(.-)\t(.*)$');
        if name ~= nil and name ~= '' then
            out[#out + 1] = { name = name, ids = codec.decodeIds(idcsv) };
        end
    end
    return out;
end

-- ---------------------------------------------------------------------------
-- the cfg bridge: the library mutates one live table and calls save();
-- save() re-encodes into the framework store (mutation-only underneath)
-- ---------------------------------------------------------------------------
local cfg, Sref = nil, nil;

local function loadCfg(S)
    cfg = {
        sets           = codec.decodeSets(S.cfg.get('sets')),
        lastApplied    = { ids = codec.decodeIds(S.cfg.get('lastApplied')) },
        activeSetName  = S.cfg.get('activeSetName'),
        codexDensity   = S.cfg.get('codexDensity'),
        applyMode      = S.cfg.get('applyMode'),
        applyDelay     = S.cfg.get('applyDelay'),
        budgetOverride = S.cfg.get('budgetOverride'),
        autoRestore    = S.cfg.get('autoRestore'),
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
        Sref.cfg.set('sets', codec.encodeSets(cfg.sets));
        Sref.cfg.set('lastApplied',
            (cfg.lastApplied and cfg.lastApplied.ids) and codec.encodeIds(cfg.lastApplied.ids) or '');
        Sref.cfg.set('activeSetName', tostring(cfg.activeSetName or ''));
        Sref.cfg.set('codexDensity', tostring(cfg.codexDensity or 'normal'));
        Sref.cfg.set('applyMode', tostring(cfg.applyMode or 'safe'));
        Sref.cfg.set('applyDelay', tonumber(cfg.applyDelay) or 1.1);
        Sref.cfg.set('budgetOverride', tonumber(cfg.budgetOverride) or 0);
        Sref.cfg.set('autoRestore', cfg.autoRestore == true);
    end);
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
            sets = 'string', lastApplied = 'string', activeSetName = 'string',
            codexDensity = 'string', applyMode = 'string',
            applyDelay = 'number', budgetOverride = 'number',
            autoRestore = 'boolean',
        },
        defaults = {
            sets = '', lastApplied = '', activeSetName = '',
            codexDensity = 'normal', applyMode = 'safe',
            applyDelay = 1.1, budgetOverride = 0,
            autoRestore = false,
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
        L.blu.delay = tonumber(cfg.applyDelay) or 1.1;
        L.blu.mode  = tostring(cfg.applyMode or 'safe');
        L.host.init({
            im = nil,                    -- the host handle arrives with panel ctx
            book = L.book, blu = L.blu, sets = L.sets,
            cfg = cfg, save = saveCfg,
        });
        -- the level-change watch + armed Restore ride the framework beat,
        -- Panel open or not, gated on the one activity predicate. A read we
        -- could not make is not permission: '~= true' stays inert.
        pcall(function()
            S.combat.subscribe('tick', function()
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
        L.host.deps.im = ctx.imgui;      -- always the HOST's handle
        L.host.renderEmbedded();
    end,

    -- The Spell Info window, through the framework's float surface (ADR 0028
    -- amendment 2026-08-04): drawn at dlac's one float draw site, so it
    -- survives the main window closing. Self-gates -- draws nothing until a
    -- spell is clicked open in the codex. On an older dlac that ignores this
    -- hook, the codex falls back to its in-panel detail pane by itself.
    window = function(ctx)
        local L = lib;
        if L == nil then return; end
        L.host.deps.im = ctx.imgui;
        L.host.renderDetailFloat();
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
    _codec = codec,
};
