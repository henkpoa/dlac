-- Attached to the Teleports row's Selectable (before another item is drawn).
-- The active server pack owns eligibility and the recharge action.
local imgui = require('imgui');
local sp = require('dlac\\gear\\serverpack');
local M = {};

function M.render(row, key)
    local service = sp.service('expRingRecharge');
    if not service then return; end
    local popup = '##tpRecharge' .. tostring(row.id or key);
    if imgui.IsItemHovered() and imgui.IsMouseClicked(1) then
        service.refresh(row);
        imgui.OpenPopup(popup);
    end
    if not imgui.BeginPopup(popup) then return; end
    local allowed, reason = service.check(row);
    if allowed then
        if imgui.Selectable('Recharge ring##recharge' .. key, false) then
            service.recharge(row);
            imgui.CloseCurrentPopup();
        end
    else
        -- Dim text is inert and keeps the explanation visible without requiring
        -- hover support on disabled ImGui widgets in this Ashita binding.
        imgui.TextDisabled('Recharge ring');
    end
    imgui.TextWrapped((reason:gsub('%%', '%%%%')));
    imgui.EndPopup();
end

return M;
