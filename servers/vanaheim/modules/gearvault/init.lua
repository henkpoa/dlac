--[[
    vanaheim/gearvault -- the Gear Vault integration's mount (ADR 0035 pack
    module; design: docs/design/gear-vault-integration.md). Slice 1: the
    0x1E0 wire client + the read-only vault MIRROR, published to core as the
    serverpack service 'gearvault' -- which is how vaulted gear becomes an
    ownership tier (GV5) without core ever requiring a servers\ path.

    This init owns only the Ashita glue: the packet_in tap (0x1E0 frames to
    the client, 0x00A as the zone probe trigger), the outgoing `!vault` chat
    watch, the module pump (per the servermods contract), the `/dl vault`
    status command, and the service registration. Every rule and every byte
    lives in vaultclient.lua, which runs headless.
]]--

local base = 'dlac\\servers\\vanaheim\\modules\\gearvault\\';

local vc  = require(base .. 'vaultclient');
local drv = require(base .. 'derive');
local rec = require(base .. 'reconcile');

-- Production seams -----------------------------------------------------------

vc._send = function(p)
    pcall(function() AshitaCore:GetPacketManager():AddOutgoingPacket(vc.PKT, p); end);
    pcall(function() require('dlac\\feature\\sendlog').note(vc.PKT, 'gear vault'); end);
end;

vc._say = function(msg)
    local ok, cf = pcall(require, 'dlac\\chatfmt');
    if ok and type(cf) == 'table' and type(cf.print) == 'function' then
        cf.print('[dlac] ' .. tostring(msg));
    else
        print('[dlac] ' .. tostring(msg));
    end
end;

-- A fresh mirror changes ownership answers NOW, not at the next ~4s
-- availability heartbeat.
vc._onFresh = function()
    pcall(function() require('dlac\\gear\\ownedcache').resetCache(); end);
end;

-- The service core consults (gearimport's vault fold, prune's guard, and
-- slice 2's tab). counts()/rows() hand out the live tables -- consumers
-- read, never write (the ownedcache _splitOverride discipline).
pcall(function()
    require('dlac\\gear\\serverpack').provide('gearvault', {
        counts     = function() return vc.mirror.counts; end,
        rows       = function() return vc.mirror.rows; end,
        vaultCount = function() return vc.mirror.vaultCount; end,
        fresh      = function() return vc.mirror.fresh == true; end,
        state      = vc.state,
        refresh    = vc.refresh,
        statusLine = vc.statusLine,
        cityBlocked = function() return rec.cityBlocked(); end,
    });
end);

-- Ashita glue (all guarded: headless there is no ashita global) ---------------

pcall(function()
    ashita.events.register('packet_in', 'dlac_gearvault_packet_in', function(e)
        if e.id == 0x00A then
            vc.noteZoneIn();
            rec.zoneArmed();   -- a city-blocked push may retry where we landed
            return;
        end
        if e.id ~= vc.PKT then return; end
        local ok, consumed = pcall(function()
            return vc.onFrame(vc.parseFrame(e.data_modified or e.data));
        end);
        -- The retail client has no idea what 0x1E0 is: block every vault-
        -- partition frame we recognised so it never reaches the game.
        if ok and consumed == true then e.blocked = true; end
    end);
end);

-- `!vault ...` in the player's own chat may mutate the store (the chat skin
-- shares the service with our packets) -- resync after it settles. Watch the
-- OUTGOING command, the eboxclient's `!box` idiom.
pcall(function()
    ashita.events.register('command', 'dlac_gearvault_chatwatch', function(e)
        local raw = string.lower(tostring(e.command or ''));
        if raw:match('^/?!vault') or raw:match('^!vault') then
            vc.noteVaultChat();
        end
    end);
end);

