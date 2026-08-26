--[[
    vanaheim/gearvault/reconcile.lua -- the ADDITIONS PUSH (GV3, slice 3).

    STATELESS BY DESIGN: instead of a durable queue of pending edits, the
    engine recomputes the derived layout for the ACTIVE main job on a slow
    beat and pushes whatever is missing from the server's layout. That one
    shape covers every trigger at once -- a set commit (the derivation hash
    moves), login (the first beat), the city gate (a NOT_IN_CITY refusal
    sets the badge and a later beat in town simply succeeds), and a dlac
    restart mid-queue (nothing was queued; the next beat re-derives).

    Additions ONLY, the GV3 law: the engine may add a missing identity or
    RAISE a count (a pair the sets now need twice), and may never remove or
    lower anything -- removals are the space-pressure flow (slice 4) or the
    player's own hand in the tab. Derived entries carry the ZERO blob
    (augment-pinned records are skipped by derivation -- the vault pane's
    "+ Layout" carries real blobs); only zero-blob layout entries are
    compared against, so a manually-added augmented copy is never disturbed.

    The engine never derives WHILE BROWSING another job (the sets root
    answers for the browsed job there -- pushing WHM's gear into WAR's
    layout is exactly the bug that guard exists for).

    Everything arrives injected (R.configure) so the suite drives the whole
    engine against the vaultclient test harness with no files and no gearui.
]]--

local R = {};

R.BEAT     = 8.0;     -- seconds between derivation checks
R.MAX_PUSH = 200;     -- adds per run -- a runaway derivation must not flood

local D = nil;        -- { vc, derive, setsRoot(), triggers(), resolve(name),
                      --   mainJob(), browsing(), say(msg), clock() }
function R.configure(deps) D = deps; end

