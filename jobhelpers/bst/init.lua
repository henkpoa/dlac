--[[
    dlac/jobhelpers/bst/init.lua -- the BST Helper module (issue #137 skeleton).

    The FIRST real Job helper, and the proof of the drop-in path end to end: this
    folder in addons\dlac\jobhelpers\ is scanned at load, its init.lua returns the
    contract table below, the loader validates + registers it, and the Job Helpers
    tab shows one row under BST with an (empty) Panel. Its behaviors -- the Fight
    switch, automatic Reward, death-only resummon -- land in later slices of PRD
    #135; #137 ships only the skeleton so the module system can be demoed and the
    server-approval unit (one folder = one row = one approval) exists.

    IDENTITY is the folder name ('bst'), assigned by the loader -- this table does
    NOT declare its own id. `label`, `jobs` and `api` are the contract; `panel`
    renders the Panel (empty for now). No init hook is needed yet.

    Player-facing name "BST Helper" is PROPOSED, pending the maintainer's sign-off
    (naming law -- helpers are named, never "Auto <activity>").
]]--

return {
    api   = 1,                 -- the Job helper contract version (feature\jobhelpers.API)
    label = 'BST Helper',      -- player-facing display label (PROPOSED)
    jobs  = { 'BST' },         -- declared main jobs

    -- The Panel. ctx = { imgui, id, record, deps }. Empty by design in #137:
    -- the controls arrive with the behavior slices. Renders one honest line so
    -- the Panel is never a blank void (hard rule 12).
    panel = function(ctx)
        local imgui = ctx and ctx.imgui;
        if imgui == nil then return; end
        imgui.TextColored({ 0.70, 0.70, 0.70, 1.00 },
            'BST Helper is installed. Its controls -- Fight switch, Reward, resummon --'
            .. ' arrive in a later update.');
    end,
};
