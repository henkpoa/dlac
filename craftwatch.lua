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
-- Piece 2: auto-equip. OFF by default, session-scoped (/dl craft auto on).
-- On a detected craft CHANGE, equips the committed set 'Craft_<Skill>'
-- (fallback: 'Craft') from the current job's profile -- one staggered
-- /lac equip per slot via the shared cmdqueue (gearui ticks it per frame).
-- Set building stays in the Sets tab, where the weights UI can already score
-- SynthSkillGain / SynthSuccessRate. TIMING (see header): the swap lands
-- during the animation, so gear counts from the NEXT synth on.
-- ---------------------------------------------------------------------------
M.autoEquip = false;
M._equippedTarget = nil;   -- craft the auto-equip last dressed for

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

local function findCraftSet(skill)
    local ok, profsets = pcall(require, 'dlac\\profilesets');
    if not ok or type(profsets) ~= 'table' or type(profsets.getSetsRoot) ~= 'function' then return nil; end
    local root = nil;
    pcall(function() root = profsets.getSetsRoot(); end);
    if type(root) ~= 'table' then return nil; end
    local dyn = (type(root.Dynamic) == 'table') and root.Dynamic or {};
    for _, nm in ipairs({ 'Craft_' .. tostring(skill), 'Craft' }) do
        local s = dyn[nm] or root[nm];
        if type(s) == 'table' then return nm, s; end
    end
    return nil;
end

-- Manifest-driven picks: resolve dlac:AutoCraft per slot through the shared
-- dispatch resolver (addon-state instance reads the same autogear.lua). The
-- craft is passed as ctx.craftOverride -- the command-bus mode write hasn't
-- landed in this frame yet. Returns { [slotLabel] = itemName }.
function M.manifestPicks(skill)
    local ok, dsp = pcall(require, 'dlac\\dispatch');
    if not ok or type(dsp) ~= 'table' or type(dsp._resolveVirtual) ~= 'function' then return nil; end
    local picks = nil;
    for _, slot in ipairs(SLOT_LABELS) do
        local nm = nil;
        pcall(function() nm = dsp._resolveVirtual('dlac:AutoCraft', { craftOverride = skill }, slot); end);
        if nm ~= nil then picks = picks or {}; picks[slot] = nm; end
    end
    return picks;
end

-- Equip craft gear for a skill; returns pieces queued (0 = nothing found).
-- A committed Craft_<Skill> / Craft set wins (explicit intent); otherwise the
-- autogear manifest's craft ladders decide (zero-setup path). Per Henrik:
-- gear STAYS ON afterwards -- the next ordinary trigger event redresses you.
-- baseDelay (frames) postpones the whole sequence (the synth-result path).
function M.equipCraftSet(skill, baseDelay)
    local setName, contents = findCraftSet(skill);
    local picks, n = {}, 0;
    if setName ~= nil then
        for _, slot in ipairs(SLOT_LABELS) do
            picks[slot] = entryName(contents[slot]);
        end
    else
        picks = M.manifestPicks(skill) or {};
        setName = 'craft gear (auto)';
    end
    local ok, cmdq = pcall(require, 'dlac\\cmdqueue');
    if not ok or type(cmdq) ~= 'table' or type(cmdq.enqueue) ~= 'function' then return 0; end
    for _, slot in ipairs(SLOT_LABELS) do
        if picks[slot] ~= nil then
            cmdq.enqueue((baseDelay or 0) + 4 * n, string.format('/lac equip %s "%s"', slot, picks[slot]));
            n = n + 1;
        end
    end
    if n > 0 then
        say(string.format('auto craft set: equipping %s (%d pieces) -- counts from the NEXT synth.', setName, n));
    else
        say(string.format('auto craft set: nothing to equip for %s -- commit a Craft_%s set or Rescan owned gear (Triggers > Automations).',
            tostring(skill), tostring(skill)));
    end
    return n;
end

