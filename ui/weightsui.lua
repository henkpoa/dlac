--[[
    dlac/weightsui.lua

    The stat-weights EDITOR, extracted from gearui (the LuaJIT 200-local chunk
    cap). The Sets tab embeds it via wui.editor(); the floating "dlac Stat
    Weights" window is gearui's renderSetsWeightPanel in a shell (registered as
    a uihost window).

    Two tabs since 2026-07-17 (Henrik's friends kept bouncing off the point
    system): Points -- the classic per-stat pts/cap rows -- and Priority -- an
    ORDERED stat list, top matters most, optional cap per stat, no numbers to
    reason about. Each tab owns its data, its per-set memory and its named
    store; whichever tab you EDIT becomes the set's build mode (looking never
    switches it). Both carry a "clear" button beside "save as...".

    Scoring itself (weightsActive / scoreOf) stays in gearui -- the Sets
    candidate machinery calls it every frame; this module is only the UI.
    Priority scoring is gearoptim's job too (dominance-derived weights behind
    optim.getWeights); this file never computes a score.

    Deps arrive once via wui.configure{} (the profilesets.configure precedent):
        ui                    -- gearui's live view-state table (_wbuf, addStat, ...)
        COL                   -- shared palette
        STAT_GROUPS           -- grouped stat names (the suggestion fallback)
        invalidateCandidates  -- weights changed: re-sort the candidate lists
]]--

local wui = {};

