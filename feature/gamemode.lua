-- What game mode is a character playing? THE central, reusable answer:
--     gamemode.get()  ->  'CW' | 'Wings' | 'ACE' | nil (unknown)
-- CatsEyeXI marks modes with an overhead name icon (CW/UCW crystal, Wings
-- Cait Sith, ACE none). Those are re-skinned retail name icons, so the
-- server's private isCrystalWarrior() state surfaces client-side as ordinary
-- name-icon flag bits on the rendered entity:
--     RenderFlags4 & 0x1000  = crystal -> 'CW'   (retail: new-character '?')
--     RenderFlags4 & 0x4000  = 'Wings'           (retail: mentor 'M')
--     neither                = 'ACE'
-- Field truth 2026-07-18, Tavnazian Safehold ICON dump (dlacprobe v1.8):
-- Mindie=UCW and Skincrawler=CW both carry 0x1000; Askar=Wings carries
-- 0x4000; Tcb/Brehanin=ACE carry neither. UCW deliberately ALSO returns
-- 'CW' -- Henrik's ruling 2026-07-18: "CW and UCW are still in the same
-- playmode and have the same restrictions", the crystal color changes
-- nothing a feature can gate on. Do not add a color split (revival path, if
-- shatter risk ever truly matters: memory cw-ucw-mode-detection).
-- The self entity is always rendered, so the self read cannot go stale;
-- reads are uncached because they are one array access.

local M = {};

M.BIT_CRYSTAL = 0x1000;     -- RenderFlags4: white OR pink crystal
M.BIT_WINGS   = 0x4000;     -- RenderFlags4: Cait Sith

-- Lua 5.1-safe single-bit test on a non-negative integer.
local function hasbit(v, b)
    return math.floor(v / b) % 2 == 1;
end

-- Live readers, injectable for headless tests. Both nil out on any failure --
-- callers treat nil as "unknown", never as a mode.
M.selfIndex = function()
    local idx = nil;
    pcall(function()
        idx = AshitaCore:GetMemoryManager():GetParty():GetMemberTargetIndex(0);
    end);
    if idx == 0 then idx = nil; end
    return idx;
end;

M.readFlags4 = function(idx)
    local v = nil;
    pcall(function()
        local em = AshitaCore:GetMemoryManager():GetEntity();
        if em:GetRawEntity(idx) == nil then return; end
        v = em:GetRenderFlags4(idx);
    end);
    return v;
end;

-- RenderFlags4 as an unsigned dword, or nil when the entity is unreadable.
-- idx defaults to the local player. (Plumbing under get(); public only as
-- the seam probes and tests reach through.)
function M.flags4(idx)
    idx = idx or M.selfIndex();
    if idx == nil then return nil; end
    local v = M.readFlags4(idx);
    if type(v) ~= 'number' then return nil; end
    if v < 0 then v = v + 4294967296; end   -- Ashita hands back signed dwords
    return v;
end

-- The game mode of the local player (or any rendered index): 'CW' | 'Wings'
-- | 'ACE', or nil when it cannot be read (headless, entity not rendered).
-- nil means UNKNOWN -- gate on an explicit mode, never on nil.
function M.get(idx)
    local v = M.flags4(idx);
    if v == nil then return nil; end
    if hasbit(v, M.BIT_CRYSTAL) then return 'CW'; end
    if hasbit(v, M.BIT_WINGS) then return 'Wings'; end
    return 'ACE';
end

return M;
