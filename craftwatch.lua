--[[
    dlac/craftwatch.lua -- synthesis detection (Piece 1: OBSERVE + REPORT ONLY).

    Answers "am I crafting, and WHICH craft?" so craft gear sets can follow.
    Auto-equip is deliberately NOT wired yet -- detection gets field-verified
    first (dlacprobe style), then a later piece maps craft -> set -> equip.

    How: outgoing packet 0x096 GP_CLI_COMMAND_COMBINE_ASK (XiPackets) carries
    the catalyst + ingredient list of the synth being confirmed:
        Crystal u16 @0x06 | CrystalIdx u8 @0x08 | Items u8 @0x09
        ItemNo[8] u16 @0x0A..0x19 | TableNo[8] u8 @0x1A..0x21
    The crystal id + ingredient MULTISET identify the recipe; crafts.lua
    (generated from the server's own synth_recipes.sql by tools/gen_craftdb.py,
    ships with the addon -- nothing is fetched at runtime) maps it to the craft
    skill and required level. Unknown recipes (CatsEyeXI customs live in the
    private repo) fail soft and are reported once, with the lookup key, so the
    maintainer can collect them.

    TIMING TRUTH (LSB synthutils): the server rolls the synth result the moment
    0x096 ARRIVES -- gear equipped on detection lands during the animation and
    counts from the NEXT synth on, not this one. First-synth coverage will need
    a pre-flip (craft mode) or synthesis-menu detection (future probe).

    Pure data core (key/decode/lookup) is headless-testable; Ashita glue below.
]]--

local M = {};

-- ---------------------------------------------------------------------------
-- pure core
-- ---------------------------------------------------------------------------

-- crafts.lua lookup key: crystal id + ingredient ids sorted ascending (the
-- client sends placement order; the db stores a canonical order -- the
-- multiset is what identifies the recipe).
function M.key(crystal, ings)
    local s = {};
    for i = 1, #ings do s[i] = ings[i]; end
    table.sort(s);
    return string.format('%d:%s', crystal, table.concat(s, ','));
end

-- Decode a raw 0x096 packet (string, includes the 4-byte header).
-- Returns crystal id, ingredient id list -- or nil if malformed.
function M.decode(data)
    if type(data) ~= 'string' or #data < 0x1A then return nil; end
    local function b(o) return string.byte(data, o + 1) or 0; end
    local function u16(o) return b(o) + b(o + 1) * 256; end
    local crystal = u16(0x06);
    local n = b(0x09);
    if crystal == 0 or n == 0 or n > 8 then return nil; end
    local ings = {};
    for i = 0, n - 1 do
        local id = u16(0x0A + i * 2);
        if id ~= 0 then ings[#ings + 1] = id; end
    end
    if #ings == 0 then return nil; end
    return crystal, ings;
end

-- Recipe database (bundled; absence degrades to every synth reading 'unknown').
local _dbok, _db = pcall(require, 'dlac\\crafts');
if not _dbok or type(_db) ~= 'table' then _db = {}; end
function M.setDb(db) _db = db or {}; end            -- test seam

-- nil when the recipe is unknown (custom / not in the public SQL).
function M.lookup(crystal, ings)
    return _db[M.key(crystal, ings)];
end

-- ---------------------------------------------------------------------------
-- Key items, tracked from s2c packet 0x055 (the FindAll pattern): the SDK's
-- HasKeyItem memory read is DEAD on this client (probe 2026-07-13: owned
-- total 0 with key items verifiably owned). The server re-sends the full
-- bitfield in 512-KI blocks on login/zone-in, so this table is complete
-- after the first zone. Layout (ThornyFFXI/FindAll pk_KeyItemUpdate):
--   u32 header | u8 avail[0x40] | u8 examined[0x40] | u8 blockOffset | pad.
-- ---------------------------------------------------------------------------
M.keyItems = {};        -- ki id -> true
M.kiBlocksSeen = 0;     -- 0 = no 0x055 yet this session
M.kiPersisted = 0;      -- entries restored from the per-char mirror at startup

-- Persistence (<char>\dlac\keyitems.lua): key items are permanent unlocks
-- (Henrik), so the last-known table is restored at startup -- the panel works
-- without a fresh zone-in -- and every 0x055 resync corrects and re-saves it.
local _kiLoaded, _kiLoadAt = false, -10;
local function kiCharDir()
    local dir = nil;
    pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty();
        local name, id = party:GetMemberName(0), party:GetMemberServerId(0);
        if name == nil or name == '' or id == nil then return; end
        dir = string.format('%sconfig\\addons\\luashitacast\\%s_%u\\dlac\\',
            AshitaCore:GetInstallPath(), name, id);
    end);
    return dir;
