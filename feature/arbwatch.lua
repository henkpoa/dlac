--[[
    dlac/feature/arbwatch.lua -- the ADDON-SIDE owner of the Arbiter's rank
    Statefile <char>\dlac\arbstate.lua (ADR 0012, step 2).

    Step 1 (engine v97) gave the engine the claim registry and taught it to READ
    arbstate on its 1s throttle (dispatch.arbOrder / arbResolve / arbCededAbove);
    THIS module is the WRITER the Automations-tab Priority section
    (ui/priorityui.lua) drives. Same two-state contract as every other Statefile:
    the GUI writes the file, the engine hot-reloads it -- a drag applies to the
    live winners with NO Reload LAC (the engine reads gState files on its own
    schedule; nothing seeded changes, so no VERSION move is needed).

    UNLIKE pinstate (session-only, cleared at load), the rank list is PERSISTENT:
    the player's priority survives reloads and job changes (PRD user story 12).
    So M.order reads the file as-is and it is never cleared.

    File format (read by dispatch.ensureArbState / M.arbOrder):
        return { order = { "Pins", "Locks", "AutoAmmo", "MaxMP",
                           "Craft", "HELM", "Fishing", "Triggers" } }

    Pure at load (no Ashita/file touches until called), so both Lua states and the
    headless suite can require it (tests AB*).
]]--

local M = {};

-- The dispatch engine owns the canonical order vocabulary + the sanitizer; reuse
-- them so the GUI and the engine can NEVER disagree about the known rows or the
-- default (a second, drifting copy is exactly what ADR 0012 set out to end).
-- Guarded: a headless load without dispatch falls back to a local mirror of the
-- default and reimplements the same drop-unknown/append-missing policy.
local _dpok, dsp = pcall(require, 'dlac\\dispatch');
local hasDispatch = _dpok and type(dsp) == 'table';
local FALLBACK_DEFAULT = { 'Pins', 'Locks', 'AutoAmmo', 'MaxMP',
                           'Craft', 'HELM', 'Fishing', 'Chocobo', 'Triggers' };

-- Rows a player CANNOT pick up: only the Triggers floor (always last -- the
-- claims dress over it). Locks became a draggable VETO row in step 3 (ADR 0012):
-- a claimant dragged above it punches through a locked slot, one below it stops.
M.FIXED = { Triggers = true };