local st = {
    lastBeat    = 0,
    lastPushKey = nil,   -- hash|layoutStamp we already pushed for (no re-spam)
    pendingCity = false, -- adds refused by the city gate: waiting for a town
    inFlight    = 0,     -- acks not yet counted this run
    runOk       = 0,
    runCity     = 0,
    runFail     = 0,
    lastDerived = nil,   -- the latest derivation (the tab's [wanted] tags)
    pressure    = nil,   -- { over, mode, candidates, pinned } | nil (see tick)
    seedStamp   = nil,   -- layout stamp already seeded into usage
    evictStamp  = nil,   -- layout stamp auto-eviction already ran for
};

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

-- What is on the body right now ({ [itemId] = true }) -- the tab's Remove
-- guard reads the same eyes the eviction ranking uses.
function R.wornNow()
    if D ~= nil and type(D.worn) == 'function' then return D.worn() or {}; end
    return {};
end

-- A zone-in may have landed us in a city: let the next beat retry a
-- city-blocked push immediately instead of waiting out lastPushKey.
function R.zoneArmed()
    if st.pendingCity then st.lastPushKey = nil; end
end

local function say(msg)
    if D ~= nil and type(D.say) == 'function' then pcall(D.say, msg); end
end

local function finishRun()
    local vc = D.vc;
    if st.runOk > 0 then
        vc.requestLayout(0);   -- the view catches up in one ask
    end
    if st.runCity > 0 then
        st.pendingCity = true;
        say('gear vault: layout additions are waiting for a city (edits to your ACTIVE job apply in town).');
    elseif st.runOk > 0 then
        st.pendingCity = false;
        say(string.format('gear vault: layout +%d piece%s from your sets.', st.runOk, (st.runOk == 1) and '' or 's'));
    end
end

-- One engine beat; call every frame, it self-throttles. Returns what it did
-- (for the suite): 'idle' | 'asked-layout' | 'pushed:N' | 'clean'.
function R.tick()
    if D == nil then return 'idle'; end
    local vc = D.vc;
    local now = (type(D.clock) == 'function') and D.clock() or os.clock();
    if now - st.lastBeat < R.BEAT then return 'idle'; end
    if st.inFlight > 0 then return 'idle'; end            -- a run is still acking
    if vc.state() == 'dormant' or vc.state() == 'syncing' then return 'idle'; end
    if type(D.browsing) == 'function' and D.browsing() == true then return 'idle'; end
    local job = (type(D.mainJob) == 'function') and D.mainJob() or nil;
    if type(job) ~= 'number' or job == 0 then return 'idle'; end
    st.lastBeat = now;

    -- The diff needs the server's CURRENT layout for the CURRENT job.
    if not vc.layoutCache.fresh or vc.layoutCache.job ~= job then
        vc.requestLayout(0);
        return 'asked-layout';
    end

    local d = D.derive.derive(D.setsRoot(), D.triggers(), D.resolve);
    st.lastDerived = d;

    -- FIRST SIGHT SEEDING (GV4): every layout identity gets an age the
    -- moment the layout shows it, once per layout stamp.
    if D.usage ~= nil and st.seedStamp ~= vc.layoutCache.stamp then
        st.seedStamp = vc.layoutCache.stamp;
        local keys = {};
        for _, e in ipairs(vc.layoutCache.entries or {}) do
            keys[#keys + 1] = D.usage.keyOf(e.itemId, e.identity);
        end
        pcall(D.usage.seed, keys);
    end

    -- zero-blob layout entries only (see header): id -> count
    local have = {};
    for _, e in ipairs(vc.layoutCache.entries or {}) do
        if e.identity == vc.ZERO24 then
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
    for _, e in ipairs(vc.layoutCache.entries or {}) do layoutUnits = layoutUnits + (e.count or 1); end
    st.freeSlots = (capacity > 0) and math.max(0, capacity - layoutUnits) or nil;

    -- The adds, under THREE gates (Henrik's 2026-08-27 field round -- the
    -- remove/re-add tug-of-war, and "dlac would keep trying to load the
    -- server needlessly"): the additions setting; the TOMBSTONES (an entry
    -- the player removed stays removed); and the SHELF -- the engine never
    -- pushes an add that cannot fit, so a full shelf costs zero wire.
    local adds = {};
    local waiting, waitingItems = 0, {};
    if not (D.settings ~= nil and D.settings().additions == 'off') then
        local units = layoutUnits;
        for _, it in ipairs(d.items) do
            local c = have[it.itemId];
            if c == nil or c < it.count then
                local excluded = false;
                if D.usage ~= nil then
                    excluded = D.usage.isExcluded(D.usage.keyOf(it.itemId, nil));
                end
                if not excluded then
                    local need = it.count - (c or 0);
                    if capacity > 0 and units + need > capacity then
                        waiting = waiting + need;
                        waitingItems[#waitingItems + 1] = { itemId = it.itemId, need = need };
                    elseif #adds < R.MAX_PUSH then
                        units = units + need;
                        adds[#adds + 1] = it;
                    end
                end
            end
        end
    end

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
            local ranked = D.usage.rankEvictions(vc.layoutCache.entries, assigned, worn);
            local mode = (D.settings ~= nil) and D.settings().removals or 'ask';
            if mode == 'auto' and over > 0 and st.evictStamp ~= vc.layoutCache.stamp then
                st.evictStamp = vc.layoutCache.stamp;
                local freed, evicted = 0, 0;
                local tomb = {};
                for _, c in ipairs(ranked.unpinned) do
                    if freed >= over then break; end
                    freed = freed + c.count;
                    evicted = evicted + 1;
                    if c.assigned then tomb[#tomb + 1] = D.usage.keyOf(c.itemId, nil); end
                    vc.requestLayoutSet({ job = 0, verb = vc.verb.REMOVE, itemId = c.itemId,
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
            elseif mode ~= 'auto' or over <= 0 then
                st.pressure = { over = math.max(0, over), waiting = waiting, waitingItems = waitingItems,
                                mode = mode, candidates = ranked.unpinned, pinned = ranked.pinned };
            end
        end
    end

    -- The PUSH half alone rides the change gate (pressure above never does).
    local pushKey = d.hash .. '|' .. tostring(vc.layoutCache.stamp);
    if pushKey == st.lastPushKey then return 'clean'; end
    st.lastPushKey = pushKey;
    if #adds == 0 then
        if st.runCity == 0 then st.pendingCity = false; end
        return 'clean';
    end

    st.inFlight, st.runOk, st.runCity, st.runFail = #adds, 0, 0, 0;
    for _, it in ipairs(adds) do
        local queued = vc.requestLayoutSet(
            { job = 0, verb = vc.verb.ADD, itemId = it.itemId, count = it.count,
              hint = 0, pinned = false, identity = vc.ZERO24 },
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
    if st.inFlight <= 0 then st.inFlight = 0; end
    return 'pushed:' .. #adds;
end

-- test seams
function R._st() return st; end
function R._reset()
    st = { lastBeat = 0, lastPushKey = nil, pendingCity = false,
           inFlight = 0, runOk = 0, runCity = 0, runFail = 0,
           lastDerived = nil, pressure = nil, seedStamp = nil, evictStamp = nil };
end

return R;
