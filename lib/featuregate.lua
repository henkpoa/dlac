--[[
    dlac/lib/featuregate.lua -- which of dlac's SURFACES exist on this install.

    dlac grew up on CatsEyeXI with every tab and menu row always present; on a
    younger server pack most of them are noise (or not yet field-tested there).
    This module answers ONE question -- "does this surface exist here?" -- from
    two layers, in order:

      * the character's own Settings overrides (Menu > Settings > Features),
        persisted in uiflags.lua by gear\syncflags through export()/applySaved();
      * else the pack's hand-maintained defaults (servers\<id>\features.lua,
        read through gear\serverpack.features() -- the one server seam). Only
        an explicit false there disables; an absent file, an absent section or
        an absent key all read as ON, so CatsEyeXI (which ships no file) keeps
        every surface it has always had.

    Consumers: ui\uihost filters the main window's tabs through tabEnabled()
    (a label uihost registers that this roster does not know is NEVER hidden --
    hiding what we cannot name is how a new tab would vanish silently); ui\menuui
    filters its rows through menuEnabled() (settings / level / debug rows are
    not in the roster, so they cannot be gated off -- the door to turn things
    back ON must always exist). Gating hides SURFACES only: it never unloads a
    module and never touches the engine, the same line a Setting has always
    kept (CONTEXT.md "Setting").

    Pure at load; serverpack is reached lazily and under pcall, so the module
    runs headless and before init() (where it simply answers "on").
]]--

local M = {};

-- The gateable rosters. `key` is STABLE (it is what uiflags persists and what
-- a features.lua names); `label` matches the uihost tab registration / menuui
-- row label verbatim, and renaming a label must not orphan saved overrides.
M.TABS = {
    -- listed in the render order uihost.TAB_RANK settles (Gear Vault leads it
    -- but is a pack module's tab -- not in this roster, so never gateable)
    { key = 'sets',        label = 'Sets' },
    { key = 'triggers',    label = 'Triggers' },
    { key = 'allequip',    label = 'All Equipment' },
    { key = 'equipped',    label = 'Equipped' },
    { key = 'gearhelpers', label = 'Gear Helpers' },
    { key = 'jobhelpers',  label = 'Job Helpers' },
};

-- menuui ROWS keys, minus the rows that must never be gateable (settings,
-- level override, the debug quartet): the way back on lives in that menu.
M.MENU = {
    { key = 'lockstyle', label = 'Lockstyle' },
    { key = 'macrobook', label = 'Macro book' },
    { key = 'hobbybar',  label = 'Hobby bar' },
    { key = 'teleports', label = 'Teleports' },
    { key = 'nm',        label = 'NM Compendium' },
    { key = 'wishlist',  label = 'Wishlist' },
};

local tabKeyByLabel = {};
for _, t in ipairs(M.TABS) do tabKeyByLabel[t.label] = t.key; end
local menuKnown = {};
for _, r in ipairs(M.MENU) do menuKnown[r.key] = true; end

-- The character's explicit flips: ['tab:sets'] = true|false. Only differences
-- from the pack default are kept (set() forgets a flip back to default), so a
-- pack changing its defaults later reaches every character that never chose.
local overrides = {};

-- Seam for the headless suite: inject a fake pack-features table (or false to
-- force "no pack file"). nil = ask serverpack.
M._packFeatures = nil;

local function packFeatures()
    if M._packFeatures ~= nil then
        return (M._packFeatures ~= false) and M._packFeatures or nil;
    end
    local feats = nil;
    pcall(function() feats = require('dlac\\gear\\serverpack').features(); end);
    return feats;
end

-- The pack's answer alone (no overrides): true unless the pack file says
-- `<section>.<key> = false` explicitly.
function M.packDefault(kind, key)
    local feats = packFeatures();
    if type(feats) ~= 'table' then return true; end
    local sect = feats[(kind == 'tab') and 'tabs' or 'menu'];
    if type(sect) ~= 'table' then return true; end
    return sect[key] ~= false;
end

-- The live answer: the character's flip if one exists, else the pack default.
function M.enabled(kind, key)
    local o = overrides[kind .. ':' .. key];
    if o ~= nil then return o; end
    return M.packDefault(kind, key);
end

-- uihost asks by LABEL (that is what register() carries). An unknown label is
-- always on: this roster gates what it can name and nothing else.
function M.tabEnabled(label)
    local key = tabKeyByLabel[label];
    if key == nil then return true; end
    return M.enabled('tab', key);
end

-- menuui asks by row key. Rows outside the roster are never gated.
function M.menuEnabled(key)
    if not menuKnown[key] then return true; end
    return M.enabled('menu', key);
end

-- A Settings checkbox flip. Landing back ON the pack default forgets the
-- override rather than pinning it -- see the overrides comment.
function M.set(kind, key, on)
    local k = kind .. ':' .. key;
    if M.packDefault(kind, key) == (on == true) then
        overrides[k] = nil;
    else
        overrides[k] = (on == true);
    end
end

-- ---------------------------------------------------------------------------
-- Persistence halves -- gear\syncflags owns the file; these own the format:
-- two sorted comma-joined lists of 'kind:key' tokens (explicit ONs, explicit
-- OFFs). Sorted so the saved line is stable frame to frame.
-- ---------------------------------------------------------------------------
function M.export()
    local on, off = {}, {};
    for k, v in pairs(overrides) do
        if v then on[#on + 1] = k; else off[#off + 1] = k; end
    end
    table.sort(on);
    table.sort(off);
    return table.concat(on, ','), table.concat(off, ',');
end

function M.applySaved(onCsv, offCsv)
    overrides = {};
    local function eat(csv, val)
        if type(csv) ~= 'string' then return; end
        for k in string.gmatch(csv, '[^,]+') do
            if string.match(k, '^%w+:%w+$') then overrides[k] = val; end
        end
    end
    eat(offCsv, false);
    eat(onCsv, true);
end

-- Test seam: back to a fresh state.
function M._reset()
    overrides = {};
    M._packFeatures = nil;
end

return M;
