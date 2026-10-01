--[[
    ascensionxi/gearvault/reconcile.lua -- the ADDITIONS PUSH (GV3, slice 3).

    STATELESS BY DESIGN: instead of a durable queue of pending edits, the
    engine recomputes the derived layout for the ACTIVE main job and pushes
    whatever is missing from the server's layout. That one shape covers every
    trigger at once -- a set commit (the derivation hash moves), login, the
    city gate, and a dlac restart mid-queue (nothing was queued; the next run
    re-derives).

    EVENT-DRIVEN since 2026-09-30 (Henrik: "the 8 second sync is
    confusing"). The engine used to wake on a fixed 8 s beat, which the tab
    painted as a countdown and which put up to 8 s -- often 16 s -- between a
    deposit and the add. Now every input that can change the answer KICKS it
    (a vault or layout commit, a set commit, a zone or job change, a
    capacity change, a settings or Bench change) and it runs a moment later;
    a quiet local re-derive every BEAT seconds catches what has no event (a
    trigger file saved elsewhere). The wire is touched only when the diff is
    non-empty. And the engine never pushes where the server would refuse:
    live edits to the active job need a CITY (the zone type's CITY bit, or
    the Mog House), so out in the field the adds wait -- visibly -- for one.

    The 2026-09-18 unused-gear rule also releases unpinned instance rows
    proven unused by the current job's sets and triggers. Worn, outside,
    and review rows are retained; incomplete derivations cannot remove gear.
    Additions remain only FROM THE VAULT, the 2026-08-30
    law: a set-wanted piece the vault holds no copy of (it is in your bags,
    or not owned at all) is never pushed into a layout -- storing it with a
    Void Warden is what makes it eligible. Derived entries carry the ZERO blob
    (augment-pinned records are skipped by derivation -- the vault pane's
    "+ Layout" carries real blobs); only zero-blob layout entries are
    compared against on legacy servers. Augmented references protect their
    item IDs during instance-mode cleanup even though auto-add skips them.
    A set entry that names no augment takes plain vault copies first, then
    augmented ones when no choice is involved (2026-10-01, see
    augmentedPick); differently rolled copies competing for fewer places
    stay the player's pick and are named by R.chooseCopy().

    The engine never derives WHILE BROWSING another job (the sets root
    answers for the browsed job there -- pushing WHM's gear into WAR's
    layout is exactly the bug that guard exists for).

    Everything arrives injected (R.configure) so the suite drives the whole
    engine against the vaultclient test harness with no files and no gearui.
]]--

local R = {};
local counts = require('dlac\\servers\\ascensionxi\\modules\\gearvault\\layoutcounts');

R.BEAT        = 3.0;  -- quiet local re-derive (no wire unless something is missing)
R.KICK_SETTLE = 0.2;  -- a burst of kicks runs the engine once, this soon after the first
R.RETRY       = 10.0; -- the same refused/unfinished adds are tried again after this
R.MAX_PUSH    = 200;  -- adds per run -- a runaway derivation must not flood

local D = nil;        -- { vc, derive, setsRoot(), triggers(), resolve(name),
                      --   mainJob(), browsing(), say(msg), clock(), inCity() }
function R.configure(deps) D = deps; end

local st = {
    lastBeat    = 0,
    kickAt      = nil,   -- a kick asked for a run at this time
    lastPushKey = nil,   -- derivation hash + the exact adds last sent (no re-spam)
    retryAt     = nil,   -- ...which may be sent again from this time
    pendingCity = false, -- adds waiting for a city (refused, or held in the field)
    inFlight    = 0,     -- acks not yet counted this run
    runOk       = 0,
    runCity     = 0,
    runFail     = 0,
    lastDerived = nil,   -- the latest derivation (the tab's [wanted] tags)
    pressure    = nil,   -- { over, mode, candidates, pinned } | nil (see tick)
    seedStamp   = nil,   -- layout stamp already seeded into usage
    evictStamp  = nil,   -- layout stamp auto-eviction already ran for
};

local function clock()
    return (D ~= nil and type(D.clock) == 'function') and D.clock() or os.clock();
end

-- Something the answer depends on changed: run soon. Kicks coalesce -- a
-- burst (a deposit's mirror + layout commits) runs the engine once.
function R.kick(reason)
    if st.kickAt == nil then st.kickAt = clock() + R.KICK_SETTLE; end
    st.kickWhy = reason;
end

-- Is this a place the server accepts live edits to the ACTIVE job? false only
-- when the town service says so; unknown (nil) never holds the engine.
local function cityHeld()
    return D ~= nil and type(D.inCity) == 'function' and D.inCity() == false;
end

-- The tab's badge (and /dl vault's line).
function R.cityBlocked() return st.pendingCity; end

-- The latest derivation's item ids ({ [itemId] = true }) -- the Inventory
-- tab's [wanted] tags and Store-wanted read this.
function R.derivedIds()
    local out = {};
    if st.lastDerived ~= nil then
        for _, it in ipairs(st.lastDerived.items) do out[it.itemId] = true; end
    end
    return out;
end

-- The live shelf-pressure verdict for the tab: nil when the layout fits,
-- else { over = units past the shelf, mode = the removals setting,
-- candidates = ranked unpinned evictees, pinned = the pinned ones (which
-- ALWAYS take explicit permission, every mode) }.
function R.pressure() return st.pressure; end

-- Free shelf slots as the engine counts them (capacity minus layout units,
-- the cap override included) -- the bench header's "you could restore
-- something" figure. nil until a beat has measured.
function R.freeSlots() return st.freeSlots; end

-- How many set-wanted items the last beat could NOT shelve because the
-- vault holds no copy (the 2026-08-30 vault law) -- `/dl vault why`'s
-- aggregate line. 0 until a beat has measured.
function R.notVaulted() return st.notVaulted or 0; end

-- Set-wanted items the vault holds only as DIFFERENTLY augmented copies,
-- more of them than the sets have room for: the player picks which.
-- { { itemId, need, copies } ... }, empty until a beat has measured.
function R.chooseCopy() return st.chooseCopy or {}; end

-- What is on the body right now ({ [itemId] = true }) -- the tab's Remove
-- guard reads the same eyes the eviction ranking uses.
function R.wornNow()
    if D ~= nil and type(D.worn) == 'function' then return D.worn() or {}; end
    return {};
end

function R.retireBlocked(itemId)
    if D == nil then return 'layout service is not ready'; end
    if type(D.browsing) == 'function' and D.browsing() then return 'return to your current job first'; end
    if type(D.inTown) ~= 'function' or D.inTown() ~= true then return 'return to a city first'; end
    local d = D.derive.derive({}, D.triggers(), D.resolve);
    if not d.cleanupSafe then return 'resolve trigger names or dynamic gear helpers before sending this piece away'; end
    if d.referencedIds[itemId] then return 'this item is used directly by a trigger; remove that trigger reference first'; end
    return nil;
end

-- What the engine is DOING, for the tab's one quiet line (replaces the 8 s
-- countdown, Henrik 2026-09-30: "the 8 second sync is confusing" -- a clock
-- that ran whether or not anything was pending read as a sync that never
-- came). { adding = n } while a run of additions is being acknowledged,
-- { removing = n } for a cleanup run, nil when there is nothing to say.
function R.activity()
    if D == nil or st.inFlight <= 0 then return nil; end
    if st.runKind == 'remove' then return { removing = st.inFlight }; end
    return { adding = st.inFlight };
end

-- A zone-in may have landed us in a city: a held or city-refused push goes
-- again right away instead of waiting out its retry clock.
-- Re-arms only: the run itself waits until the zone line is over (the vault
-- client's zone-settled callback kicks it) -- nothing happens while zoning.
function R.zoneArmed()
    if st.pendingCity then st.lastPushKey = nil; st.retryAt = nil; end
    st.repairBlocked, st.repairStamp = nil, nil;
end

local function say(msg)
    if D ~= nil and type(D.say) == 'function' then pcall(D.say, msg); end
end

local function finishRun()
    local vc = D.vc;
    st.runKind = nil;
    if st.runOk > 0 then
        vc.requestLayout(0);   -- the view catches up in one ask
    end
    if st.runCity > 0 then
        -- the town service thought this was a city and the server did not:
        -- hold until the next zone line re-arms (never re-spam from here)
        st.pendingCity = true;
        st.retryAt = math.huge;
        say('gear vault: layout additions are waiting for a city (edits to your ACTIVE job apply in town).');
    elseif st.runOk > 0 then
        st.pendingCity = false;
        say(string.format('gear vault: layout +%d piece%s from your sets.', st.runOk, (st.runOk == 1) and '' or 's'));
    end
end

-- One engine run; call every frame, it self-throttles: it runs when kicked
-- (after KICK_SETTLE) or when the quiet BEAT has passed. Returns what it did
-- (for the suite): 'idle' | 'asked-layout' | 'pushed:N' | 'clean' | ...
function R.tick()
    if D == nil then return 'idle'; end
    local vc = D.vc;
    local now = clock();
    local instances = type(vc.instanceMode) == 'function' and vc.instanceMode();
    local kicked = st.kickAt ~= nil and now >= st.kickAt;
    if not kicked and now - st.lastBeat < R.BEAT then return 'idle'; end
    if type(vc.zoning) == 'function' and vc.zoning() then return 'idle'; end   -- nothing during a zone line
    if st.inFlight > 0 then return 'idle'; end            -- a run is still acking
    if type(vc.layoutBusy) == 'function' and vc.layoutBusy() then return 'idle'; end
    local vs = vc.state();
    if vs == 'dormant' or vs == 'syncing' or vs == 'unattuned' then return 'idle'; end
    if type(D.browsing) == 'function' and D.browsing() == true then return 'idle'; end
    local job = (type(D.mainJob) == 'function') and D.mainJob() or nil;
    if type(job) ~= 'number' or job == 0 then return 'idle'; end

    -- The diff needs the server's CURRENT layout for the CURRENT job. The ask
    -- does not spend the run: the layout's commit kicks the engine, so the
    -- adds follow the view at once instead of one beat later (a deposit used
    -- to cost two 8 s beats before its add).
    if not vc.layoutCache.fresh or vc.layoutCache.job ~= job then
        vc.requestLayout(0);
        return 'asked-layout';
    end
    st.lastBeat = now;
    st.kickAt = nil;

    local d = D.derive.derive(D.setsRoot(), D.triggers(), D.resolve);
    st.lastDerived = d;

    -- FIRST SIGHT SEEDING (GV4): every layout identity gets an age the
    -- moment the layout shows it, once per layout stamp.
    if D.usage ~= nil and st.seedStamp ~= vc.layoutCache.stamp then
        st.seedStamp = vc.layoutCache.stamp;
        local keys = {};
        for _, e in ipairs(vc.layoutCache.entries or {}) do
            keys[#keys + 1] = D.usage.keyOf(e.itemId, e.identity, e.instanceId);
        end
        pcall(D.usage.seed, keys);
    end

    -- Use the same bounded counts for pressure, pair upgrades, and the UI.
    -- Retain the original entries for identity-preserving wire corrections.
    local layout, corrections = {}, {};
    for _, e in ipairs(vc.layoutCache.entries or {}) do
        local rec = type(D.lookupById) == 'function' and D.lookupById(e.itemId) or nil;
        local count = counts.count(e, rec);
        local copy = {}; for k, v in pairs(e) do copy[k] = v; end
        copy.count = count;
        layout[#layout + 1] = copy;
        if not instances and count < e.count then
            corrections[#corrections + 1] = { itemId = e.itemId, identity = e.identity,
                count = e.count - count, hint = e.hint, pinned = e.pinned };
        end
    end

    -- Release obsolete assignments before considering additions. Only a
    -- complete derivation can prove absence; review rows and outside copies
    -- remain assigned for recovery. Equipped pieces wait until taken off.
    if instances and d.cleanupSafe and type(D.worn) == 'function'
        and type(D.inTown) == 'function' and D.inTown() == true and not cityHeld() then
        local worn, obsolete = D.worn(), {};
        for _, e in ipairs(layout) do
            if worn and not e.pinned and e.kind ~= 2 and (e.state == 0 or e.state == 1)
                and not d.referencedIds[e.itemId] and not worn[e.itemId]
                and not worn['i:' .. tostring(e.instanceId)] then
                obsolete[#obsolete + 1] = e;
            end
        end
        if #obsolete > 0 then
            local n = math.min(#obsolete, R.MAX_PUSH);
            st.inFlight = n;
            st.runKind = 'remove';
            for i = 1, n do
                local e = obsolete[i];
                local queued = vc.requestLayoutSet({ job = job, verb = vc.verb.REMOVE,
                    itemId = e.itemId, instanceId = e.instanceId, ordinal = e.ordinal,
                    identity = e.identity, count = 0, reason = 'unused-unpinned' }, function()
                        st.inFlight = math.max(0, st.inFlight - 1);
                        if st.inFlight == 0 then st.runKind = nil; end
                        vc.requestLayout(0);
                    end);
                if not queued then st.inFlight = math.max(0, st.inFlight - 1); end
            end
            if st.inFlight == 0 then st.runKind = nil; end
            return 'released:' .. n;
        end
    end

    -- zero-blob layout entries only (see header): id -> count
    local have, bound, review = {}, {}, {};
    for _, e in ipairs(layout) do
        if instances then
            if e.kind == 2 then review[e.itemId] = true;
            else have[e.itemId] = (have[e.itemId] or 0) + e.count; end
            if (e.instanceId or 0) > 0 then bound[e.instanceId] = true; end
        elseif e.identity == vc.ZERO24 then
            local c = have[e.itemId];
            if c == nil or c < e.count then have[e.itemId] = e.count; end
        end
    end

    -- tombstone housekeeping: exclusions for ids no set names any more are
    -- dead weight
    if D.usage ~= nil then
        local derivedIds = {};
        for _, it in ipairs(d.items) do derivedIds[it.itemId] = true; end
        pcall(D.usage.pruneExclusions, derivedIds);
    end

    local capacity = (type(D.capacity) == 'function') and (D.capacity() or 0) or 0;
    local layoutUnits = 0;
    for _, e in ipairs(layout) do layoutUnits = layoutUnits + e.count; end
    st.freeSlots = (capacity > 0) and math.max(0, capacity - layoutUnits) or nil;

    -- Heal legacy repeated ADDs before sending any new additions or evictions.
    -- REMOVE with a positive count subtracts just the surplus; it does not
    -- delete the identity or change its pin/hint. Only known equipment limits
    -- are repaired. Active-job writes wait for town and a fresh layout.
    if #corrections > 0 then
        st.pressure = nil;
        if st.repairBlocked or cityHeld() or (type(D.inTown) == 'function' and D.inTown() == false) then return 'waiting-city'; end
        if st.repairStamp == vc.layoutCache.stamp then return 'clean'; end
        st.repairStamp = vc.layoutCache.stamp;
        local n = math.min(#corrections, R.MAX_PUSH);
        st.inFlight = n;
        local function done(code)
            if code == vc.code.NOT_IN_CITY then st.repairBlocked = true; end
            st.inFlight = math.max(0, st.inFlight - 1);
            if st.inFlight == 0 then vc.requestLayout(0); end
        end
        for i = 1, n do
            local e = corrections[i]; e.job = job; e.verb = vc.verb.REMOVE;
            if not vc.requestLayoutSet(e, done) then done(); end
        end
        return 'repairing:' .. n;
    end

    -- The adds, under FOUR gates (Henrik's 2026-08-27 field round -- the
    -- remove/re-add tug-of-war, and "dlac would keep trying to load the
    -- server needlessly" -- plus the 2026-08-30 VAULT LAW): the additions
    -- setting; the TOMBSTONES (an entry the player removed stays removed);
    -- the VAULT -- the engine may only shelve what the vault actually
    -- holds, never gear sitting in your bags or not owned at all (storing
    -- it with a Void Warden is what makes it eligible; the Inventory pane's
    -- [wanted] tags point at exactly those pieces). Want is capped at vault
    -- + layout copies, so a pair the sets need twice with one copy vaulted
    -- shelves ONE; and the SHELF -- the engine never pushes an add that
    -- cannot fit, so a full shelf costs zero wire.
    local vaultCounts = (vc.mirror ~= nil and vc.mirror.counts) or {};
    local candidates, augRows = {}, {};
    if instances then
        vaultCounts = {};
        for _, row in ipairs(vc.mirror.rows or {}) do
            -- Anchor Ring's signature is EXP, not an augment requirement.
            -- Already bound instances above keep satisfying demand after
            -- upgrades.
            if not bound[row.instanceId] then
                if row.identity == vc.ZERO24 or row.itemId == 27556 then
                    candidates[#candidates + 1] = row;
                    vaultCounts[row.itemId] = (vaultCounts[row.itemId] or 0) + math.max(1, row.qty or 1);
                elseif (row.instanceId or 0) > 0 then
                    augRows[row.itemId] = augRows[row.itemId] or {};
                    table.insert(augRows[row.itemId], row);
                end
            end
        end
    end

    -- The augmented copies to draw for demand the plain copies cannot meet
    -- (Henrik's 2026-10-01 Leather Vest: its one vaulted copy was augmented,
    -- so the Idle set never got it). Only when nothing is being chosen: the
    -- shortfall takes every augmented copy there is, or copies whose rolls
    -- are identical. Different rolls competing for fewer places stay the
    -- player's pick (returns choice = true). A plain-pinned entry (AugKey
    -- = '') would refuse to wear any of them.
    local function augmentedPick(it, short)
        local rows = augRows[it.itemId];
        if short <= 0 or rows == nil or it.plainOnly then return {}, false; end
        for i = 2, #rows do
            if #rows > short and rows[i].identity ~= rows[1].identity then return {}, true; end
        end
        local pick = {};
        for i = 1, math.min(short, #rows) do pick[i] = rows[i]; end
        return pick, false;
    end

    local adds = {};
    local waiting, waitingItems, notVaulted, chooseCopy = 0, {}, 0, {};
    if vc.mirror.fresh ~= false and not (D.settings ~= nil and D.settings().additions == 'off') then
        local units = layoutUnits;
        for _, it in ipairs(d.items) do
            local c = have[it.itemId];
            local rec = type(D.lookupById) == 'function' and D.lookupById(it.itemId) or nil;
            local want = counts.count(it, rec);
            local plainHave = (vaultCounts[it.itemId] or 0) + (c or 0);
            local augPick, choice = {}, false;
            if instances then augPick, choice = augmentedPick(it, want - plainHave); end
            local wantable = math.min(want, plainHave + #augPick);
            local excluded = false;
            if D.usage ~= nil then
                excluded = D.usage.isExcluded(D.usage.keyOf(it.itemId, nil));
            end
            if choice and not excluded and not review[it.itemId] then
                chooseCopy[#chooseCopy + 1] = { itemId = it.itemId, need = want - plainHave,
                                                copies = #augRows[it.itemId] };
            end
            if wantable > (c or 0) and not review[it.itemId] then
                if not excluded then
                    local need = wantable - (c or 0);
                    if capacity > 0 and units + need > capacity then
                        waiting = waiting + need;
                        waitingItems[#waitingItems + 1] = { itemId = it.itemId, need = need };
                    elseif #adds < R.MAX_PUSH then
                        units = units + need;
                        -- ADD increments on the server; never send the total.
                        if instances then
                            -- Select physical copies from the fresh mirror. A
                            -- changed EXP/augment snapshot never causes a second
                            -- addition of an already-bound instance.
                            for _, row in ipairs(candidates) do
                                if need <= 0 or #adds >= R.MAX_PUSH then break; end
                                if row.itemId == it.itemId and not bound[row.instanceId] then
                                    if (row.instanceId or 0) > 0 then
                                        adds[#adds + 1] = { itemId = it.itemId, count = 1,
                                            instanceId = row.instanceId, identity = row.identity };
                                        bound[row.instanceId] = true; need = need - 1;
                                    else
                                        adds[#adds + 1] = { itemId = it.itemId, count = math.min(need, 8), identity = row.identity };
                                        need = 0;
                                        break;
                                    end
                                end
                            end
                            for _, row in ipairs(augPick) do
                                if need <= 0 or #adds >= R.MAX_PUSH then break; end
                                adds[#adds + 1] = { itemId = it.itemId, count = 1,
                                    instanceId = row.instanceId, identity = row.identity };
                                bound[row.instanceId] = true; need = need - 1;
                            end
                        else
                            adds[#adds + 1] = { itemId = it.itemId, count = need };
                        end
                    end
                end
            elseif not choice and (c == nil or c < it.count) then
                -- the sets want it, the vault cannot supply it: NOT pushed,
                -- NOT waiting -- it is the Inventory pane / Warden's problem
                notVaulted = notVaulted + 1;
            end
        end
    end
    st.notVaulted = notVaulted;
    st.chooseCopy = chooseCopy;

    -- SHELF PRESSURE (GV3): the layout (plus what is about to join it) must
    -- fit the live shelf, or the swap engine will be told to dress more
    -- slots than the wardrobes hold. Verdict exposed to the tab; 'auto'
    -- evicts unpinned LRU candidates itself, ONCE per layout stamp -- and a
    -- pinned entry takes explicit permission in EVERY mode.
    --
    -- Evaluated EVERY beat, deliberately BEFORE the derivation-unchanged
    -- early-out below: capacity can move on its own (the wardrobe lock, a
    -- /dl vault cap override) with no change to the derivation or the
    -- layout -- Henrik's cap-override field round found exactly that beat
    -- answering 'clean' forever while the pressure verdict sat stale.
    st.pressure = nil;
    if capacity > 0 and D.usage ~= nil then
        -- over = the layout ITSELF outgrows the shelf; waiting = it fits,
        -- but derived pieces are queued outside for room. Either way the
        -- player decides what makes room (or Auto does, unpinned only).
        local over = layoutUnits - capacity;
        if over > 0 or waiting > 0 then
            local assigned = {};
            for _, it in ipairs(d.items) do assigned[it.itemId] = true; end
            local worn = (type(D.worn) == 'function') and D.worn() or {};
            local ranked = D.usage.rankEvictions(layout, assigned, worn);
            local mode = (D.settings ~= nil) and D.settings().removals or 'ask';
            -- Auto-eviction only ACTS in town (Henrik's 2026-08-30 field
            -- round): out in the field the active job's layout edits are
            -- refused NOT_IN_CITY anyway, so an auto-evict would just burn
            -- the once-per-stamp latch on a run of refusals. The PREDICTION
            -- (the town service) gates the action, never the verdict --
            -- pressure is still computed and exposed, and unknown (nil)
            -- reads as town so a broken service returns old behaviour.
            local town = not (type(D.inTown) == 'function' and D.inTown() == false) and not cityHeld();
            if mode == 'auto' and over > 0 and town and st.evictStamp ~= vc.layoutCache.stamp then
                st.evictStamp = vc.layoutCache.stamp;
                local freed, evicted = 0, 0;
                local tomb = {};
                for _, c in ipairs(ranked.unpinned) do
                    if freed >= over then break; end
                    freed = freed + c.count;
                    evicted = evicted + 1;
                    if c.assigned then tomb[#tomb + 1] = D.usage.keyOf(c.itemId, nil); end
                    vc.requestLayoutSet({ job = 0, verb = vc.verb.REMOVE, itemId = c.itemId,
                                          reason = 'pressure-eviction',
                                          instanceId = c.instanceId, ordinal = c.ordinal,
                                          count = 0, hint = 0, pinned = false, identity = c.identity },
                        function(code) if code == vc.code.OK then vc.requestLayout(0); end end);
                end
                -- an auto-evicted set-wanted entry is tombstoned too, or the
                -- next beat re-adds what this beat just removed
                if #tomb > 0 then pcall(D.usage.exclude, tomb); end
                if evicted > 0 then
                    say(string.format('gear vault: shelf over by %d -- evicted %d least-used unpinned entr%s (Removals: Auto).',
                        over, evicted, (evicted == 1) and 'y' or 'ies'));
                end
                if freed < over then
                    st.pressure = { over = over - freed, waiting = waiting, waitingItems = waitingItems,
                                    mode = mode, candidates = {}, pinned = ranked.pinned };
                end
            elseif (not town) or mode ~= 'auto' or over <= 0 then
                st.pressure = { over = math.max(0, over), waiting = waiting, waitingItems = waitingItems,
                                mode = mode, candidates = ranked.unpinned, pinned = ranked.pinned };
            end
        end
    end

    -- The PUSH half alone rides the change gate (pressure above never does).
    -- THE KEY IS WHAT WOULD BE SENT (2026-09-30): the derivation hash plus
    -- the exact adds, never the stamps of the views they were read from.
    --   * a deposit, a set commit or a layout change that makes a NEW add
    --     makes a new key: it goes at once (Henrik's brass set, 2026-09-10,
    --     is why the vault joined the key at all);
    --   * a re-read that changes nothing keeps the key: no re-spam (the stamp
    --     key re-sent a city-refused add after every re-read in the field,
    --     one chat line each);
    --   * a run that did not land goes again after RETRY (the stamp key parked
    --     a BUSY-refused add until some unrelated stamp happened to move).
    if vc.mirror.fresh == false then return 'clean'; end   -- a re-read is due; its commit kicks us
    if #adds == 0 then
        st.lastPushKey, st.retryAt = nil, nil;
        st.pendingCity = false;   -- nothing waits for a city any more (the badge used to stick)
        return 'clean';
    end
    local keyParts = { d.hash };
    for _, it in ipairs(adds) do
        keyParts[#keyParts + 1] = tostring(it.itemId) .. ':' .. tostring(it.instanceId or 0) .. ':' .. tostring(it.count);
    end
    local pushKey = table.concat(keyParts, '|');
    -- Live edits to the ACTIVE job need a city; out in the field the server
    -- would only refuse them. Hold the adds, send nothing, say they wait
    -- (Henrik, 2026-09-30: no vault events outside a city). Nothing is
    -- latched: the first run that finds us in a city sends them -- the zone
    -- line's kick, or the next quiet beat if the zone read lagged the kick.
    if cityHeld() then
        st.pendingCity = true;
        return 'waiting-city';
    end
    if pushKey == st.lastPushKey and now < (st.retryAt or 0) then return 'clean'; end
    st.lastPushKey = pushKey;
    st.retryAt = now + R.RETRY;

    st.inFlight, st.runOk, st.runCity, st.runFail = #adds, 0, 0, 0;
    st.runKind = 'add';
    for _, it in ipairs(adds) do
        local queued = vc.requestLayoutSet(
            { job = 0, verb = vc.verb.ADD, itemId = it.itemId, count = it.count,
              reason = 'derived-from-sets',
              hint = 0, pinned = false, identity = it.identity or vc.ZERO24, instanceId = it.instanceId },
            function(code, err)
                st.inFlight = math.max(0, st.inFlight - 1);
                if code == vc.code.OK then
                    st.runOk = st.runOk + 1;
                elseif code == vc.code.NOT_IN_CITY then
                    st.runCity = st.runCity + 1;
                    -- every sibling targets the same job: drop the rest now
                    st.inFlight = st.inFlight - vc.cancelLayoutSets();
                    if st.inFlight <= 0 then st.inFlight = 0; finishRun(); end
                    return;
                else
                    st.runFail = st.runFail + 1;
                    if err == nil and code ~= nil then
                        say(string.format('gear vault: a layout add was refused (code %d).', code));
                    end
                end
                if st.inFlight <= 0 then st.inFlight = 0; finishRun(); end
            end);
        if not queued then st.inFlight = math.max(0, st.inFlight - 1); end
    end
    if st.inFlight <= 0 then st.inFlight = 0; st.runKind = nil; end
    return 'pushed:' .. #adds;
end

-- test seams
function R._st() return st; end
function R._reset()
    st = { lastBeat = 0, kickAt = nil, lastPushKey = nil, retryAt = nil, pendingCity = false,
           inFlight = 0, runOk = 0, runCity = 0, runFail = 0, runKind = nil,
           lastDerived = nil, pressure = nil, seedStamp = nil, evictStamp = nil };
end

return R;
