--[[
    dlac/profilesmenu.lua

    The Profiles menu popup (header "Profiles" button): character > profile >
    job tree across the whole install, plus the clone / rename / delete /
    import / export forms with collision gating. Extracted from gearui's
    drawWindow (it was ~400 lines inside one function; the LuaJIT 200-local
    cap is why it was inlined with function-scoped requires in the first place).

    State stays in gearui's shared ui table (the same fields as always:
    _profMenuBuild / _profMenu / _pmForm / _pmChk / _profMenuMsg), so the
    header button keeps working unchanged: it sets ui._profMenuBuild = true and
    pm.render() snapshots + opens on the next frame.

    A REAL window since 2026-07-20 (Henrik: wider + user-resizable), not a
    BeginPopup: movable, resizable, closed by its [X] (ui._profMenuOpen).
    gearui calls pm.render() AFTER its main window's End, beside the other
    top-level windows (host.renderWindows) -- no shared popup scope anymore.

    Deps arrive via pm.configure{} (the profilesets.configure precedent);
    fields MERGE, so gearui can wire late-defined hooks with a second call:
        ui          -- gearui's live view-state table
        COL         -- shared palette
        afterImport -- fn(dstChar, dstProf, jobName) -> note|nil, called after a
                       weights-bearing job import lands (Henrik 2026-07-20:
                       auto-build the imported sets right away)
]]--

local pm = {};

local fmt = require("dlac\\gear\\gearfmt");
local imgui = (function()
    local ok, m = pcall(require, 'imgui');
    return (ok and type(m) == 'table') and m or nil;
end)();

local ui, COL, afterImport;   -- set by configure; render() no-ops until ui/COL land
pm.configure = function(deps)
    if type(deps) == 'table' then
        ui = deps.ui or ui;
        COL = deps.COL or COL;
        afterImport = deps.afterImport or afterImport;
    end
end