-- `/dl vault` -- the field probe: state, mirrored count, a `sync` verb, and
-- `why <name>` (defined below, forward-declared here -- a local referenced
-- before declaration is a silent nil global, hard rule 8). Registered like
-- every module command (the giftbox pattern); gearui's /dl dispatch never
-- learns vault words.
local vaultWhy;
pcall(function()
    ashita.events.register('command', 'dlac_gearvault_cmd', function(e)
        local raw = tostring(e.command or '');
        local rest = string.lower(raw):match('^/dl%s+vault%s*(.*)$');
        if rest == nil then return; end
        e.blocked = true;
        if rest:match('^sync') then
            vc.refresh();
            vc.requestLayout(0);
            vc._say('gear vault: sync requested.');
        elseif rest:match('^why%s+%S') then
            -- take the name from the RAW command (case preserved for display;
            -- resolution is case-tolerant anyway)
            local name = raw:match('^/[dD][lL]%s+%S+%s+%S+%s+(.+)$') or rest:match('^why%s+(.+)$');
            pcall(vaultWhy, (name or ''):gsub('%s+$', ''));
        else
            vc._say(vc.statusLine());
        end
    end);
end);

-- THE TAB (slice 2): registered on the uihost like any first-party module,
-- so it renders under gearui's tabGuard (a broken tab costs itself, never
-- the frame). It exists only where this pack mounts, and shows through the
-- gear-only surface default because featuregate never hides a label it
-- cannot name (ADR 0037).
pcall(function()
    local vui  = require(base .. 'vaultui');
    local uhost = require('dlac\\ui\\uihost');
    uhost.register({
        name = 'gearvault',
        tabs = { { label = 'Gear Vault', render = function(j, lv) vui.render(j, lv); end } },
    });
end);

-- The module contract's beat: feed the client readiness + the main-job edge.
local function mainJob()
    local j = nil;
    pcall(function() j = AshitaCore:GetMemoryManager():GetPlayer():GetMainJob(); end);
    return j;
end

-- THE RECONCILE ENGINE (slice 3 -- reconcile.lua's header carries the whole
-- design). Readers live in ONE table so the engine and the `/dl vault why`
-- probe read the world through the same eyes: sets through profilesets (the
-- one sets reader -- it answers for the LIVE job unless browsing, and the
-- engine refuses to run while browsing), the trigger file through dispatch's
-- raw reader (profile tier first, legacy tier as the fallback -- the
-- two-tier law), names through the shared lookupByName service, at call
-- time.
local RD = {
    vc     = vc,
    derive = drv,
    clock  = os.clock,
    say    = function(m) vc._say(m); end,
    mainJob = mainJob,
    browsing = function()
        local b = false;
        pcall(function() b = require('dlac\\ui\\jobbrowse').active() == true; end);
        return b;
    end,
    setsRoot = function()
        local root = nil;
        pcall(function() root = require('dlac\\gear\\profilesets').getSetsRoot(); end);
        return root;
    end,
    triggers = function()
        local t = nil;
        pcall(function()
            local j = mainJob();
            local abbr = require('dlac\\gear\\jobgate').JOBS[j];
            if abbr == nil then return; end
            local prof = require('dlac\\profiles');
            local disp = require('dlac\\dispatch');
            local tt = disp.readTriggersRaw(prof.triggersPath(abbr));
            if tt == nil then tt = disp.readTriggersRaw(prof.legacyTriggersPath(abbr)); end
            t = tt;
        end);
        return t;
    end,
    resolve = function(name)
        local out = nil;
        pcall(function()
            local S = require('dlac\\ui\\uihost').services;
            if type(S.lookupByName) ~= 'function' then return; end
            local r = S.lookupByName(name);
            if type(r) == 'table' and type(r.Id) == 'number' then
                out = { id = r.Id, aug = (type(r.AugKey) == 'string' and r.AugKey ~= '') };
            end
        end);
        return out;
    end,
};
rec.configure(RD);

