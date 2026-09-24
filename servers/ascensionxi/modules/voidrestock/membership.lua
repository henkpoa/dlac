-- Membership comes from AXI's audited server manifest. The live HELLO mask
-- reports the character's KI-gated tiers; direct client KI reads are unreliable.
local data = require('dlac\\servers\\ascensionxi\\data\\voidstorage');
local M = { data = data };
local byId = {};
for tier, ids in pairs(data.itemsByTier) do
    for _, id in ipairs(ids) do byId[id] = tier; end
end
function M.tier(id) return byId[id]; end
function M.canStore(id, mask)
    local tier = byId[id];
    if tier == nil then return false; end
    if tier == 0 then return true; end
    return type(mask) == 'number' and math.floor(mask / (2 ^ tier)) % 2 == 1;
end
function M.requirement(id)
    local tier = byId[id];
    if tier == nil then return 'Not accepted by Void Storage'; end
    if tier == 0 then return 'Base storage'; end
    return data.tiers[tier].label .. ' storage key item';
end
return M;
