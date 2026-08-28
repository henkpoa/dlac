--[[
    cexi/giftbox -- /dl giftbox and its tray icon as a server-pack module
    (ADR 0035): giftbox.lua (the opener: the substring ladder over CEXI's
    box families, the space gate, the count-drop pacing; registers its own
    /dl giftbox|box|boxes command at load) and giftboxui.lua (the tray icon
    drawn as the box's own in-game art). This init mounts both and registers
    the tray row LAST after ebox's crates -- the manifest's module order is
    the tray-order ruling (Henrik 2026-08-05: "under the e-box stocker
    icons"; the most volatile row must never slide Store under a cursor).
]]--

local base = 'dlac\\servers\\cexi\\modules\\giftbox\\';

local gb  = require(base .. 'giftbox');
local gui = require(base .. 'giftboxui');

pcall(function()
    require('dlac\\ui\\tray').register({ mod = base .. 'giftboxui', wants = 'trayWants', draw = 'trayDraw' });
end);

return {};
