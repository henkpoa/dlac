-- Attached to the Teleports row's Selectable (before another item is drawn).
-- The active server pack owns eligibility and the recharge action.
local imgui = require('imgui');
local sp = require('dlac\\gear\\serverpack');
local M = {};
local hoverSince = {};

function M.render(row, key)
    local service = sp.service('expRingRecharge');
    if not service then return; end
    local popup = '##tpRecharge' .. tostring(row.id or key);
    if imgui.IsItemHovered() and imgui.IsMouseClicked(1) then
        hoverSince[popup] = nil;
        service.refresh(row);
        imgui.OpenPopup(popup);
    end
    if not imgui.BeginPopup(popup) then
        hoverSince[popup] = nil;
        return;
    end
    local allowed, reason = service.check(row);
    if allowed then
        if imgui.Selectable('Recharge ring##recharge' .. key, false) then
            service.recharge(row);
            imgui.CloseCurrentPopup();
            hoverSince[popup] = nil;
            imgui.EndPopup();
            return;
        end
    else
        -- Dim text is inert and still supports hover without requiring
        -- hover support on disabled ImGui widgets in this Ashita binding.
        imgui.TextDisabled('Recharge ring');
    end
    if imgui.IsItemHovered() then
        local now = imgui.GetTime();
        hoverSince[popup] = hoverSince[popup] or now;
        if now - hoverSince[popup] >= 0.5 then
            imgui.BeginTooltip();
            imgui.PushTextWrapPos(300);
            imgui.TextWrapped((reason:gsub('%%', '%%%%')));
            imgui.PopTextWrapPos();
            imgui.EndTooltip();
        end
    else
        hoverSince[popup] = nil;
    end
    imgui.EndPopup();
end

return M;
