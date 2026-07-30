--[[
    dlac/jobhelpers/bst/bst-helper/init.lua -- the BST Helper module.

    THE FIRST REAL Job helper, and now the proof of the api-2 module API end to
    end. Its Panel carries THREE behaviors, all of them STANDING -- wired in the
    `init` hook below rather than by rendering, because a helper must act whether
    or not its Panel is open:

      * the **Fight switch** (fight.lua) -- Off / When I attack / Follow my
        target, driven by the combat state beat (S.combat);
      * the **Reward rule** (reward.lua) -- while armed and the pet sits below the
        player's pet-HP% threshold, it asks for the very sequence the "Reward now"
        button asks for, once per lockout window. Driven by the pet vitals beat;
      * the **Resummon rule** (resummon.lua) -- on a CONFIRMED jug-pet death it
        claims the configured jug, verifies it worn and fires the chosen summon;
        if both are on recast it queues. Driven by the same service's classified
        pet-loss edge, which proves the death off the pet's own corpse and knows
        the pet is a jug pet because it watched you summon it (the jug roster in
        jugs.lua is the fallback for a pet that was already out).

    ...plus ONE named action, which is not a standing behavior at all: **Summon
    now** (`commands.summon` -> resummon.summonNow) -- the Panel button and the
    key a player binds to it. The framework installs that key while they are on
    BST with this module on; nothing here touches the bind registry.

    THE SUMMON SET is the module's one piece of server-specific knowledge: on
    CatsEyeXI the master's +CHR when a jug pet spawns raises that pet's Ready
    strength for its whole life, and only GEAR CHR counts -- so the Summon
    section offers an optional set, worn best-effort around the summon, leaving
    the weapon slots alone unless the player opts in (a weapon swap costs TP).

    All three default OFF, because all three issue commands and two of them SPEND
    AN ITEM. The row pill is the opposite (default on, and it only ever silences).

    The act itself -- button and rule alike -- lives in reward.lua, so there is
    exactly ONE implementation of it: pick the best pet food the character can wear
    AND is carrying (feature\petfood -- no list UI, the bags are the control),
    optionally overlay a chosen Reward set, then open an Action sequence: ONE claim
    (set union food), the CONSUMED slot verified WORN, then Reward FIRES, then the
    claim releases and the next arbitration restores gear.

    IDENTITY is the folder name, assigned by the loader and handed back as `S.id`.
    This table declares no id, and -- since api 2 -- neither does any file in the
    module: siblings load through `S.sibling('reward')`, so renaming this folder is
    safe, which is what the framework always claimed and could not previously
    deliver (api 1 hardcoded `dlac\jobhelpers\bst\bst-helper\config` in four
    files).

    Player-facing names ("BST Helper", "Reward now", "Fight" and its three ways,
    "Reward my pet when it drops low", "Resummon", "Jug", "Use the other if mine is
    on cooldown") are PROPOSED, pending the maintainer's sign-off -- the naming law
    binds authors: name the helper or the RULE, never "Auto <activity>".

    Defensive throughout, but no longer by hand: the Panel is built on the widget
    kit (ctx.ui), which carries the binding guards, the measured widths, the
    vertical stacking and the panel-text standard, so this file says WHAT the
    Panel is and the kit says how to draw it safely.
]]--

-- ---------------------------------------------------------------------------
-- the panel text (kept here, together, because it is what needs sign-off)
-- ---------------------------------------------------------------------------

local TIP_FIGHT = 'While you are engaged with a target and your pet stands idle, it is sent in'
    .. ' -- retried a few times if the command does not take, then it goes quiet.'
    .. ' Follow my target also re-sends a fighting pet when your target changes.'
    .. ' Jug and charmed pets behave identically.';

local TIP_HEEL = 'On: once your pet takes a send, pulling it back with Heel sticks --\n'
    .. 'nothing is re-sent at that mob for the rest of the fight.\n'
    .. 'Off: an idle pet keeps being re-sent while you are engaged (a few tries).';

local TIP_REWARD = 'Reward tops up your pet with the best pet food you carry -- highest tier'
    .. ' your level allows and your bags hold. dlac equips the food, verifies it landed,'
    .. ' fires Reward, then restores your gear.';

local TIP_THRESHOLD = 'Your pet has to be BELOW this to be fed -- a pet sitting exactly on it is not.\n'
    .. 'Drag it, or double-click to type a number.';

local TIP_RESUMMON = 'Death only, and only your JUG pet. dlac equips your jug, verifies it landed,'
    .. ' fires your summon, then restores your gear. A Leave, zoning, logging out and'
    .. ' a charmed pet are never a resummon -- charm play stays entirely yours.';

local TIP_JUG = 'Every jug you can use on this server, lowest level first, each naming the pet\n'
    .. 'it calls -- the Lv76+ retail broths are left out, since nothing here can equip them.\n'
    .. 'The pet names are dlac module data and are NOT field-verified yet -- tell the\n'
    .. 'maintainer if one is wrong, and it is a one-line fix.';

local TIP_METHOD = 'Only Call Beast earns Beast Raising bonuses, and it CONSUMES the jug.\n'
    .. 'Bestial Loyalty does not consume it -- but it earns no bonuses.\n'
    .. 'Both need the jug EQUIPPED: the server reads your ammo slot for the\n'
    .. 'species, which is why dlac equips it and checks before firing.';

local TIP_FALLBACK = 'On by default. Off, a resummon waits for YOUR method instead of\n'
    .. 'reaching for the other one. Either way, if nothing is ready the\n'
    .. 'resummon queues and fires the moment one comes up -- and zoning,\n'
    .. 'Leave, logging out or any pet appearing cancels it.';

local TIP_DELAY = 'How long dlac waits after your pet dies before summoning the next one.\n'
    .. 'A pet falling over and another appearing in the same instant is a shape no\n'
    .. 'player produces -- a beat of hesitation costs nothing and looks like you.\n'
    .. 'The wait is also yours: summon by hand, Leave or zone inside it and the\n'
    .. 'pending resummon is dropped. 0 restores the instant behaviour.\n'
    .. 'The button and its key are never delayed -- there, you are the pause.';

local TIP_SUMMON = 'Everything about HOW your pet is summoned -- which jug, which ability,'
    .. ' and what you are wearing when it lands. The Resummon rule below uses all of it,'
    .. ' and so does the button.';

local TIP_SUMMONSET = 'Optional. dlac wears this set, equips your jug, fires the summon, then\n'
    .. 'restores your gear.\n'
    .. 'On this server the +CHR you are wearing when a jug pet spawns raises that\n'
    .. 'pet\'s Ready damage for as long as it is out -- and only GEAR CHR counts,\n'
    .. 'which is what makes a set the right tool. Build a CHR set in the Sets tab\n'
    .. 'and pick it here.\n'
    .. 'Best-effort: only the jug has to land. A slot another rule is holding costs\n'
    .. 'you that slot, never the summon.';

local TIP_WEAPONS = 'Off by default, because changing a weapon costs you your TP and a BST\n'
    .. 'usually summons mid-fight.\n'
    .. 'On, the Summon set may also claim Main, Sub and Range. Your ammo slot is\n'
    .. 'never up for it either way -- that is where the jug goes.';

local TIP_KEY = 'A key that summons on the spot, in Ashita\'s own bind syntax:\n'
    .. '  ^ = Ctrl, ! = Alt, @ = Win  --  so ^F3 is Ctrl+F3.\n'
    .. 'Type it and press Enter (or Set). It binds while you are on BST with this\n'
    .. 'helper on, and comes back to you when you change job.\n'
    .. 'A key another feature already holds is refused, and dlac says who has it --\n'
    .. '/dl binds lists them all.';

local TIP_SUMMONNOW = 'Summons right now with everything above -- the same gear, the same checks\n'
    .. 'and the same refusals the automatic rule uses. It works whether or not the\n'
    .. 'Resummon rule is armed: that switch only governs what happens without you.';

-- One picker row's label: the jug, its equip level, and the pet it calls. An
-- unmapped jug says so rather than showing a guess (jugs.lua: rows that could not
-- be placed honestly are absent, not invented).
local function jugLabel(row)
    if type(row) ~= 'table' then return 'None'; end
    local pet = row.pet;
    if type(pet) ~= 'string' or pet == '' then pet = 'pet not mapped yet'; end
    return string.format('%s (Lv %d) -- %s', tostring(row.name), tonumber(row.level) or 0, pet);
end

-- What a jug row can be SEARCHED by, beside its rendered label: the broth and
-- the familiar it calls. Both are already in the label -- this exists so that
-- stays true the day the label is shortened, and so "carrot hare" is documented
-- as a supported thing to type rather than an accident of the format.
local function jugSearch(row)
    if type(row) ~= 'table' then return ''; end
    return tostring(row.name or '') .. ' ' .. tostring(row.pet or '');
end

-- The dim "Last: ..." line, or nil when the rule has decided nothing yet.
local function lastLine(rule)
    if type(rule) ~= 'table' then return nil; end
    local d = nil;
    if type(rule.lastDecision) == 'function' then d = rule.lastDecision(); end
    if d == nil then return nil; end
    if type(rule.decisionText) ~= 'function' then return nil; end
    return rule.decisionText(d);
end

-- ---------------------------------------------------------------------------
-- the contract
-- ---------------------------------------------------------------------------

return {
    api   = 2,                 -- the module API version (feature\modapi.API)
    label = 'BST Helper',      -- player-facing display label (PROPOSED)
    jobs  = { 'BST' },         -- declared main jobs

    -- WHAT this module stores; feature\modcfg owns HOW (fmt-versioned, declared
    -- keys only, written on mutation, tolerant reader, never caches the pre-login
    -- nil). `file` is named explicitly to keep the name api 1 shipped, so an
    -- existing character's settings survive the upgrade untouched.
    --
    -- The two arming switches and the Resummon rule default OFF -- this module
    -- issues commands, and Reward and Call Beast SPEND AN ITEM, so a freshly
    -- installed helper must never start driving the pet or eating a player's food.
    -- `resummonFallback` is the one default that is ON: it is not an arming
    -- decision, it can only ever change WHICH ready ability is used.
    config = {
        file = 'jobhelper-bst.lua',
        keys = {
            fight            = 'string',     -- 'off' | 'attack' | 'follow'   (fight.lua)
            fightHeel        = 'boolean',    -- respect Heel: a send that TOOK is never re-sent
            fightWhen        = 'string',     -- 'drawn' | 'swing' -- when sends may start
            rewardArmed      = 'boolean',    -- the automatic Reward rule switch (reward.lua)
            rewardThreshold  = 'number',     -- pet HP%; the rule fires strictly below it
            rewardSet        = 'string',     -- optional Reward set by name; '' = food only
            resummonArmed    = 'boolean',    -- the death-only Resummon rule switch
            resummonJug      = 'string',     -- the configured jug by item name; '' = none
            resummonMethod   = 'string',     -- 'call' | 'loyalty'  (resummon.METHODS)
            resummonFallback = 'boolean',    -- "use the other if mine is on cooldown"
            resummonDelay    = 'number',     -- seconds to wait after a death before summoning
            summonSet        = 'string',     -- optional set worn while summoning; '' = jug only
            summonWeapons    = 'boolean',    -- may that set claim Main/Sub/Range?
            summonKey        = 'string',     -- the key bound to "Summon now"; '' = none
        },
        defaults = {
            fight            = 'off',
            fightHeel        = true,         -- respecting the player's own pet command is polite
            fightWhen        = 'drawn',      -- send from the engage; 'swing' waits for the swing
            rewardArmed      = false,
            rewardThreshold  = 50,           -- the slider's resting position, not an arming choice
            resummonArmed    = false,
            resummonMethod   = 'call',       -- the one that earns the raising bonuses
            resummonFallback = true,
            resummonDelay    = 1.0,          -- a beat of hesitation; instant reads as a bot
            summonWeapons    = false,        -- swapping a weapon costs your TP
            -- summonSet / summonKey have no default: absent means "none", and
            -- nothing here picks a player's gear or takes a key uninvited.
            -- rewardSet has no default: absent means "food only".
            -- resummonJug has none either: absent means "no jug picked", which the
            -- rule refuses on, loudly -- never a guess at which jug to spend.
        },
    },

    -- NAMED ACTIONS a player can fire by hand -- `/dl jh bst-helper summon` --
    -- and therefore bind a key to. `key` names one of the config keys above, and
    -- the FRAMEWORK does the binding from there: it installs the key while the
    -- player is on BST with this module's pill on, releases it on a job change,
    -- and refuses (loudly, naming the holder) a key another feature already has.
    -- Nothing in this module touches the bind registry.
    commands = {
        summon = {
            label = 'Summon now',
            help  = 'summon your jug pet with the Summon set on',
            key   = 'summonKey',
            run   = function(S)
                local r = S.sibling('resummon');
                if r == nil or type(r.summonNow) ~= 'function' then return false; end
                return r.summonNow();
            end,
        },
    },

    -- Arm the standing behaviors. Runs ONCE at addon load, from the loader, and
    -- deliberately not from a render -- all three must work with the tab closed.
    --
    -- Contained SEPARATELY per rule, and that matters twice over: a throw here
    -- refuses the whole module, and one unreachable service must not cost the
    -- other two rules their beat.
    init = function(S)
        for _, name in ipairs({ 'fight', 'reward', 'resummon' }) do
            pcall(function()
                local rule = S.sibling(name);
                if rule ~= nil and type(rule.init) == 'function' then rule.init(S); end
            end);
        end
    end,

    -- The Panel. ctx = { imgui, ui, id, record, S, activity }.
    panel = function(ctx)
        local ui = ctx and ctx.ui;
        local S  = ctx and ctx.S;
        if ui == nil or S == nil then return; end
        local id  = ctx.id or S.id;
        local act = S.me.acting();

        -- ----- Fight -------------------------------------------------------
        local fight = S.sibling('fight');
        if fight ~= nil then
            ui.section('Fight', TIP_FIGHT, function()
                local cur = fight.mode();
                local picked = ui.choice('bstfight_' .. id, {
                    values = fight.MODES, labels = fight.MODE_LABEL, helps = fight.MODE_HELP,
                }, cur);
                if picked ~= nil then fight.setMode(picked); end
                ui.space();

                -- "Send when": from the engage, or only after the first swing.
                ui.dim('Send when:');
                local when = ui.choice('bstwhen_' .. id, {
                    values = fight.WHENS, labels = fight.WHEN_LABEL, helps = fight.WHEN_HELP,
                    horizontal = true, w = 150, h = 22,
                }, fight.when());
                if when ~= nil then fight.setWhen(when); end
                ui.space();

                local heel = ui.toggle('bstheel_' .. id, 'Respect Heel', fight.heelRespect(), TIP_HEEL);
                if heel ~= nil then fight.setHeelRespect(heel); end
                ui.space();

                -- Why it is or is not acting, and what the last beat did.
                -- Deliberately here and NOT in chat: Fight evaluates every beat
                -- and fires on every pull, and a line per pull is noise.
                ui.ruleStatus({
                    armed     = (cur ~= 'off'),
                    activity  = act,
                    offText   = 'Fight is off -- pet commands stay entirely yours.',
                    armedText = 'Armed: ' .. tostring(fight.MODE_LABEL[cur] or cur) .. '.',
                    last      = lastLine(fight),
                });
            end);
        end

        -- ----- Reward ------------------------------------------------------
        local reward = S.sibling('reward');
        if reward ~= nil then
            ui.section('Reward', TIP_REWARD, function()
                -- The switch comes FIRST and the slider under it: the slider is
                -- meaningless until the rule is armed, and the switch is what a
                -- player scanning for "is this going to act on its own?" wants.
                local armed = reward.armed();
                local flip = ui.toggle('bstrewardauto_' .. id,
                    'Reward my pet when it drops low', armed,
                    'Off by default. Armed, dlac runs the same sequence the button below runs\n'
                    .. 'whenever your pet is under the threshold -- once per '
                    .. tostring(reward.LOCKOUT_S) .. ' seconds at most, so a hurt pet\n'
                    .. 'never turns into a stream of commands or chat lines.');
                if flip ~= nil then reward.setArmed(flip); armed = flip; end

                -- The slider carries its own unit ('51%'), and the status line
                -- under it already says what the number MEANS ("Armed: below 51%
                -- pet HP") -- so no caption beside it (Henrik's ruling
                -- 2026-07-29: "not really relevant text, can prolly be removed").
                local th = reward.threshold();
                local newTh = ui.slider('bstrewardthr_' .. id, th,
                    reward.MIN_THRESHOLD, reward.MAX_THRESHOLD, '%.0f%%', TIP_THRESHOLD);
                if newTh ~= nil then reward.setThreshold(newTh); th = reward.clampThreshold(newTh); end

                -- The WARN colour is reserved for the module gates. "No pet out",
                -- "above the threshold" and "waiting out the lockout" are the rule
                -- WORKING, not blocked -- orange would cry wolf all session, so
                -- they land in the dim line below.
                ui.ruleStatus({
                    armed     = armed,
                    activity  = act,
                    offText   = 'The rule is off -- the button below is the only thing that feeds your pet.',
                    armedText = string.format('Armed: below %d%% pet HP.', th),
                    last      = lastLine(reward),
                    lastLabel = 'Last beat',
                });
                ui.space();

                -- The optional Reward set. PERSISTED: the automatic path has no
                -- Panel to read a session-only choice from.
                ui.dim('Reward set (optional):');
                local set = ui.combo('bstrewardset_' .. id, reward.setName(),
                                     S.sets.names(), tostring, nil, 'None');
                if set ~= nil then reward.setSetName(tostring(set)); end
                ui.space();

                -- The deliberate feed. A real Button when ready, a dim countdown
                -- when down -- never a command the client will reject. It stays
                -- whatever the rule is set to: it is the field-test lever.
                local ready, remaining = S.ability.ready(reward.RECAST);
                if ready then
                    if ui.button('bstreward_' .. id, 'Reward now', nil, 130, 26) then
                        reward.request();
                    end
                else
                    ui.disabled(string.format('Reward now  (down %ss)', tostring(remaining or '?')));
                end
                ui.space();

                -- The chosen tier, or the honest reason none was chosen. The same
                -- service the act itself asks, so the preview can never disagree
                -- with what gets equipped.
                local pick = S.pet.food();
                if pick.ok then
                    ui.ok('Food: ' .. tostring(pick.name));
                else
                    ui.warn(S.pet.foodRefusal(pick));
                end
            end);
        end

        -- ----- Summon ------------------------------------------------------
        -- HOW a pet is summoned, gathered in one place because all three
        -- requesters share it: the Resummon rule below, its queue, and the
        -- button/key here.
        local resummon = S.sibling('resummon');
        local curJug = nil;
        if resummon ~= nil then
            curJug = resummon.jug();
            ui.section('Summon', TIP_SUMMON, function()
                -- The jug picker: every catalog jug, level-ordered, each naming
                -- the pet it calls.
                local jugs = S.sibling('jugs');
                if jugs ~= nil then
                    ui.dim('Jug:');
                    local rows = jugs.list();
                    local preview = curJug;
                    for _, r in ipairs(rows) do
                        if curJug ~= nil and string.lower(r.name) == string.lower(curJug) then
                            preview = jugLabel(r);
                        end
                    end
                    local picked = ui.combo('bstresumjug_' .. id, preview, rows, jugLabel,
                                            TIP_JUG, 'None', jugSearch);
                    if picked ~= nil then
                        if picked == 'None' then
                            resummon.setJug('None');
                        else
                            resummon.setJug(picked.name);
                        end
                        curJug = resummon.jug();
                    end
                    ui.space();
                end

                local method = ui.choice('bstresum_' .. id, {
                    values = resummon.METHODS, labels = resummon.METHOD_LABEL,
                    helps  = { call = TIP_METHOD, loyalty = TIP_METHOD },
                }, resummon.method());
                if method ~= nil then resummon.setMethod(method); end

                local fb = ui.toggle('bstresumfb_' .. id,
                    'Use the other if mine is on cooldown', resummon.fallback(), TIP_FALLBACK);
                if fb ~= nil then resummon.setFallback(fb); end

                -- What each summon MEASURES right now. Here because the field
                -- round that produced it (2026-07-30) could not have been
                -- diagnosed from the game: a recast slot that fails to resolve
                -- reads exactly like an ability that is up, and the rule chose
                -- accordingly. If a line here says "cannot read its cooldown",
                -- that is the bug back, visible before it costs a resummon.
                for _, m in ipairs(resummon.METHODS) do
                    local txt = resummon.recastText(S, resummon.RECAST[m]);
                    local line = string.format('%s: %s',
                                               tostring(resummon.METHOD_LABEL[m] or m), txt);
                    if txt == 'ready' then
                        ui.ok(line);
                    elseif txt:find('cannot', 1, true) ~= nil then
                        ui.warn(line);
                    else
                        ui.dim(line);
                    end
                end
                ui.space();

                -- The optional Summon set + its one exception. PERSISTED, like
                -- the Reward set: the automatic path has no Panel to read from.
                ui.dim('Summon set (optional):');
                local sset = ui.combo('bstsummonset_' .. id, resummon.setName(),
                                      S.sets.names(), tostring, TIP_SUMMONSET, 'None');
                if sset ~= nil then resummon.setSetName(tostring(sset)); end

                local wep = ui.toggle('bstsummonwep_' .. id,
                    'Include weapon slots', resummon.weapons(), TIP_WEAPONS);
                if wep ~= nil then resummon.setWeapons(wep); end
                ui.space();

                -- The key. The module STORES it; the framework installs it.
                ui.dim('Summon key:');
                local myKey = resummon.key();
                local typed = ui.input('bstsummonkey_' .. id, myKey or '',
                                       { w = 90, tip = TIP_KEY, button = 'Set' });
                if typed ~= nil then resummon.setKey(typed); myKey = resummon.key(); end

                -- What that key is actually doing right now -- asked of the
                -- registry, never assumed from the setting: a key we stored and
                -- a key we HOLD are two different facts, and the gap between
                -- them (somebody else has it) is the one worth printing.
                local keys = (type(S.keys) == 'table') and S.keys or nil;
                if myKey == nil then
                    ui.dim('No key bound -- the button below is the only way in.');
                elseif keys == nil then
                    ui.dim(string.format('%s is set.', myKey));
                else
                    local held = keys.boundTo('summon');
                    if held ~= nil then
                        ui.ok(string.format('%s is bound to Summon now.', tostring(held)));
                    else
                        local who = keys.holder(myKey);
                        if who ~= nil then
                            ui.warn(string.format('%s is held by %s -- pick another key.',
                                                  myKey, tostring(who.label or who.owner)));
                        else
                            ui.dim(string.format('%s binds while you are on BST with this helper on.', myKey));
                        end
                    end
                end
                ui.space();

                if ui.button('bstsummonnow_' .. id, 'Summon now', TIP_SUMMONNOW, 130, 26) then
                    resummon.summonNow();
                end
                if curJug == nil then
                    ui.warn('No jug picked -- nothing can be summoned.');
                end
            end);
        end

        -- ----- Resummon ----------------------------------------------------
        if resummon ~= nil then
            ui.section('Resummon', TIP_RESUMMON, function()
                local armed = resummon.armed();
                local flip = ui.toggle('bstresumauto_' .. id,
                    'Resummon my pet when it dies', armed,
                    'Off by default. Armed, a CONFIRMED jug-pet death summons a new one --\n'
                    .. 'your pet going down where it stood, which dlac reads off the pet itself.\n'
                    .. 'A Leave, zoning and logging out never count, so a deliberate\n'
                    .. 'dismissal cannot cost you a jug.');
                if flip ~= nil then resummon.setArmed(flip); armed = flip; end

                -- The pause. Its own line because it is the one setting here
                -- that is about how the act LOOKS rather than what it does.
                ui.dim('Wait before summoning:');
                local dly = ui.slider('bstresumdelay_' .. id, resummon.delay(),
                    resummon.MIN_DELAY_S, resummon.MAX_DELAY_S, '%.1fs', TIP_DELAY);
                if dly ~= nil then resummon.setDelay(dly); end
                ui.space();

                -- "No jug picked" is the module's OWN gate, and it is a real
                -- blocker the player can fix -- so it takes the warn slot ahead of
                -- the activity reasons.
                local blocked = nil;
                if curJug == nil then blocked = 'No jug picked -- nothing can be summoned.'; end
                ui.ruleStatus({
                    armed     = armed,
                    activity  = act,
                    blocked   = blocked,
                    offText   = 'The rule is off -- a dead pet stays dead until you summon it.',
                    armedText = string.format('Armed: %s, %s.', tostring(curJug),
                                  tostring(resummon.METHOD_LABEL[resummon.method()] or '?')),
                    last      = lastLine(resummon),
                    lastLabel = 'Last edge',
                });
                -- What the queue is actually waiting FOR: the pause and the
                -- cooldown are both "queued", and telling a player "waiting for
                -- a cooldown" during a one-second pause would be a small lie.
                local q = resummon.queued();
                if q ~= nil then
                    local last = resummon.lastDecision();
                    local why = (type(last) == 'table') and (last.reason or last.cancel) or nil;
                    if why == 'delay' then
                        ui.dim('Pausing a moment before summoning.');
                    else
                        ui.warn('Queued: waiting for a summon to come off cooldown.');
                    end
                end
            end);
        end

        -- ----- the live world ----------------------------------------------
        -- The vitals service's own answer, so the Panel and the rules can never
        -- disagree about the bar they read.
        local v = S.pet.get();
        if type(v) == 'table' and v.present == true then
            ui.dim(string.format('Pet: %s at %s%% HP.',
                tostring(v.name or 'your pet'), tostring(v.hpp or '?')));
        else
            ui.dim('Pet: none out.');
        end

        if S.act.busy() then
            ui.text(ui.COL.head, 'Sequence: ' .. tostring(S.act.status()));
        end
    end,

    -- The row-status hook: a short "Reward ready / Reward 12s" beside the Panel
    -- title. Contained by the tab; a throw never breaks the row.
    status = function(ctx)
        local ui = ctx and ctx.ui;
        local S  = ctx and ctx.S;
        if ui == nil or S == nil then return; end
        local reward = S.sibling('reward');
        if reward == nil then return; end
        local ready, remaining = S.ability.ready(reward.RECAST);
        if ready then
            ui.ok('Reward ready');
        else
            ui.warn(string.format('Reward %ss', tostring(remaining or '?')));
        end
    end,
};
