--[[
    claim-example -- a COMPLETE, RUNNABLE example of a third-party Ashita addon
    claiming gear slots through dlac. 2026-08-01, protocol v1.

    READ `README.md` NEXT TO THIS FILE FIRST if you are here to learn the
    integration; it explains the model. This file is the worked implementation,
    commented for the same audience.

    WHY THIS EXISTS IN TWO SENTENCES. dlac decides and equips your gear itself,
    and every Ashita addon runs in its own Lua state -- so an addon that wants a
    piece of gear on cannot just equip it (dlac would take it straight back off,
    and the two would fight every frame). Instead it FILES A CLAIM, and dlac's
    Arbiter settles that claim against everything else contending for the slot,
    by a priority order the player controls.

    WHAT THIS ADDON IS. A separate addon, in its own folder, in its own Lua
    state, with no dlac module and no shared memory -- which is the whole point:
    if this works, yours does. It talks to dlac ONLY through the published client
    shim (`addons\dlac\lib\dlacclaim.lua`), so it is also the shim's worked
    example.

    RUN IT
        1. copy this folder to  <Ashita>\addons\claim-example\
        2. /addon load claim-example
        3. /dl claims on              <- the player's switch; nothing works without it
        4. /claimex hello             <- is dlac there, is the switch on
        5. /claimex claim head Walahra Turban
        6. /dl why                    <- see the "Other addons" row win (or lose) the slot
        7. /claimex release

    FOUR THINGS WORTH TRYING, in order -- they are the four behaviours an
    integration has to survive, and each one is a command here:

      1. A CLAIM LANDS.       claim a slot; it goes on, and `/dl why` names
                              "Other addons" as the winner.
      2. RANK IS OBEYED.      pin or lock the same slot and re-claim: your claim
                              LOSES, you are told who beat you, and the gear does
                              not move. Then drag "Other addons" above that row
                              in Gear Helpers > Claim Priority -- now it wins.
                              You do not control this. The player does.
      3. THE LEASE WORKS.     `/claimex die` stops the heartbeat WITHOUT
                              releasing -- exactly what a crash looks like from
                              dlac's side. Within `ttl` seconds dlac drops the
                              claim on its own and the player's gear comes back.
                              This is why claims are leased.
      4. TWO ADDONS CONTEND.  `/claimex who b`, claim the same slot, raise
                              `prio` -- B takes it from A, and A is TOLD. Two
                              external addons share one rank row; between
                              themselves `prio` decides (ties by id, ascending).

    THE ONE LAW TO CARRY INTO YOUR OWN ADDON. At every point where something
    takes a slot, ask: **how would the losing addon find out?** Three bugs were
    found in this channel's first field round and all three were the same
    failure -- the addon believing it held a slot it did not. None of them was
    visible by checking whether the gear was right; the gear was right every
    time. Handle `onVerdict` and `onExpired`, and never assume silence means you
    still hold something.
]]--

addon.name    = 'claim-example';
addon.author  = 'dlac';
addon.version = '1.0';
addon.desc    = 'Worked example: claiming gear slots through dlac (integration-guide section 7).';

require('common');

local function chat(msg) print('[claim-example] ' .. msg); end

-- ---------------------------------------------------------------------------
-- STEP 1 -- load dlac's published client shim.
--
-- It ships with dlac and owns the wire format, the byte-table send, your reply
-- channel and the lease renewal. Do not hand-roll the protocol: the shim is the
-- supported door, and if the wire changes it absorbs the change.
--
-- Failing to load it means dlac is not installed. Say so ONCE and stay inert --
-- an addon that throws on every command because an optional integration is
-- missing is worse than one that quietly does nothing.
-- ---------------------------------------------------------------------------
local shim = nil;
do
    local path = AshitaCore:GetInstallPath() .. 'addons\\dlac\\lib\\dlacclaim.lua';
    local chunk = loadfile(path);
    if chunk == nil then
        chat('could not load dlac\'s client shim at ' .. path .. ' -- is dlac installed?');
    else
        local ok, m = pcall(chunk);
        if ok and type(m) == 'table' then shim = m; else chat('shim failed to load: ' .. tostring(m)); end
    end
