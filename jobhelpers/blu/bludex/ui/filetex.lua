--[[
    bludex/ui/filetex.lua -- load PNG files from the addon's icons/ folder as
    D3D textures for imgui.Image / imgui.ImageButton.

    Pattern ported from dlac/ui/filetex.lua, which learned it the hard way:
    CRITICAL: retain the texture OBJECT in `keep` -- storing only the numeric
    handle lets Lua GC the object, D3D frees the texture, and imgui then draws
    a dangling pointer -> hard crash.

    handle(relpath) -> uint32 texture handle for 'icons/<relpath>.png'
    (cached; nil if load failed or d3d/ffi unavailable -- callers must draw a
    fallback).
]]--

local M = {};

-- relocatable base: icons live inside this library's own folder, wherever
-- it sits ('bludex\' standalone, '<host>\bludexlib\' vendored)
local ROOT = (...):sub(1, -#('ui\\filetex') - 1);

local _fok, ffi = pcall(require, 'ffi');
local _dok, d3d = pcall(require, 'd3d8');
local has = _fok and _dok and ffi ~= nil and d3d ~= nil;

local dev;
if has then
    pcall(function()
        dev = d3d.get_device();
        pcall(ffi.cdef, 'HRESULT __stdcall D3DXCreateTextureFromFileA(IDirect3DDevice8* pDevice, const char* pSrcFile, IDirect3DTexture8** ppTexture);');
    end);
end

local cache, tried, keep = {}, {}, {};

-- relpath like 'Offensive/Head Butt-64-halo' or 'ui/logo-64' (no extension).
function M.handle(relpath)
    if not has or dev == nil then return nil; end
    if tried[relpath] then return cache[relpath]; end
    tried[relpath] = true;
    pcall(function()
        local path = string.format('%saddons\\%sicons\\%s.png',
            AshitaCore:GetInstallPath(), ROOT, relpath:gsub('/', '\\'));
        local ptr = ffi.new('IDirect3DTexture8*[1]');
        if ffi.C.D3DXCreateTextureFromFileA(dev, path, ptr) == 0 then   -- S_OK
            local tex = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]));
            keep[relpath] = tex;                        -- prevent GC of the texture
            cache[relpath] = tonumber(ffi.cast('uint32_t', tex));
        end
    end);
    return cache[relpath];
end

-- Spell sprite handle for a data row + variant key ('detail'|'grid128'|'grid64').
-- Suffix map comes from data/spells.lua M.meta.icons.
local suffixes = nil;
function M.spell(book, spell, variant)
    if spell == nil or spell.iconBase == nil then return nil; end
    if suffixes == nil then
        suffixes = (book and book.meta and book.meta.icons) or {};
    end
    local suffix = suffixes[variant] or '-64-halo.png';
    return M.handle(spell.iconBase .. suffix:gsub('%.png$', ''));
end

-- UI chrome icon by short name ('logo-64', 'element-Fire-16', ...). These are
-- OPTIONAL -- most are placeholders Henrik generates later (see
-- ICONS_WANTED.md); every caller draws a fallback when this returns nil.
function M.ui(name)
    return M.handle('ui/' .. name);
end

return M;
