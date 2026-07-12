--[[
    dlac/gearfmt.lua -- small display / format helpers for the gear UI.

    Split out of gearui.lua: LuaJIT caps a chunk at 200 local variables, and gearui's
    main chunk was already at it -- cohesive helpers get their own module from now on.

    Pure text formatters (esc/truncate/jobsText/statSummary/fullStatList) plus the two
    imgui-measuring helpers (textWrapped/nameWidthOf) and the owned-quantity tag
    (qtyTag). gearui injects its live deps once via M.configure:
      effStats(rec, level) -- level-scaled stats of a record (latents resolved)
      ownedCounts()        -- live owned quantities { itemId -> n } (avail bags)
    Everything else here depends only on stock Lua and the shared imgui lib.
]]--

local M = {};

local _iok, imgui = pcall(require, 'imgui');

-- Injected by gearui (M.configure): effStats, ownedCounts.
local deps = nil;
function M.configure(d) deps = d; end

local function esc(s) return (tostring(s):gsub('%%', '%%%%')); end

local function truncate(s, n)
    s = tostring(s or '');
    if #s <= n then return s; end
    return s:sub(1, n - 2) .. '..';
end

-- TextColored that wraps at the window edge instead of clipping off-screen.
-- For standalone status/instruction lines only -- not for text in SameLine rows.
local function textWrapped(col, s)
    imgui.PushTextWrapPos(0.0);
    imgui.TextColored(col, s);
    imgui.PopTextWrapPos();
end

local function sortedKeys(t)
    local ks = {};
    for k in pairs(t) do ks[#ks + 1] = k; end
    table.sort(ks);
    return ks;
end

local function jobsText(jobs)
    if jobs == nil then return 'All'; end
    if type(jobs) ~= 'table' or #jobs == 0 then return 'All'; end
    return table.concat(jobs, '/');
end

local function fmtStat(k, v)
    if type(v) == 'boolean' then return k; end
    if type(v) == 'number' then return k .. ((v >= 0) and '+' or '') .. tostring(v); end
    return k .. ':' .. tostring(v);
end

-- Priority order for compact summaries / totals; anything else comes after, alpha.
local STAT_PRIORITY = {
    'DMG', 'Delay', 'DEF', 'HP', 'MP', 'Accuracy', 'Attack', 'Haste',
    'MATK', 'MagicAttack', 'RangedAccuracy', 'STR', 'DEX', 'VIT', 'AGI',
    'INT', 'MND', 'CHR', 'Evasion', 'Enmity', 'StoreTP',
};

-- Compact (<=4 token) stat line for rows. Memoized on the record (per level, so
-- level-scaled items re-render when the character's level changes).
local function statSummary(rec, level)
    local lvlKey = level or -1;
    if rec._statStr ~= nil and rec._statLvl == lvlKey then return rec._statStr; end
    local stats = (deps ~= nil and deps.effStats ~= nil) and deps.effStats(rec, level) or nil;
    local out = '';
    if type(stats) == 'table' then
        local parts, used = {}, {};
        for _, k in ipairs(STAT_PRIORITY) do
            local v = stats[k];
            if v ~= nil and type(v) ~= 'table' then
                parts[#parts + 1] = fmtStat(k, v); used[k] = true;
                if #parts >= 4 then break; end
            end
        end
        if #parts < 4 then
            for k, v in pairs(stats) do
                if not used[k] and type(k) == 'string' and type(v) ~= 'table' then
                    parts[#parts + 1] = fmtStat(k, v);
                    if #parts >= 4 then break; end
                end
            end
        end
        out = table.concat(parts, ' ');
    end
    rec._statStr, rec._statLvl = out, lvlKey;
    return out;
end

-- Full stat line for the tooltip (all stats, priority first, DMG/Delay & Pet omitted).
local function fullStatList(stats)
    if type(stats) ~= 'table' then return ''; end
    local parts, used = {}, {};
    for _, k in ipairs(STAT_PRIORITY) do
        local v = stats[k];
        if v ~= nil and type(v) ~= 'table' and k ~= 'DMG' and k ~= 'Delay' then
            parts[#parts + 1] = fmtStat(k, v); used[k] = true;
        end
    end
    for k, v in pairs(stats) do
        if type(k) == 'string' and not used[k] and type(v) ~= 'table' and k ~= 'DMG' and k ~= 'Delay' then
            parts[#parts + 1] = fmtStat(k, v);
        end
    end
    return table.concat(parts, ' ');
end

-- "xN" owned tag (only when we own two or more -- the interesting case for DW /
-- paired slots). Empty otherwise. Contains no '%'.
local function qtyTag(rec)
    local oc = (deps ~= nil and deps.ownedCounts ~= nil) and deps.ownedCounts() or nil;
    local c = (rec and rec.Id and oc ~= nil) and oc[rec.Id] or nil;
    if c ~= nil and c >= 2 then return '  x' .. tostring(c); end
    return '';
end

-- "Aug: <first> (+N)" tag for the augments on YOUR owned copy (by id) -- render
-- it in the gold COL_SCORE so augmented copies stand out wherever gear is being
-- chosen or viewed. Empty string when the copy is unaugmented (or dep missing).
local function augTag(rec)
    local f = (deps ~= nil) and deps.ownedAugs or nil;
    if f == nil or rec == nil or rec.Id == nil then return ''; end
    local al = f()[rec.Id];
    if type(al) ~= 'table' or #al == 0 then return ''; end
    local txt = tostring(al[1]);
    if #al > 1 then txt = txt .. string.format(' (+%d)', #al - 1); end
    return 'Aug: ' .. txt;
end

-- Static name-column width for a record list: the longest name decides (capped),
-- so rows align. Shared by the Equipped alternatives and the All Equipment tree.
local function nameWidthOf(list)
    local w = 120;
    for _, rec in ipairs(list) do
        local ok, tw = pcall(imgui.CalcTextSize, tostring(rec.Name or '?'));
        if not ok or type(tw) ~= 'number' then tw = #tostring(rec.Name or '?') * 7; end
        if tw + 14 > w then w = tw + 14; end
    end
    return math.min(w, 260);
end

M.esc          = esc;
M.truncate     = truncate;
M.textWrapped  = textWrapped;
M.sortedKeys   = sortedKeys;
M.jobsText     = jobsText;
M.statSummary  = statSummary;
M.fullStatList = fullStatList;
M.qtyTag       = qtyTag;
M.augTag       = augTag;
M.nameWidthOf  = nameWidthOf;

return M;
