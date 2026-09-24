local base = 'dlac\\servers\\ascensionxi\\modules\\voidrestock\\';
local restock = require(base .. 'restock');
local ui = require(base .. 'ui');
local client = restock.client;
require('dlac\\gear\\serverpack').provide('voidrestock', restock);
require('dlac\\ui\\automationsui').registerHelper({
    key = 'restock',
    row = function()
        return { key = 'restock', name = 'Void Restock', kind = 'Inventory supplies',
            level = client.fresh and 1 or 0, max = 1, txt = restock.busy() and 'Working' or 'Click to manage' };
    end,
    panel = ui.render,
    quick = { label = 'Void Restock', icon = 'void_storage', tip = 'Keep inventory targets topped up and store eligible excess.' },
});
require('dlac\\ui\\tray').register({ mod = base .. 'ui', wants = 'trayWants', draw = 'trayDraw' });
if ashita and ashita.events then
    ashita.events.register('packet_in', 'dlac_void_restock', function(e)
        if e.id == 0x00A or e.id == 0x00B then restock.zone();
        elseif e.id == 0x1E0 and client.onPacket(e.data_modified or e.data) then e.blocked = true; end
    end);
    ashita.events.register('command', 'dlac_void_restock_cmd', function(e)
        local command = tostring(e.command or ''):lower();
        if command:match('^/dl%s+restock%s*$') then
            e.blocked = true; require('dlac\\ui\\gearui').openAutomation('restock');
        elseif command:match('^/?!void%s') or command == '!void' then
            restock.zone(); -- manual changes invalidate balances and any queued run
        end
    end);
end
return { pump = restock.tick };
