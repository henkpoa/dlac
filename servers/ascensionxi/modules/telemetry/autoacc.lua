--[[
    ascensionxi/telemetry/autoacc -- AutoAcc v1 on AscensionXI: may a piece
    typed AutoAcc give its slot to its fallback, with the hit rate still at
    the cap? Answered locally from the latest combat telemetry frame and
    dlac's own gear data (docs/design/ascensionxi-combat-telemetry-autoacc.md;
    server research sections 2.2, 2.13 and 3.3). Served to core as the
    serverpack service 'autoacc'; dispatch.lua asks decide() at the single
    send of a Default dispatch.

    The model. A frame taken in outfit S carries, for every gear-movable
    input, its live total and its value without gear (R). For an outfit P:
        X(P) = live + plain(P) - plain(S) + set(P) - set(S) + level(P) - level(S)
    where plain is the catalog's item stats, set the set-bonus tiers and
    level the level-scaling latents, all from dlac's data. Conditional
    latents stay inside the frame's numbers, so a piece that differs between
    S and P may not carry one on a hit-rate stat (it is unmodelled until
    issue #41 teaches the conditions). The formula then composes X(P).

    Every frame is checked before it decides anything:
      * the formula: composing its live totals gives its LiveAcc and
        ThresholdBp exactly (formula.check);
      * the gear: live - R equals dlac's plain + set sum for the outfit its
        EquipRev names. A mismatch marks that outfit's pieces unverified, and
        an unverified piece is never released.

    Frames that differ only in the outfit share the server's comparison key
    (wire.snapshotKey), so each of them can speak for the others' outfits:
    every frame of the current key that passes both checks is a BASIS, and a
    decision uses the newest basis whose outfit differs from the plan only in
    modelled, verified pieces. A weapon skill's outfit, worn for a second,
    therefore never costs the standing set its frame. A new key starts over;
    when no basis fits, dlac asks the server once for a frame taken in the
    outfit worn now (RESYNC republish).

    A piece is released only when a basis fits (LIVE for the battle target,
    both checks pass, no GEAR_REFILL), no conservative trigger is up, the
    piece and its fallback are modelled, the slot is armour (Head..Back), its
    enchantment is not up (EnchantedSlotMask), and every protected context
    (main, off hand, kick) still reaches the cap with the whole proposal.
    Removal priority decides the order; unknown stays on.

    The conservative triggers (research 3.3) hold every piece on until the
    next frame: a new target, a level or job change, gaining Blindness,
    Accuracy Down or Flash, and losing an effect that adds accuracy
    (ACC_EFFECTS). Losing any other effect keeps the decision: had it moved a
    published input, the server's next frame would follow within a tick. A
    listed loss that brings no frame within LOSS_SETTLE moved nothing either,
    and is let go.

    Demand: decide() tells the client a decision is wanted, and the worn
    outfit is sampled only while one is (IDLE_AFTER), so a player without
    AutoAcc pieces runs none of this.
]]--

local base = 'dlac\\servers\\ascensionxi\\modules\\telemetry\\';
local wire = require(base .. 'wire');
local formula = require(base .. 'formula');

local M = {
    MARGIN    = 0,    -- ACC a proposal must keep above what reaches the cap
    RING      = 8,    -- recent outfits a frame may name, and bases kept per key
    WORN_EVERY = 0.25, -- seconds between reads of the worn outfit
    PLAYER_EVERY = 0.1, -- seconds a read of jobs, buffs and target is reused
    LOSS_SETTLE = 2.0, -- seconds a listed effect's loss holds without a frame
    ASK_AGAIN = 10,   -- seconds before the same outfit's republish is asked again
    IDLE_AFTER = 300, -- seconds after the last decision that the outfit is still sampled
    FIRST_ARMOUR = 4, -- Head: equip slots 4..15 may be released in v1
    PROTECTED = { [0] = true, [1] = true, [2] = true },   -- main hand, off hand, kick
};

