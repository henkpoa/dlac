--[[
    dlac/syncflags.lua

    Gear auto-sync + UI-flag persistence, extracted from gearui (the LuaJIT
    200-local chunk cap). Two jobs that share one flags file:

    * auto-sync -- keep gear.lua current: a quiet add-only scan ~2s after a job
      change (the LAC profile reload) and ~5s after the LAST inventory-changing
      packet (debounced, so zone-in floods run one scan). Toggle: /dl autosync.
    * ui-flags -- debug / autosync / view_ids / "Build as lv.75" / teleport-button
      state survive reloads via <char>\dlac\uiflags.lua.

    The module OWNS the flag state (sf.flags.debug / sf.flags.autosync /
    sf.flags.viewids);
    gearui's /dl handler and header buttons read/write those fields directly.
    gearui keeps the actual Ashita event hooks and calls sf.loadUiFlags /
    sf.tick / sf.invDirty from them -- hook ORDER is load-bearing (loadUiFlags
    swaps the real <char> gear.lua in BEFORE the first sync can run; see below).

    Deps arrive once via sf.configure{} (the profilesets.configure precedent):
        charBase, writeFileText, callImport, refreshGear, rescanAutogear, ui
]]--

local sf = {};

local cmdq = require("dlac\\lib\\cmdqueue");
local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end
local optim = try("dlac\\gear\\gearoptim");
local print = (function()
    local m = try('dlac\\chatfmt');
    return (m ~= nil and type(m.print) == 'function') and m.print or print;
end)();

-- Defaults stay debug=false / autosync=true; a /dl command or checkbox updates
-- the field AND re-saves, and wins over the on-disk value.
-- viewids (/dl view_ids): append the item id + appearance model id to every
-- equipment hover tooltip -- the two numbers you need when reasoning about a
-- lockstyle (the look is the MODEL id, not the item id).
sf.flags = { debug = false, autosync = true, viewids = false };

local D = nil;   -- deps from gearui; sync/persistence no-op until configured
sf.configure = function(deps)
    if type(deps) == 'table' then D = deps; end
end

local _syncedJob, _syncDueFrame = nil, nil;
local _invSyncAt = nil;   -- debounced: ~5s after the LAST inventory-changing packet
local _flagsLoaded = false;

local function uiFlagsPath()
    local base = D.charBase();
    return base and (base .. 'dlac\\uiflags.lua') or nil;
end

sf.saveUiFlags = function()
    if D == nil then return; end
    local p = uiFlagsPath(); if p == nil then return; end   -- pre-login: can't persist yet
    _flagsLoaded = true;                                    -- command is now authoritative
    pcall(function()
        local ui = D.ui;
        -- buildmax is deliberately NOT saved anymore: "Build as lv.75" defaults ON and
        -- resets to on each reload (2026-07-17). Legacy uiflags keys are ignored on load.
        local tpx, tpy = 0, 0;
        if type(ui._tpPos) == 'table' then
            tpx, tpy = tonumber(ui._tpPos[1]) or 0, tonumber(ui._tpPos[2]) or 0;
        end
        local gfx, gfy = 0, 0;
        if type(ui._gfPos) == 'table' then
            gfx, gfy = tonumber(ui._gfPos[1]) or 0, tonumber(ui._gfPos[2]) or 0;
        end
        D.writeFileText(p, string.format('return { debug = %s, autosync = %s, viewids = %s, tpfloat = %s, tpx = %d, tpy = %d, gearfloat = %s, gfx = %d, gfy = %d, gfscale = %.2f }\n',
            tostring(sf.flags.debug), tostring(sf.flags.autosync), tostring(sf.flags.viewids),
            tostring(ui._tpFloat == true), tpx, tpy,
            tostring(ui._gearFloat == true), gfx, gfy,
            tonumber(ui._gfScale) or 1.0));
    end);
end

