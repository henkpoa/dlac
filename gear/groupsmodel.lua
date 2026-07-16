--[[
    dlac/groupsmodel.lua -- the pure Trigger-Groups model core (issue #25, G2; PRD #21, ADR 0009).

    A Group is a named, untyped list of action names stored per Job entry in the trigger
    file's `Groups` section (beside `Modes`) -- the engine half (G1) matches `when = { group }`
    against the current action's name. G2 is the GUI half: the Groups tab creates / renames /
    deletes groups and adds / removes typed members, and the trigger editor offers `group` as a
    condition whose value is a dropdown of the current job's groups.

    This module is the pure, ImGui-free, Ashita-free, file-IO-free core the headless suite pins
    (tests TGM*): CRUD on a groups table plus name / member validation. triggersui draws the tab
    and calls these; the group storage shape is exactly what dispatch.serializeTriggers emits and
    dispatch.ensureLoaded reads --

      groups = { ['STR Spells'] = { 'Hysteric Barrage', 'Quad. Continuum' }, ... }

    a group NAME -> an ordered array of member action names. An empty member list is legal (a
    group you are still building). Group names and member names both compare case-insensitively,
    mirroring the engine's M.groupMatch. Addon-state only -- never seeded into LAC.
]]--

local M = {};

local function trim(s)
    return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''));
end
local function ci(a, b) return string.lower(tostring(a)) == string.lower(tostring(b)); end

-- Extract + sanitize the Groups section from a raw trigger-file table into the model
-- shape (name -> string-member array). Tolerates `Groups` or `groups`, drops non-string
-- names / non-table member lists / empty member strings; member order is preserved.
-- Returns a fresh table (nil-safe: a file with no Groups yields {}). triggersui.fileToModel
-- delegates here so the round-trip carry-through has one tested home (the SetOptions/Modes
-- wipe lesson: a section the model does not carry gets erased on the next Commit).
function M.fromRaw(raw)
    local out = {};
    if type(raw) ~= 'table' then return out; end
    local gr = raw.Groups or raw.groups;
    if type(gr) ~= 'table' then return out; end
    for nm, mem in pairs(gr) do
        if type(nm) == 'string' and trim(nm) ~= '' and type(mem) == 'table' then
            local members = {};
            for _, a in ipairs(mem) do
                if type(a) == 'string' and trim(a) ~= '' then members[#members + 1] = a; end
            end
            out[nm] = members;
        end
    end
    return out;
end

-- Group names, case-insensitively sorted -- the dropdown / nav order.
function M.names(groups)
    local out = {};
    if type(groups) == 'table' then
        for nm in pairs(groups) do
            if type(nm) == 'string' then out[#out + 1] = nm; end
        end
    end
    table.sort(out, function(a, b) return string.lower(a) < string.lower(b); end);
    return out;
end

-- Does a group with this name exist (case-insensitive)? Returns the STORED name (the
-- exact key) or nil -- callers edit under the stored spelling, not the query's.
function M.findName(groups, name)
    if type(groups) ~= 'table' then return nil; end
    for nm in pairs(groups) do
        if type(nm) == 'string' and ci(nm, name) then return nm; end
    end
    return nil;
end

function M.hasGroup(groups, name) return M.findName(groups, name) ~= nil; end

-- Validate a proposed group name. `current` (optional) is the existing name when renaming,
-- so a group may keep its own spelling. Rejects blank names and case-insensitive duplicates.
-- Returns ok, err (err is a player-facing reason on failure).
function M.validateName(groups, name, current)
    local t = trim(name);
    if t == '' then return false, 'Name cannot be empty.'; end
    local existing = M.findName(groups, t);
    if existing ~= nil and (current == nil or not ci(existing, current)) then
        return false, string.format('A group named "%s" already exists.', existing);
    end
    return true;
end

-- Create an empty group. Returns ok, err.
function M.add(groups, name)
    local ok, err = M.validateName(groups, name);
    if not ok then return false, err; end
    groups[trim(name)] = {};
    return true;
end

-- Rename, preserving members and their order. Returns ok, err.
function M.rename(groups, old, new)
    local key = M.findName(groups, old);
    if key == nil then return false, string.format('No group named "%s".', tostring(old)); end
    local ok, err = M.validateName(groups, new, key);
    if not ok then return false, err; end
    local members = groups[key];
    groups[key] = nil;
    groups[trim(new)] = members;
    return true;
end

-- Delete a group (leaves any trigger referencing it dangling -- surfaced in the Triggers
-- tab, parity with a missing set; hard rule 12). Returns ok, err.
function M.remove(groups, name)
    local key = M.findName(groups, name);
    if key == nil then return false, string.format('No group named "%s".', tostring(name)); end
    groups[key] = nil;
    return true;
end

-- Validate a proposed member of `group`. Rejects blank names and case-insensitive
-- duplicates within the SAME group. Returns ok, err.
function M.validateMember(groups, name, action)
    local key = M.findName(groups, name);
    if key == nil then return false, string.format('No group named "%s".', tostring(name)); end
    local t = trim(action);
    if t == '' then return false, 'Type an action name first.'; end
    for _, m in ipairs(groups[key]) do
        if ci(m, t) then return false, string.format('"%s" is already in this group.', m); end
    end
    return true;
end

-- Add a typed member (free-name; the browse-list picker is a later slice / issue #12).
-- Returns ok, err.
function M.addMember(groups, name, action)
    local ok, err = M.validateMember(groups, name, action);
    if not ok then return false, err; end
    local key = M.findName(groups, name);
    table.insert(groups[key], trim(action));
    return true;
end

-- Remove a member (case-insensitive match). Returns ok, err.
function M.removeMember(groups, name, action)
    local key = M.findName(groups, name);
    if key == nil then return false, string.format('No group named "%s".', tostring(name)); end
    for i = #groups[key], 1, -1 do
        if ci(groups[key][i], action) then
            table.remove(groups[key], i);
            return true;
        end
    end
    return false, string.format('"%s" is not in this group.', tostring(action));
end

return M;
