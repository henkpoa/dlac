--[[
    dlac/feature/modapi.lua -- THE MODULE API. The one table a Job helper is
    handed, and the answer to "what may I call, and what will keep working?"

        init = function(S)
            S.combat.subscribe('fight',  onBeat)
            S.pet.subscribe('reward',    onVitals)
            S.pet.onLoss('resummon',     onLoss)
        end,

    ---------------------------------------------------------------------------
    WHY A FRONT DOOR, WHEN THERE IS NO WALL
    ---------------------------------------------------------------------------

    ADR 0028 settled the sandbox question and settled it correctly: dlac ships as
    readable Lua in one Lua state, so a wall buys attribution, not prevention --
    "visibility and contracts, not walls". A module CAN `require` anything. This
    table does not change that and does not try to.

    What it changes is what a module *should* call, and the difference is worth
    stating plainly because it is the whole point:

        This table is the SUPPORTED surface. It is documented, versioned by
        `api`, covered by tests, and it will keep working. Reach past it with a
        raw `require` and you own the breakage -- and that is the signal that
        this table is missing an entry, which is a bug report, not a scolding.

    Before it existed, every module reached the services by hardcoded path string,
    and the first real module paid for it in ways that are all visible in its git
    history: `local function req(name)` copied into three files, the monotonic
    clock copied into three more (five across the addon), the same three-`pcall`
    block assembling activity + busy + clock written out three times, `_emit`
    twice, `sectionOrder` twice, and its OWN module path -- `dlac\jobhelpers\bst\
    bst-helper\config` -- hardcoded in four files, in a framework whose first law
    is that the folder name is the identity. Rename the folder and the loader
    cheerfully assigns the new id while every internal require breaks.

    None of that was bad code. It is what "reach the services by path" costs.

    ---------------------------------------------------------------------------
    THE DESIGN RULE: ANSWERS IN THE AUTHOR'S VOCABULARY
    ---------------------------------------------------------------------------

    Entries here are named for the QUESTION a module asks, not for the dlac
    service that happens to answer it -- `S.item.own('Carrot Broth')`, not
    "ownedcache.counts() keyed by item id, so keep your own name-to-id table".
    Two consequences, both deliberate:

      * The right answer becomes the ONLY reachable answer. `S.player.level()`
        returns the level the ENGINE will gear at (the `/dl set level main`
        override, then the SYNC-aware level). There is no way to reach raw
        MainJobLevel from here, because reaching it is a bug that already cost a
        live field round: under level sync a picker chose a tier above the cap,
        the equip was refused, and the sequence died in a verify timeout instead
        of falling a rung. A comment cannot prevent that. An absent function can.
      * Internals stay free to move. Most entries below are plain REFERENCES to
        existing service functions -- this is a curated namespace, not a
        translation layer, so it costs nearly nothing and cannot drift from what
        it names. Where it does wrap, the wrap is buying something specific
        (a resolved name, a namespaced key, a filled-in field).

    ---------------------------------------------------------------------------
    WHAT THE LOADER DOES WITH IT
    ---------------------------------------------------------------------------

    `build(rec)` mints one S per module, closed over that module's identity. So
    `S.id` is not something a module declares (or can lie about), subscription
    keys are namespaced by it automatically -- `S.pet.subscribe('reward', cb)`
    becomes `jobhelper:bst-helper:reward` -- and every subscription is RECORDED,
    which is what finally makes teardown possible: `modapi.dropAll(id)` drops a
    module's beats wholesale. Nothing unsubscribed before this existed.

    Pure at load. Every AshitaCore / require touch below is call-time and under
    pcall, so a module built on this loads clean in the headless suites, and a
    service that failed to load degrades one answer instead of taking a module
    down with it.
]]--

local M = {};

-- The API version a module must declare. The loader refuses a mismatch loudly.
-- Bump it when an entry below changes MEANING or disappears -- adding a new entry
-- is not a break, but a module that needs one must still be able to say so.
--
--   1 -> the raw-service era: init(deps) with { host, jobhelpers }, everything
--        else reached by hardcoded require path.
--   2 -> this table.
M.API = 2;

