--[[
    dlac/ui/uiscale.lua

    THE UI SCALE (ticket AXI-24, 2026-11-13): one saved number that makes dlac's
    windows smaller or larger. Ashita 4.3 raised its default interface font from
    14px to 18px, so every dlac window grew by more than a quarter on the same
    screen; this is the knob that takes it back (about 80% restores the old
    look) without touching the font every OTHER addon draws with.

    HOW IT SCALES. ImGui has no "zoom this window": the size of everything that
    is laid out from text -- labels, buttons, tabs, rows, tooltips -- follows
    the FONT, so the scale is a resized copy of the current font pushed once per
    frame around dlac's own draws (gearui's present hook) and popped in the same
    frame. What does NOT follow the font is a pixel count written in the source;
    those go through M.px(n) where they have been converted (the main window's
    default size, the Stable tab). An unconverted number still works -- it just
    stays the size it was.

    TWO ASHITAS, TWO WAYS TO RESIZE A FONT (Henrik, 2026-11-13: "this will be
    both CEXI and AXI, so needs to work for both"):

      'sized'   Ashita 4.3 / ImGui 1.92 (AscensionXI): PushFont(nil, size) --
                the current font at another size. Told apart by
                style.FontSizeBase, which arrived with it. The sibling addon
                `chains` scales its window this way.
      'legacy'  older Ashita (CatsEyeXI): PushFont takes no size, but ImGui
                multiplies ImFont.Scale into the size at the moment a font is
                pushed. So: set the current font's Scale, push that same font,
                and put Scale back AT ONCE -- the push has already taken the
                number, and the font object is the one every other addon
                draws with. CatsEyeXI's own partyfinder / fancychat scale text
                through font.Scale + PushFont(font) (their imguiwrap.lua), which
                is the proof the binding lets Lua write that field.
                The first legacy push is CHECKED: if the font size did not
                move, the push is taken back and the scale is off for the
                session, so a binding that ignores the field cannot look like
                one that honoured it.

    Neither available: M.supported() is false, nothing is pushed, M.get()
    answers 1 and M.px is the identity. The saved number is kept.

    WHO IS NOT SCALED. The floating equipment window already carries its OWN
    scale slider, so gearui suspends this one around it: two scales multiplied
    together would make the slider lie about its number. The Ready / PLD / WHM
    gauges draw from their own present hooks, outside the bracket, and keep
    their own /dl gauge scale for the same reason.

    No ashita / AshitaCore here: plain state plus guarded imgui calls, so the
    headless tests drive the real module.
]]--

local M = {};

M.MIN, M.MAX = 0.6, 1.5;
-- The Settings row's buttons. /dl uiscale takes anything in MIN..MAX.
M.PRESETS = { 0.7, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5 };

local _saved   = 1.0;     -- what the player chose (kept even when unsupported)
local _mode    = nil;     -- nil = not asked yet; false = cannot; 'sized' | 'legacy'
local _broken  = false;   -- a push that threw or did nothing: off for the session
local _proven  = false;   -- the legacy push has been seen to move the font size
local _open    = false;   -- between frameBegin and frameEnd
local _pushed  = false;   -- a font is on ImGui's stack right now
local _resize  = nil;     -- pending main-window resize factor (new / old)

local function im()
    local ok, m = pcall(require, 'imgui');
    return (ok and type(m) == 'table') and m or nil;
end

function M.clamp(v)
    v = tonumber(v);
    if v == nil or v ~= v then return 1.0; end
    if v < M.MIN then return M.MIN; end
    if v > M.MAX then return M.MAX; end
    return math.floor(v * 100 + 0.5) / 100;
end

-- Which way can this client resize a font? Asked once and kept: the binding
-- does not change under a running addon (tests swap it and call M._reset).
local function detect()
    local g = im();
    if g == nil or type(g.PushFont) ~= 'function' or type(g.PopFont) ~= 'function' then return false; end
    local ok, base = pcall(function() return g.GetStyle().FontSizeBase; end);
    if ok and type(base) == 'number' and base > 0 then return 'sized'; end
    local ok2, fscale = pcall(function() return g.GetFont().Scale; end);
    if ok2 and type(fscale) == 'number' and fscale > 0 then return 'legacy'; end
    return false;
end

-- 'sized', 'legacy', or false.
function M.mode()
    if _broken then return false; end
    if _mode == nil then _mode = detect(); end
    return _mode;
end

function M.supported() return M.mode() ~= false; end

-- The player's saved choice, whether or not this client can show it.
function M.saved() return _saved; end

