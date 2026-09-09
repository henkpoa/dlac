--[[
    dlac/lib/imguicompat.lua -- the ONE imgui-BINDING seam.

    Different Ashita builds ship different ImGui generations, and the whole
    tree is written against the older binding. On a 1.90+ build (AscensionXI's
    Ashita, 2026-08-26) three calls dlac makes everywhere stop matching any
    sol overload and every tab dies with "no matching function call":

      * BeginChild(id, size, border:BOOL, windowFlags)
          -> the bool became ImGuiChildFlags (an int): true = _Borders.
      * ImageButton(tex, size, uv0, uv1, framePadding, bg, tint)
          -> grew a leading str_id, lost framePadding (style-driven now).
      * Image(tex, size, uv0, uv1, TINT)
          -> lost the tint overload; ImageWithBg(tex, size, uv0, uv1, bg,
             tint) carries it on the new binding.

    install() detects the binding ONCE and, only on a new one, wraps those
    three entries on the required imgui table so every existing call site --
    dlac's own, the vendored modules', the server packs' -- keeps its old
    shape. On the old binding it wraps NOTHING: zero overhead, zero risk to
    the install everything was field-tested on.

    Detection is keyed on the BINDING, never the server. If CatsEyeXI's
    Ashita updates tomorrow, the shim follows the binding it actually finds.
    The mapping halves are pure and exported (M._childFlags /
    M._imageButtonArgs) so the headless suite pins them without an imgui
    table.

    FOUR SIGNALS, ANY ONE WINS (2026-09-09): the first cut read ONE global,
    ImGuiChildFlags_Borders, which addons\libs\imgui.lua defines -- a LUA
    FILE, not the DLL. An AscensionXI install then reported the exact three
    errors this shim exists to stop, on a dlac that carried the shim: its
    Ashita.dll spoke the new binding while its libs\imgui.lua was an older
    copy (no enum, IMGUI_VERSION_NUM 18000), so the shim read "old" and
    wrapped nothing. Now the userdata itself is asked too: ImageWithBg exists
    only on the 1.91+ binding, and GetVersion() names the generation
    outright. install() records WHICH signal fired (M.signal) and, if it could
    not run, WHY (M.error); status() renders that one line for the load
    beacon and /dl check, so the next inert shim is a readable line instead
    of three red tab errors.

    One deliberate loss: framePadding is honoured via a PushStyleVar bracket
    when the binding exposes it, and silently dropped otherwise -- a border
    pixel is not worth a torn frame.
]]--

local M = {};

M.installed = false;   -- install() ran (whichever branch it took)
M.wrapped   = false;   -- ...and it actually wrapped a new-style binding
M.signal    = nil;     -- which detection signal called the binding new
M.error     = nil;     -- why install() could not run, when it could not
M.remapped  = 0;       -- enum globals whose value the lib file had WRONG for this dll