sf.loadUiFlags = function()
    if _flagsLoaded or D == nil then return; end
    local p = uiFlagsPath(); if p == nil then return; end   -- pre-login: retry next frame
    _flagsLoaded = true;
    -- First frame the character is known -- also the moment to swap the REAL gear.lua in.
    -- The addon usually loads at Ashita boot, BEFORE login, so dlac.lua's load-time preload
    -- found no character and every require("dlac\\gear") resolved to the bundled EMPTY
    -- template. Left alone, the first auto-sync would compare the wardrobe against that
    -- template, call everything "new", and commit hundreds of duplicate entries into
    -- gear.lua. refreshGear() re-reads <char>\dlac\gear.lua into the shared table (in
    -- place, so every capture sees it) BEFORE any sync can run -- gearui's d3d_present
    -- handler calls sf.loadUiFlags ahead of sf.tick.
    D.refreshGear();
    pcall(function()
        local ui = D.ui;
        local chunk = loadfile(p);
        if chunk == nil then return; end                    -- no file yet -> keep defaults
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' then
            if type(t.debug)    == 'boolean' then sf.flags.debug    = t.debug;    end
            if type(t.autosync) == 'boolean' then sf.flags.autosync = t.autosync; end
            if type(t.viewids)  == 'boolean' then sf.flags.viewids  = t.viewids;  end
            -- t.buildmax (legacy key) is ignored: "Build as lv.75" is on by default and
            -- deliberately session-only since 2026-07-17.
            if type(t.tpfloat)  == 'boolean' then ui._tpFloat = t.tpfloat; end
            if type(t.tpx) == 'number' and type(t.tpy) == 'number' and (t.tpx ~= 0 or t.tpy ~= 0) then
                ui._tpPos = { t.tpx, t.tpy };
            end
            -- The floating equipment window remembers open/closed + where it sat.
            -- (The PINS it edits do not persist -- pinwatch clears them on load.)
            if type(t.gearfloat) == 'boolean' then ui._gearFloat = t.gearfloat; end
            if type(t.gfx) == 'number' and type(t.gfy) == 'number' and (t.gfx ~= 0 or t.gfy ~= 0) then
                ui._gfPos = { t.gfx, t.gfy };
            end
            -- Stored raw; floatgear.scale() clamps on read, so a hand-edited 0 or
            -- a negative here cannot collapse the window past rescuing.
            if type(t.gfscale) == 'number' then ui._gfScale = t.gfscale; end
        end
    end);
end

-- Quiet add-only scan; also refreshes the automations manifest (new gear may
-- change the best staff/obi picks). Returns the number of items added.
sf.doSync = function()
    if D == nil then return 0; end
    local added = D.callImport('sync');
    added = (type(added) == 'number') and added or 0;
    if added > 0 then D.refreshGear(); end
    pcall(D.rescanAutogear);
    return added;
end

-- Per-frame: fire the due syncs (job-change delay + inventory debounce).
sf.tick = function()
    if not sf.flags.autosync or D == nil then return; end
    local j = nil;
    pcall(function() j = AshitaCore:GetMemoryManager():GetPlayer():GetMainJob(); end);
    if j ~= nil and j ~= 0 and j ~= _syncedJob then
        _syncedJob    = j;
        _syncDueFrame = cmdq.frame() + 120;   -- ~2s after the change, so inventory has loaded
    end
    if _syncDueFrame ~= nil and cmdq.frame() >= _syncDueFrame then
        _syncDueFrame = nil;
        local added = sf.doSync();
        if added > 0 and sf.flags.debug then   -- routine indexing runs silent; /dl debug on shows it
            pcall(function() print(string.format('[dlac] gear library: +%d new item(s).', added)); end);
        end
    end
    -- Zero-step indexing: a new item schedules the same quiet sync itself (the
    -- packet hook in gearui calls sf.invDirty) -- no command, no job change needed.
    if _invSyncAt ~= nil and os.clock() >= _invSyncAt then
        _invSyncAt = nil;
        local added = sf.doSync();
        if added > 0 and sf.flags.debug then   -- same rule: dev-only chatter
            pcall(function() print(string.format('[dlac] gear library: +%d new item(s).', added)); end);
        end
    end
end

-- An inventory-changing packet arrived: slide the sync deadline ~5s out. While
-- packets keep arriving the deadline keeps sliding, so the scan runs once, in
-- the first quiet moment after a zone-in flood / combat swap chatter.
sf.invDirty = function()
    if not sf.flags.autosync then return; end
    _invSyncAt = os.clock() + 5;
end

return sf;
