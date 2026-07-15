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
                                                  -- window; module owns visibility
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

-- Render every registered tab inside an already-open TabBar.
-- guard(label, renderFn, job, level) comes from the caller (gearui's tabGuard).
host.renderTabs = function(guard, job, level)
    if imgui == nil then return; end
    for _, m in ipairs(mods) do
        if type(m.tabs) == 'table' then
            for _, t in ipairs(m.tabs) do
                if imgui.BeginTabItem(t.label) then
                    guard(t.label, t.render, job, level);
                    imgui.EndTabItem();
                end
            end
        end
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
