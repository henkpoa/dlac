--[[
    dlac/uihost.lua

    UI module registry -- the Trove-style host contract (trove/utils/plugins.lua),
    adapted for dlac. Feature modules register a contract table once:

        host.register({
            name = 'equipped',                    -- required, unique
            tabs = {                              -- tabs in the main dlac window
                { label = 'Equipped', render = function(job, level) end },
            },
            window = { render = function(job, level) end },  -- optional floating
                                                  -- window; module owns visibility.
                                                  -- NOTE: renderWindows is called
                                                  -- from INSIDE gearui's drawWindow,
                                                  -- so a registered window only
                                                  -- draws while the MAIN box is
                                                  -- open. A window that must
                                                  -- outlive it (lockstyle,
                                                  -- floatgear) is rendered straight
                                                  -- from gearui's d3d_present with
                                                  -- its own theme bracket instead.
            invalidate = function() end,          -- gear/inventory/job changed:
                                                  -- drop derived caches
        });

    Registration order = render order. Shared services (icon renderer, tooltips,
    lookups, player info, ...) are published by gearui via host.provide{} into ONE
    live table -- modules must read host.services.X at CALL time, never capture the
    value at load time (gearui provides them after most modules have loaded).

    Deliberately unlike trove's plugin manager: a STATIC registration list -- no
    io.popen('dir /b') auto-discovery (popen spawns console windows), and module
    renders run under the caller-supplied guard (gearui's tabGuard owns the
    imgui stack-tear recovery), so a broken module can never tear the frame.
]]--

local host = {};

local imgui = (function()
    local ok, m = pcall(require, 'imgui');
    return (ok and type(m) == 'table') and m or nil;
end)();

local mods   = {};   -- registration order = render order
local byName = {};

-- The surface gate (lib\featuregate): which registered tabs EXIST on this
-- install -- the server pack's defaults plus the character's Settings flips.
-- Absent or broken, every tab renders (gating is a subtraction, never a
-- prerequisite); a label the gate's roster does not know is never hidden.
local fgate = (function()
    local ok, m = pcall(require, 'dlac\\lib\\featuregate');
    return (ok and type(m) == 'table') and m or nil;
end)();

local function tabAllowed(label)
    if fgate == nil then return true; end
    local ok, v = pcall(fgate.tabEnabled, label);
    if not ok then return true; end
    return v ~= false;
end

host.services = {};  -- live shared-services table; filled via host.provide{}

host.provide = function(tbl)
    for k, v in pairs(tbl) do host.services[k] = v; end
end

