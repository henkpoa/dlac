--[[
    dlacprobe/tests/dig_test.lua -- headless unit tests for the /probe dig pure
    core (issue #96). dlacprobe is a standalone addon and is not part of dlac's
    tests/run_tests.lua harness (which stubs dlac's own modules), so this test is
    self-contained: run it directly with lua5.4 from the repo root:

        lua5.4 dlacprobe/tests/dig_test.lua

    It only exercises the Ashita/IO-free functions in M.pure -- decodeSkillWord,
    u16 / digWordFromPacket, classifyDigText, rankFromThreshold. Loading dig.lua
    headlessly is safe: `ashita` is nil so no event handlers register, and
    AshitaCore is only ever touched inside armed handlers.
]]--

-- Resolve the module path relative to this test file so it runs from anywhere.
local here = (arg and arg[0] or ''):gsub('[^/\\]*$', '');
local modPath = here .. '..' .. package.config:sub(1, 1) .. 'dig.lua';
local M = dofile(modPath);
local P = M.pure;

local pass, fail = 0, 0;
local function check(name, got, want)
    if got == want then
        pass = pass + 1;
    else
        fail = fail + 1;
        print(string.format('FAIL %s: got %s, want %s', name, tostring(got), tostring(want)));
    end
end

-- decodeSkillWord: the mask signature.
local d = P.decodeSkillWord(0xFFFF);
check('mask skill', d.skill, 255);
check('mask rank', d.rank, 31);
check('mask flagged', d.masked, true);
check('mask raw', d.raw, 0xFFFF);

-- decodeSkillWord: a real value (skill 48, rank 8 -> raw = 48*32 + 8 = 0x0608).
local r = P.decodeSkillWord(0x0608);
check('real skill', r.skill, 48);
check('real rank', r.rank, 8);
check('real not masked', r.masked, false);

-- decodeSkillWord: zero / nil.
check('zero skill', P.decodeSkillWord(0).skill, 0);
check('zero rank', P.decodeSkillWord(0).rank, 0);
check('nil raw defaults 0', P.decodeSkillWord(nil).raw, 0);

-- u16: little-endian read + out-of-range guard.
check('u16 LE', P.u16(string.char(0x34, 0x12), 0), 0x1234);
check('u16 oob nil', P.u16(string.char(0x01), 0), nil);
check('u16 non-string nil', P.u16(42, 0), nil);

-- digWordFromPacket: place 0xFFFF at the wire offset word[59].
local off = P.WIRE_DIG_OFF;
check('wire offset value', off, 0x80 + 59 * 2);
local packet = string.rep('\0', off) .. string.char(0xFF, 0xFF) .. string.rep('\0', 8);
local dw = P.digWordFromPacket(packet);
check('packet dig masked', dw and dw.masked, true);
check('packet dig skill', dw and dw.skill, 255);
-- a real digging word (skill 12, rank 5 -> raw = 12*32 + 5 = 0x0185) on the wire.
local real = string.rep('\0', off) .. string.char(0x85, 0x01) .. string.rep('\0', 8);
local rw = P.digWordFromPacket(real);
check('packet dig real skill', rw and rw.skill, 12);
check('packet dig real rank', rw and rw.rank, 5);
check('packet dig real not masked', rw and rw.masked, false);
-- short packet -> nil, never an over-read.
check('short packet nil', P.digWordFromPacket('short'), nil);

-- classifyDigText.
local function tag(s) local t = P.classifyDigText(s); return t; end
check('obtained tag', tag('Obtained: a handful of Vegetable Seeds.'), 'obtained');
local _, item = P.classifyDigText('Obtained: a handful of Vegetable Seeds.');
check('obtained item', item, 'a handful of Vegetable Seeds');
check('nothing tag', tag('You dig and you dig, but find nothing.'), 'nothing');
check('find-nothing tag', tag('You find nothing of interest.'), 'nothing');
check('wait tag', tag('You must wait a little while longer to perform that action.'), 'wait');
check('wait-longer tag', tag('You have to wait longer before you can dig again.'), 'wait');
check('ease tag', tag('You dig up an item with ease!'), 'ease');
check('non-dig nil', tag('You hit the Orcish Fodder for 42 points of damage.'), nil);
check('non-string nil', tag(nil), nil);

-- isCompletedDig.
check('obtained completed', P.isCompletedDig('obtained'), true);
check('nothing completed', P.isCompletedDig('nothing'), true);
check('ease completed', P.isCompletedDig('ease'), true);
check('wait not completed', P.isCompletedDig('wait'), false);

-- rankFromThreshold: the ladder + rounding + clamps.
check('rank at 60s', P.rankFromThreshold(60), 0);
check('rank at 20s', P.rankFromThreshold(20), 8);
check('rank at 35s', P.rankFromThreshold(35), 5);
check('rank rounds', P.rankFromThreshold(37), 5);       -- (60-37)/5 = 4.6 -> 5
check('rank clamps low', P.rankFromThreshold(70), 0);   -- negative -> 0
check('rank clamps high', P.rankFromThreshold(5), 8);   -- >8 -> 8
check('rank non-number nil', P.rankFromThreshold('x'), nil);

if fail == 0 then
    print(string.format('OK -- %d checks passed', pass));
    os.exit(0);
else
    print(string.format('FAILED -- %d passed, %d failed', pass, fail));
    os.exit(1);
end
