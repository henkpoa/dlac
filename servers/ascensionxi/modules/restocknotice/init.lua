-- Keep this outside voidrestock/: the launcher deletes that retired directory.
if ashita and ashita.events then
    ashita.events.register('command', 'dlac_restock_notice', function(e)
        local command = tostring(e.command or ''):lower();
        if command:match('^/dl%s+restock%s*$') then
            e.blocked = true;
            require('dlac\\chatfmt').print('Void Restock moved to Nexus: /nexus restock (fetch, store or stop).');
        end
    end);
end
return {};
