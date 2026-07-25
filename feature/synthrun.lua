--[[
    dlac/feature/synthrun.lua -- run the LAST SYNTH N times (the 2..6 buttons).

    Henrik's model, and the whole point: this is a MACRO BAR, not an automation.
    Six is the cap because six is what a macro bar holds -- dlac saves you the
    six clicks, it does not craft for you. So the rules are deliberately narrow:
    one batch at a time, one command in flight, and it stops the moment the game
    stops cooperating.

    HOW IT PACES ITSELF (the part that matters)
    -------------------------------------------
    /lastsynth is the CLIENT'S OWN text command (see craftwatch's LAST SYNTH
    note) -- dlac may TYPE it and nothing else.
    So there is no return value, no callback, no way to ask "did that work?".
    We watch the wire instead:

      s2c 0x030  synthesis animation  -- arrives ~130ms after the synth starts,
                                        and the RESULT is already in it (the
                                        server rolls it the instant 0x096 lands).
                                        This is our "the shot landed" proof.
      s2c 0x06F  synthesis results    -- arrives ~17s later with the item id and
                                        quantity. This is our "what came out".

    Both offsets are the ones Ashita's own stock craftmon addon uses
    (addons/craftmon/craftmon.lua) and they match the CatsEyeXI server structs.

    THE TIMER IS FIELD TRUTH, NOT SOURCE MATH (Henrik, 07-25). The server says
    ~17s is legal (15s cooldown from synth start + a 16s AI state). The REAL
    floor is ~22s in perfect conditions, because the client's synthesis
    animation is FRAME-TIED -- in a frame-heavy zone like Lower Jeuno it takes
    longer in wall-clock and the client silently refuses to send another 0x096.
    Hence: the wait is the player's knob (default 30, floor 20), and a shot that
    does not land gets ONE retry before we give up. Frame hitches are transient;
    "out of materials" and "inventory full" are permanent, so the retry costs
    ~2s at the end of a run that was over anyway.

    WHAT A MISS LOOKS LIKE. Every refusal collapses to the same thing on our
    side -- no 0x030 comes back:
      * inventory full        -- the CLIENT refuses to send, and says so in chat
      * out of materials      -- 0x06F CancelBadRecipe, no animation
      * craft skill too low   -- 0x06F CancelSkillTooLow
      * fired too early       -- server drops it SILENTLY (packet_system.cpp
                                 logs a console warning and sends nothing)
    We do not try to tell those apart from the packet alone; we report the
    honest set of causes and stop. A 0x06F cancel code, when we get one, sharpens
    the message.

    THREADING. packet_in runs on the NETWORK thread, where chat and IO crash the
    client (see chocowatch's dig-obtained note). The handlers here decode and
    STASH into `inbox`; every decision, every chat line and every clock read
    happens in M.tick() on the main thread.

    Public door: start / stop / status / tick. The bar reads status() to draw
    itself; nothing else may touch the state table.
]]--

local M = {};