end

local function kiLoad()
    if _kiLoaded then return; end
    local now = os.clock();
    if now - _kiLoadAt < 5 then return; end   -- pre-login: char unknown, retry gently
    _kiLoadAt = now;
    pcall(function()
        local dir = kiCharDir();
        if dir == nil then return; end
        _kiLoaded = true;                     -- one real attempt; packets take over after
        local chunk = loadfile(dir .. 'keyitems.lua');
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' and M.kiBlocksSeen == 0 then
            local n = 0;
            for id, v in pairs(t) do
                if v == true and type(id) == 'number' then M.keyItems[id] = true; n = n + 1; end
            end
            M.kiPersisted = n;
        end
    end);
end

local function kiSave()
    pcall(function()
        local dir = kiCharDir();
        if dir == nil then return; end
        local ids = {};
        for id in pairs(M.keyItems) do ids[#ids + 1] = id; end
        table.sort(ids);
        local parts = {};
        for _, id in ipairs(ids) do parts[#parts + 1] = string.format('[%d]=true,', id); end
        local f = io.open(dir .. 'keyitems.lua', 'wb');
        if f == nil then return; end
        f:write('-- dlac key-item mirror (0x055-tracked; permanent unlocks persist across reloads)\nreturn {'
            .. table.concat(parts, '') .. '}\n');
        f:close();
    end);
end

function M.onKeyItemPacket(data)
    if type(data) ~= 'string' or #data < 0x85 then return; end
    kiLoad();                                 -- adopt the mirror before the first live block
    local base = (string.byte(data, 0x84 + 1) or 0) * 512;
    for x = 0, 0x3F do
        local b = string.byte(data, 0x04 + x + 1) or 0;
        for y = 0, 7 do
            local id = base + x * 8 + y;
            if math.floor(b / 2 ^ y) % 2 == 1 then
                M.keyItems[id] = true;
            else
                M.keyItems[id] = nil;
            end
        end
    end
    M.kiBlocksSeen = M.kiBlocksSeen + 1;
    kiSave();
end

function M.hasKeyItem(id)
    kiLoad();
    return M.keyItems[id] == true;
end

-- Ownership data available? Live packets beat the mirror; the mirror beats
-- nothing (the panel shows 'zone once' only when BOTH are absent).
function M.kiReady()
    kiLoad();
    return M.kiBlocksSeen > 0 or (M.kiPersisted or 0) > 0;
end

-- ---------------------------------------------------------------------------
-- Tier / binding-craft calc (Henrik): HQ tiers break when your skill exceeds
-- the recipe cap by >11 / >31 / >51. With SUBCRAFTS the craft with the
-- SMALLEST margin limits the tier -- gear should boost THAT craft ("enough
-- clothcraft but not bonecraft -> wear bonecraft gear"). Recomputed per synth.
-- ---------------------------------------------------------------------------

-- Ashita craftskills_t order (plugins/sdk/ffxi/player.h): GetCraftSkill(sid).
local CRAFT_SID = { Woodworking = 1, Smithing = 2, Goldsmithing = 3, Clothcraft = 4,
                    Leathercraft = 5, Bonecraft = 6, Alchemy = 7, Cooking = 8 };

function M.playerCraftSkill(craft)
    local v = nil;
    pcall(function()
        local sid = CRAFT_SID[craft];
        if sid == nil then return; end
        v = AshitaCore:GetMemoryManager():GetPlayer():GetCraftSkill(sid):GetSkill();
    end);
    return v;
end

-- HQ tier for a skill margin over the recipe cap (0 = none, 3 = best odds).
function M.tierOf(margin)
    if margin == nil then return nil; end
    if margin > 51 then return 3; end
    if margin > 31 then return 2; end
    if margin > 11 then return 1; end
    return 0;
end

-- skills = the recipe's full requirement map (crafts.lua `skills`, present on
-- subcraft recipes). getSkill injectable for tests. Returns the binding craft
-- name + its margin, or nil when skills are absent/unreadable.
function M.bindingCraft(skills, getSkill)
    getSkill = getSkill or M.playerCraftSkill;
    local best, bestMargin = nil, nil;
    for craft, req in pairs(skills or {}) do
        local have = getSkill(craft);
        if have ~= nil then
            local margin = have - (tonumber(req) or 0);
            if bestMargin == nil or margin < bestMargin then
                best, bestMargin = craft, margin;
            end
        end
    end
    return best, bestMargin;
end

-- ---------------------------------------------------------------------------
-- session state + Ashita glue
-- ---------------------------------------------------------------------------

M.current = nil;    -- { skill, lv, desynth, key, at } of the most recent synth
M.counts  = {};     -- skill -> synths seen this session (includes 'unknown')

local _cfok, _cfmt = pcall(require, 'dlac\\chatfmt');
_cfok = _cfok and type(_cfmt) == 'table';
local function say(s) if _cfok and _cfmt.msg then _cfmt.msg(s); else print('[dlac] ' .. s); end end

local _saidUnknown = {};   -- key -> true (report each unknown recipe once)

-- ---------------------------------------------------------------------------
-- Craft-gear equip. MANUAL (Henrik): you pick the craft (bar / panel / command)
-- and dlac equips the committed set 'Craft_<Skill>' (fallback 'Craft'), else
-- the autogear manifest's craft ladders for the current goal -- one staggered
-- /lac equip per slot via the shared cmdqueue. You do this BEFORE synthing,
-- while equipment changes are legal; the gear then counts for every synth.
-- ---------------------------------------------------------------------------
M.barVisible = false;      -- floating craft bar (craftbar.lua) shown?
M._craftRescanned = false; -- regenerated the manifest once this session?

local SLOT_LABELS = { 'Main', 'Sub', 'Range', 'Ammo', 'Head', 'Neck', 'Ear1', 'Ear2',
                      'Body', 'Hands', 'Ring1', 'Ring2', 'Back', 'Waist', 'Legs', 'Feet' };

-- Set entry -> equippable item name. Wrapper/rule forms carry the ref in .gear;
-- 'dlac:' virtuals are engine-resolved and have no direct equip form -> skip.
local function entryName(v)
    if type(v) == 'string' then
        if v:sub(1, 5) == 'dlac:' then return nil; end
        return v;
    end
    if type(v) == 'table' then
        if type(v.Name) == 'string' then return v.Name; end
        if type(v.gear) == 'string' then return v.gear; end
        if type(v.gear) == 'table' and type(v.gear.Name) == 'string' then return v.gear.Name; end
    end
    return nil;
end
M._entryName = entryName;   -- test seam

-- Preview the resolved craft picks (diagnostics / tests) -- the ACTUAL equip is
-- done by the engine overlay (dispatch.craftOverlay reading craftstate.lua).
-- Returns { [slotLabel] = itemName } for a craft + the current goal.
function M.manifestPreview(skill)
    local ok, dsp = pcall(require, 'dlac\\dispatch');
    if not ok or type(dsp) ~= 'table' or type(dsp._resolveVirtual) ~= 'function' then return {}; end
    local picks = {};
    for _, slot in ipairs(SLOT_LABELS) do
        local nm = nil;
        pcall(function() nm = dsp._resolveVirtual('dlac:AutoCraft',
            { craftOverride = skill, goalOverride = M.goal }, slot); end);
        if nm ~= nil then picks[slot] = nm; end
    end
    return picks;
end

-- ---------------------------------------------------------------------------
-- MANUAL craft control (Henrik's design). You pick craft + goal + on/off from
-- the floating bar or the Automations panel; craftwatch just WRITES the state
-- to <char>\dlac\craftstate.lua, and the dispatch ENGINE overlays that craft
-- gear on Default (dispatch.craftOverlay). So the engine WEARS the craft gear
-- -- nothing reverts it -- and turning the switch off removes the overlay so
-- normal gear returns. No commands, no locks, no fighting the engine.
-- ---------------------------------------------------------------------------
M.goal = 'hq';            -- hq | nq | skillup
M.activeCraft = nil;      -- the craft you selected
M.enabled = false;        -- the on/off switch; session-only, starts OFF
local _stateLoaded = false;

local function craftStatePath()
    local dir = kiCharDir();
    return dir and (dir .. 'craftstate.lua') or nil;
end
local function saveCraftState()
    pcall(function()
        local p = craftStatePath();
        if p == nil then return; end
        local f = io.open(p, 'wb'); if f == nil then return; end
        f:write(string.format('return { craft = %q, goal = %q, enabled = %s }\n',
            tostring(M.activeCraft or ''), tostring(M.goal or 'hq'), tostring(M.enabled == true)));
        f:close();
    end);
end
M._saveCraftState = saveCraftState;   -- test seam

function M.loadCraftState()
    if _stateLoaded then return; end
    local dir = kiCharDir();
    if dir == nil then return; end        -- pre-login: retry next call
    _stateLoaded = true;
    pcall(function()
        local chunk = loadfile(dir .. 'craftstate.lua');
        if chunk ~= nil then
            local ok, t = pcall(chunk);
            if ok and type(t) == 'table' then
                if type(t.goal) == 'string' and (t.goal == 'nq' or t.goal == 'skillup' or t.goal == 'hq') then
                    M.goal = t.goal;
                end
                if type(t.craft) == 'string' and t.craft ~= '' then M.activeCraft = t.craft; end
                -- `enabled` is NOT restored: the switch starts OFF each session
                -- (no craft gear glued on at login). craft+goal DO persist.
            end
        end
    end);
    M.enabled = false;
    saveCraftState();                     -- sync the file to enabled=false for the engine
end

function M.getGoal() M.loadCraftState(); return M.goal or 'hq'; end
function M.getCraft() M.loadCraftState(); return M.activeCraft; end
function M.isEnabled() M.loadCraftState(); return M.enabled == true; end

-- Ensure the manifest's craft ladders are current. Regenerate when the on-disk
-- schema is older than this build (a fmtver-5 manifest lacks the fmtver-6
-- head/back skill-up fillers -- exactly why Bonze Cape / Midras's Helm didn't
-- equip). Checked on every select/enable (autoLoad is cached, so it's cheap);
-- the engine then reads the fresh autogear.lua.
local function ensureManifestFresh()
    pcall(function()
        local tg = require('dlac\\triggersui');
        if type(tg.rescanAutogear) ~= 'function' then return; end
        local stale = (type(tg.manifestStale) ~= 'function') or tg.manifestStale();
        if stale or not M._craftRescanned then
            M._craftRescanned = true;
            tg.rescanAutogear();
        end
    end);
end

-- The on/off switch (bar + panel). Writing enabled -> the engine picks it up
-- within a dispatch (~0.4s tick) and overlays / stops overlaying the craft gear.
function M.setEnabled(on)
    M.loadCraftState();
    M.enabled = (on == true);
    if M.enabled then ensureManifestFresh(); end
    saveCraftState();
    if M.enabled and M.activeCraft ~= nil then
        say(string.format('craft gear: %s (%s) -- the engine now wears it; turn off to restore normal gear.',
            M.activeCraft, M.goal or 'hq'));
    elseif not M.enabled then
        say('craft gear: off -- normal gear restored.');
    end
end

-- Pick the GOAL craft. Craft buttons ONLY set which craft is active (Henrik);
-- they do NOT flip the switch. The engine equips it only while the switch is on.
function M.selectCraft(craft)
    if type(craft) ~= 'string' or craft == '' then return; end
    M.loadCraftState();
    M.activeCraft = craft;
    ensureManifestFresh();
    saveCraftState();
end

-- Change the goal (persists; the engine re-resolves on its next dispatch).
function M.setGoal(goal)
    if goal ~= 'hq' and goal ~= 'nq' and goal ~= 'skillup' then return; end
    M.loadCraftState();
    M.goal = goal;
    saveCraftState();
end

-- Process one detected synth; returns the record (also used by tests).
function M.onSynth(crystal, ings, clock)
    local rec = M.lookup(crystal, ings);
    local skill = rec and rec.skill or 'unknown';
    M.counts[skill] = (M.counts[skill] or 0) + 1;
    local prev = M.current;
    -- Gear should boost the BINDING craft: on subcraft recipes the smallest
    -- player-skill margin limits the HQ tier (recomputed every synth).
    local binding, margin = nil, nil;
    if rec ~= nil and type(rec.skills) == 'table' then
        binding, margin = M.bindingCraft(rec.skills);
    end
    local target = binding or skill;
    M.current = {
        skill = skill, lv = rec and rec.lv or nil,
        desynth = rec and rec.desynth or nil,
        binding = binding, margin = margin, target = target,
        key = M.key(crystal, ings), at = clock or os.clock(),
    };
    if rec ~= nil then
        local prevTarget = prev and (prev.target or prev.skill) or nil;
        if prevTarget ~= target then               -- announce once per craft change
            local note = '';
            if binding ~= nil and binding ~= skill then
                note = string.format(' -- binding subcraft: %s (margin %+d, tier %d)',
                    binding, margin or 0, M.tierOf(margin) or 0);
            end
            say(string.format('synth detected: %s (recipe lv %d%s)%s.',
                skill, rec.lv or 0, rec.desynth and ', desynth' or '', note));
            -- Detection is now INFO only (it can't equip in time -- 0x096 is
            -- the first packet). It just highlights the current craft on the
            -- bar; equipping is your manual pick (selectCraft). If the binding
            -- subcraft differs from what you selected, nudge you to switch.
            if M.activeCraft ~= nil and target ~= M.activeCraft and target ~= 'unknown' then
                say(string.format('  (you have %s gear on; this recipe is bound by %s -- click %s on the craft bar to switch)',
                    M.activeCraft, target, target));
            end
        end
    elseif not _saidUnknown[M.current.key] then        -- each unknown once, with the key
        _saidUnknown[M.current.key] = true;
        say(string.format('synth detected, recipe UNKNOWN (key %s) -- likely a CatsEyeXI custom; '
            .. 'tell the maintainer so crafts.lua can learn it.', M.current.key));
    end
    return M.current;
end

if ashita ~= nil and ashita.events ~= nil and type(ashita.events.register) == 'function' then
    ashita.events.register('packet_out', 'dlac-craftwatch-out', function(e)
        if e.id ~= 0x096 then return; end
        pcall(function()
            local crystal, ings = M.decode(e.data);
            if crystal ~= nil then M.onSynth(crystal, ings); end
        end);
    end);

    ashita.events.register('packet_in', 'dlac-craftwatch-in', function(e)
        if e.id == 0x055 then pcall(function() M.onKeyItemPacket(e.data); end); end
    end);

    -- /dl craft [bar | <craft> | goal <hq|nq|skillup> | ki] -- manual controls.
    ashita.events.register('command', 'dlac-craftwatch-cmd', function(e)
        pcall(function()
            local raw = string.lower(e.command or '');
            local a, b, c = raw:match('^/dl%s+(%S+)%s*(%S*)%s*(%S*)');
            if a == nil then a, b, c = raw:match('^/dlac%s+(%S+)%s*(%S*)%s*(%S*)'); end
            if a ~= 'craft' then return; end
            e.blocked = true;
            local CRAFTS = { woodworking = 'Woodworking', smithing = 'Smithing',
                goldsmithing = 'Goldsmithing', clothcraft = 'Clothcraft',
                leathercraft = 'Leathercraft', bonecraft = 'Bonecraft',
                alchemy = 'Alchemy', cooking = 'Cooking' };
            if b == 'bar' then
                M.barVisible = not M.barVisible;
                say('craft bar ' .. (M.barVisible and 'shown' or 'hidden') .. '.');
                return;
            end
            if b == 'goal' then
                if c == 'hq' or c == 'nq' or c == 'skillup' then
                    M.setGoal(c); say('craft goal: ' .. c .. (M.activeCraft and (' (re-equipped ' .. M.activeCraft .. ')') or ''));
                else
                    say('craft goal is ' .. M.getGoal() .. '  (/dl craft goal hq|nq|skillup)');
                end
                return;
            end
            if CRAFTS[b] ~= nil then
                M.selectCraft(CRAFTS[b]);   -- equips immediately
                return;
            end
            if b == 'ki' then
                -- Key-item diagnostic (field tool): what does THIS client call
                -- the guild KIs, what ids do they map to, and what does
                -- HasKeyItem say? Paste the output to fix the panel for real.
                local res = nil;
                pcall(function() res = AshitaCore:GetResourceManager(); end);
                if res == nil then say('ki probe: resources unavailable.'); return; end
                say(string.format('ki probe -- 0x055 blocks seen this session: %d%s',
                    M.kiBlocksSeen, (M.kiBlocksSeen == 0) and '  (ZONE ONCE to sync)' or ''));
                say('ki probe -- exact reverse lookups (packet-tracked ownership):');
                for _, nm in ipairs({ 'Way of the Carpenter', 'Way of the Blacksmith', 'Way of the Goldsmith',
                                      'Way of the Weaver', 'Way of the Tanner', 'Way of the Boneworker',
                                      'Way of the Alchemist', 'Way of the Culinarian' }) do
                    local id = nil;
                    pcall(function() id = res:GetString('keyitems.names', nm, 2); end);
                    if type(id) == 'number' and id >= 0 then
                        say(string.format('  %s: id=%d has=%s', nm, id, tostring(M.hasKeyItem(id))));
                    else
                        say(string.format('  %s: NOT in client strings', nm));
                    end
                end
                say('ki probe -- everything the 0x055 tracker reports as OWNED:');
                local ids = {};
                for id in pairs(M.keyItems) do ids[#ids + 1] = id; end
                table.sort(ids);
                for i = 1, math.min(#ids, 40) do
                    local nm = nil;
                    pcall(function() nm = res:GetString('keyitems.names', ids[i]); end);
                    say(string.format('  id=%d "%s"', ids[i], tostring(nm or '?')));
                end
                say(string.format('  owned total: %d%s', #ids, (#ids > 40) and ' (first 40 shown)' or ''));
                return;
            end
            if b == 'show' then                        -- what would the engine equip?
                local skill = M.getCraft();
                if skill == nil then say('craft show: pick a craft first (/dl craft <name>).'); return; end
                local picks = M.manifestPreview(skill);
                say(string.format('craft show: %s (%s goal) -> engine overlay:', skill, M.getGoal()));
                local any = false;
                for _, slot in ipairs(SLOT_LABELS) do
                    if picks[slot] ~= nil then any = true; say(string.format('  %-6s %s', slot, picks[slot])); end
                end
                if not any then say('  (nothing -- Rescan owned gear in Triggers > Automations)'); end
                return;
            end
            -- bare /dl craft: status.
            say(string.format('craft: selected = %s, goal = %s, switch = %s.',
                M.getCraft() or '(none -- /dl craft <name>)', M.getGoal(), M.isEnabled() and 'ON' or 'off'));
            say('  pick a craft + goal on the bar (/dl craft bar) or Automations panel, then flip the switch ON --');
            say('  the engine wears that craft\'s gear until you turn it off. /dl craft show lists the pieces.');
            if M.current ~= nil then
                say(string.format('  last synth seen: %s%s.', M.current.skill,
                    M.current.lv and (' lv ' .. M.current.lv) or ''));
            end
            local parts = {};
            for sk, n in pairs(M.counts) do parts[#parts + 1] = string.format('%s x%d', sk, n); end
            table.sort(parts);
            if #parts > 0 then say('  session: ' .. table.concat(parts, ', ')); end
        end);
    end);
end

return M;
