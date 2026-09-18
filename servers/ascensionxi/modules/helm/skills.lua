-- AscensionXI helm.lua: bandFloor, canWork and hitChance. Normal skill
-- packets replace these skills with 0xFFFF; status.lua supplies snapshots.
local M = {};
M.order = { 'Mining', 'Harvesting', 'Excavation', 'Logging' };
M.floors = { 0, 20, 40, 60, 80 };
local values = {};

function M.reset() values = {}; end
function M.value(category) return values[category]; end

function M.set(snapshot) values = snapshot; end

function M.chance(category, band)
    local skill, floor = values[category], M.floors[band];
    if skill == nil or floor == nil then return nil, 'unknown'; end
    if skill < floor then return nil, 'locked'; end
    local ceiling = M.floors[band + 1] or 100;
    return 50 + 30 * math.min(1, (skill - floor) / (ceiling - floor));
end

return M;