-- The scale IN EFFECT: the saved one where the client can honour it, else 1.
-- Everything that sizes a draw asks this, never M.saved().
function M.get()
    if _saved == 1.0 or not M.supported() then return 1.0; end
    return _saved;
end

-- n source pixels at the scale in effect, on whole pixels.
function M.px(n)
    local s = M.get();
    if s == 1.0 then return n; end
    return math.floor(n * s + 0.5);
end

-- Set the scale. `quiet` = a load from disk: nothing on screen should move.
-- Otherwise the main window is asked to resize by the same factor next frame,
-- because a window that keeps its old pixel size around smaller text has not
-- got any smaller. Returns the clamped value.
function M.set(v, quiet)
    local old = M.get();
    _saved = M.clamp(v);
    local new = M.get();
    if not quiet and new ~= old and old > 0 then
        _resize = (_resize or 1.0) * (new / old);
    end
    return _saved;
end

-- The main window's pending resize factor, handed out ONCE (gearui takes it
-- just before Begin). nil when nothing changed.
function M.takeResize()
    local f = _resize;
    _resize = nil;
    return f;
end

local function fontSize(g)
    local ok, cur = pcall(g.GetFontSize);
    if ok and type(cur) == 'number' and cur > 0 then return cur; end
    return nil;
end

-- 'sized': the unscaled base (style.FontSizeBase is exactly the "before global
-- factors" number the sized PushFont wants back) times the scale.
local function pushSized(g, s)
    local base = nil;
    pcall(function() base = g.GetStyle().FontSizeBase; end);
    if type(base) ~= 'number' or base <= 0 then base = fontSize(g); end
    if base == nil then return false; end
    return (pcall(g.PushFont, nil, math.max(6, math.floor(base * s + 0.5))));
end

-- 'legacy': Scale on the font, push it, Scale straight back (see the header).
local function pushLegacy(g, s)
    local before = fontSize(g);
    local font, was = nil, nil;
    local ok = pcall(function()
        font = g.GetFont();
        was = font.Scale;
        font.Scale = was * s;
        g.PushFont(font);
    end);
    if font ~= nil and was ~= nil then pcall(function() font.Scale = was; end); end
    if not ok then return false; end
    if not _proven then
        -- Honoured = the size moved at least half way to where it was sent.
        local after = fontSize(g);
        if before ~= nil and after ~= nil
           and math.abs(after - before * s) > math.abs(before - before * s) * 0.5 then
            pcall(g.PopFont);
            return false;
        end
        _proven = true;
    end
    return true;
end

local function push(g)
    if _pushed or g == nil then return; end
    local s, m = M.get(), M.mode();
    if s == 1.0 or m == false then return; end
    local ok;
    if m == 'sized' then ok = pushSized(g, s); else ok = pushLegacy(g, s); end
    if ok then
        _pushed = true;
    else
        _broken = true;   -- never retry a binding that refused: once is a fact
    end
end

local function pop(g)
    if not _pushed then return; end
    _pushed = false;
    if g ~= nil then pcall(g.PopFont); end
end

-- Open the frame: push the resized font for everything dlac draws until
-- frameEnd. A scale of 1 (or an unsupported client) pushes nothing at all.
function M.frameBegin()
    _open = true;
    if _saved == 1.0 then return; end
    push(im());
end

-- Close it. ALWAYS call it, an error path included: the font stack is shared
-- with every other addon, exactly like the style stack.
function M.frameEnd()
    pop(im());
    _open = false;
end

-- Step outside the scale for a draw that carries its own (see WHO IS NOT
-- SCALED). suspend() returns a token; hand it to resume().
function M.suspend()
    if not _pushed then return false; end
    pop(im());
    return true;
end

function M.resume(token)
    if token ~= true or not _open then return; end
    push(im());
end

-- '80%' for a label or a chat line.
function M.label(v)
    return string.format('%d%%', math.floor((tonumber(v) or 1) * 100 + 0.5));
end

-- '/dl uiscale 80', '0.8', '80%' or 'reset' -> a scale, or nil when unreadable.
-- A bare number above 3 is a percentage; nobody means 80x.
function M.parse(text)
    if type(text) ~= 'string' then return nil; end
    text = text:lower():gsub('%s', '');
    if text == 'reset' or text == 'default' or text == 'off' then return 1.0; end
    local n = tonumber((text:gsub('%%$', '')));
    if n == nil or n ~= n or n <= 0 then return nil; end
    if text:sub(-1) == '%' or n > 3 then n = n / 100; end
    return M.clamp(n);
end

-- Tests only.
function M._reset()
    _saved, _mode, _broken, _proven = 1.0, nil, false, false;
    _open, _pushed, _resize = false, false, nil;
end

return M;