end

-- ---------------------------------------------------------------------------
-- STEP 2 -- create a client.
--
-- TWO identities here, which a real addon would not have: it lets one addon
-- demonstrate external-vs-external contention (check 4 above). Yours needs one.
--
--   id     REQUIRED, and it is both your identity and your lease key. Use
--          something unmistakably yours; two addons sharing an id would
--          overwrite each other's claims.
--   label  what the PLAYER reads in `/dl claims list` and in dlac's Claim
--          Priority row. Write it for them, not for you.
--   ttl    lease seconds (dlac clamps to 1..300 and tells you if it clamped).
--          Shorter = your gear is released faster if you crash; longer = fewer
--          heartbeats. 10 is a sane default.
--   prio   settles ties against OTHER EXTERNAL ADDONS only. It has no bearing
--          on dlac's own claimants -- that is the player's rank order, and it
--          is theirs to set, not yours to outrank.
-- ---------------------------------------------------------------------------
local ids = { 'a', 'b' };
local cl, staged, beating = {}, {}, {};
local active = 'a';

local function slotLabel(t)
    local ks = {};
    for k, v in pairs(t or {}) do ks[#ks + 1] = k .. '=' .. tostring(v); end
    table.sort(ks);
    return (#ks > 0) and table.concat(ks, ', ') or '(nothing)';
end

if shim ~= nil then
    for _, k in ipairs(ids) do
        staged[k] = {};
        beating[k] = true;
        local c = shim.new({
            id    = 'claim-example-' .. k,
            label = 'Claim example ' .. string.upper(k),
            ttl   = 10,
            prio  = 0,
        });

        -- ---------------------------------------------------------------
        -- STEP 3 -- handle what dlac tells you. THIS IS THE PART PEOPLE SKIP,
        -- and it is where every bug in this channel has lived.
        -- ---------------------------------------------------------------

        -- onAck: every reply to something you SENT. A real addon would handle
        -- only what it cares about; here the whole conversation is the output,
        -- because seeing it is the point of an example.
        c.onAck = function(t)
            local bits = { tostring(t.what or '?'), t.ok and 'ok' or 'REFUSED' };
            if t.err then bits[#bits + 1] = t.err; end
            if type(t.data) == 'table' then
                if t.data.on ~= nil then bits[#bits + 1] = 'claims=' .. tostring(t.data.on); end
                if t.data.dlac then bits[#bits + 1] = 'dlac ' .. tostring(t.data.dlac); end
                if t.data.ttlClamped then bits[#bits + 1] = 'ttl CLAMPED to ' .. tostring(t.data.ttl); end
                if t.data.expiresIn then bits[#bits + 1] = tostring(t.data.expiresIn) .. 's lease'; end
                if type(t.data.holders) == 'table' then
                    for _, h in ipairs(t.data.holders) do
                        bits[#bits + 1] = string.format('[%s prio %s: %d slot(s)]',
                            tostring(h.id), tostring(h.prio), tonumber(h.slots) or 0);
                    end
                end
            end
            chat(string.format('%s <- %s', string.upper(k), table.concat(bits, ' | ')));
        end

        -- onVerdict: SOMETHING ELSE HAS A SLOT YOU CLAIMED. An accepted claim is
        -- not a worn item -- dlac accepted your opinion, then the Arbiter
        -- settled the slot, and you may have lost it. This is the only way to
        -- learn that; the alternative is diffing the worn stream against your
        -- own claim and guessing.
        --
        -- The two kinds of loss want OPPOSITE responses, and printing the wrong
        -- advice sends the player to the wrong screen:
        --   * lost to a DLAC CLAIMANT (Pins, MaxMP, Locks, ...) -- settled by
        --     the player's Claim Priority drag. Not yours to fix.
        --   * lost to ANOTHER ADDON -- settled by `prio`, and it never appears
        --     in that list at all.
        -- `d.held == true` is the all-clear: you hold everything again.
        c.onVerdict = function(d)
            if d.held then
                chat(string.format('%s <- VERDICT: all clear, nothing is beating me now', string.upper(k)));
                return;
            end
            local ks, toPeer = {}, false;
            for slot, who in pairs(d.lost or {}) do
                ks[#ks + 1] = slot .. ' -> ' .. tostring(who);
                if tostring(who):sub(1, 14) == 'claim-example-' then toPeer = true; end
            end
            table.sort(ks);
            chat(string.format('%s <- VERDICT: LOST %s (%s)', string.upper(k), table.concat(ks, ', '),
                toPeer and 'another ADDON outranks me -- /claimex prio <higher> to take it'
                       or  'a dlac claimant outranks me -- the player drags "Other addons" up in Claim Priority'));
        end

        -- onExpired: YOUR CLAIM IS GONE. Three causes, and `data.on` (the
        -- player's switch state) tells you which world you are in without
        -- parsing the reason string:
        --   'lease lapsed'  -- you stopped heartbeating. Your bug.
        --   'logout'        -- claims are session state; the PERMISSION is
        --                      saved, so `on` is still true and you may claim
        --                      again when your own conditions are met.
        --   player turned it off -- `on` is false. Do NOT re-file. Re-claiming
        --                      through a switch someone just turned off is the
        --                      behaviour that gets an addon uninstalled.
        c.onExpired = function(d)
            chat(string.format('%s <- EXPIRED: %s (claims switch is now %s)',
                string.upper(k), tostring(d.reason or '?'), tostring(d.on)));
        end
        cl[k] = c;
    end
end

local function C() return cl[active]; end

-- ---------------------------------------------------------------------------
-- STEP 4 -- pump every frame. THIS IS NOT OPTIONAL.
--
-- `pump()` renews the lease while you hold a claim and does nothing at all
-- otherwise -- no traffic, no allocation when idle. Stop pumping and dlac drops
-- your claim within `ttl` seconds, which is exactly what should happen if your
-- addon has died. `/claimex die` below stops it deliberately so you can watch.
-- ---------------------------------------------------------------------------
ashita.events.register('d3d_present', 'claim_example_pump', function()
    for _, k in ipairs(ids) do
        if beating[k] and cl[k] ~= nil then pcall(function() cl[k]:pump(); end); end
    end
end);

local USAGE = {
    '/claimex hello                     -- is dlac there, is the switch on',
    '/claimex claim <slot> <item name>  -- add a slot and file the claim',
    '/claimex empty <slot>              -- claim the slot EMPTY ("remove")',
    '/claimex drop <slot>               -- take a slot out and re-file',
    '/claimex release                   -- give everything back',
    '/claimex status                    -- what dlac holds, for every addon',
    '/claimex who a|b                   -- switch identity (two contenders)',
    '/claimex prio <n>                  -- this identity\'s priority vs other ADDONS',
    '/claimex ttl <n>                   -- lease seconds (dlac clamps 1..300)',
    '/claimex die | live                -- stop/resume the heartbeat (lease demo)',
    '/claimex bad                       -- send a bogus slot, see the named refusal',
};

-- A claim REPLACES your previous one: one claimant, one table. So the example
-- keeps the whole staged table and re-sends all of it on every change, which is
-- also what your addon should do.
local function refile()
    local c = C();
    if c == nil then return; end
    if next(staged[active]) == nil then
        c:release();
        chat(string.format('%s -> release (staged claim is empty)', string.upper(active)));
        return;
    end
    c:claim(staged[active]);
    chat(string.format('%s -> claim %s', string.upper(active), slotLabel(staged[active])));
end

local function handle(args)
    if shim == nil then chat('inert -- dlac\'s shim did not load.'); return; end
    local sub = (args[2] or ''):lower();
    local c = C();

    if sub == '' or sub == 'help' then
        chat(string.format('identity %s (%s), heartbeat %s, staged: %s',
            string.upper(active), c.id, beating[active] and 'on' or 'STOPPED', slotLabel(staged[active])));
        chat(string.format('dlac present: %s, claims switch: %s, holding: %s',
            tostring(c.present), tostring(c.enabled), tostring(c.held)));
        for _, line in ipairs(USAGE) do chat(line); end
        return;
    end

    if sub == 'hello' then c:hello(); chat(string.upper(active) .. ' -> hello'); return; end
    if sub == 'status' then c:status(); chat(string.upper(active) .. ' -> status'); return; end
    if sub == 'release' then
        staged[active] = {};
        c:release();
        chat(string.upper(active) .. ' -> release');
        return;
    end

    if sub == 'who' then
        local w = (args[3] or ''):lower();
        if w ~= 'a' and w ~= 'b' then chat('who a|b'); return; end
        active = w;
        chat('active identity is now ' .. string.upper(active) .. ' (' .. cl[w].id .. ')');
        return;
    end

    if sub == 'prio' then
        local n = tonumber(args[3]);
        if n == nil then chat('prio <number>'); return; end
        c.prio = n;
        chat(string.format('%s prio = %d (higher beats other ADDONS; dlac\'s own claimants are the player\'s rank order)',
            string.upper(active), n));
        if next(staged[active]) ~= nil then refile(); end
        return;
    end

    if sub == 'ttl' then
        local n = tonumber(args[3]);
        if n == nil then chat('ttl <seconds>'); return; end
        c.ttl = n;
        chat(string.format('%s ttl = %s', string.upper(active), tostring(n)));
        if next(staged[active]) ~= nil then refile(); end
        return;
    end

    if sub == 'die' then
        beating[active] = false;
        chat(string.format('%s heartbeat STOPPED (claim NOT released -- this is what a crash looks like; dlac should drop it within ~%ss and the gear should come back)',
            string.upper(active), tostring(c.ttl)));
        return;
    end
    if sub == 'live' then
        beating[active] = true;
        chat(string.upper(active) .. ' heartbeat resumed (re-claim if the lease already lapsed)');
        return;
    end

    if sub == 'claim' then
        local slot = args[3];
        if slot == nil then chat('claim <slot> <item name>'); return; end
        local parts = {};
        for i = 4, #args do parts[#parts + 1] = args[i]; end
        local item = table.concat(parts, ' ');
        if item == '' then chat('claim <slot> <item name>'); return; end
        staged[active][slot] = item;
        refile();
        return;
    end

    if sub == 'empty' then
        local slot = args[3];
        if slot == nil then chat('empty <slot>'); return; end
        -- 'remove' is dlac's own empty-the-slot convention: you can claim a slot
        -- HELD EMPTY, not just claim an item into it.
        staged[active][slot] = 'remove';
        refile();
        return;
    end

    if sub == 'drop' then
        local slot = args[3];
        if slot == nil then chat('drop <slot>'); return; end
        for kk in pairs(staged[active]) do                     -- the player typed it; be forgiving
            if kk:lower() == slot:lower() then staged[active][kk] = nil; end
        end
        refile();
        return;
    end

    if sub == 'bad' then
        -- A deliberately invalid claim. dlac must answer with a NAMED refusal,
        -- not silence -- silence would be indistinguishable from dlac being
        -- broken, and that ambiguity is what this command exists to disprove.
        c:claim({ Elbow = 'Walahra Turban' });
        chat(string.upper(active) .. ' -> claim { Elbow = ... } (expect a named refusal)');
        return;
    end

    chat('unknown -- /claimex for usage');
end

ashita.events.register('command', 'claim_example_cmd', function(e)
    local args = e.command:args();
    if #args == 0 then return; end
    local cmd = args[1]:lower();
    if cmd ~= '/claimex' and cmd ~= '/claimexample' then return; end
    e.blocked = true;
    handle(args);
end);

-- Be a good citizen on the way out: hand the slots back. The lease would cover
-- it anyway, but making the player wait ten seconds for their gear because you
-- could not be bothered is not a good look.
ashita.events.register('unload', 'claim_example_unload', function()
    for _, k in ipairs(ids) do
        if cl[k] ~= nil then pcall(function() cl[k]:release(); end); end
    end
end);

chat('loaded. /dl claims on, then /claimex for usage.');
