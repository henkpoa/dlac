-- lua tests/ascensionxi_telemetry_wire.lua   (from the dlac repo root)
-- The AscensionXI combat telemetry codec and formula copy against the
-- server's own vectors: tests/fixtures/ascensionxi/telemetry-wire-vectors.md
-- is a verbatim copy of the server repo's
-- documentation/custom/autoacc-backend-research/wire-vectors.md (regenerate
-- there with wire_vectors.py and copy it over when the contract changes).
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);

local wire = require('dlac\\servers\\ascensionxi\\modules\\telemetry\\wire');
local formula = require('dlac\\servers\\ascensionxi\\modules\\telemetry\\formula');

local pass, fail = 0, 0;
local function check(name, got, want)
    if got == want then pass = pass + 1; return; end
    fail = fail + 1;
    print(('FAIL %s: got %s, want %s'):format(name, tostring(got), tostring(want)));
end

local function readVectors(path)
    local f = assert(io.open(path, 'rb'));
    local text = f:read('*a');
    f:close();
    local out, cur, inBlock, hex = {}, nil, false, {};
    for line in text:gmatch('[^\n]*') do
        line = line:gsub('\r$', '');
        local name = line:match('^### (TV%-[%w]+)');
        if name then
            cur = name;
        elseif cur and line == '```' then
            if inBlock then out[cur] = table.concat(hex); cur, inBlock, hex = nil, false, {};
            else inBlock = true; end
        elseif inBlock then
            for b in line:sub(7):gmatch('%x%x') do hex[#hex + 1] = string.char(tonumber(b, 16)); end
        end
    end
    return out;
end

local V = readVectors('tests/fixtures/ascensionxi/telemetry-wire-vectors.md');
local SESSION = 0x7A3F19C4;

-- C2S frames as dlac hands them to AddOutgoingPacket.
check('TV-01 HELLO', wire.bytesOf(wire.outgoing(wire.op.HELLO, 0x21,
    wire.encodeHello({ nonce = 0x1234ABCD, caps = 0x7F, build = 0x20260929 }))), V['TV-01']);
check('TV-03 WATCH FOLLOW', wire.bytesOf(wire.outgoing(wire.op.WATCH, 0x22,
    wire.encodeWatch({ session = SESSION, nonce = 0x0BADF00D, lane = 0, flags = 0x06, contextMask = 0x000B, watchGen = 1 }))),
    V['TV-03']);
check('TV-07 RESYNC', wire.bytesOf(wire.outgoing(wire.op.RESYNC, 0x24,
    wire.encodeResync({ session = SESSION, nonce = 0x5EED0003, mode = 0, laneMask = 0 }))), V['TV-07']);
check('TV-09 WATCH clear', wire.bytesOf(wire.outgoing(wire.op.WATCH, 0x29,
    wire.encodeWatch({ session = SESSION, nonce = 0x5EED0005, lane = 1, watchGen = 9 }))), V['TV-09']);
check('TV-10 STOP', wire.bytesOf(wire.outgoing(wire.op.STOP, 0x25,
    wire.encodeStop({ session = SESSION, nonce = 0x5EED0004, laneMask = 0xFF, flags = 1 }))), V['TV-10']);

-- S2C frames decode to the documented fields.
local f2 = wire.incoming(V['TV-02']);
check('TV-02 op', f2.op, wire.op.HELLO);
local hello = wire.decodeHelloReply(f2.payload);
check('TV-02 session', hello.session, SESSION);
check('TV-02 nonce', hello.nonce, 0x1234ABCD);
check('TV-02 caps', hello.caps, 0x73);
check('TV-02 lease', hello.leaseSeconds, 45);
check('TV-02 renew', hello.renewAfterSeconds, 15);
check('TV-02 charId', hello.charId, 21828);
check('TV-02 rulesRev', hello.rulesRev, 0x9C41E27B);

local watch = wire.decodeWatchReply(wire.incoming(V['TV-04']).payload);
check('TV-04 state', watch.laneState, wire.laneState.LIVE);
check('TV-04 spawnGen', watch.boundSpawnGen, 7);
check('TV-04 granted', watch.grantedFlags, 0x06);

local f5 = wire.incoming(V['TV-05']);
check('TV-05 push op', f5.op, wire.op.SNAPSHOT);
check('TV-05 push seq', f5.seq, 0);
local tv05 = assert(wire.decodeSnapshot(f5.payload));
check('TV-05 rev', tv05.rev, 1);
check('TV-05 flags', tv05.snapFlags, 0x09);
check('TV-05 equipRev', tv05.equipRev, 0x78CAEAF2);
check('TV-05 target', tv05.targetId, 0x010680A5);
check('TV-05 enchanted', tv05.enchantedSlotMask, 0x0040);
check('TV-05 dexR', tv05.dexR, 88);
check('TV-05 accModLive', tv05.accModLive, 37);
check('TV-05 food', tv05.foodAccCap, 30);
check('TV-05 contexts', #tv05.contexts, 3);
check('TV-05 ctx0 liveAcc', tv05.contexts[1].liveAcc, 383);
check('TV-05 ctx0 level', tv05.contexts[1].levelCorrection, -12);
check('TV-05 ctx3 threshold', tv05.contexts[3].thresholdBp, 2800);
local tv06 = assert(wire.decodeSnapshot(wire.incoming(V['TV-06']).payload));
check('TV-06 rev', tv06.rev, 2);
check('TV-06 NEW_OUTFIT', wire.hasBit(tv06.snapFlags, wire.snapFlag.NEW_OUTFIT), true);
check('TV-06 dexR', tv06.dexR, 91);

local resync = wire.decodeResyncReply(wire.incoming(V['TV-08']).payload);
check('TV-08 battleRev', resync.battleRev, 2);
check('TV-08 watchGen', resync.battleWatchGen, 1);

-- Refusals: the status byte, an empty or header-only payload.
check('TV-N1 BAD_OP', wire.incoming(V['TV-N1']).status, wire.status.BAD_OP);
local n2 = wire.readHeader(wire.incoming(V['TV-N2']).payload);
check('TV-N2 NO_SESSION', n2.code, wire.result.NO_SESSION);
check('TV-N4 MALFORMED', wire.incoming(V['TV-N4']).status, wire.status.MALFORMED);
check('TV-N4 empty', wire.incoming(V['TV-N4']).payload, '');
check('TV-N5 stale session', wire.decodeSnapshot(wire.incoming(V['TV-N5']).payload).session, 0x11111111);
check('TV-N6 UNAVAILABLE', wire.incoming(V['TV-N6']).status, wire.status.UNAVAILABLE);

-- The R/live pairs and the inputs are signed: an ACC-down past zero.
do
    local p = f5.payload;
    local neg = p:sub(1, 98) .. string.char(0xF6, 0xFF) .. p:sub(101);   -- AccMod live = -10
    neg = neg:sub(1, 96) .. string.char(0xEC, 0xFF) .. neg:sub(99);       -- AccMod R = -20
    local s = wire.decodeSnapshot(neg);
    check('signed AccMod live', s.accModLive, -10);
    check('signed AccMod R', s.accModR, -20);
end

-- The comparison key (research 4.4, the vectors' "Hashes and the comparison
-- key"): what moves on its own, what is informational and what moves with
-- gear leave it; everything else is in it.
do
    local p5 = f5.payload;
    local function poke(p, offset, bytes) return p:sub(1, offset) .. bytes .. p:sub(offset + #bytes + 1); end
    local key5 = wire.snapshotKey(p5);
    check('key: a string', type(key5), 'string');
    local later = poke(p5, 8, wire.w32(5));                 -- Rev 5
    later = poke(later, 19, string.char(0x08));             -- no FIRST
    later = poke(later, 32, wire.w32(1238567));             -- SampleMs
    later = poke(later, 52, wire.w16(41));                  -- DistanceDeci
    check('key: TV-05 with Rev 5, no FIRST, SampleMs and DistanceDeci moved', wire.snapshotKey(later), key5);
    local outfit = poke(p5, 24, wire.w32(0x12345678));      -- EquipRev
    outfit = poke(outfit, 19, string.char(0x09 + 0x20));    -- NEW_OUTFIT
    outfit = poke(outfit, 62, wire.w16(3));                 -- LatentActiveMask
    for _, o in ipairs({ 90, 94, 98, 102, 106, 110 }) do outfit = poke(outfit, o, wire.w16(77)); end
    for i = 0, tv05.contextCount - 1 do
        local o = wire.SNAPSHOT_FIXED + i * wire.CONTEXT_SIZE;
        outfit = poke(outfit, o + 3, string.char(0xFF));    -- CtxFlags
        outfit = poke(outfit, o + 6, wire.w16(301));        -- live skill
        outfit = poke(outfit, o + 16, wire.w16(999) .. wire.w16(9500));   -- LiveAcc, ThresholdBp
    end
    outfit = poke(outfit, 47, string.char(0xFF));           -- TargetFlags
    check('key: an outfit-only change keeps it', wire.snapshotKey(outfit), key5);
    check('key: TV-06 has another (DEX R moved with the Rajas Ring latents)',
        wire.snapshotKey(wire.incoming(V['TV-06']).payload) ~= key5, true);
    check('key: an R value is in it', wire.snapshotKey(poke(p5, 88, wire.w16(89))) ~= key5, true);
    check('key: the target is in it', wire.snapshotKey(poke(p5, 40, wire.w32(0x01068001))) ~= key5, true);
    check('key: the lane state is in it', wire.snapshotKey(poke(p5, 16, string.char(4))) ~= key5, true);
    check('key: GEAR_REFILL is in it', wire.snapshotKey(poke(p5, 19, string.char(0x09 + 0x10))) ~= key5, true);
    check('key: the enchanted slots are in it', wire.snapshotKey(poke(p5, 60, wire.w16(0))) ~= key5, true);
    check('key: a context R skill is in it',
        wire.snapshotKey(poke(p5, wire.SNAPSHOT_FIXED + 4, wire.w16(200))) ~= key5, true);
    check('key: a short frame has none', wire.snapshotKey(p5:sub(1, 100)), nil);
    check('key: contexts past the length have none', wire.snapshotKey(poke(p5, 18, string.char(9))), nil);
end

-- The receive side copes with Ashita's 512-byte buffer: the header names the length.
local padded = V['TV-05'] .. string.rep('\0', 512 - #V['TV-05']);
check('padded buffer', wire.incoming(padded).payload, f5.payload);

-- Hashes.
check('fnv empty', wire.fnv1a32(''), 0x811C9DC5);
check('fnv a', wire.fnv1a32('a'), 0xE40C292C);
local outfit = { [0] = { 0, 5, 16460 }, [1] = { 8, 3, 16536 }, [2] = { 8, 4, 17152 }, [3] = { 0, 6, 17318 },
                 [6] = { 8, 9, 14925 }, [9] = { 8, 10, 15515 }, [13] = { 8, 11, 14674 }, [14] = { 0, 7, 13465 } };
check('EquipRev TV-05', wire.outfitHash(outfit), 0x78CAEAF2);
outfit[13] = { 8, 12, 15543 };
check('EquipRev TV-06', wire.outfitHash(outfit), 0xEBC50981);

-- The formula copy: every context of both frames composes from its live totals.
check('TV-05 formula', formula.check(tv05), nil);
check('TV-06 formula', formula.check(tv06), nil);
for _, s in ipairs({ { 0, 0 }, { 150, 150 }, { 200, 200 }, { 201, 200 }, { 256, 250 }, { 400, 380 }, { 401, 380 },
                     { 450, 420 }, { 600, 540 }, { 601, 540 }, { 700, 630 } }) do
    check('AccFromSkill ' .. s[1], formula.accFromSkill(s[1]), s[2]);
end
-- The vectors' formula lines: AccToCap and the truncation artefact.
local ctx0, ctx1, ctx3 = tv05.contexts[1], tv05.contexts[2], tv05.contexts[3];
local _, eff0 = formula.compose(tv05, ctx0);
check('TV-05 ctx0 eff', eff0, 371);
check('TV-05 ctx0 AccToCap', formula.accToCap(ctx0, eff0), -11);
local acc1, eff1, th1 = formula.compose(tv05, ctx1);
check('TV-05 ctx1 getACC', acc1, 322);
check('TV-05 ctx1 threshold', th1, 7000);
check('TV-05 ctx1 AccToCap', formula.accToCap(ctx1, eff1), 50);
local acc3, eff3, th3 = formula.compose(tv05, ctx3);
check('TV-05 ctx3 getRACC (food +100 quirk)', acc3, 240);
check('TV-05 ctx3 threshold at gap -92 truncates to 28', th3, 2800);
check('TV-05 ctx3 AccToCap', formula.accToCap(ctx3, eff3), 132);

-- The local projection of the vectors: TV-05's R plus the released outfit's
-- plain modifiers and its active level latents gives TV-06's live totals.
local released = {
    dex = tv05.dexR - 0 + 2 + 3,       -- Rajas Ring DEX+2, its three level latents DEX+3
    agi = tv05.agiR,
    accMod = tv05.accModR + 10,        -- Peacock Amulet ACC+10 (Toreador's Ring released)
    raccMod = tv05.raccModR + 10,
    twoHandAccMod = 0,
};
check('projected DEX', released.dex, tv06.dexLive);
check('projected AccMod', released.accMod, tv06.accModLive);
for i = 1, 3 do
    local acc, _, th = formula.compose(tv05, tv05.contexts[i], released);
    check('projected ctx ' .. tv05.contexts[i].kind .. ' accessor', acc, tv06.contexts[i].liveAcc);
    check('projected ctx ' .. tv05.contexts[i].kind .. ' threshold', th, tv06.contexts[i].thresholdBp);
end
-- A weapon skill's first hit: +100 ACC, compared with the cap directly.
check('WS first hit rate', formula.rate(ctx0, eff0 + 100), 0.95);

print(('ascensionxi_telemetry_wire: %d passed, %d failed'):format(pass, fail));
if fail > 0 then os.exit(1); end
