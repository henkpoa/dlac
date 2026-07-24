--[[
    dlac/feature/idleexcl.lua

    Idle-hobby mutual exclusion: only ONE of the four idle-activity overlays --
    Craft, HELM, Fishing, Chocobo -- may be armed at a time. Arming one stands the
    other three down; the armed one shows in the floating indicator
    (ui/idlefloat.lua), which also disarms it.

    WHERE THIS SITS (and why it is NOT the recorded dead end). history.md records
    "newest-armed exclusivity as a *claim-side* rule" as a dead end (ADR 0012
    step 1.5, engine v98): the OLD rule lived inline in dispatch's M.dispatch and
    reached across at DISPATCH time to silence a peer's gear claims wholesale -- so
    arming HELM yanked the fishing rod out of Range even though HELM never claims
    Range (the AR10/PUP case). That claim-side rule stays dead.

    This is a different seam entirely: exclusivity at the ENABLE toggle. Each
    watcher's setEnabled(true) (and helm's setAutoHelm(true)) calls
    M.onActivated(key), which turns the OTHER three OFF. Because only one hobby is
    ever ARMED, the engine's co-claim / Arbiter never even sees a conflict -- it is
    untouched, and tests AR8/AR9/AR10 (which stub state files directly, never
    setEnabled) keep passing. See ADR 0017.

    NO LOAD-TIME CYCLE: the watchers require this module, and this module requires
    the watchers -- but only ever inside function bodies (lazy `try`), so neither
    load pulls the other. onActivated is guarded so a sibling stand-down
    (setEnabled(false), which never re-enters onActivated) can never recurse.
]]--

local M = {};

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

-- Lazy watcher accessors (called at USE time, never at load -- see the cycle note
-- above). Each returns the watcher module or nil if it isn't loadable.
local function craftMod() return try('dlac\\feature\\craftwatch'); end
local function helmMod()  return try('dlac\\feature\\helmwatch');  end
local function fishMod()  return try('dlac\\feature\\fishwatch');  end
local function chocoMod() return try('dlac\\feature\\chocowatch'); end

-- The four mutually-exclusive idle hobbies, in display / tiebreak order.
--   key      : stable id passed to onActivated()
--   name     : label for the float and logs
--   isOn()   : armed right now?  HELM = manual idle OR proximity Auto HELM.
--   disable(): stand it FULLY down. HELM clears BOTH switches (idle + auto), so
--              activating a peer also disarms a background Auto HELM.
--   detail() : short sub-label for the float (craft/category/target), or nil.
M.MEMBERS = {
    {
        key = 'craft', name = 'Craft',
        isOn    = function() local w = craftMod(); return w ~= nil and w.isEnabled() == true; end,
        disable = function() local w = craftMod(); if w ~= nil then pcall(w.setEnabled, false); end end,
        detail  = function() local w = craftMod(); return w ~= nil and w.getCraft() or nil; end,
    },
    {
        key = 'helm', name = 'HELM',
        isOn    = function()
            local w = helmMod();
            return w ~= nil and (w.isEnabled() == true or w.isAutoHelm() == true);
        end,
        disable = function()
            local w = helmMod();
            if w ~= nil then pcall(w.setEnabled, false); pcall(w.setAutoHelm, false); end
        end,
        detail  = function()
            local w = helmMod(); if w == nil then return nil; end
            local g = w.getGather();
            -- Auto-only (idle switch off, proximity armed) -> flag it so the badge
            -- reads "HELM: Mining (auto)".
            if w.isAutoHelm() == true and w.isEnabled() ~= true then
                return (type(g) == 'string' and g ~= '') and (g .. ' (auto)') or 'auto';
            end
            return g;
        end,
    },
    {
        key = 'fish', name = 'Fishing',
        isOn    = function() local w = fishMod(); return w ~= nil and w.isEnabled() == true; end,
        disable = function() local w = fishMod(); if w ~= nil then pcall(w.setEnabled, false); end end,
        detail  = function()
            local w = fishMod(); if w == nil then return nil; end
            local ok, _, nm = pcall(w.getTarget);   -- getTarget() -> id, name
            return (ok and type(nm) == 'string' and nm ~= '') and nm or nil;
        end,
    },
    {
        key = 'choco', name = 'Chocobo',
        isOn    = function() local w = chocoMod(); return w ~= nil and w.isEnabled() == true; end,
        disable = function() local w = chocoMod(); if w ~= nil then pcall(w.setEnabled, false); end end,
        detail  = function() return nil; end,
    },
};

-- Re-entrancy guard. onActivated fires ONLY from setEnabled(true)/setAutoHelm(true);
-- the disable() calls below go through setEnabled(false)/setAutoHelm(false), which
-- never call onActivated -- so this flag is belt-and-suspenders against a future
-- caller that flips the convention.
local _standingDown = false;

-- A hobby just armed: stand the other three down. Called from each watcher's
-- setEnabled(true) (and helm's setAutoHelm(true)). Safe to call with an unknown
-- key (then all four are left alone).
function M.onActivated(key)
    if _standingDown then return; end
    _standingDown = true;
    pcall(function()
        for _, m in ipairs(M.MEMBERS) do
            if m.key ~= key then m.disable(); end
        end
    end);
    _standingDown = false;
end

-- The one armed hobby, or nil. Exclusion keeps at most one armed; if a hand-edited
-- state file somehow arms two, the FIRST in MEMBERS order wins the badge
-- (deterministic -- the float never flickers between them).
--   returns { key = <id>, name = <label>, detail = <string|nil> }
function M.getActive()
    for _, m in ipairs(M.MEMBERS) do
        if m.isOn() == true then
            local ok, d = pcall(m.detail);
            local detail = (ok and type(d) == 'string' and d ~= '') and d or nil;
            return { key = m.key, name = m.name, detail = detail };
        end
    end
    return nil;
end

function M.isActive() return M.getActive() ~= nil; end

-- Stand the currently-armed hobby down (the float's Off button).
-- Returns the key it disarmed, or nil if none was armed.
function M.deactivate()
    for _, m in ipairs(M.MEMBERS) do
        if m.isOn() == true then m.disable(); return m.key; end
    end
    return nil;
end

return M;
