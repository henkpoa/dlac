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
    if entry.kind == 2 and entry.state == 2 then return 0; end
    if entry.kind == 1 then return (entry.count or 0) > 0 and 1 or 0; end
    if (entry.instanceId or 0) > 0 then
        return (entry.state == 3 or entry.state == 4) and 0 or 1;
    end
    local count = entry.count or 1;
    local limit = M.limit(rec);
    return limit and math.min(count, limit) or count;
end

return M;
