--[[
    dlac/ui/wishlistui.lua -- the Wishlist window + the item context menu (ADR 0026).

    Two surfaces, one module:

      * M.renderItemMenu(rec, job) -- the BODY of the right-click menu. It is
        drawn inside somebody else's BeginPopup (All Equipment today), because
        OpenPopup and BeginPopup must share a window scope and the rows that
        detect the click live inside a BeginChild. The menu body lives here, not
        in the tab, so `Move To >` and friends can join `Wishlist >` later
        without any of it moving house.
      * M.render() -- the window, INDEPENDENT of the main dlac box (the Menu row
        opens it and it stays up), so it cannot go through uihost's window
        contract; gearui's d3d_present calls it in its own theme bracket, exactly
        as it calls the lockstyle and floating-equipment windows.

    THE SPLIT THIS FILE EXISTS TO RENDER (ADR 0026): a link is what you MEANT
    ("Dalmatica is for WHM/Idle"), stored on the entry and never revoked; whether
    the piece is actually IN that set is a FACT, read fresh from the set files by
    whereInSet(). They are allowed to disagree -- and where they do, that is
    precisely where the Apply button belongs. dlac never edits a set on its own.

    Cross-job reads are CACHED (M.refresh): reading 22 jobs' set files is cheap
    but not per-frame cheap. Refreshed when the window opens and after any apply.

    Cascades: BeginMenu is field-proven in this binding (floatgear, 07-15) but
    only ONE level deep. `Wishlist > Add for > row` is two, which nothing here has
    proven -- so hasMenu is probed (hard rule 2) and there is a flat drill-down
    fallback that uses only Selectable. No BeginChild anywhere in a menu chain:
    a child under a submenu makes ImGui tear the whole popup down as the mouse
    travels (floatgear paid for that one twice).
]]--

local host  = require("dlac\\ui\\uihost");
local wl    = require("dlac\\feature\\wishlist");
local fmt   = require("dlac\\gear\\gearfmt");
local icons = require("dlac\\ui\\itemicons");
local owned = require("dlac\\gear\\ownedcache");

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end
local imgui   = try('imgui');
local prof    = try('dlac\\profiles');
local psets   = try('dlac\\gear\\profilesets');
local setmgr  = try('dlac\\gear\\setmanager');
local uistyle = try('dlac\\ui\\uistyle');
local cfmt    = try('dlac\\chatfmt');

local M = {};
M.VERSION = 1;

local say = (cfmt ~= nil and type(cfmt.print) == 'function') and cfmt.print or print;

local S = host.services;
local ui, COL = S.ui, S.COL;
local EQUIP_SLOTS = S.EQUIP_SLOTS;

-- gearui provides its services BEFORE requiring this module. If that order ever
-- changes, fail loud and render nothing rather than throwing a nil index every
-- frame (the floatgear precedent).
if ui == nil or COL == nil or EQUIP_SLOTS == nil then
    pcall(function() print('[dlac] wishlistui: shared services missing -- the Wishlist is disabled.'); end);
    M.render = function() end;
    M.renderItemMenu = function() end;
    M.open = function() end;
    M.close = function() end;
    M.toggle = function() end;
    return M;
end

local hasMenu = (imgui ~= nil)
    and (type(imgui.BeginMenu) == 'function') and (type(imgui.EndMenu) == 'function');