-- `/dl vault why <name>` -- the WHOLE chain for one item, in one screen: what
-- the mirror holds, what ownership believes, what derivation wants, what the
-- layout carries, and what the engine last did. The debugging law: when a
-- report survives one code-read, stop reading and make the engine print its
-- own evidence.
local _tickErr = nil;   -- the engine's last error, said once (hard rule 12)
vaultWhy = function(name)
    local out = {};
    local function line(s) out[#out + 1] = s; end
    local r = RD.resolve(name);
    if r == nil then
        line(string.format('why "%s": dlac cannot resolve that name (gear.lua / catalog spelling?).', name));
    else
        line(string.format('why "%s": id %d%s', name, r.id, r.aug and ' (augment-pinned record: derivation skips it -- use + Layout)' or ''));
        local held, zerocnt = 0, 0;
        for _, row in ipairs(vc.mirror.rows) do
            if row.itemId == r.id then
                held = held + math.max(1, row.qty);
                if row.identity == vc.ZERO24 then zerocnt = zerocnt + 1; end
            end
        end
        line(string.format('  mirror [%s]: %d instance(s) of it in the vault (%d plain, %d augmented/signed)',
            vc.state(), held, zerocnt, held - zerocnt));
        pcall(function()
            local oc = require('dlac\\gear\\ownedcache');
            local rec2 = { Id = r.id };
            local w = oc.whereOf(r.id);
            local homes = {};
            if type(w) == 'table' then
                local gi = require('dlac\\gear\\gearimport');
                for cid, n in pairs(w) do homes[#homes + 1] = gi.containerName(cid) .. ' x' .. n; end
                table.sort(homes);
            end
            line(string.format('  ownership: verdict=%s stored=%s vaulted=%s  where: %s',
                oc.verdict(rec2, true), tostring(oc.isStored(rec2)), tostring(oc.isVaulted(rec2)),
                (#homes > 0) and table.concat(homes, ', ') or '(nowhere)'));
        end);
        local d = drv.derive(RD.setsRoot(), RD.triggers(), RD.resolve);
        local want = 0;
        for _, it in ipairs(d.items) do if it.itemId == r.id then want = it.count; end end
        line(string.format('  derived: this job wants %d of it (%d items total, %d aug-skipped, %d unresolved)',
            want, #d.items, d.skippedAug, #d.unresolved));
        local lc = vc.layoutCache;
        local inLayout = 0;
        for _, e in ipairs(lc.entries or {}) do
            if e.itemId == r.id then inLayout = inLayout + e.count; end
        end
        line(string.format('  layout [job %s, %s]: carries %d of it',
            tostring(lc.job), lc.fresh and 'fresh' or 'STALE', inLayout));
        if inLayout > 0 and held > 0 then
            line('  NOTE: the layout names it and the vault holds it -- the SHELF catches up at the');
            line('  next job change or live layout edit (a deposit alone does not trigger an apply).');
        end
    end
    local rst = rec._st();
    line(string.format('  engine: cityBlocked=%s lastPushKey=%s%s',
        tostring(rec.cityBlocked()), rst.lastPushKey and 'set' or 'none',
        _tickErr ~= nil and ('  LAST ERROR: ' .. _tickErr) or ''));
    for _, s in ipairs(out) do vc._say(s); end
end

return {
    pump = function()
        local j = mainJob();
        local ready = (type(j) == 'number' and j ~= 0);
        if ready then vc.noteJob(j); end
        vc.pump(ready);
        if ready then
            -- A silently-dead engine looks exactly like "nothing happened"
            -- (hard rule 12): one loud line per DISTINCT error, and the
            -- probe carries it too.
            local ok, err = pcall(rec.tick);
            if not ok then
                err = tostring(err);
                if err ~= _tickErr then
                    _tickErr = err;
                    vc._say('gear vault: the layout engine errored: ' .. err .. ' -- please report this line.');
                end
            end
        end
    end,
};
