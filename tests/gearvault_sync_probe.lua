-- Run from the DLAC root. Real client and transport; simulated 160ms replies.
local vc = dofile('servers/ascensionxi/modules/gearvault/vaultclient.lua')
local tr = dofile('servers/ascensionxi/transport.lua')
local w16, w32 = vc._wu16, vc._wu32
local function run(batch)
    vc._reset(); tr._reset()
    local now, wire, sends, transitions, previous = 100, nil, 0, 0, 'fresh'
    vc._clock = function() return now end
    tr._clock = vc._clock; tr._audit = nil
    tr._send = function(p) sends = sends + 1; wire = { due = now + 0.16, op = p[5], seq = p[6] }; return true end
    vc._send = function(p) return tr.send(p, 'probe') end
    vc._received = tr.received
    vc._readSlot = function(_, slot) return 1000 + slot end
    vc.limits = { instances = true, maxLookup = 41 }
    vc.revision = 10; vc.mirror.stamp = now; vc.mirror.fresh = true
    vc.invalidateInstances()
    local slots = {}
    for slot = 1, 16 do
        slots[#slots + 1] = { container = 8, slot = slot }
        if not batch then vc.instanceAt(8, slot, 1000 + slot) end
    end
    if batch then assert(vc.requestLookup(slots)) end
    local started = now
    for frame = 1, 1800 do
        now = 100 + frame / 60
        vc.pump(true)
        if wire and now >= wire.due then
            local reply = wire; wire = nil
            local entries = vc._st().lookupQ[1].entries
            local parts = { w16(#entries), w16(0), w32(10) }
            for _, e in ipairs(entries) do
                parts[#parts + 1] = string.char(e.container, e.slot) .. w16(1000 + e.slot)
                    .. w32(2000 + e.slot) .. string.char(1, 0) .. w16(0)
            end
            vc.onFrame({ op = reply.op, seq = reply.seq, status = 0, flags = 0, payload = table.concat(parts) })
        end
        local state = vc.state()
        if state ~= previous then transitions = transitions + 1; previous = state end
        if not vc._st().pending and #(vc._st().lookupQ or {}) == 0 then break end
    end
    for slot = 1, 16 do assert(vc.instanceAt(8, slot, 1000 + slot).instanceId == 2000 + slot) end
    print(string.format('%s: requests=%d elapsed=%.3fs status_transitions=%d', batch and 'batch API' or 'normal instanceAt', sends, now - started, transitions))
    return sends
end
local normal = run(false)
local batched = run(true)
assert(batched == 1)
if arg[1] == '--budget' then assert(normal <= 1, 'FAIL: 16 co-pending slots should fit one existing lookup request') end
