--[[
    cexi/prestige -- CatsEyeXI's job-reset system as a server-pack module
    (ADR 0035). prestigewatch.lua is the whole feature (the 0x1A4
    pluginId-1 mirror + <char>\dlac\prestige.lua persistence); this init
    mounts it, hands its frame beat to the servermods pump (the beat's old
    hardcoded seat in dlac.lua), and provides 'prestige' -- the service
    gear\jobgate.lua folds over raw job levels. No module, no service, no
    waiver: the gate reads raw levels, which is every other server's truth.
]]--

local pw = require('dlac\\servers\\cexi\\modules\\prestige\\prestigewatch');

pcall(function()
    require('dlac\\gear\\serverpack').provide('prestige', pw);
end);

return {
    pump = function()
        if type(pw) == 'table' and type(pw.pump) == 'function' then pw.pump(); end
    end,
};
