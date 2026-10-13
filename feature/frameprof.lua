--[[
    dlac/feature/frameprof.lua -- /dl perf: THE FRAME PROFILER (2026-10-13).

    Field report, 2026-10-13 (Abraxis, on the 13b test build): TrueFPS still
    spikes with dlac loaded -- "a bit better, but way worse than us". The
    headless harness (tests/perf/frame_profile.lua) puts dlac at ~0.1 ms of
    Lua per frame on Henrik's machine. Whatever is left lives on THEIR
    machine -- a slow disk, an antivirus that scans every file dlac opens, a
    slower CPU, the game client loading a gear model from disk after a swap --
    so the measurement has to run there.

        /dl perf [seconds]     (default 60, 10-300)
        /dl perf stop          finish early

    For the window it records, for EVERY frame:
      * the frame time, present to present (QueryPerformanceCounter) -- the
        number TrueFPS draws;
      * dlac's own time inside it: every event handler dlac registered, timed
        one by one;
      * every file dlac opened, loaded, renamed or removed, timed;
      * the Lua heap (a fall = a garbage collection cycle ended there);
      * the gear packets on the wire (a swap makes the CLIENT load the new
        piece's model -- a hitch that is not dlac's Lua at all).
    and writes ONE file: addons\dlac\debug\dlac-perf-<Name>.txt, whose top
    says how many hitches dlac's own work explains and how many it does not.

    HOW IT SEES EVERY HANDLER: dlac.lua requires this module before anything
    registers an event, and install() wraps ashita.events.register for this
    Lua state -- every handler registered after it runs inside a shim that
    times it while a window is open. The file functions (io.open, loadfile,
    dofile, os.remove, os.rename, ashita.fs.*) are wrapped the same way, so a
    module that copied io.open into a local at load time copied the wrapper.
    DISARMED, A SHIM IS ONE TABLE READ AND A TAIL CALL: no clock, no garbage.
    The profiler's own hooks register on the real function, so they are never
    in the table they produce.
]]--

local M = {};

M.MIN_S, M.MAX_S, M.DEF_S = 10, 300, 60;
M.KEEP_SLOW  = 300;      -- slowest frames kept with their breakdown
M.KEEP_DLAC  = 60;       -- dlac's heaviest frames kept with theirs
M.KEEP_HITCH = 4000;     -- hitches kept for the verdict block (the count stays exact)
M.PER_FRAME  = 6;        -- handlers / files / packets named per kept frame
M.NOTE_S     = 0.0002;   -- a handler call this long is named in its frame
M.IO_NOTE_S  = 0.0001;   -- a file operation this long is named in its frame
M.GEAR_S     = 0.6;      -- "a gear packet just before the hitch": this far back
M.GC_DROP_KB = 256;      -- the heap falling this much inside a frame = a GC cycle ended

-- Gear packets: outgoing equip / equip-set / lockstyle, incoming equip and
-- the appearance list (the one after which the client loads models).
M.GEAR_OUT = { [0x050] = true, [0x051] = true, [0x053] = true };
M.GEAR_IN  = { [0x050] = true, [0x051] = true };

-- ---------------------------------------------------------------------------
-- clocks (seams: the tests drive _now / _heap / _tid)
-- ---------------------------------------------------------------------------

M.clockName = 'os.clock (1 ms steps)';
M._now  = function() return os.clock(); end
M._heap = function() return collectgarbage('count'); end
M._tid  = function() return 0; end

-- QueryPerformanceCounter through the FFI, declared under dlac's own names
-- (__asm__ redirect) so no other declaration in this state can collide with
-- it. Read as two 32-bit halves, not an int64_t: indexing an int64_t boxes a
-- cdata on every call -- garbage on the one path that must not make any.
pcall(function()
    local ffi = require('ffi');
    pcall(ffi.cdef, [[
        int __stdcall dlac_fp_qpc(void *count) __asm__("QueryPerformanceCounter");
        int __stdcall dlac_fp_qpf(void *freq) __asm__("QueryPerformanceFrequency");
        unsigned long __stdcall dlac_fp_tid(void) __asm__("GetCurrentThreadId");
    ]]);
    local C = ffi.C;
    local buf = ffi.new('uint32_t[2]');
    if C.dlac_fp_qpf(buf) == 0 then return; end
    local freq = buf[0] + buf[1] * 4294967296;
    if not (freq > 0) then return; end
    local qpc, tid = C.dlac_fp_qpc, C.dlac_fp_tid;
    M._qpcBuf = buf;     -- held: the closure below reads it every call
    M._now = function()
        qpc(buf);
        return (buf[0] + buf[1] * 4294967296) / freq;
    end
    M._tid = function() return tonumber(tid()); end
    M.clockName = 'QueryPerformanceCounter';
end);

