--[[
    dlac/jobhelpers/bst/init.lua -- the BST Helper module (issue #140 adds the
    automatic Reward rule; #139 the three-way Fight switch; #138 brought "Reward
    now" and the Action sequence machinery; #137 shipped the skeleton they
    replace).

    The FIRST real Job helper, and the proof of the drop-in path end to end.

    Its Panel carries TWO behaviors, both of them STANDING -- wired in the `init`
    hook below rather than by rendering, because a helper must act whether or not
    its Panel is open:

      * the **Fight switch** (bst\fight.lua) -- Off / When I attack / Follow my
        target, driven entirely by the engage/target edge service;
      * the **Reward rule** (bst\reward.lua) -- while it is armed and the pet
        sits below the player's pet-HP% threshold, it asks for the very sequence
        the "Reward now" button asks for, once per lockout window. It is driven
        by the pet vitals service (feature\petvitals), which publishes presence /
        HP% / TP / name once per dispatch beat.

    Both store their settings in the module's OWN per-character config file
    (bst\config.lua), and both default OFF.

    The act itself -- button and rule alike -- lives in bst\reward.lua, so there
    is exactly ONE implementation of it:
      * pick the best pet food the character both can wear AND is carrying (the
        eight-tier pet-food Ladder, feature\petfood -- no list UI, the bags are
        the control);
      * optionally overlay a chosen Reward set from the job entry's own Sets;
      * open an Action sequence (feature\actionseq): ONE claim (set union food),
        the CONSUMED slot verified WORN, then Reward FIRES, then the claim
        releases and the next arbitration restores gear.
    The button additionally GRAYS OUT while Reward is on cooldown (the ability
    recast readiness service, feature\recast) rather than firing a command the
    client rejects; the rule simply holds, silently, which is the same thing said
    without a button.

    IDENTITY is the folder name ('bst'), assigned by the loader -- this table does
    NOT declare its own id. `label`, `jobs` and `api` are the contract.

    Player-facing names ("BST Helper", "Reward now", "Fight" and its three ways,
    "Reward my pet when it drops below") are PROPOSED, pending the maintainer's
    sign-off (naming law -- helpers are named, never "Auto <activity>").
    Defensive throughout: every imgui + service touch is guarded so the Panel
    renders headlessly (the smoke suite) and a missing service never tears the
    tab (hard rules 6, 12).
]]--

local COL_DIM  = { 0.70, 0.70, 0.70, 1.00 };
local COL_WARN = { 1.00, 0.72, 0.30, 1.00 };
local COL_OK   = { 0.55, 0.90, 0.55, 1.00 };
local COL_HEAD = { 0.60, 0.75, 1.00, 1.00 };

-- The module's own folder name. The LOADER is the identity authority (it reads
-- the folder), so this is only the fallback for the paths that run without a
-- render ctx -- the init hook, which receives deps but not an id.
local MODULE_ID = 'bst-helper';

-- ---------------------------------------------------------------------------
-- helpers (all contained -- a missing service degrades, never throws)
-- ---------------------------------------------------------------------------

