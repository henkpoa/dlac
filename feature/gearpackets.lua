--[[
    dlac/feature/gearpackets.lua -- /dl gearpackets: HOW GEAR GOES ON THE WIRE.

    The question that begat it (Henrik, 2026-08-06): "does it send a packet per
    slot, and would equipsets be cheaper?" The research answer is in
    gear\equipcore's AUTO_THRESHOLD comment; this is the knob that lets the
    field answer it instead of the source.

    WHAT THE SERVER ACTUALLY OFFERS (catseyexi src\map\packets\c2s):
      * 0x050 EQUIP_SET      -- one slot. 8 bytes.
      * 0x051 EQUIPSET_SET   -- up to 16 slots in ONE packet. Fixed 72 bytes.
      * 0x052 EQUIPSET_CHECK -- a validity query, answered with 0x116.

    The game's saved Equipment Sets are CLIENT-SIDE bookkeeping. The server
    stores no equipset and 0x051 carries raw {index, slot, container} triples,
    so there is nothing to register and nothing to keep in sync -- the batch is
    available to any sender at any time. That is why this is a style switch and
    not a set-builder.

    THE TRADE, which is the whole reason for a knob:
      * BYTES favour singles under 9 pieces (8*n vs a flat 72).
      * SERVER WORK favours the batch always: 0x050's handler and 0x051's run
        the same post-equip tail -- RequestPersist, luautils::CheckForGearSet
        (a Lua call that clears every gear-set mod and rescans all 16 slots),
        UpdateHealth, retriggerLatents -- but 0x051 runs it ONCE for the whole
        set instead of once per slot.
      * ATOMICITY favours the batch: one packet cannot be split across chunks,
        and the server validates it whole (a bad entry drops all 16, where a
        bad single drops only itself).

    Which of those matters in play is a field question, so: four modes and a
    threshold, switchable live, with /dl sends as the readout.

    WHY IT COVERS PRECAST AND MIDCAST BOTH (Henrik, same session). LAC ships
    Precast/Preshot as 'set' and Midcast/Midshot as 'single', and the intuition
    for the split -- "precast is rushed, midcast has the whole cast to work
    with" -- does not survive reading the pipeline: equipengine.handleAction
    fires pre, re-injects the action and fires mid as three synchronous calls
    inside ONE outgoing chunk. Midcast is microseconds behind precast, not
    seconds, so the two are the same timing problem and a mode that moved only
    one of them would be measuring nothing.

    NOT A PROBE (the 07-23 ruling): this changes dlac's own send shape and
    reads dlac's own counters. Nothing here touches the wire.

    Pure at load; every require / file touch is call-time under pcall.
]]--

local M = {};

-- ---------------------------------------------------------------------------
-- pure core (headless-tested, GP*)
-- ---------------------------------------------------------------------------

-- 'default' means "whatever the dispatch point asks for" -- the LAC-parity
-- shape. The other three OVERRIDE every dispatch point at once, which is what
-- makes an A/B in the field a single command apart.
M.MODES = { 'default', 'single', 'set', 'auto' };

M.MODE_BLURB = {
    ['default'] = 'each dispatch point picks (LAC parity: Precast/Preshot batch, Midcast/Midshot single, the rest auto)',
    ['single']  = 'ALWAYS one 0x050 per slot, however many slots change',
    ['set']     = 'ALWAYS one 0x051 batch, even for a single slot',
    ['auto']    = 'batch from the threshold up, singles below it -- everywhere',
};

function M.isMode(s)
    s = string.lower(tostring(s or ''));
    for _, m in ipairs(M.MODES) do
        if m == s then return m; end
    end
    return nil;
end

-- 1..16 -- sixteen is every equip slot the game has, and the extremes already
-- have names ('set' is threshold 1, 'single' is "no threshold"), so the knob
-- does not need to reach past what it can express.
function M.clampThreshold(n)
    n = tonumber(n);
    if n == nil then return nil; end
    n = math.floor(n);
    if n < 1 then n = 1; end
    if n > 16 then n = 16; end
    return n;
end

-- THE RESOLUTION, and the only place the override means anything: 'default'
-- defers to the dispatch point, everything else replaces it.
function M.resolve(routeStyle, mode)
    local m = M.isMode(mode) or 'default';
    if m == 'default' then
        return (routeStyle == 'set' or routeStyle == 'single') and routeStyle or 'auto';
    end
    return m;
end

