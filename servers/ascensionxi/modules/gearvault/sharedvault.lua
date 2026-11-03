--[[
    ascensionxi/gearvault/sharedvault.lua -- what the Shared Vault tab DOES and
    SAYS (Group Ironman, AscensionXI only). The wire is vaultclient's (its
    "SHARED VAULT" section); vaultui draws the tab. Kept apart from imgui so
    the suite drives every rule headless.

    The server's rules this leans on (group_ironman_vault.lua, decision S12):
      * one piece per click (rule 8): one share or take at a time;
      * a piece in your job layouts asks once (rule 1), and an unworn piece
        in a Mog Wardrobe always asks once (rule 2). The server answers
        NEEDS_CONFIRM with the layouts it is in; the question names them, and
        only a yes sends the share again -- with the confirm flag, as a new
        request. A no sends nothing;
      * pieces only (rule 3), one Rare copy however inscribed (rule 4), and
        the sharer's chat line when someone takes their piece (rule 5) are
        the server's: here they are only refusal codes put into words.
]]--

local M = {};

local vc = require('dlac\\servers\\ascensionxi\\modules\\gearvault\\vaultclient');

M.CONFIRM_TTL = 60;   -- seconds an unanswered question stays open

M._clock = function() return vc._clock(); end;
M._note  = nil;       -- function(text, isErr): the tab's result line and chat (vaultui sets it)

local function note(text, isErr)
    if type(M._note) == 'function' then pcall(M._note, text, isErr == true); return; end
    print('[dlac] shared vault: ' .. tostring(text));
end

-- ---------------------------------------------------------------------------
-- Words
-- ---------------------------------------------------------------------------

-- The refusals a share or a take can meet (GroupIronmanCode), in the server's
-- own words where it has them (group_ironman_vault.lua, sv.refusal).
M.REFUSAL =
{
    [vc.giCode.NOT_IN_GROUP]   = 'you are not in a Group Ironman group',
    [vc.giCode.BUSY]           = 'your group is busy with another change -- try again in a moment',
    [vc.giCode.STORE_ERROR]    = 'something went wrong; nothing moved -- try again shortly',
    [vc.giCode.CLOSED]         = 'your group has closed',
    [vc.giCode.STAYS_WITH_YOU] = 'it stays with you: it can be replaced for free, so it cannot be shared',
    [vc.giCode.SHELF_CAP]      = 'the Shared Vault already holds as many of that piece as it can',
    [vc.giCode.RARE_IN_STORE]  = 'the Shared Vault already holds that Rare piece',
    [vc.giCode.NEEDS_CONFIRM]  = 'it is in your job layouts and needs your yes first',
    [vc.giCode.NOT_ELIGIBLE]   = 'only single pieces of gear go in the Shared Vault; materials go to the group pool',
    [vc.giCode.NO_ROW]         = 'that piece is not there any more -- refreshing',
    [vc.giCode.RARE_HELD]      = 'you already have one of that Rare piece',
    [vc.giCode.DUPLICATE]      = 'your Gear Vault already holds that piece (or its pair)',
    [vc.giCode.ITEM_BUSY]      = 'you cannot do that right now',
};

