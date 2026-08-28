--[[
    dlac/feature/servermods.lua -- the server-pack MODULE loader (ADR 0035).

    A server-pack module is a drop-in FOLDER under the active pack:
    servers\<id>\modules\<name>\init.lua. It is the home for code that only
    exists because that server exists -- CatsEyeXI's 0x1A4 protocol family,
    its game modes, its prestige system -- so on any other server the code
    is not gated off, it is NOT THERE.

    The manifest's `modules` list is the mount list AND the order: a name
    the manifest does not carry never loads, and registration order (tray
    rows, helper rows) follows the list. The jobhelpers containment
    discipline applies wholesale: a module whose init.lua is missing,
    malformed or throws gets ONE loud line and a ledger entry, never a
    crash and never collateral damage to its siblings.

    Contract (first-party, versioned WITH the repo -- no api number, unlike
    the third-party-facing Job helper contract): init.lua returns a table;
    OPTIONAL init(deps) runs after the require; OPTIONAL pump() is called
    every frame from dlac.lua's d3d_present beat (the prestigewatch pump's
    old seat, now generic). Everything else -- commands, packet handlers,
    serverpack.provide() services, ui registrations -- the module does
    itself at load, exactly as core feature modules always have.

    Core NEVER requires a servers\ path: it asks serverpack.service() for
    a provider a module registered, or lives without one.
]]--

local M = {};

local loaded = {};   -- name -> the module's init.lua return table
local order  = {};   -- names in mount order

local function emitErr(msg)
    local ok, cf = pcall(require, 'dlac\\chatfmt');
    if ok and type(cf) == 'table' and type(cf.err) == 'function' then
        pcall(cf.err, msg);
    else
        print('[dlac] ' .. tostring(msg));
    end
end

-- Mount the active pack's modules. Call once at boot, after the UI host is
-- up (the registration surfaces must exist). Idempotent per name.
function M.load(deps)
    local ok, sp = pcall(require, 'dlac\\gear\\serverpack');
    if not ok or type(sp) ~= 'table' then return; end
    local id  = sp.active();
    local man = sp.manifest();
    if id == nil or type(man) ~= 'table' or type(man.modules) ~= 'table' then return; end
    local ledger = package.loaded['dlac\\loadledger'];
    for _, name in ipairs(man.modules) do
        if loaded[name] == nil and type(name) == 'string' and name ~= '' then
            local okm, mod = pcall(require, 'dlac\\servers\\' .. id .. '\\modules\\' .. name .. '\\init');
            if type(ledger) == 'table' and type(ledger.failed) == 'table' then
                ledger.total = (tonumber(ledger.total) or 0) + 1;
                if not (okm and type(mod) == 'table') then
                    ledger.failed[#ledger.failed + 1] = { mod = 'server:' .. name, err = tostring(mod) };
                end
            end
            if okm and type(mod) == 'table' then
                loaded[name] = mod;
                order[#order + 1] = name;
                if type(mod.init) == 'function' then pcall(mod.init, deps); end
            else
                emitErr(('server module %s failed to load: %s'):format(name, tostring(mod)));
            end
        end
    end
end

-- The frame beat: every mounted module's pump, contained. A module without
-- one costs nothing.
function M.pump()
    for _, name in ipairs(order) do
        local mod = loaded[name];
        if type(mod) == 'table' and type(mod.pump) == 'function' then pcall(mod.pump); end
    end
end

function M.get(name) return loaded[name]; end

function M.list()
    local out = {};
    for _, name in ipairs(order) do out[#out + 1] = name; end
    return out;
end

-- test seam
function M._reset() loaded = {}; order = {}; end

return M;
