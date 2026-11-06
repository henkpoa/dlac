--[[
    dlac/feature/conquest.lua -- IS THE REGION I STAND IN HELD BY MY NATION?

    The question behind the inNationControl trigger condition (engine v177,
    2026-11-06, Henrik: "if you are inside an area of nations control, or
    outside an area of nations control ... DLAC needs to know the nation of
    player, and the nation's owner of the region"). Three facts answer it,
    each read where the client already holds it:

      your nation   GetPlayer():GetNation() -- 0 San d'Oria, 1 Bastok, 2 Windurst
      the region    zone id -> conquest region, M.REGION below
      its owner     the conquest packet 0x05E. The client asks for it itself
                    (0x05A; the server's note: "the client itself requests
                    this packet after a fixed period of time") and the server
                    pushes it at the weekly tally. dlac only LISTENS --
                    nothing is sent, and nothing is polled.

    The answer copies the server's gear latent "in areas under / outside own
    nation's control" (latent 53 nation_control, latent_effect_container.cpp;
    the same code on AscensionXI and CatsEyeXI), minus its Signet / Sanction /
    Sigil requirement, which a rule adds itself with a buff condition:

      true   a conquest region (Ronfaure .. Tavnazian Archipelago) your nation
             holds
      false  a conquest region someone else holds -- another nation, the
             beastmen, or nobody -- AND the regions the server says are never
             under a nation's control: the three cities, Jeuno, Dynamis, the
             Tavnazian Safehold, Promyvion, Lumoria and Limbus
             (zoneutils::IsAlwaysOutOfNationControl). Your own city reads
             false: that is the server's ruling, not a slip.
      nil    everywhere the latent never fires (Aht Urhgan, the Crystal War
             past, Abyssea, Adoulin, an unlisted zone), an unread zone or
             nation, and a conquest region before the first 0x05E of the
             session. nil matches NEITHER polarity (the inTown discipline):
             after an addon reload the condition waits for the client's next
             conquest request rather than guessing.
]]--

local M = {};

-- Zone id -> conquest region id, regions 0-27 only: the server's own
-- zoneutils::GetCurrentRegion switch (AscensionXI main 2026-11-06, zone ids
-- from data/enums/zone.yaml), identical to CatsEyeXI's for every zone listed
-- here. The two servers differ only in Aht Urhgan (region 31), which never
-- counts. Region ids are the client's own: 0x05E lists owners in this order.
M.REGION = {
    -- 0 Ronfaure
    [100] = 0, [101] = 0, [139] = 0, [140] = 0, [141] = 0, [142] = 0, [167] = 0, [190] = 0,
    -- 1 Zulkheim
    [102] = 1, [103] = 1, [108] = 1, [193] = 1, [196] = 1, [248] = 1,
    -- 2 Norvallen
    [1] = 2, [2] = 2, [104] = 2, [105] = 2, [149] = 2, [150] = 2, [195] = 2,
    -- 3 Gustaberg
    [106] = 3, [107] = 3, [143] = 3, [144] = 3, [172] = 3, [173] = 3, [191] = 3,
    -- 4 Derfland
    [109] = 4, [110] = 4, [147] = 4, [148] = 4, [197] = 4,
    -- 5 Sarutabaruta
    [115] = 5, [116] = 5, [145] = 5, [146] = 5, [169] = 5, [170] = 5, [192] = 5, [194] = 5,
    -- 6 Kolshushu
    [3] = 6, [4] = 6, [117] = 6, [118] = 6, [198] = 6, [213] = 6, [249] = 6,
    -- 7 Aragoneu
    [7] = 7, [8] = 7, [119] = 7, [120] = 7, [151] = 7, [152] = 7, [200] = 7,
    -- 8 Fauregandi
    [9] = 8, [10] = 8, [111] = 8, [166] = 8, [203] = 8, [204] = 8, [206] = 8,
    -- 9 Valdeaunia
    [5] = 9, [6] = 9, [112] = 9, [161] = 9, [162] = 9, [165] = 9,
    -- 10 Qufim Island
    [126] = 10, [127] = 10, [157] = 10, [158] = 10, [179] = 10, [184] = 10,
    -- 11 Li'Telor
    [121] = 11, [122] = 11, [153] = 11, [154] = 11, [202] = 11, [251] = 11,
    -- 12 Kuzotz
    [114] = 12, [125] = 12, [168] = 12, [208] = 12, [209] = 12, [247] = 12,
    -- 13 Vollbow
    [113] = 13, [128] = 13, [174] = 13, [201] = 13, [212] = 13,
    -- 14 Elshimo Lowlands
    [123] = 14, [176] = 14, [250] = 14, [252] = 14,
    -- 15 Elshimo Uplands
    [124] = 15, [159] = 15, [160] = 15, [163] = 15, [205] = 15, [207] = 15, [211] = 15,
    -- 16 Tu'Lia
    [130] = 16, [177] = 16, [178] = 16, [180] = 16, [181] = 16,
    -- 17 Movalpolos
    [11] = 17, [12] = 17, [13] = 17,
    -- 18 Tavnazian Archipelago
    [24] = 18, [25] = 18, [27] = 18, [28] = 18, [29] = 18, [30] = 18, [31] = 18, [32] = 18,
    -- 19 San d'Oria
    [230] = 19, [231] = 19, [232] = 19, [233] = 19,
    -- 20 Bastok
    [234] = 20, [235] = 20, [236] = 20, [237] = 20,
    -- 21 Windurst
    [238] = 21, [239] = 21, [240] = 21, [241] = 21, [242] = 21,
    -- 22 Jeuno
    [243] = 22, [244] = 22, [245] = 22, [246] = 22,
    -- 23 Dynamis
    [39] = 23, [40] = 23, [41] = 23, [42] = 23, [134] = 23, [135] = 23, [185] = 23, [186] = 23,
    [187] = 23, [188] = 23,
    -- 24 Tavnazian Marquisate (the Safehold)
    [26] = 24,
    -- 25 Promyvion
    [14] = 25, [16] = 25, [17] = 25, [18] = 25, [19] = 25, [20] = 25, [21] = 25, [22] = 25,
    [23] = 25,
    -- 26 Lumoria
    [33] = 26, [34] = 26, [35] = 26, [36] = 26,
    -- 27 Limbus
    [37] = 27, [38] = 27,
};

-- Regions 0-18 change hands at the tally; 19-27 never belong to a nation.
M.LAST_CONQUEST = 18;
M.LAST_COUNTED  = 27;

-- 0x05E: region r's 4-byte entry starts at 0x1A + 4*r, and its 4th byte is
-- the owner -- 0 nobody, 1 San d'Oria, 2 Bastok, 3 Windurst, 4 beastmen
-- (the server's GP_SERV_COMMAND_CONQUEST writes nation + 1, neutral as 0;
-- Windower's packets/fields.lua documents the same bytes from the client
-- side). Offsets count the 4-byte header, as e.data carries it.
local REGIONS_AT = 0x1A;

local owners = nil;   -- region 0-18 -> owner byte, from the last 0x05E; nil = none yet

-- Pure, bounds-checked: a packet too short to hold all 19 conquest regions
-- is refused whole rather than half-read.
function M.decode(data)
    if type(data) ~= 'string' or #data < REGIONS_AT + 4 * (M.LAST_CONQUEST + 1) then return nil; end
    local out = {};
    for r = 0, M.LAST_CONQUEST do
        out[r] = data:byte(REGIONS_AT + 4 * r + 4);   -- +3 into the entry, +1 for Lua
    end
    return out;
end

-- Pure: the answer for one zone, nation and owner table (see the header).
function M.answer(zone, nation, own)
    local r = (type(zone) == 'number') and M.REGION[zone] or nil;
    if r == nil then return nil; end
    if r > M.LAST_CONQUEST then return false; end
    if nation ~= 0 and nation ~= 1 and nation ~= 2 then return nil; end
    local o = (type(own) == 'table') and own[r] or nil;
    if type(o) ~= 'number' then return nil; end
    return o == nation + 1;
end

function M.onPacket(id, data)
    if id ~= 0x05E then return; end
    local o = M.decode(data);
    if o ~= nil then owners = o; end
end

-- Live reads, injectable (the mobtag idiom). Each is a FUNCTION.
M.reads = {
    nation = function() return AshitaCore:GetMemoryManager():GetPlayer():GetNation(); end,
    zone   = function() return AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0); end,
};

local function read(name)
    local ok, v = pcall(M.reads[name]);
    if ok and type(v) == 'number' then return v; end
    return nil;
end

-- The live answer. dispatch passes the zone it already read for the
-- dispatch; any other caller may leave it out.
function M.inNationControl(zone)
    if zone == nil then zone = read('zone'); end
    return M.answer(zone, read('nation'), owners);
end

function M.owners() return owners; end
function M.reset() owners = nil; end

pcall(function()
    ashita.events.register('packet_in', 'dlac-conquest-in', function(e)
        if e.id ~= 0x05E or e.injected == true then return; end
        pcall(M.onPacket, e.id, e.data);
    end);
end);

return M;