-- Synthesis-window detection: equip BEFORE the confirm (the only correct
-- moment -- 0x096 IS the first packet, so nothing can dress you for the synth
-- that fired it). The synth menu name is learned at synth time (self-
-- calibrating) and persisted per character; on a fresh session it also
-- matches the known-default so the very first window works.
M._lastTarget = nil;      -- craft to dress for (last synth, or the mode picker)
M._synthMenu = nil;       -- learned synthesis menu name
M._menuWas = '';          -- previous frame's menu name (edge detect)
M._dressedThisWindow = false;
local DEFAULT_SYNTH_MENU = 'synthesis';   -- common FFXiMain name; the learned one wins

local function synthMenuPath()
    local dir = kiCharDir();
    return dir and (dir .. 'synthmenu.lua') or nil;
end
function M.saveSynthMenu()
    pcall(function()
        local p = synthMenuPath();
        if p == nil or type(M._synthMenu) ~= 'string' then return; end
        local f = io.open(p, 'wb'); if f == nil then return; end
        f:write(string.format('return %q\n', M._synthMenu)); f:close();
    end);
end
local function loadSynthMenu()
    if M._synthMenu ~= nil then return; end
    pcall(function()
        local p = synthMenuPath();
        if p == nil then return; end
        local chunk = loadfile(p);
        if chunk ~= nil then
            local ok, v = pcall(chunk);
            if ok and type(v) == 'string' and v ~= '' then M._synthMenu = v; end
        end
    end);
end

-- Does this menu name look like the synthesis window? The learned name is
-- authoritative; before we've learned one, fall back to a case-insensitive
-- substring of the common default.
local function isSynthMenu(nm)
    if type(nm) ~= 'string' or nm == '' then return false; end
    if M._synthMenu ~= nil then return nm == M._synthMenu; end
    return string.find(string.lower(nm), DEFAULT_SYNTH_MENU, 1, true) ~= nil;
end

-- Per-frame: fire once when the synthesis window OPENS (menu edge), dressing
-- for the active craft while equipment changes are still allowed.
function M.tick()
    if not M.autoEquip then M._menuWas = ''; return; end
    local nm = '';
    pcall(function()
        local dsp = require('dlac\\dispatch');
        if type(dsp.menuName) == 'function' then nm = dsp.menuName() or ''; end
    end);
    local nowSynth = isSynthMenu(nm);
    local wasSynth = isSynthMenu(M._menuWas);
    M._menuWas = nm;
    if nowSynth and not wasSynth then                  -- window just opened
        M._dressedThisWindow = false;
        local target = M._lastTarget
            or (M.current and (M.current.target or M.current.skill)) or nil;
        if target ~= nil and target ~= 'unknown' then
            M._dressedThisWindow = true;
            pcall(function() M.equipCraftSet(target); end);
        end
    elseif not nowSynth then
        M._dressedThisWindow = false;
    end
end

