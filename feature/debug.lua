--[[
    dlac/debug.lua -- the /dl debug section (Henrik, 2026-07-23: "make a
    proper dl debug section"). One router, topic-per-feature state readouts,
    each in the two-halves pattern /dl check established: this ADDON-state
    module prints a feature's addon half, the engine's 'debug' branch
    (dispatch.lua v104) prints its half, and only KNOWN topics answer there --
    the usage/topic list has exactly one printer (here).

    Scope law (Henrik's 07-23 ruling, the /dl check session): these are
    "is it doing what it should?" state readouts -- liveness, resolved paths,
    the decision inputs a feature would act on. Packet captures, event spies
    and timing probes stay in dlacprobe. When a field case needs a readout,
    add a TOPIC here (+ its engine branch when the feature has engine state)
    instead of a bespoke per-feature command.

    Topics:
      ls (alias: lockstyle) -- lockstyle.M.debugLines() addon-side (boxes
          file/tier, marked box, unsaved-edits warning, v47 gate verdict,
          keep/town/guard state); engine-side the apply pipeline as a DRY RUN
          ('/dl debug ls <box>' picks a box exactly like apply).
]]--

local M = {};

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

-- alias -> canonical topic. Aliases are free; a canonical topic needs a
-- PRINTERS entry below (and an engine branch when the feature has one).
M.ALIAS = { ls = 'ls', lockstyle = 'ls' };

-- Pure (headless-tested, DBT*): first word after 'debug' -> canonical topic
-- or nil (unknown/absent -> the usage line).
function M._topic(word)
    return M.ALIAS[string.lower(tostring(word or ''))];
end

function M._usage()
    return 'debug topics: ls (alias: lockstyle) -- lockstyle state, addon + engine halves. Wiring health: /dl check.';
end

local PRINTERS = {
    ls = function()
        local m = try('dlac\\feature\\lockstyle');
        if m == nil or type(m.debugLines) ~= 'function' then
            print('[dlac] debug ls (addon): lockstyle module not loaded.');
            return;
        end
        local ok, lines = pcall(m.debugLines);
        if not ok or type(lines) ~= 'table' then
            print('[dlac] debug ls (addon): readout failed (' .. tostring(lines) .. ').');
            return;
        end
        for _, l in ipairs(lines) do print('[dlac] debug ls (addon): ' .. l); end
    end,
};

-- '/dl debug [topic]' in the ADDON state. e.blocked only quiets the game
-- parser -- the LAC state's dispatch handler still sees the command (the
-- /dl ls apply precedent) and adds its engine half for known topics.
ashita.events.register('command', 'dlac-debug', function(e)
    local raw = string.lower(e.command);
    local rest = nil;
    if raw:match('^/dlac?%s+debug%s*$') ~= nil then rest = '';
    else rest = raw:match('^/dlac?%s+debug%s+(.*)$'); end
    if rest == nil then return; end
    e.blocked = true;
    local topic = M._topic(rest:match('^(%S+)'));
    if topic == nil then print('[dlac] ' .. M._usage()); return; end
    PRINTERS[topic]();
end);

return M;