pm.render = function()
    if imgui == nil or ui == nil then return; end
    -- Profiles menu popup: character > profile > jobs across the whole
    -- install, snapshotted on open/Refresh (a per-frame probe would be 44
    -- io.opens per profile). Function-scoped requires: 200-local cap.
    if ui._profMenuBuild then
        ui._profMenuBuild = nil;
        local m = { chars = {} };
        pcall(function()
            local prof = require('dlac\\profiles');
            if type(prof) ~= 'table' then m.err = 'profiles.lua unavailable'; return; end
            m.active = prof.activeName();
            m.exports = prof.listExports() or {};
            m.jobsSet = {};
            for _, j in ipairs(prof.JOBS) do m.jobsSet[j] = true; end
            local chars, cur = prof.listCharFolders();
            if chars == nil then m.err = 'No directory listing available on this system -- use /dl profile from chat instead.'; return; end
            for _, c in ipairs(chars) do
                -- Display the bare character name: names cannot collide on
                -- the server, so the _<ServerId> suffix is noise (the full
                -- folder name stays in .name -- paths need it).
                local e = { name = c, disp = c:match('^(.-)_%d+$') or c, isCurrent = (c == cur), profiles = {} };
                for _, pn in ipairs(prof.listProfilesAt(c) or {}) do
                    e.profiles[#e.profiles + 1] = { name = pn, files = prof.listProfileFilesAt(c, pn) };
                end
                m.chars[#m.chars + 1] = e;
            end
        end);
        ui._profMenu = m;
        ui._pmForm, ui._pmChk = nil, nil;   -- reopening always lands on the tree view
        ui._pmDelArm = nil;                 -- disarm any pending export delete
        ui._profMenuOpen = true;
    end
    if ui._profMenuOpen ~= true then return; end
    imgui.SetNextWindowSize({ 980, 540 }, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSizeConstraints({ 700, 360 }, { 1600, 1200 });
    local wopen = { true };
    if imgui.Begin('dlac Profiles###dlac_profmenu', wopen, ImGuiWindowFlags_None) then
        local m = ui._profMenu or { chars = {} };
        local f = ui._pmForm;

        if f ~= nil then
            -- ------- FORM VIEW: clone (profile/job) or rename, collision-gated -------
            local title;
            if f.kind == 'cloneProfile' then title = string.format('Clone profile "%s" from %s', f.srcProf, f.srcDisp);
            elseif f.kind == 'cloneJob' then title = string.format('Clone %s from %s\'s "%s"', f.job, f.srcDisp, f.srcProf);
            elseif f.kind == 'renameJob' then title = string.format('Rename %s in %s\'s "%s"', f.job, f.srcDisp, f.srcProf);
            elseif f.kind == 'deleteJob' then title = string.format('Delete %s from %s\'s "%s"', f.job, f.srcDisp, f.srcProf);
            elseif f.kind == 'newProfile' then title = string.format('New empty profile on %s', f.srcDisp);
            elseif f.kind == 'importJob' then title = string.format('Import %s (shared by %s, from their "%s")', f.job, f.srcDisp, f.srcProf);
            elseif f.kind == 'exportJob' then title = string.format('Export %s from %s\'s "%s"', f.job, f.srcDisp, f.srcProf);
            elseif f.kind == 'deleteProfile' then title = string.format('Delete profile "%s" from %s', f.srcProf, f.srcDisp);
            else title = string.format('Rename profile "%s"', f.srcProf); end
            imgui.TextColored(COL.HEADER, title);
            imgui.Separator();

            if f.kind == 'cloneProfile' or f.kind == 'cloneJob' or f.kind == 'importJob' then
                imgui.TextColored(COL.DIM, 'To character:'); imgui.SameLine(0, 8);
                local dstC = m.chars[f.dstIdx] or m.chars[1];
                imgui.PushItemWidth(180);
                if imgui.BeginCombo('##pm_dstchar', dstC and (dstC.disp or dstC.name) or '?') then
                    for i, cc in ipairs(m.chars) do
                        if imgui.Selectable((cc.disp or cc.name) .. '##pm_dc_' .. i, i == f.dstIdx) then f.dstIdx = i; end
                    end
                    imgui.EndCombo();
                end
                imgui.PopItemWidth();
            end
            if f.prof ~= nil and f.kind ~= 'deleteProfile' and f.kind ~= 'renameJob' then
                imgui.TextColored(COL.DIM, (f.kind == 'rename') and 'New name:' or 'To profile:'); imgui.SameLine(0, 8);
                imgui.PushItemWidth(180);
                imgui.InputText('##pm_fprof', f.prof, 48);
                imgui.PopItemWidth();
            end
            if f.kind == 'cloneJob' or f.kind == 'renameJob' or f.kind == 'newProfile' or f.kind == 'importJob' then
                imgui.TextColored(COL.DIM, (f.kind == 'renameJob') and 'New name:' or (f.kind == 'newProfile') and 'Name:' or 'As name:'); imgui.SameLine(0, 8);
                imgui.PushItemWidth(180);
                imgui.InputText('##pm_fname', f.name, 48);
                imgui.PopItemWidth();
            end
            if f.kind == 'exportJob' then
                -- What travels. Set equipment and Stat weights ride the sets:
                -- without Sets they are forced off and shown inert.
                imgui.TextColored(COL.DIM, 'Pick what travels; the file lands in dlac-exports\\ for sharing.');
                -- Dependency gating: a blocked row renders INERT (dim text)
                -- but the underlying tick is never mutated, so restoring the
                -- dependency restores the choice. The export click reads the
                -- same effective values (f._eff) -- blocked = not exported.
                local deps = f.deps or {};
                local modesOn, groupsOn = f.xModes[1] == true, f.xGroups[1] == true;
                imgui.Checkbox('Sets##pmx_sets', f.xSets);
                local setsOn = f.xSets[1] == true;
                local equipBlock = nil;
                if not setsOn then equipBlock = '(needs Sets)';
                elseif deps.setModes and not modesOn then
                    -- Gated gear without its Modes = inert rungs on the receiver.
                    equipBlock = '(this gear is Mode-gated -- include Modes to export it)';
                end
                if equipBlock ~= nil then
                    imgui.TextColored(COL.DIM, '    [ ] Set equipment  ' .. equipBlock);
                else
                    imgui.Text('    '); imgui.SameLine(0, 0);
                    imgui.Checkbox('Set equipment##pmx_equip', f.xEquip);
                    if imgui.IsItemHovered() then
                        imgui.SetTooltip('OFF (default): sets travel as EMPTY shells -- names only, no gear.\nGear rarely aligns between characters; the receiver auto-builds their own.\nON: the exact gear ladders travel verbatim.');
                    end
                end
                -- Triggers need whatever their rules reference: Sets (rules
                -- point at set names -- shells are enough), Modes and Groups
                -- (conditions). A dangling reference never fires on the
                -- receiver, so a choice that would ship one is disabled, not
                -- just warned. Sets first: it's the reference even an
                -- empty-condition rule carries.
                local trigNeeds = {};
                if deps.trigSets and not setsOn then trigNeeds[#trigNeeds + 1] = 'Sets'; end
                if deps.trigModes and not modesOn then trigNeeds[#trigNeeds + 1] = 'Modes'; end
                if deps.trigGroups and not groupsOn then trigNeeds[#trigNeeds + 1] = 'Groups'; end
                if #trigNeeds > 0 then
                    imgui.TextColored(COL.DIM, string.format('[ ] Triggers  (this job\'s triggers use %s -- include %s to export them)',
                        table.concat(trigNeeds, ' and '), (#trigNeeds > 1) and 'them' or 'it'));
                else
                    imgui.Checkbox('Triggers##pmx_trig', f.xTrig);
                end
                imgui.Checkbox('Groups##pmx_groups', f.xGroups);
                imgui.Checkbox('Modes##pmx_modes', f.xModes);
                if setsOn then
                    imgui.Checkbox('Stat weights##pmx_wts', f.xWts);
                    if imgui.IsItemHovered() then
                        imgui.SetTooltip('The per-set stat weights of this job\'s sets (points, priority lists,\nbuild-slot marks). They ride the sets -- can\'t travel without them.');
                    end
                else
                    imgui.TextColored(COL.DIM, '    [ ] Stat weights  (needs Sets)');
                end
                f._eff = {
                    sets       = setsOn,
                    equipment  = f.xEquip[1] == true and equipBlock == nil,
                    triggers   = f.xTrig[1] == true and #trigNeeds == 0,
                    groups     = groupsOn,
                    modes      = modesOn,
                    weights    = f.xWts[1] == true and setsOn,
                    lockstyles = f.xLs[1] == true,
                };
                imgui.Checkbox('Lockstyles##pmx_ls', f.xLs);
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('OFF (default): lockstyle boxes reference YOUR items, like set gear --\nthey rarely make sense on another character. ON: they travel verbatim.');
                end
            end

            -- Collision / validity check -- recomputed only when an input
            -- changes (a per-frame disk probe would spawn popen consoles).
            local dstC = m.chars[f.dstIdx] or m.chars[1];
            local key = f.kind .. '|' .. (dstC and dstC.name or '?') .. '|' .. tostring(f.prof and f.prof[1]) .. '|' .. tostring(f.name and f.name[1]);
            if ui._pmChk == nil or ui._pmChk.key ~= key then
                local chk = { key = key, blocked = false, why = nil, note = nil };
                pcall(function()
                    local prof = require('dlac\\profiles');
                    if f.kind == 'renameJob' then
                        local nm = prof.sanitizeName(f.name[1]);
                        if nm == nil then chk.blocked, chk.why = true, 'Invalid name: one word, letters/digits/_/- only.';
                        elseif nm == f.job then chk.blocked, chk.why = true, 'Same name -- nothing to rename.';
                        elseif prof.jobNameTakenAt(f.srcChar, f.srcProf, nm) then
                            chk.blocked, chk.why = true, string.format('NAME COLLISION: "%s" already has a %s -- change the name to continue.', f.srcProf, nm);
                        elseif m.jobsSet ~= nil and m.jobsSet[f.job] == true and m.jobsSet[nm] ~= true then
                            chk.note = f.job .. ' becomes DORMANT as "' .. nm .. '" -- the engine stops loading it. Rename it back to a job name to revive it.';
                        elseif m.jobsSet ~= nil and m.jobsSet[nm] == true and m.jobsSet[f.job] ~= true then
                            chk.note = '"' .. f.job .. '" goes LIVE as ' .. nm .. ' immediately.';
                        end
                        return;
                    end
                    if f.kind == 'deleteProfile' then
                        if f.srcChar == prof.currentCharFolder() and f.srcProf == prof.activeName() then
                            chk.blocked, chk.why = true, 'This is your ACTIVE profile -- switch to another one first (/dl profile use <name>).';
                        end
                        return;
                    end
                    if f.kind == 'deleteJob' then return; end   -- no inputs; the warning + red button gate it
                    if f.kind == 'newProfile' then
                        local nm = prof.sanitizeName(f.name[1]);
                        if nm == nil then chk.blocked, chk.why = true, 'Invalid name: one word, letters/digits/_/- only.';
                        elseif prof.profileNameExistsAt(f.srcChar, nm) then
                            chk.blocked, chk.why = true, string.format('NAME COLLISION: %s already has a profile "%s" -- change the name to continue.', f.srcDisp, nm);
                        end
                        return;
                    end
                    local pn = prof.sanitizeName(f.prof[1]);
                    if pn == nil then chk.blocked, chk.why = true, 'Invalid name: one word, letters/digits/_/- only.'; return; end
                    if f.kind == 'cloneProfile' then
                        if dstC.name == f.srcChar and pn == f.srcProf then
                            chk.blocked, chk.why = true, 'Source and destination are the same profile -- change the name.';
                        elseif prof.profileHasFilesAt(dstC.name, pn) then
                            chk.blocked, chk.why = true, string.format('NAME COLLISION: %s already has a profile "%s" -- change the name to continue.', dstC.disp or dstC.name, pn);
                        end
                    elseif f.kind == 'cloneJob' then
                        local nm = prof.sanitizeName(f.name[1]);
                        if nm == nil then chk.blocked, chk.why = true, 'Invalid file name: one word, letters/digits/_/- only.'; return; end
                        if dstC.name == f.srcChar and pn == f.srcProf and nm == f.job then
                            chk.blocked, chk.why = true, 'Source and destination are the same file -- change the name.';
                        elseif prof.jobNameTakenAt(dstC.name, pn, nm) then
                            chk.blocked, chk.why = true, string.format('NAME COLLISION: "%s" already has a %s -- change the name to continue.', pn, nm);
                        elseif m.jobsSet ~= nil and m.jobsSet[nm] ~= true then
                            chk.note = '"' .. nm .. '" is not a job name: it is copied as a dormant archive (the engine only reads <JOB>.lua).';
                        end
                    elseif f.kind == 'importJob' then
                        local nm = prof.sanitizeName(f.name[1]);
                        if nm == nil then chk.blocked, chk.why = true, 'Invalid file name: one word, letters/digits/_/- only.'; return; end
                        if prof.jobNameTakenAt(dstC.name, pn, nm) then
                            chk.blocked, chk.why = true, string.format('NAME COLLISION: "%s" already has a %s -- change the name to continue.', pn, nm);
                        elseif m.jobsSet ~= nil and m.jobsSet[nm] ~= true then
                            chk.note = '"' .. nm .. '" is not a job name: it is imported as a dormant archive (the engine only reads <JOB>.lua).';
                        end
                    else   -- rename
                        if pn == f.srcProf then
                            chk.blocked, chk.why = true, 'Same name -- nothing to rename.';
                        elseif prof.profileHasFilesAt(prof.currentCharFolder(), pn) then
                            chk.blocked, chk.why = true, string.format('NAME COLLISION: you already have a profile "%s" -- change the name to continue.', pn);
                        end
                    end
                end);
                ui._pmChk = chk;
            end
            local chk = ui._pmChk;
            if chk.note ~= nil then fmt.textWrapped(COL.DIM, chk.note); end
            if f.kind == 'deleteJob' and not chk.blocked then
                fmt.textWrapped(COL.ERR, string.format(
                    'THIS DELETES %s FROM "%s" ON %s -- its sets, triggers and lockstyle boxes, together.',
                    f.job, f.srcProf, f.srcDisp));
                fmt.textWrapped(COL.DIM,
                    'Verified safety copies land in that character\'s backups\\deleted-jobs\\ first. Hand-delete those if you truly want it gone.');
            end
            if f.kind == 'deleteProfile' and not chk.blocked then
                -- The warning IS the feature: say exactly what dies, before the button.
                local names, cnt = {}, 0;
                for _, e in ipairs(f.files or {}) do
                    names[#names + 1] = e.name;
                    cnt = cnt + (e.sets and 1 or 0) + (e.trig and 1 or 0) + (e.ls and 1 or 0);
                end
                fmt.textWrapped(COL.ERR, string.format(
                    'THIS DELETES THE WHOLE PROFILE "%s" ON %s -- every set, trigger and lockstyle box in it: %s (%d file(s)). It disappears from the menu and the engine.',
                    f.srcProf, f.srcDisp, (#names > 0) and table.concat(names, ', ') or '(empty)', cnt));
                fmt.textWrapped(COL.DIM,
                    'One safety net remains: the files are first copied to that character\'s backups\\deleted-profiles\\ (verified before anything is removed). Delete that folder by hand if you truly want it gone.');
            end
            imgui.Separator();
            local isDelete = (f.kind == 'deleteProfile' or f.kind == 'deleteJob');
            local goLabel = isDelete and 'DELETE PERMANENTLY' or (f.kind == 'exportJob' and 'Export' or 'Commit');
            if chk.blocked then
                fmt.textWrapped(COL.ERR, chk.why or 'blocked');
                local grey = ImGuiCol_Button ~= nil;
                if grey then imgui.PushStyleColor(ImGuiCol_Button, { 0.35, 0.35, 0.35, 1.0 }); end
                imgui.Button(goLabel .. '##pm_go0', { 170, 24 });   -- inert until the problem is fixed
                if grey then imgui.PopStyleColor(1); end
                if imgui.IsItemHovered() then imgui.SetTooltip('Fix the problem above first -- the button is disabled.'); end
            else
                local red = isDelete and ImGuiCol_Button ~= nil;
                if red then imgui.PushStyleColor(ImGuiCol_Button, { 0.72, 0.18, 0.18, 1.0 }); end
                local go = imgui.Button(goLabel .. '##pm_go', { 170, 24 });
                if red then imgui.PopStyleColor(1); end
                if go then
                    pcall(function()
                        local prof = require('dlac\\profiles');
                        if f.kind == 'cloneProfile' then
                            local n, err = prof.cloneProfileTo(f.srcChar, f.srcProf, dstC.name, f.prof[1]);
                            ui._profMenuMsg = (n ~= nil)
                                and string.format('Cloned "%s" -> %s / "%s" (%d file(s)).', f.srcProf, dstC.disp or dstC.name, prof.sanitizeName(f.prof[1]), n)
                                or ('Clone failed: ' .. tostring(err));
                        elseif f.kind == 'cloneJob' then
                            local n, err = prof.copyJobTo(f.srcChar, f.srcProf, f.job, dstC.name, f.prof[1], f.name[1]);
                            ui._profMenuMsg = (n ~= nil)
                                and string.format('Cloned %s -> %s / "%s" as %s (%d file(s)).', f.job, dstC.disp or dstC.name, prof.sanitizeName(f.prof[1]), prof.sanitizeName(f.name[1]), n)
                                or ('Clone failed: ' .. tostring(err));
                        elseif f.kind == 'renameJob' then
                            local n, err = prof.renameJobAt(f.srcChar, f.srcProf, f.job, f.name[1]);
                            ui._profMenuMsg = (n ~= nil)
                                and string.format('Renamed %s -> %s in "%s" (%d file(s)).', f.job, prof.sanitizeName(f.name[1]), f.srcProf, n)
                                or ('Rename failed: ' .. tostring(err));
                        elseif f.kind == 'importJob' then
                            local n, err = prof.importJobFile(f.file, dstC.name, f.prof[1], f.name[1]);
                            -- The weights payload (selective export) rides along: applied
                            -- through gearoptim -- live merge for the current character,
                            -- file merge for another -- with the job re-keyed to its
                            -- imported name. Failure only annotates; files already landed.
                            local wnote, wOK = '', false;
                            if n ~= nil then
                                pcall(function()
                                    local meta = prof.readExportFile(f.file);
                                    if meta ~= nil and type(meta.weights) == 'string' then
                                        local optim = require('dlac\\gear\\gearoptim');
                                        local wn, werr = optim.importJobWeightsTextAt(dstC.name, meta.weights, meta.job, prof.sanitizeName(f.name[1]));
                                        wOK = (wn ~= nil and wn > 0);
                                        wnote = (wn ~= nil)
                                            and string.format(' + stat weights for %d set(s)', wn)
                                            or (' (stat weights skipped: ' .. tostring(werr) .. ')');
                                    end
                                end);
                            end
                            ui._profMenuMsg = (n ~= nil)
                                and string.format('Imported %s -> %s / "%s" as %s (%d file(s))%s.', f.job, dstC.disp or dstC.name, prof.sanitizeName(f.prof[1]), prof.sanitizeName(f.name[1]), n, wnote)
                                or ('Import failed: ' .. tostring(err));
                            -- Weights landed -> auto-build the imported sets right away
                            -- (Henrik 2026-07-20: the exported shells are EMPTY on
                            -- purpose; the importer's own gear fills them). The hook
                            -- (gearui's Auto-Build All) decides whether it CAN --
                            -- current character, active profile, current job -- and
                            -- returns the note either way.
                            if n ~= nil and wOK and afterImport ~= nil then
                                local note = nil;
                                pcall(function()
                                    note = afterImport(dstC.name, prof.sanitizeName(f.prof[1]), prof.sanitizeName(f.name[1]));
                                end);
                                if type(note) == 'string' and note ~= '' then
                                    ui._profMenuMsg = tostring(ui._profMenuMsg) .. note;
                                end
                            end
                        elseif f.kind == 'exportJob' then
                            local pexp = require('dlac\\gear\\profileexport');
                            -- f._eff = the dependency-gated effective choices the
                            -- form just rendered (a blocked row exports nothing,
                            -- whatever its remembered tick says).
                            local opts = f._eff or { sets = f.xSets[1] == true, equipment = f.xEquip[1] == true,
                                                     triggers = f.xTrig[1] == true, groups = f.xGroups[1] == true,
                                                     modes = f.xModes[1] == true, lockstyles = f.xLs[1] == true,
                                                     weights = f.xWts[1] == true and f.xSets[1] == true };
                            local payloads, perr = pexp.buildPayloads(f.srcChar, f.srcProf, f.job, opts);
                            if payloads == nil then
                                ui._profMenuMsg = 'Export failed: ' .. tostring(perr);
                            else
                                local path, err = prof.exportJob(f.srcChar, f.srcProf, f.job, payloads);
                                ui._profMenuMsg = (path ~= nil)
                                    and string.format('Exported %s -> %s   Send that file; your friend drops it into THEIR dlac-exports folder and imports it from this menu.', f.job, path)
                                    or ('Export failed: ' .. tostring(err));
                            end
                        elseif f.kind == 'newProfile' then
                            local ok2, err = prof.createProfileAt(f.srcChar, f.name[1]);
                            ui._profMenuMsg = (ok2 ~= nil)
                                and string.format('Created empty profile "%s" on %s -- build sets in the Sets tab, or clone jobs into it.', prof.sanitizeName(f.name[1]), f.srcDisp)
                                or ('Create failed: ' .. tostring(err));
                        elseif f.kind == 'deleteJob' then
                            local n, info = prof.deleteJobAt(f.srcChar, f.srcProf, f.job);
                            ui._profMenuMsg = (n ~= nil)
                                and string.format('Deleted %s from "%s" (%d file(s) removed). Safety copy in backups\\deleted-jobs\\.', f.job, f.srcProf, n)
                                or ('Delete failed: ' .. tostring(info));
                        elseif f.kind == 'deleteProfile' then
                            local n, info = prof.deleteProfileAt(f.srcChar, f.srcProf);
                            ui._profMenuMsg = (n ~= nil)
                                and string.format('Deleted profile "%s" (%d file(s) removed). Safety copy: %s', f.srcProf, n, tostring(info))
                                or ('Delete failed: ' .. tostring(info));
                        else
                            local ok2, err = prof.renameProfile(f.srcProf, f.prof[1]);
                            ui._profMenuMsg = (ok2 ~= nil)
                                and string.format('Renamed "%s" -> "%s".', f.srcProf, prof.sanitizeName(f.prof[1]))
                                or ('Rename failed: ' .. tostring(err));
                        end
                        -- touched the CURRENT character's ACTIVE profile? make the
                        -- engine follow right now (sets + trigger hot-reload).
                        local tc, tp = nil, nil;
                        if f.kind == 'cloneJob' or f.kind == 'importJob' then tc, tp = dstC.name, prof.sanitizeName(f.prof[1]);
                        elseif f.kind == 'renameJob' or f.kind == 'deleteJob' then tc, tp = f.srcChar, f.srcProf; end
                        if tc ~= nil and tc == prof.currentCharFolder() and tp == prof.activeName() then
                            AshitaCore:GetChatManager():QueueCommand(1, '/dl sets reload');
                            AshitaCore:GetChatManager():QueueCommand(1, '/dl triggers reload');
                        end
                    end);
                    ui._pmForm, ui._pmChk = nil, nil;
                    ui._profMenuBuild = true;   -- rebuild the tree with the result
                end
            end
            imgui.SameLine(0, 8);
            if imgui.Button(isDelete and 'Cancel##pm_back' or 'Back##pm_back', { 90, 24 }) then ui._pmForm, ui._pmChk = nil, nil; end
        else
            -- ------- TREE VIEW: character > profile > job files -------
            -- W derives from the live window width: safe now that this is a
            -- USER-sized window -- the old fixed-800 rule guarded the
            -- AlwaysAutoResize popup, where GetWindowWidth fed back on itself
            -- (content reaches last frame's width, padding is added, the
            -- window crawls to full-screen -- field screenshot 2026-07-13).
            local W = 800;
            pcall(function()
                local gw = imgui.GetWindowWidth();
                if type(gw) == 'number' and gw > 100 then W = gw - 16; end
            end);
            do   -- centered PROFILES title, Refresh pinned right
                local tw = 62;
                pcall(function() local cw = imgui.CalcTextSize('PROFILES'); if type(cw) == 'number' then tw = cw; end end);
                pcall(function() imgui.SetCursorPosX(math.max(0, (W - tw) / 2)); end);
                imgui.TextColored(COL.HEADER, 'PROFILES');
                imgui.SameLine(math.max(0, W - 64));
                if imgui.SmallButton('Refresh##pm_r') then ui._profMenuBuild = true; end
            end
            imgui.Separator();
            if m.err ~= nil then fmt.textWrapped(COL.ERR, m.err); end
            -- Fill the resizable window; reserve a strip at the bottom for the
            -- status message when one is showing.
            imgui.BeginChild('##pm_body', { -1, (ui._profMenuMsg ~= nil) and -72 or -1 }, false);
            for _, c in ipairs(m.chars) do
                local fl = (c.isCurrent and ImGuiTreeNodeFlags_DefaultOpen ~= nil) and ImGuiTreeNodeFlags_DefaultOpen or 0;
                local cOpen = imgui.CollapsingHeader((c.disp or c.name) .. (c.isCurrent and '   (this character)' or '') .. '###pm_c_' .. c.name, fl);
                -- CollapsingHeader is a FULL-ROW hit target (unlike TreeNode, whose
                -- hit box is just the label): a button overlaid on the row never
                -- receives the click unless the header allows overlap (field case:
                -- "+ profile" was dead). Feature-detect; without the API the button
                -- moves inside the expanded section instead of silently not working.
                local canOverlap = type(imgui.SetItemAllowOverlap) == 'function';
                if canOverlap then
                    pcall(imgui.SetItemAllowOverlap);
                    imgui.SameLine(math.max(0, W - 34));   -- right-aligned on the character row
                    if imgui.SmallButton('+##pm_np_' .. c.name) then
                        ui._pmForm = { kind = 'newProfile', srcChar = c.name, srcDisp = c.disp or c.name, name = { '' } };
                        ui._pmChk = nil;
                    end
                end
                if cOpen then
                    if not canOverlap then
                        if imgui.SmallButton('Create Empty Profile##pm_np2_' .. c.name) then
                            ui._pmForm = { kind = 'newProfile', srcChar = c.name, srcDisp = c.disp or c.name, name = { '' } };
                            ui._pmChk = nil;
                        end
                    end
                    if #c.profiles == 0 then imgui.TextColored(COL.DIM, '     (no dlac profiles)'); end
                    for _, p in ipairs(c.profiles) do
                        local open = imgui.TreeNode(p.name .. '###pm_p_' .. c.name .. '_' .. p.name);
                        imgui.SameLine(0, 10);
                        if c.isCurrent and p.name == m.active then
                            imgui.TextColored(COL.SCORE, '[active]');
                            imgui.SameLine(0, 8);
                        elseif c.isCurrent then
                            if imgui.SmallButton('use##pm_u_' .. p.name) then
                                pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/dl profile use ' .. p.name); end);
                                ui._profMenuMsg = 'Switching to "' .. p.name .. '" -- the engine confirms in chat (hot; no LAC reload).';
                                m.active = p.name;   -- optimistic; Refresh re-reads the pointer
                            end
                            imgui.SameLine(0, 8);
                        end
                        if imgui.SmallButton('clone##pm_cl_' .. c.name .. '_' .. p.name) then
                            ui._pmForm = { kind = 'cloneProfile', srcChar = c.name, srcDisp = c.disp or c.name,
                                           srcProf = p.name, dstIdx = 1, prof = { p.name } };
                            ui._pmChk = nil;
                        end
                        if c.isCurrent then
                            imgui.SameLine(0, 8);
                            if imgui.SmallButton('rename##pm_rn_' .. p.name) then
                                ui._pmForm = { kind = 'rename', srcChar = c.name, srcDisp = c.disp or c.name,
                                               srcProf = p.name, prof = { p.name } };
                                ui._pmChk = nil;
                            end
                        end
                        if not (c.isCurrent and p.name == m.active) then   -- never offer deleting the live one
                            imgui.SameLine(0, 8);
                            if imgui.SmallButton('delete##pm_del_' .. c.name .. '_' .. p.name) then
                                ui._pmForm = { kind = 'deleteProfile', srcChar = c.name, srcDisp = c.disp or c.name,
                                               srcProf = p.name, files = p.files };
                                ui._pmChk = nil;
                            end
                        end
                        if open then
                            if #p.files == 0 then imgui.TextColored(COL.DIM, '     (empty)'); end
                            for _, jf2 in ipairs(p.files) do
                                imgui.Text('     ');
                                imgui.SameLine(0, 0);
                                if imgui.SmallButton('clone##pm_jc_' .. c.name .. '_' .. p.name .. '_' .. jf2.name) then
                                    ui._pmForm = { kind = 'cloneJob', srcChar = c.name, srcDisp = c.disp or c.name,
                                                   srcProf = p.name, job = jf2.name, dstIdx = 1,
                                                   prof = { p.name }, name = { jf2.name } };
                                    ui._pmChk = nil;
                                end
                                imgui.SameLine(0, 6);
                                if imgui.SmallButton('rename##pm_jr_' .. c.name .. '_' .. p.name .. '_' .. jf2.name) then
                                    ui._pmForm = { kind = 'renameJob', srcChar = c.name, srcDisp = c.disp or c.name,
                                                   srcProf = p.name, job = jf2.name, name = { jf2.name } };
                                    ui._pmChk = nil;
                                end
                                imgui.SameLine(0, 6);
                                if imgui.SmallButton('delete##pm_jd_' .. c.name .. '_' .. p.name .. '_' .. jf2.name) then
                                    ui._pmForm = { kind = 'deleteJob', srcChar = c.name, srcDisp = c.disp or c.name,
                                                   srcProf = p.name, job = jf2.name };
                                    ui._pmChk = nil;
                                end
                                imgui.SameLine(0, 6);
                                if imgui.SmallButton('export##pm_je_' .. c.name .. '_' .. p.name .. '_' .. jf2.name) then
                                    -- Selective export (2026-07-19): the form picks what
                                    -- travels; defaults = everything except set equipment
                                    -- and lockstyles (both reference YOUR items -- field
                                    -- ruling, Henrik: gear doesn't align between characters).
                                    -- deps: which selections REFERENCE which others (one
                                    -- disk probe at open, like the menu snapshot) -- the
                                    -- form disables choices that would ship dead references.
                                    local deps = { trigModes = false, trigGroups = false, trigSets = false, setModes = false };
                                    pcall(function()
                                        local pexp = require('dlac\\gear\\profileexport');
                                        deps = pexp.analyzeJob(c.name, p.name, jf2.name) or deps;
                                    end);
                                    ui._pmForm = { kind = 'exportJob', srcChar = c.name, srcDisp = c.disp or c.name,
                                                   srcProf = p.name, job = jf2.name, deps = deps,
                                                   xSets = { true }, xEquip = { false }, xTrig = { true },
                                                   xGroups = { true }, xModes = { true }, xWts = { true }, xLs = { false } };
                                    ui._pmChk = nil;
                                end
                                imgui.SameLine(0, 10);
                                local dormant = (m.jobsSet ~= nil and m.jobsSet[jf2.name] ~= true);
                                imgui.TextColored(dormant and COL.DIM or COL.USABLE, jf2.name);
                                if dormant then
                                    imgui.SameLine(0, 8);
                                    imgui.TextColored(COL.DIM, '(dormant -- not a job name)');
                                end
                            end
                            imgui.TreePop();
                        end
                    end
                end
            end
            -- Shared exports: per-job files in the install-wide dlac-exports\
            -- folder -- your own exports AND anything a friend sent you.
            if #(m.exports or {}) > 0 then
                imgui.Separator();
                imgui.TextColored(COL.HEADER, 'Shared exports');
                imgui.SameLine(0, 8);
                imgui.TextColored(COL.DIM, '(config\\addons\\luashitacast\\dlac-exports\\)');
                for _, ex in ipairs(m.exports) do
                    imgui.Text('  ');
                    imgui.SameLine(0, 0);
                    if imgui.SmallButton('import##pm_ix_' .. ex.file) then
                        ui._pmForm = { kind = 'importJob', srcDisp = tostring(ex.from), srcProf = tostring(ex.profile),
                                       job = ex.job, file = ex.file, dstIdx = 1,
                                       prof = { 'Default' }, name = { ex.job } };
                        ui._pmChk = nil;
                    end
                    -- x: delete the export FILE (Henrik 2026-07-20) -- red
                    -- second-click confirms; profiles imported from it keep
                    -- their copies.
                    imgui.SameLine(0, 6);
                    if ui._pmDelArm == ex.file then
                        local red = (ImGuiCol_Button ~= nil);
                        if red then imgui.PushStyleColor(ImGuiCol_Button, { 0.72, 0.18, 0.18, 1.0 }); end
                        if imgui.SmallButton('sure?##pm_dx_' .. ex.file) then
                            ui._pmDelArm = nil;
                            pcall(function()
                                local prof = require('dlac\\profiles');
                                local okd, derr = prof.deleteExport(ex.file);
                                ui._profMenuMsg = (okd == true)
                                    and string.format('Deleted export %s.lua from dlac-exports.', ex.file)
                                    or ('Delete failed: ' .. tostring(derr));
                            end);
                            ui._profMenuBuild = true;   -- re-list without the file
                        end
                        if red then imgui.PopStyleColor(1); end
                    else
                        if imgui.SmallButton('x##pm_dx_' .. ex.file) then ui._pmDelArm = ex.file; end
                        if imgui.IsItemHovered() then
                            imgui.SetTooltip('Delete this export file from dlac-exports -- the second (red) click\nconfirms. Profiles already imported from it keep their copies.');
                        end
                    end
                    imgui.SameLine(0, 10);
                    imgui.TextColored(COL.USABLE, tostring(ex.job));
                    -- What the file carries (selective exports differ).
                    local parts = {};
                    if ex.sets then parts[#parts + 1] = 'sets'; end
                    if ex.trig then parts[#parts + 1] = 'triggers'; end
                    if ex.ls then parts[#parts + 1] = 'lockstyles'; end
                    if ex.wts then parts[#parts + 1] = 'weights'; end
                    imgui.SameLine(0, 8);
                    imgui.TextColored(COL.DIM, '[' .. table.concat(parts, '+') .. ']');
                    imgui.SameLine(0, 10);
                    imgui.TextColored(COL.DIM, string.format('from %s / "%s"   %s.lua', tostring(ex.from), tostring(ex.profile), ex.file));
                end
            end
            imgui.EndChild();
            if ui._profMenuMsg ~= nil then
                imgui.Separator();
                fmt.textWrapped(COL.SCORE, ui._profMenuMsg);
            end
        end
    end
    imgui.End();
    if wopen[1] == false then ui._profMenuOpen = false; end
end

return pm;
