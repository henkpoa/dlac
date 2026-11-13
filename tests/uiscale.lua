-- Run from the addon root: lua tests/uiscale.lua
-- The UI scale (ui/uiscale.lua, ticket AXI-24): the pure module, the uiflags
-- round trip, and the Stable tab laid out under a scaled font.
table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end);

local n = 0;
local function check(label, got, want)
    n = n + 1;
    if got ~= want then
        error(string.format('%s: got %s, want %s', label, tostring(got), tostring(want)), 2);
    end
end

-- A binding that records the font stack, in either of the two shapes:
--   base = 18, font = nil   Ashita 4.3: style.FontSizeBase + PushFont(nil, size)
--   base = nil, font = {..} older Ashita: PushFont(font), sized by font.Scale
--   both nil                neither: the scale cannot be shown at all
local stack, pushes, base, throwPush = {}, {}, 18, false;
local font, ignoreScale, scaleAtPush = nil, false, nil;
local function rest() return base or (font and font.FontSize) or 18; end
local sizes, children = {}, {};
local dl = setmetatable({}, { __index = function() return function() end; end });
local function fontScale() return (stack[#stack] or rest()) / rest(); end
local stub = {
    GetStyle = function() return { FontSizeBase = base }; end,
    GetFontSize = function() return stack[#stack] or rest(); end,
    GetFont = function() return font; end,
    PushFont = function(f, size)
        if throwPush then error('injected PushFont failure'); end
        if size == nil then
            -- the older signature: the size is read off the font AT THE PUSH
            assert(font ~= nil and f == font, 'the older PushFont is handed the current font');
            scaleAtPush = f.Scale;
            size = f.FontSize * (ignoreScale and 1 or f.Scale);
        else
            assert(f == nil, 'the current font is resized, never replaced');
        end
        stack[#stack + 1] = size; pushes[#pushes + 1] = size;
    end,
    PopFont = function() assert(#stack > 0, 'PopFont on an empty stack'); stack[#stack] = nil; end,
    -- enough of a layout for the Stable tab
    GetContentRegionAvail = function() return 1000, 600; end,
    GetCursorScreenPos = function() return 0, 0; end,
    GetCursorPosY = function() return 0; end,
    GetScrollY = function() return 0; end,
    GetWindowHeight = function() return 600; end,
    GetWindowDrawList = function() return dl; end,
    CalcTextSize = function(text) return #tostring(text) * 9 * fontScale(), 18 * fontScale(); end,
    BeginChild = function(id, size) children[#children + 1] = { id = id, w = size[1], h = size[2] }; return true; end,
    Image = function(_, size) sizes[#sizes + 1] = size[1]; end,
    Button = function() return false; end,
};
package.loaded.imgui = setmetatable(stub, { __index = function() return function() return false; end; end });

local sc = require('dlac\\ui\\uiscale');

-- 1. Numbers in, numbers out.
check('clamp low', sc.clamp(0.1), 0.6);
check('clamp high', sc.clamp(9), 1.5);
check('clamp garbage', sc.clamp('x'), 1.0);
check('clamp nan', sc.clamp(0 / 0), 1.0);
check('clamp rounds to a percent', sc.clamp(0.8049), 0.8);
check('parse percent', sc.parse('80'), 0.8);
check('parse percent sign', sc.parse('125%'), 1.25);
check('parse fraction', sc.parse('0.9'), 0.9);
check('parse reset', sc.parse('reset'), 1.0);
check('parse garbage', sc.parse('big'), nil);
check('parse zero', sc.parse('0'), nil);
check('parse out of range clamps', sc.parse('500'), 1.5);
check('label', sc.label(0.8), '80%');
for _, v in ipairs(sc.PRESETS) do check('preset ' .. v .. ' is in range', sc.clamp(v), v); end

-- 2. At 100% nothing is pushed at all.
check('default', sc.get(), 1.0);
sc.frameBegin(); sc.frameEnd();
check('100% pushes no font', #pushes, 0);
check('px identity at 100%', sc.px(940), 940);

-- 3. A scale pushes ONE resized font per frame and pops it in the same frame.
check('supported', sc.supported(), true);
check('set returns the clamped value', sc.set(0.8), 0.8);
check('px', sc.px(940), 752);
check('px rounds', sc.px(155), 124);
sc.frameBegin();
check('one push', #pushes, 1);
check('pushed size is the base times the scale', pushes[1], 14);
check('on the stack during the frame', #stack, 1);
-- ...and steps aside for a draw that carries its own scale.
local tok = sc.suspend();
check('suspended', #stack, 0);
sc.resume(tok);
check('resumed', #stack, 1);
check('resume re-pushes the same size', pushes[#pushes], 14);
sc.frameEnd();
check('balanced after the frame', #stack, 0);
sc.frameEnd();   -- a second close (an error path that also closes) must not pop twice
check('double close is safe', #stack, 0);
check('suspend outside a frame holds nothing', sc.suspend(), false);
sc.resume(true);
check('resume outside a frame pushes nothing', #stack, 0);

-- 4. Changing the scale asks the main window to resize by the same factor, once.
sc._reset(); sc.set(0.8);
check('resize factor', sc.takeResize(), 0.8);
check('handed out once', sc.takeResize(), nil);
sc.set(1.0);
check('back up', math.abs(sc.takeResize() - 1.25) < 1e-9, true);
sc.set(0.8); sc.set(0.7);
check('two changes before a frame compound', math.abs(sc.takeResize() - 0.7) < 1e-9, true);
sc.set(0.7);
check('no change, no resize', sc.takeResize(), nil);
sc._reset(); sc.set(0.8, true);
check('a load from disk moves nothing', sc.takeResize(), nil);

-- 5a. An older Ashita (CatsEyeXI): no sized PushFont, so the current font's
--     Scale carries the number through the push and is put straight back.
sc._reset(); base = nil; font = { Scale = 1, FontSize = 14 }; pushes = {};
check('older Ashita: mode', sc.mode(), 'legacy');
sc.set(0.8);
check('older Ashita: in effect', sc.get(), 0.8);
check('older Ashita: px', sc.px(940), 752);
check('older Ashita: resize factor', sc.takeResize(), 0.8);
sc.frameBegin();
check('older Ashita: one push', #pushes, 1);
check('older Ashita: the push saw the scaled font', scaleAtPush, 0.8);
check('older Ashita: pushed size', math.abs(pushes[1] - 11.2) < 1e-9, true);
check('older Ashita: the shared font is restored at once', font.Scale, 1);
local tok2 = sc.suspend(); check('older Ashita: suspended', #stack, 0);
sc.resume(tok2); check('older Ashita: resumed', #stack, 1);
check('older Ashita: still restored', font.Scale, 1);
sc.frameEnd();
check('older Ashita: balanced', #stack, 0);
-- A font another addon already scaled keeps ITS factor: ours multiplies.
font.Scale = 1.5; sc.frameBegin();
check('older Ashita: multiplies an existing Scale', math.abs(scaleAtPush - 1.2) < 1e-9, true);
sc.frameEnd(); check('older Ashita: existing Scale restored', font.Scale, 1.5);
font.Scale = 1;

-- 5b. A binding that takes the push but ignores Scale: caught on the first
--     push, taken back, and off -- never "on" with nothing to show for it.
sc._reset(); pushes = {}; ignoreScale = true; sc.set(0.8);
sc.frameBegin();
check('ignored Scale: the push is taken back', #stack, 0);
check('ignored Scale: font restored', font.Scale, 1);
check('ignored Scale: off', sc.supported(), false);
check('ignored Scale: sizes unscaled', sc.px(100), 100);
sc.frameEnd(); sc.frameBegin(); sc.frameEnd();
check('ignored Scale: tried once', #pushes, 1);
ignoreScale = false;

-- 5c. Neither way exists: the choice is kept, nothing is drawn differently.
sc._reset(); base = nil; font = nil; pushes = {};
sc.set(0.8);
check('unsupported', sc.supported(), false);
check('saved is kept', sc.saved(), 0.8);
check('in effect is 100%', sc.get(), 1.0);
check('px identity when unsupported', sc.px(940), 940);
check('no resize for a scale that cannot show', sc.takeResize(), nil);
sc.frameBegin(); sc.frameEnd();
check('unsupported pushes nothing', #pushes, 0);
base = 18;

-- 6. A PushFont that throws is tried once, never popped, and off for the session.
sc._reset(); sc.set(0.8); throwPush = true;
sc.frameBegin(); sc.frameEnd();
check('a refused push leaves the stack alone', #stack, 0);
throwPush = false;
check('off after a refusal', sc.supported(), false);
check('...so sizes are unscaled too', sc.px(100), 100);
sc.frameBegin(); sc.frameEnd();
check('never retried', #pushes, 0);

-- 7. uiflags round trip: saved by one session, read by the next.
sc._reset(); sc.set(0.9);
local written = nil;
package.loaded['dlac\\lib\\cmdqueue'] = { issue = function() end };
local function flags()
    local sf = dofile('gear/syncflags.lua');
    sf.configure({ dataDir = function() return 'scratch/'; end, ui = {},
        callImport = function() return 0; end, refreshGear = function() end,
        writeFileText = function(_, text) written = text; end });
    return sf;
end
flags().saveUiFlags();
check('uiflags carries the scale', written ~= nil and written:find('uiscale = 0.90', 1, true) ~= nil, true);
local realLoadfile = loadfile;
local function loadWith(text)
    loadfile = function(path)
        if path == 'scratch/uiflags.lua' then return (loadstring or load)(text); end
        return realLoadfile(path);
    end;
    flags().loadUiFlags();
    loadfile = realLoadfile;
end
sc._reset();
loadWith(written);
check('...and the next session reads it', sc.saved(), 0.9);
check('...without resizing anything', sc.takeResize(), nil);
sc._reset();
loadWith('return { debug = false }');
check('a file from before the setting = 100%', sc.saved(), 1.0);
sc._reset();
loadWith('return { uiscale = 40 }');
check('a hand-edited value is clamped', sc.saved(), 1.5);

-- 8. The Stable tab under a scaled font: its pixel sizes follow, at 100% they
--    are the numbers it always had.
package.loaded['dlac\\ui\\filetex'] = { packHandle = function() return 1; end };
local view = require('dlac\\servers\\ascensionxi\\modules\\stable\\view');
local catalog = require('dlac\\servers\\ascensionxi\\modules\\stable\\catalog');
local function ctx()
    local owned, discovered = {}, {};
    for id = 2, 135 do owned[id] = { name = '', level = 0, hp = 0, tp = 0 }; discovered[id] = true; end
    return {
        catalog = catalog, names = setmetatable({}, { __index = function() return { '' }; end }),
        label = function(id) return 'Companion ' .. id; end, notice = '', pending = false,
        state = { owned = owned, discovered = discovered, roster = { 2, 0, 0 }, presets = {},
            activeRoster = 0, active = 0, captures = {} },
    };
end
local function layout()
    children, sizes = {}, {};
    sc.frameBegin();
    local ok, err = pcall(view.render, ctx());
    sc.frameEnd();
    assert(ok, err);
    local out = { cards = 0 };
    for _, c in ipairs(children) do
        if c.id == '##slot' then out.slot = c.h; end
        if c.id == '##companion' then out.cards = out.cards + 1; out.card = c.w; end
        if c.id == '##bstdetails' then out.details = c.w; end
    end
    out.portrait = sizes[1];
    return out;
end
sc._reset();
local full = layout();
check('100%: roster slot height', full.slot, 132);
check('100%: roster portrait', full.portrait, 54);
check('100%: details pane', full.details, 280);
sc.set(0.8);
local small = layout();
check('80%: roster slot height', small.slot, 106);
check('80%: roster portrait', small.portrait, 43);
check('80%: details pane', small.details, 250);   -- a quarter of the width, inside the scaled 224..288
check('80%: cards are narrower', small.card < full.card, true);
check('80%: more cards fit the same grid', small.cards > full.cards, true);
check('font stack balanced after the tab', #stack, 0);

print(string.format('UI scale: %d checks passed (both Ashita font paths, uiflags round trip, Stable tab layout).', n));
