--[[
    dlac/feature/eboxtrace.lua -- the readout behind `/dl debug ebox`.

    E-Box Restock v2 rests on a promise about server load: the box's contents are
    tracked by arithmetic, so standing at a box crafting sends NOTHING (see
    feature/eboxclient's header, and docs/design/ebox-restock-v2-grill-2026-07-25.md).
    A promise nobody can watch is a hope. This is the window onto it: every
    packet the one client sent, when, and what caused it -- plus, when nothing
    is being sent, which gate is holding it back.

    Henrik's 07-23 ruling stands: packet CAPTURE lives in dlacprobe. This is not
    capture -- dlacprobe can see an outgoing 0x1A4 but can never say WHY we sent
    it. Only the client knows that it was a verify rather than a re-count, or
    that a `!box store` dirtied everything. So this is a wiring-health readout of
    our own decisions, the same class as `/dl check`.

    Two surfaces:
      * `/dl debug ebox`             -- the snapshot (counters, gates, last 40 events)
      * `/dl debug ebox on|off`      -- live echo: each event printed as it happens
      * `/dl debug ebox reset`       -- zero the counters and clear the log

    THE THREAD RULE: eboxclient RECORDS from wherever it happens, including the
    packet thread, because appending to a table is safe there. Printing is not
    (feature/chocowatch paid for that with a crash). So the live echo is pumped
    from d3d_present, and this module is the only thing that prints.

    This module is required lazily by the debug router, so an unused debug
    surface costs nothing -- not even the d3d_present hook below.
]]--

local M = {};

local _ecok, ec = pcall(require, 'dlac\\feature\\eboxclient');
_ecok = _ecok and type(ec) == 'table';

-- "12.3s" / "2m04s" / "1h02m". Pure (tests EBT*).
function M._dur(sec)
    sec = math.max(0, tonumber(sec) or 0);
    if sec < 60 then return string.format('%.1fs', sec); end
    if sec < 3600 then return string.format('%dm%02ds', math.floor(sec / 60), math.floor(sec % 60)); end
    return string.format('%dh%02dm', math.floor(sec / 3600), math.floor((sec % 3600) / 60));
end

local function joinNums(t)
    if #t == 0 then return 'none'; end
    local s = {};
    for _, v in ipairs(t) do s[#s + 1] = tostring(v); end
    return table.concat(s, ', ');
end

-- The whole readout, as lines. PURE over the client table (tests EBT*): hand it
-- a stand-in and it formats that, so the shape is pinned without a game running.
function M.lines(c)
    if type(c) ~= 'table' then return { 'eboxclient failed to load -- nothing to report.' }; end
    local out = {};
    local now = c._now();
    local st  = c.stats or {};
    local outN, inN = st.out or 0, st.inn or 0;
    local span = (st.since ~= nil) and math.max(0, now - st.since) or 0;
    local rate = (span > 1 and outN > 0) and string.format('  (%.1f/min)', outN * 60 / span) or '';

    out[#out + 1] = string.format('E-Box traffic: %d packet%s sent, %d received, over %s%s',
        outN, (outN == 1) and '' or 's', inN, M._dur(span), rate);

    local kinds = {};
    for k, n in pairs(st.byKind or {}) do kinds[#kinds + 1] = string.format('%s x%d', k, n); end
    table.sort(kinds);
    out[#out + 1] = '  sent: ' .. ((#kinds > 0) and table.concat(kinds, '   ') or '(nothing yet)');

    -- Why it is (or is not) talking right now. `c.busy` is read RAW on purpose:
    -- isBusy() has side effects, and a readout must never change what it reports.
    local cw, dist, sBusy = false, nil, false;
    pcall(function() cw = (c.isCW() == true); end);
    pcall(function() dist = c.boxDistance(); end);
    pcall(function() sBusy = (c.searchBusy() == true); end);
    out[#out + 1] = string.format('Now: %s | %s | %s | %s',
        cw and 'Crystal Warrior' or 'NOT CW -- every query refused',
        (dist == nil) and 'no Ephemeral Box in sight'
            or string.format('box %.1f yalms (%s)', dist,
                (dist <= (c.BOX_RANGE or 5)) and 'IN RANGE' or 'too far to query'),
        c.busy and 'withdraw in flight' or (sBusy and 'search in flight' or 'idle'),
        (st.lastOutAt ~= nil) and ('last sent ' .. M._dur(now - st.lastOutAt) .. ' ago')
            or 'nothing sent yet');
    if c.lockedReason ~= nil then
        out[#out + 1] = '  the server said LOCKED (' .. tostring(c.lockedReason)
            .. ') -- nothing more will be sent this session';
    end
    local menu = false;
    pcall(function() menu = (c.menuOpen() == true); end);
    if menu then
        out[#out + 1] = '  a `!box ...` menu is open -- off the wire until items actually'
            .. ' move (or you cancel, which costs nothing)';
    end

    -- What we believe, and what we have stopped believing. Anything in `dirty`
    -- is what the NEXT verify near a box will spend a packet on.
    local believed, dirty = {}, {};
    for cat in pairs(c.cat or {}) do
        if (c.dirty or {})[cat] then dirty[#dirty + 1] = cat; else believed[#believed + 1] = cat; end
    end
    table.sort(believed); table.sort(dirty);
    out[#out + 1] = string.format('Categories: believed %s | dirty, will re-count: %s',
        joinNums(believed), joinNums(dirty));

    out[#out + 1] = string.format('Recent -- oldest first, > sent, < received, * event%s:',
        c.echo and '   [LIVE ECHO ON]' or '');
    local tr = c.trace or {};
    if #tr == 0 then
        out[#out + 1] = '  (nothing yet -- walk up to a box, or open the Restock panel)';
    else
        for _, e in ipairs(tr) do
            out[#out + 1] = string.format('  %8s ago  %s %s', M._dur(now - e.at), e.dir, e.what);
        end
    end
    return out;
end

function M.report(c)
    for _, l in ipairs(M.lines(c or ec)) do print('[dlac] ' .. l); end
end

-- The live echo, drained on the RENDER thread (see THE THREAD RULE above).
function M.pump()
    if not _ecok or not ec.echo then return; end
    local t = ec.trace or {};
    while (ec.echoAt or 0) < #t do
        ec.echoAt = (ec.echoAt or 0) + 1;
        local e = t[ec.echoAt];
        if e ~= nil then print(string.format('[dlac] ebox %s %s', e.dir, e.what)); end
    end
end

function M.setEcho(on)
    if not _ecok then return false; end
    ec.echo = (on == true);
    ec.echoAt = #(ec.trace or {});   -- start from NOW: do not replay the backlog
    return ec.echo;
end

pcall(function()
    ashita.events.register('d3d_present', 'dlac_eboxtrace_echo', function() M.pump(); end);
end);

-- ---------------------------------------------------------------------------
-- `/dl debug ebox scan` -- the ENTITY probe. MOVED HERE 2026-07-27 from
-- feature/eboxammo (deleted with AutoAmmo's E-Box section; auto-ammo.md §10.8)
-- rather than deleted with it: this is the readout that ended two field rounds
-- of always-red fetch buttons, proximity is still what refuses an E-Box Restock
-- withdraw, and it answers the one question the traffic report above cannot --
-- is there a box out there at all, and where?
--
-- Three rules are baked in and every one of them cost a field round:
--   * sweep the WHOLE array 0x000-0x8FF -- E-Boxes are DYNAMIC entities (a live
--     Bastok Mines sample, server id 17737730, decodes to index 0x802), so a
--     0-1023 static sweep can never see one;
--   * GetName returns TRAILING WHITESPACE -- trim it, and compare ci;
--   * check RenderFlags0 bit 0x200 (rendered; the flags read back SIGNED) before
--     trusting GetDistance, which is SQUARED.
-- ---------------------------------------------------------------------------
local _gmok, _gm = pcall(require, 'dlac\\feature\\gamemode');
_gmok = _gmok and type(_gm) == 'table';
local _ewok, _ew = pcall(require, 'dlac\\lib\\entwatch');
_ewok = _ewok and type(_ew) == 'table';

function M.scan()
    local gm, cw, dist = nil, nil, nil;
    if _gmok then pcall(function() gm = _gm.get(); end); end
    if _ecok then
        pcall(function() cw = ec.isCW(); end);
        pcall(function() dist = ec.boxDistance(); end);
    end
    print(string.format('[dlac] ebox scan: gamemode=%s isCW=%s locked=%s dist=%s range=%d',
        tostring(gm), tostring(cw), tostring(_ecok and ec.lockedReason or 'n/a'),
        tostring(dist), (_ecok and ec.BOX_RANGE) or 5));
    if _ewok then
        for _, w in ipairs(_ew.debugState()) do
            print(string.format('[dlac] ebox watch: %q subs=[%s] matches=%d active=%s',
                w.name, w.subs, w.matches, tostring(w.active)));
        end
    end
    local ok = pcall(function()
        local em = AshitaCore:GetMemoryManager():GetEntity();
        local nRaw, nRen, nHit, near = 0, 0, 0, {};
        for i = 0, 2303 do
            pcall(function()
                if em:GetRawEntity(i) == nil then return; end
                nRaw = nRaw + 1;
                local rf = em:GetRenderFlags0(i) or 0;
                if rf < 0 then rf = rf + 4294967296; end
                local ren = (math.floor(rf / 0x200) % 2) == 1;
                if ren then nRen = nRen + 1; end
                local nm = tostring(em:GetName(i) or ''):gsub('%s+$', '');
                local d = em:GetDistance(i);
                if string.find(string.lower(nm), 'ephemeral', 1, true) ~= nil then
                    nHit = nHit + 1;
                    print(string.format('[dlac] ebox HIT idx=0x%03X name=%q sid=%s rf0=0x%08X rendered=%s distSq=%s (%.1fy)',
                        i, nm, tostring(em:GetServerId(i)), rf, tostring(ren), tostring(d),
                        (type(d) == 'number' and d >= 0) and math.sqrt(d) or -1));
                elseif ren and nm ~= '' and type(d) == 'number' and d >= 0 and d < 900 then
                    near[#near + 1] = { i = i, nm = nm, d = d };
                end
            end);
        end
        table.sort(near, function(x, y) return x.d < y.d; end);
        local parts = {};
        for k = 1, math.min(8, #near) do
            parts[#parts + 1] = string.format('%s(0x%03X,%.1fy)', near[k].nm, near[k].i, math.sqrt(near[k].d));
        end
        print(string.format('[dlac] ebox scan: raw=%d rendered=%d ephemeral-hits=%d; nearest named: %s',
            nRaw, nRen, nHit, table.concat(parts, ', ')));
    end);
    if not ok then print('[dlac] ebox scan: no entity array to read (headless?).'); end
end

-- The topic body. feature/debug.lua's router owns the command itself; `rest` is
-- everything after 'debug', i.e. 'ebox' / 'ebox on' / 'ebox reset' / 'ebox scan'.
-- Pure-ish word split so tests can drive it (EBT*).
function M._word(rest)
    return string.match(string.lower(tostring(rest or '')), '^%S+%s+(%S+)') or '';
end

function M.run(rest)
    local w = M._word(rest);
    if w == 'on' or w == 'off' then
        M.setEcho(w == 'on');
        print('[dlac] E-Box live echo ' .. ((w == 'on')
            and 'ON -- every packet is printed the moment it goes out.' or 'off.'));
        return;
    end
    if w == 'reset' then
        if _ecok then ec.traceReset(); end
        print('[dlac] E-Box traffic counters and log cleared.');
        return;
    end
    if w == 'scan' then M.scan(); return; end
    M.report(ec);
    print('[dlac]   on|off = echo it live   |   reset = clear the counters   |   scan = find the box');
end

return M;