-- The built-in default rank (a fresh copy each call -- callers may keep it).
function M.defaultOrder()
    local d = hasDispatch and dsp._arbDefaultOrder or nil;
    local src = (type(d) == 'table' and #d > 0) and d or FALLBACK_DEFAULT;
    local out = {};
    for i, n in ipairs(src) do out[i] = n; end
    return out;
end

-- Sanitize a raw { order = ... } table to a COMPLETE strict order: unknown rows
-- dropped, duplicates collapsed, missing known rows appended in default order.
-- Delegates to the engine's arbOrder when present (one truth); the fallback is
-- the same policy so headless tests still exercise the shape.
function M.sanitize(st)
    if hasDispatch and type(dsp.arbOrder) == 'function' then
        return dsp.arbOrder(st);
    end
    local given = (type(st) == 'table' and type(st.order) == 'table') and st.order or nil;
    local out, seen = {}, {};
    local known = {};
    for _, n in ipairs(FALLBACK_DEFAULT) do known[n] = true; end
    -- Triggers floor pinned last (the dispatch.arbOrder invariant, mirrored so
    -- the headless-without-dispatch fallback agrees).
    for _, n in ipairs(given or {}) do
        if known[n] and not seen[n] and n ~= 'Triggers' then out[#out + 1] = n; seen[n] = true; end
    end
    for _, n in ipairs(FALLBACK_DEFAULT) do
        if not seen[n] and n ~= 'Triggers' then out[#out + 1] = n; seen[n] = true; end
    end
    out[#out + 1] = 'Triggers';
    return out;
end

-- <char>\dlac\ dir (lib\statefile -- the one addon-side copy). nil pre-login;
-- callers just retry on their next frame.
local _sfok, _sfile = pcall(require, 'dlac\\lib\\statefile');
local charDir = (_sfok and type(_sfile) == 'table') and _sfile.charDir
    or function() return nil; end;

local function arbStatePath()
    local dir = charDir();
    return dir and (dir .. 'arbstate.lua') or nil;
end
M._path = arbStatePath;   -- test seam

-- Serialize a rank order to the engine's file format. Pure (order in, text out)
-- so tests check the format with no character or disk. Non-string / empty
-- entries are skipped; the caller sanitizes before persisting.
function M.serialize(order)
    local parts = {};
    for _, n in ipairs(order or {}) do
        if type(n) == 'string' and n ~= '' then
            parts[#parts + 1] = string.format('%q', n);
        end
    end
    return 'return { order = { ' .. table.concat(parts, ', ') .. ' } }\n';
end

-- The live rank as the engine sees it: the on-disk order, sanitized. A missing
-- or torn/unparseable file reads as the built-in default (the Statefile drop
-- policy). Never throws -- the GUI calls it every frame.
function M.order()
    local st = nil;
    pcall(function()
        local p = arbStatePath();
        if p == nil then return; end
        local chunk = loadfile(p);
        if chunk == nil then return; end
        local ok, t = pcall(chunk);
        if ok and type(t) == 'table' then st = t; end
    end);
    return M.sanitize(st);
end

-- The safe replace ladder (temp -> parse/validate -> atomic swap -> restore on
-- late failure). No rotated backup: a lost arbstate self-heals to the default,
-- so the file class does not warrant the set-file backup policy -- but a torn
-- write must never clobber the live list, which the atomic swap guarantees.
local _swok, safewrite = pcall(require, 'dlac\\lib\\safewrite');
local hasSafe = _swok and type(safewrite) == 'table';

-- Commit a rank order to disk (sanitized first, so a bad drag can never persist
-- a partial or unknown-row list). Returns true on a successful write.
function M.setOrder(order)
    local p = arbStatePath();
    if p == nil then return false; end
    local clean = M.sanitize({ order = order });
    local text = M.serialize(clean);
    local ok = false;
    if hasSafe and type(safewrite.replaceLua) == 'function' then
        local orig = nil;
        pcall(function()
            local f = io.open(p, 'r');
            if f ~= nil then orig = f:read('*a'); f:close(); end
        end);
        ok = (safewrite.replaceLua(p, text, { origText = orig }) == true);
    else
        pcall(function()
            local f = io.open(p, 'wb');
            if f == nil then return; end
            f:write(text); f:close();
            ok = true;
        end);
    end
    return ok;
end

-- One-step reorder for the drag gesture / the arrow buttons: move the row at
-- `fromIdx` one place in `dir` (-1 = up/higher priority, +1 = down), returning a
-- NEW order (the input is untouched) or nil if the move is illegal. Legality
-- (ADR 0012): the Triggers floor never moves and is never displaced from last
-- (M.FIXED); the target must be in bounds. Every other row -- the claimants AND
-- the Locks veto (step 3) -- drags freely: raising a claimant above Locks makes
-- it punch through a locked slot, and dragging Locks itself resets which
-- claimants the veto stops.
function M.moveClaimant(order, fromIdx, dir)
    if type(order) ~= 'table' then return nil; end
    local n = #order;
    if type(fromIdx) ~= 'number' or fromIdx < 1 or fromIdx > n then return nil; end
    if dir ~= 1 and dir ~= -1 then return nil; end
    if M.FIXED[order[fromIdx]] then return nil; end          -- Locks / Triggers refuse the drag
    local toIdx = fromIdx + dir;
    if toIdx < 1 or toIdx > n then return nil; end
    if order[toIdx] == 'Triggers' then return nil; end        -- never push the floor off last
    local out = {};
    for i, v in ipairs(order) do out[i] = v; end
    out[fromIdx], out[toIdx] = out[toIdx], out[fromIdx];
    return out;
end

return M;
