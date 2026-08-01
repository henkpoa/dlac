--[[
    dlac/lib/dlacclaim.lua -- THE CLIENT SHIM for dlac's external-claim channel.
    2026-08-01, protocol v1.

    THIS FILE IS FOR OTHER PEOPLE'S ADDONS -- the ONE file in dlac written to be
    loaded from a FOREIGN Lua state. Everything else in `lib\` is dlac's own
    internal plumbing and carries no promises; this file is a published
    interface and changes like one. Nothing in dlac requires it.

    Load it from your own addon and you never have to know the wire format:

        local ok, mk = pcall(loadfile,
            AshitaCore:GetInstallPath() .. 'addons\\dlac\\lib\\dlacclaim.lua');
        local dlac = (ok and mk ~= nil) and mk().new({
            id    = 'myaddon',              -- your identity AND your lease
            label = 'My Addon',             -- what the player reads in dlac's UI
            ttl   = 10,                     -- seconds; the shim renews for you
        }) or nil;

        dlac.onAck     = function(t) end    -- every reply to something you sent
        dlac.onVerdict = function(d) end    -- d.lost = { Slot = 'WhoBeatYou' }
        dlac.onExpired = function(d) end    -- your claim is gone; d.reason says why

        dlac:hello();                        -- is dlac there, is the switch on
        dlac:claim({ Head = 'Walahra Turban', Ammo = 'remove' });
        ...
        dlac:release();

        ashita.events.register('d3d_present', 'myaddon_dlac', function()
            dlac:pump();                     -- REQUIRED: renews the lease
        end);

    FOUR THINGS TO KNOW, all of them consequences of dlac's design rather than
    this shim's:

      1. YOUR CLAIM IS A LEASE. Stop calling pump() -- crash, unload, forget --
         and dlac drops your claim within `ttl` seconds. That is the point: an
         addon that dies must not leave the player's gear stuck, with no clue
         which addon to blame.

      2. YOU ARE NOT THE ONLY CLAIMANT. dlac's Arbiter settles your claim against
         the player's pins, locks, ammo rule, MP batteries, craft/fishing gear
         and trigger sets, by a rank order THE PLAYER controls. Being accepted
         is not being worn. `onVerdict` tells you which slots you lost and to
         whom; watching the `dlac_worn` stream (see the integration guide) tells
         you what is actually on.

      3. THE PLAYER OWNS THE SWITCH. Everything is silent until they type
         `/dl claims on`. `hello` is answered even when it is off, precisely so
         your UI can say "dlac is here, claims are off" instead of failing
         quietly. Never nag; never re-file a claim the player turned off.

      4. CLAIM, NEVER COMMIT. There is no writer here for sets, triggers, modes
         or lockstyles, and there will not be one. A claim is temporary and
         session-only by construction.

    Pure Lua 5.1/LuaJIT, no dependencies beyond Ashita's own globals.
]]--

local M = {};

M.PROTOCOL = 1;
M.EVENT    = 'dlac_claim';

-- ---------------------------------------------------------------------------
-- Wire format: a Lua source string, sent as a BYTE TABLE. Both halves are
-- probe-verified (2026-07-28): the binding refuses a plain string on SEND, and
-- the receiver gets the bytes reassembled as a string under `e.data`.
-- ---------------------------------------------------------------------------
local function ser(v, depth)
    depth = depth or 0;
    local t = type(v);
    if t == 'number' then return string.format('%.14g', v);
    elseif t == 'boolean' then return tostring(v);
    elseif t == 'string' then return string.format('%q', v);
    elseif t ~= 'table' or depth > 7 then return 'nil'; end
    local out, inArray = {}, {};
    for i = 1, #v do out[#out + 1] = ser(v[i], depth + 1); inArray[i] = true; end
    local keys = {};
    for k in pairs(v) do
        if inArray[k] ~= true and (type(k) == 'string' or type(k) == 'number') then
            keys[#keys + 1] = k;
        end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b); end);
    for _, k in ipairs(keys) do
        local kk = (type(k) == 'string' and string.match(k, '^[%a_][%w_]*$') ~= nil)
                   and k or ('[' .. ser(k, depth + 1) .. ']');
        out[#out + 1] = kk .. ' = ' .. ser(v[k], depth + 1);
    end
    return '{ ' .. table.concat(out, ', ') .. ' }';
end
M.serialize = ser;

local function toBytes(s)
    local t = {};
    for i = 1, #s do t[i] = string.byte(s, i); end
    return t;
end

-- Decode an inbound envelope. Defensive about the payload field on purpose:
-- `e.data` is the verified fast path, the rest costs nothing and survives an
-- Ashita that changes its mind.
function M.decode(e)
    local raw = nil;
    pcall(function() raw = e.data or e.payload or e.eventData; end);
    local s = (type(raw) == 'string') and raw or nil;
    if s == nil and type(raw) == 'table' then
        local b = {};
        for i = 1, #raw do b[i] = string.char(raw[i]); end
        s = table.concat(b);
    end
    if type(s) ~= 'string' or s == '' then return nil; end
    local chunk = (loadstring or load)(s);
    if chunk == nil then return nil; end
    local ok, t = pcall(chunk);
    return (ok and type(t) == 'table') and t or nil;
end

-- ---------------------------------------------------------------------------
-- The client object.
-- ---------------------------------------------------------------------------
local Client = {};
Client.__index = Client;

-- new{ id, label, prio, ttl, reply, autoRegister }
--   id     REQUIRED. Your addon's identity; also the key of your lease.
--   label  what a player sees in /dl claims list and dlac's Claim Priority row.
--   prio   settles ties against OTHER external addons only (higher wins). It has
--          no bearing on dlac's own claimants -- that is the player's rank order,
--          and yours to respect, not to outrank.
--   ttl    lease seconds (dlac clamps to 1..300; it tells you if it clamped).
--   reply  your private reply channel; defaults to the id. Must be unique.
function M.new(opts)
    opts = (type(opts) == 'table') and opts or {};
    local id = tostring(opts.id or '');
    if id == '' then error('dlacclaim.new: id is required', 2); end
    local c = setmetatable({
        id       = id,
        label    = opts.label or id,
        prio     = tonumber(opts.prio) or 0,
        ttl      = tonumber(opts.ttl) or 10,
        reply    = tostring(opts.reply or id),
        -- live state, all read-only to you
        present  = nil,        -- nil = never answered; true/false = dlac is/is not there
        enabled  = nil,        -- is the player's /dl claims switch on
        held     = false,      -- do we believe we hold a claim right now
        slots    = nil,        -- what we last successfully claimed
        lost     = {},         -- Slot -> claimant that beat us (from onVerdict)
        lastErr  = nil,
        _next    = 0,          -- next heartbeat clock
    }, Client);

    if opts.autoRegister ~= false then
        pcall(function()
            ashita.events.register('plugin_event', 'dlacclaim_' .. id, function(e)
                local nm = nil;
                pcall(function() nm = e.name; end);
                if tostring(nm or '') ~= (c.reply .. '_r') then return; end
                local t = M.decode(e);
                if t ~= nil then pcall(c.onEnvelope, c, t); end
            end);
        end);
    end
    return c;
end

function Client:_send(tbl)
    tbl.v = M.PROTOCOL;
    tbl.id = self.id;
    tbl.reply = self.reply;
    local src = 'return ' .. ser(tbl);
    return pcall(function()
        AshitaCore:GetPluginManager():RaiseEvent(M.EVENT, toBytes(src));
    end);
end

-- The one inbound funnel. Keeps `present`/`enabled`/`held` honest, then hands
-- the envelope to your callbacks. Override the callbacks, not this.
function Client:onEnvelope(t)
    self.present = true;
    local what = tostring(t.what or '');
    local data = (type(t.data) == 'table') and t.data or {};

    if what == 'hello' then
        self.enabled = (data.on == true);
        self.dlacVersion = data.dlac;
        self.protocol = data.protocol;
    elseif what == 'claim' then
        if t.ok then
            self.enabled, self.held, self.slots = true, true, data.slots;
            self.ttl = tonumber(data.ttl) or self.ttl;
            self.lost = {};
            self:_arm();
        else
            self.held = false;
        end
    elseif what == 'release' then
        self.held, self.slots, self.lost = false, nil, {};
    elseif what == 'heartbeat' then
        if t.ok then self:_arm(); else self.held = false; end
    elseif what == 'expired' then
        -- dlac dropped us: the lease lapsed, the player switched claims off, or
        -- we logged out. `data.on` is the SWITCH state, sent explicitly so you
        -- never have to infer permission from the reason string -- a logout
        -- clears every claim but leaves the permission standing, and those two
        -- want different responses.
        self.held, self.slots, self.lost = false, nil, {};
        if data.on ~= nil then self.enabled = (data.on == true); end
        -- We do NOT re-file automatically. Re-claiming through a switch the
        -- player just turned off is the behaviour that gets an addon
        -- uninstalled; and after a logout you want to re-claim when YOUR
        -- feature's conditions are met again, not blindly at character select.
        if type(self.onExpired) == 'function' then pcall(self.onExpired, data); end
    elseif what == 'verdict' then
        self.lost = (type(data.lost) == 'table') and data.lost or {};
        if type(self.onVerdict) == 'function' then pcall(self.onVerdict, data); end
    end

    if t.ok == false then
        self.lastErr = t.err;
        if tostring(t.err or '') == 'external claims are off' then self.enabled = false; end
    end
    if type(self.onAck) == 'function' then pcall(self.onAck, t); end
end

function Client:_arm()
    local ok, now = pcall(os.clock);
    if not ok then return; end
    -- Renew at a THIRD of the lease: one lost frame or one dropped broadcast
    -- must never cost the claim, and three chances before expiry is cheap.
    self._next = now + math.max(1, (tonumber(self.ttl) or 10) / 3);
end

-- ---------------------------------------------------------------------------
-- The verbs.
-- ---------------------------------------------------------------------------

-- Ask whether dlac is present and whether the player has claims switched on.
-- Answered even when the switch is off. Call this at load; if nothing comes
-- back at all, dlac is not installed (or not loaded yet -- ask again later).
function Client:hello() return self:_send({ what = 'hello' }); end

-- File (or REPLACE) your whole claim. slots = { Head = 'Item Name', ... }, and
-- 'remove' as an item claims the slot EMPTY. Replaces, never merges: one
-- claimant, one claim -- send the full table every time.
function Client:claim(slots)
    return self:_send({ what = 'claim', slots = slots,
                        prio = self.prio, ttl = self.ttl, label = self.label });
end

-- Give the slots back. Always call this when your reason for holding them ends;
-- the lease is the backstop for crashes, not the normal path.
function Client:release() return self:_send({ what = 'release' }); end

function Client:heartbeat() return self:_send({ what = 'heartbeat' }); end

-- What dlac thinks you hold, plus every other addon holding a claim.
function Client:status() return self:_send({ what = 'status' }); end

-- Call every frame (d3d_present). Renews the lease while you hold a claim and
-- does nothing at all otherwise -- no polling, no traffic when idle.
function Client:pump()
    if not self.held then return; end
    local ok, now = pcall(os.clock);
    if not ok or now < (self._next or 0) then return; end
    self:_arm();
    self:heartbeat();
end

M.Client = Client;
return M;
