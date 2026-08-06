--[[
    dlac/feature/giftbox.lua -- /dl giftbox: open every reward box in your
    inventory, one at a time, stopping the moment there is not room for what the
    next one pays out.

    FOUR FAMILIES, one run (Henrik, 2026-08-06). It started as the Goblin
    Giftboxes that CatsEyeXI drops off Ventures; the Goblin Gatherbox, the
    Tiny/Timeworn/Titanic Tackleboxes and the Mamool Ja/Lamia/Troll Troves are
    the same job -- a container you use from your bag that pays out several
    items -- so they open through the same loop rather than four copies of it.
    The command keeps its name (`/dl giftbox`, `/dl gb`) because that is what is
    in the README and in muscle memory; `/dl box` and `/dl boxes` answer to it
    too, and every line the run prints says "box" so it is never claiming to
    have opened a giftbox it did not.

    One box yields UP TO 5 ITEMS, so the space gate is the whole feature: open
    one with a nearly full bag and the payout is refused item by item, which is
    how you lose a box's contents to a wall of "you cannot carry any more"
    lines. That "up to 5" is measured on the giftboxes; the gate applies the
    same number to all four families, which for a smaller payout is merely
    strict and for a larger one would be the bug -- if a Titanic Tacklebox ever
    turns out to pay more than five, NEED_FREE is where that is fixed.

    THE GATE RUNS BEFORE EVERY BOX, NOT ONCE (Henrik's spec said "more than 5
    free"; the correction is that it has to be re-asked each time). A box gives
    up to 5 and frees at most 1 slot -- its own -- so a run of ten is a net -4
    per box in the worst case. Checking once at the start and then looping is
    exactly how you end up half way through a stack with an unknown number of
    boxes unopened and no idea which.

    HOW IT PACES ITSELF -- the part worth reading before changing anything.
    We do NOT guess a delay between uses. Nobody has measured what these boxes
    do (recast? animation only? server-side queue?), and this project has been
    burned by exactly that guess before: the synth repeat is ~22s real against
    the server's ~17s because the client is frame-tied, and the ammo/recast unit
    was a borrowed /4 that made every countdown 15x too big. So instead of a
    number, the loop uses PROOF: fire the use, then watch the item's own count
    in your bag. When the count drops, that use landed and the next may fire.
    If it never drops, we stop and SAY so rather than firing again into whatever
    refused the first one.

    That has three payoffs beyond correctness: it self-corrects on a slow
    server, it works whether or not the boxes stack (we count QUANTITY, never
    slots), and the failure mode is one honest line instead of a command-spam
    loop that reads as botting to anyone watching.

    Pure helpers (M.plan, M.pickNext, M.classify) are headless-testable; the
    Ashita glue is guarded at the bottom, the chocowatch/useitem precedent --
    its own blocked command registration, never the dispatch whitelist.
]]--

local M = {};

local _cfok, _cfmt = pcall(require, 'dlac\\chatfmt');
_cfok = _cfok and type(_cfmt) == 'table';
local function say(s)  if _cfok and _cfmt.msg  then _cfmt.msg(s);  else print('[dlac] ' .. s); end end
local function warn(s) if _cfok and _cfmt.warn then _cfmt.warn(s); else print('[dlac] ' .. s); end end

-- Usable items fire from INVENTORY only -- a box in a satchel or locker cannot
-- be opened where it sits, and saying so is more use than silently ignoring it.
M.BAG = 0;

-- Free slots we insist on before opening one more. Henrik's rule, and it is the
-- payout size: "up to 5 items from it". Not a setting -- a smaller number is
-- just a slower way of losing a box.
M.NEED_FREE = 6;   -- strictly MORE than 5

-- How long one use may take to show up as a count drop before we call it
-- refused. Generous on purpose: a long animation is not a failure, and the cost
-- of waiting is seconds while the cost of firing again is a duplicate use.
M.CONFIRM_TIMEOUT = 15.0;
-- The beat after a CONFIRMED open, before the next fire. 0.6 shipped, raised to
-- 1.6 after Henrik's first field run ("I suspect lag may create issues"), cut to
-- 1.2 the same day, and to 1.0 on 2026-08-06 -- his call again, after a live
-- trove run: "think we can also tweak the use timer down 0.2 seconds". Each of
-- those was a FIELD number, which is the only kind this constant should ever
-- take; nobody has measured what a box actually costs the client.
--
-- Worth being clear about what this does and does not protect: the count-drop
-- confirm already proves the previous use landed, so this is not the pacing --
-- it is headroom for the client to finish settling after a payout of up to 5
-- items lands in the bag. On a laggy client the confirm can arrive on the same
-- frame the inventory is still being written, and the next use would then read
-- a half-updated bag for its space gate.
--
-- Any decimal is honoured to the FRAME: tickSettle is called from d3d_present
-- every frame and compares os.clock() against settleAt, so it is not rounded to
-- POLL (0.25) or to anything else -- 1.0 means 1.0, +/- one frame.
M.SETTLE          = 1.0;
M.POLL            = 0.25;

-- How stale the tray's cached bag snapshot may get. The tray's gate contract
-- says trayWants must be CHEAP -- flags only, no bag scans -- and detecting
-- boxes is unavoidably a bag scan, so the scan is throttled to this and the
-- gate reads the cache. A ~80 slot walk every 2s is not the per-frame cost the
-- contract was written to forbid.
M.SCAN_EVERY = 2.0;

-- The ladder, smallest first, so a run is deterministic and a space-limited run
-- always stops at a predictable place. Matching is by SUBSTRING on the resource
-- name (case-insensitive), not this list: the list only orders what we found.
-- A name we do not know still opens -- it just sorts last -- which is the
-- difference between this working on the next box CatsEyeXI adds and not.
--
-- ORDER ACROSS FAMILIES: the giftboxes stay at the TOP, where they have always
-- been, for one reason worth stating -- the tray draws the highest rung you are
-- carrying (see M.peek), and the grand giftbox is the art that was field-checked
-- as the icon. Keeping it the top rung means nothing anyone has already seen
-- changes; the other families slot in below it and simply open first. Within
-- the giftboxes the intended order is unchanged (sm, md, lg, gr) -- it is just
-- that from 08-05 until now it was never actually reached; see the note on the
-- names below.
--
-- ORDER WITHIN A FAMILY is a reading of the names where the names say a size
-- (the tackleboxes, the giftboxes) and the item id where they say nothing at
-- all (the troves -- Mamool Ja / Lamia / Troll is 6554 / 6555 / 6556 and
-- nothing more principled than that). Nobody has priced any of these payouts.
-- All it decides is which opens first, so a wrong guess costs a run's ordering
-- and nothing else.
--
-- THE NAMES ARE THE SERVER'S, read off the live item API on 2026-08-06 rather
-- than typed from memory -- which is how the four giftbox rungs turned out to
-- have never matched anything. They are `Gob. Giftbox (sm/md/lg/gr)`, not the
-- `Goblin Giftbox (Small)` / `Grand Giftbox` that shipped here from 08-05; the
-- substring still caught them, so the feature worked while quietly ranking all
-- four as unknown-sorts-last, which alphabetically opened the GRAND first and
-- the small last -- the exact reverse of the rule this list exists to state.
--
-- BOTH SPELLINGS ARE LISTED. dlac reads the CLIENT's name for an item and the
-- API serves the SERVER's, and this project has been bitten three times by the
-- two disagreeing (HELM's `Excavation Point` against the client's `Excav.
-- Point`). The abbreviations here are the ~20-char DAT-name style, so the
-- client almost certainly says the same thing -- but "almost certainly" is
-- worth four dead array entries, and only one of each pair can ever match.
--
-- `halvung trove` is the FOURTH instance, reported live: Henrik opened one on
-- 2026-08-06 and called it "the halvung trove", and no such item exists in the
-- server table -- 6556 is `Troll Trove` there. Trolls come from Halvung, and
-- the neighbouring Hoard family (3063-3065) is named for the REGIONS -- Mamook,
-- Halvung, Arrapago -- so the client naming a trove for the region is exactly
-- the shape you would expect. Only that one is listed: the matching `mamook` /
-- `arrapago` spellings for 6554/6555 are a guess off a pattern, and a guess is
-- not what this list is for. They go in when someone reads them in game.
--
-- WHY AN ALIAS MATTERS EVEN WHERE THE ORDER DOES NOT. Trove order is admittedly
-- arbitrary, so who cares which opens first -- but an unrecognised box gets
-- #LADDER + 1, which is ABOVE the giftboxes, and the tray draws the highest
-- rung you hold. A trove the ladder does not know would therefore take the
-- icon off the grand giftbox and open after it, quietly undoing the one
-- arrangement Session I field-checked. That is the cost of a missing alias
-- here, and it is why they are worth adding on nothing more than a report.
--
-- Ids, for provenance only -- the logic is name-based on purpose, so a box
-- CatsEyeXI adds tomorrow opens without an addon update:
--   tackleboxes 5110 / 5946 / 5112 · gatherbox 6345
--   troves 6554 / 6555 / 6556      · giftboxes 5109 / 5111 / 6264 / 6558
M.LADDER = { 'tiny tacklebox', 'timeworn tacklebox', 'titanic tacklebox',
             'goblin gatherbox',
             'mamool ja trove', 'lamia trove', 'troll trove', 'halvung trove',
             'gob. giftbox (sm)', 'goblin giftbox (small)',
             'gob. giftbox (md)', 'goblin giftbox (medium)',
             'gob. giftbox (lg)', 'goblin giftbox (large)',
             'gob. giftbox (gr)', 'grand giftbox' };

-- What makes an item ours. Substrings, so an unheard-of rung in any of the
-- four families still opens. The cost of being this open-ended is bounded: a
-- non-usable item that happened to be named "...Tacklebox" would be fired at
-- once, never confirm, and stop the run with one honest line after the timeout
-- -- not a loop, and nothing lost.
--
-- All four were checked against the live item table on 2026-08-06 and each one
-- catches its family and NOTHING else: giftbox 4, tacklebox 3, gatherbox 1,
-- trove 3 -- fifteen items, no strays. `trove` was the one worth checking; it
-- is the shortest and the least box-like word here.
M.MATCH  = { 'giftbox', 'gatherbox', 'tacklebox', 'trove' };

-- Is this item name one of ours, and where does it sort? nil = not a box.
function M.classify(name)
    if type(name) ~= 'string' then return nil; end
    local low, ours = string.lower(name), false;
    for _, frag in ipairs(M.MATCH) do
        if string.find(low, frag, 1, true) ~= nil then ours = true; break; end
    end
    if not ours then return nil; end
    for i, known in ipairs(M.LADDER) do
        if low == known then return i; end
    end
    return #M.LADDER + 1;    -- an unknown box: still ours, sorts last
end

-- Which box to open next: lowest rank first, ties by name so the order is
-- stable across scans (a bag walk is not).
function M.pickNext(found)
    if type(found) ~= 'table' then return nil; end
    local best = nil;
    for _, e in ipairs(found) do
        if type(e) == 'table' and (tonumber(e.count) or 0) > 0 then
            if best == nil or e.rank < best.rank
               or (e.rank == best.rank and tostring(e.name) < tostring(best.name)) then
                best = e;
            end
        end
    end
    return best;
end

-- The whole decision, pure (tests GB*): given what is in the bag and how much
-- room there is, do we open something -- and if not, WHY not. Never returns a
-- bare false: a run that does nothing has to be able to say which of the three
-- reasons it was, because they call for three different actions from the player.
function M.plan(found, freeSlots)
    local free  = math.max(0, math.floor(tonumber(freeSlots) or 0));
    local total = 0;
    for _, e in ipairs(found or {}) do total = total + math.max(0, tonumber(e.count) or 0); end
    if total <= 0 then
        return nil, 'none', 'no boxes in your inventory.';
    end
    if free < M.NEED_FREE then
        return nil, 'space', string.format(
            '%d box%s waiting -- you need %d free inventory slots and have %d.',
            total, (total == 1) and '' or 'es', M.NEED_FREE, free);
    end
    return M.pickNext(found), 'go', nil;
end

-- ---------------------------------------------------------------------------
-- Live reads (guarded: headless every one of these is simply absent)
-- ---------------------------------------------------------------------------

-- Every box in Inventory, plus the free-slot count, in ONE walk -- the two
-- numbers must come from the same instant or the gate is deciding on a bag that
-- no longer exists.
function M.scan()
    local found, free, ok = {}, 0, false;
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        local res = AshitaCore:GetResourceManager();
        local max = inv:GetContainerCountMax(M.BAG) or 0;
        if max <= 0 then return; end
        local byName = {};
        for i = 1, max do
            local item = inv:GetContainerItem(M.BAG, i);
            local id   = (item ~= nil) and tonumber(item.Id) or nil;
            local cnt  = (item ~= nil) and (tonumber(item.Count) or 0) or 0;
            if id == nil or id == 0 or cnt <= 0 then
                free = free + 1;                      -- an empty slot
            else
                local r  = res:GetItemById(id);
                local nm = (r ~= nil and r.Name ~= nil) and r.Name[1] or nil;
                local rank = M.classify(nm);
                if rank ~= nil then
                    local e = byName[nm];
                    if e == nil then
                        e = { name = nm, id = id, rank = rank, count = 0 };
                        byName[nm] = e; found[#found + 1] = e;
                    end
                    e.count = e.count + cnt;          -- stacked or scattered: quantity
                end
            end
        end
        ok = true;
    end);
    if not ok then return nil, 0; end
    return found, free;
end

-- How many of one name are in the bag right now. The confirm signal: this
-- dropping is the ONLY evidence a use actually landed.
function M.countOf(name)
    local found = M.scan();
    for _, e in ipairs(found or {}) do
        if e.name == name then return e.count; end
    end
    return 0;
end

-- The throttled snapshot the floating tray reads: whether you have any boxes,
-- how many, how much room, and WHICH box to show. Cached because the tray asks
-- every frame (M.SCAN_EVERY).
--
-- `top` is the HIGHEST rung you are carrying, and that is what the tray draws:
-- a grand giftbox is the one worth noticing, and it is the most distinctive art
-- on the ladder -- which is why the giftboxes were left at the top of it when
-- the gatherbox, the tackleboxes and the troves were added. Falling back to the
-- best box you actually hold also means the icon is never for something you do
-- not have.
local _peekAt, _peek = 0, { have = false, total = 0, free = 0, top = nil };

function M.peek(now)
    now = tonumber(now) or os.clock();
    if now < _peekAt then return _peek; end
    _peekAt = now + M.SCAN_EVERY;
    local found, free = M.scan();
    local total, top = 0, nil;
    for _, e in ipairs(found or {}) do
        total = total + math.max(0, tonumber(e.count) or 0);
        if (tonumber(e.count) or 0) > 0 and (top == nil or e.rank > top.rank) then top = e; end
    end
    _peek = { have = (total > 0), total = total, free = free or 0, top = top };
    return _peek;
end

M._peekReset = function() _peekAt = 0; end   -- test seam

-- ---------------------------------------------------------------------------
-- The run
-- ---------------------------------------------------------------------------

local run = nil;   -- nil = idle. { name, was, firedAt, opened, stage, nextPoll }

function M.running() return run ~= nil; end

local function finish(msg, bad)
    run = nil;
    if msg ~= nil then if bad then warn(msg); else say(msg); end end
end

local function report(opened, tail)
    local head = (opened > 0)
        and string.format('opened %d box%s', opened, (opened == 1) and '' or 'es')
        or 'opened nothing';
    return head .. ((tail ~= nil) and (' -- ' .. tail) or '.');
end

local function fireNext()
    local found, free = M.scan();
    if found == nil then
        finish(report(run.opened, 'cannot read your inventory.'), true); return;
    end
    local pick, code, why = M.plan(found, free);
    if pick == nil then
        -- 'none' after a productive run is success, not a warning: it means we
        -- opened everything there was.
        if code == 'none' and run.opened > 0 then finish(report(run.opened), false);
        else finish(report(run.opened, why), code == 'space'); end
        return;
    end
    run.name    = pick.name;
    run.was     = pick.count;
    run.firedAt = os.clock();
    run.stage   = 'confirm';
    run.nextPoll = os.clock() + M.POLL;
    pcall(function()
        AshitaCore:GetChatManager():QueueCommand(1, '/item "' .. pick.name .. '" <me>');
    end);
end

function M.start()
    if run ~= nil then say('already opening boxes -- /dl giftbox stop to halt.'); return; end
    local found, free = M.scan();
    if found == nil then warn('cannot read your inventory.'); return; end
    local pick, code, why = M.plan(found, free);
    if pick == nil then (code == 'space' and warn or say)(why); return; end
    local total = 0;
    for _, e in ipairs(found) do total = total + e.count; end
    say(string.format('opening %d box%s (%d free slots) -- /dl giftbox stop to halt.',
        total, (total == 1) and '' or 'es', free));
    run = { opened = 0 };
    fireNext();
end

function M.stop()
    if run == nil then say('not opening anything.'); return; end
    finish(report(run.opened, 'stopped.'), false);
end

-- One tick of the confirm wait. Split out so the tests can drive it without a
-- d3d_present event: they inject clock + countOf and assert the transitions.
function M.tick(now)
    if run == nil or run.stage ~= 'confirm' then return; end
    if now < (run.nextPoll or 0) then return; end
    run.nextPoll = now + M.POLL;
    local left = M.countOf(run.name);
    if left < run.was then
        run.opened = run.opened + 1;
        run.stage  = 'settle';
        run.settleAt = now + M.SETTLE;
        return;
    end
    if now - run.firedAt >= M.CONFIRM_TIMEOUT then
        -- Deliberately NOT a retry. Whatever refused that use will refuse the
        -- next one too, and a loop that keeps firing at a wall is both useless
        -- and the thing that looks like botting.
        finish(report(run.opened,
            string.format('%s did not open (no change after %ds) -- stopping.',
                run.name, math.floor(M.CONFIRM_TIMEOUT))), true);
    end
end

function M.tickSettle(now)
    if run == nil or run.stage ~= 'settle' then return; end
    if now >= (run.settleAt or 0) then fireNext(); end
end

M._runState = function() return run; end          -- test seam
M._setRun   = function(r) run = r; end            -- test seam

-- ---------------------------------------------------------------------------
-- Ashita glue
-- ---------------------------------------------------------------------------
if ashita ~= nil and ashita.events ~= nil and type(ashita.events.register) == 'function' then
    ashita.events.register('command', 'dlac-giftbox-cmd', function(e)
        pcall(function()
            local raw = string.lower(e.command or '');
            local a, b = raw:match('^/dl%s+(%S+)%s*(%S*)');
            if a == nil then a, b = raw:match('^/dlac%s+(%S+)%s*(%S*)'); end
            -- `box`/`boxes` since 2026-08-06, when the run stopped being only
            -- about giftboxes. `giftbox`/`gb` are what the docs and everyone's
            -- fingers know, so they are not going anywhere.
            if a ~= 'giftbox' and a ~= 'gb' and a ~= 'box' and a ~= 'boxes' then return; end
            e.blocked = true;
            if b == 'stop' then M.stop(); return; end
            if b == 'status' then
                local found, free = M.scan();
                if found == nil then warn('cannot read your inventory.'); return; end
                local total = 0;
                for _, x in ipairs(found) do total = total + x.count; end
                say(string.format('%d box%s in inventory, %d free slots%s.',
                    total, (total == 1) and '' or 'es', free,
                    (run ~= nil) and '  (opening now)' or ''));
                return;
            end
            M.start();
        end);
    end);

    ashita.events.register('d3d_present', 'dlac-giftbox-tick', function()
        if run == nil then return; end
        local now = os.clock();
        pcall(function() M.tick(now); M.tickSettle(now); end);
    end);
end

return M;
