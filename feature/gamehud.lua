-- Is the game's OWN interface hidden right now? THE central, reusable answer:
--     gamehud.hidden()  ->  true | false
-- Scroll Lock is FFXI's own hide-the-interface key: the chat log, the menus and
-- every gauge blink out so you can take a clean screenshot. Addon windows are
-- not the game's UI, so nothing hides them for you -- an overlay that ignores
-- this ends up pasted across every picture the player takes (Henrik's field
-- report, 2026-07-28: "the addon windows don't disappear").
--
-- The client keeps the flag as a byte hanging off a static structure; the
-- signature below is the standard Velyn one that xivbar and HXUI both ship
-- with (addons\xivbar\xivbar.lua, addons\HXUI\HXUI.lua) -- it matches a small
-- FFXiMain function whose 10th byte is the pointer to that structure, and
-- +0xB4 inside it is 1 while the interface is hidden.
--
-- FAILS OPEN, always: an unmatched signature, a null pointer or a headless
-- state all answer false ("not hidden"), so a client this signature does not
-- fit simply behaves the way dlac did before this file existed. The one thing
-- this must never do is hide the UI because a read went wrong.
--
-- NOTE this is the SCREENSHOT flag only. Cutscenes (the event system) and the
-- fullscreen map have their own signatures -- xivbar folds all three into one
-- "interface hidden" answer for its gauges. dlac deliberately does not: a
-- cutscene is exactly when you may want to keep reading a plan, and that call
-- is Henrik's to make, not this file's.

local M = {};

-- The Velyn signature + the two offsets that walk it. Exposed (not baked into
-- the reads) because when a client patch moves them, these three numbers are
-- the whole fix -- and the reference copies to diff against are two addons
-- away in this same Ashita install.
M.SIG      = '8B4424046A016A0050B9????????E8????????F6D81BC040C3';
M.PTR_OFF  = 10;      -- bytes into the match where the structure pointer sits
M.FLAG_OFF = 0xB4;    -- byte inside the structure: 1 = interface hidden

-- Live readers, injectable for headless tests. Each nils out on any failure;
-- the logic below treats nil as "cannot tell" and answers false.
M.find = function()
    local p = nil;
    pcall(function() p = ashita.memory.find('FFXiMain.dll', 0, M.SIG, 0, 0); end);
    return p;
end;

M.readU32 = function(addr)
    local v = nil;
    pcall(function() v = ashita.memory.read_uint32(addr); end);
    return v;
end;

M.readU8 = function(addr)
    local v = nil;
    pcall(function() v = ashita.memory.read_uint8(addr); end);
    return v;
end;

-- Resolved signature address: nil = not scanned yet, false = scan failed.
-- A signature scan is the expensive part (a pattern walk over the module) and
-- its answer cannot change inside a session, so it happens once. A FAILED scan
-- caches too: it means this client does not carry the pattern at all, and
-- re-walking the module every frame to be told so again is pure waste.
local _base = nil;

function M._reset() _base = nil; end   -- headless tests re-scan with fresh readers

-- Did the signature resolve? (Public because it is the one useful diagnostic:
-- false here means "this client, not this player's setting".)
function M.available()
    if _base == nil then
        local p = M.find();
        _base = (type(p) == 'number' and p ~= 0) and p or false;
    end
    return _base ~= false;
end

-- True only while the game is actively hiding its own interface.
function M.hidden()
    if not M.available() then return false; end
    local ptr = M.readU32(_base + M.PTR_OFF);
    if type(ptr) ~= 'number' or ptr == 0 then return false; end
    return M.readU8(ptr + M.FLAG_OFF) == 1;
end

return M;