-- Toggle entry point (GUI button + /dl craft auto). Dressing happens when the
-- synth window opens (M.tick); turning ON while the window is already up
-- dresses immediately.
function M.setAuto(on)
    M.autoEquip = (on == true);
    if not M.autoEquip then
        M._equippedTarget = nil;
        return;
    end
    loadSynthMenu();
    -- If the synth window is open right now, dress at once.
    local nm = '';
    pcall(function()
        local dsp = require('dlac\\dispatch');
        if type(dsp.menuName) == 'function' then nm = dsp.menuName() or ''; end
    end);
    local target = M._lastTarget or (M.current and (M.current.target or M.current.skill)) or nil;
    if isSynthMenu(nm) and target ~= nil and target ~= 'unknown' then
        pcall(function() M.equipCraftSet(target); end);
    end
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
        if prevTarget ~= target then               -- announce/publish on TARGET change only
            local note = '';
            if binding ~= nil and binding ~= skill then
                note = string.format(' -- binding subcraft: %s (margin %+d, tier %d)',
                    binding, margin or 0, M.tierOf(margin) or 0);
            end
            say(string.format('synth detected: %s (recipe lv %d%s)%s.',
                skill, rec.lv or 0, rec.desynth and ', desynth' or '', note));
            -- Publish the TARGET craft as the dlac-owned 'craft' cycle value. The
            -- chat-command bus reaches BOTH Lua states, so the engine's
            -- dlac:AutoCraft virtuals resolve for this craft in trigger sets too.
            pcall(function()
                AshitaCore:GetChatManager():QueueCommand(1, '/dl mode craft ' .. tostring(target));
            end);
        end
        -- Remember the craft for the NEXT synth-window open (that's when we can
        -- dress -- BEFORE the confirm, while equipment changes are still legal).
        -- Also learn the synthesis MENU NAME here: 0x096 is sent from inside the
        -- open window, so whatever menu is up right now IS the synth menu. This
        -- self-calibrates the window detector -- no hardcoded menu string.
        M._lastTarget = target;
        pcall(function()
            local dsp = require('dlac\\dispatch');
            if type(dsp.menuName) == 'function' then
                local nm = dsp.menuName();
                if type(nm) == 'string' and nm ~= '' and nm ~= M._synthMenu then
                    M._synthMenu = nm;
                    M.saveSynthMenu();
                end
            end
        end);
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

    -- Poll the open-menu name every frame: equip when the synthesis window
    -- opens (BEFORE the confirm -- the only moment gear can count for the synth).
    ashita.events.register('d3d_present', 'dlac-craftwatch-menu', function()
        pcall(M.tick);
    end);

    -- /dl craft [auto on|off | equip] -- status / automation control.
    ashita.events.register('command', 'dlac-craftwatch-cmd', function(e)
        pcall(function()
            local raw = string.lower(e.command or '');
            local a, b, c = raw:match('^/dl%s+(%S+)%s*(%S*)%s*(%S*)');
            if a == nil then a, b, c = raw:match('^/dlac%s+(%S+)%s*(%S*)%s*(%S*)'); end
            if a ~= 'craft' then return; end
            e.blocked = true;
            if b == 'auto' then
                if     c == 'on'  then M.setAuto(true);
                elseif c == 'off' then M.setAuto(false); end
                say('auto craft set ' .. (M.autoEquip and 'ON' or 'OFF')
                    .. ' -- EQUIPS your best craft pieces when a synth of a new craft is detected; it never crafts for you.'
                    .. '  (/dl craft auto on|off; session-only for now)');
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
            if b == 'equip' then
                local skill = M.current and M.current.skill or nil;
                if skill == nil or skill == 'unknown' then
                    say('craft equip: no known craft detected yet this session -- synth once, then retry.');
                else
                    M.equipCraftSet(skill);
                end
                return;
            end
            if M.current == nil then
                say('craft watch: no synth seen yet this session. Start a synth and check again.'
                    .. (M.autoEquip and '' or '  (auto craft set is OFF: /dl craft auto on)'));
                return;
            end
            say(string.format('craft watch: last synth = %s%s (%.0fs ago); auto craft set %s.',
                M.current.skill, M.current.lv and (' lv ' .. M.current.lv) or '',
                os.clock() - (M.current.at or 0), M.autoEquip and 'ON' or 'OFF'));
            say(string.format('  synth window: %s; dresses for %s when it opens.',
                M._synthMenu and ('learned as "' .. M._synthMenu .. '"') or ('not learned yet (default "' .. DEFAULT_SYNTH_MENU .. '")'),
                M._lastTarget or (M.current and (M.current.target or M.current.skill)) or '(no craft yet)'));
            local parts = {};
            for sk, n in pairs(M.counts) do parts[#parts + 1] = string.format('%s x%d', sk, n); end
            table.sort(parts);
            say('  session: ' .. table.concat(parts, ', '));
        end);
    end);
end

return M;