M._clock = os.clock;
M._worn = nil;      -- () -> refs[0..15] = { container, slot, itemId, augmented } as worn now
M._player = nil;    -- () -> { mainJob, mainLevel, subJob, subLevel, buffs = { [id] = true }, target = server id }
M._record = nil;    -- (itemId) -> catalog record { Id, Name, Level, Stats, RSlot }
M._idOf = nil;      -- (item name) -> item id
M._data = nil;      -- () -> { gearsets?, levelscaling, latentstats, itemscripts }
M._want = nil;      -- () a decision is wanted (the client keeps its session)
M._ask = nil;       -- (kind) 'republish': a frame in the outfit worn now; 'renew': what landed

-- Equip slot ids by the names dispatch's plans use (gear/equipcore.lua order).
M.SLOTS = { Main = 0, Sub = 1, Range = 2, Ammo = 3, Head = 4, Body = 5, Hands = 6, Legs = 7, Feet = 8,
            Neck = 9, Waist = 10, Ear1 = 11, Ear2 = 12, Ring1 = 13, Ring2 = 14, Back = 15 };

-- dlac's catalog keys for the server's gear-movable inputs.
local INPUT_STAT = { dex = 'DEX', agi = 'AGI', accMod = 'Accuracy', raccMod = 'RangedAccuracy',
                     wsAccMod = 'WeaponSkillAccuracy' };
local INPUTS = { 'dex', 'agi', 'accMod', 'raccMod', 'twoHandAccMod', 'wsAccMod' };
local SKILL_STAT = { [1] = 'HandToHandSkill', [2] = 'DaggerSkill', [3] = 'SwordSkill', [4] = 'GreatSwordSkill',
                     [5] = 'AxeSkill', [6] = 'GreatAxeSkill', [7] = 'ScytheSkill', [8] = 'PolearmSkill',
                     [9] = 'KatanaSkill', [10] = 'GreatKatanaSkill', [11] = 'ClubSkill', [12] = 'StaffSkill',
                     [25] = 'ArcherySkill', [26] = 'MarksmanshipSkill', [27] = 'ThrowingSkill' };
local HIT_STATS = { DEX = true, AGI = true, Accuracy = true, RangedAccuracy = true, WeaponSkillAccuracy = true };
for _, key in pairs(SKILL_STAT) do HIT_STATS[key] = true; end

-- Status ids whose gain lowers accuracy (Blindness, Accuracy Down, Flash).
M.ACC_DEBUFFS = { [5] = true, [146] = true, [156] = true };

