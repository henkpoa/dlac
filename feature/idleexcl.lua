--[[
    dlac/feature/idleexcl.lua

    Idle-hobby mutual exclusion: only ONE of the four idle-activity overlays --
    Craft, HELM, Fishing, Chocobo -- may be armed at a time.

    MODEL: lock-while-active (Henrik). Arming a hobby while another is already
    active is REFUSED (a brief hint says which one to turn off first) -- we do NOT
    auto-disarm the running one. You switch hobbies by turning the current one off,
    then arming the next. The shared hobby bar (ui/hobbybar.lua) makes this visible:
    its selector locks to the active hobby and only unlocks once it is off. The
    floating badge (ui/idlefloat.lua) names the active hobby and offers the Off.

    WHERE THIS SITS (and why it is NOT the recorded dead end). history.md records
    "newest-armed exclusivity as a *claim-side* rule" as a dead end (ADR 0012
    step 1.5): the OLD rule lived inline in dispatch's M.dispatch and reached
    across at DISPATCH time to silence a peer's gear CLAIMS wholesale (the AR10/PUP
    case). That claim-side rule stays dead. This is a different seam entirely --
    exclusivity at the ENABLE toggle, enforced by a guard in each watcher's
    setEnabled/setAutoHelm. Only one hobby is ever ARMED, so the engine's co-claim
    / Arbiter never sees a conflict and is untouched; tests AR8/AR9/AR10 (which
    stub state files, never setEnabled) keep passing. See ADR 0017.

    NO LOAD-TIME CYCLE: the watchers require this module, and this module requires
    the watchers -- but only ever inside function bodies (lazy `try`), so neither
    load pulls the other.

    HELM: the ONE HELM switch is Auto HELM (Henrik: two toggles was confusing, Auto
    works best). "HELM armed" = isAutoHelm; disabling clears both HELM switches so a
    stray manual-idle flag can't linger.
]]--

local M = {};

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end
local function chatPrint(msg)
    local m = try('dlac\\chatfmt');
    if m ~= nil and type(m.print) == 'function' then pcall(m.print, msg); else pcall(print, msg); end
end

-- Lazy watcher accessors (called at USE time, never at load -- see the cycle note
-- above). Each returns the watcher module or nil if it isn't loadable.
local function craftMod() return try('dlac\\feature\\craftwatch'); end
local function helmMod()  return try('dlac\\feature\\helmwatch');  end
local function fishMod()  return try('dlac\\feature\\fishwatch');  end
local function chocoMod() return try('dlac\\feature\\chocowatch'); end

-- The four mutually-exclusive idle hobbies, in display / tiebreak order.
--   key      : stable id passed to canActivate() / guardActivate()
--   name     : label for the float, the bar selector, and hints
--   isOn()   : armed right now?  HELM = Auto HELM (the only HELM switch now).
--   disable(): stand it FULLY down. HELM clears BOTH switches.
--   detail() : short sub-label for the float / bar (craft/category/target), or nil.
M.MEMBERS = {
    {
        key = 'craft', name = 'Craft',
        isOn    = function() local w = craftMod(); return w ~= nil and w.isEnabled() == true; end,
        disable = function() local w = craftMod(); if w ~= nil then pcall(w.setEnabled, false); end end,
        detail  = function() local w = craftMod(); return w ~= nil and w.getCraft() or nil; end,
    },
    {
        key = 'helm', name = 'HELM',
        isOn    = function() local w = helmMod(); return w ~= nil and w.isAutoHelm() == true; end,
        disable = function()
            local w = helmMod();
            if w ~= nil then pcall(w.setAutoHelm, false); pcall(w.setEnabled, false); end
        end,
        detail  = function() local w = helmMod(); return w ~= nil and w.getGather() or nil; end,
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

local function memberOf(key)
    for _, m in ipairs(M.MEMBERS) do if m.key == key then return m; end end
    return nil;
end

-- The one armed hobby, or nil. The lock guarantees at most one; if a hand-edited
-- state file somehow arms two, the FIRST in MEMBERS order wins (deterministic --
-- the badge/selector never flicker between them).
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

function M.isActive() return M.getActive() ~= nil end

-- May `key` be armed right now? Yes when nothing is armed, or when `key` IS the
-- armed one (re-arming / toggling itself is always fine).
function M.canActivate(key)
    local a = M.getActive();
    return a == nil or a.key == key;
end

-- Guard called from each watcher's setEnabled(true) / setAutoHelm(true). Returns
-- true to allow the arm; false (with a one-line hint) to refuse it because another
-- hobby is active. Fail-OPEN: any internal error allows the arm (a broken guard
-- must never wedge every toggle).
function M.guardActivate(key)
    local ok, allowed = pcall(function()
        local a = M.getActive();
        if a == nil or a.key == key then return true; end
        local m = memberOf(key);
        chatPrint(string.format('[dlac] %s is active -- turn it off before starting %s (only one idle hobby at a time).',
            tostring(a.name), tostring((m ~= nil and m.name) or key)));
        return false;
    end);
    if not ok then return true; end   -- fail open
    return allowed == true;
end

-- Stand the currently-armed hobby down (the badge's Off button, the bar's pill).
-- Returns the key it disarmed, or nil if none was armed.
function M.deactivate()
    for _, m in ipairs(M.MEMBERS) do
        if m.isOn() == true then m.disable(); return m.key; end
    end
    return nil;
end

return M;
