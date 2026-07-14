--[[
    dlac/itemicons.lua

    Item-icon texture service (the trove/equipmon load_item_texture pattern),
    extracted from gearui (the LuaJIT 200-local chunk cap). One D3D texture per
    item id from the resource's in-memory bitmap, cached, drawn with imgui.Image.

    Every entry point degrades to a no-op / nil when imgui, ffi, or d3d8 could
    not be required (headless tests, missing libs) -- callers never need to
    check availability first.
]]--

local icons = {};

local imgui = (function()
    local ok, m = pcall(require, 'imgui');
    return (ok and m ~= nil) and m or nil;
end)();
local ffi = (function()
    local ok, m = pcall(require, 'ffi');
    return (ok and m ~= nil) and m or nil;
end)();
local d3d = (function()
    local ok, m = pcall(require, 'd3d8');
    return (ok and m ~= nil) and m or nil;
end)();

local hasD3D = imgui ~= nil and ffi ~= nil and d3d ~= nil;
local C, d3d8dev;
if hasD3D then
    C = ffi.C;
    local okdev, dev = pcall(function() return d3d.get_device(); end);
    if okdev and dev ~= nil then
        d3d8dev = dev;
    else
        hasD3D = false;
    end
    if hasD3D then
        pcall(function()
            ffi.cdef[[
                HRESULT __stdcall D3DXCreateTextureFromFileInMemoryEx(IDirect3DDevice8* pDevice, const void* pSrcData, unsigned int SrcDataSize, unsigned int Width, unsigned int Height, unsigned int MipLevels, unsigned int Usage, int Format, int Pool, unsigned int Filter, unsigned int MipFilter, unsigned int ColorKey, void* pSrcInfo, void* pPalette, IDirect3DTexture8** ppTexture);
            ]];
        end);
    end
end

local texCache   = {};   -- itemId -> texture (or false once we know it has none)
local texHandles = {};   -- itemId -> uint32 handle for imgui.Image

local function loadItemTexture(itemId)
    if not hasD3D then return false; end
    if texCache[itemId] ~= nil then return texCache[itemId]; end
    if itemId == nil or itemId == 0 then texCache[itemId] = false; return false; end

    local item = AshitaCore:GetResourceManager():GetItemById(itemId);
    if item == nil or item.ImageSize == nil or item.ImageSize == 0 then
        texCache[itemId] = false;
        return false;
    end

    pcall(function()
        local ptr = ffi.new('IDirect3DTexture8*[1]');
        if (C.D3DXCreateTextureFromFileInMemoryEx(
                d3d8dev, item.Bitmap, item.ImageSize,
                0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
                C.D3DFMT_A8R8G8B8, C.D3DPOOL_MANAGED,
                C.D3DX_DEFAULT, C.D3DX_DEFAULT,
                0xFF000000, nil, nil, ptr) == C.S_OK) then
            local tex = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]));
            texCache[itemId]   = tex;
            texHandles[itemId] = tonumber(ffi.cast('uint32_t', tex));
        end
    end);

    if texCache[itemId] == nil then texCache[itemId] = false; end
    return texCache[itemId];
end

-- The imgui.Image handle for an item's icon, loading the texture on first use.
-- nil when the item has no icon or d3d is unavailable -- callers fall back to a
-- text button / placeholder.
icons.handleOf = function(itemId)
    if itemId == nil or itemId == 0 then return nil; end
    if loadItemTexture(itemId) == false then return nil; end
    return texHandles[itemId];
end

-- The 8-element wheel: the icon for VIRTUAL slot entries (dlac:AutoIridescence /
-- dlac:AutoObi) -- one dot per element (classic hues) around a bright core,
-- painted with the window draw list (no texture to load). x may be an Ashita
-- vec2 table OR a plain number (both getter styles normalized here).
icons.drawElementWheel = function(size, x, y)
    if imgui == nil then return; end
    pcall(function()
        if type(x) == 'table' then x, y = (x[1] or x.x), (x[2] or x.y); end
        local dl = imgui.GetWindowDrawList();
        local COLS = { { 0.95, 0.25, 0.15 }, { 0.55, 0.85, 1.00 },   -- Fire, Ice
                       { 0.35, 0.90, 0.40 }, { 0.85, 0.65, 0.25 },   -- Wind, Earth
                       { 0.80, 0.40, 1.00 }, { 0.25, 0.45, 1.00 },   -- Thunder, Water
                       { 1.00, 1.00, 0.85 }, { 0.45, 0.25, 0.60 } }; -- Light, Dark
        local c = size / 2;
        dl:AddCircleFilled({ x + c, y + c }, size * 0.16, imgui.GetColorU32({ 1.0, 1.0, 0.92, 0.95 }), 12);
        local orbit, dot = size * 0.34, math.max(1.5, size * 0.11);
        for i, col in ipairs(COLS) do
            local a = (i - 1) * (math.pi / 4) - math.pi / 2;
            dl:AddCircleFilled({ x + c + math.cos(a) * orbit, y + c + math.sin(a) * orbit },
                dot, imgui.GetColorU32({ col[1], col[2], col[3], 1.0 }), 10);
        end
    end);
end

-- Draw an item icon (or a blank placeholder), then SameLine so the caller can put
-- the item's text right after it. Pass the record too when the entry may be a
-- VIRTUAL one (no Id) -- it gets the element wheel instead of a blank.
icons.renderIcon = function(itemId, size, rec)
    if imgui == nil then return; end
    local drew = false;
    if itemId ~= nil and itemId ~= 0 then
        local tex = loadItemTexture(itemId);
        local handle = texHandles[itemId];
        if tex and tex ~= false and handle ~= nil then
            pcall(function() imgui.Image(handle, { size, size }); end);
            drew = true;
        end
    end
    if not drew and rec ~= nil and rec.Virtual == true then
        drew = pcall(function()
            local x, y = imgui.GetCursorScreenPos();
            imgui.Dummy({ size, size });
            icons.drawElementWheel(size, x, y);
        end);
    end
    if not drew then
        pcall(function() imgui.Dummy({ size, size }); end);
    end
    imgui.SameLine(0, 6);
end

-- Release every cached texture (addon unload).
icons.release = function()
    for _, tex in pairs(texCache) do
        if tex and tex ~= false then
            pcall(function()
                ffi.gc(tex, nil);
                tex:Release();
            end);
        end
    end
    texCache   = {};
    texHandles = {};
end

return icons;
