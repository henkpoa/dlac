-- lua tests/gearvault_augmented_draw.lua -- set demand drawn from augmented
-- vault copies when no choice is involved.
--
-- Henrik's 2026-10-01 field report: a Leather Vest added to the DNC Idle set
-- stayed in the vault while the Hume M Gloves added beside it came out. The
-- vault held one copy of the vest, augmented, and the engine skipped every
-- augmented row as a "new augmented-copy choice". With one copy there is no
-- choice to make.
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local base = 'dlac\\servers\\ascensionxi\\modules\\gearvault\\';
local vc = require(base .. 'vaultclient');
local rc = require(base .. 'reconcile');
local derive = require(base .. 'derive');

local zero = vc.ZERO24;
local function aug(byte) return string.char(2, 3, byte) .. string.rep('\0', 21); end

local now, queue = 100, {};
local function engine(rows, layoutEntries, sets)
    queue = {};
    local mock = { ZERO24 = zero, code = vc.code, verb = vc.verb,
        instanceMode = function() return true; end,
        state = function() return 'fresh'; end, layoutBusy = function() return false; end,
        requestLayoutSet = function(e) queue[#queue + 1] = e; return true; end,
        requestLayout = function() end,
        layoutCache = { fresh = true, job = 19, stamp = 1, entries = layoutEntries or {} },
        mirror = { fresh = true, stamp = 1, counts = {}, rows = rows },
    };
    rc._reset();
    rc.configure({ vc = mock, clock = function() return now; end, mainJob = function() return 19; end,
        setsRoot = function() return sets; end, triggers = function() return {}; end, derive = derive,
        lookupById = function(id) return { Slot = (id == 13500) and 'Ring' or 'Body' }; end,
        capacity = function() return 80; end, inTown = function() return true; end });
    now = now + 20;
    return rc.tick();
end

local vest = { Name = 'Leather Vest', Id = 12568 };
local gloves = { Name = 'Hume M Gloves', Id = 12754 };
local idle = { Dynamic = { Idle = { Body = { vest }, Hands = { gloves } } } };

-- The field report: the vest's one vaulted copy is augmented.
local r = engine({
    { itemId = 12568, instanceId = 2974, qty = 1, identity = aug(0x22) },
    { itemId = 12754, instanceId = 2832, qty = 1, identity = zero },
}, {}, idle);
assert(r == 'pushed:2', 'both pieces go out, got ' .. tostring(r));
local got = {};
for _, e in ipairs(queue) do got[e.itemId] = e; end
assert(got[12568] and got[12568].instanceId == 2974 and got[12568].identity == aug(0x22),
    'the only (augmented) vest is drawn, carrying its own identity');
assert(got[12754] and got[12754].instanceId == 2832, 'the plain gloves still go out');
assert(rc.notVaulted() == 0 and #rc.chooseCopy() == 0, 'nothing reported as missing');
print('OK -- the only vaulted copy is drawn even when augmented');

-- A plain copy still wins over an augmented one.
engine({
    { itemId = 12568, instanceId = 1, qty = 1, identity = aug(0x22) },
    { itemId = 12568, instanceId = 2, qty = 1, identity = zero },
}, {}, { Idle = { Body = vest } });
assert(#queue == 1 and queue[1].instanceId == 2, 'plain copy preferred');

-- Two DIFFERENT rolls for one slot is a real choice: nothing moves, and the
-- engine says a copy must be chosen instead of calling it unvaulted.
engine({
    { itemId = 12568, instanceId = 1, qty = 1, identity = aug(0x22) },
    { itemId = 12568, instanceId = 2, qty = 1, identity = aug(0x23) },
}, {}, { Idle = { Body = vest } });
assert(#queue == 0, 'differently augmented copies stay manual');
assert(rc.notVaulted() == 0, 'a choice is not "not vaulted"');
local choose = rc.chooseCopy();
assert(#choose == 1 and choose[1].itemId == 12568 and choose[1].need == 1 and choose[1].copies == 2,
    'the choice is reported with its counts');

-- Identical rolls are interchangeable: one of them goes.
engine({
    { itemId = 12568, instanceId = 1, qty = 1, identity = aug(0x22) },
    { itemId = 12568, instanceId = 2, qty = 1, identity = aug(0x22) },
}, {}, { Idle = { Body = vest } });
assert(#queue == 1 and #rc.chooseCopy() == 0, 'identical rolls need no choice');

-- A pair the sets need twice takes every copy there is, whatever the rolls:
-- two rings wanted and two differently rolled rings vaulted is no choice.
local ring = { Name = 'Ring', Id = 13500 };
engine({
    { itemId = 13500, instanceId = 1, qty = 1, identity = aug(0x22) },
    { itemId = 13500, instanceId = 2, qty = 1, identity = aug(0x23) },
}, {}, { Idle = { Ring1 = ring, Ring2 = ring } });
assert(#queue == 2 and #rc.chooseCopy() == 0, 'all copies wanted: all go');

-- A copy already bound in the layout satisfies the demand: nothing more.
engine({
    { itemId = 12568, instanceId = 7, qty = 1, identity = aug(0x22) },
}, { { itemId = 12568, instanceId = 3, kind = 0, state = 1, count = 1, identity = zero } },
    { Idle = { Body = vest } });
assert(#queue == 0, 'satisfied demand draws nothing');

-- AugKey = '' pins the PLAIN copy: an augmented one would never be worn.
engine({
    { itemId = 12568, instanceId = 1, qty = 1, identity = aug(0x22) },
}, {}, { Idle = { Body = { Name = 'Leather Vest', Id = 12568, AugKey = '' } } });
assert(#queue == 0, 'a plain-pinned entry never draws an augmented copy');
assert(rc.notVaulted() == 1 and #rc.chooseCopy() == 0, 'it is reported as not vaulted, as before');

-- ...and a plain pin anywhere keeps the generic entry elsewhere plain too.
engine({
    { itemId = 12568, instanceId = 1, qty = 1, identity = aug(0x22) },
}, {}, { Idle = { Body = vest }, Tp = { Body = { Name = 'Leather Vest', Id = 12568, AugKey = '' } } });
assert(#queue == 0, 'a plain pin on the same item blocks the augmented fallback');
print('OK -- plain copies first; real choices stay manual and are named');
