--[[
    dlac/jobhelpers/bst/init.lua -- the BST Helper module (issue #139 adds the
    three-way Fight switch; #138 brought "Reward now" and the Action sequence
    machinery; #137 shipped the skeleton both replace).

    The FIRST real Job helper, and the proof of the drop-in path end to end.

    Its Panel carries TWO behaviors. The **Fight switch** (bst\fight.lua) is the
    module's first standing one: Off / When I attack / Follow my target, driven
    entirely by the engage/target edge service, storing its setting in the
    module's OWN per-character config file (bst\config.lua). It is wired in the
    `init` hook below, not by rendering -- a helper must act whether or not its
    Panel is open.

    And the "Reward now" button, which:
      * picks the best pet food the character both can wear AND is carrying (the
        eight-tier pet-food Ladder, feature\petfood -- no list UI, the bags are
        the control);
      * optionally overlays a chosen Reward set from the job entry's own Sets;
      * opens an Action sequence (feature\actionseq): ONE claim (set union food),
        verified WORN through the gear oracle, then Reward FIRES, then the claim
        releases and the next arbitration restores gear;
      * GRAYS OUT while Reward is on cooldown (the ability recast readiness
        service, feature\recast), rather than firing a command the client
        rejects.

    IDENTITY is the folder name ('bst'), assigned by the loader -- this table does
    NOT declare its own id. `label`, `jobs` and `api` are the contract.

    Player-facing names ("BST Helper", "Reward now", "Fight" and its three ways)
    are PROPOSED, pending the maintainer's sign-off (naming law -- helpers are
    named, never "Auto <activity>"). Defensive throughout: every imgui + service
    touch is guarded so the Panel renders headlessly (the smoke suite) and a
    missing service never tears the tab (hard rules 6, 12).
]]--

local COL_DIM  = { 0.70, 0.70, 0.70, 1.00 };
local COL_WARN = { 1.00, 0.72, 0.30, 1.00 };
local COL_OK   = { 0.55, 0.90, 0.55, 1.00 };
local COL_HEAD = { 0.60, 0.75, 1.00, 1.00 };

-- The action command. Reward is a BST job ability used on the pet. FLAGGED for
-- field verification: the exact target token on CatsEyeXI (<me> vs <pet>) is
-- confirmed in-game before this ships to players -- the sequencer's verify-worn
-- gate protects the GEAR either way, but a wrong token means the command no-ops.
local REWARD_CMD = '/ja "Reward" <me>';

-- The verify window: how long the sequencer waits for the food to land worn
-- before it ABORTS (nothing fired). A handful of 0.4s dispatches.
local VERIFY_TIMEOUT = 4;

-- The module's own folder name. The LOADER is the identity authority (it reads
-- the folder), so this is only the fallback for the paths that run without a
-- render ctx -- the init hook, which receives deps but not an id.
local MODULE_ID = 'bst';

-- Panel state (file-scope locals, captured by the contract closures below): the
-- optional Reward set the picker chose. 'None' = food only.
local _setChoice = nil;

-- ---------------------------------------------------------------------------
-- helpers (all contained -- a missing service degrades, never throws)
-- ---------------------------------------------------------------------------