-- ---------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------

local P = { on = false, depth = 0 };   -- the one switch every shim reads
M._P = P;
local REC = {};                        -- 'event/alias' -> handler record
M._recs = REC;
local IOS = {};                        -- kind -> path -> file record
M._ios = IOS;
local REAL = {};                       -- the functions install() wrapped
M._REAL = REAL;

local function newFrame()
    return { dlac = 0, io = 0, iot = 0, heap0 = 0, pin = 0, pout = 0,
             nh = 0, hk = {}, ht = {}, ni = 0, ik = {}, ip = {}, it = {}, np = 0, pk = {} };
end
P.F = newFrame();

local function recFor(name, alias)
    local key = tostring(name) .. '/' .. tostring(alias);
    local r = REC[key];
    if r == nil then
        r = { key = key, ev = tostring(name), calls = 0, total = 0, max = 0, n2 = 0, n8 = 0, off = 0 };
        REC[key] = r;
    end
    return r;
end
M._recFor = recFor;

-- ---------------------------------------------------------------------------
-- the armed path
-- ---------------------------------------------------------------------------

-- One handler call, measured. Only an OUTERMOST call adds to the frame's dlac
-- total: a handler that prints raises text_in inside itself, and counting the
-- inner one again would double it.
local function noteHandler(r, dt, outer)
    r.calls = r.calls + 1;
    r.total = r.total + dt;
    if dt > r.max then r.max = dt; end
    if dt >= 0.002 then
        r.n2 = r.n2 + 1;
        if dt >= 0.008 then r.n8 = r.n8 + 1; end
    end
    if not outer then return; end
    local F = P.F;
    F.dlac = F.dlac + dt;
    if dt < M.NOTE_S then return; end
    -- The frame's biggest few, merged per handler (a packet handler runs
    -- thirty times a second; its name belongs in the list once).
    local n, hk, ht = F.nh, F.hk, F.ht;
    for i = 1, n do
        if hk[i] == r.key then ht[i] = ht[i] + dt; return; end
    end
    if n < M.PER_FRAME then
        n = n + 1;
        F.nh = n; hk[n] = r.key; ht[n] = dt;
        return;
    end
    local lo, at = ht[1], 1;
    for i = 2, n do if ht[i] < lo then lo, at = ht[i], i; end end
    if dt > lo then hk[at] = r.key; ht[at] = dt; end
end

local function finish(r, t0, outer, ...)
    local dt = M._now() - t0;
    P.depth = outer and 0 or (P.depth - 1);
    if P.on then
        noteHandler(r, dt, outer);
        if r.ev ~= 'd3d_present' and P.mainTid ~= nil and M._tid() ~= P.mainTid then
            r.off = r.off + 1;
        end
    end
    return ...;
end

local function shim(r, fn)
    return function(...)
        if not P.on then return fn(...); end
        local outer = (P.depth == 0);
        P.depth = P.depth + 1;
        local t0 = M._now();
        return finish(r, t0, outer, fn(...));
    end
end
M._shim = shim;

local function ioNote(kind, path, dt)
    local byKind = IOS[kind];
    if byKind == nil then byKind = {}; IOS[kind] = byKind; end
    local p = tostring(path);
    local r = byKind[p];
    if r == nil then
        r = { kind = kind, path = p, n = 0, total = 0, max = 0 };
        byKind[p] = r;
    end
    r.n = r.n + 1;
    r.total = r.total + dt;
    if dt > r.max then r.max = dt; end
    local F = P.F;
    F.io = F.io + 1;
    F.iot = F.iot + dt;
    if dt < M.IO_NOTE_S then return; end
    local n = F.ni;
    if n < M.PER_FRAME then
        n = n + 1;
        F.ni = n; F.ik[n] = kind; F.ip[n] = p; F.it[n] = dt;
        return;
    end
    local lo, at = F.it[1], 1;
    for i = 2, n do if F.it[i] < lo then lo, at = F.it[i], i; end end
    if dt > lo then F.ik[at] = kind; F.ip[at] = p; F.it[at] = dt; end
end

local function ioDone(kind, path, t0, ...)
    if P.on then ioNote(kind, path, M._now() - t0); end
    return ...;
end

-- A file opened for WRITING is handed back behind a thin proxy while a window
-- is open, so its close is timed too: an antivirus scans a written file when
-- it is CLOSED, which is exactly the cost this module exists to find. Every
-- other method passes straight through; nothing in dlac type-checks a handle
-- (no io.type / io.close(f) / io.lines anywhere in the tree).
local function writer(path, t0, f, ...)
    if P.on then ioNote('open.w', path, M._now() - t0); end
    if f == nil then return f, ...; end
    return setmetatable({}, { __index = function(_, k)
        local v = f[k];
        if type(v) ~= 'function' then return v; end
        if k == 'close' then
            return function(_, ...)
                local c0 = M._now();
                return ioDone('close.w', path, c0, v(f, ...));
            end
        end
        return function(_, ...) return v(f, ...); end
    end });