local fmt = require("dlac\\gear\\gearfmt");
local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end
local imgui    = try('imgui');
local optim    = try("dlac\\gear\\gearoptim");
local statdefs = try("dlac\\data\\statdefs");
local wimp     = try("dlac\\gear\\weightimport");
local oracle   = try("dlac\\gear\\gearoracle");
local hasStatdefs = statdefs ~= nil and type(statdefs.list) == 'table';
-- Multiline paste box probe (triggersui's group-import precedent): absent
-- binding -> a one-line box with a "keep it on one line" hint, never a crash.
local hasMultiline = (imgui ~= nil) and type(imgui.InputTextMultiline) == 'function';

local D = nil;   -- deps from gearui; editor() no-ops until configured
wui.configure = function(deps)
    if type(deps) == 'table' then D = deps; end
end

-- Cascading submenus for the copy-from menu: probe the binding, never assume
-- (hard rule 2; floatgear field-proved BeginMenu in this install; the
-- drill-down fallback uses only proven APIs).
local hasMenu = (imgui ~= nil)
    and (type(imgui.BeginMenu) == 'function') and (type(imgui.EndMenu) == 'function');

local function textW(s)
    local ok, w = pcall(imgui.CalcTextSize, s);
    if ok and type(w) == 'number' then return w; end
    return #tostring(s) * 7;
end

-- The (?) tooltip body for one stored source: its assigned weights, sorted.
local function weightsTip(kind, key)
    local t = nil;
    pcall(function() t = optim.peekWeights(kind, key); end);
    if type(t) ~= 'table' or next(t) == nil then return '(no weights set)'; end
    local keys = {};
    for k in pairs(t) do keys[#keys + 1] = k; end
    table.sort(keys);
    local lines = {};
    for _, k in ipairs(keys) do
        local w = t[k];
        lines[#lines + 1] = string.format('%s  %s%s', k, tostring(w.perUnit),
            (type(w.cap) == 'number') and ('  (cap ' .. tostring(w.cap) .. ')') or '');
    end
    return table.concat(lines, '\n');
end

-- Same, for a stored PRIORITY list: ordered lines, top first.
local function prioTip(kind, key)
    local t = nil;
    pcall(function() t = optim.peekPrio(kind, key); end);
    if type(t) ~= 'table' or #t == 0 then return '(empty list)'; end
    local lines = {};
    for i, e in ipairs(t) do
        lines[#lines + 1] = string.format('%d. %s%s', i, tostring(e.stat),
            (type(e.cap) == 'number') and ('  (cap ' .. tostring(e.cap) .. ')') or '');
    end
    return table.concat(lines, '\n');
end

-- Flat, de-duplicated stat list for the weights "add" searchable dropdown (kept in group
-- order). Typing still accepts any custom name; this is just the suggestion set.
local _choices = nil;
local function weightChoices()
    if _choices ~= nil then return _choices; end
    _choices = {};
    local seen = {};
    local function add(s) if not seen[s] then seen[s] = true; _choices[#_choices + 1] = s; end end
    for _, g in ipairs((D and D.STAT_GROUPS) or {}) do for _, s in ipairs(g.stats) do add(s); end end
    for _, s in ipairs({ 'DMG', 'Counter', 'MovementSpeed', 'PDT', 'DT' }) do add(s); end
    return _choices;
end

-- Suggestion list for the "add stat" pickers (both tabs). Sourced from statdefs when
-- available, so the search matches key/label/aliases (type "MATK" or "MagicAttackBonus"
-- -> find MAB) and picking inserts the CANONICAL key; falls back to the grouped choices.
-- Each entry:
--   { key = <canonical key to insert>, label = <display>, terms = {<lowercased key/label/aliases>} }
local _weightSuggest = nil;
local function weightSuggestions()
    if _weightSuggest ~= nil then return _weightSuggest; end
    local out = {};
    if hasStatdefs then
        for _, e in ipairs(statdefs.list) do
            local lbl = e.label or e.key;
            local terms = { string.lower(e.key) };
            if string.lower(lbl) ~= terms[1] then terms[#terms + 1] = string.lower(lbl); end
            if e.aliases ~= nil then for _, a in ipairs(e.aliases) do terms[#terms + 1] = string.lower(a); end end
            out[#out + 1] = { key = e.key, label = lbl, terms = terms };
        end
    else
        for _, name in ipairs(weightChoices()) do
            out[#out + 1] = { key = name, label = name, terms = { string.lower(name) } };
        end
    end
    -- The pet-channel family ('Pet:Haste' -> what your gear grants YOUR PET --
    -- scored via oracle.petScoreStats' namespace). Sourced from the oracle so the
    -- menu lists exactly the stats the pet data actually carries; terms include
    -- 'pet' plus the inner stat's key/label, so typing "pet" browses the family
    -- and "haste" still surfaces Pet:Haste beside Haste.
    if oracle ~= nil and type(oracle.petStatKeys) == 'function' then
        for _, k in ipairs(oracle.petStatKeys()) do
            local ie = hasStatdefs and statdefs.get(k) or nil;
            local innerLbl = (ie ~= nil and ie.label) or k;
            local key = 'Pet:' .. k;
            local terms = { 'pet', string.lower(key), string.lower(k) };
            if string.lower(innerLbl) ~= string.lower(k) then
                terms[#terms + 1] = string.lower(innerLbl);
            end
            out[#out + 1] = { key = key, label = 'Pet: ' .. innerLbl, terms = terms };
        end
    end
    _weightSuggest = out;
    return out;
end

-- One searchable stat picker (shared by both tabs' add rows). buf is the {text}
-- InputText buffer the chosen canonical key lands in; skip(lowerKey) -> true
-- hides an entry (the priority tab hides stats already listed); width overrides
-- the default combo width (the points tab sizes it to its Stat column).
local function statPickerCombo(id, buf, skip, width)
    imgui.PushItemWidth(width or 160);
    if imgui.BeginCombo('##' .. id, (buf[1] ~= '' and buf[1]) or '(type to search)') then
        if imgui.IsWindowAppearing ~= nil and imgui.IsWindowAppearing()
           and imgui.SetKeyboardFocusHere ~= nil then imgui.SetKeyboardFocusHere(0); end
        imgui.PushItemWidth(-1); imgui.InputText('##' .. id .. '_f', buf, 32); imgui.PopItemWidth();
        imgui.Separator();
        local q, shown = string.lower(buf[1] or ''), 0;
        for _, sug in ipairs(weightSuggestions()) do
            if skip == nil or not skip(string.lower(sug.key)) then
                local match = (q == '');
                if not match then
                    for _, t in ipairs(sug.terms) do
                        if string.find(t, q, 1, true) ~= nil then match = true; break; end
                    end
                end
                if match then
                    shown = shown + 1;
                    local disp = (sug.label ~= sug.key) and (sug.label .. '  (' .. sug.key .. ')') or sug.key;
                    if imgui.Selectable(disp .. '##' .. id .. '_s_' .. sug.key, false) then
                        buf[1] = sug.key;            -- insert the canonical key (not the alias/label)
                        imgui.CloseCurrentPopup();
                    end
                end
            end
        end
        if shown == 0 then imgui.TextColored(D.COL.DIM, '(no match -- Add will use your typed text)'); end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();
end

-- ---------------------------------------------------------------------------
-- The 4x4 build-slot grid (2026-07-17, replaces the Skip-weapons checkbox):
-- text-only tiles in equipmon's visual order marking which slots Auto-build
-- FILLS for the bound set (shared when none). Unmarked slots are left exactly
-- as the working set has them. Weapons default unmarked (swapping Main/Sub/
-- Range resets TP) but are one click away. Rides the same per-set binding and
-- gearweights.lua persistence as the weights -- no rebuilding marks between
-- sets. Checkbox toggles need no candidate invalidation: the mask changes
-- WHICH slots build, never how items score.
-- ---------------------------------------------------------------------------
wui.slotGrid = function()
    if D == nil or imgui == nil or optim == nil then return; end
    if type(D.EQUIP_SLOTS) ~= 'table' or type(optim.getSlotMask) ~= 'function' then return; end
    local COL = D.COL;
    local mask = nil;
    pcall(function() mask = optim.getSlotMask(); end);
    if type(mask) ~= 'table' then return; end
    imgui.TextColored(COL.DIM, 'build slots:');
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Mark the slots Auto-build fills; unmarked slots keep whatever the set\nalready holds. Each set remembers its own marks (with its weights).\nWeapons start unmarked so building never resets your TP -- tick them\nwhen you do want weapons picked.');
    end
    for i, sl in ipairs(D.EQUIP_SLOTS) do
        local b = { mask[sl.label] == true };
        if imgui.Checkbox(sl.short .. '##bslot_' .. sl.label, b) then
            pcall(optim.setSlotEnabled, sl.label, b[1]);
            pcall(optim.saveWeights);
        end
        if i % 4 ~= 0 then imgui.SameLine(math.floor((i % 4) * 74) + 1); end
    end
end

-- ---------------------------------------------------------------------------
-- Weights IMPORT (Henrik 2026-07-19; round 3, 07-20, splits it in two):
--   import...        -- LOCAL: paste ONE nameless table, it becomes THE BOUND
--                       SET's tuning directly (parseLocal / parsePrioLocal ->
--                       importSetWeights / importSetPrio, behind the copy-from
--                       revert snapshot). A single Name = wrapper is ignored;
--                       two+ named tables are refused.
--   manage shared... -- the named store's window ("Saved Sets" / "Saved
--                       Lists" in copy from...): list + delete, create from
--                       the current set, bulk-import `Name = {...}` tables
--                       (several at once, overwrite-confirmed) and export the
--                       store as re-importable text (weightimport pins the
--                       round trip).
-- Pure transforms in weightimport.lua; appliers in gearoptim; this is only
-- the popups. Each tab passes SPECs; popup state lives under
-- wui['_imp'|'_exp' .. key].
-- ---------------------------------------------------------------------------
local hasClipboard = (imgui ~= nil) and type(imgui.SetClipboardText) == 'function';

local function impState(spec)
    local slot = '_imp' .. spec.key;
    wui[slot] = wui[slot] or { text = { '' }, plan = nil };
    return wui[slot];
end

local function applyImport(spec, st)
    local plan = st.plan;
    if plan == nil or plan.parsed == nil then return; end
    local sum = nil;
    pcall(function() sum = spec.apply(plan.parsed); end);
    pcall(optim.saveWeights);
    plan.pending = false;
    plan.summary = sum or { created = 0, updated = 0, stats = 0 };
end

local function renderImportPopup(spec, COL)
    local st = impState(spec);
    for _, line in ipairs(spec.help) do imgui.TextColored(COL.DIM, line); end
    if hasMultiline then
        imgui.InputTextMultiline('##wimptext_' .. spec.key, st.text, 16384, { 430, 130 });
    else
        imgui.TextColored(COL.SCORE, '(this build has no multiline box -- keep the paste on ONE line)');
        imgui.PushItemWidth(430);
        imgui.InputText('##wimptext_' .. spec.key, st.text, 16384);
        imgui.PopItemWidth();
    end
    if imgui.Button('Import##wimpgo_' .. spec.key, { 0, 24 }) then
        local parsed, errs = spec.parse(st.text[1]);
        if parsed == nil then
            st.plan = { errors = errs or {}, created = {}, overwritten = {}, pending = false };
        else
            local existing = {};
            pcall(function() existing = spec.existing() or {}; end);
            local created, overwritten = wimp.classify(parsed, existing);
            st.plan = { parsed = parsed, errors = errs or {},
                        created = created, overwritten = overwritten, pending = true };
            -- No collisions -> land immediately; the confirm step is only for overwrites.
            if #overwritten == 0 then applyImport(spec, st); end
        end
    end
    if imgui.IsItemHovered() then imgui.SetTooltip('Parse the paste and preview what would be created / overwritten.'); end
    imgui.SameLine(0, 6);
    if imgui.Button('Clear##wimpclr_' .. spec.key, { 0, 24 }) then
        st.text[1] = ''; st.plan = nil;
    end
    local plan = st.plan;
    if plan ~= nil then
        imgui.Spacing();
        imgui.TextColored(COL.HEADER, plan.pending and 'Preview' or 'Imported');
        if #plan.created > 0 then
            imgui.TextColored(COL.SCORE, string.format('  create %d: %s', #plan.created, fmt.esc(table.concat(plan.created, ', '))));
        end
        if #plan.overwritten > 0 then
            imgui.TextColored(COL.ERR, string.format('  overwrite %d existing: %s', #plan.overwritten, fmt.esc(table.concat(plan.overwritten, ', '))));
        end
        if #plan.errors > 0 then
            imgui.TextColored(COL.DIM, string.format('  skip %d:', #plan.errors));
            for _, e in ipairs(plan.errors) do imgui.TextColored(COL.DIM, '     ' .. fmt.esc(e)); end
        end
        if #plan.created == 0 and #plan.overwritten == 0 and #plan.errors == 0 then
            imgui.TextColored(COL.DIM, '  (nothing to import)');
        end
        if plan.pending then
            if ImGuiCol_Button ~= nil then imgui.PushStyleColor(ImGuiCol_Button, { 0.72, 0.18, 0.18, 1.0 }); end
            if imgui.Button(string.format('Overwrite %d & import###wimpconfirm_%s', #plan.overwritten, spec.key), { 0, 24 }) then
                applyImport(spec, st);
            end
            if ImGuiCol_Button ~= nil then imgui.PopStyleColor(1); end
            if imgui.IsItemHovered() then imgui.SetTooltip('Replaces the named existing profile(s) with the paste.\nNamed profiles have no revert snapshot -- sure?'); end
            imgui.SameLine(0, 6);
            if imgui.Button('Cancel##wimpcancel_' .. spec.key, { 0, 24 }) then
                st.plan = nil;
            end
        elseif plan.summary ~= nil then
            imgui.TextColored(COL.DIM, string.format('  %d created, %d updated, %d rows.',
                plan.summary.created or 0, plan.summary.updated or 0, plan.summary.stats or 0));
        end
    end
end

-- The export popup: the store rendered to importable text at button-click
-- time (wui['_exp'..key]), shown in a box whose buffer is rebuilt every frame
-- -- edits never stick, so it reads as a copy source, not an editor.
local function renderExportPopup(specKey, text, COL)
    if text == nil or text == '' then
        imgui.TextColored(COL.DIM, '(nothing shared yet -- create or import one above first)');
        return;
    end
    imgui.TextColored(COL.DIM, 'Copy this block -- the matching import... accepts it verbatim.');
    local buf = { text };
    if hasMultiline then
        imgui.InputTextMultiline('##wexptext_' .. specKey, buf, #text + 64, { 430, 200 });
    else
        imgui.PushItemWidth(430);
        imgui.InputText('##wexptext_' .. specKey, buf, #text + 64);
        imgui.PopItemWidth();
    end
    if hasClipboard then
        if imgui.Button('Copy to clipboard##wexpcopy_' .. specKey, { 0, 24 }) then
            pcall(function() imgui.SetClipboardText(text); end);
        end
    end
end

-- The two named-store (shared) import specs, fed to renderImportPopup inside
-- the manage shared... window. Guarded at the call sites on wimp + the applier.
local PTS_SPEC = {
    key = 'pts',
    help = {
        'One Saved Set per name. A weight is  pts,  { pts, cap }  or  { perUnit = ..., cap = ... }.',
        'e.g.   Debuff = { MACC = 12, BlueMagicSkill = 12, INT = 10 },',
        'Stat spellings are forgiving (ACC / Acc / Accuracy all resolve). Apply via copy from... > Saved Sets.',
    },
    parse    = function(t) return wimp.parse(t); end,
    existing = function() return optim.namedKeys(); end,
    apply    = function(p) return optim.importNamedWeights(p); end,
};
local PRIO_SPEC = {
    key = 'prio',
    help = {
        'One Saved List per name -- ORDERED, top matters most. An entry is  \'Stat\'  or  { \'Stat\', cap }.',
        'e.g.   Debuff = { \'MACC\', \'BlueMagicSkill\', { \'INT\', 60 } },',
        'Stat spellings are forgiving. Apply via copy from... > Saved Lists.',
    },
    parse    = function(t) return wimp.parsePrio(t); end,
    existing = function() return optim.prioNamedKeys(); end,
    apply    = function(p) return optim.importNamedPrio(p); end,
};

-- The LOCAL import specs (Henrik 07-20): import... feeds the BOUND SET
-- directly -- ONE nameless table, no named-store detour. applied() is the
-- post-import housekeeping (stale edit buffers + candidate re-sort).
local PTS_LOCAL = {
    key = 'lpts',
    help = {
        'Paste ONE plain table -- it becomes THIS set\'s point weights, no name needed:',
        '    { Accuracy = 12, Attack = 10, STR = 10, BlueMagicSkill = { 3, 40 } }',
        'A single  Name = {...}  wrapper is ignored; several named tables are refused',
        '(import those via manage shared...). Stat spellings are forgiving.',
    },
    what    = 'stat',
    parse   = function(t) return wimp.parseLocal(t); end,
    apply   = function(p) return optim.importSetWeights(p); end,
    applied = function() D.ui._wbuf = {}; D.invalidateCandidates(); end,
};
local PRIO_LOCAL = {
    key = 'lprio',
    help = {
        'Paste ONE plain ORDERED list -- it becomes THIS set\'s priority list, no name needed:',
        '    { \'MACC\', \'BlueMagicSkill\', { \'INT\', 60 } }',
        'A single  Name = {...}  wrapper is ignored; several named lists are refused',
        '(import those via manage shared...). Top matters most.',
    },
    what    = 'row',
    parse   = function(t) return wimp.parsePrioLocal(t); end,
    apply   = function(p) return optim.importSetPrio(p); end,
    applied = function() wui._pbuf = {}; D.invalidateCandidates(); end,
};

-- The manage shared... window descriptors: one place to see, create, delete,
-- bulk-import and export the named store. spec = the bulk-import SPEC above.
local PTS_SHARED = {
    key = 'pts', spec = PTS_SPEC,
    title = 'Shared weight sets',
    hint  = '("Saved Sets" in copy from... -- reachable from every job and set)',
    names  = function() return optim.namedKeys(); end,
    tip    = function(n) return weightsTip('named', n); end,
    create = function(n) return optim.saveNamedWeights(n); end,
    delete = function(n) return optim.deleteNamedWeights(n); end,
    render = function() return wimp.renderPoints(optim.allNamedWeights()); end,
    createTip = 'Save THIS set\'s current weights + build-slot marks under the name.\nSame name = update in place.',
};
local PRIO_SHARED = {
    key = 'prio', spec = PRIO_SPEC,
    title = 'Shared priority lists',
    hint  = '("Saved Lists" in copy from... -- reachable from every job and set)',
    names  = function() return optim.prioNamedKeys(); end,
    tip    = function(n) return prioTip('named', n); end,
    create = function(n) return optim.savePrioNamed(n); end,
    delete = function(n) return optim.deletePrioNamed(n); end,
    render = function() return wimp.renderPrio(optim.allNamedPrio()); end,
    createTip = 'Save THIS set\'s current priority list under the name.\nSame name = update in place.',
};

-- The LOCAL import popup body: paste -> parse -> apply to the bound set
-- immediately. No confirm step: the target is always this set, and the
-- copy-from revert snapshot is the safety net.
local function renderLocalImportPopup(spec, COL)
    local st = impState(spec);
    for _, line in ipairs(spec.help) do imgui.TextColored(COL.DIM, line); end
    if hasMultiline then
        imgui.InputTextMultiline('##wlimptext_' .. spec.key, st.text, 16384, { 470, 120 });
    else
        imgui.TextColored(COL.SCORE, '(this build has no multiline box -- keep the paste on ONE line)');
        imgui.PushItemWidth(470);
        imgui.InputText('##wlimptext_' .. spec.key, st.text, 16384);
        imgui.PopItemWidth();
    end
    if imgui.Button('Import##wlimpgo_' .. spec.key, { 0, 24 }) then
        local parsed, errs = spec.parse(st.text[1]);
        if parsed == nil then
            st.plan = { errors = errs or {} };
        else
            local ok, n = false, nil;
            pcall(function() ok, n = spec.apply(parsed); end);
            if ok then
                pcall(optim.saveWeights);
                spec.applied();
                st.plan = { errors = errs or {}, n = tonumber(n) or 0 };
            else
                st.plan = { errors = { tostring(n or 'import failed') } };
            end
        end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Replace this set\'s current tuning with the paste.\nMis-paste? copy from... > revert restores what was there.');
    end
    imgui.SameLine(0, 6);
    if imgui.Button('Clear##wlimpclr_' .. spec.key, { 0, 24 }) then
        st.text[1] = ''; st.plan = nil;
    end
    local plan = st.plan;
    if plan ~= nil then
        imgui.Spacing();
        if plan.n ~= nil then
            imgui.TextColored(COL.SCORE, string.format('Imported %d %s%s into this set.',
                plan.n, spec.what, (plan.n == 1) and '' or 's'));
        end
        for _, e in ipairs(plan.errors) do fmt.textWrapped(COL.ERR, fmt.esc(e)); end
    end
end

-- The manage shared... window body: the named store's verbs in one place --
-- list + delete (red second-click confirm, the copy-from pattern), create
-- from the current set, the bulk import, and the export text.
local function renderSharedPopup(sh, COL)
    imgui.TextColored(COL.HEADER, sh.title);
    imgui.SameLine(0, 8);
    imgui.TextColored(COL.DIM, sh.hint);
    imgui.Spacing();
    local named = {};
    pcall(function() named = sh.names() or {}; end);
    if #named == 0 then
        imgui.TextColored(COL.DIM, '(none yet -- create or import one below)');
    end
    local colQ = 110;
    for _, n in ipairs(named) do
        local w = textW(n) + 18;
        if w > colQ then colQ = w; end
    end
    for _, n in ipairs(named) do
        imgui.TextColored(COL.USABLE, fmt.esc(n));
        imgui.SameLine(colQ);
        imgui.TextColored(COL.DIM, '(?)');
        if imgui.IsItemHovered() then imgui.SetTooltip(sh.tip(n)); end
        imgui.SameLine(0, 8);
        local armKey = 'm:' .. sh.key .. ':' .. n;
        if wui._delArm == armKey then
            local red = (ImGuiCol_Button ~= nil);
            if red then imgui.PushStyleColor(ImGuiCol_Button, { 0.72, 0.18, 0.18, 1.0 }); end
            if imgui.SmallButton('sure?##wshd_' .. n) then
                pcall(sh.delete, n);
                pcall(optim.saveWeights);
                wui._delArm = nil;
            end
            if red then imgui.PopStyleColor(1); end
        else
            if imgui.SmallButton('x##wshd_' .. n) then wui._delArm = armKey; end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Delete this shared entry -- the second (red) click confirms.\nSets that copied from it keep their copy.');
            end
        end
    end
    imgui.Separator();
    imgui.TextColored(COL.DIM, 'create from this set:');
    imgui.SameLine(0, 6);
    wui._sharedName = wui._sharedName or { '' };
    imgui.PushItemWidth(160);
    imgui.InputText('##wshname_' .. sh.key, wui._sharedName, 48);
    imgui.PopItemWidth();
    imgui.SameLine(0, 6);
    if imgui.Button('Create##wshcreate_' .. sh.key, { 0, 22 }) then
        local ok = false;
        pcall(function() ok = sh.create(wui._sharedName[1]); end);
        if ok then
            pcall(optim.saveWeights);
            wui._sharedName[1] = '';
        end
    end
    if imgui.IsItemHovered() then imgui.SetTooltip(sh.createTip); end
    imgui.Separator();
    imgui.TextColored(COL.HEADER, 'Import shared');
    renderImportPopup(sh.spec, COL);
    imgui.Separator();
    local expOpen = true;
    if type(imgui.CollapsingHeader) == 'function' then
        expOpen = imgui.CollapsingHeader('Export all as text###wshexp_' .. sh.key);
    else
        imgui.TextColored(COL.HEADER, 'Export');
    end
    if expOpen then
        local text = nil;
        pcall(function() text = sh.render(); end);
        renderExportPopup(sh.key, text, COL);
    end
end

-- The set's build mode ('points' | 'priority'), read fresh each frame.
local function modeNow()
    local m = 'points';
    pcall(function() m = optim.weightsMode() or 'points'; end);
    return m;
end

-- ---------------------------------------------------------------------------
-- POINTS tab (the classic editor): per-stat pts/cap rows, live-apply,
-- copy from... / save as... / clear, sortable Stat/Points/Cap columns.
-- ---------------------------------------------------------------------------
local function renderPointsTab(boundKey)
    local ui, COL = D.ui, D.COL;

    -- Mode banner: looking at this tab never switches the mode -- say so when
    -- the OTHER tab is the one actually building this set.
    if modeNow() == 'priority' then
        fmt.textWrapped(COL.SCORE, '[!] This set builds from the Priority tab right now. Editing anything here switches it back to point weights.');
    end

    -- Copy another tuning (weights + build-slot marks) into THIS one -- a
    -- CASCADING menu (Henrik: the floatgear pattern, not one flat bloaty
    -- list): This set (revert) / Saved Sets > / (shared) / then one submenu
    -- per job. Every source row carries a (?) in its own reserved column
    -- whose hover lists the assigned weights. Typing in the search box
    -- overrides the cascade with one flat filtered list.
    if type(optim.copyWeightsFrom) == 'function' and type(optim.perSetKeys) == 'function' then
        if imgui.SmallButton('copy from...##wcopy') then
            wui._copyQ = { '' };
            wui._copyDrill = nil;
            wui._delArm = nil;
            imgui.OpenPopup('##wcopy_pop');
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Replace this table\'s weights AND build-slot marks with a copy:\nThis set (revert) / Saved Sets / any job\'s per-set weights.\nThe source is never touched.');
        end
        -- save as...: name the CURRENT tuning; it lands under Saved Sets.
        if type(optim.saveNamedWeights) == 'function' then
            imgui.SameLine(0, 6);
            if imgui.SmallButton('save as...##wsaveas') then
                wui._saveName = { '' };
                imgui.OpenPopup('##wsaveas_pop');
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Found a tuning that works? Save the current weights + build-slot\nmarks under a proper name -- it lands in copy from... > Saved Sets,\nreachable from every job and set. Same name = update in place.');
            end
            if imgui.BeginPopup('##wsaveas_pop') then
                if imgui.IsWindowAppearing ~= nil and imgui.IsWindowAppearing()
                   and imgui.SetKeyboardFocusHere ~= nil then imgui.SetKeyboardFocusHere(0); end
                wui._saveName = wui._saveName or { '' };
                imgui.PushItemWidth(180);
                imgui.InputText('##wsavename', wui._saveName, 48);
                imgui.PopItemWidth();
                imgui.SameLine(0, 6);
                if imgui.Button('Save##wsavego', { 50, 0 }) then
                    local oks = false;
                    pcall(function() oks = optim.saveNamedWeights(wui._saveName[1]); end);
                    if oks then
                        pcall(optim.saveWeights);
                        imgui.CloseCurrentPopup();
                    end
                end
                imgui.EndPopup();
            end
        end
        -- clear: empty this table (Henrik 07-17). Recoverable -- the clear takes
        -- the same snapshot a copy does, so This set (revert) restores it.
        if type(optim.clearAllWeights) == 'function' then
            imgui.SameLine(0, 6);
            if imgui.SmallButton('clear##wclearall') then
                pcall(optim.clearAllWeights);
                pcall(optim.saveWeights);
                ui._wbuf = {};
                D.invalidateCandidates();
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Remove EVERY stat weight from this table (build-slot marks stay).\nMis-click? copy from... > This set (revert) brings it back.');
            end
        end
        -- import...: ONE nameless table straight into THIS set (Henrik 07-20;
        -- the named bulk import + export live under manage shared... now).
        if wimp ~= nil and type(wimp.parseLocal) == 'function'
           and type(optim.importSetWeights) == 'function' then
            imgui.SameLine(0, 6);
            if imgui.SmallButton('import...##wimport') then
                impState(PTS_LOCAL).plan = nil;
                imgui.OpenPopup('##wlimport_pop');
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Paste ONE plain  { Stat = pts, ... }  table -- it becomes THIS set\'s\nweights, no name needed. Several named tables at once go through\nmanage shared... instead.');
            end
            imgui.SetNextWindowSizeConstraints({ 490, 0 }, { 620, 420 });
            if imgui.BeginPopup('##wlimport_pop') then
                renderLocalImportPopup(PTS_LOCAL, COL);
                imgui.EndPopup();
            end
        end
        -- manage shared...: the Saved Sets store's window -- create, delete,
        -- bulk-import and export shared tunings.
        if wimp ~= nil and type(optim.importNamedWeights) == 'function' then
            imgui.SameLine(0, 6);
            if imgui.SmallButton('manage shared...##wshared') then
                impState(PTS_SPEC).plan = nil;
                wui._sharedName = { '' };
                wui._delArm = nil;
                imgui.OpenPopup('##wshared_pop');
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('The shared store behind copy from... > Saved Sets: create one from this\nset, delete one, bulk-import  Name = { Stat = pts, ... }  tables (several\nat once) or export them all as text.');
            end
            imgui.SetNextWindowSizeConstraints({ 500, 0 }, { 620, 560 });
            if imgui.BeginPopup('##wshared_pop') then
                renderSharedPopup(PTS_SHARED, COL);
                imgui.EndPopup();
            end
        end

        -- Bound height (floatgear's rule: constrain the popup, never a child
        -- in a menu chain); safe to call unconditionally in this binding.
        imgui.SetNextWindowSizeConstraints({ 250, 0 }, { 380, 340 });
        if imgui.BeginPopup('##wcopy_pop') then
            local function applied(ok)
                if ok then
                    ui._wbuf = {};
                    pcall(optim.saveWeights);
                    D.invalidateCandidates();
                end
                imgui.CloseCurrentPopup();
            end
            -- One source row: fixed-width selectable + the (?) box in its own
            -- reserved column, straight under the others (static position).
            -- doDelete (named rows only) adds an x with a red second-click
            -- confirm -- named deletions have no revert snapshot, so a single
            -- stray click must never be enough.
            local function srcRow(id, label, colQ, kind, key, doCopy, doDelete)
                if imgui.Selectable(label .. '##wc_' .. id, false, 0, { colQ - 6, 0 }) then
                    local ok = false;
                    pcall(function() ok = doCopy(); end);
                    applied(ok);
                end
                imgui.SameLine(colQ);
                imgui.TextColored(COL.DIM, '(?)');
                if imgui.IsItemHovered() then imgui.SetTooltip(weightsTip(kind, key)); end
                if doDelete ~= nil then
                    imgui.SameLine(0, 8);
                    local armKey = kind .. ':' .. tostring(key);
                    if wui._delArm == armKey then
                        local red = (ImGuiCol_Button ~= nil);
                        if red then imgui.PushStyleColor(ImGuiCol_Button, { 0.72, 0.18, 0.18, 1.0 }); end
                        if imgui.SmallButton('sure?##wcd_' .. id) then
                            pcall(doDelete);
                            pcall(optim.saveWeights);
                            wui._delArm = nil;
                        end
                        if red then imgui.PopStyleColor(1); end
                    else
                        if imgui.SmallButton('x##wcd_' .. id) then wui._delArm = armKey; end
                        if imgui.IsItemHovered() then
                            imgui.SetTooltip('Delete this saved profile -- the second (red) click confirms.');
                        end
                    end
                end
            end
            local function colQof(labels)
                local w = 110;
                for _, l in ipairs(labels) do
                    local lw = textW(l) + 18;
                    if lw > w then w = lw; end
                end
                return w;
            end
            local named, keys = {}, {};
            pcall(function() named = optim.namedKeys() or {}; end);
            pcall(function() keys = optim.perSetKeys() or {}; end);

            if imgui.IsWindowAppearing ~= nil and imgui.IsWindowAppearing()
               and imgui.SetKeyboardFocusHere ~= nil then imgui.SetKeyboardFocusHere(0); end
            wui._copyQ = wui._copyQ or { '' };
            imgui.PushItemWidth(200);
            imgui.InputText('##wcopy_q', wui._copyQ, 48);
            imgui.PopItemWidth();
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Type to search every source flat (saved profiles + JOB|Set).');
            end
            local q = string.lower(wui._copyQ[1] or '');

            if q ~= '' then
                -- Search overrides the cascade: one flat filtered list.
                local labels = {};
                for _, n in ipairs(named) do labels[#labels + 1] = 'Saved: ' .. n; end
                for _, k in ipairs(keys) do labels[#labels + 1] = k; end
                local colQ = colQof(labels);
                local shown = 0;
                for _, n in ipairs(named) do
                    if string.find(string.lower(n), q, 1, true) ~= nil then
                        shown = shown + 1;
                        srcRow('n_' .. n, 'Saved: ' .. n, colQ, 'named', n,
                            function() return optim.copyWeightsFromNamed(n); end,
                            function() return optim.deleteNamedWeights(n); end);
                    end
                end
                for _, k in ipairs(keys) do
                    if k ~= boundKey and string.find(string.lower(k), q, 1, true) ~= nil then
                        shown = shown + 1;
                        srcRow('k_' .. k, k, colQ, 'set', k,
                            function() return optim.copyWeightsFrom(k); end);
                    end
                end
                if shown == 0 then imgui.TextColored(COL.DIM, '(no match)'); end
            else
                -- 1. This set (revert) -- ABSOLUTE TOP, no cascade, no (?).
                local canRevert = false;
                pcall(function() canRevert = optim.copyUndoAvailable(); end);
                if canRevert then
                    if imgui.Selectable('This set  (revert to before copying)##wcrevert') then
                        local ok = false;
                        pcall(function() ok = optim.revertCopiedWeights(); end);
                        applied(ok);
                    end
                    if imgui.IsItemHovered() then
                        imgui.SetTooltip('Restore this table to how it was BEFORE its first copy or clear\n(the snapshot lives until the addon reloads).');
                    end
                else
                    imgui.TextColored(COL.DIM, 'This set  (nothing copied yet)');
                end
                imgui.Separator();

                -- 2. Saved Sets -> cascade of named profiles.
                local savedColQ = colQof(named);
                local function savedRows()
                    if #named == 0 then
                        imgui.TextColored(COL.DIM, '(none yet -- "save as..." beside copy from)');
                        return;
                    end
                    for _, n in ipairs(named) do
                        srcRow('n_' .. n, n, savedColQ, 'named', n,
                            function() return optim.copyWeightsFromNamed(n); end,
                            function() return optim.deleteNamedWeights(n); end);
                    end
                end
                -- 3. One submenu per job that has per-set weights stored.
                local jobs, jobSets = {}, {};
                for _, k in ipairs(keys) do
                    local j = string.match(k, '^([^|]+)|') or '?';
                    if jobSets[j] == nil then jobSets[j] = {}; jobs[#jobs + 1] = j; end
                    jobSets[j][#jobSets[j] + 1] = k;
                end
                local function jobRows(j)
                    local colQ = colQof(jobSets[j]);
                    for _, k in ipairs(jobSets[j]) do
                        if k ~= boundKey then
                            srcRow('k_' .. k, k, colQ, 'set', k,
                                function() return optim.copyWeightsFrom(k); end);
                        else
                            imgui.TextColored(COL.DIM, k .. '  (this set)');
                        end
                    end
                end

                if hasMenu then
                    if imgui.BeginMenu('Saved Sets##wcsaved') then
                        savedRows();
                        imgui.EndMenu();
                    end
                    imgui.Separator();
                    if #jobs == 0 then
                        imgui.TextColored(COL.DIM, '(no per-set weights stored yet)');
                    end
                    for _, j in ipairs(jobs) do
                        if imgui.BeginMenu(j .. '##wcjob' .. j) then
                            jobRows(j);
                            imgui.EndMenu();
                        end
                    end
                else
                    -- Drill-down fallback (floatgear's shape: proven APIs only).
                    if wui._copyDrill == 'saved' then
                        if imgui.Selectable('< back##wcback') then
                            wui._copyDrill = nil;
                        else
                            imgui.Separator();
                            savedRows();
                        end
                    elseif type(wui._copyDrill) == 'string' and jobSets[wui._copyDrill] ~= nil then
                        if imgui.Selectable('< back##wcback') then
                            wui._copyDrill = nil;
                        else
                            imgui.Separator();
                            jobRows(wui._copyDrill);
                        end
                    else
                        if imgui.Selectable('Saved Sets  >##wcsaved') then wui._copyDrill = 'saved'; end
                        imgui.Separator();
                        for _, j in ipairs(jobs) do
                            if imgui.Selectable(j .. '  >##wcjob' .. j) then wui._copyDrill = j; end
                        end
                    end
                end
            end
            imgui.EndPopup();
        end
    end
    imgui.TextColored(COL.DIM, 'pts/point up to cap (cap 0 = none) -- applies as you type:');
    imgui.BeginChild('##ffxilac_weights', { -1, -1 }, true);   -- fill the (now windowed) space

    -- FIXED columns, header and rows on the same x/width (Henrik 07-17 round 2:
    -- the themed font is wide, so guessed pixel widths clipped "Points" into
    -- "Cap"). Widths are MEASURED from the widest state of each header (sort
    -- marker shown) via CalcTextSize, the same lesson as the fixed-width
    -- buttons; the Stat column takes whatever the window has left.
    local availW = imgui.GetContentRegionAvail();
    local ptsW   = math.max(56, textW('Points  v') + 10);
    local capW   = math.max(46, textW('Cap  v') + 10);
    local endW   = 46;                                -- widest of x (rows) / Add (add row)
    local nameCol = availW - (ptsW + capW + endW + 18);
    if nameCol < 44 then nameCol = 44; end
    local capCol = nameCol + ptsW + 6;
    local xCol   = capCol + capW + 6;
    local nchars = math.max(6, math.floor(nameCol / 7));

    local ws = {};
    pcall(function() ws = (type(optim.getPointWeights) == 'function')
        and optim.getPointWeights() or optim.getWeights() or {}; end);

    -- Sortable column headers (Henrik 07-17): click Stat / Points / Cap to sort
    -- the rows; click the active one again to flip. State survives in wui only
    -- for the session -- the default (Stat, ascending) is the old alphabetical.
    wui._sortCol = wui._sortCol or 'stat';
    if wui._sortAsc == nil then wui._sortAsc = true; end
    local function sortHeader(label, col, x, w, defAsc)
        if x > 0 then imgui.SameLine(x); end
        local active = (wui._sortCol == col);
        local mark = active and (wui._sortAsc and '  ^' or '  v') or '';
        if imgui.Selectable(label .. mark .. '##wsort_' .. col, false, 0, { w, 0 }) then
            if active then wui._sortAsc = not wui._sortAsc;
            else wui._sortCol = col; wui._sortAsc = defAsc; end
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Sort by ' .. label .. (active and ' (click to flip)' or ''));
        end
    end
    sortHeader('Stat', 'stat', 0, nameCol - 8, true);
    sortHeader('Points', 'pts', nameCol, ptsW, false);   -- numbers default big-first
    sortHeader('Cap', 'cap', capCol, capW, false);
    imgui.Separator();

    local keys = {};
    for k in pairs(ws) do keys[#keys + 1] = k; end
    local col, asc = wui._sortCol, wui._sortAsc;
    table.sort(keys, function(a, b)
        if col ~= 'stat' then
            local va, vb;
            if col == 'pts' then
                va = (type(ws[a]) == 'table' and ws[a].perUnit) or 0;
                vb = (type(ws[b]) == 'table' and ws[b].perUnit) or 0;
            else
                va = (type(ws[a]) == 'table' and ws[a].cap) or 0;
                vb = (type(ws[b]) == 'table' and ws[b].cap) or 0;
            end
            if va ~= vb then
                if asc then return va < vb; else return va > vb; end
            end
            return string.lower(a) < string.lower(b);   -- stable tie-break
        end
        local la, lb = string.lower(a), string.lower(b);
        if la ~= lb then
            if asc then return la < lb; else return la > lb; end
        end
        return a < b;
    end);

    for _, stat in ipairs(keys) do
        local w = ws[stat];
        local b = ui._wbuf[stat];
        if b == nil then
            local pv = (type(w) == 'table' and w.perUnit) or 0;
            b = { per = { math.floor(pv + 0.5) }, cap = { (type(w) == 'table' and w.cap) or 0 } };
            ui._wbuf[stat] = b;
        end
        imgui.TextColored(COL.USABLE, fmt.truncate(stat, nchars));
        if #stat > nchars and imgui.IsItemHovered() then imgui.SetTooltip(stat); end
        imgui.SameLine(nameCol);
        imgui.PushItemWidth(ptsW - 6);
        local chgPer = imgui.InputInt('##per_' .. stat, b.per, 0);
        imgui.PopItemWidth();
        imgui.SameLine(capCol);
        imgui.PushItemWidth(capW - 6);
        local chgCap = imgui.InputInt('##cap_' .. stat, b.cap, 0);
        imgui.PopItemWidth();
        -- Live apply (Henrik): the number in the box IS the weight -- a "Set" click
        -- was too easy to miss. Mid-typing values ("2" on the way to "20") apply
        -- transiently and self-correct on the next keystroke.
        if chgPer or chgCap then
            pcall(optim.setWeight, stat, b.per[1], (b.cap[1] and b.cap[1] > 0) and b.cap[1] or nil);
            pcall(optim.saveWeights);
            D.invalidateCandidates();
        end
        imgui.SameLine(xCol);
        if imgui.Button('x##wx_' .. stat, { 20, 0 }) then
            pcall(optim.clearWeight, stat);
            pcall(optim.saveWeights);
            ui._wbuf[stat] = nil;
            D.invalidateCandidates();
        end
    end

    imgui.Separator();

    -- Add row: searchable stat dropdown -- type in the box to filter suggestions,
    -- click one (or keep your own text), then Add. The inputs sit ON the Points/
    -- Cap columns (no inline labels -- the headers name them).
    imgui.TextColored(COL.DIM, 'add'); imgui.SameLine(0, 4);
    local comboW = nameCol - (textW('add') + 14);
    if comboW < 80 then comboW = 80; end
    statPickerCombo('addstat', ui.addStat, nil, comboW);
    imgui.SameLine(nameCol);
    imgui.PushItemWidth(ptsW - 6); imgui.InputInt('##addper', ui.addPer, 0); imgui.PopItemWidth();
    imgui.SameLine(capCol);
    imgui.PushItemWidth(capW - 6); imgui.InputInt('##addcap', ui.addCap, 0); imgui.PopItemWidth();
    imgui.SameLine(xCol);
    if imgui.Button('Add##addw', { endW, 0 }) then
        local name = ui.addStat[1];
        if name ~= nil and name ~= '' then
            pcall(optim.setWeight, name, ui.addPer[1], (ui.addCap[1] and ui.addCap[1] > 0) and ui.addCap[1] or nil);
            pcall(optim.saveWeights);
            ui.addStat[1] = '';
            D.invalidateCandidates();
        end
    end

    imgui.EndChild();
end

-- ---------------------------------------------------------------------------
-- PRIORITY tab (the simple mode): an ordered stat list, top matters most,
-- optional cap per stat. Its own per-set memory, its own Saved Lists store
-- (never mixes with point templates), same copy/save/clear/revert verbs.
-- ---------------------------------------------------------------------------
local function renderPrioTab(boundKey)
    local ui, COL = D.ui, D.COL;

    if modeNow() == 'points' then
        fmt.textWrapped(COL.SCORE, '[!] This set builds from the Points tab right now. Editing anything here switches it to the priority list.');
    end

    -- Everything a prio edit must do besides the edit itself.
    local function prioChanged()
        wui._pbuf = {};
        pcall(optim.saveWeights);
        D.invalidateCandidates();
    end

    -- copy from...: flat menu -- prio sources stay few (This list revert /
    -- Saved Lists / shared / per-set); the points tab's cascade would be
    -- ceremony here.
    if imgui.SmallButton('copy from...##pcopy') then
        wui._delArm = nil;
        imgui.OpenPopup('##pcopy_pop');
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Replace this priority list with a copy of a saved or per-set one.\nLists only -- build-slot marks and point weights are never touched.');
    end
    imgui.SameLine(0, 6);
    if imgui.SmallButton('save as...##psaveas') then
        wui._pSaveName = { '' };
        imgui.OpenPopup('##psaveas_pop');
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Save the current priority list under a proper name -- it lands in\ncopy from... > Saved Lists, reachable from every job and set.\nSame name = update in place. Separate from the Points tab\'s saves:\na point template and a priority list never cross-load.');
    end
    if imgui.BeginPopup('##psaveas_pop') then
        if imgui.IsWindowAppearing ~= nil and imgui.IsWindowAppearing()
           and imgui.SetKeyboardFocusHere ~= nil then imgui.SetKeyboardFocusHere(0); end
        wui._pSaveName = wui._pSaveName or { '' };
        imgui.PushItemWidth(180);
        imgui.InputText('##psavename', wui._pSaveName, 48);
        imgui.PopItemWidth();
        imgui.SameLine(0, 6);
        if imgui.Button('Save##psavego', { 50, 0 }) then
            local oks = false;
            pcall(function() oks = optim.savePrioNamed(wui._pSaveName[1]); end);
            if oks then
                pcall(optim.saveWeights);
                imgui.CloseCurrentPopup();
            end
        end
        imgui.EndPopup();
    end
    imgui.SameLine(0, 6);
    if imgui.SmallButton('clear##pclear') then
        pcall(optim.prioClear);
        prioChanged();
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Empty this priority list.\nMis-click? copy from... > This list (revert) brings it back.');
    end
    -- import...: ONE nameless ordered list straight into THIS set (Henrik
    -- 07-20; the named bulk import + export live under manage shared... now).
    if wimp ~= nil and type(wimp.parsePrioLocal) == 'function'
       and type(optim.importSetPrio) == 'function' then
        imgui.SameLine(0, 6);
        if imgui.SmallButton('import...##pimport') then
            impState(PRIO_LOCAL).plan = nil;
            imgui.OpenPopup('##plimport_pop');
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Paste ONE plain ordered list --  { \'MACC\', { \'INT\', 60 } }  -- it becomes\nTHIS set\'s priority list, no name needed. Several named lists at once\ngo through manage shared... instead.');
        end
        imgui.SetNextWindowSizeConstraints({ 490, 0 }, { 620, 420 });
        if imgui.BeginPopup('##plimport_pop') then
            renderLocalImportPopup(PRIO_LOCAL, COL);
            imgui.EndPopup();
        end
    end
    -- manage shared...: the Saved Lists store's window.
    if wimp ~= nil and type(optim.importNamedPrio) == 'function' then
        imgui.SameLine(0, 6);
        if imgui.SmallButton('manage shared...##pshared') then
            impState(PRIO_SPEC).plan = nil;
            wui._sharedName = { '' };
            wui._delArm = nil;
            imgui.OpenPopup('##pshared_pop');
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('The shared store behind copy from... > Saved Lists: create one from this\nset, delete one, bulk-import  Name = { \'Stat\', ... }  lists (several at\nonce) or export them all as text.');
        end
        imgui.SetNextWindowSizeConstraints({ 500, 0 }, { 620, 560 });
        if imgui.BeginPopup('##pshared_pop') then
            renderSharedPopup(PRIO_SHARED, COL);
            imgui.EndPopup();
        end
    end

    imgui.SetNextWindowSizeConstraints({ 250, 0 }, { 380, 340 });
    if imgui.BeginPopup('##pcopy_pop') then
        local function appliedP(ok)
            if ok then prioChanged(); end
            imgui.CloseCurrentPopup();
        end
        local function pRow(id, label, colQ, kind, key, doCopy, doDelete)
            if imgui.Selectable(label .. '##pc_' .. id, false, 0, { colQ - 6, 0 }) then
                local ok = false;
                pcall(function() ok = doCopy(); end);
                appliedP(ok);
            end
            imgui.SameLine(colQ);
            imgui.TextColored(COL.DIM, '(?)');
            if imgui.IsItemHovered() then imgui.SetTooltip(prioTip(kind, key)); end
            if doDelete ~= nil then
                imgui.SameLine(0, 8);
                local armKey = 'p:' .. kind .. ':' .. tostring(key);
                if wui._delArm == armKey then
                    local red = (ImGuiCol_Button ~= nil);
                    if red then imgui.PushStyleColor(ImGuiCol_Button, { 0.72, 0.18, 0.18, 1.0 }); end
                    if imgui.SmallButton('sure?##pcd_' .. id) then
                        pcall(doDelete);
                        pcall(optim.saveWeights);
                        wui._delArm = nil;
                    end
                    if red then imgui.PopStyleColor(1); end
                else
                    if imgui.SmallButton('x##pcd_' .. id) then wui._delArm = armKey; end
                    if imgui.IsItemHovered() then
                        imgui.SetTooltip('Delete this saved list -- the second (red) click confirms.');
                    end
                end
            end
        end
        local named, keys = {}, {};
        pcall(function() named = optim.prioNamedKeys() or {}; end);
        pcall(function() keys = optim.prioPerSetKeys() or {}; end);
        local colQ = 110;
        for _, l in ipairs(named) do local w = textW(l) + 18; if w > colQ then colQ = w; end end
        for _, l in ipairs(keys)  do local w = textW(l) + 18; if w > colQ then colQ = w; end end

        local canRevert = false;
        pcall(function() canRevert = optim.prioUndoAvailable(); end);
        if canRevert then
            if imgui.Selectable('This list  (revert to before copying)##pcrevert') then
                local ok = false;
                pcall(function() ok = optim.revertCopiedPrio(); end);
                appliedP(ok);
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Restore this list to how it was BEFORE its first copy or clear\n(the snapshot lives until the addon reloads).');
            end
        else
            imgui.TextColored(COL.DIM, 'This list  (nothing copied yet)');
        end
        imgui.Separator();
        imgui.TextColored(COL.HEADER, 'Saved Lists');
        if #named == 0 then
            imgui.TextColored(COL.DIM, '(none yet -- "save as..." beside copy from)');
        end
        for _, n in ipairs(named) do
            pRow('n_' .. n, n, colQ, 'named', n,
                function() return optim.copyPrioFromNamed(n); end,
                function() return optim.deletePrioNamed(n); end);
        end
        imgui.Separator();
        local shownSets = 0;
        for _, k in ipairs(keys) do
            if k ~= boundKey then
                shownSets = shownSets + 1;
                pRow('k_' .. k, k, colQ, 'set', k,
                    function() return optim.copyPrioFrom(k); end);
            end
        end
        if shownSets == 0 then
            imgui.TextColored(COL.DIM, '(no other set has a priority list yet)');
        end
        imgui.EndPopup();
    end

    imgui.TextColored(COL.DIM, 'top matters most; cap stops a stat once the set reaches it (0 = none):');
    imgui.BeginChild('##dlac_prio', { -1, -1 }, true);

    -- Reserve the right block from MEASURED widths (wide themed font): the
    -- 'cap' label + input, the ^ / v small buttons, the x button, plus gaps.
    local availW  = imgui.GetContentRegionAvail();
    local rightW  = textW('cap') + 46 + (textW('^') + 16) + (textW('v') + 16) + 20 + 26;
    local nameCol = availW - rightW; if nameCol < 44 then nameCol = 44; end
    local nchars  = math.max(6, math.floor(nameCol / 7));

    local pl = {};
    pcall(function() pl = optim.getPrio() or {}; end);
    wui._pbuf = wui._pbuf or {};

    -- Structural edits (move/remove) are gathered and applied AFTER the loop:
    -- mutating the list mid-iteration would re-render moved rows this frame
    -- with colliding ids.
    local act = nil;
    for i, e in ipairs(pl) do
        imgui.TextColored(COL.DIM, string.format('%2d.', i));
        imgui.SameLine(0, 4);
        imgui.TextColored(COL.USABLE, fmt.truncate(e.stat, nchars - 3));
        if #e.stat > (nchars - 3) and imgui.IsItemHovered() then imgui.SetTooltip(e.stat); end
        imgui.SameLine(nameCol);
        imgui.TextColored(COL.DIM, 'cap'); imgui.SameLine(0, 2);
        local b = wui._pbuf[e.stat];
        if b == nil then
            b = { (type(e.cap) == 'number') and e.cap or 0 };
            wui._pbuf[e.stat] = b;
        end
        imgui.PushItemWidth(46);
        local chg = imgui.InputInt('##pcap_' .. e.stat, b, 0);
        imgui.PopItemWidth();
        if chg then
            pcall(optim.prioSetCap, i, b[1]);
            pcall(optim.saveWeights);
            D.invalidateCandidates();
        end
        imgui.SameLine(0, 4);
        if imgui.SmallButton('^##pup_' .. i) and i > 1 then act = { kind = 'move', i = i, d = -1 }; end
        imgui.SameLine(0, 2);
        if imgui.SmallButton('v##pdn_' .. i) and i < #pl then act = { kind = 'move', i = i, d = 1 }; end
        imgui.SameLine(0, 4);
        if imgui.Button('x##px_' .. i, { 20, 0 }) then act = { kind = 'remove', i = i }; end
    end
    if #pl == 0 then
        imgui.TextColored(COL.DIM, '(empty -- add the stat that matters most first)');
    end
    if act ~= nil then
        if act.kind == 'move' then pcall(optim.prioMove, act.i, act.d);
        else pcall(optim.prioRemove, act.i); end
        prioChanged();
    end

    imgui.Separator();

    -- Add row: same searchable picker, minus stats already listed. No points --
    -- the position in the list IS the weight.
    local lower = {};
    for _, e in ipairs(pl) do lower[string.lower(e.stat)] = true; end
    wui._pAddStat = wui._pAddStat or { '' };
    wui._pAddCap  = wui._pAddCap or { 0 };
    imgui.TextColored(COL.DIM, 'add'); imgui.SameLine(0, 4);
    statPickerCombo('paddstat', wui._pAddStat, function(lk) return lower[lk] == true; end);
    imgui.SameLine(0, 6); imgui.TextColored(COL.DIM, 'cap'); imgui.SameLine(0, 2);
    imgui.PushItemWidth(46); imgui.InputInt('##paddcap', wui._pAddCap, 0); imgui.PopItemWidth();
    imgui.SameLine(0, 6);
    if imgui.Button('Add##paddgo', { 40, 0 }) then
        local name = wui._pAddStat[1];
        if name ~= nil and name ~= '' then
            local ok = false;
            pcall(function() ok = optim.prioAdd(name, wui._pAddCap[1]); end);
            if ok then
                wui._pAddStat[1] = '';
                wui._pAddCap[1] = 0;
                prioChanged();
            end
        end
    end

    imgui.EndChild();
end

-- ---------------------------------------------------------------------------
-- The weights editor body (fills the surrounding child/window).
-- ---------------------------------------------------------------------------
wui.editor = function()
    if D == nil or imgui == nil then return; end
    local ui, COL = D.ui, D.COL;
    if optim == nil then
        imgui.TextColored(COL.DIM, 'Optimizer unavailable -- weights disabled.');
        return;
    end
    -- Weights are PER SET only (the shared/no-set table is a dead concept,
    -- Henrik 07-17): without a binding there is nothing to edit. gearui gates
    -- the whole panel already; this is the belt-and-braces for other callers.
    local boundKey = nil;
    pcall(function()
        boundKey = (optim.weightsBoundTo ~= nil) and optim.weightsBoundTo() or nil;
    end);
    if boundKey == nil then
        fmt.textWrapped(COL.DIM, 'No set selected -- every set carries its own weights. Pick or create one on the Sets tab.');
        return;
    end
    -- Say WHOSE weights these are: each set remembers its own (blank when new).
    local j, s = string.match(boundKey, '^([^|]+)|(.+)$');
    imgui.TextColored(COL.HEADER, string.format('weights for set "%s" (%s)', s or boundKey, j or '?'));
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Every set remembers its own tuning -- point weights, priority list and\nbuild-slot marks. A new set starts BLANK; edits stick to that set only\nand come back when you re-select it.');
    end
    -- Priority cap buffers go stale across binding switches (gearui owns the
    -- ui._wbuf reset; the prio buffers live here, so the reset does too).
    local bk = boundKey or '<shared>';
    if wui._pbufFor ~= bk then
        wui._pbufFor = bk;
        wui._pbuf = {};
    end

    -- Points | Priority tabs (Henrik 07-17). Tab APIs are proven in this
    -- install (gearui's main tab bar); the guard is for a stripped binding,
    -- where we fall back to the points editor alone.
    local hasTabs = type(imgui.BeginTabBar) == 'function'
        and type(imgui.BeginTabItem) == 'function'
        and type(imgui.EndTabItem) == 'function'
        and type(imgui.EndTabBar) == 'function'
        and type(optim.getPrio) == 'function';
    if not hasTabs then
        renderPointsTab(boundKey);
        return;
    end
    if imgui.BeginTabBar('##dlac_wtabs', ImGuiTabBarFlags_None) then
        if imgui.BeginTabItem('Points##wtab_points') then
            renderPointsTab(boundKey);
            imgui.EndTabItem();
        end
        if imgui.BeginTabItem('Priority##wtab_prio') then
            renderPrioTab(boundKey);
            imgui.EndTabItem();
        end
        imgui.EndTabBar();
    end
end

return wui;