local function req(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

local function emit(line)
    local done = false;
    local cf = req('dlac\\chatfmt');
    if cf ~= nil and type(cf.err) == 'function' then pcall(cf.err, line); done = true; end
    if not done then pcall(function() print('[dlac] ' .. tostring(line)); end); end
end

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

-- The player's current main job, or nil.
local function playerJob()
    local j = nil;
    pcall(function() j = gData.GetPlayer().MainJob; end);
    if type(j) ~= 'string' or j == '' or j == '?' then return nil; end
    return j;
end

-- This module's priority among the current job's section (the tab's section
-- order). Higher wins a simultaneous contention (actionseq.arbitrateRequests);
-- top-of-section is highest, so order = (count - index + 1). Defaults to 1.
local function sectionOrder(id)
    local order = 1;
    pcall(function()
        local jh = req('dlac\\feature\\jobhelpers');
        local job = playerJob();
        if jh == nil or job == nil then return; end
        local ids = jh.idsForJob(job);
        for i, n in ipairs(ids) do
            if n == id then order = (#ids - i + 1); return; end
        end
    end);
    return order;
end

-- The named Reward sets available to pick from -- the job entry's static Sets
-- (Idle, Reward, ...). Never the Dynamic build sets. A short list; the picker is
-- optional.
local function rewardSetNames()
    local out = {};
    pcall(function()
        local ps = req('dlac\\gear\\profilesets');
        if ps == nil or type(ps.staticSetNames) ~= 'function' then return; end
        out = ps.staticSetNames() or {};
    end);
    return out;
end

-- Pull a slot -> item-name map from a named set (best-effort: strings and the
-- common wrapper shapes). Missing / unreadable -> empty (food-only claim).
local function setSlots(name)
    local slots = {};
    if type(name) ~= 'string' or name == '' or name == 'None' then return slots; end
    pcall(function()
        local ps = req('dlac\\gear\\profilesets');
        if ps == nil or type(ps.getSetsRoot) ~= 'function' then return; end
        local root = ps.getSetsRoot();
        local set = (type(root) == 'table') and root[name] or nil;
        if type(set) ~= 'table' then return; end
        for slot, v in pairs(set) do
            local item = nil;
            if type(v) == 'string' then item = v;
            elseif type(v) == 'table' then item = v.Name or v.name or v.item; end
            if type(item) == 'string' and item ~= '' then slots[slot] = item; end
        end
    end);
    return slots;
end

-- Build the Action sequence claim: the optional Reward set overlaid, then the
-- chosen food forced into Ammo (food always wins the ammo slot -- the union the
-- PRD names). Returns claim, need.
local function buildRequest(id, foodName, setName)
    local claim = setSlots(setName);
    claim.Ammo = foodName;                 -- food ∪ set; food owns Ammo
    return {
        module  = id,
        label   = 'Reward',
        order   = sectionOrder(id),
        claim   = claim,
        need    = { Ammo = foodName },      -- the one slot that MUST verify worn
        command = REWARD_CMD,
        timeout = VERIFY_TIMEOUT,
    };
end

-- The click handler: pick food, refuse loudly if none, else open the sequence.
local function doReward(id)
    local petfood   = req('dlac\\feature\\petfood');
    local actionseq = req('dlac\\feature\\actionseq');
    if petfood == nil or actionseq == nil then
        emit('Reward unavailable: a required service failed to load.');
        return;
    end
    local pick = petfood.choose();
    if not pick.ok then
        emit('Reward: ' .. petfood.refusalLine(pick));     -- loud refusal (AC4)
        return;
    end
    local res = actionseq.request(buildRequest(id, pick.name, _setChoice));
    if type(res) == 'table' and res.ok ~= true then
        if res.reason == 'busy' then
            emit(string.format('Reward is busy -- %s is running a sequence.',
                tostring(res.holderLabel or res.holder or 'another helper')));
        end
        return;
    end
    -- Kick one Default so the claim applies now rather than on the next 0.4s
    -- tick (the same explicit re-dispatch a mode flip does). The pump then reads
    -- the worn food and fires. Contained: the tick is the fallback.
    pcall(function()
        local dsp = req('dlac\\dispatch');
        if dsp ~= nil and type(dsp.kickDefault) == 'function' then dsp.kickDefault(); end
    end);
end

-- ---------------------------------------------------------------------------
-- the Fight switch (issue #139) -- three buttons, one of them lit
-- ---------------------------------------------------------------------------

local function fightMod() return req('dlac\\jobhelpers\\bst\\fight'); end

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
-- the contract
-- ---------------------------------------------------------------------------
return {
    api   = 1,                 -- the Job helper contract version (feature\jobhelpers.API)
    label = 'BST Helper',      -- player-facing display label (PROPOSED)
    jobs  = { 'BST' },         -- declared main jobs

    -- The init hook: arm the standing behaviors. Runs ONCE at addon load, from
    -- the loader, and deliberately not from a render -- Fight must work with the
    -- Job Helpers tab closed. `deps` is the shared-services table (unused here;
    -- fight.lua consumes the central services by name). Contained by the loader:
    -- a throw here refuses the whole module, so nothing in it may throw.
    init = function(deps)
        pcall(function()
            local fight = req('dlac\\jobhelpers\\bst\\fight');
            if fight ~= nil and type(fight.init) == 'function' then fight.init(MODULE_ID); end
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
                'Send your pet in off your own attacks. Nothing here polls or repeats:'
                .. ' every send follows one attack or target change, so Heel is respected until'
                .. ' the next one. Jug and charmed pets behave identically.');
            space();

            local cur = fight.mode();
            local w = modeWidth(imgui, fight);
            for _, m in ipairs(fight.MODES) do
                if modeButton(imgui, fight, id, m, cur, w) then fight.setMode(m); end
            end
            space();

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
                txt(COL_DIM, 'Last edge: ' .. fight.decisionText(lastD) .. '.');
            end
            space();
            rule();
            space();
        end

        -- ----- Reward (issue #138) ------------------------------------------
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

        -- optional Reward set picker (guarded: the combo is not in every binding)
        if type(imgui.BeginCombo) == 'function' and type(imgui.EndCombo) == 'function' then
            txt(COL_DIM, 'Reward set (optional):');
            local cur = _setChoice or 'None';
            if imgui.BeginCombo('##bstrewardset_' .. id, cur) then
                local names = { 'None' };
                for _, n in ipairs(rewardSetNames()) do names[#names + 1] = n; end
                for _, n in ipairs(names) do
                    local sel = (cur == n);
                    if type(imgui.Selectable) == 'function' and imgui.Selectable(n, sel) then
                        -- plain if/else: `(x) and nil or y` always yields y --
                        -- the documented ternary trap (07-23 review lesson).
                        if n == 'None' then _setChoice = nil; else _setChoice = n; end
                    end
                end
                imgui.EndCombo();
            end
            space();
        end

        -- the button -- a real Button when ready, a dim countdown when down
        if ready then
            local clicked = false;
            if type(imgui.Button) == 'function' then
                clicked = imgui.Button('Reward now##bstreward_' .. id, { 130, 26 });
            end
            if clicked then doReward(id); end
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
