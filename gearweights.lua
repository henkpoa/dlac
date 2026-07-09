-- dlac gear stat weights  (auto-written by gearoptim.lua)
-- Each stat scores perUnit points per point of the stat, up to cap; beyond
-- the cap it adds nothing. Edit here or via  /dl weight <Stat> <perUnit> <cap>.
return {
    ["INT"] = { perUnit = 10, cap = nil },
    ["MATK"] = { perUnit = 20, cap = 2 },
}
