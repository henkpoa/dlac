-- lua tests/gearvault_shared.lua -- Group Ironman's Shared Vault tab
-- (AscensionXI ops 0x60-0x6F; docs/design/gear-vault-integration.md, "The
-- Shared Vault"). The codecs, the capability gate that shows or hides the
-- tab, the HELLO subscription bit, the write laws the vault's own writes
-- keep (isWrite, the replay window, one piece per click), the NEEDS_CONFIRM
-- question, the refresh rules (on open and on SV_CHANGED, never on a clock),
-- the vault's view after a share or a take, zone lines, and the tab itself.
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);
local base = 'dlac\\servers\\ascensionxi\\modules\\gearvault\\';
local vc = require(base .. 'vaultclient');
local rc = require(base .. 'reconcile');
local svm = require(base .. 'sharedvault');
local transport = require('dlac\\servers\\ascensionxi\\transport');
local w16, w32, zero = vc._wu16, vc._wu32, vc.ZERO24;

local failures, checks = 0, 0;
local function check(name, got, want)
    checks = checks + 1;
    if got ~= want then
        failures = failures + 1;
        print(string.format('FAIL %s: got %s, want %s', name, tostring(got), tostring(want)));
    end
end

-- ---------------------------------------------------------------------------
-- Harness: the stage-8 fake wire (a gate the shared transport can close),
-- plus the tab: while `tab.open`, every frame draws it (vc.noteShelfView).
-- ---------------------------------------------------------------------------
local now = 1000;
local sent = {};                  -- { { at, p } } in send order
local gate = { open = true };
local tab = { open = false };
local function rawSend(p)
    if not gate.open then return false; end
    sent[#sent + 1] = { at = now, p = p };
    return true;
end
vc._clock = function() return now; end;
transport._clock = function() return now; end;
transport._audit = nil;
vc._say = function() end;
local zone = { v = nil };
vc._vaultZone = function() return zone.v; end;

local function tick(dt)
    now = now + (dt or 0.2);
    if tab.open then vc.noteShelfView(); end
    vc.pump(true);
end
local function last() return sent[#sent] and sent[#sent].p or {}; end
local function sends(op, after)
    local n = 0;
    for _, s in ipairs(sent) do
        if s.p[5] == op and (after == nil or s.at > after) then n = n + 1; end
    end
    return n;
end
local function shelfSends() return sends(vc.op.SV_LIST) + sends(vc.op.SV_MEMBERS); end
local function anyShelfSent()
    for _, s in ipairs(sent) do if s.p[5] >= 0x60 and s.p[5] <= 0x6F then return true; end end
    return false;
end
local function u32At(p, i)
    return (p[i] or 0) + (p[i + 1] or 0) * 256 + (p[i + 2] or 0) * 65536 + (p[i + 3] or 0) * 16777216;
end
-- The answer to whatever is on the wire. Nothing on the wire is a failure
-- of its own, recorded, and the suite goes on (a broken build shows every
-- check it breaks, not just the first).
local function frame(status, flags, payload)
    local p = vc._st().pending;
    if p == nil then
        check('HARNESS a request was on the wire to answer', 'none', 'one');
        return false;
    end
    return vc.onFrame({ op = p.op, seq = p.seq, status = status or 0, flags = flags or 0, payload = payload or '' });
end
local function reply(payload, flags)
    frame(0, flags, payload);
    for _ = 1, 3 do
        local p = vc._st().pending;
        if not (p and p.sentAt == nil) then break; end
        tick();
    end
end

local FULL = 1 + 2 + 4 + 8 + 32;   -- instances, atomic add, push, stream, SHELF
local function hello(caps, count, rev, group, shelfRev, shelfCount)
    local p = w16(1) .. w16(caps) .. w32(count or 0) .. string.char(15, 62, 62, 0) .. w32(rev or 10)
        .. string.char(13, 12, 41, 30);
    if group ~= nil then p = p .. w32(group) .. w32(shelfRev or 0) .. w32(shelfCount or 0); end
    return p;
end
local function listRow(rowId, item, qty, inst)
    return w32(rowId) .. w16(item) .. w16(qty or 1) .. w32(inst or rowId) .. zero;
end
local function list2(rows, rev) return w16(#rows) .. w16(0) .. w32(rev or 10) .. table.concat(rows); end
local function layout2(rows, rev) return w16(#rows) .. w16(0) .. w32(rev or 10) .. table.concat(rows); end
local function shelfRow(rowId, item, inst, by, ident)
    return w32(rowId) .. w16(item) .. w16(0) .. w32(inst or rowId) .. w32(by or 11) .. (ident or zero);
end
local function shelfList(rows, rev) return w16(#rows) .. w16(0) .. w32(rev or 5) .. table.concat(rows); end
local function member(charId, name, flags)
    return w32(charId) .. string.char(flags or 1, 0, 0, 0) .. name .. string.rep('\0', 16 - #name);
end
local function members(list, group, leader)
    local parts = {};
    for _, m in ipairs(list) do parts[#parts + 1] = member(m[1], m[2], m[3]); end
    return w16(#list) .. w16(0) .. w32(group or 7) .. w32(leader or 11) .. table.concat(parts);
end
local GROUP = { { 11, 'Alice', 1 + 2 + 4 }, { 12, 'Bob', 1 }, { 13, 'Cara', 0 } };
local function putAck(code, jobs, wardrobe, shelfRowId, rev)
    local j = '';
    for _, x in ipairs(jobs or {}) do j = j .. string.char(x); end
    return w16(code) .. string.char(#(jobs or {}), wardrobe and 1 or 0) .. w32(shelfRowId or 0) .. w32(rev or 0) .. j;
end
local function takeAck(code, vaultRowId, rev) return w16(code) .. w16(0) .. w32(vaultRowId or 0) .. w32(rev or 0); end
local function svPush(rev, count, inGroup, group)
    return { op = vc.op.SV_CHANGED, seq = 0, status = 0, flags = 0,
             payload = w32(rev) .. w32(count or 0) .. string.char(inGroup and 1 or 0, 0, 0, 0) .. w32(group or 0) };
end
local function zoneOut(state) vc.noteZoneOut(state or vc.LOGOUT_ZONECHANGE); end
local function loaded() vc.noteItemSame(0); vc.noteItemSame(0); vc.noteItemSame(1); end

-- A small fake server for the reads: whatever is on the wire gets the
-- answer this state gives. Writes are answered by hand.
local srv = {};
local function answer()
    local p = vc._st().pending;
    if p == nil or p.sentAt == nil then return false; end
    if p.op == vc.op.HELLO then
        frame(0, 0, hello(srv.caps or FULL, #srv.rows, srv.rev, srv.group, srv.shelfRev, #srv.shelf));
    elseif p.op == vc.op.LIST2 then
        local r = {};
        for _, x in ipairs(srv.rows) do r[#r + 1] = listRow(x[1], x[2]); end
        frame(0, 0, list2(r, srv.rev));
    elseif p.op == vc.op.LAYOUT_LIST2 then
        frame(0, 0, layout2({}, srv.rev));
    elseif p.op == vc.op.LOST_LIST then
        frame(0, 0, w16(0) .. w16(0));
    elseif p.op == vc.op.SV_MEMBERS then
        frame(0, 0, members(srv.members, srv.group));
    elseif p.op == vc.op.SV_LIST then
        local r = {};
        for _, x in ipairs(srv.shelf) do r[#r + 1] = shelfRow(x[1], x[2], x[3], x[4]); end
        frame(0, 0, shelfList(r, srv.shelfRev));
    else
        return false;
    end
    return true;
end
local function settle(n)
    for _ = 1, (n or 40) do tick(0.1); answer(); end
end

-- A synced instance-mode client in group 7 (by default), its shelf at Rev 5.
-- o = { caps, group (0 = none), noTail, shelfRev, rows, wired }
local function boot(o)
    o = o or {};
    vc._reset(); rc._reset(); transport._reset(); svm._reset();
    sent = {}; now = now + 100; zone.v = nil; gate.open = true; tab.open = false;
    vc._onZoneSettled, vc._readSlot, vc._onFresh, vc._onLayout, vc._onPush = nil, nil, nil, nil, nil;
    if o.wired then
        transport._send = rawSend;
        vc._send = function(p) return transport.send(p, 'test vault'); end;
        vc._received, vc._abandon, vc._notePush = transport.received, transport.abandon, transport.notePush;
    else
        vc._send = rawSend;
        vc._received, vc._abandon, vc._notePush = nil, nil, nil;
    end
    srv = { caps = o.caps or FULL, rev = 10, rows = o.rows or { { 1, 100 } },
            group = (o.group ~= nil) and o.group or 7, shelfRev = o.shelfRev or 5,
            shelf = {}, members = GROUP };
    if o.noTail then srv.group = nil; end
    vc.noteJob(1); vc.refresh(); tick();
    if last()[5] ~= vc.op.HELLO then check('HARNESS boot opens with HELLO', last()[5], vc.op.HELLO); end
    settle(20);
    if not (vc.mirror.fresh and vc._st().pending == nil) then check('HARNESS boot ends fresh and idle', false, true); end
    vc.requestLayout(0); settle(10);
    if not (vc.layoutCache.fresh and vc._st().pending == nil) then check('HARNESS boot reads the layout', false, true); end
end

-- ===========================================================================
-- SC: the codecs (group_ironman_vault.lua's byte layouts)
-- ===========================================================================
local h = vc.parseHello(hello(FULL, 3, 10, 7, 42, 5)) or {};
check('SC1 HELLO with SHELF and its 12-byte tail offers the shelf', h.shelf, true);
check('SC2 ...GroupId', h.groupId, 7);
check('SC3 ...the shelf\'s Rev', h.shelfRev, 42);
check('SC4 ...ShelfCount', h.shelfCount, 5);
check('SC5 ...and the vault\'s own fields read as before',
    h.instances and h.push and h.stream and h.revision == 10 and h.vaultCount == 3 and h.maxLookup == 41, true);
local short = vc.parseHello(hello(FULL, 3, 10));
check('SC6 SHELF without its tail offers no shelf', short ~= nil and short.shelf, false);
check('SC7 ...and never costs the vault its HELLO', short ~= nil and short.instances and short.push, true);
check('SC8 a tail without the SHELF bit offers no shelf', (vc.parseHello(hello(1 + 4 + 8, 3, 10, 7, 42, 5)) or {}).shelf, false);

local id24 = string.char(2, 3, 0x22) .. string.rep('\0', 21);
local sl = vc.parseShelfList(shelfList({ shelfRow(31, 12345, 900, 11, id24), shelfRow(32, 23456, 901, 12) }, 77));
check('SC10 SV_LIST frame: its rows and its Rev', sl ~= nil and #sl.entries == 2 and sl.revision == 77, true);
local r1 = sl and sl.entries[1] or {};
check('SC11 ...RowId, ItemNo, InstanceId, SharedBy at their offsets',
    r1.rowId == 31 and r1.itemId == 12345 and r1.instanceId == 900 and r1.sharedBy == 11, true);
check('SC12 ...and the 24-byte identity blob, whole', r1.identity, id24);
check('SC13 a truncated SV_LIST frame is refused whole',
    vc.parseShelfList(shelfList({ shelfRow(31, 1) }, 1):sub(1, 30)), nil);
local tooMany = {};
for i = 1, 13 do tooMany[i] = shelfRow(i, 100 + i); end
check('SC14 more than 12 rows in one frame is refused', vc.parseShelfList(shelfList(tooMany, 1)), nil);
local empty = vc.parseShelfList(shelfList({}, 0));
check('SC15 an empty shelf reads', empty ~= nil and #empty.entries == 0, true);

check('SC20 SV_PUT for a vault row: { u32 VaultRowId; 0; 0; flags 0; 0 }',
    vc.shelfPutPayload({ vaultRowId = 0x01020304 }), string.char(4, 3, 2, 1, 0, 0, 0, 0));
check('SC21 ...the confirm flag is bit 0 of byte 6',
    vc.shelfPutPayload({ vaultRowId = 9, confirm = true }), string.char(9, 0, 0, 0, 0, 0, 1, 0));
check('SC22 a wardrobe piece: VaultRowId 0, then Container and Slot',
    vc.shelfPutPayload({ container = 10, slot = 33 }), string.char(0, 0, 0, 0, 10, 33, 0, 0));
local pa = vc.parseShelfPutAck(putAck(20, { 1, 7 }, false, 0, 0));
check('SC23 SV_PUT answer: NEEDS_CONFIRM with its jobs',
    pa ~= nil and pa.code == 20 and #pa.jobs == 2 and pa.jobs[1] == 1 and pa.jobs[2] == 7 and pa.wardrobe == false, true);
local pw = vc.parseShelfPutAck(putAck(0, {}, true, 55, 9)) or {};
check('SC24 ...OK with the shelf row, the Rev and the wardrobe flag',
    pw.code == 0 and pw.shelfRowId == 55 and pw.revision == 9 and pw.wardrobe == true, true);
check('SC25 ...a job list shorter than its count is refused', vc.parseShelfPutAck(putAck(20, { 1, 7 }):sub(1, 13)), nil);
check('SC26 ...and a frame under 12 bytes', vc.parseShelfPutAck(w16(0)), nil);
check('SC27 SV_TAKE asks by shelf row', vc.shelfTakePayload(0x0A0B0C0D), string.char(0x0D, 0x0C, 0x0B, 0x0A));
local ta = vc.parseShelfTakeAck(takeAck(0, 88, 10)) or {};
check('SC28 SV_TAKE answer: the code, the new vault row, the Rev',
    ta.code == 0 and ta.vaultRowId == 88 and ta.revision == 10, true);
check('SC29 ...a short one is refused', vc.parseShelfTakeAck(w16(0) .. w16(0)), nil);
local mm = vc.parseShelfMembers(members(GROUP, 7, 11)) or { members = {} };
local m1, m3 = mm.members[1] or {}, mm.members[3] or {};
check('SC30 SV_MEMBERS: the group, its leader, its members', mm.groupId == 7 and mm.leader == 11 and #mm.members == 3, true);
check('SC31 ...a zero-padded name reads clean', m1.name, 'Alice');
check('SC32 ...the flags: active, leader, online', m1.active and m1.leader and m1.online, true);
check('SC33 ...a member who left is listed, not active', m3.active, false);
check('SC34 a full 16-byte name keeps all 16',
    (((vc.parseShelfMembers(members({ { 14, 'Abcdefghijklmnop', 1 } })) or { members = {} }).members[1]) or {}).name, 'Abcdefghijklmnop');
check('SC35 a truncated member list is refused', vc.parseShelfMembers(members({ { 11, 'Alice', 1 } }):sub(1, 20)), nil);
local pc = vc.parseShelfChanged(svPush(12, 4, true, 7).payload) or {};
check('SC36 SV_CHANGED: Rev, count, InGroup, GroupId',
    pc.revision == 12 and pc.count == 4 and pc.inGroup == true and pc.groupId == 7, true);
check('SC37 ...a short push is refused', vc.parseShelfChanged(w32(1)), nil);

-- ===========================================================================
-- SH: the HELLO request subscribes to SV_CHANGED (word @2, bit 1)
-- ===========================================================================
local hp = vc.helloPayload();
local word = hp:byte(3) + hp:byte(4) * 256;
check('SH1 the HELLO request asks for SV_CHANGED pushes (word @2, bit 1 = value 2)', vc._has(word, 2), true);
check('SH2 ...and still for the vault\'s own CHANGED pushes (bit 0)', vc._has(word, 1), true);
check('SH3 ...and nothing else', word, 3);
boot({});
check('SH4 every HELLO on the wire carries it', last() ~= nil and (function()
    for _, s in ipairs(sent) do
        if s.p[5] == vc.op.HELLO and (s.p[11] + s.p[12] * 256) ~= 3 then return false; end
    end
    return true;
end)(), true);
local bye = vc.unsubscribeFrame();
check('SH5 the goodbye HELLO clears both subscriptions (client caps 0)',
    bye ~= nil and bye[5] == vc.op.HELLO and bye[11] == 0 and bye[12] == 0, true);

-- ===========================================================================
-- SG: the tab shows only when the server offers the shelf AND the character
-- is in a group (S12 rule 7) -- hidden otherwise, older servers included
-- ===========================================================================
boot({ caps = 1 + 2 + 4 + 8 });
check('SG1 an older server (no SHELF bit): no Shared Vault tab', vc.shelfAvailable(), false);
check('SG1a ...and nothing in 0x60-0x6F is ever offered to it',
    vc.requestShelfPut({ vaultRowId = 1 }, function() end) or vc.requestShelfTake({ shelfRowId = 1 }, function() end), false);
tab.open = true;
for _ = 1, 10 do tick(0.25); end
check('SG1b ...nor sent, even with the tab "drawn"', anyShelfSent(), false);
boot({ noTail = true });
check('SG2 SHELF without its tail: no tab', vc.shelfAvailable(), false);
check('SG2a ...and the vault itself is unharmed', vc.mirror.fresh and vc.state() == 'fresh', true);
boot({ group = 0 });
check('SG3 SHELF, but in no group: no tab', vc.shelfAvailable(), false);
boot({});
check('SG4 SHELF and a group (HELLO\'s GroupId): the tab shows', vc.shelfAvailable(), true);
vc.onFrame(svPush(5, 0, false, 0));
check('SG5 an SV_CHANGED with InGroup 0 hides it', vc.shelfAvailable(), false);
boot({ group = 0 });
vc.onFrame(svPush(1, 0, true, 9));
check('SG6 an SV_CHANGED with InGroup 1 shows it, though HELLO said no group (a join mid-session)',
    vc.shelfAvailable(), true);
srv.group = 0;
vc.markStale(0, 'test'); settle(20);
check('SG7 the next HELLO saying no group hides it again', vc.shelfAvailable(), false);
boot({});
vc.onFrame(svPush(5, 0, true, 0));
check('SG8 InGroup 1 with GroupId 0 is no group', vc.shelfAvailable(), false);
boot({});
vc.onFrame(svPush(5, 0, false, 7));
check('SG9 InGroup 0 hides the tab whatever the GroupId says', vc.shelfAvailable(), false);
boot({ noTail = true });
vc.onFrame(svPush(5, 0, true, 7));
check('SG10 a push cannot open the tab on a server whose HELLO did not offer the shelf', vc.shelfAvailable(), false);
boot({ caps = 1 + 2 + 4 + 8 });
vc.onFrame(svPush(5, 0, true, 7));
check('SG10a ...nor on an older server', vc.shelfAvailable(), false);

-- ===========================================================================
-- SW: PUT and TAKE are writes -- the replay window, the same seq, never a
-- fresh-seq resend, one at a time (S12 rule 8: one piece per click)
-- ===========================================================================
check('SW1 SV_PUT is on the isWrite list', vc._isWrite(vc.op.SV_PUT), true);
check('SW2 SV_TAKE is on the isWrite list', vc._isWrite(vc.op.SV_TAKE), true);
check('SW3 SV_LIST and SV_MEMBERS are reads', vc._isWrite(vc.op.SV_LIST) or vc._isWrite(vc.op.SV_MEMBERS), false);

boot({});
local werr, t0, wseq = 'unset', nil, nil;
vc.requestShelfPut({ vaultRowId = 1, itemId = 100 }, function(_, e) werr = e; end);
tick(); t0, wseq = now, last()[6];
for _ = 1, 24 do tick(0.25); end
local puts, same, lastAt = 0, true, t0;
for _, s in ipairs(sent) do
    if s.p[5] == vc.op.SV_PUT then
        puts = puts + 1; lastAt = s.at;
        if s.p[6] ~= wseq then same = false; end
    end
end
check('SW4 a lost share is sent 1 + MAX_RETRIES times', puts, 1 + vc.MAX_RETRIES);
check('SW5 ...always with the SAME seq (the server\'s ring answers a retry)', same, true);
check('SW6 ...every one inside WRITE_DEADLINE of the first send', lastAt - t0 < vc.WRITE_DEADLINE, true);
check('SW7 ...then the outcome is unknown', werr, 'timeout');
check('SW8 ...and the vault is re-read, never trusted', vc.mirror.fresh == false or sends(vc.op.HELLO, t0) > 0, true);
for _ = 1, 20 do tick(0.25); end
check('SW9 ...and it is never sent again', sends(vc.op.SV_PUT), puts);

-- the shared gate holds a retry past the window: it never leaves
boot({});
werr = 'unset';
vc.requestShelfTake({ shelfRowId = 31, itemId = 12345 }, function(_, e) werr = e; end);
tick(); t0 = now;
check('SW10 the take left', sends(vc.op.SV_TAKE), 1);
gate.open = false;                      -- another addon's traffic holds the gate
for _ = 1, 16 do tick(0.25); end        -- 4 s: every retry fell due while held
gate.open = true;
for _ = 1, 20 do tick(0.25); end
check('SW11 a take retry held past the replay window never leaves', sends(vc.op.SV_TAKE, t0 + vc.WRITE_DEADLINE), 0);
check('SW12 ...it ends as outcome unknown', werr, 'timeout');

-- through the REAL shared transport, another addon sending 0x1E0 every 0.25 s
local function foreign() transport.noteOutgoing(0x1E0, string.char(0, 0, 0, 0, 0x06, 77, 0, 0)); end
boot({ wired = true });
werr = 'unset';
vc.requestShelfPut({ vaultRowId = 1 }, function(_, e) werr = e; end);
tick(); t0 = now;
check('SW13 the share left through the shared gate', sends(vc.op.SV_PUT), 1);
for _ = 1, 40 do foreign(); tick(0.25); end
for _ = 1, 20 do tick(0.25); end
check('SW14 ...held by another addon, no retry leaves after the window', sends(vc.op.SV_PUT, t0 + vc.WRITE_DEADLINE), 0);
check('SW15 ...and it ends as outcome unknown', werr, 'timeout');
check('SW16 every shelf op is the vault\'s own module on the shared gate',
    transport.producerOf(vc.op.SV_PUT) == transport.producerOf(vc.op.LIST2)
    and transport.producerOf(vc.op.SV_TAKE) == 'vault' and transport.producerOf(vc.op.SV_LIST) == 'vault', true);

boot({});
check('SW17 a share queues', vc.requestShelfPut({ vaultRowId = 1 }, function() end), true);
check('SW18 a second write is refused while it is out (one piece per click)',
    vc.requestShelfTake({ shelfRowId = 3 }, function() end), false);
check('SW18a ...and a second share too', vc.requestShelfPut({ vaultRowId = 1 }, function() end), false);

-- the ring answers both copies of a retried share: applied once, heard once
boot({ rows = { { 1, 100 }, { 2, 101 } } });
local calls = 0;
vc.requestShelfPut({ vaultRowId = 1, itemId = 100 }, function() calls = calls + 1; end);
tick();
local wp = vc._st().pending;
now = now + vc.SEND_TIMEOUT + 0.01; vc.pump(true);
vc.onFrame({ op = wp.op, seq = wp.seq, status = 0, flags = 0, payload = putAck(0, {}, false, 55, 6) });
vc.onFrame({ op = wp.op, seq = wp.seq, status = 0, flags = 0, payload = putAck(0, {}, false, 55, 6) });
check('SW19 a replayed share answer is applied once', #vc.mirror.rows, 1);
check('SW20 ...and its caller hears once', calls, 1);

-- ===========================================================================
-- SN: the question (NEEDS_CONFIRM, S12 rules 1 and 2) and the words
-- ===========================================================================
local notes = {};
local function lastNote() return notes[#notes] and notes[#notes].t; end
boot({ rows = { { 1, 100 }, { 2, 101 } } });
svm._note = function(t, e) notes[#notes + 1] = { t = t, e = e }; end;
local harness = { rowId = 2, itemId = 101, qty = 1, name = 'Scorpion Harness' };
check('SN1 Share from the Vault tab sends one SV_PUT', svm.shareVaultRow(harness), true);
tick();
local put1 = last();
check('SN2 ...for that vault row, without the confirm flag',
    put1[5] == vc.op.SV_PUT and u32At(put1, 9) == 2 and put1[13] == 0 and put1[14] == 0 and put1[15] == 0, true);
check('SN3 one piece per click: a second share waits',
    svm.shareVaultRow({ rowId = 1, itemId = 100, qty = 1, name = 'Item100' }), false);
reply(putAck(vc.giCode.NEEDS_CONFIRM, { 1, 7 }, false, 0, 0));
local c = svm.pendingConfirm();
check('SN4 NEEDS_CONFIRM opens a question', c ~= nil, true);
check('SN5 ...naming the layouts', c ~= nil and table.concat(svm.confirmLines(c), '|'):find('It is in your WAR and PLD layouts.', 1, true) ~= nil, true);
check('SN5a ...and what a yes does', c ~= nil and table.concat(svm.confirmLines(c), '|'):find('removes it from those layouts', 1, true) ~= nil, true);
check('SN6 ...nothing moved and nothing else was sent', sends(vc.op.SV_PUT) == 1 and #vc.mirror.rows == 2, true);
check('SN7 ...the tab waits for the answer (one piece per click)', svm.busy(), true);
check('SN7a ...and a take waits too', svm.take({ rowId = 31, itemId = 12345, name = 'Sword' }), false);
svm.confirm(false);
for _ = 1, 5 do tick(0.25); end
check('SN8 Cancel sends nothing', sends(vc.op.SV_PUT), 1);
check('SN9 ...and closes the question', svm.pendingConfirm(), nil);
svm.shareVaultRow(harness); tick();
reply(putAck(vc.giCode.NEEDS_CONFIRM, { 1 }, false, 0, 0));
local cq = svm.pendingConfirm();
check('SN10 one layout reads in the singular',
    cq ~= nil and table.concat(svm.confirmLines(cq), '|'):find('It is in your WAR layout.', 1, true) ~= nil, true);
local askSeq = last()[6];
svm.confirm(true); tick();
local put2 = last();
check('SN11 Share anyway sends SV_PUT again WITH the confirm flag', put2[5] == vc.op.SV_PUT and put2[15] == 1, true);
check('SN12 ...for the same vault row', u32At(put2, 9), 2);
check('SN13 ...as a new request with its own seq', put2[6] ~= askSeq, true);
reply(putAck(vc.giCode.OK, { 1 }, false, 61, 6));
check('SN14 the yes is answered OK: the row left the vault at once', (function()
    for _, r in ipairs(vc.mirror.rows) do if r.rowId == 2 then return false; end end
    return #vc.mirror.rows == 1;
end)(), true);
check('SN15 ...the player hears it', lastNote(), 'shared Scorpion Harness with your group');
check('SN16 ...it left the job layouts that named it: the layout is read again', vc.layoutCache.fresh, false);

boot({});
svm._reset();
check('SN20 an unworn wardrobe piece is shared by (Container, Slot)',
    svm.shareWardrobe({ container = 10, slot = 33, itemId = 300, name = 'Wardrobe Coat' }), true);
tick();
local wput = last();
check('SN21 ...VaultRowId 0, Container 10, Slot 33, no confirm',
    u32At(wput, 9) == 0 and wput[13] == 10 and wput[14] == 33 and wput[15] == 0, true);
reply(putAck(vc.giCode.NEEDS_CONFIRM, {}, true, 0, 0));
local wc = svm.pendingConfirm();
check('SN22 a wardrobe piece always asks once, and says where it is', wc ~= nil and wc.wardrobe == true
    and table.concat(svm.confirmLines(wc), '|'):find('It is in your Mog Wardrobe.', 1, true) ~= nil, true);
svm.confirm(true); tick();
local wput2 = last();
check('SN23 ...the yes sends the same piece again with the confirm flag',
    wput2[5] == vc.op.SV_PUT and u32At(wput2, 9) == 0 and wput2[13] == 10 and wput2[14] == 33 and wput2[15] == 1, true);
reply(putAck(vc.giCode.OK, {}, true, 62, 6));
check('SN24 ...a wardrobe share re-reads the layout (the piece left its wardrobe)', vc.layoutCache.fresh, false);

boot({});
svm._reset();
svm.shareVaultRow({ rowId = 1, itemId = 100, qty = 1, name = 'Item100' }); tick();
reply(putAck(vc.giCode.NEEDS_CONFIRM, { 3 }, false, 0, 0));
now = now + svm.CONFIRM_TTL + 1;
check('SN25 an unanswered question lapses after CONFIRM_TTL', svm.pendingConfirm(), nil);
check('SN26 ...and a late yes sends nothing', svm.confirm(true) == false and sends(vc.op.SV_PUT) == 1, true);
svm.shareVaultRow({ rowId = 1, itemId = 100, qty = 1, name = 'Item100' }); tick();
reply(putAck(vc.giCode.NEEDS_CONFIRM, { 3 }, false, 0, 0));
check('SN27 (a fresh question is open)', svm.pendingConfirm() ~= nil, true);
vc.onFrame(svPush(9, 0, false, 0));
check('SN27a leaving the group drops an open question', svm.pendingConfirm(), nil);

check('SN30 a refusal code becomes words', svm.refusalWords(vc.giCode.SHELF_CAP),
    'the Shared Vault already holds as many of that piece as it can');
check('SN31 every refusal a share or a take can meet has words', (function()
    for _, k in ipairs({ 'NOT_IN_GROUP', 'BUSY', 'STORE_ERROR', 'STAYS_WITH_YOU', 'SHELF_CAP', 'RARE_IN_STORE',
                         'NOT_ELIGIBLE', 'NO_ROW', 'RARE_HELD', 'DUPLICATE', 'ITEM_BUSY', 'CLOSED' }) do
        if svm.REFUSAL[vc.giCode[k]] == nil then return k; end
    end
    return true;
end)(), true);
check('SN32 an unknown code still says something', svm.refusalWords(99), 'refused (code 99)');
check('SN33 TOO_FAR says where to stand', svm.errWords('too_far'), 'stand at a Gear Vault to use the Shared Vault');
boot({});
svm._reset(); notes = {};
svm._note = function(t, e) notes[#notes + 1] = { t = t, e = e }; end;
svm.take({ rowId = 31, itemId = 12345, name = 'Shared Sword' }); tick();
reply(takeAck(vc.giCode.RARE_HELD, 0, 0));
check('SN34 a refused take says why', lastNote(), 'Shared Sword: you already have one of that Rare piece');
check('SN34a ...as a complaint', notes[#notes] ~= nil and notes[#notes].e, true);
svm.take({ rowId = 31, itemId = 12345, name = 'Shared Sword' }); tick();
frame(vc.status.TOO_FAR);
check('SN35 a take away from a Gear Vault says where to stand',
    lastNote(), 'Shared Sword: stand at a Gear Vault to use the Shared Vault');
check('SN36 a stack is never offered to the shelf (pieces only, S12 rule 3)',
    svm.shareVaultRow({ rowId = 1, itemId = 100, qty = 3, name = 'Arrows' }) == false and vc.shelfBusy() == false, true);
check('SN37 jobs read by abbreviation, in order', svm.jobList({ 1, 7, 5 }), 'WAR, PLD and RDM');

-- ===========================================================================
-- SR: the shelf is read when the tab opens and on SV_CHANGED, only while the
-- tab is open (S9), only when the Rev differs from the last read's, and
-- never on a clock
-- ===========================================================================
boot({ shelfRev = 5 });
srv.shelf = { { 31, 12345, 900, 11 } };
srv.shelfRev = 6;
vc.onFrame(svPush(6, 1, true, 7));
for _ = 1, 20 do tick(0.25); end
check('SR1 tab closed: an SV_CHANGED reads nothing (S9)', shelfSends(), 0);
tab.open = true; tick();
check('SR2 opening the tab asks for the member list first', last()[5], vc.op.SV_MEMBERS);
reply(members(GROUP));
tick();
check('SR3 ...then for the shelf', last()[5], vc.op.SV_LIST);
check('SR4 ...streamed (flags 1, MaxFrames 8) from RowId 0',
    u32At(last(), 9) == 0 and last()[13] == 1 and last()[14] == vc.STREAM_FRAMES, true);
reply(shelfList({ shelfRow(31, 12345, 900, 11) }, 6));
check('SR5 the shelf is read at its Rev', #vc.shelf.rows == 1 and vc.shelf.readRev == 6, true);
check('SR6 ...and the sharer has a name', svm.sharerName(11), 'Alice');
check('SR6a ...and the group line names the members still in it', svm.memberLine(), 'Alice (leader), Bob');
local n0 = shelfSends();
vc.onFrame(svPush(6, 1, true, 7));        -- the arrival push after a zone line or a login
for _ = 1, 10 do tick(0.25); end
check('SR7 an SV_CHANGED at the Rev we read changes nothing', shelfSends(), n0);
vc.onFrame(svPush(7, 2, true, 7));
tick();
check('SR8 an SV_CHANGED at another Rev reads the shelf, once',
    shelfSends() == n0 + 1 and last()[5] == vc.op.SV_LIST, true);
reply(shelfList({ shelfRow(31, 12345, 900, 11), shelfRow(33, 23456, 901, 12) }, 7));
check('SR9 ...and the tab shows the new piece', #vc.shelf.rows, 2);
local n1 = shelfSends();
for _ = 1, 300 do tick(0.2); end
check('SR10 a minute with the tab open reads nothing by itself (no clock)', shelfSends(), n1);
srv.shelf = { { 31, 12345, 900, 11 }, { 33, 23456, 901, 12 } };
srv.shelfRev = 7;
vc.markStale(0, 'test'); settle(20);
check('SR11 a HELLO tail at the Rev we read changes nothing', shelfSends(), n1);
srv.shelfRev = 8;
srv.shelf[#srv.shelf + 1] = { 34, 34567, 902, 13 };
vc.markStale(0, 'test'); settle(30);
check('SR12 a HELLO tail at another Rev reads the shelf (the tab is open)',
    sends(vc.op.SV_LIST) > 0 and #vc.shelf.rows == 3 and vc.shelf.readRev == 8, true);
tab.open = false;
for _ = 1, 10 do tick(0.25); end          -- the tab closed
local n2 = shelfSends();
vc.onFrame(svPush(9, 3, true, 7));
for _ = 1, 10 do tick(0.25); end
check('SR13 a push to a closed tab reads nothing...', shelfSends(), n2);
srv.shelfRev = 9;
tab.open = true; settle(10);
check('SR14 ...the next open reads the members and the shelf',
    shelfSends() == n2 + 2 and vc.shelf.readRev == 9, true);
local n3 = shelfSends();
tab.open = false; tick(); tick(); tick(); tick(); tick(); tick(); tick();
tab.open = true; settle(10);
check('SR15 every open reads again (on open, S9)', shelfSends(), n3 + 2);

-- streamed: FOLLOWS frames, duplicates skipped by RowId, MORE asks again
boot({}); tab.open = true; tick();
reply(members(GROUP)); tick();
check('SR20 (the shelf read is on the wire)', vc._st().pending ~= nil and vc._st().pending.op, vc.op.SV_LIST);
frame(0, vc.FLAG_FOLLOWS, shelfList({ shelfRow(1, 101), shelfRow(2, 102) }, 9));
check('SR21 a FOLLOWS frame keeps the read open', vc._st().pending ~= nil and vc.shelf.stamp == nil, true);
frame(0, vc.FLAG_FOLLOWS, shelfList({ shelfRow(1, 101), shelfRow(2, 102) }, 9));   -- a retry's duplicate burst
frame(0, vc.FLAG_MORE, shelfList({ shelfRow(3, 103) }, 9));
tick();
local more = last();
check('SR22 MORE asks again, after the last RowId', more[5] == vc.op.SV_LIST and u32At(more, 9) == 3, true);
reply(shelfList({ shelfRow(4, 104) }, 9));
check('SR23 one consistent shelf, no duplicates', #vc.shelf.rows == 4 and vc.shelf.readRev == 9, true);
check('SR23a ...in RowId order', #vc.shelf.rows == 4 and vc.shelf.rows[1].rowId == 1 and vc.shelf.rows[4].rowId == 4, true);
boot({}); tab.open = true; tick();
reply(members(GROUP)); tick();
frame(0, vc.FLAG_MORE, shelfList({ shelfRow(1, 101) }, 9));
tick();
frame(0, 0, shelfList({ shelfRow(2, 102) }, 10));    -- the shelf moved between our pages
check('SR24 pages at two Revs are never committed together', vc.shelf.stamp == nil and #vc.shelf.rows == 0, true);
tick();
check('SR25 ...the shelf is read again from the top', last()[5] == vc.op.SV_LIST and u32At(last(), 9) == 0, true);
-- a Rev announced while the pages were on the wire
boot({}); tab.open = true; tick();
reply(members(GROUP)); tick();
vc.onFrame(svPush(12, 1, true, 7));        -- the shelf moved while our read was out
local n26 = sends(vc.op.SV_LIST);
reply(shelfList({ shelfRow(1, 101) }, 11));   -- this answer predates it
tick();
check('SR26 a newer Rev announced during the read reads once more',
    sends(vc.op.SV_LIST) == n26 + 1 and vc._st().pending ~= nil and vc._st().pending.op == vc.op.SV_LIST, true);
reply(shelfList({ shelfRow(1, 101), shelfRow(2, 102) }, 12));
local n4 = shelfSends();
for _ = 1, 10 do tick(0.25); end
check('SR27 ...and then holds still', shelfSends(), n4);
boot({}); tab.open = true; tick();
reply(members(GROUP)); tick();
vc.onFrame(svPush(12, 1, true, 7));        -- announced while our read was out...
reply(shelfList({ shelfRow(1, 101) }, 12));   -- ...and the read already shows it
local n4b = shelfSends();
for _ = 1, 10 do tick(0.25); end
check('SR27a a Rev announced during the read that the read already shows costs no second read', shelfSends(), n4b);
boot({}); tab.open = true; tick();
reply(members(GROUP)); tick();
vc.onFrame(svPush(12, 1, true, 7));        -- announced while our read was out...
reply(shelfList({ shelfRow(1, 101), shelfRow(2, 102) }, 13));   -- ...which saw a later change too
local n4c = shelfSends();
for _ = 1, 10 do tick(0.25); end
check('SR27b ...nor one the read overtook', shelfSends() == n4c and vc.shelf.readRev == 13, true);
-- our own take: Rev + 1 is exactly our change
boot({});
srv.shelf = { { 31, 12345, 900, 11 }, { 32, 23456, 901, 12 } };
srv.shelfRev = 6;
tab.open = true; settle(10);
check('SR28 (two pieces read at Rev 6)', #vc.shelf.rows == 2 and vc.shelf.readRev == 6, true);
local n5 = shelfSends();
svm.take({ rowId = 31, itemId = 12345, name = 'Sword' }); tick();
reply(takeAck(0, 88, 7));
check('SR29 our own take: the row leaves the shelf at once', #vc.shelf.rows == 1 and vc.shelf.rows[1].rowId == 32, true);
srv.shelf = { { 32, 23456, 901, 12 } }; srv.shelfRev = 7; srv.rows = { { 1, 100 }, { 88, 12345 } };
settle(20);
check('SR30 ...when nothing else moved (Rev + 1), the shelf is not read again', shelfSends(), n5);
check('SR30a ...and the vault, which gained a row, is', (function()
    for _, r in ipairs(vc.mirror.rows) do if r.rowId == 88 then return vc.mirror.fresh; end end
    return false;
end)(), true);
svm.take({ rowId = 32, itemId = 23456, name = 'Shield' }); tick();
reply(takeAck(0, 89, 10));                 -- others moved meanwhile (7 -> 10)
srv.shelf = { { 35, 45678, 903, 13 } }; srv.shelfRev = 10;
settle(20);
check('SR31 ...when others moved meanwhile, the shelf is read again', shelfSends() > n5 and vc.shelf.readRev == 10
    and #vc.shelf.rows == 1 and vc.shelf.rows[1].rowId == 35, true);
-- our own share while the tab is open
srv.rows = { { 1, 100 }, { 88, 12345 }, { 89, 23456 } };
vc.markStale(0, 'test'); settle(20);
local n6 = sends(vc.op.SV_LIST);
svm.shareVaultRow({ rowId = 1, itemId = 100, qty = 1, name = 'Item100' }); tick();
reply(putAck(0, {}, false, 36, 11));
srv.shelf[#srv.shelf + 1] = { 36, 100, 1, 99 }; srv.shelfRev = 11; srv.rows = { { 88, 12345 }, { 89, 23456 } };
settle(20);
check('SR32 our own share while the tab is open reads the shelf once', sends(vc.op.SV_LIST) == n6 + 1
    and vc.shelf.readRev == 11 and #vc.shelf.rows == 2, true);
check('SR33 a sharer the member list does not know asks for the members once more', sends(vc.op.SV_MEMBERS) > 0
    and (function()
        local n = 0;
        for _, s in ipairs(sent) do if s.p[5] == vc.op.SV_MEMBERS and s.at > now - 3 then n = n + 1; end end
        return n == 1;
    end)(), true);

-- ===========================================================================
-- SV: the vault's own view stays the vault's: a shelf answer never sends it
-- dormant or un-attuned, never backs it off, and a share or take refreshes it
-- the way its own withdraw and deposit do
-- ===========================================================================
boot({});
vc.requestShelfPut({ vaultRowId = 1 }, function() end); tick();
frame(vc.status.TOO_FAR);
check('SV1 a TOO_FAR share leaves the vault mirror standing', vc.mirror.fresh and vc.state() == 'fresh', true);
boot({}); tab.open = true; tick();
frame(vc.status.BAD_OP);
check('SV2 BAD_OP on a shelf op hides the shelf for the session...', vc.shelfAvailable(), false);
check('SV3 ...but never sends the vault dormant', vc.state() ~= 'dormant' and vc.mirror.fresh, true);
boot({}); tab.open = true; tick();
frame(vc.status.NOT_ATTUNED);
check('SV4 a shelf NOT_ATTUNED never un-attunes the vault', vc.state(), 'fresh');
boot({}); tab.open = true; tick();         -- the member list is out
for _ = 1, 160 do tick(0.25); end           -- and never answered, nor the shelf after it
check('SV5 an unanswered shelf read does not back the vault off', vc._st().giveups == 0 and vc.mirror.fresh, true);
check('SV6 ...the tab says the read failed', vc.shelfFailed(), true);
check('SV6a ...each read the open asked for gives up after its retries',
    sends(vc.op.SV_MEMBERS) == 1 + vc.READ_RETRIES and sends(vc.op.SV_LIST) == 1 + vc.READ_RETRIES, true);
local nq = shelfSends();
for _ = 1, 300 do tick(0.2); end
check('SV6b ...and nothing asks again on a clock', shelfSends(), nq);

boot({ rows = { { 1, 100 }, { 2, 101 } } });
local stamp0 = vc.mirror.stamp;
local onFresh = 0;
vc._onFresh = function() onFresh = onFresh + 1; end;
vc.requestShelfPut({ vaultRowId = 2, itemId = 101 }, function() end); tick();
reply(putAck(0, {}, false, 55, 6));
check('SV7 a share takes its row out of the vault mirror at once (a withdraw\'s subtraction)',
    #vc.mirror.rows == 1 and vc.mirror.rows[1].rowId == 1 and vc.mirror.stamp ~= stamp0, true);
check('SV8 ...the counts follow', vc.mirror.counts[101] == nil and vc.mirror.counts[100] == 1, true);
check('SV9 ...ownership hears it (the mirror\'s commit hook)', onFresh >= 1, true);
check('SV10 ...and the vault is marked for a re-read', vc.mirror.fresh, false);
check('SV11 a share no layout named leaves the layout alone', vc.layoutCache.fresh, true);
local h0 = sends(vc.op.HELLO);
now = now + vc.SETTLE_EDIT - 0.1; vc.pump(true);
check('SV12 ...the re-read waits out SETTLE_EDIT (a run of clicks is one read)...', sends(vc.op.HELLO), h0);
tick();
check('SV12a ...then goes', sends(vc.op.HELLO), h0 + 1);
-- the server's echo push (scope VAULT) lands right after: still one read
boot({ rows = { { 1, 100 }, { 2, 101 } } });
vc.requestShelfPut({ vaultRowId = 2, itemId = 101 }, function() end); tick();
now = now + 0.15;                          -- the answer's round trip
frame(0, 0, putAck(0, {}, false, 55, 6));
h0 = sends(vc.op.HELLO);
for _ = 1, 6 do now = now + 1 / 60; vc.pump(true); end   -- frames pass; the push lands 0.1 s later
vc.onFrame({ op = vc.op.CHANGED, seq = 0, status = 0, flags = 0,
             payload = w16(vc.change.VAULT) .. w16(2) .. w32(11) .. w32(0) .. w32(1) .. w16(0) .. w16(0) .. w32(1) });
srv.rows = { { 1, 100 } };
settle(20);
check('SV13 our answer and the vault\'s CHANGED push make ONE re-read', sends(vc.op.HELLO), h0 + 1);
boot({});
vc.requestShelfTake({ shelfRowId = 31, itemId = 12345 }, function() end); tick();
reply(takeAck(0, 88, 7));
check('SV14 a take marks the vault for a re-read (one LIST folds the new row in)', vc.mirror.fresh, false);
boot({});
vc.layoutCache.entries = { { ordinal = 1, itemId = 12345, instanceId = 900, kind = 0, state = 0, count = 1 } };
vc.requestShelfTake({ shelfRowId = 31, itemId = 12345 }, function() end); tick();
reply(takeAck(0, 88, 7));
check('SV15 ...and the layout when it names the piece (the server may pull it onto a wardrobe)', vc.layoutCache.fresh, false);
boot({});
vc.requestShelfPut({ vaultRowId = 1 }, function() end); tick();
reply(putAck(vc.giCode.NO_ROW, {}, false, 0, 0));
check('SV16 a share that met a gone vault row re-reads the vault', vc.mirror.fresh, false);
boot({});
vc.requestShelfPut({ vaultRowId = 1 }, function() end); tick();
reply(putAck(vc.giCode.DUPLICATE, {}, false, 0, 0));
check('SV17 a plain refusal moved nothing: the vault stays fresh', vc.mirror.fresh and #vc.mirror.rows == 1, true);
boot({});
vc.requestShelfPut({ vaultRowId = 1 }, function() end); tick();
reply(putAck(vc.giCode.NOT_IN_GROUP, {}, false, 0, 0));
check('SV18 NOT_IN_GROUP hides the tab', vc.shelfAvailable(), false);
boot({});
vc.requestShelfPut({ vaultRowId = 1 }, function() end); tick();
frame(vc.status.UNAVAILABLE);
check('SV19 an UNAVAILABLE share may have run: the vault and the layout are re-read',
    vc.mirror.fresh == false and vc.layoutCache.fresh == false, true);
boot({});
local merr = 'unset';
vc.requestShelfTake({ shelfRowId = 31 }, function(_, e) merr = e; end); tick();
frame(0, 0, w16(0));
check('SV20 an unreadable take answer is reported and both stores re-read',
    merr == 'malformed' and vc.mirror.fresh == false, true);
-- an SV_CHANGED is a push: it never answers the pending request (T2)
boot({ wired = true });
vc.markStale(0, 'test'); tick();           -- a vault HELLO on the shared gate
check('SV21 an SV_CHANGED is ours (blocked from the game)', vc.onFrame(svPush(5, 0, true, 7)), true);
now = now + transport.MIN_GAP + 0.01;
check('SV22 ...and never frees the shared gate (T2)', transport.send({ 0, 0, 0, 0, 0x80, 9 }, 'HELM'), false);
check('SV23 an unreadable SV_CHANGED is eaten and changes nothing',
    vc.onFrame({ op = vc.op.SV_CHANGED, seq = 0, status = 0, flags = 0, payload = 'x' }) == true and vc.shelfAvailable(), true);
-- the shelf is never yours: ownership and lockstyle read the vault mirror only (S12 rule 6)
boot({});
onFresh = 0;
vc._onFresh = function() onFresh = onFresh + 1; end;
srv.shelf = { { 31, 12345, 900, 11 } }; srv.shelfRev = 6;
tab.open = true; settle(10);
check('SV24 a shelf piece is never counted as yours', #vc.shelf.rows == 1 and vc.mirror.counts[12345] == nil, true);
check('SV25 ...reading the shelf never touches the ownership hook', onFresh, 0);
-- an un-attuned answer to the vault drains a queued share
boot({});
local qerr = 'unset';
vc.markStale(0, 'test'); tick();           -- a vault HELLO is out
vc.requestShelfPut({ vaultRowId = 1 }, function(_, e) qerr = e; end);
frame(vc.status.NOT_ATTUNED);
check('SV26 the vault saying NOT_ATTUNED drains a queued share, unsent',
    qerr == 'not_attuned' and sends(vc.op.SV_PUT) == 0 and vc.shelfBusy() == false, true);
-- leaving the group cancels a share that has not left
boot({});
gate.open = false;
qerr = 'unset';
vc.requestShelfPut({ vaultRowId = 1 }, function(_, e) qerr = e; end);
tick();
vc.onFrame(svPush(9, 0, false, 0));
gate.open = true;
for _ = 1, 10 do tick(0.25); end
check('SV27 leaving the group cancels a share that never left', qerr == 'not_in_group' and sends(vc.op.SV_PUT) == 0, true);
boot({});
local heard, lastAck = 0, nil;
vc.requestShelfPut({ vaultRowId = 1 }, function(ack, e) heard = heard + 1; lastAck = ack; qerr = e; end);
tick();
vc.onFrame(svPush(9, 0, false, 0));
check('SV28 ...but a share already on the wire still gets its answer', vc.shelfBusy() == true and heard == 0, true);
reply(putAck(vc.giCode.NOT_IN_GROUP, {}, false, 0, 0));
check('SV28a ...and its caller hears it, once', vc.shelfBusy() == false and heard == 1 and qerr == nil
    and lastAck ~= nil and lastAck.code == vc.giCode.NOT_IN_GROUP, true);

-- ===========================================================================
-- SZ: zone lines (the vault's laws hold for the shelf)
-- ===========================================================================
boot({});
local zerr = 'unset';
vc.requestShelfPut({ vaultRowId = 1 }, function(_, e) zerr = e; end); tick();
zoneOut(); vc.noteZoneIn(); loaded();
for _ = 1, 20 do tick(0.25); end
check('SZ1 a share on the wire at a zone line is outcome unknown', zerr, 'timeout');
check('SZ2 ...and never re-sent into the new map process', sends(vc.op.SV_PUT), 1);
boot({});
zoneOut();
vc.requestShelfTake({ shelfRowId = 31 }, function() end);
for _ = 1, 10 do tick(0.25); end
check('SZ3 nothing leaves while zoning', sends(vc.op.SV_TAKE), 0);
vc.noteZoneIn(); loaded(); tick();
check('SZ4 ...the take goes once the zone is ours', sends(vc.op.SV_TAKE), 1);
boot({}); tab.open = true; tick();          -- the member list is on the wire
zoneOut(); vc.noteZoneIn(); loaded(); tick();
check('SZ5 a shelf read cut by a zone line runs again once the zone is ours', last()[5], vc.op.SV_MEMBERS);
boot({}); tab.open = true; tick();          -- the member list is on the wire
zoneOut(); tab.open = false;               -- ...and the tab closes during the zone line
now = now + 3; vc.noteZoneIn(); loaded();
local nzc = shelfSends();
for _ = 1, 10 do tick(0.25); end
check('SZ7 ...but not once the tab has closed (the next open reads)', shelfSends(), nzc);
boot({}); tab.open = true; settle(10);
local nz = shelfSends();
zoneOut(); vc.noteZoneIn(); loaded();
vc.onFrame(svPush(srv.shelfRev, 0, true, 7));   -- the new map process tells us where the shelf is
for _ = 1, 10 do tick(0.25); end
check('SZ6 the arrival push at the Rev we read changes nothing', shelfSends(), nz);

-- ===========================================================================
-- SU: the tab (vaultui against an imgui-shaped stub)
-- ===========================================================================
local depth = { child = 0, item = 0, tree = 0, tip = 0, col = 0, pop = 0, bar = 0, tab = 0 };
local texts, smallHits, headers, selectables, opened = {}, {}, {}, {}, {};
local press = { small = nil, select = nil };
local openPopups = {};
local hover = { on = false, rightClick = false };
local nop = function() end;
local IM = {
    TextColored = function(_, s) texts[#texts + 1] = tostring(s); end,
    SameLine = nop, Separator = nop, SetTooltip = nop, SetNextItemOpen = nop, Dummy = nop,
    Selectable = function(label)
        selectables[#selectables + 1] = tostring(label);
        return press.select ~= nil and tostring(label) == press.select;
    end,
    GetCursorPosY = function() return 0; end, SetCursorPosY = nop,
    GetWindowWidth = function() return 800; end,
    PushStyleColor = function() depth.col = depth.col + 1; end,
    PopStyleColor = function(n) depth.col = depth.col - (n or 1); end,
    GetContentRegionAvail = function() return 800, 500; end,
    IsItemHovered = function() return hover.on; end,
    SmallButton = function(label)
        smallHits[#smallHits + 1] = tostring(label);
        return press.small ~= nil and tostring(label):find(press.small, 1, true) ~= nil;
    end,
    CollapsingHeader = function(label) headers[#headers + 1] = tostring(label); return true; end,
    IsMouseClicked = function(b) return hover.rightClick and b == 1; end,
    CloseCurrentPopup = nop,
    OpenPopup = function(id) opened[#opened + 1] = id; openPopups[id] = true; end,
    BeginPopup = function(id)
        if openPopups[id] then depth.pop = depth.pop + 1; return true; end
        return false;
    end,
    EndPopup = function() depth.pop = depth.pop - 1; end,
    TreeNode = function() depth.tree = depth.tree + 1; return true; end,
    TreePop = function() depth.tree = depth.tree - 1; end,
    BeginTabBar = function() depth.bar = depth.bar + 1; return true; end,
    EndTabBar = function() depth.bar = depth.bar - 1; end,
    BeginTabItem = function(label) headers[#headers + 1] = tostring(label); depth.tab = depth.tab + 1; return true; end,
    EndTabItem = function() depth.tab = depth.tab - 1; end,
    BeginTooltip = function() depth.tip = depth.tip + 1; end,
    EndTooltip = function() depth.tip = depth.tip - 1; end,
    PushItemWidth = function() depth.item = depth.item + 1; end,
    PopItemWidth = function() depth.item = depth.item - 1; end,
    InputText = function() return false; end,
    BeginChild = function() depth.child = depth.child + 1; return true; end,
    EndChild = function() depth.child = depth.child - 1; end,
};
package.loaded['imgui'] = IM;
package.loaded['dlac\\chatfmt'] = { print = nop };   -- the result line's chat echo
package.loaded['dlac\\ui\\itemicons'] = { renderIcon = nop };
package.loaded['dlac\\ui\\uistyle'] = {};
package.loaded['dlac\\ui\\uihost'] = {
    services = {
        COL = { ERR = { 1, 0, 0, 1 }, DIM = { 1, 1, 1, 1 }, HEADER = { 1, 1, 1, 1 }, USABLE = { 1, 1, 1, 1 },
                SCORE = { 1, 1, 1, 1 }, VAULT = { 1, 1, 1, 1 }, LEVEL = { 1, 1, 1, 1 }, STATS = { 1, 1, 1, 1 } },
        displayName = function(id) return 'Item' .. tostring(id); end,
        lookupById = function(id) return { Id = id, Name = 'Item' .. tostring(id), Slot = 'Body', Level = 10 }; end,
        itemTooltip = function() IM.BeginTooltip(); IM.EndTooltip(); end,
        SLOT_TREE_ORDER = { 'Body' },
        CAT_ORDER = {},
    },
};
local vui = require(base .. 'vaultui');
vui._invOverride = {};
vui._wornOverride = {};
vui._wardrobeOverride = {};
local function frameUI()
    texts, smallHits, headers, selectables, opened = {}, {}, {}, {}, {};
    local ok, err = pcall(vui.render, 1, 75);
    if not ok then print('render error: ' .. tostring(err)); end
    return ok;
end
local function has(list, needle)
    for _, s in ipairs(list) do if s:find(needle, 1, true) ~= nil then return true; end end
    return false;
end
local function hasExact(list, text)
    for _, s in ipairs(list) do if s == text then return true; end end
    return false;
end
local function queued() return (vc._st().shelfWriteQ or {})[1] or {}; end
local function balanced()
    return depth.child == 0 and depth.item == 0 and depth.tree == 0 and depth.tip == 0 and depth.col == 0
        and depth.pop == 0 and depth.bar == 0 and depth.tab == 0;
end

boot({ group = 0 });
check('SU1 in no group the window renders', frameUI(), true);
check('SU1a ...with no Shared Vault tab', has(headers, 'Shared Vault'), false);
check('SU1b ...and its Vault and Inventory tabs as before', has(headers, 'Vault (') and has(headers, 'Inventory ('), true);
boot({ caps = 1 + 2 + 4 + 8 });
frameUI();
check('SU2 an older server: no Shared Vault tab', has(headers, 'Shared Vault'), false);

boot({});
srv.shelf = { { 31, 12345, 900, 11 } };
srv.shelfRev = 6;
check('SU3 in a group the window renders', frameUI(), true);
check('SU3a ...with the Shared Vault as the third tab', headers[#headers] ~= nil and (function()
    local v, i, s;
    for n, l in ipairs(headers) do
        if l:find('Vault (', 1, true) == 1 then v = n; end
        if l:find('Inventory (', 1, true) == 1 then i = n; end
        if l:find('Shared Vault (', 1, true) == 1 then s = n; end
    end
    return v ~= nil and i ~= nil and s ~= nil and v < i and i < s;
end)(), true);
check('SU3b ...drawing it is opening it: the member list is asked for', vc._st().svMembersWant == true
    or (vc._st().pending ~= nil and vc._st().pending.op == vc.op.SV_MEMBERS), true);
for _ = 1, 20 do now = now + 0.1; frameUI(); vc.pump(true); answer(); end
frameUI();
check('SU4 the shelf row is drawn, with who shared it', hasExact(texts, 'Item12345') and hasExact(texts, 'from Alice'), true);
check('SU4a ...the tab counts it', has(headers, 'Shared Vault (1)'), true);
check('SU4b ...the group line names the members', has(texts, 'Your group: Alice (leader), Bob'), true);
check('SU5 ...and it offers Take', has(smallHits, 'Take##gvst31'), true);
check('SU5a ...and points at the Vault tab for sharing', has(texts, 'right-click it in the Vault tab'), true);
check('SU6 the stacks stay balanced', balanced(), true);
press.small = 'Take##gvst31';
frameUI();
press.small = nil;
check('SU7 Take queues one SV_TAKE for that row', vc.shelfBusy() and queued().op == vc.op.SV_TAKE
    and queued().shelfRowId == 31, true);
frameUI();
check('SU8 ...the row says Taking... and no Take button is offered meanwhile',
    has(texts, 'Taking...') and not has(smallHits, 'Take##'), true);
tick(); reply(takeAck(0, 88, 7));
frameUI();
check('SU9 ...the answer lands on the tab\'s line', vui._lastResult() ~= nil
    and vui._lastResult().text == 'took Item12345 into your Gear Vault', true);
check('SU9a ...and the row is gone', hasExact(texts, 'Item12345'), false);

-- the Vault tab's right-click menu: Share with your group
boot({ rows = { { 1, 100 } }, group = 0 });
openPopups = {};
hover.on, hover.rightClick = true, true;
frameUI();
hover.on, hover.rightClick = false, false;
frameUI();
check('SU10b in no group the Vault tab\'s menu has no Share with your group',
    has(selectables, 'Add to Mog Wardrobe on all MW Layouts') and not has(selectables, 'Share with your group'), true);
boot({ rows = { { 1, 100 } } });
openPopups = {};
srv.shelfRev = 6;
hover.on, hover.rightClick = true, true;
frameUI();
hover.on, hover.rightClick = false, false;
frameUI();
check('SU10 the Vault tab\'s right-click menu offers Share with your group', has(selectables, 'Share with your group'), true);
check('SU10a ...beside its existing action', has(selectables, 'Add to Mog Wardrobe on all MW Layouts'), true);
press.select = 'Share with your group';
frameUI();
press.select = nil;
check('SU11 ...which queues one SV_PUT for that vault row', vc.shelfBusy() and queued().op == vc.op.SV_PUT
    and queued().vaultRowId == 1, true);
frameUI();
check('SU11a ...and the row says sharing... until it is answered', has(texts, 'sharing...'), true);
tick(); reply(putAck(vc.giCode.NEEDS_CONFIRM, { 1, 7 }, false, 0, 0));
frameUI();
check('SU12 the question opens as a popup', has(opened, '##gv-share-confirm'), true);
check('SU12a ...asking about that piece', has(texts, 'Share Item100 with your group?'), true);
check('SU12b ...naming the layouts', has(texts, 'It is in your WAR and PLD layouts.'), true);
check('SU12c ...offering Share anyway and Cancel', has(smallHits, 'Share anyway##') and has(smallHits, 'Cancel##'), true);
check('SU12d the stacks stay balanced with the popup up', balanced(), true);
press.small = 'Share anyway##';
frameUI();
press.small = nil;
tick();
check('SU13 Share anyway sends the share again with the confirm flag',
    last()[5] == vc.op.SV_PUT and u32At(last(), 9) == 1 and last()[15] == 1, true);
reply(putAck(0, { 1, 7 }, false, 40, 7));
frameUI();
check('SU13a ...and says so', vui._lastResult() ~= nil and vui._lastResult().text == 'shared Item100 with your group', true);
-- clicking away is a no
boot({ rows = { { 1, 100 } } });
openPopups = {};
svm.shareVaultRow({ rowId = 1, itemId = 100, qty = 1, name = 'Item100' }); tick();
reply(putAck(vc.giCode.NEEDS_CONFIRM, { 3 }, false, 0, 0));
frameUI();
check('SU14 (the question is up)', has(opened, '##gv-share-confirm') and svm.pendingConfirm() ~= nil, true);
openPopups['##gv-share-confirm'] = nil;     -- the player clicked elsewhere
frameUI();
for _ = 1, 5 do tick(0.25); end
check('SU15 clicking away closes it as a no: nothing sent', svm.pendingConfirm() == nil and sends(vc.op.SV_PUT) == 1, true);
-- the wardrobe share list
boot({});
vui._wardrobeOverride = { { container = 10, slot = 33, itemId = 300, qty = 1, sortKey = 10 * 256 + 33,
    rec = { Id = 300, Name = 'Item300', Slot = 'Body', Level = 20 }, name = 'Item300' } };
frameUI();
check('SU16 unworn wardrobe gear is listed for sharing', has(headers, 'Share from your Mog Wardrobes (1)'), true);
check('SU16a ...each with a Share button', has(smallHits, 'Share##gvsw' .. tostring(10 * 256 + 33)), true);
press.small = 'Share##gvsw';
frameUI();
press.small = nil;
check('SU17 Share queues one SV_PUT by (Container, Slot)', vc.shelfBusy() and queued().op == vc.op.SV_PUT
    and queued().vaultRowId == 0, true);
tick();
check('SU17a ...on the wire as VaultRowId 0, Container 10, Slot 33',
    u32At(last(), 9) == 0 and last()[13] == 10 and last()[14] == 33 and last()[15] == 0, true);
vui._wardrobeOverride = {};
-- leaving the group takes the tab away
boot({});
frameUI();
check('SU18 (the tab is there)', has(headers, 'Shared Vault ('), true);
vc.onFrame(svPush(9, 0, false, 0));
frameUI();
check('SU18a an SV_CHANGED with InGroup 0 takes it away', has(headers, 'Shared Vault'), false);
check('SU19 the stacks stay balanced throughout', balanced(), true);

-- ---- the Ashita glue: init.lua is not loadable headless, so its two shelf
-- lines are pinned as text (the behaviour behind them is tested above) ----
do
    local f = io.open('servers/ascensionxi/modules/gearvault/init.lua', 'r');
    local src = (f ~= nil) and f:read('*a') or '';
    if f ~= nil then f:close(); end
    check('SG20 /dl vault prints the shelf line', src:find('vc.shelfStatusLine()', 1, true) ~= nil, true);
    check('SG21 a character switch forgets an open question', src:find("require(base .. 'sharedvault')._reset()", 1, true) ~= nil, true);
end

if failures > 0 then
    print(string.format('FAIL -- %d of %d Shared Vault checks failed', failures, checks));
    os.exit(1);
end
print(string.format('OK -- %d Shared Vault checks: codecs, the tab gate, write laws, the question, refresh rules, the vault view, zone lines, the tab', checks));