local function req(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

-- The Reward rule + the act itself. Both the button and the automatic rule go
-- through this ONE module, which is why "identical refusal behavior to the
-- button" needs no second implementation to agree with.
local function rewardMod() return req('dlac\\jobhelpers\\bst\\bst-helper\\reward'); end

-- A section header per the PANEL-TEXT STANDARD (uistyle.helpLabel): the label
-- underlined, the explanation in its HOVER -- never an inline paragraph, which
-- clips at the panel edge (Henrik's field ruling 2026-07-29, screenshot round
-- 2: "do some word wrapping, I can't make the window wider"). Falls back to a
-- plain colored label when uistyle is unreachable.
local function head(imgui, label, tip)
    local us = req('dlac\\ui\\uistyle');
    if us ~= nil and type(us.helpLabel) == 'function' then
        local ok = pcall(us.helpLabel, imgui, label, tip, COL_HEAD);
        if ok then return; end
    end
    if type(imgui.TextColored) == 'function' then imgui.TextColored(COL_HEAD, label); end
end


-- ---------------------------------------------------------------------------
-- the Fight switch (issue #139) -- three buttons, one of them lit
-- ---------------------------------------------------------------------------

local function fightMod() return req('dlac\\jobhelpers\\bst\\bst-helper\\fight'); end

-- The widest of the three labels, MEASURED (the craftbar "Last Synth" lesson --
-- a hardcoded width clipped the trailing character). Falls back to a width that
-- fits "Follow my target" at the themed font's ~9.5px/char. The three ways stack
-- VERTICALLY: side by side they need ~520px, and the right-hand Panel child is
-- whatever is left of a window whose minimum is 480 -- the same clipping trap the
-- row STATUS column fell into on 2026-07-29.
local function modeWidth(imgui, fight)
    local w = 176;
    pcall(function()
        if type(imgui.CalcTextSize) ~= 'function' then return; end
        local widest = 0;
        for _, m in ipairs(fight.MODES) do
            local tw = imgui.CalcTextSize(fight.MODE_LABEL[m]);
            if type(tw) == 'number' and tw > widest then widest = tw; end
        end
        if widest > 0 then w = math.max(120, math.floor(widest) + 20); end
    end);
    return w;
end

-- One way of the three. Lit (green) when it is the live mode. Uses only widgets
-- this Ashita install is known to carry -- Button + the style-color push, the
-- craftbar fallback shape; RadioButton is not called anywhere in dlac and
-- presence would prove nothing anyway (hard rule 2).
local function modeButton(imgui, fight, id, m, current, w)
    local lit = (current == m);
    local pushed = false;
    if lit and ImGuiCol_Button ~= nil and type(imgui.PushStyleColor) == 'function' then
        imgui.PushStyleColor(ImGuiCol_Button, { 0.18, 0.55, 0.18, 1.00 });
        pushed = true;
    end
    local clicked = false;
    if type(imgui.Button) == 'function' then
        clicked = imgui.Button(fight.MODE_LABEL[m] .. '##bstfight_' .. m .. '_' .. id, { w or 176, 24 });
    end
    if pushed then imgui.PopStyleColor(1); end
    if type(imgui.IsItemHovered) == 'function' and imgui.IsItemHovered()
       and type(imgui.SetTooltip) == 'function' then
        imgui.SetTooltip(fight.MODE_HELP[m]);
    end
    return clicked;
end

-- ---------------------------------------------------------------------------
-- the Reward rule's threshold widget (issue #140)
-- ---------------------------------------------------------------------------

-- The pet-HP% slider. Returns (newValue|nil, drew) -- `drew` so the caller only
-- SameLines a label onto a widget that actually reached the screen.
--
-- SliderFloat, not SliderInt: SliderInt is called nowhere in dlac and presence
-- would prove nothing about it (hard rule 2 -- BeginPopupContextItem was bound
-- and did not work), whereas SliderFloat is FIELD-PROVEN as the floating-gear
-- scale slider in equippedui. The '%.0f%%' format makes it read as whole
-- percent, and the value is clamped to whole numbers by reward.clampThreshold on
-- the way into the config. InputInt (also proven, three panels use it) is the
-- fallback for a binding without either.
local function thresholdWidget(imgui, reward, id, cur)
    local out, drew = nil, false;
    local key = '##bstrewardthr_' .. id;
    if type(imgui.PushItemWidth) == 'function' then imgui.PushItemWidth(150); end
    if type(imgui.SliderFloat) == 'function' then
        local buf = { cur };
        drew = true;
        if imgui.SliderFloat(key, buf, reward.MIN_THRESHOLD, reward.MAX_THRESHOLD, '%.0f%%') then
            out = buf[1];
        end
    elseif type(imgui.InputInt) == 'function' then
        local buf = { cur };
        drew = true;
        if imgui.InputInt(key, buf) then out = buf[1]; end
    end
    if type(imgui.PopItemWidth) == 'function' then imgui.PopItemWidth(); end
    if drew and type(imgui.IsItemHovered) == 'function' and imgui.IsItemHovered()
       and type(imgui.SetTooltip) == 'function' then
        imgui.SetTooltip('Your pet has to be BELOW this to be fed -- a pet sitting exactly on it is not.\n'
            .. 'Drag it, or double-click to type a number.');
    end
    return out, drew;
end

-- ---------------------------------------------------------------------------
-- the contract
-- ---------------------------------------------------------------------------
return {
    api   = 1,                 -- the Job helper contract version (feature\jobhelpers.API)
    label = 'BST Helper',      -- player-facing display label (PROPOSED)
    jobs  = { 'BST' },         -- declared main jobs

    -- The init hook: arm the standing behaviors. Runs ONCE at addon load, from
    -- the loader, and deliberately not from a render -- both behaviors must work
    -- with the Job Helpers tab closed. `deps` is the shared-services table
    -- (unused here; fight.lua and reward.lua consume the central services by
    -- name). Contained by the loader: a throw here refuses the whole module, so
    -- nothing in it may throw -- and the two subscriptions are contained
    -- SEPARATELY, so a broken edge service cannot cost the Reward rule its beat.
    init = function(deps)
        pcall(function()
            local fight = req('dlac\\jobhelpers\\bst\\bst-helper\\fight');
            if fight ~= nil and type(fight.init) == 'function' then fight.init(MODULE_ID); end
        end);
        pcall(function()
            local reward = rewardMod();
            if reward ~= nil and type(reward.init) == 'function' then reward.init(MODULE_ID); end
        end);
    end,

    -- The Panel. ctx = { imgui, id, record, deps }.
    panel = function(ctx)
        local imgui = ctx and ctx.imgui;
        if imgui == nil then return; end
        local id = (ctx and ctx.id) or MODULE_ID;

        local function txt(col, s) if type(imgui.TextColored) == 'function' then imgui.TextColored(col, s); end end
        local function space() if type(imgui.Spacing) == 'function' then imgui.Spacing(); end end
        local function rule() if type(imgui.Separator) == 'function' then imgui.Separator(); end end

        -- ----- Fight (issue #139) -------------------------------------------
        local fight = fightMod();
        if fight ~= nil then
            head(imgui, 'Fight',
                'While you are engaged with a target and your pet stands idle, it is sent in'
                .. ' -- retried a few times if the command does not take, then it goes quiet.'
                .. ' Follow my target also re-sends a fighting pet when your target changes.'
                .. ' Jug and charmed pets behave identically.');
            space();

            local cur = fight.mode();
            local w = modeWidth(imgui, fight);
            for _, m in ipairs(fight.MODES) do
                if modeButton(imgui, fight, id, m, cur, w) then fight.setMode(m); end
            end
            space();

            -- Respect Heel -- the player's option (Henrik's ruling 2026-07-29).
            if type(imgui.Checkbox) == 'function' then
                local heel = { fight.heelRespect() };
                if imgui.Checkbox('Respect Heel##bstheel_' .. id, heel) then
                    fight.setHeelRespect(heel[1]);
                end
                if type(imgui.IsItemHovered) == 'function' and imgui.IsItemHovered()
                   and type(imgui.SetTooltip) == 'function' then
                    imgui.SetTooltip('On: once your pet takes a send, pulling it back with Heel sticks --\n'
                        .. 'nothing is re-sent at that mob for the rest of the fight.\n'
                        .. 'Off: an idle pet keeps being re-sent while you are engaged (a few tries).');
                end
                space();
            end

            -- Why it is or is not acting right now, plus what the last edge did.
            -- Deliberately here and NOT in chat: Fight fires on every pull, and a
            -- line per pull is noise (the standing "success is silent" law).
            local act = nil;
            pcall(function()
                local jh = req('dlac\\feature\\jobhelpers');
                if jh ~= nil and type(jh.activity) == 'function' then act = jh.activity(id); end
            end);
            if cur == 'off' then
                txt(COL_DIM, 'Fight is off -- pet commands stay entirely yours.');
            elseif type(act) == 'table' and act.active ~= true then
                txt(COL_WARN, 'Not acting: ' .. tostring(act.label or 'inactive') .. '.');
            else
                txt(COL_OK, 'Armed: ' .. tostring(fight.MODE_LABEL[cur] or cur) .. '.');
            end
            local lastD = fight.lastDecision();
            if lastD ~= nil then
                txt(COL_DIM, 'Last: ' .. fight.decisionText(lastD) .. '.');
            end
            space();
            rule();
            space();
        end

        -- ----- Reward (issues #138 + #140) ----------------------------------
        local reward = rewardMod();
        head(imgui, 'Reward',
            'Reward tops up your pet with the best pet food you carry -- highest tier'
            .. ' your level allows and your bags hold. dlac equips the food, verifies it landed,'
            .. ' fires Reward, then restores your gear.');
        space();

        -- recast readiness -> gray the button while Reward is down (AC7)
        local recast = req('dlac\\feature\\recast');
        local ready, remaining = true, nil;
        if recast ~= nil then ready, remaining = recast.rewardReady(); end

        -- food preview (the ladder, read off the bags)
        local petfood = req('dlac\\feature\\petfood');
        local pick = petfood ~= nil and petfood.choose() or { ok = false, reason = 'none-carried' };

        -- ----- the automatic rule (issue #140): switch + threshold ----------
        -- The switch comes FIRST and the slider under it, because the slider is
        -- meaningless until the rule is armed -- and the switch is what a player
        -- scanning the Panel for "is this thing going to act on its own?" is
        -- looking for.
        if reward ~= nil then
            local armed = reward.armed();
            if type(imgui.Checkbox) == 'function' then
                local buf = { armed };
                if imgui.Checkbox('Reward my pet when it drops low##bstrewardauto_' .. id, buf) then
                    reward.setArmed(buf[1]);
                    armed = buf[1];
                end
                if type(imgui.IsItemHovered) == 'function' and imgui.IsItemHovered()
                   and type(imgui.SetTooltip) == 'function' then
                    imgui.SetTooltip('Off by default. Armed, dlac runs the same sequence the button below runs\n'
                        .. 'whenever your pet is under the threshold -- once per '
                        .. tostring(reward.LOCKOUT_S) .. ' seconds at most, so a hurt pet\n'
                        .. 'never turns into a stream of commands or chat lines.');
                end
            end

            local th = reward.threshold();
            local newTh, drewThr = thresholdWidget(imgui, reward, id, th);
            if newTh ~= nil then reward.setThreshold(newTh); th = reward.clampThreshold(newTh); end
            if drewThr and type(imgui.SameLine) == 'function' then imgui.SameLine(0, 8); end
            txt(COL_DIM, string.format('below %d%% pet HP', th));

            -- Why the rule is or is not acting right now, and what the last beat
            -- decided. Deliberately here and NOT in chat: the rule evaluates
            -- every dispatch beat, and only an ATTEMPT is news.
            --
            -- The WARN line is reserved for the module gates -- the same reads
            -- the Fight section warns on. "No pet out", "above the threshold"
            -- and "waiting out the lockout" are the rule working, not the rule
            -- blocked, and colouring them orange would cry wolf all session;
            -- they land in the dim "Last beat" line below instead.
            local ract = nil;
            pcall(function()
                local jh = req('dlac\\feature\\jobhelpers');
                if jh ~= nil and type(jh.activity) == 'function' then ract = jh.activity(id); end
            end);
            local lastD = reward.lastDecision();
            if not armed then
                txt(COL_DIM, 'The rule is off -- the button below is the only thing that feeds your pet.');
            elseif type(ract) == 'table' and ract.active ~= true then
                txt(COL_WARN, 'Not acting: ' .. tostring(ract.label or 'inactive') .. '.');
            else
                txt(COL_OK, string.format('Armed: below %d%% pet HP.', th));
            end
            if lastD ~= nil then
                txt(COL_DIM, 'Last beat: ' .. reward.decisionText(lastD) .. '.');
            end
            space();
        end

        -- optional Reward set picker (guarded: the combo is not in every
        -- binding). PERSISTED since #140: the automatic rule has no Panel to
        -- read a session-only choice from.
        if reward ~= nil and type(imgui.BeginCombo) == 'function' and type(imgui.EndCombo) == 'function' then
            txt(COL_DIM, 'Reward set (optional):');
            local cur = reward.setName() or 'None';
            if imgui.BeginCombo('##bstrewardset_' .. id, cur) then
                local names = { 'None' };
                for _, n in ipairs(reward.setNames()) do names[#names + 1] = n; end
                for _, n in ipairs(names) do
                    local sel = (cur == n);
                    if type(imgui.Selectable) == 'function' and imgui.Selectable(n, sel) then
                        reward.setSetName(n);
                    end
                end
                imgui.EndCombo();
            end
            space();
        end

        -- the button -- a real Button when ready, a dim countdown when down. It
        -- stays whatever the rule is set to: it is the deliberate feed, and the
        -- field-test lever for the whole sequence.
        if ready then
            local clicked = false;
            if type(imgui.Button) == 'function' then
                clicked = imgui.Button('Reward now##bstreward_' .. id, { 130, 26 });
            end
            if clicked and reward ~= nil then reward.request(id); end
        else
            if type(imgui.TextDisabled) == 'function' then
                imgui.TextDisabled(string.format('Reward now  (down %ss)', tostring(remaining or '?')));
            else
                txt(COL_DIM, string.format('Reward now (down %ss)', tostring(remaining or '?')));
            end
        end
        space();

        -- food line: the chosen tier, or the loud reason none was chosen
        if pick.ok then
            txt(COL_OK, 'Food: ' .. tostring(pick.name));
        else
            txt(COL_WARN, petfood ~= nil and petfood.refusalLine(pick) or 'no pet food available.');
        end

        -- the live pet, when there is one -- the vitals service's own answer, so
        -- the Panel and the rule can never disagree about the bar they read.
        local pv = req('dlac\\feature\\petvitals');
        if pv ~= nil then
            local v = pv.get();
            if type(v) == 'table' and v.present == true then
                txt(COL_DIM, string.format('Pet: %s at %s%% HP.',
                    tostring(v.name or 'your pet'), tostring(v.hpp or '?')));
            else
                txt(COL_DIM, 'Pet: none out.');
            end
        end

        -- the live sequence state, if one is running
        local actionseq = req('dlac\\feature\\actionseq');
        if actionseq ~= nil and actionseq.active() then
            txt(COL_HEAD, 'Sequence: ' .. tostring(actionseq.statusText()));
        end
    end,

    -- The row-status hook (optional, #137): a short "Reward: ready / 12s" beside
    -- the row. Contained by the tab; a throw never breaks the row.
    status = function(ctx)
        local imgui = ctx and ctx.imgui;
        if imgui == nil or type(imgui.TextColored) ~= 'function' then return; end
        local recast = req('dlac\\feature\\recast');
        if recast == nil then return; end
        local ready, remaining = recast.rewardReady();
        if ready then
            imgui.TextColored(COL_OK, 'Reward ready');
        else
            imgui.TextColored(COL_WARN, string.format('Reward %ss', tostring(remaining or '?')));
        end
    end,
};