-- ---------------------------------------------------------------------------
-- tunables
-- ---------------------------------------------------------------------------
local MAX_BATCH     = 6;      -- Henrik: a macro bar holds six
local DETECT_WINDOW = 2.0;    -- seconds to see 0x030 after firing (Henrik: "if
                              -- you need more than that, your timer is way too
                              -- tight" -- 0x030 lands ~130ms after the synth)
local RESULT_GRACE  = 30.0;   -- max wait for the FINAL 0x06F before reporting
                              -- anyway (~17s typical; 30 covers a bad zone)

-- Result codes the CatsEyeXI server actually emits (synthesis_result.h). The
-- other retail codes are dead on this server.
local R_SUCCESS       = 0x00;
local R_FAILED        = 0x01;   -- break: materials lost
local R_BAD_RECIPE    = 0x03;   -- also "missing ingredients" and "no guild KI"
local R_SKILL_TOO_LOW = 0x06;
local R_DESYNTH_OK    = 0x0C;
local R_INTERRUPTED   = 0x0E;   -- zoned/KO mid-synth: ALL materials destroyed

local CANCEL_REASON = {
    [R_BAD_RECIPE]    = 'the recipe was rejected (out of materials, or not a recipe you can make)',
    [R_SKILL_TOO_LOW] = 'your craft skill is too low for that recipe',
    [R_INTERRUPTED]   = 'the synth was interrupted -- materials lost',
};

-- Injectable clock (lib/entwatch's seam): a timed module with a hardcoded
-- os.clock() cannot be tested headless.
function M._now() return os.clock(); end

-- ---------------------------------------------------------------------------
-- chat. chatfmt.good is GREEN (chat.success). The type guards are mandatory,
-- not defensive noise: the headless suite stubs chatfmt as { print = ... } with
-- no .good/.warn, and an unguarded call nil-indexes there.
-- ---------------------------------------------------------------------------
local _cfok, _cfmt = pcall(require, 'dlac\\chatfmt');
_cfok = _cfok and type(_cfmt) == 'table';
local function emit(fn, s)
    if _cfok and type(_cfmt[fn]) == 'function' then _cfmt[fn](s); else print('[dlac] ' .. s); end
end
local function good(s) emit('good', s); end   -- green: the batch ran in full
local function warn(s) emit('warn', s); end   -- yellow: it stopped early
local function say(s)  emit('msg',  s); end   -- white: you stopped it, or a tally

-- ---------------------------------------------------------------------------
-- state. nil = idle. Only tick() and the API below may write it.
--   stage 'await'  fired, watching for 0x030 until `deadline`
--         'cool'   synth landed, waiting out the player's timer until `nextAt`
--         'finish' last synth landed, waiting for its 0x06F until `graceAt`
-- ---------------------------------------------------------------------------
local run = nil;
local inbox = {};    -- packet-thread stash, drained in tick()

-- ---------------------------------------------------------------------------
-- the wait timer. craftwatch OWNS <char>\dlac\craftstate.lua -- two writers
-- would clobber each other -- so the value lives there and we read through it.
-- ---------------------------------------------------------------------------
function M.getWait()
    local v = nil;
    pcall(function() v = require('dlac\\feature\\craftwatch').getSynthWait(); end);
    return tonumber(v) or 30;
end

function M.setWait(n)
    pcall(function() require('dlac\\feature\\craftwatch').setSynthWait(n); end);
end

-- ---------------------------------------------------------------------------
-- pure helpers (headless-testable)
-- ---------------------------------------------------------------------------

-- Decode s2c 0x030 (synthesis animation). Packet offset o = byte o+1 in Lua.
-- Returns the actor's target index and the result type, or nil.
function M.decodeAnim(data)
    if type(data) ~= 'string' or #data < 0x0E then return nil; end
    local function b(o) return string.byte(data, o + 1) or 0; end
    return b(0x08) + b(0x09) * 256, b(0x0C);
end

-- Decode s2c 0x06F (synthesis results). Returns result code, count, item id.
function M.decodeResult(data)
    if type(data) ~= 'string' or #data < 0x0A then return nil; end
    local function b(o) return string.byte(data, o + 1) or 0; end
    return b(0x04), b(0x06), b(0x08) + b(0x09) * 256;
end

local _nameCache = {};
local function itemName(id)
    if _nameCache[id] ~= nil then return _nameCache[id]; end
    local nm = nil;
    pcall(function()
        local r = AshitaCore:GetResourceManager():GetItemById(id);
        nm = (r ~= nil and r.Name ~= nil) and r.Name[1] or nil;
    end);
    _nameCache[id] = nm or ('item #' .. tostring(id));
    return _nameCache[id];
end
M._itemName = itemName;   -- test seam

-- "10x Bronze Ingot, 2x Bronze Ingot +1" -- grouped by item, order of first
-- appearance. HQ needs no special case: the game names HQ items "... +1", so
-- the tally shows them apart for free (crafts.lua only stores the NQ id).
function M.tally(results, nameOf)
    nameOf = nameOf or M._itemName;
    local order, byId, made, broke = {}, {}, 0, 0;
    for _, r in ipairs(results or {}) do
        if r.code == R_SUCCESS or r.code == R_DESYNTH_OK then
            made = made + 1;
            if r.id ~= nil and r.id ~= 0 then
                if byId[r.id] == nil then byId[r.id] = 0; order[#order + 1] = r.id; end
                byId[r.id] = byId[r.id] + math.max(1, r.count or 1);
            end
        elseif r.code == R_FAILED then
            broke = broke + 1;
        end
    end
    local parts = {};
    for _, id in ipairs(order) do
        parts[#parts + 1] = string.format('%dx %s', byId[id], nameOf(id));
    end
    return made, broke, table.concat(parts, ', ');
end

-- ---------------------------------------------------------------------------
-- the report -- ONE line at the end (plus a tally line when there is one).
-- Henrik stripped every per-synth print out of craftwatch on 07-13 as "too
-- chatty"; the bar's "Stop 3/6" IS the progress display.
-- ---------------------------------------------------------------------------
local function report(why, extra)
    local made, broke, items = M.tally(run.results);
    local n, total = run.started, run.total;
    local head;
    if why == 'done' then
        head = string.format('Crafting complete -- %d synth%s', n, (n == 1) and '' or 's');
        if broke > 0 then head = head .. string.format(' (%d made, %d broke)', made, broke); end
        good(head .. ((items ~= '') and (': ' .. items .. '.') or '.'));
    elseif why == 'user' then
        say(string.format('Crafting stopped -- %d of %d done.', n, total));
        if items ~= '' then say('  ' .. items .. '.'); end
    else
        local cause = extra or 'the game did not start a synth (out of materials, inventory full, or Wait too short)';
        warn(string.format('Crafting stopped after %d of %d -- %s.', n, total, cause));
        if items ~= '' then say('  ' .. items .. '.'); end
    end
end

local function finish(why, extra)
    if run == nil then return; end
    report(why, extra);
    run = nil;
end

-- One command, once per tick -- never two in a frame (two same-frame
-- QueueCommands arrive REVERSED in other states; see docs/architecture.md).
local function fire()
    run.fired = run.fired + 1;
    run.stage = 'await';
    run.deadline = M._now() + DETECT_WINDOW;
    pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/lastsynth'); end);
end

-- ---------------------------------------------------------------------------
-- public API
-- ---------------------------------------------------------------------------

-- Begin a batch of n synths (the first fires immediately). Returns false when
-- one is already running or n is out of range -- the bar greys the buttons, so
-- this is the belt to that braces.
function M.start(n)
    n = math.floor(tonumber(n) or 0);
    if run ~= nil or n < 1 or n > MAX_BATCH then return false; end
    run = { total = n, fired = 0, started = 0, retried = false, results = {}, anims = {} };
    inbox = {};
    fire();
    return true;
end

function M.stop()
    if run == nil then return false; end
    finish('user');
    return true;
end

-- nil when idle. The bar draws itself from this and nothing else.
function M.status()
    if run == nil then return nil; end
    local now, nextIn = M._now(), nil;
    if run.stage == 'cool' then nextIn = math.max(0, math.ceil(run.nextAt - now)); end
    return { done = run.started, total = run.total, stage = run.stage,
             nextIn = nextIn, retrying = (run.stage == 'await' and run.retried) };
end

function M.isRunning() return run ~= nil; end
M.MAX_BATCH = MAX_BATCH;

-- ---------------------------------------------------------------------------
-- the tick (main thread). Drains the packet inbox, then advances the machine.
-- ---------------------------------------------------------------------------
local function applyAnim(typ)
    local now = M._now();
    run.started = run.started + 1;
    run.anims[#run.anims + 1] = typ;
    run.retried = false;
    if run.started >= run.total then
        run.stage = 'finish';
        run.graceAt = now + RESULT_GRACE;
    else
        run.stage = 'cool';
        run.nextAt = now + M.getWait();
    end
end

local function applyResult(code, count, id)
    if CANCEL_REASON[code] ~= nil then
        -- A cancel never produced an animation, so `started` is already right.
        finish('cancel', CANCEL_REASON[code]);
        return;
    end
    run.results[#run.results + 1] = { code = code, count = count, id = id };
end

function M.tick()
    -- Drain first: a stashed packet must be seen before any deadline fires, or
    -- a 0x030 that landed at 1.99s loses to the 2.00s detect window.
    if #inbox > 0 then
        local pending = inbox;
        inbox = {};
        if run ~= nil then
            local myIdx = nil;
            pcall(function()
                local p = GetPlayerEntity();
                myIdx = (p ~= nil) and p.TargetIndex or nil;
            end);
            for _, ev in ipairs(pending) do
                if run == nil then break; end
                if ev.k == 'anim' then
                    -- Ours? (Bystanders' synths animate too.) If the player
                    -- entity is unreadable, trust it -- a missed animation
                    -- would abort a healthy batch.
                    if myIdx == nil or ev.idx == myIdx then applyAnim(ev.t); end
                elseif ev.k == 'res' then
                    applyResult(ev.code, ev.count, ev.id);
                elseif ev.k == 'zone' then
                    finish('cancel', 'you zoned');
                end
            end
        end
    end

    if run == nil then return; end
    local now = M._now();
    if run.stage == 'await' then
        if now >= run.deadline then
            if not run.retried then
                run.retried = true;   -- one free shot: frame hitches are transient
                fire();
            else
                finish('nostart');
            end
        end
    elseif run.stage == 'cool' then
        if now >= run.nextAt then
            run.retried = false;
            fire();
        end
    elseif run.stage == 'finish' then
        if #run.results >= run.started or now >= run.graceAt then
            finish('done');
        end
    end
end

-- The packet door. SAFE ON THE NETWORK THREAD: it decodes and stashes, full
-- stop -- no chat, no IO, no clock read, no decision. Everything else happens
-- in M.tick() on the main thread. (Kept a named function rather than an inline
-- handler so the suite can drive the whole machine headless.)
function M.onPacket(id, data)
    if run == nil then return; end              -- idle: cost is one compare
    if id == 0x030 then
        local idx, typ = M.decodeAnim(data);
        if idx ~= nil then inbox[#inbox + 1] = { k = 'anim', idx = idx, t = typ }; end
    elseif id == 0x06F then
        local code, count, iid = M.decodeResult(data);
        if code ~= nil then inbox[#inbox + 1] = { k = 'res', code = code, count = count, id = iid }; end
    elseif id == 0x00A then
        inbox[#inbox + 1] = { k = 'zone' };     -- zone-in voids every assumption
    end
end

-- ---------------------------------------------------------------------------
-- Ashita glue.
-- ---------------------------------------------------------------------------
if ashita ~= nil and ashita.events ~= nil and type(ashita.events.register) == 'function' then
    ashita.events.register('packet_in', 'dlac-synthrun-in', function(e)
        M.onPacket(e.id, e.data);
    end);

    ashita.events.register('d3d_present', 'dlac-synthrun-tick', function()
        if run == nil and #inbox == 0 then return; end
        pcall(M.tick);
    end);

    -- Reload/unload mid-batch: drop it silently. A timer that outlived its
    -- addon would fire /lastsynth into whatever you are doing next.
    ashita.events.register('unload', 'dlac-synthrun-unload', function()
        run = nil; inbox = {};
    end);
end

return M;
