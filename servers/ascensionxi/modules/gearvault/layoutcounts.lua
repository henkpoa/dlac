-- Shared layout multiplicity for display, admission and space accounting.
-- The wire stores requested units; repeated ADDs can leave impossible counts.
local M = {};
local single = { Sub = true, Range = true, Head = true, Body = true, Hands = true,
    Legs = true, Feet = true, Neck = true, Waist = true, Back = true };

function M.limit(rec)
    if type(rec) ~= 'table' then return nil; end
    if rec.Slot == 'Ring' or rec.Slot == 'Ear' then return 2; end
    if rec.Slot == 'Main' then return rec.OneHanded == false and 1 or 2; end
    if single[rec.Slot] then return 1; end
    -- Unknown items and Ammo (including stackable fishing bait) are not
    -- repaired from guessed metadata.
    return nil;
end

function M.count(entry, rec)
    local count = entry.count or 1;
    local limit = M.limit(rec);
    return limit and math.min(count, limit) or count;
end

return M;
