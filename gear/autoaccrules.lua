--[[
    dlac/gear/autoaccrules.lua -- the AutoAcc settings (2026-11-06, Henrik:
    "Auto Acc shouldn't overwrite every form of trigger ... settings for
    AutoAcc under gear helpers, where we can choose which rules to override
    or not"; "I do want to be able to choose if trigger rules override
    autoacc").

    Four switches, per character, in <dataDir>\autoaccrules.lua:

      triggerRules   (on)  a later Trigger rule's set that names an AutoAcc
                           piece's slot puts its own piece there. Off: the
                           AutoAcc piece keeps the slot, and the rule's piece
                           becomes its fallback -- what the slot wears once
                           the accuracy is not needed (dispatch.lua's merge).
      conditional    (on)  a mode or stance entry that is on right now, in
                           the same slot list, wins the slot over the AutoAcc
                           piece (utils.flattenHead). Off: the AutoAcc piece
                           wins, and that entry is only its fallback.
      levelRange     (off) an entry with a level range, in the same slot
                           list, wins the slot over the AutoAcc piece.
      rangedAttacks  (on)  a ranged attack (Midshot) may release AutoAcc
                           pieces on the ranged hit rate (AscensionXI).

    Not a switch, a rule: while you are not engaged, every AutoAcc piece
    wears its fallback (dispatch.lua) -- there is nothing to hit.

    rev() moves on every change: dispatch folds it into its retrace
    signature, and utils.rebuildSets re-flattens on it (the two in-slot
    switches change what a set flattens to).

    Pure definitions at load; the file is touched only at call time, under
    pcall, so headless suites load this freely (M._dir is the seam).
]]--

local M = {};

M.DEFAULTS = { triggerRules = true, conditional = true, levelRange = false, rangedAttacks = true };
M.ORDER = { 'triggerRules', 'conditional', 'levelRange', 'rangedAttacks' };
M.FILE = 'autoaccrules.lua';

-- () -> the character's data dir (with its trailing separator), or nil
-- before login. Tests replace it.
M._dir = function()
    local ok, sf = pcall(require, 'dlac\\lib\\statefile');
    if not ok or type(sf) ~= 'table' or type(sf.charDir) ~= 'function' then return nil; end
    local ok2, d = pcall(sf.charDir);
    return ok2 and d or nil;
end;

local st = { dir = nil, vals = nil, rev = 0 };

local function defaults()
    local out = {};
    for k, v in pairs(M.DEFAULTS) do out[k] = v; end
    return out;
end

-- Loads once per character dir. Before login (no dir) the defaults answer
-- from memory; the first call with a dir reads that character's file.
local function load()
    local dir = M._dir();
    if st.vals ~= nil and dir == st.dir then return st.vals; end
    local vals = defaults();
    if dir ~= nil then
        pcall(function()
            local chunk = loadfile(dir .. M.FILE);
            if chunk == nil then return; end
            local ok, t = pcall(chunk);
            if not ok or type(t) ~= 'table' then return; end
            for k in pairs(M.DEFAULTS) do
                if type(t[k]) == 'boolean' then vals[k] = t[k]; end
            end
        end);
    end
    st.dir, st.vals = dir, vals;
    st.rev = st.rev + 1;
    return vals;
end

local function save(vals)
    local dir = M._dir();
    if dir == nil then return false; end
    local ok = pcall(function()
        local parts = {};
        for _, k in ipairs(M.ORDER) do parts[#parts + 1] = ('%s = %s'):format(k, tostring(vals[k] == true)); end
        local f = io.open(dir .. M.FILE, 'wb');
        if f == nil then error('open'); end
        f:write('-- dlac AutoAcc settings (Gear Helpers > AutoAcc). Safe to hand-edit.\n');
        f:write('return { ' .. table.concat(parts, ', ') .. ' }\n');
        f:close();
    end);
    return ok;
end

-- The value of one switch (its default when the name is unknown to the file).
function M.get(name)
    local v = load()[name];
    if v == nil then return M.DEFAULTS[name]; end
    return v;
end

-- Sets one switch and saves the file. Unknown names are refused.
function M.set(name, on)
    if M.DEFAULTS[name] == nil then return false; end
    local vals = load();
    on = (on == true);
    if vals[name] == on then return true; end
    vals[name] = on;
    st.rev = st.rev + 1;
    return save(vals);
end

-- Moves whenever a switch does (or another character's file is read).
function M.rev()
    load();
    return st.rev;
end

-- test seam: forget what was read
function M._reset() st.dir, st.vals = nil, nil; st.rev = st.rev + 1; end

return M;