-- A whole frame refused or lost (vaultclient's err words).
M.ERR =
{
    too_far      = 'stand at a Gear Vault to use the Shared Vault',
    not_attuned  = 'finish The Deeper Room first -- the vault does not know you yet',
    busy         = 'the server is busy -- try again',
    unavailable  = 'the Shared Vault is unavailable right now',
    malformed    = 'the answer did not parse -- please report this',
    timeout      = 'no answer -- the outcome is unknown, re-reading your Gear Vault and the Shared Vault',
    not_in_group = 'you are no longer in a group',
};

function M.refusalWords(code)
    return M.REFUSAL[code] or string.format('refused (code %s)', tostring(code));
end

function M.errWords(err)
    return M.ERR[err] or string.format('failed (%s)', tostring(err));
end

local function jobAbbr(id)
    local ok, jg = pcall(require, 'dlac\\gear\\jobgate');
    local abbr = (ok and type(jg) == 'table' and type(jg.JOBS) == 'table') and jg.JOBS[id] or nil;
    return abbr or ('job ' .. tostring(id));
end

-- { 1, 7, 5 } -> 'WAR, PLD and RDM'
function M.jobList(jobs)
    local names = {};
    for _, j in ipairs(jobs or {}) do names[#names + 1] = jobAbbr(j); end
    if #names <= 1 then return names[1] or ''; end
    return table.concat(names, ', ', 1, #names - 1) .. ' and ' .. names[#names];
end

-- The question NEEDS_CONFIRM asks, as short lines (a popup does not wrap).
function M.confirmLines(c)
    local lines = { string.format('Share %s with your group?', c.name) };
    local n = #(c.jobs or {});
    if c.wardrobe then
        lines[#lines + 1] = 'It is in your Mog Wardrobe.';
        lines[#lines + 1] = 'Sharing it also removes it from any job layout that uses it.';
    elseif n > 0 then
        lines[#lines + 1] = string.format('It is in your %s layout%s.', M.jobList(c.jobs), (n == 1) and '' or 's');
        lines[#lines + 1] = string.format('Sharing it removes it from %s, pins included.',
            (n == 1) and 'that layout' or 'those layouts');
    else
        lines[#lines + 1] = 'It is in your job layouts.';
        lines[#lines + 1] = 'Sharing it removes it from them, pins included.';
    end
    return lines;
end

-- ---------------------------------------------------------------------------
-- State: the open question and the moves on their way
-- ---------------------------------------------------------------------------

M._confirm = nil;    -- { target, jobs, wardrobe, name, at }: NEEDS_CONFIRM's question
M._taking  = {};     -- shelfRowId -> true while its take is out
M._sharing = {};     -- 'v:<vaultRowId>' | 'w:<container>:<slot>' -> true while its share is out

function M._reset()
    M._confirm, M._taking, M._sharing = nil, {}, {};
end

-- The open question, or nil once answered, after CONFIRM_TTL, or once the
-- tab is gone (the group was left).
function M.pendingConfirm()
    local c = M._confirm;
    if c ~= nil and (M._clock() - c.at > M.CONFIRM_TTL or not vc.shelfAvailable()) then
        M._confirm = nil;
        return nil;
    end
    return c;
end

-- One piece at a time: a move on its way, or a question waiting for its answer.
function M.busy()
    return vc.shelfBusy() or M.pendingConfirm() ~= nil;
end

-- A move counts as on its way only while the client still holds a write
-- (a reload or a character switch drops the queue without an answer).
function M.isTaking(rowId) return M._taking[rowId] == true and vc.shelfBusy(); end
function M.isSharingRow(rowId) return M._sharing['v:' .. tostring(rowId)] == true and vc.shelfBusy(); end
function M.isSharingSlot(container, slot)
    return M._sharing['w:' .. tostring(container) .. ':' .. tostring(slot)] == true and vc.shelfBusy();
end

local function shareKey(t)
    if (t.vaultRowId or 0) > 0 then return 'v:' .. tostring(t.vaultRowId); end
    return 'w:' .. tostring(t.container) .. ':' .. tostring(t.slot);
end

-- ---------------------------------------------------------------------------
-- Moves
-- ---------------------------------------------------------------------------

-- One share on the wire. `confirm` only for the resend after a yes.
local function put(t, confirm)
    local key = shareKey(t);
    M._sharing[key] = true;
    local queued = vc.requestShelfPut({ vaultRowId = t.vaultRowId, container = t.container, slot = t.slot,
        itemId = t.itemId, confirm = confirm }, function(ack, err)
        M._sharing[key] = nil;
        if ack == nil then
            note(t.name .. ': ' .. M.errWords(err), true);
        elseif ack.code == vc.giCode.OK then
            note(string.format('shared %s with your group', t.name));
        elseif ack.code == vc.giCode.NEEDS_CONFIRM and not confirm then
            -- nothing moved: ask, and send again only on a yes
            M._confirm = { target = t, jobs = ack.jobs or {}, wardrobe = ack.wardrobe == true,
                           name = t.name, at = M._clock() };
        else
            note(t.name .. ': ' .. M.refusalWords(ack.code), true);
        end
    end);
    if not queued then
        M._sharing[key] = nil;
        note('could not send the share -- the Shared Vault is not open for you right now', true);
    end
    return queued;
end

local function nameOf(e)
    return e.name or ('#' .. tostring(e.itemId));
end

-- Share one piece from your own vault: a Vault tab row (rowId, itemId, qty, name).
function M.shareVaultRow(row)
    if type(row) ~= 'table' or (row.rowId or 0) <= 0 then return false; end
    if (row.qty or 1) > 1 then
        note(nameOf(row) .. ': ' .. M.refusalWords(vc.giCode.NOT_ELIGIBLE), true);
        return false;
    end
    if M.busy() then note('one piece at a time -- wait for the last one to finish', true); return false; end
    return put({ vaultRowId = row.rowId, itemId = row.itemId, name = nameOf(row) }, false);
end

-- Share an unworn piece from a Mog Wardrobe (container, slot, itemId, name).
-- The server always asks first: it is the vault's cache of your layouts.
function M.shareWardrobe(piece)
    if type(piece) ~= 'table' or piece.container == nil or piece.slot == nil then return false; end
    if M.busy() then note('one piece at a time -- wait for the last one to finish', true); return false; end
    return put({ container = piece.container, slot = piece.slot, itemId = piece.itemId, name = nameOf(piece) }, false);
end

-- The answer to the question: yes sends the share again WITH the confirm
-- flag; no forgets it -- nothing was sent, nothing moved.
function M.confirm(agree)
    local c = M.pendingConfirm();
    M._confirm = nil;
    if c == nil or not agree then return false; end
    return put(c.target, true);
end

-- Take one piece from the shelf into your own vault (a shelf row: rowId, itemId, name).
function M.take(row)
    if type(row) ~= 'table' or (row.rowId or 0) <= 0 then return false; end
    if M.busy() then note('one piece at a time -- wait for the last one to finish', true); return false; end
    local name, rowId = nameOf(row), row.rowId;
    M._taking[rowId] = true;
    local queued = vc.requestShelfTake({ shelfRowId = rowId, itemId = row.itemId }, function(ack, err)
        M._taking[rowId] = nil;
        if ack == nil then
            note(name .. ': ' .. M.errWords(err), true);
        elseif ack.code == vc.giCode.OK then
            note(string.format('took %s into your Gear Vault', name));
        else
            note(name .. ': ' .. M.refusalWords(ack.code), true);
        end
    end);
    if not queued then
        M._taking[rowId] = nil;
        note('could not send the take -- the Shared Vault is not open for you right now', true);
    end
    return queued;
end

-- ---------------------------------------------------------------------------
-- Readers for the tab
-- ---------------------------------------------------------------------------

-- Who shared a row, or nil when the member list cannot say.
function M.sharerName(charId)
    local n = ((vc.shelf or {}).names or {})[charId];
    return (type(n) == 'string' and n ~= '') and n or nil;
end

-- 'Alice (leader), Bob': the members still in the group.
function M.memberLine()
    local out = {};
    for _, m in ipairs((vc.shelf or {}).members or {}) do
        if m.active then out[#out + 1] = m.name .. (m.leader and ' (leader)' or ''); end
    end
    return table.concat(out, ', ');
end

-- The tab's count: the rows read, or the server's count before the first read.
function M.count()
    local sh = vc.shelf or {};
    if sh.stamp ~= nil then return #(sh.rows or {}); end
    return sh.count or 0;
end

return M;