-- One line per dispatch point: what it asks for, and what it will get.
-- `points` is { { name = 'Precast', style = 'set' }, ... } -- the caller
-- assembles it from the live route table so this cannot drift from it.
function M.effective(points, mode)
    local out = {};
    for _, p in ipairs(points or {}) do
        out[#out + 1] = { name = p.name, asked = p.style, gets = M.resolve(p.style, mode) };
    end
    return out;
end

-- What one resolved style will DO at a given size -- 'auto' is the only one
-- that still depends on the plan, so it is the only one that names a number.
function M.shapeOf(style, threshold)
    if style == 'set' then return 'one 0x051'; end
    if style == 'single' then return 'one 0x050 per slot'; end
    return string.format('0x051 from %d slots up, else 0x050 each', threshold or 9);
end

-- mode + threshold + the resolved dispatch points -> the readout lines
-- (no '[dlac] ' prefix -- the caller adds it).
function M.lines(mode, threshold, points)
    local m = M.isMode(mode) or 'default';
    local t = M.clampThreshold(threshold) or 9;
    local L = {};
    L[#L + 1] = string.format('gearpackets: mode %s -- %s.', string.upper(m), M.MODE_BLURB[m]);
    if m == 'default' or m == 'auto' then
        L[#L + 1] = string.format('gearpackets: threshold %d -- an auto dispatch point batches from %d changed slots up'
            .. ' (byte parity is 9: a 0x050 is 8 bytes, a 0x051 a flat 72).', t, t);
    else
        L[#L + 1] = string.format('gearpackets: threshold %d -- not consulted in %s mode.', t, m);
    end

    local eff = M.effective(points, m);
    if #eff > 0 then
        L[#L + 1] = 'gearpackets: dispatch points --';
        for _, e in ipairs(eff) do
            local moved = (e.asked ~= e.gets) and '  <- overridden' or '';
            L[#L + 1] = string.format('    %-12s asks %-6s gets %-6s  %s%s',
                e.name, e.asked, e.gets, M.shapeOf(e.gets, t), moved);
        end
    end

    -- THE LINE THAT SAVES A FIELD ROUND. Conflict strips are unequips that
    -- must land BEFORE the equips that displaced them, so they ride as their
    -- own 0x050s at every mode including 'set'. Without this said out loud,
    -- the first 0x050 seen in set mode reads as "the switch did nothing".
    L[#L + 1] = 'gearpackets: conflict strips (a slot emptied so its item can move) always ride as'
             .. ' separate 0x050s ahead of the equips -- seeing those in set mode is correct.';
    L[#L + 1] = 'gearpackets: /dl sends counts what actually went out, by packet id and by cause --'
             .. ' the cause names the dispatch point and the shape it used.';
    return L;
end

-- raw (lowercased) -> the argument words, or nil when the command is not ours.
-- Bare and argument forms are matched SEPARATELY, sendlog's law: one combined
-- pattern also swallows '/dl gearpacketsfoo', and a command that eats its
-- neighbours is worse than one that misses.
function M.parse(raw)
    raw = tostring(raw or '');
    for _, verb in ipairs({ 'gearpackets', 'gp' }) do
        if raw:match('^/dl%s+' .. verb .. '%s*$') ~= nil
            or raw:match('^/dlac%s+' .. verb .. '%s*$') ~= nil then
            return {};
        end
        local rest = raw:match('^/dl%s+' .. verb .. '%s+(.-)%s*$')
                  or raw:match('^/dlac%s+' .. verb .. '%s+(.-)%s*$');
        if rest ~= nil then
            local args = {};
            for w in string.gmatch(rest, '%S+') do args[#args + 1] = w; end
            return args;
        end
    end
    return nil;
end

-- args -> an intent the command handler can act on without re-parsing.
-- A bare number is a threshold: '/dl gp 3' is what a tired thumb types, and
-- refusing it to insist on '/dl gp threshold 3' buys nothing.
function M.intent(args)
    args = (type(args) == 'table') and args or {};
    if #args == 0 then return { kind = 'show' }; end
    local a1 = string.lower(tostring(args[1]));
    if a1 == 'threshold' or a1 == 't' then
        local n = M.clampThreshold(args[2]);
        if n == nil then return { kind = 'usage' }; end
        return { kind = 'threshold', n = n };
    end
    local m = M.isMode(a1);
    if m ~= nil then return { kind = 'mode', mode = m }; end
    local n = M.clampThreshold(a1);
    if n ~= nil and tostring(args[1]):match('^%d+$') ~= nil then
        return { kind = 'threshold', n = n };
    end
    return { kind = 'usage' };
end

-- ---------------------------------------------------------------------------
-- the live store
-- ---------------------------------------------------------------------------

-- Persisted, and that is a correctness requirement rather than a convenience:
-- a mode that silently reverted on /addon reload would let a field round
-- report numbers for a mode the player thought they had left.
local SPEC = {
    file     = 'gearpackets.lua',
    keys     = { mode = 'string', threshold = 'number' },
    defaults = { mode = 'default', threshold = 9 },
};

local _store = nil;

local function store()
    if _store ~= nil then return _store; end
    pcall(function()
        local mc = require('dlac\\feature\\modcfg');
        if type(mc) == 'table' and type(mc.open) == 'function' then
            _store = mc.open('gearpackets', SPEC);
        end
    end);
    return _store;
end

-- Pre-login (or with the store absent) these serve the declared defaults, so
-- no caller ever has to branch on "not ready yet" -- and the defaults ARE the
-- LAC-parity shape, so a failure to load settles on today's behaviour.
function M.mode()
    local s = store();
    if s == nil then return SPEC.defaults.mode; end
    local ok, v = pcall(s.get, 'mode');
    return (ok and M.isMode(v)) or SPEC.defaults.mode;
end

function M.threshold()
    local s = store();
    if s == nil then return SPEC.defaults.threshold; end
    local ok, v = pcall(s.get, 'threshold');
    if not ok then return SPEC.defaults.threshold; end
    return M.clampThreshold(v) or SPEC.defaults.threshold;
end

-- Returns true when the value is now in effect. False means pre-login: the
-- store has no character directory to write to yet.
function M.setMode(m)
    m = M.isMode(m);
    if m == nil then return false; end
    local s = store();
    if s == nil then return false; end
    local ok, res = pcall(s.set, 'mode', m);
    return ok and res == true;
end

function M.setThreshold(n)
    n = M.clampThreshold(n);
    if n == nil then return false; end
    local s = store();
    if s == nil then return false; end
    local ok, res = pcall(s.set, 'threshold', n);
    return ok and res == true;
end

-- THE CALL equipengine makes: a dispatch point's declared style in, the style
-- to actually send with out.
function M.styleFor(routeStyle)
    return M.resolve(routeStyle, M.mode());
end

-- The dispatch points, read from the LIVE route table so this readout cannot
-- drift from what the engine does. The three that have no route row (they
-- call fireEvent directly) are named here because a player looking for
-- "why is my idle swap still singles" needs to find Default in the list.
M.EXTRA_POINTS = {
    { name = 'Default', style = 'auto' },
    { name = 'Item',    style = 'auto' },
    { name = 'PetAction', style = 'auto' },
};

function M.points()
    local out = {};
    pcall(function()
        local ee = require('dlac\\feature\\equipengine');
        local routes = (type(ee) == 'table') and ee.ACTION_ROUTES or nil;
        if type(routes) ~= 'table' then return; end
        local ids = {};
        for id in pairs(routes) do ids[#ids + 1] = id; end
        table.sort(ids);
        for _, id in ipairs(ids) do
            local r = routes[id];
            if r.pre ~= nil then out[#out + 1] = { name = r.pre, style = r.preStyle or 'auto' }; end
            if r.mid ~= nil then out[#out + 1] = { name = r.mid, style = r.midStyle or 'auto' }; end
        end
    end);
    for _, p in ipairs(M.EXTRA_POINTS) do out[#out + 1] = p; end
    return out;
end

-- ---------------------------------------------------------------------------
-- the command
-- ---------------------------------------------------------------------------

local USAGE = 'usage: /dl gearpackets [default|single|set|auto] [threshold <1-16>]'
           .. '   how dlac puts gear on the wire (/dl gp works too)';

function M.report()
    for _, l in ipairs(M.lines(M.mode(), M.threshold(), M.points())) do print('[dlac] ' .. l); end
end

ashita.events.register('command', 'dlac-gearpackets', function(e)
    local args = M.parse(string.lower(e.command));
    if args == nil then return; end
    e.blocked = true;

    local it = M.intent(args);
    if it.kind == 'usage' then
        print('[dlac] ' .. USAGE);
        return;
    end
    if it.kind == 'show' then
        M.report();
        return;
    end
    -- ACKS ARE ONE LINE (the /dl disable standard), then the full state, so a
    -- switch mid-fight costs one glance and a deliberate check costs none.
    if it.kind == 'mode' then
        local was = M.mode();
        if not M.setMode(it.mode) then
            print('[dlac] gearpackets: cannot store the mode yet -- not logged in.');
            return;
        end
        print(string.format('[dlac] gearpackets: %s -> %s.', was, it.mode));
    elseif it.kind == 'threshold' then
        local was = M.threshold();
        if not M.setThreshold(it.n) then
            print('[dlac] gearpackets: cannot store the threshold yet -- not logged in.');
            return;
        end
        print(string.format('[dlac] gearpackets: threshold %d -> %d.', was, it.n));
    end
    M.report();
end);

return M;
