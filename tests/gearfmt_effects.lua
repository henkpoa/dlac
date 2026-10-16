-- Run from the addon root: lua tests/gearfmt_effects.lua
local fmt = dofile('gear/gearfmt.lua');
local catalog = dofile('servers/ascensionxi/data/catalog.lua');
local function find(t, id)
    if t.Id == id then return t; end
    for _, v in pairs(t) do
        if type(v) == 'table' then
            local found = find(v, id);
            if found then return found; end
        end
    end
end
AshitaCore = { GetResourceManager = function()
    return { GetString = function(_, category, id)
        assert(category == 'buffs.names');
        return ({ [5] = 'Blind', [3] = 'Poison' })[id];
    end };
end };
local blind = assert(find(catalog, 18150));
local line = fmt.fullStatList(blind.Stats);
assert(line == 'Additional effect: Blind', line);
fmt.configure({ effStats = function(rec) return rec.Stats; end });
local summary = fmt.statSummary(blind, 75);
assert(summary:find('Additional effect: Blind', 1, true), summary);
assert(not summary:find('ITEM_', 1, true), summary);
assert(blind.Stats.ITEM_ADDEFFECT_CHANCE == 100, 'formatter mutated catalog');
assert(fmt.fullStatList({ Accuracy = 5, ITEM_ADDEFFECT_TYPE = 2,
    ITEM_ADDEFFECT_STATUS = 3 }) == 'Accuracy+5 Additional effect: Poison');
assert(fmt.fullStatList({ ITEM_ADDEFFECT_TYPE = 5, ITEM_SUBEFFECT = 1 })
    == 'Additional effect: HP drain');
AshitaCore = nil;
assert(fmt.fullStatList({ ITEM_ADDEFFECT_TYPE = 2, ITEM_ADDEFFECT_STATUS = 999 })
    == 'Additional effect: Status ailment');
assert(fmt.fullStatList({ ITEM_ADDEFFECT_SCRIPTED = 1 })
    == 'Additional effect: Special effect');
assert(fmt.fullStatList({ Accuracy = 5 }) == 'Accuracy+5');

-- Race restriction (server mod EQUIPMENT_ONLY_RACE): who may wear a piece, said in
-- words, never a stat. Custom Tunic is the field report (2026-10-16): dlac's card
-- read "EQUIPMENT_ONLY_RACE+1" where the game's own card prints "[Body]H♂".
local tunic = assert(find(catalog, 12654));
assert(tunic.Name == 'Custom Tunic' and tunic.Stats.EQUIPMENT_ONLY_RACE == 1);
assert(fmt.raceText(tunic) == 'Hume male only', tostring(fmt.raceText(tunic)));
assert(fmt.fullStatList(tunic.Stats) == 'DEF+18 HP+32 VIT+3 INT-1 CHR+1',
    fmt.fullStatList(tunic.Stats));
assert(fmt.statSummary(tunic, 75) == 'DEF+18 HP+32 VIT+3 INT-1 (+1 more)',
    fmt.statSummary(tunic, 75));   -- the race mask is not one of the "more"
assert(tunic.Stats.EQUIPMENT_ONLY_RACE == 1, 'formatter mutated catalog');

-- Every mask the AscensionXI catalog ships. Race id r is bit r-1, in the server's
-- order: Hume m/f, Elvaan m/f, Tarutaru m/f, Mithra, Galka.
local WORDS = {
    [1] = 'Hume male only',      [2] = 'Hume female only',      [3] = 'Hume only',
    [4] = 'Elvaan male only',    [8] = 'Elvaan female only',    [12] = 'Elvaan only',
    [16] = 'Tarutaru male only', [32] = 'Tarutaru female only', [48] = 'Tarutaru only',
    [64] = 'Mithra only',        [128] = 'Galka only',
    [149] = 'Male only',         [106] = 'Female only',
};
for mask, want in pairs(WORDS) do
    local got = fmt.raceText({ Stats = { EQUIPMENT_ONLY_RACE = mask } });
    assert(got == want, mask .. ': ' .. tostring(got));
end
-- No restriction reads as nothing; other mixes still name each race once.
assert(fmt.raceText(nil) == nil and fmt.raceText({}) == nil and fmt.raceText({ Stats = {} }) == nil);
assert(fmt.raceText({ Stats = { EQUIPMENT_ONLY_RACE = 0 } }) == nil, '0 = every race');
assert(fmt.raceText({ Stats = { EQUIPMENT_ONLY_RACE = 255 } }) == nil, 'all eight = every race');
assert(fmt.raceText({ Stats = { EQUIPMENT_ONLY_RACE = -1 } }) == nil, 'the server ignores <= 0');
assert(fmt.raceText({ Stats = { EQUIPMENT_ONLY_RACE = 5 } }) == 'Hume male, Elvaan male only');
assert(fmt.raceText({ Stats = { EQUIPMENT_ONLY_RACE = 65 } }) == 'Hume male, Mithra only');
assert(fmt.raceText({ Stats = { EQUIPMENT_ONLY_RACE = 257 } }) == 'Hume male only',
    'only bits 0..7 name a race');

-- The whole shipped catalog: every race-restricted piece says who may wear it,
-- and no stat line or row summary carries the mask.
local restricted = 0;
local function walk(t)
    local m = (type(t.Stats) == 'table') and t.Stats.EQUIPMENT_ONLY_RACE or nil;
    if m ~= nil and t.Name ~= nil then
        restricted = restricted + 1;
        local words = fmt.raceText(t);
        assert(words ~= nil and words:match(' only$') and not words:find('%d'),
            t.Name .. ': ' .. tostring(words));
        if WORDS[m] ~= nil then assert(words == WORDS[m], t.Name .. ': ' .. words); end
        assert(not fmt.fullStatList(t.Stats):find('RACE', 1, true), t.Name);
        assert(not fmt.statSummary(t, 75):find('RACE', 1, true), t.Name);
    end
    for _, v in pairs(t) do if type(v) == 'table' then walk(v); end end
end
walk(catalog);
assert(restricted >= 400, 'walked only ' .. restricted .. ' race-restricted pieces');
print(string.format('OK -- readable additional effects and race restrictions (%d pieces)', restricted));
