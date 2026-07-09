-- dlac gear inventory -- YOUR owned gear. Start empty and fill it in-game:
--   /dl scan   (see what's found)  ->  /dl stage  ->  /dl commit
-- Each slot is a table of item entries; Main/Range are nested by weapon category
-- (e.g. gear.Main.Sword.WaxSword_1). The GUI (/dl ui) edits this for you.
gear = {
    Main = {
    },
    Sub = {
    },
    Range = {
    },
    Ammo = {
    },
    Head = {
    },
    Neck = {
    },
    Ear = {
    },
    Body = {
    },
    Hands = {
    },
    Ring = {
    },
    Back = {
    },
    Waist = {
    },
    Legs = {
    },
    Feet = {
    },
};

-- Build a Name -> object lookup so string references resolve to the actual entry.
NameToObject = {}
for slotName, slotVars in pairs(gear) do
    if slotName == "Main" or slotName == "Range" then
        for combatCategory, combatVars in pairs(slotVars) do
            for gearObjectName, gearVars in pairs(combatVars) do
                NameToObject[gearVars.Name] = gearVars
            end
        end
    else
        for gearObjectName, gearVars in pairs(slotVars) do
            NameToObject[gearVars.Name] = gearVars
        end
    end
end
gear.NameToObject = NameToObject
return gear
