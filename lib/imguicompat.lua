--[[
    dlac/lib/imguicompat.lua -- the ONE imgui-BINDING seam.

    Different Ashita builds ship different ImGui generations, and the whole
    tree is written against the older binding. On a 1.90+ build (Vanaheim's
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

    Detection is keyed on the BINDING, never the server: the new build
    defines the ImGuiChildFlags_* enum globals in every addon state, the old
    one has no such enum at all. If CatsEyeXI's Ashita updates tomorrow, the
    shim follows the binding it actually finds. The mapping halves are pure
    and exported (M._childFlags / M._imageButtonArgs) so the headless suite
    pins them without an imgui table.

    One deliberate loss: framePadding is honoured via a PushStyleVar bracket
    when the binding exposes it, and silently dropped otherwise -- a border
    pixel is not worth a torn frame.
]]--

local M = {};

M.installed = false;   -- install() ran (whichever branch it took)
M.wrapped   = false;   -- ...and it actually wrapped a new-style binding

-- The new binding's build defines the ImGuiChildFlags_* enum globals; the old
-- one predates the enum entirely. Overridable for the headless suite.
function M.isNewBinding()
    return type(ImGuiChildFlags_Borders) == 'number';
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
    if not ok or type(imgui) ~= 'table' then return false; end
    M.installed = true;
    if not M.isNewBinding() then return false; end   -- old binding: leave it be
    M.wrapped = true;

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
