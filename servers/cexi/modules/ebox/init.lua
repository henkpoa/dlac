--[[
    cexi/ebox -- the Ephemeral Box family as a server-pack module (ADR 0035):
    eboxclient (THE one 0x1A4 store client, ADR 0016), restockwatch (config +
    the pure planners), restockui (the Restock panel + tray crates) and
    eboxtrace (/dl debug ebox). This init mounts the four, provides the two
    services core may ask for, and registers the surfaces core used to
    hardcode: the tray crates (between Teleports and the giftboxes -- the
    manifest's module order IS that ruling now), the Gear Helpers row + panel,
    and the quick-menu row. Every registration sits behind the module's OWN
    CW gate (Henrik: 100% CW-only) -- core no longer knows what a Crystal
    Warrior is.
]]--

local base = 'dlac\\servers\\cexi\\modules\\ebox\\';

local ec  = require(base .. 'eboxclient');
local rw  = require(base .. 'restockwatch');
local rui = require(base .. 'restockui');
local et  = require(base .. 'eboxtrace');

pcall(function()
    local sp = require('dlac\\gear\\serverpack');
    sp.provide('eboxclient', ec);
    sp.provide('eboxtrace', et);
end);

-- The affirmative CW gate (architecture.md): shown in 'CW', hidden on
-- Wings/ACE and on nil-unknown alike.
local function isCW()
    local out = false;
    pcall(function()
        local gm = require('dlac\\gear\\serverpack').service('gamemode');
        out = type(gm) == 'table' and gm.get() == 'CW';
    end);
    return out;
end

-- The tray crates: registration order = vertical order (dlac.lua mounts the
-- pack's modules in manifest order, so ebox before giftbox keeps Store's
-- crate from ever sliding under a cursor -- the tray header's ruling).
pcall(function()
    require('dlac\\ui\\tray').register({ mod = base .. 'restockui', wants = 'trayWants', draw = 'trayDraw' });
end);

-- The Gear Helpers row (+ its panel) and the quick-menu row, through the one
-- helper registry. The row/panel/quick keys keep their historical 'restock'
-- identity so saved jumps and /dl restock keep landing.
pcall(function()
    local auto = require('dlac\\ui\\automationsui');
    if type(auto.registerHelper) ~= 'function' then return; end
    auto.registerHelper({
        key  = 'restock',
        want = isCW,
        row  = function(deps)
            local r = { key = 'restock', name = 'E-Box Restock',
                        kind = 'restock helper (Ephemeral Box, CW)',
                        level = 0, max = 1, txt = nil };
            pcall(function()
                r.max = rui.maxLevel or 1;
                r.level, r.txt = rui.status(deps);
            end);
            return r;
        end,
        panel = function(deps, availW)
            if type(rui.render) == 'function' then rui.render(deps, availW); end
        end,
        quick = {
            label = 'E-Box Restock',
            tip   = 'Open the E-Box Restock panel -- what you keep topped up from the Ephemeral\nBox, how many of each, and the floating nudge\'s settings.',
            icon  = 'ebox',
        },
    });
end);

return {};