end

-- ---------------------------------------------------------------------------
-- frames
-- ---------------------------------------------------------------------------

local function median(hist)
    local total = 0;
    for _, c in pairs(hist) do total = total + c; end
    if total == 0 then return nil; end
    local keys = {};
    for b in pairs(hist) do keys[#keys + 1] = b; end
    table.sort(keys);
    local half, run = total / 2, 0;
    for _, b in ipairs(keys) do
        run = run + hist[b];
        if run >= half then return b / 1000; end
    end
    return keys[#keys] / 1000;
end
M._median = median;

-- What counts as a hitch, from the frame time this machine normally runs at:
-- 1.5x the median, at least 5 ms over it, never under 12 ms. 60 fps -> 25 ms,
-- 30 fps -> 50 ms, 144 fps -> 12 ms.
function M._threshold(med)
    if med == nil then return 0.025; end
    return math.max(med * 1.5, med + 0.005, 0.012);
end

local function keepTop(list, cap, field, rec)
    if #list < cap then list[#list + 1] = rec; return; end
    local lo, at = math.huge, nil;
    for i = 1, #list do
        local s = list[i][field];
        if s < lo then lo, at = s, i; end
    end
    if at ~= nil and rec[field] > lo then list[at] = rec; end
end

local function snapshotFrame(F, t, iv, heap)
    local rec = { t = t - P.t0, iv = iv, dlac = F.dlac, io = F.io, iot = F.iot,
                  heapDelta = heap - F.heap0, pin = F.pin, pout = F.pout,
                  h = {}, f = {}, p = {} };
    for i = 1, F.nh do rec.h[i] = { F.hk[i], F.ht[i] }; end
    for i = 1, F.ni do rec.f[i] = { F.ik[i], F.ip[i], F.it[i] }; end
    for i = 1, F.np do rec.p[i] = F.pk[i]; end
    if P.lastGearOut ~= nil then rec.gearOut = t - P.lastGearOut; end
    if P.lastGearIn ~= nil then rec.gearIn = t - P.lastGearIn; end
    return rec;
end

local function closeFrame(t, iv, heap)
    local F = P.F;
    local n = P.n + 1;
    P.n = n;
    P.iv[n] = iv;
    P.dl[n] = F.dlac;
    P.dlacTotal = P.dlacTotal + F.dlac;
    local b = math.floor(iv * 1000 + 0.5);
    if b > 2000 then b = 2000; end
    P.hist[b] = (P.hist[b] or 0) + 1;
    local fell = F.heap0 - heap;
    if fell >= M.GC_DROP_KB then
        P.gcCycles = P.gcCycles + 1;
    elseif fell < 0 then
        P.heapRise = P.heapRise - fell;
    end
    if heap < P.heapMin then P.heapMin = heap; end
    if heap > P.heapMax then P.heapMax = heap; end
    if iv >= P.thresh or F.dlac >= 0.001 or F.iot >= 0.001 then
        local rec = snapshotFrame(F, t, iv, heap);
        rec.n = n;
        rec.gc = (fell >= M.GC_DROP_KB) or nil;
        if iv >= P.thresh then keepTop(P.slow, M.KEEP_SLOW, 'iv', rec); end
        if F.dlac >= 0.001 then keepTop(P.heavy, M.KEEP_DLAC, 'dlac', rec); end
        if iv >= P.thresh and #P.hitchAt < M.KEEP_HITCH then P.hitchAt[#P.hitchAt + 1] = rec; end
    end
    if n % 60 == 0 then P.thresh = M._threshold(median(P.hist)); end
end

local function openFrame(heap)
    local F = P.F;
    F.dlac, F.io, F.iot, F.heap0, F.pin, F.pout = 0, 0, 0, heap, 0, 0;
    F.nh, F.ni, F.np = 0, 0, 0;
end

local function frameMark()
    if not P.on then return; end
    local t = M._now();
    local heap = M._heap();
    P.depth = 0;    -- heals a handler that errored out of its shim
    if P.mainTid == nil then P.mainTid = M._tid(); end
    if P.last ~= nil then closeFrame(t, t - P.last, heap); end
    P.last = t;
    if P.t0 == nil then P.t0 = t; end
    openFrame(heap);
    if t - P.t0 >= P.secs then M.stop('the window closed on its own'); end
end
M._frameMark = frameMark;

local function notePacket(id, dir)
    local F = P.F;
    if F.np < M.PER_FRAME then
        F.np = F.np + 1;
        F.pk[F.np] = string.format('%s 0x%03X', dir, id);
    end
end

local function pktIn(e)
    if not P.on then return; end
    P.F.pin = P.F.pin + 1;
    local id = e and e.id;
    if id ~= nil and M.GEAR_IN[id] then
        P.lastGearIn = M._now();
        P.gearIn = P.gearIn + 1;
        notePacket(id, 'in');
    end
end
M._pktIn = pktIn;

local function pktOut(e)
    if not P.on then return; end
    P.F.pout = P.F.pout + 1;
    local id = e and e.id;
    if id ~= nil and M.GEAR_OUT[id] then
        P.lastGearOut = M._now();
        P.gearOut = P.gearOut + 1;
        notePacket(id, 'out');
    end
end
M._pktOut = pktOut;

-- ---------------------------------------------------------------------------
-- the window
-- ---------------------------------------------------------------------------

function M._dur(word)
    local n = tonumber(word);
    if n == nil then return M.DEF_S; end
    return math.max(M.MIN_S, math.min(M.MAX_S, math.floor(n)));
end

function M.status()
    if not P.on then return nil; end
    local left = P.secs;
    if P.t0 ~= nil then left = math.max(0, P.secs - (M._now() - P.t0)); end
    return { left = left, frames = P.n };
end

function M.start(secs)
    if P.on then return false, 'already measuring'; end
    for _, r in pairs(REC) do
        r.calls, r.total, r.max, r.n2, r.n8, r.off = 0, 0, 0, 0, 0, 0;
    end
    for k in pairs(IOS) do IOS[k] = nil; end
    P.secs = secs or M.DEF_S;
    P.t0, P.last, P.mainTid = nil, nil, nil;
    P.n, P.iv, P.dl, P.hist = 0, {}, {}, {};
    P.dlacTotal, P.thresh = 0, M._threshold(nil);
    P.slow, P.heavy, P.hitchAt = {}, {}, {};
    P.gcCycles, P.heapRise = 0, 0;
    P.heapMin, P.heapMax = math.huge, 0;
    P.lastGearOut, P.lastGearIn, P.gearOut, P.gearIn = nil, nil, 0, 0;
    P.depth = 0;
    P.startedAt = os.date('%Y-%m-%d %H:%M:%S');
    P.ctx = M._context();
    openFrame(M._heap());
    P.on = true;
    return true;
end

-- ---------------------------------------------------------------------------
-- the file
-- ---------------------------------------------------------------------------

local function ms(s) return string.format('%.1f', (tonumber(s) or 0) * 1000); end

local function pct(sorted, p)
    if #sorted == 0 then return 0; end
    local i = math.max(1, math.min(#sorted, math.ceil(p * #sorted)));
    return sorted[i];
end

-- Paths read better without the install root (and the character folder is
-- the same one on every line).
function M._short(p, root)
    p = tostring(p or '');
    if root ~= nil and root ~= '' and string.lower(string.sub(p, 1, #root)) == string.lower(root) then
        p = string.sub(p, #root + 1);
    end
    p = p:gsub('^config\\addons\\dlac\\[^\\]+\\', '<char>\\');
    return p;
end

-- The whole report, from a finished recording. Pure over (P, REC, IOS) and
-- the context table -- the tests render a synthetic recording through it.
function M.render(why)
    local ctx = P.ctx or {};
    local L = {};
    local function add(s) L[#L + 1] = s; end
    local n = P.n or 0;
    local wall = 0;
    for i = 1, n do wall = wall + P.iv[i]; end

    add('========================================================================');
    add(string.format('dlac frame profile -- %s -- dlac %s', tostring(ctx.name or '?'), tostring(ctx.version or '?')));
    add(string.format('started %s, %.1f s recorded of %d requested (%s)', tostring(P.startedAt or '?'),
        wall, P.secs or 0, tostring(why or 'stopped')));
    add('clock: ' .. M.clockName);
    if ctx.where ~= nil then add('player: ' .. ctx.where); end
    if ctx.pack ~= nil then add('server pack: ' .. ctx.pack); end
    if ctx.flags ~= nil then add('window settings (uiflags.lua): ' .. ctx.flags); end
    add('------------------------------------------------------------------------');
    add('HOW TO READ IT: "frame" is the time from one picture to the next -- the');
    add('line TrueFPS draws. "dlac" is the time dlac\'s own code ran inside that');
    add('frame. A hitch with little dlac time in it was slow somewhere ELSE --');
    add('the WHAT THE HITCHES HAD IN THEM block names the usual suspects.');
    add('========================================================================');
    add('');

    if n == 0 then
        add('no frames were recorded (the window closed before the first frame).');
        return table.concat(L, '\n') .. '\n';
    end

    local sorted = {};
    for i = 1, n do sorted[i] = P.iv[i]; end
    table.sort(sorted);
    local med = pct(sorted, 0.5);
    local thr = M._threshold(med);
    local dls = {};
    for i = 1, n do dls[i] = P.dl[i]; end
    table.sort(dls);
    local over = { 0, 0, 0, 0 };
    for i = 1, n do
        local d = P.dl[i];
        if d >= 0.002 then over[1] = over[1] + 1; end
        if d >= 0.004 then over[2] = over[2] + 1; end
        if d >= 0.008 then over[3] = over[3] + 1; end
        if d >= 0.016 then over[4] = over[4] + 1; end
    end

    -- Hitches against the FINAL median (the kept list used a running one).
    local hitches = {};
    for _, rec in ipairs(P.hitchAt) do
        if rec.iv >= thr then hitches[#hitches + 1] = rec; end
    end
    local nHitch = 0;
    for i = 1, n do if P.iv[i] >= thr then nHitch = nHitch + 1; end end

    add('===== FRAMES =====');
    add(string.format('frames %d over %.1f s (%.1f fps average)', n, wall, n / math.max(wall, 1e-9)));
    add(string.format('frame time: median %s ms, p90 %s, p99 %s, p99.9 %s, max %s ms',
        ms(med), ms(pct(sorted, 0.9)), ms(pct(sorted, 0.99)), ms(pct(sorted, 0.999)), ms(sorted[#sorted])));
    add(string.format('hitches (frames >= %s ms): %d -- %.1f per minute', ms(thr), nHitch, nHitch * 60 / math.max(wall, 1e-9)));
    add(string.format('dlac per frame: mean %s ms, median %s, p99 %s, max %s ms -- %.2f%% of the window',
        string.format('%.3f', (P.dlacTotal / n) * 1000), string.format('%.3f', pct(dls, 0.5) * 1000),
        ms(pct(dls, 0.99)), ms(dls[#dls]), 100 * P.dlacTotal / math.max(wall, 1e-9)));
    add(string.format('frames where dlac ran >= 2 ms: %d   >= 4 ms: %d   >= 8 ms: %d   >= 16 ms: %d',
        over[1], over[2], over[3], over[4]));
    add('');

    -- The verdict block: for each hitch, what was in it.
    local cDlac, cGear, cGc, cIo, cNone = 0, 0, 0, 0, 0;
    for _, rec in ipairs(hitches) do
        local extra = rec.iv - med;
        local isDlac = rec.dlac >= 0.5 * extra;
        local isGear = (rec.gearOut ~= nil and rec.gearOut <= M.GEAR_S) or (rec.gearIn ~= nil and rec.gearIn <= M.GEAR_S);
        local isGc = rec.gc == true;
        local isIo = false;
        for _, f in ipairs(rec.f) do if f[3] >= 0.001 then isIo = true; end end
        if isDlac then cDlac = cDlac + 1; end
        if isGear then cGear = cGear + 1; end
        if isGc then cGc = cGc + 1; end
        if isIo then cIo = cIo + 1; end
        if not (isDlac or isGear or isGc or isIo) then cNone = cNone + 1; end
    end
    add('===== WHAT THE HITCHES HAD IN THEM =====');
    if #hitches == 0 then
        add('no hitches -- every frame stayed under ' .. ms(thr) .. ' ms.');
    else
        local kept = (#hitches < nHitch) and string.format(' (the %d slowest of %d kept)', #hitches, nHitch) or '';
        add(string.format('of %d hitches%s:', #hitches, kept));
        add(string.format('  %4d  dlac\'s own code was at least half of the extra time', cDlac));
        add(string.format('  %4d  a gear packet went out or came in within %.1f s before', cGear, M.GEAR_S));
        add(string.format('  %4d  a Lua garbage collection cycle ended inside it', cGc));
        add(string.format('  %4d  a dlac file operation took >= 1 ms inside it', cIo));
        add(string.format('  %4d  none of these: the frame was slow OUTSIDE dlac\'s code', cNone));
        add('  (one hitch can count in more than one row)');
    end
    add(string.format('gear packets in the window: %d out (equip/lockstyle), %d in (equip/appearance)',
        P.gearOut or 0, P.gearIn or 0));
    add('');

    add('===== GARBAGE =====');
    add(string.format('Lua heap: %.1f MB at the end (window min %.1f, max %.1f); %d collection cycle(s) ended',
        (P.heapLast or P.heapMax) / 1024, (P.heapMin < math.huge and P.heapMin or 0) / 1024, P.heapMax / 1024, P.gcCycles));
    add(string.format('heap growth between collections: ~%.0f KB/s', P.heapRise / math.max(wall, 1e-9)));
    add('');

    add('===== dlac HANDLERS (by total time) =====');
    add(string.format('%-46s %7s %9s %7s %8s %7s %5s %5s %4s', 'event/handler', 'calls', 'total ms', 'ms/s',
        'avg us', 'max ms', '>=2ms', '>=8ms', 'off'));
    local list = {};
    for _, r in pairs(REC) do if r.calls > 0 then list[#list + 1] = r; end end
    table.sort(list, function(a, b) return a.total > b.total; end);
    for i, r in ipairs(list) do
        if i > 30 then break; end
        add(string.format('%-46s %7d %9s %7.2f %8.1f %7s %5d %5d %4s', string.sub(r.key, 1, 46), r.calls,
            ms(r.total), r.total * 1000 / math.max(wall, 1e-9), r.total * 1e6 / r.calls, ms(r.max),
            r.n2, r.n8, (r.off > 0) and tostring(r.off) or ''));
    end
    if #list == 0 then add('  (no dlac handler ran)'); end
    add('("off" = calls that ran on a different thread than the frame)');
    add('');

    add('===== dlac FILE OPERATIONS (by total time) =====');
    local fl = {};
    for _, byKind in pairs(IOS) do for _, r in pairs(byKind) do fl[#fl + 1] = r; end end
    table.sort(fl, function(a, b) return a.total > b.total; end);
    add(string.format('%-10s %6s %9s %8s %8s  %s', 'kind', 'count', 'total ms', 'avg us', 'max ms', 'path'));
    for i, r in ipairs(fl) do
        if i > 30 then break; end
        add(string.format('%-10s %6d %9s %8.1f %8s  %s', r.kind, r.n, ms(r.total), r.total * 1e6 / r.n,
            ms(r.max), M._short(r.path, ctx.root)));
    end
    if #fl == 0 then add('  (none)'); end
    add('');

    local function frameLines(rec)
        local bits = {};
        if rec.gearOut ~= nil and rec.gearOut <= 5 then bits[#bits + 1] = string.format('gear out %.2fs before', rec.gearOut); end
        if rec.gearIn ~= nil and rec.gearIn <= 5 then bits[#bits + 1] = string.format('gear in %.2fs before', rec.gearIn); end
        if rec.gc then bits[#bits + 1] = 'GC cycle ended'; end
        add(string.format('  +%7.2fs  frame %6s ms  dlac %6s ms  files %d (%s ms)  heap %+.0f KB  pkts %d in / %d out%s',
            rec.t, ms(rec.iv), ms(rec.dlac), rec.io, ms(rec.iot), rec.heapDelta, rec.pin, rec.pout,
            (#bits > 0) and ('  -- ' .. table.concat(bits, ', ')) or ''));
        if #rec.h > 0 then
            table.sort(rec.h, function(a, b) return a[2] > b[2]; end);
            local hs = {};
            for _, h in ipairs(rec.h) do hs[#hs + 1] = string.format('%s %s', h[1], ms(h[2])); end
            add('        dlac: ' .. table.concat(hs, ', '));
        end
        if #rec.f > 0 then
            table.sort(rec.f, function(a, b) return a[3] > b[3]; end);
            local fs = {};
            for _, f in ipairs(rec.f) do fs[#fs + 1] = string.format('%s %s %s', f[1], M._short(f[2], ctx.root), ms(f[3])); end
            add('        files: ' .. table.concat(fs, ', '));
        end
        if #rec.p > 0 then add('        packets: ' .. table.concat(rec.p, ', ')); end
    end

    add('===== SLOWEST FRAMES (by frame time) =====');
    local slow = {};
    for _, r in ipairs(P.slow) do slow[#slow + 1] = r; end
    table.sort(slow, function(a, b) return a.iv > b.iv; end);
    for i, rec in ipairs(slow) do
        if i > 40 then break; end
        frameLines(rec);
    end
    if #slow == 0 then add('  (none over the hitch line)'); end
    add('');

    add('===== dlac\'s HEAVIEST FRAMES (by dlac\'s own time) =====');
    local heavy = {};
    for _, r in ipairs(P.heavy) do heavy[#heavy + 1] = r; end
    table.sort(heavy, function(a, b) return a.dlac > b.dlac; end);
    for i, rec in ipairs(heavy) do
        if i > 20 then break; end
        frameLines(rec);
    end
    if #heavy == 0 then add('  (dlac never ran 1 ms in a frame)'); end
    add('');

    add('===== HITCH SPACING =====');
    if #hitches > 2 then
        local byT = {};
        for _, r in ipairs(hitches) do byT[#byT + 1] = r.t; end
        table.sort(byT);
        local gaps = {};
        for i = 2, #byT do
            local g = math.floor((byT[i] - byT[i - 1]) * 10 + 0.5) / 10;
            gaps[g] = (gaps[g] or 0) + 1;
        end
        local gl = {};
        for g, c in pairs(gaps) do gl[#gl + 1] = { g = g, c = c }; end
        table.sort(gl, function(a, b) if a.c ~= b.c then return a.c > b.c; end return a.g < b.g; end);
        local s = {};
        for i, e in ipairs(gl) do if i > 10 then break; end s[#s + 1] = string.format('%.1fs x%d', e.g, e.c); end
        add('seconds between hitches: ' .. table.concat(s, ', '));
        add('(a steady number here = something on a timer)');
    else
        add('too few hitches to show a rhythm.');
    end
    add('');
    add('===== END =====');
    return table.concat(L, '\n') .. '\n';
end

-- The chat summary: the file's verdict in two lines.
function M.summary()
    local n = P.n or 0;
    if n == 0 then return { 'no frames recorded.' }; end
    local sorted = {};
    for i = 1, n do sorted[i] = P.iv[i]; end
    table.sort(sorted);
    local med = pct(sorted, 0.5);
    local thr = M._threshold(med);
    local nHitch, worstDlac = 0, 0;
    for i = 1, n do
        if P.iv[i] >= thr then nHitch = nHitch + 1; end
        if P.dl[i] > worstDlac then worstDlac = P.dl[i]; end
    end
    return {
        string.format('%d frames, median %s ms; %d hitch%s over %s ms, worst %s ms.', n, ms(med), nHitch,
            (nHitch == 1) and '' or 'es', ms(thr), ms(sorted[#sorted])),
        string.format('dlac ran %.3f ms per frame on average, %s ms at most.', (P.dlacTotal / n) * 1000, ms(worstDlac)),
    };
end

-- ---------------------------------------------------------------------------
-- live glue (Ashita only; seams for the tests)
-- ---------------------------------------------------------------------------

function M._context()
    local c = {};
    pcall(function() c.version = addon and addon.version; end);
    pcall(function() c.root = AshitaCore:GetInstallPath(); end);
    pcall(function() c.name = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0); end);
    pcall(function()
        local pl = AshitaCore:GetMemoryManager():GetPlayer();
        local zone = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0);
        c.where = string.format('job %s/%s, level %s/%s, zone %s', tostring(pl:GetMainJob()), tostring(pl:GetSubJob()),
            tostring(pl:GetMainJobLevel()), tostring(pl:GetSubJobLevel()), tostring(zone));
    end);
    pcall(function() c.pack = tostring(require('dlac\\gear\\serverpack').active()); end);
    pcall(function()
        local d = require('dlac\\profiles').dataDir();
        local f = REAL.open and REAL.open(d .. 'uiflags.lua', 'rb') or nil;
        if f ~= nil then
            local s = f:read('*a');
            f:close();
            c.flags = (s:gsub('%s+', ' '):gsub('^return ', ''));
        end
    end);
    return c;
end

function M._out()
    local root = nil;
    pcall(function() root = AshitaCore:GetInstallPath(); end);
    if root == nil then return nil; end
    local name = (P.ctx and P.ctx.name) or 'unknown';
    name = tostring(name):gsub('%W', '');
    if name == '' then name = 'unknown'; end
    return root .. 'addons\\dlac\\debug\\dlac-perf-' .. name .. '.txt';
end

function M._write(path, text)
    pcall(function()
        if ashita and ashita.fs and ashita.fs.create_directory then
            ashita.fs.create_directory((path:gsub('[^\\]+$', '')));
        end
    end);
    local open = REAL.open or io.open;
    local f = open(path, 'wb');
    if f == nil then error('cannot open for write: ' .. tostring(path), 0); end
    f:write(text);
    f:close();
end

function M.stop(why)
    if not P.on then return nil, 'nothing is measuring'; end
    P.on = false;
    P.heapLast = M._heap();
    local ok, text = pcall(M.render, why);
    if not ok then text = 'dlac frame profile: the report failed to render -- ' .. tostring(text) .. '\n'; end
    local path = M._out();
    if path == nil then return nil, 'the install path is unavailable'; end
    local wok, err = pcall(M._write, path, text);
    if not wok then return nil, 'write failed: ' .. tostring(err); end
    for _, line in ipairs(M.summary()) do print('[dlac] perf: ' .. line); end
    print('[dlac] perf: wrote ' .. path);
    return path;
end

-- '/dl perf ...' -> the argument word ('' when bare), nil when not ours.
-- Bare and argument forms matched separately, so '/dl perfx' is not eaten.
function M._parse(raw)
    raw = tostring(raw or '');
    if raw:match('^/dl%s+perf%s*$') ~= nil or raw:match('^/dlac%s+perf%s*$') ~= nil then return ''; end
    return raw:match('^/dl%s+perf%s+(.-)%s*$') or raw:match('^/dlac%s+perf%s+(.-)%s*$');
end

function M._usage()
    return 'perf [seconds|stop]  -- time every frame for a while (default ' .. M.DEF_S .. 's, '
        .. M.MIN_S .. '-' .. M.MAX_S .. ') and write debug\\dlac-perf-<Name>.txt: frame times,'
        .. ' what dlac did in each, file and gear-packet timing.';
end

local function onCommand(e)
    local sub = M._parse(string.lower(tostring(e.command)));
    if sub == nil then return; end
    e.blocked = true;
    if sub == 'stop' then
        local p, err = M.stop('the player stopped it');
        if p == nil then print('[dlac] perf: ' .. tostring(err) .. ' -- /dl perf starts one.'); end
        return;
    end
    if sub == 'help' or sub == '?' or (sub ~= '' and tonumber(sub) == nil) then
        print('[dlac] ' .. M._usage());
        return;
    end
    local secs = M._dur(sub ~= '' and sub or nil);
    local ok, err = M.start(secs);
    if not ok then
        print('[dlac] perf: ' .. tostring(err) .. ' -- /dl perf stop finishes it.');
        return;
    end
    print(string.format('[dlac] perf: measuring every frame for %ds. Play the way that stutters;'
        .. ' the file writes itself at the end (/dl perf stop finishes early).', secs));
end
M._onCommand = onCommand;

local function onUnload()
    if P.on then pcall(M.stop, 'dlac was unloaded'); end
end

-- ---------------------------------------------------------------------------
-- install: wrap the registrar and the file functions (dlac.lua calls this
-- before anything registers an event)
-- ---------------------------------------------------------------------------

function M.install()
    if M._installed then return true; end
    local ev = ashita and ashita.events;
    if type(ev) ~= 'table' or type(ev.register) ~= 'function' then return false; end
    REAL.register = ev.register;
    REAL.open, REAL.loadfile, REAL.dofile = io.open, loadfile, dofile;
    REAL.remove, REAL.rename = os.remove, os.rename;

    ev.register = function(name, alias, fn)
        if type(fn) ~= 'function' then return REAL.register(name, alias, fn); end
        return REAL.register(name, alias, shim(recFor(name, alias), fn));
    end

    io.open = function(path, mode)
        if not P.on then return REAL.open(path, mode); end
        local t0 = M._now();
        if mode ~= nil and string.find(mode, '[wa+]') ~= nil then
            return writer(path, t0, REAL.open(path, mode));
        end
        return ioDone('open.r', path, t0, REAL.open(path, mode));
    end
    loadfile = function(path, ...)
        if not P.on then return REAL.loadfile(path, ...); end
        local t0 = M._now();
        return ioDone('loadfile', path, t0, REAL.loadfile(path, ...));
    end
    dofile = function(path)
        if not P.on then return REAL.dofile(path); end
        local t0 = M._now();
        return ioDone('dofile', path, t0, REAL.dofile(path));
    end
    os.remove = function(path)
        if not P.on then return REAL.remove(path); end
        local t0 = M._now();
        return ioDone('remove', path, t0, REAL.remove(path));
    end
    os.rename = function(a, b)
        if not P.on then return REAL.rename(a, b); end
        local t0 = M._now();
        return ioDone('rename', a, t0, REAL.rename(a, b));
    end
    pcall(function()
        local fs = ashita.fs;
        if type(fs) ~= 'table' then return; end
        REAL.fs = {};
        for k, fn in pairs(fs) do
            if type(fn) == 'function' then
                REAL.fs[k] = fn;
                local kind = 'fs.' .. tostring(k);
                fs[k] = function(p, ...)
                    if not P.on then return fn(p, ...); end
                    local t0 = M._now();
                    return ioDone(kind, p, t0, fn(p, ...));
                end
            end
        end
    end);

    -- The profiler's own hooks, on the REAL registrar: never timed, never in
    -- the table they produce.
    REAL.register('d3d_present', 'dlac-frameprof', frameMark);
    REAL.register('packet_in', 'dlac-frameprof-in', pktIn);
    REAL.register('packet_out', 'dlac-frameprof-out', pktOut);
    REAL.register('command', 'dlac-frameprof-cmd', onCommand);
    REAL.register('unload', 'dlac-frameprof-unload', onUnload);
    M._installed = true;
    return true;
end

-- Test seam: put every wrapped function back.
function M._uninstall()
    if not M._installed then return; end
    if ashita and ashita.events and REAL.register then ashita.events.register = REAL.register; end
    io.open, loadfile, dofile = REAL.open, REAL.loadfile, REAL.dofile;
    os.remove, os.rename = REAL.remove, REAL.rename;
    if REAL.fs ~= nil and ashita and type(ashita.fs) == 'table' then
        for k, fn in pairs(REAL.fs) do ashita.fs[k] = fn; end
    end
    P.on = false;
    M._installed = nil;
end

return M;