-- Status ids whose loss can lower a melee accuracy input (DEX, ACC, a combat
-- skill) on AscensionXI: food, the accuracy songs, the playable jobs'
-- accuracy abilities, item and weapon effects, trust and Grounds of Valor
-- auras, and the custom Monk Resonance (server modules/custom/lua/
-- mnk_mantra.lua). A new server effect that adds accuracy belongs here.
M.ACC_EFFECTS = {
    [58] = true,  [59] = true,                   -- Aggressor, Focus
    [81] = true,  [120] = true, [90] = true,     -- DEX Boost, DEX Boost II, Accuracy Boost
    [162] = true,                                -- Enchantment (an item's use)
    [199] = true, [215] = true,                  -- Madrigal, Etude
    [251] = true,                                -- Food
    [270] = true, [271] = true, [272] = true, [273] = true,   -- Aftermath
    [275] = true,                                -- Auspice
    [320] = true,                                -- Hunter's Roll
    [375] = true,                                -- Building Flourish
    [783] = true, [810] = true,                  -- Prowess (ACC/RACC), trust ACC aura
    [817] = true,                                -- Resonance (Monk Mantra)
};

local st;

function M.reset()
    st = {
        latest = nil, latestAt = nil,  -- the newest frame
        key = nil,                -- its comparison key
        bases = {}, baseOrder = {},   -- EquipRev -> { frame, outfit } of the key, oldest first
        why = 'no telemetry yet', -- the newest frame's verdict; nil when it became a basis
        gearOk = false, formulaOk = false, mismatch = nil,
        at = nil,                 -- the player state when the newest frame arrived
        effectsAt = nil,          -- when a listed effect's loss was first seen
        asked = {},               -- worn EquipRev -> when its republish was asked (this key)
        ring = {}, ringOrder = {}, wornAt = nil, wornHash = nil,
        unverified = {},          -- itemId -> the input that did not match
        rev = 0,                  -- what dispatch folds into its retrace signature
        memo = nil,               -- the last decision and its key
        lastDecision = nil, lastBasis = nil,
        wantedAt = nil,           -- the last decide()
        player = nil, playerAt = nil,
        vectors = {},             -- itemId -> stat vector (catalog facts never change)
    };
end
M.reset();

local function bump() st.rev = st.rev + 1; st.memo = nil; end

-- ---------------------------------------------------------------------------
-- Gear facts
-- ---------------------------------------------------------------------------

local function data()
    local ok, d = pcall(function() return type(M._data) == 'function' and M._data() or nil; end);
    return (ok and type(d) == 'table') and d or {};
end

-- The stat vector of an item: what it adds to each input and skill, and HP.
local function vectorOf(itemId)
    if itemId == nil or itemId == 0 then return nil; end
    local v = st.vectors[itemId];
    if v ~= nil then return v or nil; end
    local rec = type(M._record) == 'function' and M._record(itemId) or nil;
    if type(rec) ~= 'table' then st.vectors[itemId] = false; return nil; end
    local s = type(rec.Stats) == 'table' and rec.Stats or {};
    v = { id = itemId, name = rec.Name, level = tonumber(rec.Level) or 0, rslot = rec.RSlot,
          twoHandAccMod = 0, skills = {}, hp = tonumber(s.HP) or 0 };
    for input, key in pairs(INPUT_STAT) do v[input] = tonumber(s[key]) or 0; end
    for skill, key in pairs(SKILL_STAT) do
        local n = tonumber(s[key]);
        if n ~= nil and n ~= 0 then v.skills[skill] = n; end
    end
    st.vectors[itemId] = v;
    return v;
end
M._vectorOf = vectorOf;

-- Why a piece cannot be modelled, or nil when it can. augmented: this copy
-- carries augments (v1 models catalog stats only).
local function unmodelled(itemId, augmented)
    if itemId == nil or itemId == 0 then return nil; end    -- an empty slot is exact
    local v = vectorOf(itemId);
    if v == nil then return 'not in the catalog'; end
    local d = data();
    local scripts = d.itemscripts;
    if type(scripts) == 'table' and scripts[itemId] ~= nil and scripts[itemId] ~= 'neutral' and scripts[itemId] ~= 'enchant' then
        return 'an equip script dlac does not model';
    end
    local latents = type(d.latentstats) == 'table' and d.latentstats[itemId] or nil;
    if type(latents) == 'table' then
        for _, row in ipairs(latents) do
            if HIT_STATS[row.stat] then return 'an accuracy latent (' .. tostring(row.cond) .. ')'; end
        end
    end
    if v.rslot ~= nil and v.rslot ~= 0 then return 'it covers another slot'; end
    if augmented then return 'augmented'; end
    return nil;
end
M._unmodelled = unmodelled;

-- Level-scaling latents active at a level (they depend on nothing else).
local function levelRows(itemId, level, out)
    local rows = data().levelscaling;
    rows = type(rows) == 'table' and rows[itemId] or nil;
    if type(rows) ~= 'table' then return; end
    for _, r in ipairs(rows) do
        local on = (r.from ~= nil and level >= r.from) or (r.below ~= nil and level < r.below);
        if on then out[r.stat] = (out[r.stat] or 0) + (tonumber(r.add) or 0); end
    end
end

-- The set bonuses of an outfit at a level: { statKey = n } (the server's rule:
-- per slot, level-gated, tiers replace).
local function setBonus(ids, level)
    local sets = data().gearsets;
    if type(sets) ~= 'table' then return {}; end
    local count = {};
    for slot = 0, 15 do
        local id = ids[slot];
        local v = vectorOf(id);
        if v ~= nil and v.level <= level then
            for sid, e in pairs(sets) do
                if type(e.pieces) == 'table' then
                    for _, pid in ipairs(e.pieces) do
                        if pid == id then count[sid] = (count[sid] or 0) + 1; break; end
                    end
                end
            end
        end
    end
    local out = {};
    for sid, n in pairs(count) do
        local e = sets[sid];
        if n >= (e.min or 2) then
            local tier = e.tiers and e.tiers[math.min(n, e.max or n)];
            if type(tier) == 'table' then
                for k, x in pairs(tier) do out[k] = (out[k] or 0) + (tonumber(x) or 0); end
            end
        end
    end
    return out;
end

-- What an outfit adds to every input: plain stats, set bonus, level latents.
-- ids[0..15] = item id or 0.
local function gearSums(ids, level, withLevel)
    local sum = { skills = {}, hp = 0 };
    for _, k in ipairs(INPUTS) do sum[k] = 0; end
    local lvl = {};
    for slot = 0, 15 do
        local v = vectorOf(ids[slot]);
        if v ~= nil then
            for _, k in ipairs(INPUTS) do sum[k] = sum[k] + (v[k] or 0); end
            for skill, n in pairs(v.skills) do sum.skills[skill] = (sum.skills[skill] or 0) + n; end
            sum.hp = sum.hp + v.hp;
            if withLevel then levelRows(v.id, level, lvl); end
        end
    end
    local set = setBonus(ids, level);
    for input, key in pairs(INPUT_STAT) do
        sum[input] = sum[input] + (set[key] or 0) + (lvl[key] or 0);
    end
    for skill, key in pairs(SKILL_STAT) do
        local n = (set[key] or 0) + (lvl[key] or 0);
        if n ~= 0 then sum.skills[skill] = (sum.skills[skill] or 0) + n; end
    end
    return sum;
end
M._gearSums = gearSums;

-- ---------------------------------------------------------------------------
-- The ring of recent outfits: a frame names its outfit by hash.
-- ---------------------------------------------------------------------------

local function rememberWorn(force)
    local t = M._clock();
    if not force and st.wornAt ~= nil and t - st.wornAt < M.WORN_EVERY then return st.wornHash; end
    st.wornAt = t;
    local refs = type(M._worn) == 'function' and M._worn() or nil;
    if type(refs) ~= 'table' then return nil; end
    local hash = wire.outfitHash(refs);
    st.wornHash = hash;
    if st.ring[hash] == nil then
        local ids, aug = {}, {};
        for slot = 0, 15 do
            local r = refs[slot];
            ids[slot] = (type(r) == 'table' and tonumber(r[3])) or 0;
            aug[slot] = type(r) == 'table' and r[4] == true or nil;
        end
        st.ring[hash] = { ids = ids, aug = aug };
        st.ringOrder[#st.ringOrder + 1] = hash;
        if #st.ringOrder > M.RING then st.ring[table.remove(st.ringOrder, 1)] = nil; end
    end
    return hash;
end

-- ---------------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------------

-- Jobs, levels, buffs and the battle target, read at most every PLAYER_EVERY
-- (the readout and two calls per dispatch ask). fresh: read now.
local function playerNow(fresh)
    local t = M._clock();
    if not fresh and st.player ~= nil and st.playerAt ~= nil and t - st.playerAt < M.PLAYER_EVERY then
        return st.player;
    end
    local ok, p = pcall(function() return type(M._player) == 'function' and M._player() or nil; end);
    p = (ok and type(p) == 'table') and p or {};
    st.player, st.playerAt = p, t;
    return p;
end

local function copyPlayer(p)
    local out = { buffs = {} };
    for k, v in pairs(p) do if k ~= 'buffs' then out[k] = v; end end
    for id in pairs(p.buffs or {}) do out.buffs[id] = true; end
    return out;
end

-- The gear check: live - R per input against dlac's sums for outfit S.
local function gearCheck(frame, ids)
    local sums = gearSums(ids, frame.mainLevel or 0, false);
    for _, k in ipairs(INPUTS) do
        local server = (frame[k .. 'Live'] or 0) - (frame[k .. 'R'] or 0);
        if server ~= sums[k] then return false, ('%s: the server adds %d, dlac %d'):format(k, server, sums[k]); end
    end
    for _, ctx in ipairs(frame.contexts or {}) do
        if ctx.applicability == wire.applicability.APPLICABLE then
            local server = (ctx.skillLive or 0) - (ctx.skillR or 0);
            local mine = sums.skills[ctx.skillType] or 0;
            if server ~= mine then
                return false, ('skill %d: the server adds %d, dlac %d'):format(ctx.skillType, server, mine);
            end
        end
    end
    return true;
end

local function newestBasis() return st.bases[st.baseOrder[#st.baseOrder]]; end

local function dropBases() st.bases, st.baseOrder = {}, {}; end

local function addBasis(frame, outfit)
    local hash = frame.equipRev;
    for i, h in ipairs(st.baseOrder) do
        if h == hash then table.remove(st.baseOrder, i); break; end
    end
    st.baseOrder[#st.baseOrder + 1] = hash;
    if #st.baseOrder > M.RING then st.bases[table.remove(st.baseOrder, 1)] = nil; end
    st.bases[hash] = { frame = frame, outfit = outfit };
end

-- A gear-check mismatch: dlac's numbers for this outfit are wrong somewhere.
-- Beside a verified basis of the same key (same R), the fault lies in the
-- pieces that differ from it; without one, in any piece of the outfit.
local function markUnverified(outfit, why)
    local ref = newestBasis();
    for slot = 0, 15 do
        local id = outfit.ids[slot];
        if id ~= 0 and (ref == nil or ref.outfit.ids[slot] ~= id) then st.unverified[id] = why; end
    end
end

function M.noteFrame(frame)
    st.latest, st.latestAt = frame, M._clock();
    st.at, st.effectsAt = copyPlayer(playerNow(true)), nil;
    st.formulaOk, st.gearOk, st.mismatch = false, false, nil;
    rememberWorn(true);
    bump();
    if frame.key == nil or frame.key ~= st.key then
        st.key, st.asked = frame.key, {};
        dropBases();
    end
    if frame.laneState ~= wire.laneState.LIVE then
        st.why = ('the lane is not live (state %d)'):format(frame.laneState or -1);
        dropBases();
        return;
    end
    local bad = formula.check(frame);
    if bad ~= nil then st.why = 'formula check: ' .. bad; dropBases(); return; end
    st.formulaOk = true;
    -- Inside an Onslaught run the server refills gear stats: no decision,
    -- and no gear check to mark pieces by.
    if wire.hasBit(frame.snapFlags, wire.snapFlag.GEAR_REFILL) then st.why = 'inside an Onslaught run'; dropBases(); return; end
    local outfit = st.ring[frame.equipRev];
    if outfit == nil then st.why = 'the frame names an outfit dlac did not see'; return; end
    local ok, why = gearCheck(frame, outfit.ids);
    if not ok then
        st.mismatch = why;
        markUnverified(outfit, why);
        st.why = 'gear check: ' .. why;
        return;
    end
    for slot = 0, 15 do st.unverified[outfit.ids[slot]] = nil; end
    st.gearOk, st.why = true, nil;
    addBasis(frame, outfit);
end

-- A conservative trigger since the newest frame: something the client can
-- see that may lower accuracy before the next frame (research 3.3).
local function conservative()
    local at, p = st.at or {}, playerNow();
    if p.target ~= nil and st.latest ~= nil and p.target ~= st.latest.targetId then return 'a new target'; end
    if p.mainJob ~= at.mainJob or p.mainLevel ~= at.mainLevel or p.subJob ~= at.subJob or p.subLevel ~= at.subLevel then
        return 'a level or job change';
    end
    local now, before = p.buffs or {}, at.buffs or {};
    for id in pairs(M.ACC_DEBUFFS) do
        if now[id] and not before[id] then return 'an accuracy debuff'; end
    end
    -- Any other loss keeps the decision: the frame still speaks.
    local lost = false;
    for id in pairs(before) do
        if not now[id] and M.ACC_EFFECTS[id] then lost = true; break; end
    end
    if not lost then st.effectsAt = nil; return nil; end
    local t = M._clock();
    st.effectsAt = st.effectsAt or t;
    if t - st.effectsAt < M.LOSS_SETTLE then return 'an accuracy effect wore off'; end
    -- No frame came: the loss moved nothing the server publishes. Let it go,
    -- and ask what landed in case a frame was lost on the way.
    for id in pairs(before) do if not now[id] then before[id] = nil; end end
    st.effectsAt = nil;
    if type(M._ask) == 'function' then pcall(M._ask, 'renew'); end
    return nil;
end

local function wanted(t) return st.wantedAt ~= nil and t - st.wantedAt < M.IDLE_AFTER; end

function M.pump()
    if wanted(M._clock()) then rememberWorn(false); end
end

function M.zoneChange()
    st.latest, st.key, st.why, st.asked = nil, nil, 'zoned', {};
    dropBases();
    bump();
end
M.zoneIn = M.zoneChange;

-- What dispatch folds into its retrace signature: it moves whenever an input
-- of the decision does.
function M.revision()
    local trigger = (st.latest ~= nil) and conservative() or nil;
    return tostring(st.rev) .. (trigger and ('c') or '');
end

-- ---------------------------------------------------------------------------
-- The decision (research 2.13)
-- ---------------------------------------------------------------------------

local function evaluate(frame, base, ids, level)
    local x = { skills = {} };
    local mine = gearSums(ids, level, true);
    for _, k in ipairs(INPUTS) do x[k] = (frame[k .. 'Live'] or 0) + mine[k] - base[k]; end
    local metrics, allMeet = {}, true;
    for _, ctx in ipairs(frame.contexts or {}) do
        if M.PROTECTED[ctx.kind] and ctx.applicability == wire.applicability.APPLICABLE then
            local skill = (ctx.skillLive or 0) + (mine.skills[ctx.skillType] or 0) - (base.skills[ctx.skillType] or 0);
            x.skill = skill;
            local _, eff = formula.compose(frame, ctx, x);
            local toCap = formula.accToCap(ctx, eff);
            local meets = formula.thresholdBp(ctx, eff - M.MARGIN) >= formula.capThresholdBp(ctx);
            metrics[#metrics + 1] = { kind = ctx.kind, accToCap = toCap, meets = meets };
            if not meets then allMeet = false; end
        end
    end
    return allMeet, metrics, mine;
end

-- Plans and claims spell slot names in either case.
local SLOT_BY_LOWER = {};
for name, id in pairs(M.SLOTS) do SLOT_BY_LOWER[string.lower(name)] = id; end
local function slotId(name) return SLOT_BY_LOWER[string.lower(tostring(name))]; end

local function slotValue(t, name)
    if type(t) ~= 'table' then return nil; end
    local v = t[name];
    if v == nil then
        local want = string.lower(name);
        for k, x in pairs(t) do if string.lower(tostring(k)) == want then return x; end end
    end
    return v;
end

local function planKey(req)
    local parts = {};
    for name, slot in pairs(M.SLOTS) do
        local v = slotValue(req.plan, name);
        if v ~= nil then parts[#parts + 1] = slot .. '=' .. tostring(v); end
    end
    table.sort(parts);
    for _, c in ipairs(req.candidates or {}) do
        parts[#parts + 1] = ('%s:%s>%s@%s'):format(tostring(c.slot), tostring(c.typed), tostring(c.fallback), tostring(c.prio));
    end
    return table.concat(parts, ';');
end

-- Does the outfit wear a piece whose accuracy latent reads HP or MP?
local function wearsHpLatent(ids)
    local latents = data().latentstats;
    if type(latents) ~= 'table' then return false; end
    for slot = 0, 15 do
        local rows = latents[ids[slot]];
        if type(rows) == 'table' then
            for _, row in ipairs(rows) do
                local cond = tostring(row.cond);
                if HIT_STATS[row.stat] and (cond:find('HP', 1, true) or cond:find('MP', 1, true)) then return true; end
            end
        end
    end
    return false;
end

local function nameOf(id)
    local v = vectorOf(id);
    return (v ~= nil and v.name) or ('item ' .. tostring(id));
end

local function idOf(name)
    if name == nil or name == '' or name == 'remove' then return 0; end
    local ok, id = pcall(function() return type(M._idOf) == 'function' and M._idOf(name) or nil; end);
    return ok and id or nil;
end

-- The newest basis whose outfit differs from the baseline only in modelled,
-- verified pieces; else nil and why the newest one cannot speak.
local function basisFor(ids, aug)
    local first = nil;
    for i = #st.baseOrder, 1, -1 do
        local b = st.bases[st.baseOrder[i]];
        local why = nil;
        for slot = 0, 15 do
            if ids[slot] ~= b.outfit.ids[slot] or aug[slot] ~= b.outfit.aug[slot] then
                for _, piece in ipairs({ { ids[slot], aug[slot] }, { b.outfit.ids[slot], b.outfit.aug[slot] } }) do
                    local bad = unmodelled(piece[1], piece[2]) or (st.unverified[piece[1]] and 'unverified');
                    if bad ~= nil then
                        why = ('%s differs from the frame outfit and is %s'):format(nameOf(piece[1]), bad);
                        break;
                    end
                end
            end
            if why ~= nil then break; end
        end
        if why == nil then return b; end
        first = first or why;
    end
    return nil, first;
end

-- No basis fits: ask once for a frame taken in the outfit worn now, unless
-- the newest frame already was (asking again would bring the same answer).
local function askFrame(wornHash)
    local latest = st.latest;
    if wornHash == nil or latest == nil or latest.laneState ~= wire.laneState.LIVE then return; end
    if latest.equipRev == wornHash or st.bases[wornHash] ~= nil or type(M._ask) ~= 'function' then return; end
    local t = M._clock();
    local at = st.asked[wornHash];
    if at ~= nil and t - at < M.ASK_AGAIN then return; end
    st.asked[wornHash] = t;
    pcall(M._ask, 'republish');
end

-- Is the piece's enchantment up? Any frame of the key that saw it worn in
-- the slot says so (EnchantedSlotMask is in the key, so they agree).
local function enchanted(slot, itemId)
    local bit = 2 ^ slot;
    for _, b in pairs(st.bases) do
        if b.outfit.ids[slot] == itemId and wire.hasBit(b.frame.enchantedSlotMask or 0, bit) then return true; end
    end
    local latest = st.latest;
    local outfit = latest ~= nil and st.ring[latest.equipRev] or nil;
    return outfit ~= nil and outfit.ids[slot] == itemId and wire.hasBit(latest.enchantedSlotMask or 0, bit);
end

-- req = { plan = { [slotName] = item name }, augmented = { [slotName] = true }
--         for a plan entry pinned to an augmented copy, candidates = { { slot,
--         typed, fallback, prio } }, event = dispatch kind }. Returns
-- { release = { [slotName] = fallback }, why = { [slotName] = text }, metrics }.
function M.decide(req)
    local out = { release = {}, why = {}, metrics = nil };
    local cands = req.candidates or {};
    if #cands == 0 then return out; end
    st.wantedAt = M._clock();
    if type(M._want) == 'function' then pcall(M._want); end
    local latest = st.latest;
    local trigger = (latest ~= nil) and conservative() or nil;
    local wornHash = rememberWorn(false) or st.wornHash;
    local key = planKey(req) .. '|' .. tostring(st.rev) .. '|' .. tostring(trigger) .. '|' .. tostring(wornHash);
    if st.memo ~= nil and st.memo.key == key then return st.memo.out; end
    local function hold(why)
        for _, c in ipairs(cands) do out.why[c.slot] = why; end
        st.memo, st.lastDecision, st.lastBasis = { key = key, out = out }, out, nil;
        return out;
    end
    if req.event ~= nil and req.event ~= 'Default' then return hold('only the standing Default set releases'); end
    if latest == nil then return hold(st.why or 'no telemetry yet'); end
    if trigger ~= nil then return hold('held until the next frame: ' .. trigger); end

    -- The baseline: the composed plan with every AutoAcc piece on; absent
    -- slots keep what is worn.
    local worn = st.ring[wornHash or 0];
    if worn == nil then return hold('the outfits are not known yet'); end
    local ids, aug = {}, {};
    for name, slot in pairs(M.SLOTS) do
        local v = slotValue(req.plan, name);
        if v ~= nil then
            local id = idOf(v);
            if id == nil then return hold('an item dlac cannot name: ' .. tostring(v)); end
            ids[slot] = id;
            aug[slot] = slotValue(req.augmented, name) == true or nil;
        else
            ids[slot], aug[slot] = worn.ids[slot], worn.aug[slot];
        end
    end
    for slot = 0, 15 do ids[slot] = ids[slot] or 0; end

    -- Every piece that differs between a basis's outfit and the baseline
    -- must be modelled, or that frame cannot speak for the baseline.
    local basis, whyNot = basisFor(ids, aug);
    if basis == nil then
        askFrame(wornHash);
        return hold(whyNot or st.why or 'no frame speaks for this outfit');
    end
    st.lastBasis = basis.frame;
    local frame, frameOutfit = basis.frame, basis.outfit;
    local level = frame.mainLevel or 0;

    local frameSums = gearSums(frameOutfit.ids, level, true);
    local meets, metrics = evaluate(frame, frameSums, ids, level);
    out.metrics = metrics;
    if not meets then return hold('the full set does not reach the cap'); end

    table.sort(cands, function(a, b)
        if (a.prio or 0) ~= (b.prio or 0) then return (a.prio or 0) > (b.prio or 0); end
        return (slotId(a.slot) or 99) < (slotId(b.slot) or 99);
    end);
    local accepted = {};
    for k, v in pairs(ids) do accepted[k] = v; end
    for _, c in ipairs(cands) do
        local slot = slotId(c.slot);
        local typedId, fallbackId = idOf(c.typed), idOf(c.fallback);
        local why = nil;
        if slot == nil or slot < M.FIRST_ARMOUR then why = 'weapon slots stay';
        elseif c.fallback == nil or fallbackId == nil then why = 'no fallback';
        elseif typedId ~= accepted[slot] then why = 'the slot is not the piece';
        elseif enchanted(slot, typedId) then
            why = 'its enchantment would be lost';
        else
            why = unmodelled(typedId, aug[slot]) or unmodelled(fallbackId, c.fallbackAugmented);
            if why == nil and (st.unverified[typedId] or st.unverified[fallbackId]) then why = 'unverified'; end
            local typedV, fallbackV = vectorOf(typedId), vectorOf(fallbackId);
            if why == nil and typedV ~= nil and fallbackV ~= nil and fallbackV.hp < typedV.hp and wearsHpLatent(accepted) then
                why = 'it lowers max HP while an HP latent is worn';
            end
        end
        if why == nil then
            local trial = {};
            for k, v in pairs(accepted) do trial[k] = v; end
            trial[slot] = fallbackId;
            local ok, m = evaluate(frame, frameSums, trial, level);
            if ok then
                accepted = trial;
                out.release[c.slot] = c.fallback;
                out.metrics = m;
                why = ('released for %s'):format(c.fallback);
            else
                why = 'needed for the cap';
            end
        end
        out.why[c.slot] = why;
    end
    st.memo, st.lastDecision = { key = key, out = out }, out;
    return out;
end

-- The readout's view.
function M.report()
    local f = st.latest;
    return {
        usable = #st.baseOrder > 0, why = st.why, formulaOk = st.formulaOk, gearOk = st.gearOk, mismatch = st.mismatch,
        frame = f, frameAt = st.latestAt, bases = #st.baseOrder, basis = st.lastBasis,
        trigger = (f ~= nil) and conservative() or nil, decision = st.lastDecision,
        unverified = st.unverified, wanted = wanted(M._clock()),
    };
end

-- test seam
function M._state() return st; end

return M;
