--[[
    example-helper/init.lua -- A WORKING Job helper. Copy the folder, rename it,
    change the four things marked CHANGE ME, delete what you do not need.

        docs\templates\example-helper\   ->   addons\dlac\jobhelpers\<job>\<your-module>\

    It lives here, outside `jobhelpers\`, on purpose: the loader treats every folder
    directly under `jobhelpers\` as a JOB folder, so a template sitting there would
    load as a job called "templates". Copy it out; do not develop it in place.

    What it does: one rule that uses an ability once per fight while you are engaged,
    off by default, with a Panel to arm it and a status line explaining itself. That
    is deliberately the smallest thing that still touches every part of the contract
    -- settings, a standing behavior, the activity gate, a retry lockout, the command
    door, and a Panel -- so you can see the whole shape before you change any of it.

    After copying: `/addon reload dlac`. There is no hot-plug. Your module appears as
    one row under its job's section on the Job Helpers tab. If it was refused you get
    exactly one chat line naming your folder and the reason.

    The full reference is docs\reference\jobhelper-authoring-guide.md. Everything
    below is explained there in more detail, and the section numbers in the comments
    point at it.
]]--

-- Panel text lives up here, together, because player-facing strings are the part
-- that needs the maintainer's sign-off -- and because the naming law binds you:
-- name the HELPER or the RULE, never "Auto <activity>". (guide 0)
local TIP_RULE = 'While you are engaged, this uses the ability once per fight.'
    .. ' It never acts in town, on another job, while dead or zoning -- and never'
    .. ' at all until you arm it.';

return {
    -- The API version you were written against. It must EQUAL the running dlac's,
    -- or your module is refused with one loud line. That is the entire version
    -- gate, and it exists so a module built for a different dlac fails visibly
    -- instead of misbehaving quietly. (guide 2.1)
    api = 2,

    -- CHANGE ME: the one string players see. Row label, Panel title, and the name
    -- in any refusal they read.
    label = 'Example Helper',

    -- CHANGE ME: the MAIN jobs you act on. A module whose job is not the current
    -- one shows as inactive rather than vanishing, so a player can always tell
    -- "installed but dormant" from "not installed". (guide 2.3)
    jobs = { 'WHM' },

    -- CHANGE ME: what you store per character. You declare the keys and their
    -- types; the framework owns the file, the format, the tolerant reader and the
    -- write-on-mutation policy, and hands you back a store as `S.cfg`. Scalars
    -- only: string, number, boolean.
    --
    -- Default anything that ACTS to false. A helper that issues commands -- and
    -- especially one that spends an item -- never arms itself. The player arms it;
    -- the row pill only ever silences. (guide 5)
    config = {
        keys     = { armed = 'boolean', lockout = 'number' },
        defaults = { armed = false,     lockout = 60 },
        -- file = 'jobhelper-yours.lua',   -- optional; defaults to jobhelper-<your folder>.lua
    },

    -- Arm your standing behaviors. Runs ONCE at addon load, from the loader --
    -- deliberately not from a render, because a helper must act whether or not its
    -- Panel is open.
    --
    -- `S` is the module API (feature\modapi): your identity, the one clock, every
    -- service, the act doors, your settings store and the widget kit. It is the
    -- SUPPORTED surface -- documented, versioned by `api`, and it will keep
    -- working. You can still `require` anything you like (dlac does not sandbox
    -- you), but then you own the breakage.
    --
    -- A THROW HERE REFUSES YOUR WHOLE MODULE, so contain each rule separately: one
    -- unreachable service must not cost you the others. (guide 2.4)
    init = function(S)
        pcall(function()
            local rule = S.sibling('rule');       -- your own files, by bare name
            if rule ~= nil and type(rule.init) == 'function' then rule.init(S); end
        end);
    end,

    -- Your Panel. It draws INSIDE a child region the tab already opened: no
    -- Begin/End, no window, no tab of your own.
    --
    -- `ctx.ui` is the widget kit bound to the host's imgui handle. Use it rather
    -- than ctx.imgui: it carries the binding guards, the measured widths, the
    -- vertical stacking and the panel-text standard that dlac learned in the
    -- field, so you get them by default instead of by remembering. (guide 6.7)
    panel = function(ctx)
        local ui, S = ctx.ui, ctx.S;
        if ui == nil or S == nil then return; end
        local rule = S.sibling('rule');
        if rule == nil then
            ui.err('This helper could not load its rule.');
            return;
        end

        -- A section: header + hover explanation, your body, then a rule line.
        -- Never hang an explanatory paragraph off a label -- it clips at the panel
        -- edge, and the window's minimum width is 480.
        ui.section('Example rule', TIP_RULE, function()
            -- Every control returns the NEW value when the player changed it, and
            -- nil otherwise -- so an untouched frame writes nothing.
            local flip = ui.toggle('exarm_' .. S.id, 'Use the ability when I engage',
                                   rule.armed(),
                                   'Off by default. Armed, it fires once per fight while you are engaged.');
            if flip ~= nil then rule.setArmed(flip); end

            -- The two lines every standing rule owes the player: is it going to
            -- act, and what did it last decide. In the PANEL, not in chat -- a rule
            -- that evaluates every beat has nothing to say on most beats, and only
            -- an attempt is news. The colours are the kit's: dim when you turned it
            -- off, orange only for something you can FIX, green when armed.
            ui.ruleStatus({
                armed     = rule.armed(),
                activity  = S.me.acting(),
                offText   = 'The rule is off -- nothing will be used on its own.',
                armedText = 'Armed: once per fight while engaged.',
                last      = rule.lastLine(),
            });
        end);
    end,

    -- Optional: one short item beside the Panel title. Keep it to a few words.
    status = function(ctx)
        local ui, S = ctx.ui, ctx.S;
        if ui == nil or S == nil then return; end
        local ready = S.ability.ready('Divine Seal');     -- CHANGE ME
        if ready then ui.ok('ready'); else ui.warn('cooling down'); end
    end,
};
