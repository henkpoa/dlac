--[[
    dlac/filetex.lua -- load PNG files from the addon's assets/ folder as D3D
    textures for imgui.Image / imgui.ImageButton. Its own module because
    gearui sits at the LuaJIT 200-local cap (hard rule 1). handle(name) returns
    a uint32 texture handle (cached; nil if load failed or d3d/ffi unavailable).
]]--

local M = {};

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

-- name -> assets/<name>.png handle (loaded once). nil on any failure.
-- CRITICAL: retain the texture OBJECT in `keep` -- storing only the numeric
-- handle lets Lua GC the object, D3D frees the texture, and imgui then draws a
-- dangling pointer -> hard crash. (This was the header-icon crash.)
function M.handle(name)
    if not has or dev == nil then return nil; end
    if tried[name] then return cache[name]; end
    tried[name] = true;
    pcall(function()
        local path = string.format('%saddons\\dlac\\assets\\%s.png', AshitaCore:GetInstallPath(), name);
        local ptr = ffi.new('IDirect3DTexture8*[1]');
        if ffi.C.D3DXCreateTextureFromFileA(dev, path, ptr) == 0 then   -- S_OK
            local tex = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]));
            keep[name] = tex;                                   -- prevent GC of the texture
            cache[name] = tonumber(ffi.cast('uint32_t', tex));
        end
    end);
    return cache[name];
end

return M;
