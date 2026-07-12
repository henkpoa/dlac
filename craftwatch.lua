--[[
    dlac/craftwatch.lua -- synthesis detection (Piece 1: OBSERVE + REPORT ONLY).

    Answers "am I crafting, and WHICH craft?" so craft gear sets can follow.
    Auto-equip is deliberately NOT wired yet -- detection gets field-verified
    first (dlacprobe style), then a later piece maps craft -> set -> equip.

    How: outgoing packet 0x096 GP_CLI_COMMAND_COMBINE_ASK (XiPackets) carries
    the catalyst + ingredient list of the synth being confirmed:
        Crystal u16 @0x06 | CrystalIdx u8 @0x08 | Items u8 @0x09
        ItemNo[8] u16 @0x0A..0x19 | TableNo[8] u8 @0x1A..0x21
    The crystal id + ingredient MULTISET identify the recipe; crafts.lua
    (generated from the server's own synth_recipes.sql by tools/gen_craftdb.py,
    ships with the addon -- nothing is fetched at runtime) maps it to the craft
    skill and required level. Unknown recipes (CatsEyeXI customs live in the
    private repo) fail soft and are reported once, with the lookup key, so the
    maintainer can collect them.

    TIMING TRUTH (LSB synthutils): the server rolls the synth result the moment
    0x096 ARRIVES -- gear equipped on detection lands during the animation and
    counts from the NEXT synth on, not this one. First-synth coverage will need
    a pre-flip (craft mode) or synthesis-menu detection (future probe).

    Pure data core (key/decode/lookup) is headless-testable; Ashita glue below.
]]--

local M = {};

-- ---------------------------------------------------------------------------
-- pure core
-- ---------------------------------------------------------------------------

-- crafts.lua lookup key: crystal id + ingredient ids sorted ascending (the
-- client sends placement order; the db stores a canonical order -- the
-- multiset is what identifies the recipe).
function M.key(crystal, ings)
    local s = {};
    for i = 1, #ings do s[i] = ings[i]; end
    table.sort(s);
    return string.format('%d:%s', crystal, table.concat(s, ','));
end

-- Decode a raw 0x096 packet (string, includes the 4-byte header).
-- Returns crystal id, ingredient id list -- or nil if malformed.
function M.decode(data)
    if type(data) ~= 'string' or #data < 0x1A then return nil; end
    local function b(o) return string.byte(data, o + 1) or 0; end
    local function u16(o) return b(o) + b(o + 1) * 256; end
    local crystal = u16(0x06);
    local n = b(0x09);
    if crystal == 0 or n == 0 or n > 8 then return nil; end
    local ings = {};
    for i = 0, n - 1 do
        local id = u16(0x0A + i * 2);
        if id ~= 0 then ings[#ings + 1] = id; end
    end
    if #ings == 0 then return nil; end
    return crystal, ings;
end

-- Recipe database (bundled; absence degrades to every synth reading 'unknown').
local _dbok, _db = pcall(require, 'dlac\\crafts');
if not _dbok or type(_db) ~= 'table' then _db = {}; end
function M.setDb(db) _db = db or {}; end            -- test seam

-- nil when the recipe is unknown (custom / not in the public SQL).
function M.lookup(crystal, ings)
    return _db[M.key(crystal, ings)];
end

-- ---------------------------------------------------------------------------
-- session state + Ashita glue
-- ---------------------------------------------------------------------------

M.current = nil;    -- { skill, lv, desynth, key, at } of the most recent synth
M.counts  = {};     -- skill -> synths seen this session (includes 'unknown')

local _cfok, _cfmt = pcall(require, 'dlac\\chatfmt');
_cfok = _cfok and type(_cfmt) == 'table';
local function say(s) if _cfok and _cfmt.msg then _cfmt.msg(s); else print('[dlac] ' .. s); end end

local _saidUnknown = {};   -- key -> true (report each unknown recipe once)

-- Process one detected synth; returns the record (also used by tests).
function M.onSynth(crystal, ings, clock)
    local rec = M.lookup(crystal, ings);
    local skill = rec and rec.skill or 'unknown';
    M.counts[skill] = (M.counts[skill] or 0) + 1;
    local prev = M.current;
    M.current = {
        skill = skill, lv = rec and rec.lv or nil,
        desynth = rec and rec.desynth or nil,
        key = M.key(crystal, ings), at = clock or os.clock(),
    };
    if rec ~= nil then
        if prev == nil or prev.skill ~= skill then     -- announce on craft change only
            say(string.format('synth detected: %s (recipe lv %d%s) -- craft sets will hook here.',
                skill, rec.lv or 0, rec.desynth and ', desynth' or ''));
        end
    elseif not _saidUnknown[M.current.key] then        -- each unknown once, with the key
        _saidUnknown[M.current.key] = true;
        say(string.format('synth detected, recipe UNKNOWN (key %s) -- likely a CatsEyeXI custom; '
            .. 'tell the maintainer so crafts.lua can learn it.', M.current.key));
    end
    return M.current;
end

if ashita ~= nil and ashita.events ~= nil and type(ashita.events.register) == 'function' then
    ashita.events.register('packet_out', 'dlac-craftwatch-out', function(e)
        if e.id ~= 0x096 then return; end
        pcall(function()
            local crystal, ings = M.decode(e.data);
            if crystal ~= nil then M.onSynth(crystal, ings); end
        end);
    end);

    -- /dl craft -- session status (what detection has seen so far).
    ashita.events.register('command', 'dlac-craftwatch-cmd', function(e)
        pcall(function()
            local raw = string.lower(e.command or '');
            local a = raw:match('^/dl%s+(%S+)') or raw:match('^/dlac%s+(%S+)');
            if a ~= 'craft' then return; end
            e.blocked = true;
            if M.current == nil then
                say('craft watch: no synth seen yet this session. Start a synth and check again.');
                return;
            end
            say(string.format('craft watch: last synth = %s%s (%.0fs ago).',
                M.current.skill, M.current.lv and (' lv ' .. M.current.lv) or '',
                os.clock() - (M.current.at or 0)));
            local parts = {};
            for sk, n in pairs(M.counts) do parts[#parts + 1] = string.format('%s x%d', sk, n); end
            table.sort(parts);
            say('  session: ' .. table.concat(parts, ', '));
        end);
    end);
end

return M;
