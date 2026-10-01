--[[
    dlac/feature/location.lua -- WHERE is the character? The central, reusable
    answer for zone/town questions -- gamemode.lua's sibling, for place instead
    of playmode:

        location.zoneId()   -> current zone id | nil (unknown: unreadable, or 0)
        location.isTown(id) -> is that zone id one of the curated towns?
        location.inTown()   -> is the CURRENT zone a town? true | false | nil
        location.isCity(id) -> does the SERVER call that zone a city (the
                               zone type's CITY bit, the `.t` field)?
        location.inCity()   -> is the CURRENT zone a city? true | false | nil

    Town membership is the curated set in data/zones.lua (the `.town` flag --
    server CITY zonetype + Nashmau, minus combat-staging CITY zones; generated
    by tools/gen_zones.py). This module (addon side) and the dispatch engine's
    inTown condition read that ONE data file -- the single source of town truth.
    City is the raw server predicate instead of the curated set: a server that
    gates something on "a city" (AscensionXI's Gear Vault layout edits test the
    CITY bit of the zone type) is predicted by isCity, never by the idle set.

    The live read is GetMemberZone(0), a single party-memory array access, so it
    is uncached (gamemode.lua's rule). The reader is injectable for headless
    tests (M.reader), and everything nils out on a failed read -- callers treat
    nil as "unknown", never as a definite answer (the buff/target-cache
    discipline: a bad read must not flip behavior).
]]--

local M = {};

-- Curated town set from data/zones.lua (the .town flag). A missing/old file
-- just means nothing is a town -- the feature degrades off, never errors (the
-- nativemp rule).
local TOWN = {};
local CITY = {};   -- zone id -> true when the zone type carries the CITY bit (0x1)
local TYPED = false;   -- does this pack's zone file carry type masks at all?
do
    local ok, zones = pcall(require, 'dlac\\data\\zones');
    if ok and type(zones) == 'table' then
        for zid, z in pairs(zones) do
            if type(z) == 'table' and z.town then TOWN[zid] = true; end
            if type(z) == 'table' and type(z.t) == 'number' then
                TYPED = true;
                if z.t % 2 == 1 then CITY[zid] = true; end
            end
        end
    end
end

-- Is zone id `id` one of the curated towns? Pure lookup, nil-safe.
function M.isTown(id)
    return id ~= nil and TOWN[id] == true;
end

-- Does the server call zone `id` a city (its zone type's CITY bit)? nil when
-- the pack's zone file carries no type masks -- unknown, never a guess.
function M.isCity(id)
    if not TYPED or id == nil then return nil; end
    return CITY[id] == true;
end

-- Live zone reader, injectable for headless tests. nil on any failure and on
-- zone 0 (the demo stub, never a real player location).
M.reader = function()
    local z = nil;
    pcall(function()
        z = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0);
    end);
    if type(z) ~= 'number' or z == 0 then return nil; end
    return z;
end;

-- The current zone id, or nil when unreadable (headless, pre-login, mid-zone).
function M.zoneId()
    return M.reader();
end

-- Is the CURRENT zone a town? true / false, or nil when the zone is unknown --
-- never guess. Callers hold their behavior on nil (a mid-zone blink must not
-- flip gear).
function M.inTown()
    local z = M.zoneId();
    if z == nil then return nil; end
    return M.isTown(z);
end

-- Is the CURRENT zone a city by the server's own predicate? true / false, or
-- nil when the zone or the pack's type masks are unknown.
function M.inCity()
    local z = M.zoneId();
    if z == nil then return nil; end
    return M.isCity(z);
end

return M;
