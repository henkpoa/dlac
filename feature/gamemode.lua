-- Game-mode detection from the overhead name icon: the crystal that marks
-- CW/UCW (Crystal Warrior) characters and the Cait Sith that marks Wings.
-- CatsEyeXI re-skins the retail name-icon graphics; the server's private
-- isCrystalWarrior() state therefore surfaces client-side as ordinary
-- name-icon flag bits on the rendered entity:
--     RenderFlags4 & 0x1000  = crystal, CW or UCW   (retail: new-character '?')
--     RenderFlags4 & 0x4000  = Wings Cait Sith      (retail: mentor 'M')
--     neither                = ACE (no icon)
-- Field truth 2026-07-18, Tavnazian Safehold ICON dump (dlacprobe v1.8):
-- Mindie=UCW and Skincrawler=CW both carry 0x1000; Askar=Wings carries
-- 0x4000; Tcb/Brehanin=ACE carry neither. WHITE-vs-PINK (CW vs UCW) is NOT
-- readable here yet -- the only candidate bits (RenderFlags7 0xE0000000,
-- RenderFlags8 low nibble 7) come from the sole local-player sample and may
-- be local render state; a remote-UCW capture settles it (memory:
-- cw-ucw-mode-detection). Until then this module answers "crystal or not",
-- which is the gameplay-mode split (CW and UCW play identically).
-- The self entity is always rendered, so the self read cannot go stale; reads
-- are uncached because they are one array access.

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
-- idx defaults to the local player.
function M.flags4(idx)
    idx = idx or M.selfIndex();
    if idx == nil then return nil; end
    local v = M.readFlags4(idx);
    if type(v) ~= 'number' then return nil; end
    if v < 0 then v = v + 4294967296; end   -- Ashita hands back signed dwords
    return v;
end

-- 'crystal' | 'wings' | 'none' | nil (unknown/headless).
function M.icon(idx)
    local v = M.flags4(idx);
    if v == nil then return nil; end
    if hasbit(v, M.BIT_CRYSTAL) then return 'crystal'; end
    if hasbit(v, M.BIT_WINGS) then return 'wings'; end
    return 'none';
end

-- true = CW/UCW character, false = not, nil = unknown (headless, entity not
-- rendered). Gate features on == true / == false explicitly; never treat nil
-- as either answer.
function M.hasCrystal(idx)
    local i = M.icon(idx);
    if i == nil then return nil; end
    return i == 'crystal';
end

return M;
