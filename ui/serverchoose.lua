--[[
    dlac/ui/serverchoose.lua -- the FIRST-RUN server chooser (2026-08-30).

    Rendered from gearui's d3d_present (independent of the main window --
    the whole point is that it finds a brand-new player at first login), but
    only while gear\serverpack.needsChoice() holds: several packs ship and
    neither the flag file nor detection answered, so NOTHING is mounted.

    A click writes config\addons\dlac\server.lua through serverpack (the one
    owner of the flag) and queues '/addon reload dlac' -- a live re-select is
    not enough, because every module that pcall-required data before the
    choice has already cached its miss.
]]--

local M = {};

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

local imgui = try('imgui');
local sp    = try('dlac\\gear\\serverpack');

M._chosen = nil;   -- the id a click committed (the reload is on its way)

function M.render()
    if imgui == nil or sp == nil then return; end
    if type(sp.needsChoice) ~= 'function' or not sp.needsChoice() then return; end

    -- Center-ish on first appearance; the player can drag it after. No
    -- SetNextWindowSize beside AlwaysAutoResize -- the zero-size collapse law.
    pcall(function()
        if type(imgui.SetNextWindowPos) == 'function' then
            imgui.SetNextWindowPos({ 320, 240 }, (ImGuiCond_FirstUseEver or 0));
        end
    end);
    -- This binding is fed a p_open TABLE everywhere else; no close button on
    -- purpose (force-true each frame) -- the only way out is an answer.
    M._openT = M._openT or { true };
    M._openT[1] = true;
    if not imgui.Begin('dlac -- choose your server###dlacsrvpick', M._openT,
                       (ImGuiWindowFlags_AlwaysAutoResize or 0) + (ImGuiWindowFlags_NoCollapse or 0)) then
        imgui.End();
        return;
    end

    if M._chosen ~= nil then
        imgui.Text(('Server set to %s -- reloading dlac...'):format(M._chosen));
        imgui.End();
        return;
    end

    imgui.Text('Which server does this install play on?');
    imgui.TextColored({ 0.70, 0.70, 0.70, 1.00 },
        'dlac ships data for more than one server and could not tell which\n'
        .. 'one this is. Nothing is loaded until you answer -- your choice is\n'
        .. 'remembered for this install (change it later under Menu > Settings).');
    imgui.Separator();
    for _, p in ipairs(sp.installed()) do
        if imgui.Button(tostring(p.name) .. '###dlacsrv_' .. tostring(p.id), { 220, 0 }) then
            if sp.writeChoice(p.id) then
                M._chosen = tostring(p.name);
                pcall(function()
                    AshitaCore:GetChatManager():QueueCommand(1, '/addon reload dlac');
                end);
            else
                M._err = true;
            end
        end
    end
    if M._err then
        imgui.TextColored({ 1.00, 0.45, 0.40, 1.00 },
            'Could not write config\\addons\\dlac\\server.lua -- write it by hand:\nreturn { server = \'<id>\' }');
    end
    imgui.End();
end

return M;