-- ---------------------------------------------------------------------------
-- internals
-- ---------------------------------------------------------------------------

-- Require a dlac module, contained. nil when it is unreachable, which every
-- caller below treats as "this answer is unavailable right now", never as fatal.
local function svc(path)
    local ok, m = pcall(require, path);
    if ok and type(m) == 'table' then return m; end
    return nil;
end
M._svc = svc;   -- test seam

-- Call `fn` on a service, contained, and answer `fallback` when the service or
-- the function is missing. Every read in this file goes through here, which is
-- why none of them can throw into a module.
local function ask(path, fname, fallback, ...)
    local m = svc(path);
    if m == nil or type(m[fname]) ~= 'function' then return fallback; end
    local ok, a, b = pcall(m[fname], ...);
    if not ok then return fallback; end
    if a == nil then return fallback, b; end
    return a, b;
end

-- Every subscription every module has opened: id -> { { path, off, key }, .. }.
-- Recorded so dropAll can undo them; see the header.
local _subs = {};

local function record(id, path, off, key)
    if type(id) ~= 'string' then return; end
    _subs[id] = _subs[id] or {};
    _subs[id][#_subs[id] + 1] = { path = path, off = off, key = key };
end

-- Drop every subscription a module opened. Called by the loader on teardown /
-- reload, and by the tests. Returns how many were dropped.
function M.dropAll(id)
    local list = _subs[id];
    if type(list) ~= 'table' then return 0; end
    local n = 0;
    for _, s in ipairs(list) do
        local m = svc(s.path);
        if m ~= nil and type(m[s.off]) == 'function' then
            if pcall(m[s.off], s.key) then n = n + 1; end
        end
    end
    _subs[id] = nil;
    return n;
end

function M.subscriptionCount(id)
    local list = _subs[id];
    if type(list) ~= 'table' then return 0; end
    return #list;
end

-- Resolve an item NAME or id to a catalog / owned record. The oracle first (its
-- records carry owned-copy facts and augments), the catalog index behind it (it
-- answers for anything the character does not own). nil when neither can.
local function itemRec(nameOrId)
    if nameOrId == nil then return nil; end
    local rec = ask('dlac\\gear\\gearoracle', 'lookup', nil, nameOrId);
    if type(rec) == 'table' then return rec; end
    local ci = svc('dlac\\gear\\catalogindex');
    if ci == nil or type(ci.flat) ~= 'function' then return nil; end
    local out = nil;
    pcall(function()
        local _, byId, byName = ci.flat();
        if type(nameOrId) == 'number' then
            if type(byId) == 'table' then out = byId[nameOrId]; end
        elseif type(nameOrId) == 'string' then
            if type(byName) == 'table' then out = byName[string.lower(nameOrId)]; end
        end
    end);
    if type(out) == 'table' then return out; end
    return nil;
end

-- ---------------------------------------------------------------------------
-- build -- one S per module
-- ---------------------------------------------------------------------------
--
-- `rec` is the loader's module record: { id, job, label, jobs, mod, cfg }.
-- Everything below closes over `id`, so a module cannot ask a question "as"
-- another module.
function M.build(rec)
    rec = (type(rec) == 'table') and rec or {};
    local id  = tostring(rec.id or '?');
    local job = tostring(rec.job or '');

    local S = {
        api   = M.API,
        id    = id,
        job   = job,                       -- the JOB FOLDER you filed under
        label = rec.label,
        jobs  = rec.jobs,                  -- the jobs you DECLARED (where you act)
    };

    -- The namespaced subscription key. One module's 'reward' can never collide
    -- with another's -- which was previously an author's job to remember.
    local function who(name) return 'jobhelper:' .. id .. ':' .. tostring(name or 'main'); end
    S.who = who;

    -- ----- identity + plumbing --------------------------------------------

    -- Require one of YOUR OWN files, by bare name: S.sibling('reward'). This is
    -- the reason a module never writes its own path -- and therefore the reason
    -- renaming a module folder is safe, which the framework has always claimed.
    function S.sibling(name)
        if type(name) ~= 'string' or name == '' then return nil; end
        if job == '' then return nil; end
        return svc('dlac\\jobhelpers\\' .. job .. '\\' .. id .. '\\' .. name);
    end

    -- THE escape hatch, named so it is obvious in a diff and in a code review.
    -- Anything you reach through here is unsupported: it may move or change
    -- shape without an `api` bump. If you need it, say so and it becomes an
    -- entry above.
    function S.service(path) return svc(path); end

    -- The ONE monotonic clock: the cmdqueue frame counter (the addon's steady
    -- tick), falling back to os.clock. Measure every lockout and every debounce
    -- against this, and never against os.time -- os.clock is process CPU time on
    -- some builds, and two clocks compared to each other is a bug that only
    -- shows up in the field.
    function S.now()
        local t = nil;
        pcall(function()
            local cq = require('dlac\\lib\\cmdqueue');
            if type(cq) == 'table' and type(cq.frame) == 'function' then t = cq.frame() / 60.0; end
        end);
        if type(t) ~= 'number' then pcall(function() t = os.clock(); end); end
        return tonumber(t) or 0;
    end

    -- ----- speaking to the player -----------------------------------------
    --
    -- Success is SILENT; a refusal is ONE line naming the blocker. These are the
    -- only ways a module should reach chat -- never print(), never a direct
    -- QueueCommand of a /echo.
    local function say(kind, line)
        local done = false;
        local cf = svc('dlac\\chatfmt');
        if cf ~= nil and type(cf[kind]) == 'function' then
            if pcall(cf[kind], line) then done = true; end
        end
        if not done then pcall(function() print('[dlac] ' .. tostring(line)); end); end
        return true;
    end
    S.say = {
        good = function(line) return say('good', line); end,
        warn = function(line) return say('warn', line); end,
        err  = function(line) return say('err',  line); end,
    };

    -- ----- am I acting? ----------------------------------------------------

    S.me = {};

    -- The ONE gate every Job helper consults: { active, reason, label }, where
    -- reason is off / job / zoning / dead / town, in that precedence -- which is
    -- also the order to REPORT them in, so the most specific true statement wins.
    -- An unknown world never manufactures a reason. Your own gates then decide
    -- which way THEIR nils go, and for anything that issues a command or spends
    -- an item, `active` must be positively true before you act.
    function S.me.acting()
        return ask('dlac\\feature\\jobhelpers', 'activity',
                   { active = false, reason = nil, label = '?' }, id);
    end

    -- Your tie-break priority for a contended Action sequence: your row's
    -- position in the current job's section, as the player dragged it. Higher
    -- wins. Do not invent your own number -- the framework owns this because it
    -- is a fact about the MODULE, so all of your rules share one answer.
    function S.me.order()
        return ask('dlac\\feature\\jobhelpers', 'sectionOrder', 1, id);
    end

    -- Your row pill. Note it defaults ON: a freshly installed module runs and the
    -- player SILENCES it. Your own behaviors are the opposite -- default them off.
    function S.me.enabled()
        return ask('dlac\\feature\\jobhelpers', 'isEnabled', true, id) == true;
    end

    -- ----- the player ------------------------------------------------------

    S.player = {};

    local function gPlayer()
        local p = nil;
        pcall(function()
            local g = rawget(_G, 'gData');
            if type(g) ~= 'table' or type(g.GetPlayer) ~= 'function' then return; end
            p = g.GetPlayer();
        end);
        if type(p) == 'table' then return p; end
        return nil;
    end

    function S.player.job()
        local p = gPlayer();
        if p == nil or type(p.MainJob) ~= 'string' or p.MainJob == '?' then return nil; end
        return p.MainJob;
    end

    function S.player.subJob()
        local p = gPlayer();
        if p == nil or type(p.SubJob) ~= 'string' or p.SubJob == '' then return nil; end
        return p.SubJob;
    end

    -- THE level, and the only one reachable: the `/dl set level main` override
    -- first, then the SYNC-aware main level. See the header -- this asymmetry is
    -- the whole reason the entry exists rather than being left to the author.
    function S.player.level()
        local ovr = rawget(_G, 'staticMainLevel');
        if type(ovr) == 'number' and ovr > 0 then return ovr; end
        local p = gPlayer();
        if p == nil then return nil; end
        local lv = tonumber(p.MainJobSync);
        if lv ~= nil and lv > 0 then return lv; end
        return nil;
    end

    -- The raw status string ('Idle' / 'Engaged' / 'Dead' / 'Zoning' / ...), or nil.
    function S.player.status()
        local p = gPlayer();
        if p == nil or type(p.Status) ~= 'string' or p.Status == '' then return nil; end
        return p.Status;
    end

    -- WHERE am I -- the zone id, or nil when it cannot be read (headless,
    -- pre-login, mid-zone). The central location service's answer, which is also
    -- the one the `inTown` condition and the activity predicate are built on, so
    -- a module and the gate that governs it can never disagree about where the
    -- player is.
    --
    -- The reason it exists is quieting: "once per zone" is the natural budget
    -- for a refusal a player cannot fix where they are standing, and comparing
    -- zone ids is how you spend it. Nil is a VALUE for that purpose -- latch on
    -- it like any other, or an unreadable world becomes a repeating line.
    function S.player.zone()
        return ask('dlac\\feature\\location', 'zoneId', nil);
    end

    -- Am I ZONING / LOGGING OUT? true / false / nil, where nil means "could not
    -- tell" and must never be treated as either -- an unreadable world does not
    -- manufacture a reason (the buff-cache discipline).
    --
    -- These are the two reads that CANCEL a pending act, so they come from exactly
    -- the same probes the pet-loss classifier used to suppress a death. A module
    -- that opened its own would eventually disagree with the classifier about
    -- whether the player zoned, and then a queued act and the edge that queued it
    -- would be reasoning about different worlds.
    function S.player.zoning()
        local pv = svc('dlac\\feature\\petvitals');
        if pv == nil or type(pv.reads) ~= 'table' or type(pv.reads.zoning) ~= 'function' then
            return nil;
        end
        local ok, z = pcall(pv.reads.zoning);
        if not ok then return nil; end
        return z;
    end

    function S.player.loggingOut()
        local pv = svc('dlac\\feature\\petvitals');
        if pv == nil or type(pv.reads) ~= 'table' or type(pv.reads.loggingOut) ~= 'function' then
            return nil;
        end
        local ok, lo = pcall(pv.reads.loggingOut);
        if not ok then return nil; end
        return lo;
    end

    -- ----- combat ---------------------------------------------------------
    --
    -- One service, two shapes, and you do not choose between them: the BEAT
    -- carries the state a standing rule gates on (and, because it repeats, the
    -- retry a one-shot edge can never give you), while `targetChanged` on that
    -- beat is answered by the packet EDGE whenever one arrived. See
    -- feature\combat's header for the field history that shape is made of.

    S.combat = {};

    function S.combat.subscribe(name, cb)
        local key = who(name);
        local ok = ask('dlac\\feature\\combat', 'subscribe', false, key, cb) == true;
        if ok then record(id, 'dlac\\feature\\combat', 'unsubscribe', key); end
        return ok;
    end

    function S.combat.state() return ask('dlac\\feature\\combat', 'get', {}); end

    -- The raw edge, for a rule that reacts to the MOMENT rather than gating on
    -- the state. The entity travels WITH the edge, captured from the packet --
    -- but issue `<t>` all the same and let the client resolve it at execution.
    function S.combat.onEdge(name, cb)
        local key = who(name);
        local ok = ask('dlac\\feature\\combat', 'onEdge', false, key, cb) == true;
        if ok then record(id, 'dlac\\feature\\combat', 'offEdge', key); end
        return ok;
    end

    function S.combat.lastEdge() return ask('dlac\\feature\\combat', 'lastEdge', nil); end

    -- ----- the pet --------------------------------------------------------

    S.pet = {};

    -- { present, hpp, tp, name, status }. Two laws ride along: DEAD PET = NO PET,
    -- and PRESENCE IS TWO-STATE -- "no pet" and "could not read" answer the same,
    -- because every consumer issues a command or spends an item off the answer.
    -- Individual vitals stay nil-able: refuse on the nil, never guess.
    function S.pet.get() return ask('dlac\\feature\\petvitals', 'get', { present = false }); end

    function S.pet.subscribe(name, cb)
        local key = who(name);
        local ok = ask('dlac\\feature\\petvitals', 'subscribe', false, key, cb) == true;
        if ok then record(id, 'dlac\\feature\\petvitals', 'unsubscribe', key); end
        return ok;
    end

    -- The classified loss edge: your pet is gone, and WHY. Death is confirmed,
    -- never assumed -- a Leave, zoning and a logout each suppress ahead of any
    -- proof, and anything unproven is 'unknown', which lets nothing act.
    function S.pet.onLoss(name, cb)
        local key = who(name);
        local ok = ask('dlac\\feature\\petvitals', 'subscribeLoss', false, key, cb) == true;
        if ok then record(id, 'dlac\\feature\\petvitals', 'unsubscribeLoss', key); end
        return ok;
    end

    function S.pet.lastLoss() return ask('dlac\\feature\\petvitals', 'lastLoss', nil); end

    -- What the world OBSERVED lately, inside its shelf life: { leave = <name|true>,
    -- falls = <name|true> }. The same inbox the loss classifier reads, so a rule
    -- deciding whether to cancel a pending act sees exactly what the edge saw.
    function S.pet.signals(at)
        return ask('dlac\\feature\\petvitals', 'signals', {}, at);
    end

    -- Tell the loss classifier which pet NAMES are yours to act on -- jug pets
    -- carry unique pet names, a charmed pet keeps its mob name. The service owns
    -- the RULE; you own the LIST, and the next module's list will be its own.
    -- Answer true / false / nil, where nil means "cannot tell" and nothing acts.
    -- THE PET FOOD LADDER: the highest tier this character can BOTH wear and is
    -- carrying, read off the bags. -> { ok = true, id, name, key, level } or
    -- { ok = false, reason = 'none-carried'|'level' }.
    --
    -- There is deliberately no list UI anywhere for this and no setting to pick a
    -- tier: the best food you are carrying is the right food, always, so the
    -- feature reads the bags instead of asking. Carrying none is a LOUD refusal,
    -- never a silent no-op -- pair it with foodRefusal for the sentence.
    function S.pet.food()
        return ask('dlac\\feature\\petfood', 'choose', { ok = false, reason = 'none-carried' });
    end

    -- The one honest sentence for a refused pick ("you are not carrying any pet
    -- food." / "the pet food you are carrying is above your level.").
    function S.pet.foodRefusal(pick)
        return ask('dlac\\feature\\petfood', 'refusalLine', 'no pet food available.', pick);
    end

    function S.pet.nameAuthority(fn)
        if type(fn) ~= 'function' then return false; end
        local pv = svc('dlac\\feature\\petvitals');
        if pv == nil or type(pv.lossCtx) ~= 'table' then return false; end
        pv.lossCtx.isJugPet = fn;
        return true;
    end

    -- ----- abilities ------------------------------------------------------

    S.ability = {};

    -- Is this ability off cooldown? -> ready(bool), remaining(seconds|nil).
    --
    -- Takes a NAME and wires the live reader for you. That second part matters:
    -- the underlying core is pure, so calling it without a reader has nothing to
    -- measure and silently answers READY -- a footgun the raw service had to
    -- document and this cannot have.
    --
    -- UNKNOWN READS READY, on purpose: a recast we cannot measure must never be
    -- the reason a player cannot press a button, and the sequencer's verify-worn
    -- is the real safety net. Use it to grey out a button and to hold a rule
    -- SILENTLY -- never to manufacture a refusal you did not measure.
    function S.ability.ready(nameOrSig)
        local rc = svc('dlac\\feature\\recast');
        if rc == nil or type(rc.readyFor) ~= 'function' then return true, nil; end
        local sig = nameOrSig;
        if type(sig) == 'string' then sig = { name = sig, label = sig }; end
        if type(sig) ~= 'table' then return true, nil; end
        local ok, ready, remaining = pcall(rc.readyFor, sig, rc.liveRemaining);
        if not ok then return true, nil; end
        return ready ~= false, remaining;
    end

    -- ----- items and gear -------------------------------------------------

    S.item = {};

    -- The catalog / owned record for a name or id: { Id, Name, Level, Jobs,
    -- Slot, Stats, ... }, or nil. Live memory outranks the repo -- an owned
    -- record wins over the catalog row.
    function S.item.info(nameOrId) return itemRec(nameOrId); end

    -- How many can I EQUIP RIGHT NOW -- the equippable-bag count, which is the
    -- number that decides whether an act can happen. Takes a NAME (or an id) and
    -- resolves it for you; the underlying map is keyed by id, which is why every
    -- module that asked this question used to carry its own name-to-id table.
    --
    -- 0 when it cannot answer. An item we cannot see is an item not carried,
    -- which REFUSES rather than firing an act bare -- the safe direction.
    function S.item.own(nameOrId)
        local iid = nameOrId;
        if type(iid) ~= 'number' then
            local r = itemRec(nameOrId);
            iid = (type(r) == 'table') and tonumber(r.Id) or nil;
        end
        if iid == nil then return 0; end
        local n = 0;
        pcall(function()
            local oc = require('dlac\\gear\\ownedcache');
            if type(oc) ~= 'table' or type(oc.counts) ~= 'function' then return; end
            local counts = oc.counts();
            if type(counts) == 'table' then n = tonumber(counts[iid]) or 0; end
        end);
        return n;
    end

    -- Owned ANYWHERE, including storage (visibility, not availability). Use
    -- `own` to decide whether to act; use this to explain why you cannot.
    function S.item.stored(nameOrId)
        local iid = nameOrId;
        if type(iid) ~= 'number' then
            local r = itemRec(nameOrId);
            iid = (type(r) == 'table') and tonumber(r.Id) or nil;
        end
        if iid == nil then return 0; end
        local n = 0;
        pcall(function()
            local oc = require('dlac\\gear\\ownedcache');
            if type(oc) ~= 'table' or type(oc.totals) ~= 'function' then return; end
            local t = oc.totals();
            if type(t) == 'table' then n = tonumber(t[iid]) or 0; end
        end);
        return n;
    end

    -- What is WORN in a LAC slot key ('Ammo', 'Main', 'Head', ...) right now, by
    -- name, or nil for empty / unreadable. The engine's own worn reader -- never
    -- decode the equipment block yourself.
    function S.item.worn(slot)
        return ask('dlac\\dispatch', 'wornName', nil, slot);
    end

    -- ----- named sets -----------------------------------------------------

    S.sets = {};

    -- THE sets a player can pick: the DYNAMIC sets -- the ones the Sets tab
    -- builds and commits, and the only ones this character's engine gears from.
    --
    -- This used to answer `staticSetNames`, and that was a bug with a field
    -- report attached (2026-07-30, the BST Helper's Reward picker): the statics
    -- are the pre-profiles job file's flattened leftovers plus whatever the
    -- pre-migration backup still holds -- the Copy-from helper's IMPORT SOURCES,
    -- not a live library. A migrated character saw a list of sets they had not
    -- edited in months and none of the ones they use. One namespace, and it is
    -- the one the Sets tab shows (maintainer's ruling: Dynamic only -- a flat
    -- picker holding both cannot say WHICH `Reward` you meant).
    function S.sets.names()
        return ask('dlac\\gear\\profilesets', 'dynamicSetNames', {});
    end

    -- A named set as a flat { SlotKey = itemName } map, ready to hand to
    -- S.act.request as a claim. Empty when the set is missing or unreadable.
    --
    -- THE ENGINE'S OWN FLATTEN ANSWERS FIRST, and that is the whole point: a
    -- Dynamic set is a LADDER per slot (level rungs, mode gates, Sub pairing,
    -- virtual entries), and `sets[Name]` in the store is the head rung the
    -- engine picked at the live level -- utils.BuildDynamicSets writes it there.
    -- So a helper claims exactly the pieces the engine would have equipped,
    -- rather than a second reading of the same ladder that drifts the first time
    -- a rung is level-gated. Virtual entries ride through untouched: the claim
    -- resolves them at equip time like any set (dispatch.equipResolved), which
    -- is also why they must never appear in `need`.
    --
    -- The raw walk stays as the degraded path -- pre-login, headless, or a set
    -- authored but not yet flattened. The wrapper-shape tolerance lives HERE and
    -- not in your module: an entry may be a plain string or a table carrying
    -- Name / name / item depending on how it was authored or imported, and a
    -- module that hand-parsed it would break the day the format grew a fourth
    -- shape.
    function S.sets.slotsOf(name)
        local slots = {};
        if type(name) ~= 'string' or name == '' or name == 'None' then return slots; end

        local flat = ask('dlac\\dispatch', 'flattenedSet', nil, name);
        if type(flat) == 'table' then
            for slot, v in pairs(flat) do
                if type(v) == 'string' and v ~= '' then slots[slot] = v; end
            end
            if next(slots) ~= nil then return slots; end
        end

        pcall(function()
            local ps = require('dlac\\gear\\profilesets');
            if type(ps) ~= 'table' or type(ps.getSetsRoot) ~= 'function' then return; end
            local root = ps.getSetsRoot();
            if type(root) ~= 'table' then return; end
            -- The authored Dynamic set first, then a same-named top-level entry
            -- (a static, or a flatten this state can still see).
            local set = nil;
            if type(root.Dynamic) == 'table' and type(root.Dynamic[name]) == 'table' then
                set = root.Dynamic[name];
            elseif type(root[name]) == 'table' then
                set = root[name];
            end
            if set == nil then return; end
            for slot, v in pairs(set) do
                local item = nil;
                if type(v) == 'string' then
                    item = v;
                elseif type(v) == 'table' then
                    -- An authored LADDER is an array of candidates; its head is
                    -- what the flatten would have chosen, minus the level gates
                    -- this degraded path cannot apply.
                    local head = v[1];
                    if type(head) == 'string' then
                        item = head;
                    elseif type(head) == 'table' then
                        item = head.Name or head.name or head.item;
                    else
                        item = v.Name or v.name or v.item;
                    end
                end
                if type(item) == 'string' and item ~= '' then slots[slot] = item; end
            end
        end);
        return slots;
    end

    -- ----- acting ---------------------------------------------------------

    S.act = {};

    -- OPEN AN ACTION SEQUENCE: dress the slots, verify they landed, fire ONE
    -- command, release. This is the only way a module puts anything on the
    -- player's body, and it is deliberately a REQUEST -- the Arbiter decides, per
    -- slot, whether you get it, so Locks / Naked / Free equip cannot be punched
    -- through and `/dl why` can always explain what is worn.
    --
    --   S.act.request{
    --       label   = 'Reward',                    -- the ACT's name, shown in refusals
    --       claim   = { Ammo = 'Pet Food Theta' }, -- slot -> item; dressed best-effort
    --       need    = { Ammo = 'Pet Food Theta' }, -- MUST verify worn or nothing fires
    --       command = '/ja "Reward" <me>',
    --       timeout = 4,
    --   }
    --
    -- `module` and `order` are filled in from your identity -- you cannot get
    -- your own priority wrong, and you cannot request as somebody else.
    --
    -- Keep `need` to the CONSUMED or PRECONDITION slot alone. Everything else is
    -- costume: a claimed-but-not-needed slot dresses best-effort, so a senior
    -- claimant taking it costs you that slot and refuses nothing, while every
    -- extra NEEDED slot is one more way for the whole act to be refused.
    --
    -- Returns { ok = true }, or { ok = false, reason = 'busy'|'bad-request'|...,
    -- holderLabel = <who is mid-act> }. Treat 'busy' as a HOLD, not a failure --
    -- and holding attempted nothing, so it must not arm your retry lockout.
    function S.act.request(req)
        req = (type(req) == 'table') and req or {};
        local as = svc('dlac\\feature\\actionseq');
        if as == nil or type(as.request) ~= 'function' then
            return { ok = false, reason = 'service' };
        end
        req.module = id;
        req.order  = S.me.order();
        local ok, res = pcall(as.request, req);
        if not ok or type(res) ~= 'table' then return { ok = false, reason = 'service' }; end
        if res.ok == true then
            -- Kick one Default so the claim applies now instead of on the next
            -- 0.4s tick; the sequencer's pump then reads the worn gear and fires.
            -- Contained -- the standing tick is the fallback.
            pcall(function()
                local dsp = require('dlac\\dispatch');
                if type(dsp) == 'table' and type(dsp.kickDefault) == 'function' then dsp.kickDefault(); end
            end);
        end
        return res;
    end

    -- Is a sequence live right now (anyone's)? One is live at a time, addon-wide,
    -- and a started one is never preempted.
    function S.act.busy()
        return ask('dlac\\feature\\actionseq', 'active', false) == true;
    end

    -- The live sequence's status text, for your Panel ('bst-helper: Reward
    -- (firing)' / 'idle (last: Reward fired)').
    function S.act.status()
        return ask('dlac\\feature\\actionseq', 'statusText', 'idle');
    end

    -- ISSUE A BARE COMMAND -- one that needs nothing worn first, like
    -- `/pet "Fight" <t>`. THE central auto-issue door: it queues on the frame
    -- clock and leaves on the main thread.
    --
    -- Do not open a sequence for a bare command; you would be taking the one
    -- shared claim slot for nothing. And note two facts the queue exists for:
    -- two commands issued in the SAME frame arrive reversed in other Lua states,
    -- and an addon state never hears its own queued commands back -- so if two of
    -- yours must arrive in order, give them different frames.
    function S.cmd(command)
        return ask('dlac\\lib\\cmdqueue', 'issue', false, command) == true;
    end

    -- ----- settings + UI --------------------------------------------------

    -- Your settings store, or nil when you declared no `config` block. The
    -- framework owns the FORMAT (fmt-versioned, declared keys only, written on
    -- mutation, tolerant reader, never caches the pre-login nil); you own the
    -- keys. See feature\modcfg.
    S.cfg = rec.cfg;

    -- ----- keys -----------------------------------------------------------
    --
    -- YOU DO NOT BIND KEYS. Declare a `commands` block whose entry names one of
    -- your own config keys (`key = 'summonKey'`) and the framework installs the
    -- whole group through the one registry (feature\keybinds) -- job-scoped, so
    -- your key exists while the player is on your job with your pill on and
    -- comes back to them the moment they switch. The owner id and the command
    -- string are the framework's, for the reason S.act.request fills in your
    -- module id: so a module cannot claim a key as somebody else.
    --
    -- These are the two READS a Panel needs to render a key field honestly.
    S.keys = {};

    -- The key this module's action holds right now, as the player typed it, or
    -- nil when it holds none (not configured, wrong job, pill off).
    function S.keys.boundTo(action)
        local kb = svc('dlac\\feature\\keybinds');
        if kb == nil or type(kb.heldBy) ~= 'function' then return nil; end
        local held = nil;
        pcall(function() held = kb.heldBy(string.format('jobhelper:%s:%s', id, tostring(action))); end);
        if type(held) ~= 'table' then return nil; end
        return held.raw or held.key;
    end

    -- Who holds a key -- { owner, label, command } or nil for "free". Ask before
    -- you save a key the player typed: the registry REFUSES a second claim, so
    -- a Panel that does not ask lets them save a key that will never fire.
    function S.keys.holder(key)
        local kb = svc('dlac\\feature\\keybinds');
        if kb == nil or type(kb.holder) ~= 'function' then return nil; end
        local held = nil;
        pcall(function() held = kb.holder(key); end);
        if type(held) ~= 'table' then return nil; end
        return held;
    end

    -- The Panel widget kit, UNBOUND (every function takes an imgui handle first).
    -- Your `panel(ctx)` is handed `ctx.ui`, the same kit already bound to the
    -- host's handle -- use that; it is the one that renders under the test stub.
    S.ui = svc('dlac\\ui\\panelkit');

    -- ----- compatibility --------------------------------------------------
    --
    -- The api = 1 shape, retained so the two keys it actually carried still
    -- resolve. Nothing new should reach for these.
    S.host       = rec.host;
    S.jobhelpers = svc('dlac\\feature\\jobhelpers');

    return S;
end

return M;
