--[[
    dlac/groupscan.lua -- the pure "scan my Lua file for group tables" transform (Item 1; the
    auto-import sibling of groupimport.lua's paste-based "Import Lua Table(s)").

    A player who already keeps their spells grouped in their LuaAshitacast file
    (`local BlueSpells = { STR_DEX = T{...}, VIT = T{...} }`) shouldn't have to copy-paste:
    point the scanner at the file text and it surfaces every group-shaped table as an import
    candidate, ready for the same classify / apply + overwrite-confirm as the paste flow.

      scan(fileText) -> ( candidates { { name, members{...} }, ... }, notes { string, ... } )

    The player's group tables are usually `local` variables -- invisible to any sandbox-run env --
    so this is a TEXT scan: pull each top-level `[local] NAME = T?{...}` block, evaluate its body
    in groupimport's hardened sandbox (T = identity, no globals -> a hostile block errors, never
    runs), then classify the value:
      * a flat array of strings             -> one candidate named NAME (a directly-defined group,
                                               or a variant/config table the player can deselect)
      * a container of flat string arrays   -> one candidate per inner key (the BlueSpells case)
      * anything else (gear sets, settings) -> skipped, with a note

    Candidates are deduped case-insensitively and sorted (hard rule 8). The flat-array heuristic
    and the sandbox eval are groupimport's (membersOf / evalTable), so "is this a group?" lives in
    one place. Pure: no ImGui, no Ashita, no file IO -- the UI passes the file text. Addon-state
    only; never seeded into LAC.
]]--

local gimp = require("dlac\\gear\\groupimport");

local M = {};

-- Strip Lua comments so a stray brace in a comment can't unbalance the block scan. Block
-- comments first (they span lines), then line comments. Safe for this content -- action / gear
-- names never contain `--`.
local function stripComments(text)
    text = text:gsub('%-%-%[%[.-%]%]', ' ');
    text = text:gsub('%-%-[^\n]*', '');
    return text;
end

-- Return every top-level `[local ] NAME = T?{...}` as { name, body }. Walks balanced `%b{}`
-- blocks and never descends into one (i jumps past each block), so only the outermost
-- assignments are seen -- a gear set's inner `['Idle'] = {...}` is part of its parent's body,
-- not a top-level hit. Stops cleanly on the first unbalanced brace.
local function topLevelBlocks(text)
    local out, i, n = {}, 1, #text;
    while i <= n do
        local bs = string.find(text, '{', i, true);
        if bs == nil then break; end
        local _, be = string.find(text, '%b{}', bs);
        if be == nil then break; end                        -- unbalanced: stop scanning
        local prefix = string.sub(text, math.max(1, bs - 64), bs - 1);
        local name = string.match(prefix, '([%a_][%w_]*)%s*=%s*T?%s*$');
        if name ~= nil then
            out[#out + 1] = { name = name, body = string.sub(text, bs, be) };
        end
        i = be + 1;                                         -- top-level only: skip past this block
    end
    return out;
end

-- The pure transform. See the header. Returns (candidates, notes).
function M.scan(fileText)
    local candidates, notes, seen = {}, {}, {};
    if type(fileText) ~= 'string' or fileText == '' then return candidates, notes; end

    local function addCandidate(name, members)
        if type(members) ~= 'table' or #members == 0 then return; end
        local key = string.lower(tostring(name));
        if seen[key] ~= nil then return; end                -- first spelling wins (dedup CI)
        seen[key] = true;
        candidates[#candidates + 1] = { name = tostring(name), members = members };
    end

    for _, blk in ipairs(topLevelBlocks(stripComments(fileText))) do
        local val = gimp.evalTable(blk.body);
        if type(val) ~= 'table' then
            notes[#notes + 1] = string.format('"%s" skipped: could not be read as a table.', blk.name);
        else
            local members = gimp.membersOf(val);            -- a flat array of strings?
            if members ~= nil then
                addCandidate(blk.name, members);            -- a directly-defined group / variant table
            else
                -- a container of groups, or a gear set: pull each inner key that is a flat list.
                local inner = {};                            -- collect then sort (hard rule 8)
                for k, v in pairs(val) do
                    if type(k) == 'string' and type(v) == 'table' then
                        local m = gimp.membersOf(v);
                        if m ~= nil and #m > 0 then inner[#inner + 1] = { name = k, members = m }; end
                    end
                end
                table.sort(inner, function(a, b) return a.name < b.name; end);
                if #inner == 0 then
                    notes[#notes + 1] = string.format('"%s" skipped: no group-shaped lists inside (gear sets / settings).', blk.name);
                else
                    for _, c in ipairs(inner) do addCandidate(c.name, c.members); end
                end
            end
        end
    end
    table.sort(candidates, function(a, b) return string.lower(a.name) < string.lower(b.name); end);
    return candidates, notes;
end

return M;
