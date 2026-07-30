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
        pet-loss edge, and the module's jug roster (jugs.lua) is what lets that
        edge tell a jug pet from a charmed one.

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

local TIP_JUG = 'Every jug in the catalog, lowest level first, each naming the pet it calls.\n'
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

-- One picker row's label: the jug, its equip level, and the pet it calls. An
-- unmapped jug says so rather than showing a guess (jugs.lua: rows that could not
-- be placed honestly are absent, not invented).
local function jugLabel(row)
    if type(row) ~= 'table' then return 'None'; end
    local pet = row.pet;
    if type(pet) ~= 'string' or pet == '' then pet = 'pet not mapped yet'; end
    return string.format('%s (Lv %d) -- %s', tostring(row.name), tonumber(row.level) or 0, pet);
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
            -- rewardSet has no default: absent means "food only".
            -- resummonJug has none either: absent means "no jug picked", which the
            -- rule refuses on, loudly -- never a guess at which jug to spend.
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

        -- ----- Resummon ----------------------------------------------------
        local resummon = S.sibling('resummon');
        if resummon ~= nil then
            ui.section('Resummon', TIP_RESUMMON, function()
                local armed = resummon.armed();
                local flip = ui.toggle('bstresumauto_' .. id,
                    'Resummon my pet when it dies', armed,
                    'Off by default. Armed, a CONFIRMED jug-pet death summons a new one --\n'
                    .. 'the pet-falls message, or your pet vanishing with its HP already low.\n'
                    .. 'Nothing else counts, so a deliberate dismissal never costs you a jug.');
                if flip ~= nil then resummon.setArmed(flip); armed = flip; end

                -- The jug picker: every catalog jug, level-ordered, each naming
                -- the pet it calls.
                local jugs = S.sibling('jugs');
                local curJug = resummon.jug();
                if jugs ~= nil then
                    ui.dim('Jug:');
                    local rows = jugs.list();
                    local preview = curJug;
                    for _, r in ipairs(rows) do
                        if curJug ~= nil and string.lower(r.name) == string.lower(curJug) then
                            preview = jugLabel(r);
                        end
                    end
                    local picked = ui.combo('bstresumjug_' .. id, preview, rows, jugLabel, TIP_JUG, 'None');
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
                if resummon.queued() ~= nil then
                    ui.warn('Queued: waiting for a summon to come off cooldown.');
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
