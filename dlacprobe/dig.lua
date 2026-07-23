--[[
    dlacprobe/dig.lua -- /probe dig: confirm the dig-rank mask + calibrate the
    first-dig timing read in the field (issue #96, parent PRD #93).

    OBSERVATION ONLY -- injects NOTHING. It reads the client, hexdumps incoming
    skills packets, watches the dig chat lines and the player's own outgoing dig
    attempts, and writes timestamped lines to probe_log.txt. It never sends a
    packet, never queues a command, never blocks game traffic (only the
    `/probe dig` command line itself is consumed).

    Run once by the maintainer to (a) prove the dig rank is masked out of the
    client, and (b) validate the timing ladder before dlac's timing auto-detect
    (a later PRD #93 slice) is trusted.

    WHY the dig rank is invisible: the dig skill is skill id 59 on the wire. The
    server blanks it to 0xFFFF in the only packet that could carry it (0x062
    skills), so the live read GetCraftSkill(11) returns the sentinel forever.
    There is no NPC, command, or packet that reveals it -- the ONE side-channel
    is timing: the server gates the first dig after a zone-in until
    (60 - 5*rank) seconds elapse (rank 0 -> 60s ... rank 8 -> 20s), and a
    cooldown-rejected dig is FREE (no Gysahl Green consumed). So the
    reject -> first-success bracket pins the rank via (60 - threshold) / 5.

    WHAT it captures while armed:
      - a one-shot GetCraftSkill(0..15) Raw/Skill/Rank dump (index 11 = Digging;
        expected raw 0xFFFF -> skill 255, rank 31 -- the mask signature), plus a
        GetCombatSkill control line proving the probe reads skills fine and only
        support skills 58-63 are blanked;
      - a hexdump of every incoming 0x062 with word[59] (wire offset 0x80 + 59*2)
        decoded and labelled MASKED/REAL;
      - the dig chat lines (Obtained / dig-and-dig-nothing / wait-longer /
        with-ease), timestamped;
      - zone-in -> every outgoing dig attempt (0x01A) -> the reject -> first-
        success transition, timestamped, with the rank the bracket implies.

    Drop-in for the standalone dlacprobe addon: this file follows dlacprobe's
    hunt idioms (command dispatch, packet_in / packet_out / text_in registration,
    timestamped probe_log.txt writes) and self-registers its Ashita event
    handlers guarded by an `armed` flag, so the host only has to load it and add
    a `/probe dig` help line. See dlacprobe/README.md for the two-line wiring.

    Lua 5.1 / LuaJIT compatible (no bit library, no 5.3 bit operators) so the
    pure core is headless-testable on lua5.4 -- see dlacprobe/tests/dig_test.lua.
]]--

local M = { armed = false };

-- ===========================================================================
-- pure core (no Ashita / no IO -- headless-testable)
-- ===========================================================================

local P = {};
M.pure = P;

-- The Digging skill's word in the 0x062 skills packet: word[59] at the wire
-- byte offset the issue names, 0x80 + 59*2.
P.WIRE_DIG_OFF = 0x80 + 59 * 2;

-- The server's mask sentinel. A masked word reads as skill 255 / rank 31 under
-- the decode below -- the "0xFFFF signature".
P.MASK_WORD = 0xFFFF;

-- Decode a 16-bit skill word (a GetCraftSkill value or a 0x062 wire word) into
-- { raw, skill, rank, masked }. Bit maths done with arithmetic so the file
-- stays LuaJIT/5.1-and-5.4 compatible:
--   rank  = low 5 bits          = raw % 32
--   skill = next 8 bits         = floor(raw / 32) % 256
-- A raw of 0xFFFF yields skill 255 / rank 31 and masked = true (issue #96).
function P.decodeSkillWord(raw)
    raw = raw or 0;
    return {
        raw = raw,
        skill = math.floor(raw / 32) % 256,
        rank = raw % 32,
        masked = (raw == P.MASK_WORD),
    };
end

-- Little-endian u16 at 0-based byte offset `off` in a packet string; nil if the
-- read would run past the end (a short/legacy packet can never over-read).
function P.u16(data, off)
    if type(data) ~= 'string' then return nil; end
    local a = string.byte(data, off + 1);
    local b = string.byte(data, off + 2);
    if a == nil or b == nil then return nil; end
    return a + b * 256;
end

-- Decode the Digging word straight out of a raw 0x062 packet string, or nil if
-- the packet is too short to carry word[59].
function P.digWordFromPacket(data)
    local raw = P.u16(data, P.WIRE_DIG_OFF);
    if raw == nil then return nil; end
    return P.decodeSkillWord(raw);
end

-- Classify a dig chat line. Returns (tag, item) where tag is one of
-- 'obtained' | 'nothing' | 'wait' | 'ease', or nil for a non-dig line.
--   obtained -> a completed dig that yielded an item (item name captured)
--   nothing  -> a completed dig that found nothing (cooldown HAD elapsed)
--   ease     -> a completed dig phrased "with ease"
--   wait     -> a FREE cooldown reject (dig came too soon; no green consumed)
-- Matching is case-insensitive substring so minor server wording drift still
-- registers -- this is a calibration probe, so over-catching is preferred to
-- missing a transition.
function P.classifyDigText(msg)
    if type(msg) ~= 'string' then return nil; end
    local s = string.lower(msg);
    -- reject first: "wait a little while longer" / "wait longer"
    if s:find('wait', 1, true) and (s:find('longer', 1, true) or s:find('little while', 1, true)) then
        return 'wait';
    end
    -- obtained: "Obtained: <item>."
    local item = msg:match('[Oo]btained:%s*(.-)%.?%s*$');
    if item ~= nil and item ~= '' then return 'obtained', item; end
    if s:find('with ease', 1, true) then return 'ease'; end
    if s:find('dig and you dig', 1, true) or s:find('find nothing', 1, true)
        or s:find('but find nothing', 1, true) then
        return 'nothing';
    end
    return nil;
end

-- A completed dig (cooldown had elapsed) vs a free reject.
function P.isCompletedDig(tag)
    return tag == 'obtained' or tag == 'nothing' or tag == 'ease';
end

-- The first-dig cooldown bracket -> dig rank. The server gates the first dig
-- until (60 - 5*rank)s, so rank = round((60 - threshold) / 5), snapped/clamped
-- to the 0..8 ladder. `threshold` is seconds since zone-in at the first
-- completed dig (an upper bound; the last free reject is the lower bound).
function P.rankFromThreshold(threshold)
    if type(threshold) ~= 'number' then return nil; end
    local r = (60 - threshold) / 5;
    r = math.floor(r + 0.5);
    if r < 0 then r = 0; end
    if r > 8 then r = 8; end
    return r;
end

-- ===========================================================================
-- IO + logging (probe_log.txt, dlacprobe's drop dir)
-- ===========================================================================

local fmt = string.format;
local _t0 = nil;   -- os.clock at arm, for the relative t+ stamp

local function logPath()
    local base = '';
    pcall(function() base = AshitaCore:GetInstallPath(); end);
    return base .. 'addons\\dlacprobe\\probe_log.txt';
end

-- One timestamped line -> chat (so arming visibly "prints" per the ACs) AND
-- appended to probe_log.txt. Append-only; a failed open degrades to chat-only,
-- never errors (a probe must never take the client down).
local function log(line)
    local rel = _t0 and fmt('t+%6.1fs ', os.clock() - _t0) or '          ';
    local stamp = os.date('%H:%M:%S');
    print('[probe dig] ' .. line);
    pcall(function()
        local f = io.open(logPath(), 'a');
        if f ~= nil then
            f:write(fmt('[%s] %s%s\n', stamp, rel, line));
            f:close();
        end
    end);
end

-- Hexdump a packet string to the log (16 bytes/row: offset, hex, ascii).
local function hexdump(data)
    if type(data) ~= 'string' then return; end
    local n = #data;
    for base = 0, n - 1, 16 do
        local hex, asc = {}, {};
        for i = 0, 15 do
            local b = string.byte(data, base + i + 1);
            if b == nil then
                hex[#hex + 1] = '  ';
            else
                hex[#hex + 1] = fmt('%02X', b);
                asc[#asc + 1] = (b >= 0x20 and b < 0x7F) and string.char(b) or '.';
            end
        end
        log(fmt('  %04X  %s  %s', base, table.concat(hex, ' '), table.concat(asc)));
    end
end

-- ===========================================================================
-- the hunt (stateful; arm/disarm + Ashita handlers)
-- ===========================================================================

M.zoneInAt = nil;          -- os.clock at the last zone-in (timing baseline)
M.lastRejectElapsed = nil; -- t+ of the last FREE reject since zone-in
M.firstSuccessDone = false;-- has the first completed dig this zone been logged?

local function elapsed()
    if M.zoneInAt == nil then return nil; end
    return os.clock() - M.zoneInAt;
end

-- One-shot skill dump: GetCraftSkill(0..15) with the index-11 verdict, plus a
-- GetCombatSkill control line proving reads work and only 58-63 are blanked.
function M.dumpSkills()
    local pl = nil;
    pcall(function() pl = AshitaCore:GetMemoryManager():GetPlayer(); end);
    if pl == nil then
        log('GetCraftSkill dump: player memory not ready (not logged in?).');
        return;
    end
    log('GetCraftSkill(0..15)  [craft idx N = wire skill 48+N; idx 11 = Digging (wire 59)]:');
    for i = 0, 15 do
        local raw = 0;
        pcall(function() raw = pl:GetCraftSkill(i); end);
        local d = P.decodeSkillWord(raw or 0);
        local mark = d.masked and '  <- MASKED (0xFFFF)' or '';
        local dig = (i == 11) and '  DIGGING' or '';
        log(fmt('  [%2d] raw=0x%04X  skill=%3d  rank=%2d%s%s', i, d.raw, d.skill, d.rank, dig, mark));
    end
    local d11 = P.decodeSkillWord((function() local r = 0; pcall(function() r = pl:GetCraftSkill(11); end); return r or 0; end)());
    if d11.masked then
        log('VERDICT idx11 Digging: MASKED -- client reads 0xFFFF (skill 255 / rank 31). '
            .. 'Rank is blanked at the source; the timing side-channel is the only exact read.');
    else
        log(fmt('VERDICT idx11 Digging: READABLE -- skill=%d rank=%d. '
            .. 'The server is NOT masking this build -- prefer the direct read!', d11.skill, d11.rank));
    end
    -- Control: a combat skill (wire 0..47) that is never blanked, to prove the
    -- probe reads skills fine and only support skills 58-63 come back masked.
    local craw = 0;
    pcall(function() craw = pl:GetCombatSkill(1); end);
    local c = P.decodeSkillWord(craw or 0);
    log(fmt('CONTROL GetCombatSkill(1): raw=0x%04X skill=%d rank=%d%s -- proves reads work; only 58-63 are blanked.',
        c.raw, c.skill, c.rank, c.masked and ' (masked?!)' or ''));
end

function M.arm()
    M.armed = true;
    _t0 = os.clock();
    M.zoneInAt = nil;
    M.lastRejectElapsed = nil;
    M.firstSuccessDone = false;
    log('=== /probe dig ARMED -- observation only, injects nothing ===');
    M.dumpSkills();
    log('Now: zone in, then spam-dig to bracket the first-dig cooldown. /probe dig off when done.');
end

function M.disarm()
    log('=== /probe dig DISARMED ===');
    M.armed = false;
    _t0 = nil;
end

function M.usage()
    print('[probe dig] /probe dig [on|off] -- toggle the dig-rank/timing probe (observation only).');
    print('[probe dig]   arms a GetCraftSkill dump + 0x062 hexdump + dig chat/timing capture to probe_log.txt.');
end

-- zone-in: reset the timing baseline.
function M.onZoneIn()
    M.zoneInAt = os.clock();
    M.lastRejectElapsed = nil;
    M.firstSuccessDone = false;
    log('ZONE-IN (0x00A) -- timing baseline reset. Spam-dig now to bracket the first-dig cooldown.');
end

-- incoming 0x062: hexdump + decode word[59].
function M.on062(data)
    log('0x062 skills packet in:');
    hexdump(data);
    local d = P.digWordFromPacket(data);
    if d == nil then
        log('  word[59] (Digging): out of range -- packet shorter than 0x' .. fmt('%X', P.WIRE_DIG_OFF + 2) .. '.');
    else
        log(fmt('  word[59] (Digging) @0x%X: raw=0x%04X skill=%d rank=%d -> %s',
            P.WIRE_DIG_OFF, d.raw, d.skill, d.rank, d.masked and 'MASKED' or 'REAL'));
    end
end

-- outgoing 0x01A: log candidate dig attempts. The issue names the dig attempt
-- as 0x01A "sub 0x1104"; we read the u16 at both plausible action-field offsets
-- (0x0A category / 0x0C param) and flag a match either way, so a slightly-off
-- offset guess still catches it -- the hexdump confirms the true field.
function M.onOut01A(data)
    local subA = P.u16(data, 0x0A);
    local subC = P.u16(data, 0x0C);
    local isDig = (subA == 0x1104) or (subC == 0x1104);
    local el = elapsed();
    local els = el and fmt('  t+%.1fs', el) or '';
    log(fmt('OUT 0x01A: sub@0x0A=0x%04X sub@0x0C=0x%04X%s%s',
        subA or 0, subC or 0, isDig and '  <DIG ATTEMPT>' or '', els));
    if isDig then hexdump(data); end
end

-- dig chat: timestamp every dig line; a completed dig after zone-in pins the
-- first-dig bracket (reject -> first success -> rank).
function M.onText(msg)
    local tag, item = P.classifyDigText(msg);
    if tag == nil then return; end
    local el = elapsed();
    local els = el and fmt('  t+%.1fs', el) or '';
    if tag == 'wait' then
        M.lastRejectElapsed = el;
        log(fmt('DIG reject (cooldown not up yet -- FREE, no green)%s', els));
        return;
    end
    -- a completed dig => the first-dig cooldown had elapsed.
    if not M.firstSuccessDone and el ~= nil then
        M.firstSuccessDone = true;
        local rank = P.rankFromThreshold(el);
        local lo = M.lastRejectElapsed and fmt(' (last free reject t+%.1fs)', M.lastRejectElapsed) or '';
        log(fmt('DIG first-success bracket: threshold ~= %.1fs since zone-in%s -> rank ~= %d   [(60 - threshold) / 5]',
            el, lo, rank));
    end
    log(fmt('DIG %s%s%s', tag, item and (': ' .. item) or '', els));
end

-- ===========================================================================
-- Ashita glue -- guarded so the file loads headlessly (no registration then)
-- ===========================================================================

if ashita ~= nil and ashita.events ~= nil and type(ashita.events.register) == 'function' then
    ashita.events.register('command', 'dlacprobe-dig-cmd', function(e)
        pcall(function()
            local raw = string.lower(e.command or '');
            local sub = raw:match('^/probe%s+(%S+)');
            if sub ~= 'dig' then return; end
            e.blocked = true;
            local arg = raw:match('^/probe%s+dig%s+(%S+)');
            if arg == 'on' then
                M.arm();
            elseif arg == 'off' then
                M.disarm();
            elseif arg == 'help' or arg == '?' then
                M.usage();
            else
                if M.armed then M.disarm(); else M.arm(); end
            end
        end);
    end);

    ashita.events.register('packet_in', 'dlacprobe-dig-in', function(e)
        if not M.armed then return; end
        pcall(function()
            if e.id == 0x00A then M.onZoneIn(); end
            if e.id == 0x062 then M.on062(e.data); end
        end);
    end);

    ashita.events.register('packet_out', 'dlacprobe-dig-out', function(e)
        if not M.armed then return; end
        if e.id ~= 0x01A then return; end
        pcall(function() M.onOut01A(e.data); end);
    end);

    ashita.events.register('text_in', 'dlacprobe-dig-text', function(e)
        if not M.armed then return; end
        pcall(function() M.onText(e.message); end);
    end);
end

return M;