-- Which slot labels an item can go into. Everything is one slot except rings and
-- earrings, where the gear model's single 'Ring' / 'Ear' has to become a CHOICE:
-- the wishlist knows "Body", but "Ring1 or Ring2?" has no answer it can derive,
-- so the apply cascade grows one level and asks (Henrik's call).
local SLOT_CHOICES = { Ring = { 'Ring1', 'Ring2' }, Ear = { 'Ear1', 'Ear2' } };
local function slotChoicesFor(slot)
    return SLOT_CHOICES[slot] or { slot };
end

-- ---------------------------------------------------------------------------
-- Cross-job set reads (the FACT half)
-- ---------------------------------------------------------------------------

local _dyn = {};          -- job -> the job's Dynamic table (name -> set)

function M.refresh()
    _dyn = {};
    if prof == nil or type(prof.readSetsFile) ~= 'function' then return; end
    for _, job in ipairs(prof.JOBS or {}) do
        local ok, d = pcall(prof.readSetsFile, job);
        if ok and type(d) == 'table' then _dyn[job] = d; end
    end
end

-- Test seam: inject the cross-job set cache in place of the disk read, so the
-- fact half (whereInSet / linkFacts / slotsFor) is drivable without a character.
function M._setDyn(t) _dyn = (type(t) == 'table') and t or {}; end

function M.jobsWithSets()
    local out = {};
    for _, job in ipairs((prof ~= nil and prof.JOBS) or {}) do
        if _dyn[job] ~= nil then out[#out + 1] = job; end
    end
    return out;
end

function M.setNames(job)
    local d = _dyn[job];
    if type(d) ~= 'table' then return {}; end
    local out = {};
    for n in pairs(d) do if type(n) == 'string' then out[#out + 1] = n; end end
    table.sort(out);
    return out;
end

-- The NAME a set-list element refers to. Elements arrive in three shapes after
-- profiles.readSetsFile has run the file: a bare string, a resolved gear record,
-- or a { gear = <either>, minLevel/mode/... } wrapper.
local function entryName(e)
    if type(e) == 'string' then return e; end
    if type(e) ~= 'table' then return nil; end
    if type(e.Name) == 'string' then return e.Name; end
    if e.gear ~= nil then return entryName(e.gear); end
    return nil;
end
M._entryName = entryName;   -- test seam

-- Which SLOT of <job>/<setName> already holds this name, or nil. Compared through
-- wl.normName so the catalog's "Arhats Gi" matches a set that says "Arhat's Gi".
function M.whereInSet(job, setName, name)
    local d = _dyn[job];
    local st = (type(d) == 'table') and d[setName] or nil;
    if type(st) ~= 'table' or type(name) ~= 'string' then return nil; end
    local want = wl.normName(name);
    for slotLabel, list in pairs(st) do
        if type(list) == 'table' then
            for _, e in ipairs(list) do
                local nm = entryName(e);
                if nm ~= nil and wl.normName(nm) == want then return slotLabel; end
            end
        end
    end
    return nil;
end

-- Each stored link paired with the live fact. `inSlot` = the slot it actually
-- sits in (nil = not added yet); `gone` = the link names a set that no longer
-- exists, which is worth SAYING rather than silently rendering as "not added".
function M.linkFacts(entry)
    local out = {};
    for _, l in ipairs((type(entry) == 'table' and entry.links) or {}) do
        local d = _dyn[l.job];
        out[#out + 1] = {
            job    = l.job,
            set    = l.set,
            inSlot = (l.set ~= nil) and M.whereInSet(l.job, l.set, entry.name) or nil,
            gone   = (l.set ~= nil) and (type(d) ~= 'table' or type(d[l.set]) ~= 'table'),
        };
    end
    return out;
end

-- ---------------------------------------------------------------------------
-- Applying a piece into a set
-- ---------------------------------------------------------------------------

-- The Lua expression that refers to `rec` in a set file. Owned records are
-- IDENTITY-SHARED with gear.lua (profiles.readSetsFile says so), so the table key
-- can be found by identity and the file's existing `gear.Slot.Key` form is
-- preserved on the round-trip. A record we cannot place -- and any wishlisted
-- piece, which is not in gear.lua at all -- renders as a quoted NAME, the form
-- utils.resolveGearName resolves.
local function pathOf(rec)
    if type(rec) ~= 'table' or type(rec.Name) ~= 'string' then return nil; end
    local gok, g = pcall(require, 'dlac\\gear');
    if gok and type(g) == 'table' and rec.Slot ~= nil and type(g[rec.Slot]) == 'table' then
        local base = g[rec.Slot];
        for k, v in pairs(base) do
            if v == rec then return 'gear.' .. rec.Slot .. '.' .. tostring(k); end
            if type(v) == 'table' and v.Name == nil then          -- Main/Range nest by category
                for k2, v2 in pairs(v) do
                    if v2 == rec then
                        return 'gear.' .. rec.Slot .. '.' .. tostring(k) .. '.' .. tostring(k2);
                    end
                end
            end
        end
    end
    return string.format('%q', rec.Name);
end

-- One set-list element -> one setmanager item ({ path, minLevel, ... }). Every
-- semantic field of the wrapper form is carried across; only comments and
-- formatting are lost, which is exactly what a Sets-tab Commit already costs.
local function entryToItem(e)
    local ref, w = e, nil;
    if type(e) == 'table' and e.Name == nil and e.gear ~= nil then ref, w = e.gear, e; end
    local path = (type(ref) == 'string') and string.format('%q', ref) or pathOf(ref);
    if path == nil then return nil; end
    local it = { path = path };
    if w ~= nil then
        it.minLevel, it.maxLevel, it.mode = w.minLevel, w.maxLevel, w.mode;
        it.autoType, it.removePrio, it.acc = w.autoType, w.removePrio, w.acc;
    end
    return it;
end

-- setmanager's ordered slots array for <job>/<setName>, optionally with `addName`
-- appended to `addSlot`. Slots come out in EQUIP_SLOTS order; any slot key the
-- equipment model does not know is carried through afterwards rather than
-- silently dropped -- a commit must never delete something it did not understand.
local function slotsFor(job, setName, addSlot, addName)
    local d = _dyn[job];
    local st = (type(d) == 'table') and d[setName] or nil;
    if type(st) ~= 'table' then return nil; end
    local items, order, seen = {}, {}, {};
    local function bucket(label)
        if items[label] == nil then items[label] = {}; order[#order + 1] = label; end
        return items[label];
    end
    for _, sl in ipairs(EQUIP_SLOTS) do
        local list = st[sl.label];
        seen[sl.label] = true;
        if type(list) == 'table' and #list > 0 then
            local b = bucket(sl.label);
            for _, e in ipairs(list) do
                local it = entryToItem(e);
                if it ~= nil then b[#b + 1] = it; end
            end
        elseif addSlot == sl.label then
            bucket(sl.label);                      -- a brand-new slot, in model order
        end
    end
    for label, list in pairs(st) do                -- anything EQUIP_SLOTS does not know
        if not seen[label] and type(list) == 'table' and #list > 0 then
            local b = bucket(label);
            for _, e in ipairs(list) do
                local it = entryToItem(e);
                if it ~= nil then b[#b + 1] = it; end
            end
        end
    end
    if addSlot ~= nil and addName ~= nil then
        local b = bucket(addSlot);
        b[#b + 1] = { path = string.format('%q', addName) };
    end
    local slots = {};
    for _, label in ipairs(order) do
        if #items[label] > 0 then slots[#slots + 1] = { name = label, items = items[label] }; end
    end
    return slots;
end
M._slotsFor = slotsFor;   -- test seam

-- The name to WRITE. Once you own the piece, gear.lua carries the client's
-- spelling ("Arhat's Gi") where the catalog carried the API's ("Arhats Gi").
-- Both resolve, but writing the one you actually own keeps the set file reading
-- like the game does.
local function writeNameFor(entry)
    if type(S.lookupById) == 'function' and entry.id ~= nil then
        local ok, rec = pcall(S.lookupById, entry.id);
        if ok and type(rec) == 'table' and type(rec.Name) == 'string'
           and owned.haveInBags(rec) then
            return rec.Name;
        end
    end
    return entry.name;
end

-- Put `entry` into <job>/<setName>'s `slotLabel`. Refuses while the Sets tab
-- holds uncommitted edits to that exact set: writing underneath it would be
-- silently stomped by the next Commit.
-- Real equipment slots only. Without this a record whose Slot never resolved
-- ('?' -- an item the catalog does not describe) would write a slot named '?'
-- into the set file: it would parse, commit, and then be ignored by everything
-- forever. Refusing at the one door beats guarding at each caller.
local VALID_SLOT = {};
for _, sl in ipairs(EQUIP_SLOTS) do VALID_SLOT[sl.label] = true; end
M._validSlot = function(s) return VALID_SLOT[s] == true; end   -- test seam

function M.applyToSet(entry, job, setName, slotLabel)
    if setmgr == nil or type(setmgr.commitSet) ~= 'function' then
        return false, 'setmanager unavailable';
    end
    if not VALID_SLOT[slotLabel] then
        return false, string.format('%s is not an equipment slot -- dlac could not work out where this piece goes', tostring(slotLabel));
    end
    if type(S.setsDirtyFor) == 'function' then
        local ok, dJob, dSet = pcall(S.setsDirtyFor);
        if ok and dJob == job and dSet == setName then
            return false, string.format('the Sets tab has uncommitted changes to %s / %s -- Commit or discard them first', job, setName);
        end
    end
    local name = writeNameFor(entry);
    if M.whereInSet(job, setName, name) ~= nil then
        return false, string.format('%s is already in %s / %s', name, job, setName);
    end
    local slots = slotsFor(job, setName, slotLabel, name);
    if slots == nil then return false, string.format('%s / %s not found', job, setName); end
    local ok, msg = setmgr.commitSet(job, setName, slots);
    if ok then
        M.refresh();                                    -- the FACT half just changed
        if psets ~= nil and type(psets.invalidate) == 'function' then pcall(psets.invalidate); end
    end
    return ok, msg;
end

-- ---------------------------------------------------------------------------
-- The item context menu (drawn inside someone else's BeginPopup)
-- ---------------------------------------------------------------------------

local _drill = nil;   -- drill-down fallback state (only when BeginMenu is absent)

local function addWish(rec, job, setName)
    if rec == nil or rec.Id == nil then return; end
    local _, created = wl.add(rec.Id, rec.Name);
    local tag = '';
    if job ~= nil then
        wl.addLink(rec.Id, job, setName);
        tag = '  (' .. job .. (setName and (' / ' .. setName) or '') .. ')';
    end
    say(string.format('[dlac] Wishlist: %s %s%s.', created and 'added' or 'updated',
        tostring(rec.Name), tag));
end

-- The rows inside `Wishlist >`. `inMenu` picks the widget: MenuItem inside a
-- BeginMenu, Selectable in the drill-down fallback -- tied to hasMenu rather
-- than to imgui.MenuItem existing, so the fallback stays on APIs this client has
-- actually proven. No fmt.esc on these labels: menu/selectable labels are not
-- format strings (floatgear's rule).
local function renderWishRows(rec, job, inMenu)
    local function row(label)
        if inMenu then return imgui.MenuItem(label); end
        return imgui.Selectable(label);
    end
    local on = (rec.Id ~= nil) and (wl.get(rec.Id) ~= nil);

    if row(on and 'On your wishlist' or 'Add to wishlist') and not on then
        addWish(rec, nil, nil);
    end
    if on and imgui.IsItemHovered() then
        imgui.SetTooltip('Already on the list. Use "Add to wishlist for" to note another\njob or set that wants it, or open the Wishlist window to edit it.');
    end

    -- "...for" -- the current job's sets only. Cross-job tagging lives in the
    -- window, where there is room: a character with six jobs would otherwise
    -- turn this into a fifty-row submenu.
    local names = (job ~= nil) and M.setNames(job) or {};
    if job ~= nil then
        if inMenu and hasMenu then
            if imgui.BeginMenu('Add to wishlist for##wlfor') then
                if imgui.MenuItem(job .. '   (job only)##wlforjob') then addWish(rec, job, nil); end
                if #names > 0 then imgui.Separator(); end
                for _, sn in ipairs(names) do
                    if imgui.MenuItem(job .. ' / ' .. sn .. '##wlfor_' .. sn) then addWish(rec, job, sn); end
                end
                imgui.EndMenu();
            end
        else
            imgui.Separator();
            imgui.TextColored(COL.DIM, 'Add to wishlist for');
            if imgui.Selectable(job .. '   (job only)##wlforjob') then addWish(rec, job, nil); end
            for _, sn in ipairs(names) do
                if imgui.Selectable(job .. ' / ' .. sn .. '##wlfor_' .. sn) then addWish(rec, job, sn); end
            end
        end
    end

    if on then
        imgui.Separator();
        if row('Remove from wishlist') then
            wl.remove(rec.Id);
            say(string.format('[dlac] Wishlist: removed %s.', tostring(rec.Name)));
        end
        if row('Open Wishlist window') then M.open(); end
    end
end

function M.renderItemMenu(rec, job)
    if imgui == nil then return; end
    if type(rec) ~= 'table' or rec.Id == nil then
        imgui.TextColored(COL.DIM, '(no item)');
        return;
    end
    imgui.TextColored(COL.HEADER, fmt.esc(tostring(rec.Name or '?')));
    if not owned.haveInBags(rec) then
        imgui.SameLine(0, 8);
        imgui.TextColored(COL.WANT, '(not owned)');
    end
    imgui.Separator();
    if hasMenu then
        if imgui.BeginMenu('Wishlist##wlroot') then
            renderWishRows(rec, job, true);
            imgui.EndMenu();
        end
    elseif _drill == 'wish' then
        imgui.TextColored(COL.DIM, 'Wishlist');
        if imgui.Selectable('< back##wlback') then _drill = nil; end
        renderWishRows(rec, job, false);
    else
        if imgui.Selectable('Wishlist...##wlroot') then _drill = 'wish'; end
    end
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

M.visible = false;

local _sel     = nil;                  -- selected entry id (expands its editor)
local _noteBuf = { '' };
local _search  = { '' };
local _jobF    = nil;                  -- job filter, nil = all
local _slotF   = nil;                  -- slot filter, nil = all
local _status  = '';
local _applyFor = nil;                 -- { id, job, set } awaiting a Ring1/Ring2 pick

function M.open()
    M.visible = true;
    M.refresh();
    _status = '';
end
function M.close() M.visible = false; end
function M.toggle() if M.visible then M.close(); else M.open(); end end

-- The catalog/owned record behind an entry, for icon, level and slot. Entries
-- store only id + name on purpose (the engine reads that file and has no
-- catalog); everything else is looked up here.
local function recOf(entry)
    if type(S.lookupById) ~= 'function' or entry.id == nil then return nil; end
    local ok, rec = pcall(S.lookupById, entry.id);
    return (ok and type(rec) == 'table') and rec or nil;
end

local function slotOf(entry, rec)
    return (rec ~= nil and rec.Slot) or '?';
end

-- MEASURE, never guess. The themed font is wide (~9.5px/char), so every fixed
-- pixel column in this window was a clipping bug waiting for a longer name --
-- and the first field report was exactly that: "SAM / Tp_Default" ran straight
-- through the status text at a hardcoded SameLine(140). Columns are derived from
-- the widest string that will actually be drawn in them.
local function textW(s)
    -- The nil check is NOT redundant with the pcall: `imgui.CalcTextSize` on a nil
    -- imgui throws while EVALUATING the argument, before pcall ever runs.
    if imgui ~= nil then
        local ok, w = pcall(imgui.CalcTextSize, tostring(s or ''));
        if ok and type(w) == 'number' then return w; end
    end
    return #tostring(s or '') * 10;                -- themed-font fallback, deliberately generous
end

-- A link's label -- 'WHM / Idle' or bare 'WHM'. One definition, because the
-- column width and the text drawn in it must never be computed differently.
local function linkLabel(l)
    return tostring(l.job) .. ((l.set ~= nil and l.set ~= '') and (' / ' .. tostring(l.set)) or '');
end
M._linkLabel = linkLabel;   -- test seam

-- The label column for ONE entry's link rows. DOUBLE the widest label it will
-- draw, on a doubled floor -- Henrik's call after field round 2: measuring the
-- label exactly is correct and still reads cramped, because the column has to
-- hold set names it has never seen. Set names are player-chosen and long ones
-- are normal ("Midcast_STR-VIT", "Tp_Default_Acc"), so the room has to be there
-- BEFORE the name is, or the column moves under him every time he picks a
-- different entry. Capped so a pathological name cannot push the status and its
-- buttons off the right edge.
local LINK_COL_MIN, LINK_COL_MAX = 180, 360;
local function linkColW(facts)
    local w = LINK_COL_MIN;
    for _, f in ipairs(facts or {}) do
        local tw = textW(linkLabel(f)) * 2;
        if tw > w then w = tw; end
    end
    return math.min(w, LINK_COL_MAX);
end
M._linkColW = linkColW;   -- test seam

-- Owned first, then by slot in equipment order, then by name. Owned-first
-- because a piece that just landed is the one you came here to act on.
local SLOT_RANK = {};
for i, sl in ipairs(EQUIP_SLOTS) do
    if SLOT_RANK[sl.gear] == nil then SLOT_RANK[sl.gear] = i; end
end
local function sortRows(rows)
    table.sort(rows, function(a, b)
        if a.own ~= b.own then return a.own; end
        local ra = SLOT_RANK[a.slot] or 99;
        local rb = SLOT_RANK[b.slot] or 99;
        if ra ~= rb then return ra < rb; end
        return tostring(a.entry.name) < tostring(b.entry.name);
    end);
    return rows;
end
M._sortRows = sortRows;   -- test seam

local function renderLinkRow(entry, f, i, colW)
    imgui.TextColored(COL.JOBS, fmt.esc(linkLabel(f)));
    imgui.SameLine(colW or 140);
    if f.set == nil then
        imgui.TextColored(COL.DIM, '(job only -- no set picked)');
    elseif f.gone then
        imgui.TextColored(COL.ERR, 'that set no longer exists');
    elseif f.inSlot ~= nil then
        imgui.TextColored(COL.HAVE, 'in the set  (' .. f.inSlot .. ')');
    else
        imgui.TextColored(COL.DIM, 'not added yet');
        -- Apply is offered only where the link and the fact disagree -- and only
        -- for a piece you actually have. dlac never edits a set on its own; this
        -- is the button that puts the choice where you are already looking.
        if wl.isOwned(entry.id) then
            imgui.SameLine(0, 10);
            local rec = recOf(entry);
            local choices = slotChoicesFor((rec ~= nil and rec.Slot) or '?');
            if not M._validSlot(choices[1]) then
                -- Slot unresolved (the catalog does not describe this piece). Say
                -- so rather than offering a button that can only write nonsense.
                imgui.TextColored(COL.DIM, 'add it by hand -- slot unknown');
            elseif #choices <= 1 then
                if imgui.SmallButton('Add##wlap' .. i) then
                    local ok, msg = M.applyToSet(entry, f.job, f.set, choices[1]);
                    _status = ok and string.format('Added %s to %s / %s.', entry.name, f.job, f.set)
                                  or ('Could not add: ' .. tostring(msg));
                end
            else
                -- Rings and ears: one more level, showing what already sits in each.
                for _, sl in ipairs(choices) do
                    imgui.SameLine(0, 6);
                    if imgui.SmallButton(sl .. '##wlap' .. i .. sl) then
                        local ok, msg = M.applyToSet(entry, f.job, f.set, sl);
                        _status = ok and string.format('Added %s to %s / %s (%s).', entry.name, f.job, f.set, sl)
                                      or ('Could not add: ' .. tostring(msg));
                    end
                    if imgui.IsItemHovered() then
                        local d = _dyn[f.job];
                        local st = (type(d) == 'table') and d[f.set] or nil;
                        local cur = {};
                        for _, e in ipairs((type(st) == 'table' and st[sl]) or {}) do
                            local nm = entryName(e);
                            if nm ~= nil then cur[#cur + 1] = nm; end
                        end
                        imgui.SetTooltip('Add to ' .. sl .. '.\n\n' .. sl .. ' currently holds:\n'
                            .. ((#cur > 0) and ('  ' .. table.concat(cur, '\n  ')) or '  (nothing)'));
                    end
                end
            end
        end
    end
    imgui.SameLine(0, 10);
    if imgui.SmallButton('x##wlrm' .. i) then
        wl.removeLink(entry.id, f.job, f.set);
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Forget this link. The wishlist entry stays;\nif the piece is in that set, it stays there too.');
    end
end

local function renderEditor(entry)
    imgui.Indent(26);
    imgui.TextColored(COL.DIM, 'Note:');
    imgui.SameLine(0, 6);
    imgui.PushItemWidth(-1);
    if imgui.InputText('##wlnote', _noteBuf, 128) then
        wl.setNote(entry.id, _noteBuf[1] or '');
    end
    imgui.PopItemWidth();
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Why you want it -- where it drops, what it costs, which\nversion is the real target. Saved as you type.');
    end

    local facts = M.linkFacts(entry);
    if #facts == 0 then
        imgui.TextColored(COL.DIM, 'No jobs or sets linked yet -- add one below.');
    else
        local colW = linkColW(facts);
        for i, f in ipairs(facts) do renderLinkRow(entry, f, i, colW); end
    end

    -- Add a link, any job (the window is where cross-job tagging lives).
    imgui.TextColored(COL.DIM, 'Link to:');
    imgui.SameLine(0, 6);
    imgui.PushItemWidth(textW('job') + 34);
    if imgui.BeginCombo('##wladdjob', _applyFor and _applyFor.job or 'job') then
        for _, j in ipairs(M.jobsWithSets()) do
            if imgui.Selectable(j .. '##wlaj' .. j, _applyFor and _applyFor.job == j) then
                _applyFor = { job = j };
            end
        end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();
    if _applyFor ~= nil and _applyFor.job ~= nil then
        imgui.SameLine(0, 6);
        -- Sized to the widest set name this job actually has, not a guess:
        -- set names are player-chosen and can be long ("Midcast_STR-VIT").
        local setW = textW('(job only)');
        for _, sn in ipairs(M.setNames(_applyFor.job)) do
            local tw = textW(sn);
            if tw > setW then setW = tw; end
        end
        imgui.PushItemWidth(math.min(setW + 34, 260));
        if imgui.BeginCombo('##wladdset', _applyFor.set or '(job only)') then
            if imgui.Selectable('(job only)##wlas_none', _applyFor.set == nil) then _applyFor.set = nil; end
            for _, sn in ipairs(M.setNames(_applyFor.job)) do
                if imgui.Selectable(sn .. '##wlas_' .. sn, _applyFor.set == sn) then _applyFor.set = sn; end
            end
            imgui.EndCombo();
        end
        imgui.PopItemWidth();
        imgui.SameLine(0, 6);
        if imgui.SmallButton('Link##wladd') then
            if wl.addLink(entry.id, _applyFor.job, _applyFor.set) then
                _status = string.format('Linked %s to %s%s.', entry.name, _applyFor.job,
                    _applyFor.set and (' / ' .. _applyFor.set) or '');
            else
                _status = 'That link is already there.';
            end
        end
    end

    imgui.Spacing();
    if imgui.SmallButton('Remove from wishlist##wldel') then
        wl.remove(entry.id);
        _sel = nil;
        _status = string.format('Removed %s from the wishlist.', entry.name);
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Deletes the entry and its links. Never happens by itself --\nnot even when you finally get the piece.');
    end
    imgui.Unindent(26);
end

function M.render()
    if imgui == nil or not M.visible then return; end
    local vis = { true };
    -- `or 4` (the real ImGuiCond_FirstUseEver), not `or 0`: floatgear's law --
    -- a zero fallback silently turns the flag into "always", which here would
    -- re-force the size every frame and quietly break resizing.
    imgui.SetNextWindowSize({ 700, 460 }, ImGuiCond_FirstUseEver or 4);
    if not imgui.Begin('dlac -- Wishlist##dlac_wishlist', vis, ImGuiWindowFlags_None or 0) then
        imgui.End();
        if not vis[1] then M.visible = false; end
        return;
    end
    if not vis[1] then M.visible = false; end

    -- Filter row -- the same shape as the All Equipment filter row on purpose:
    -- this reads as a sibling surface, not a new idiom.
    -- Widths measured off the widest preview each combo can show, + the arrow.
    -- "All jo▼" / "All slo▼" was the first thing wrong in the field.
    imgui.PushItemWidth(textW('All jobs') + 34);
    if imgui.BeginCombo('##wlfjob', _jobF or 'All jobs') then
        if imgui.Selectable('All jobs', _jobF == nil) then _jobF = nil; end
        for _, j in ipairs(M.jobsWithSets()) do
            if imgui.Selectable(j .. '##wlfj' .. j, _jobF == j) then _jobF = j; end
        end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();
    imgui.SameLine(0, 8);
    imgui.PushItemWidth(textW('All slots') + 34);
    if imgui.BeginCombo('##wlfslot', _slotF or 'All slots') then
        if imgui.Selectable('All slots', _slotF == nil) then _slotF = nil; end
        for _, s in ipairs(S.SLOT_ORDER or {}) do
            if imgui.Selectable(s .. '##wlfs' .. s, _slotF == s) then _slotF = s; end
        end
        imgui.EndCombo();
    end
    imgui.PopItemWidth();
    imgui.SameLine(0, 8);
    imgui.TextColored(COL.DIM, 'Search:');
    imgui.SameLine(0, 4);
    imgui.PushItemWidth(150);
    imgui.InputText('##wlsearch', _search, 48);
    imgui.PopItemWidth();
    imgui.SameLine(0, 8);
    if imgui.SmallButton('Refresh##wlref') then M.refresh(); _status = 'Re-read your set files.'; end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Re-read every job\'s set files, so the "in the set" marks\nbeside each link are current.');
    end

    -- Build the rows.
    local needle = string.lower(_search[1] or '');
    local rows, nOwn = {}, 0;
    for _, e in ipairs(wl.list()) do
        local rec  = recOf(e);
        local own  = wl.isOwned(e.id);
        local slot = slotOf(e, rec);
        local keep = true;
        if _slotF ~= nil and slot ~= _slotF then keep = false; end
        if keep and needle ~= '' and string.find(string.lower(e.name or ''), needle, 1, true) == nil then
            keep = false;
        end
        if keep and _jobF ~= nil then
            local hit = false;
            for _, l in ipairs(e.links or {}) do if l.job == _jobF then hit = true; break; end end
            keep = hit;
        end
        if own then nOwn = nOwn + 1; end
        if keep then rows[#rows + 1] = { entry = e, rec = rec, own = own, slot = slot }; end
    end
    sortRows(rows);

    imgui.TextColored(COL.DIM, string.format('%d wishlisted  |  %d already yours  |  showing %d',
        wl.count(), nOwn, #rows));
    if _status ~= '' then
        fmt.textWrapped(COL.SCORE, fmt.esc(_status));
    end
    imgui.Separator();

    imgui.BeginChild('##wllist', { -1, -1 }, false);
    if #rows == 0 then
        if wl.count() == 0 then
            fmt.textWrapped(COL.DIM, 'Nothing on your wishlist yet.\n\n'
                .. 'Open the All Equipment tab, tick "Show gear I don\'t own", then RIGHT-CLICK '
                .. 'anything you are hunting -> Wishlist -> Add. Adding a piece you do not own to '
                .. 'a set puts it here too.');
        else
            imgui.TextColored(COL.DIM, 'Nothing matches the filters.');
        end
    end
    -- Column stops, measured off what is ACTUALLY in the list this frame (plus
    -- the widest slot name, so the Lv->slot gap never collapses on 'Ranged').
    local NAME_X = 26;
    local nameW  = 120;
    for _, r in ipairs(rows) do
        local tw = textW(r.entry.name) + 18;
        if tw > nameW then nameW = tw; end
    end
    nameW = math.min(nameW, 300);
    local LV_X   = NAME_X + nameW;
    local SLOT_X = LV_X + textW('Lv99') + 16;
    local TAG_X  = SLOT_X + textW('Ranged') + 16;
    local NOTE_X = TAG_X + textW('in 9 set(s)') + 16;

    for i, r in ipairs(rows) do
        local e = r.entry;
        icons.renderIcon(e.id, 18);
        imgui.SameLine(NAME_X);
        local sel = (_sel == e.id);
        if imgui.Selectable('##wlrow' .. i, sel) then
            if sel then
                _sel = nil;
            else
                _sel = e.id;
                _noteBuf[1] = e.note or '';
                _applyFor = nil;
            end
        end
        imgui.SameLine(NAME_X);
        imgui.TextColored(r.own and COL.HAVE or COL.WANT, fmt.esc(e.name or '?'));
        imgui.SameLine(LV_X);
        imgui.TextColored(COL.LEVEL, string.format('Lv%d', (r.rec and r.rec.Level) or 0));
        imgui.SameLine(SLOT_X);
        imgui.TextColored(COL.DIM, fmt.esc(r.slot));
        imgui.SameLine(TAG_X);
        if r.own then
            imgui.TextColored(COL.HAVE, 'OWNED');
        else
            local n = 0;
            for _, f in ipairs(M.linkFacts(e)) do if f.set ~= nil and f.inSlot ~= nil then n = n + 1; end end
            imgui.TextColored(COL.DIM, (n > 0) and string.format('in %d set(s)', n) or '');
        end
        if (e.note or '') ~= '' and not sel then
            imgui.SameLine(NOTE_X);
            imgui.TextColored(COL.STATS, fmt.esc(fmt.truncate(e.note, 28)));
            if imgui.IsItemHovered() then imgui.SetTooltip(fmt.esc(e.note)); end
        end
        if sel then renderEditor(e); end
    end
    imgui.EndChild();

    imgui.End();
end

-- ---------------------------------------------------------------------------
-- The "you got it" notice
-- ---------------------------------------------------------------------------

-- Called on a debounce after an inventory-changing packet (gearui owns the
-- hook). One line per piece, on the TRANSITION into owned only -- the window is
-- where the detail lives; chat just tells you to go look.
function M.checkObtained()
    local ok, fresh = pcall(wl.newlyOwned);
    if not ok or type(fresh) ~= 'table' then return; end
    if #fresh == 0 then return; end
    -- The set cache is normally filled when the window opens -- but this fires
    -- while you play, and on a session where you never opened it every link
    -- would read as "that set is gone" and the line would lose the half worth
    -- reading. Prime it once, here, and only when there is actually news.
    if next(_dyn) == nil then pcall(M.refresh); end
    for _, e in ipairs(fresh) do
        local want = {};
        for _, f in ipairs(M.linkFacts(e)) do
            if f.set ~= nil and f.inSlot == nil and not f.gone then
                want[#want + 1] = f.job .. '/' .. f.set;
            end
        end
        if #want > 0 then
            say(string.format('[dlac] Wishlist: you got %s -- %s %s it and %s not added yet (/dl wish).',
                tostring(e.name), table.concat(want, ', '),
                (#want == 1) and 'wants' or 'want', (#want == 1) and 'is' or 'are'));
        else
            say(string.format('[dlac] Wishlist: you got %s (/dl wish).', tostring(e.name)));
        end
    end
end

-- /dl wish (or /dl wishlist) -- open the window. Own command handler (the
-- restockui/useitem pattern): fires for every command, acts only on ours.
pcall(function()
    ashita.events.register('command', 'dlac_wishlist_cmd', function(e)
        local raw = string.lower(e.command or '');
        local a = raw:match('^/dl%s+(%S+)') or raw:match('^/dlac%s+(%S+)');
        if a ~= 'wish' and a ~= 'wishlist' then return; end
        e.blocked = true;
        M.open();
        say(string.format('[dlac] Wishlist: %d item(s) -- window open.', wl.count()));
    end);
end);

return M;