-- THE ENUM VALUES THE NEW BINDING SPEAKS (mixed install, round 2, 2026-09-09).
-- The enum globals (ImGuiStyleVar_*, ImGuiCol_*, ...) are not the dll's:
-- addons\libs\imgui.lua defines them, a LUA FILE. A mixed install carries
-- the 1.80 numbers into a 1.92 dll, and the numbers MOVED: WindowPadding 1
-- is DisabledAlpha now (a float), so PushStyleVar(WindowPadding, {0,0})
-- asserts "variant with wrong type" and the PopStyleVar behind it pops one
-- too many -- the red MESSAGE FROM DEAR IMGUI panel on a friend's install,
-- every frame the float grid drew. Round 1 fixed the CALL SHAPES; the
-- VALUES are the other half of the same mismatch.
--
-- So on a new binding install() sets dlac's OWN copies of every enum global
-- dlac uses to the 1.92 numbers (each Ashita addon has its own Lua state --
-- nobody else's globals move). On a matching new install every value is
-- already equal and nothing changes; on a mixed one the count of corrected
-- values is the MIXED-install readout in the status line. Names the new
-- lib retired (TabActive/TabUnfocused/...) map onto their 1.92 successors so
-- uistyle's tab theme applies there too. Values read off Ashita 4.3.1.2's
-- libs\imgui.lua (ImGui 1.92.3, IMGUI_VERSION_NUM 19223); every name here
-- is one the dlac tree references. The old binding is never touched.
M.NEW_ENUMS = {
    -- ImGuiStyleVar (1.80 -> 1.92: DisabledAlpha slid in at 1)
    ImGuiStyleVar_WindowPadding    = 2,    -- was 1
    ImGuiStyleVar_WindowBorderSize = 4,    -- was 3
    ImGuiStyleVar_FramePadding     = 11,   -- was 10
    ImGuiStyleVar_ItemSpacing      = 14,   -- was 13
    -- ImGuiCol (identical through ResizeGripActive 32; the tab family moved)
    ImGuiCol_Text = 0, ImGuiCol_TextDisabled = 1, ImGuiCol_WindowBg = 2,
    ImGuiCol_ChildBg = 3, ImGuiCol_PopupBg = 4, ImGuiCol_Border = 5,
    ImGuiCol_FrameBg = 7, ImGuiCol_FrameBgHovered = 8, ImGuiCol_FrameBgActive = 9,
    ImGuiCol_TitleBg = 10, ImGuiCol_TitleBgActive = 11, ImGuiCol_TitleBgCollapsed = 12,
    ImGuiCol_ScrollbarBg = 14, ImGuiCol_ScrollbarGrab = 15,
    ImGuiCol_ScrollbarGrabHovered = 16, ImGuiCol_ScrollbarGrabActive = 17,
    ImGuiCol_CheckMark = 18, ImGuiCol_SliderGrab = 19, ImGuiCol_SliderGrabActive = 20,
    ImGuiCol_Button = 21, ImGuiCol_ButtonHovered = 22, ImGuiCol_ButtonActive = 23,
    ImGuiCol_Header = 24, ImGuiCol_HeaderHovered = 25, ImGuiCol_HeaderActive = 26,
    ImGuiCol_Separator = 27, ImGuiCol_SeparatorHovered = 28, ImGuiCol_SeparatorActive = 29,
    ImGuiCol_ResizeGrip = 30, ImGuiCol_ResizeGripHovered = 31, ImGuiCol_ResizeGripActive = 32,
    ImGuiCol_TabHovered = 34,           -- unchanged
    ImGuiCol_Tab = 35,                  -- was 33
    ImGuiCol_TabActive = 36,            -- retired name -> TabSelected (was 35)
    ImGuiCol_TabUnfocused = 38,         -- retired name -> TabDimmed (was 36)
    ImGuiCol_TabUnfocusedActive = 39,   -- retired name -> TabDimmedSelected (was 37)
    ImGuiCol_TextSelectedBg = 53,       -- was 49
    -- flags whose bit moved
    ImGuiInputTextFlags_EnterReturnsTrue           = 64,    -- was 1<<5
    ImGuiHoveredFlags_AllowWhenBlockedByActiveItem = 128,   -- was 1<<5
};

-- Apply NEW_ENUMS to this Lua state's globals; returns how many values
-- actually CHANGED (0 on a matching install, > 0 = the lib file was old).
-- `env` is a test seam (defaults to _G).
function M._applyEnums(env)
    env = env or _G;
    local changed = 0;
    for name, value in pairs(M.NEW_ENUMS) do
        if env[name] ~= value then
            env[name] = value;
            changed = changed + 1;
        end
    end
    return changed;
end

-- PURE: "1.92.3 WIP" / "1.80" -> true when the generation is 1.90 or later
-- (the BeginChild bool became ImGuiChildFlags in 1.90; ImageButton's str_id
-- came in 1.89, which no Ashita build shipped alone).
function M._versionIsNew(s)
    if type(s) ~= 'string' then return false; end
    local major, minor = s:match('^%s*(%d+)%.(%d+)');
    if major == nil then return false; end
    major, minor = tonumber(major), tonumber(minor);
    if major > 1 then return true; end
    return major == 1 and minor >= 90;
end

-- Is the binding the 1.90+ generation? Four signals, any one wins -- the two
-- lib-file globals first (cheap, the common case), then the userdata itself,
-- because a mixed install (new DLL, old libs\imgui.lua) has NO true global
-- to read. `imgui` is the required table; it may be nil headless, in which
-- case only the globals speak. Overridable for the headless suite.
function M.isNewBinding(imgui)
    if type(ImGuiChildFlags_Borders) == 'number' then
        M.signal = 'ImGuiChildFlags enum'; return true;
    end
    if type(IMGUI_VERSION_NUM) == 'number' and IMGUI_VERSION_NUM >= 19000 then
        M.signal = 'IMGUI_VERSION_NUM ' .. tostring(IMGUI_VERSION_NUM); return true;
    end
    if type(imgui) == 'table' then
        -- ImageWithBg exists only on the new binding (1.91+). The table
        -- resolves through __index = the gui-manager userdata, so the lookup
        -- itself is guarded.
        local okw, withBg = pcall(function() return imgui.ImageWithBg; end);
        if okw and withBg ~= nil then M.signal = 'ImageWithBg present'; return true; end
        local okv, ver = pcall(function() return imgui.GetVersion(); end);
        if okv and M._versionIsNew(ver) then
            M.signal = 'GetVersion ' .. tostring(ver); return true;
        end
    end
    M.signal = nil;
    return false;
end

-- ONE line for the load beacon and /dl check: what the shim decided and why.
function M.status()
    if M.error ~= nil then
        return 'imgui shim FAILED to install: ' .. tostring(M.error);
    end
    if not M.installed then return 'imgui shim NOT installed (install() never ran)'; end
    if M.wrapped then
        local mixed = (M.remapped > 0)
            and (' on an OLD libs\\imgui.lua (MIXED install: ' .. tostring(M.remapped) .. ' enum values corrected)')
            or '';
        return 'imgui binding NEW (' .. tostring(M.signal) .. ')' .. mixed
            .. ' -- shim WRAPPED BeginChild/ImageButton/Image';
    end
    return 'imgui binding OLD (no new-binding signal) -- shim inert, call sites native';
end

-- PURE: the old bool-or-passthrough third argument -> ImGuiChildFlags.
function M._childFlags(border)
    if type(border) == 'number' then return border; end   -- caller already speaks new
    if border == true then return ImGuiChildFlags_Borders or 1; end
    return 0;
end

-- PURE: old ImageButton args -> { id, tex, size, uv0, uv1, bg, tint, pad }.
-- The old binding keyed the widget ID on the texture; deriving the str_id from
-- it keeps the identity semantics call sites were written against.
function M._imageButtonArgs(tex, size, uv0, uv1, pad, bg, tint)
    return {
        id   = '##dlacib_' .. tostring(tex),
        tex  = tex,
        size = size,
        uv0  = uv0 or { 0, 0 },
        uv1  = uv1 or { 1, 1 },
        bg   = bg  or { 0, 0, 0, 0 },
        tint = tint or { 1, 1, 1, 1 },
        pad  = (type(pad) == 'number' and pad >= 0) and pad or nil,
    };
end

function M.install()
    if M.installed then return M.wrapped; end
    local ok, imgui = pcall(require, 'imgui');
    if not ok or type(imgui) ~= 'table' then
        M.error = (not ok) and ('require(imgui): ' .. tostring(imgui)) or 'require(imgui) returned no table';
        return false;
    end
    M.installed = true;
    if not M.isNewBinding(imgui) then return false; end   -- old binding: leave it be
    M.wrapped = true;

    -- The enum VALUES first: the ImageButton wrapper below reads
    -- ImGuiStyleVar_FramePadding at call time, and every module that loads
    -- after install() bakes these globals into its style tables.
    M.remapped = M._applyEnums();

    -- NOTE on the guards below: this build's imgui table resolves entries
    -- through __index = GetGuiManager() (a sol userdata), so a bound member
    -- is not guaranteed to answer type() == 'function'. Guard on ~= nil;
    -- callability is what the pcall around each raw call is for. Assigning
    -- the wrapper RAWSETS the key on the table, which shadows the __index
    -- for every later call site -- exactly the seam we want.

    -- BeginChild: the third argument was a border BOOL; it is ImGuiChildFlags
    -- now. Everything else is positionally identical.
    local rawBeginChild = imgui.BeginChild;
    if rawBeginChild ~= nil then
        imgui.BeginChild = function(id, size, border, wflags)
            local okc, r = pcall(rawBeginChild, id, size or { 0, 0 },
                                 M._childFlags(border), wflags or 0);
            if okc then return r; end
            return rawBeginChild(id, size or { 0, 0 });
        end;
    end

    -- ImageButton: a leading str_id now, framePadding via style. A call that
    -- already leads with a string is speaking the new shape -- pass it through.
    local rawImageButton = imgui.ImageButton;
    if rawImageButton ~= nil then
        imgui.ImageButton = function(a, b, c, d, e, f, g)
            if type(a) == 'string' then return rawImageButton(a, b, c, d, e, f, g); end
            local args = M._imageButtonArgs(a, b, c, d, e, f, g);
            local pushed = false;
            if args.pad ~= nil and imgui.PushStyleVar ~= nil
                and type(ImGuiStyleVar_FramePadding) == 'number' then
                pushed = pcall(imgui.PushStyleVar, ImGuiStyleVar_FramePadding,
                               { args.pad, args.pad });
            end
            local okb, r = pcall(rawImageButton, args.id, args.tex, args.size,
                                 args.uv0, args.uv1, args.bg, args.tint);
            if pushed then pcall(imgui.PopStyleVar); end
            if okb then return (r and true or false); end
            return false;
        end;
    end

    -- Image: the 5-arg tint overload is gone; ImageWithBg carries the tint on
    -- the new binding. The plain 2-4 arg calls are identical on both.
    local rawImage       = imgui.Image;
    local rawImageWithBg = imgui.ImageWithBg;
    if rawImage ~= nil then
        imgui.Image = function(tex, size, uv0, uv1, tint)
            if tint == nil then return rawImage(tex, size, uv0, uv1); end
            if rawImageWithBg ~= nil then
                local oki = pcall(rawImageWithBg, tex, size, uv0 or { 0, 0 },
                                  uv1 or { 1, 1 }, { 0, 0, 0, 0 }, tint);
                if oki then return; end
            end
            return rawImage(tex, size, uv0, uv1);   -- tint lost, image kept
        end;
    end

    return true;
end

return M;