host.register = function(mod)
    if type(mod) ~= 'table' or type(mod.name) ~= 'string' then return false; end
    if byName[mod.name] ~= nil then
        -- re-register replaces in place (module hot-reload keeps its tab position)
        for i, m in ipairs(mods) do
            if m.name == mod.name then mods[i] = mod; end
        end
    else
        mods[#mods + 1] = mod;
    end
    byName[mod.name] = mod;
    return true;
end

host.get = function(name) return byName[name]; end

-- Forced tab selection, HELD UNTIL IT TAKES (2026-07-30). A caller asks for a
-- label ("go to Gear Helpers"); every renderTabs pass hands
-- ImGuiTabItemFlags_SetSelected to that label's BeginTabItem until the tab is
-- observed OPEN, then stops.
--
-- It used to be a strict one-shot -- arm, hand the flag to the next pass, forget.
-- Henrik, field 2026-07-30: the jump sets the right PANEL but the tab bar never
-- moves ("I click E-Box Restock in the teleport menu... but when I open the GUI I
-- am still on the Job Helpers tab"), and he reports the same for the other
-- cross-links. Two things were wrong with the one-shot, and they hid each other:
--
--   * ImGui applies a forced selection at the NEXT frame's TabBarLayout, so on
--     the pass that carries the flag BeginTabItem still returns false. A one-shot
--     therefore never had anything to observe -- honoured and ignored looked
--     identical (hard rule 12), which is why this shipped broken and stayed that
--     way. Holding the request until the tab actually opens both FIXES an arming
--     pass that lands on a frame the tab bar cannot act on, and gives the failure
--     a place to be noticed.
--   * `o == true` threw away a truthy non-boolean. If this binding returns
--     anything but a Lua `true`, the flagged pass would skip both the content AND
--     `EndTabItem` -- an unbalanced tab item, which tears the bar it was trying to
--     steer. Every other call site here treats the return as truthy; so does this
--     one now.
--
-- THE FLAG DOES NOT WORK IN THIS BUILD -- field 2026-07-30, second round. With the
-- hold in place, both flag shapes ran their full budget and the give-up line
-- printed: *"could not switch to the Gear Helpers tab -- this build's imgui ignored
-- the tab-selection flag."* The SDK header on disk
-- (`plugins\sdk\imgui.h`) declares `BeginTabItem(label, bool* p_open = nullptr,
-- ImGuiTabItemFlags flags = 0)` with `SetSelected = 1 << 1`, so the value and the
-- argument order were never in doubt -- what is not visible anywhere on disk is how
-- Ashita's hand-written Lua binding maps a `bool*`, and no sibling addon proves it
-- either (the one that passes flags, `ventures`, looks identical to a player
-- whether its flag lands or is dropped).
--
-- So we stop ASKING and TAKE the selection, in three rungs, cheapest first:
--
--   1. `(label, {true}, flags)` -- p_open as a TABLE. This is the shape that
--      demonstrably works for `imgui.Begin` in this very addon (gearui's own window
--      passes `isOpen` as a table and its X button works), so it is the best
--      remaining guess at how the binding wants a `bool*`. It costs a close (x) on
--      the tab for the pass or two it rides; we ignore the table, so clicking it
--      does nothing.
--   2. `(label, nil, flags)` -- the header's own signature. Disproven HERE, kept
--      because a correct binding honours it and gets the jump with no artifact.
--   3. THE REBUILD -- the one that does not depend on the binding at all. A tab bar
--      ImGui has never seen has no selection, and it adopts the FIRST tab submitted
--      to it. So the bar's ID gets a new generation (`host.tabBarId`, which gearui
--      asks for) and the wanted tab is submitted FIRST until it opens. Cost: the
--      tabs sit in a different order for one or two frames, and the bar is empty
--      for one frame while ImGui has nothing selected. That is the price of a jump
--      that actually works.
--
-- The chat line stays as the last resort behind all three.
local SEL_PASSES = 30;    -- ~0.5s at 60fps: far too short to fight a real click.
local SEL_SHAPE  = 2;     -- passes spent on the flag before the rebuild is armed
local _sel    = nil;      -- { label = 'Gear Helpers', n = <passes>, rebuilt = bool }
local _barGen = 0;        -- tab-bar ID generation; every bump = a bar ImGui has
                          -- never seen, which is what makes rung 3 work.

-- The ID gearui must pass to BeginTabBar. Changing it is not cosmetic -- it is the
-- selection reset rung 3 is built on, so the caller may not cache it. Each bump
-- abandons one ImGuiTabBar inside ImGui (a small struct plus its tab list); jumps
-- are a handful per session, so the drift is not worth managing.
host.tabBarId = function(base)
    base = (type(base) == 'string') and base or '##dlac_tabs';
    if _barGen == 0 then return base; end
    return base .. '#g' .. tostring(_barGen);
end

host.selectTab = function(label)
    if type(label) ~= 'string' or label == '' then return false; end
    _sel = { label = label, n = 0 };
    return true;
end

-- What the host is currently trying to select, or nil. Tests read it; so can a
-- future /dl check line.
host.pendingTab = function() return (_sel ~= nil) and _sel.label or nil; end

-- The tab jump that never landed. One chat line, only after the budget expires --
-- a working binding never reaches it, and a broken one can no longer look like
-- nothing happened.
local function reportStuck(label)
    pcall(function()
        local m = require('dlac\\chatfmt');
        local say = (type(m) == 'table' and type(m.print) == 'function') and m.print or print;
        say('[dlac] could not switch to the "' .. tostring(label)
            .. '" tab -- neither the selection flag nor a bar rebuild took. The panel is '
            .. 'set correctly; click the tab. Please report this line.');
    end);
end

-- Submit the wanted tab, asking for the selection on the rungs that ask. Returns
-- whether it is open. Past the flag rungs this is an ordinary submission -- the
-- rebuild is what is doing the work by then, and a stray flag would only add a
-- close button to the tab we are trying to land on.
local function beginForced(label, pass)
    local flag = ImGuiTabItemFlags_SetSelected or 2;
    local ok, o;
    if pass == 1 then
        ok, o = pcall(imgui.BeginTabItem, label, { true }, flag);  -- p_open as a TABLE
    elseif pass == 2 then
        ok, o = pcall(imgui.BeginTabItem, label, nil, flag);       -- the header signature
    else
        ok, o = pcall(imgui.BeginTabItem, label);                  -- rung 3 is steering
    end
    if ok then return (o and true or false); end
    return (imgui.BeginTabItem(label) and true or false);          -- shape refused: plain tab
end

-- Render every registered tab inside an already-open TabBar.
-- guard(label, renderFn, job, level) comes from the caller (gearui's tabGuard).
host.renderTabs = function(guard, job, level)
    if imgui == nil then return; end
    -- The budget counts PASSES, not frames: a request made while the main window
    -- is shut waits for it to open rather than expiring unseen.
    local sel = _sel;
    if sel ~= nil then
        sel.n = sel.n + 1;
        if sel.n > SEL_PASSES then
            local stuck = sel.label;
            _sel, sel = nil, nil;
            reportStuck(stuck);
        end
    end

    -- One flat submission list. While a rebuild is riding, the wanted tab goes
    -- FIRST -- a bar ImGui has never seen has nothing selected and adopts the tab
    -- at index 0. The order returns to normal the moment the request clears.
    local list = {};
    for _, m in ipairs(mods) do
        if type(m.tabs) == 'table' then
            for _, t in ipairs(m.tabs) do
                if tabAllowed(t.label) then list[#list + 1] = t; end
            end
        end
    end
    if sel ~= nil and sel.rebuilt then
        for i, t in ipairs(list) do
            if t.label == sel.label then
                table.remove(list, i);
                table.insert(list, 1, t);
                break;
            end
        end
    end

    for _, t in ipairs(list) do
        local open;
        if sel ~= nil and sel.label == t.label then
            open = beginForced(t.label, sel.n);
            -- Open = the selection took. Stop forcing at once: holding it one pass
            -- longer would refuse the player's next tab click, and would leave the
            -- tabs sitting in the rebuild's order.
            if open then _sel = nil; end
        else
            open = (imgui.BeginTabItem(t.label) and true or false);
        end
        if open then
            guard(t.label, t.render, job, level);
            imgui.EndTabItem();
        end
    end

    -- Arm the rebuild only AFTER the submission that might have made it
    -- unnecessary. Deciding this at the top of the pass would bump the generation
    -- on the very pass a working flag lands -- the next pass would then hand
    -- gearui a bar ImGui has never seen, throwing the selection away again.
    if _sel ~= nil and _sel.n > SEL_SHAPE and not _sel.rebuilt then
        _sel.rebuilt = true;
        _barGen = _barGen + 1;
    end
end

-- Render every registered floating window (module owns its own visibility flag
-- and calls imgui.Begin/End itself; hidden windows return immediately).
host.renderWindows = function(guard, job, level)
    for _, m in ipairs(mods) do
        if type(m.window) == 'table' and type(m.window.render) == 'function' then
            guard(m.name .. ' window', m.window.render, job, level);
        end
    end
end

-- Gear/inventory/job state changed: every module drops its derived caches.
host.invalidateAll = function()
    for _, m in ipairs(mods) do
        if type(m.invalidate) == 'function' then pcall(m.invalidate); end
    end
end

return host;
