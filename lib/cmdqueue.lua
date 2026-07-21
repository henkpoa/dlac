--[[
    dlac/cmdqueue.lua -- frame clock + frame-delayed chat-command queue.

    Split out of gearui.lua: LuaJIT caps a chunk at 200 local variables, and gearui's
    main chunk was already at it -- cohesive helpers get their own module from now on.

    Used for the "Lock when equipped" lock/equip sequence (and the set-lock
    command pair): commands run a fixed number of frames apart so they never block.
    gearui calls M.tick() once per d3d_present -- it advances the frame clock, then
    flushes every queued command that has come due. M.frame() exposes the clock for
    the other per-frame logic (equipped-id memo, auto-sync delay, heartbeats).
]]--

local M = {};

local frameCounter = 0;
local cmdQueue = {};

-- The current frame number (increments once per M.tick / d3d_present).
function M.frame() return frameCounter; end

-- Queue a chat command to run `delayFrames` frames from now.
function M.enqueue(delayFrames, cmd)
    cmdQueue[#cmdQueue + 1] = { at = frameCounter + math.max(0, delayFrames), cmd = cmd };
end

local function processCmdQueue()
    if #cmdQueue == 0 then return; end
    local remaining = {};
    for _, c in ipairs(cmdQueue) do
        if frameCounter >= c.at then
            pcall(function() AshitaCore:GetChatManager():QueueCommand(1, c.cmd); end);
        else
            remaining[#remaining + 1] = c;
        end
    end
    cmdQueue = remaining;
end

-- Once per frame (d3d_present): advance the clock, then flush due commands.
function M.tick()
    frameCounter = frameCounter + 1;
    processCmdQueue();
end

return M;
