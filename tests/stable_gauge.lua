-- Pure native Ready clock boundaries, independent of a client/server checkout.
local recast = dofile('feature/recast.lua');
recast._recastMgr = function() return {
    GetAbilityTimerId = function(_, slot) return slot == 5 and 102 or 0; end,
    GetAbilityTimer = function() return 1; end,
}; end;
assert(recast.liveRemainingSeconds({ timerId = 102 }) == 1 / 60);
assert(recast.liveRemaining({ timerId = 102 }) == 0, 'existing rounded API remains compatible');
recast._recastMgr = function() return {}; end;
assert(recast.liveRemainingSeconds({ timerId = 102 }) == nil);
local gauge = dofile('servers/ascensionxi/modules/stable/gauge.lua');
local now, native, reads = 100, 0, 0;
gauge._clock = function() return now; end;
gauge._read = function() reads = reads + 1; return native; end;
assert(gauge.context(9, 75));
for period = 25, 30 do
    gauge.periodChanged();
    local epoch = gauge.requested();
    assert(gauge.accept(0, period * 1000, epoch));
    for missing = 0, 3 do
        native = missing * period;
        gauge.recastChanged(); gauge.pump();
        local v = gauge.view();
        assert(v.charges == 3 - missing and v.nextSeconds == (missing > 0 and period or 0));
        if missing > 0 then
            now = now + period - 1 / 60;
            assert(gauge.view().charges == 3 - missing);
            now = now + 2 / 60;
            assert(gauge.view().charges == 4 - missing);
        end
    end
end
native = 1 / 60; gauge.recastChanged(); gauge.pump();
assert(gauge.view().charges == 2, 'a fractional jiffy is still a spent charge');
now = now + 0.02; assert(gauge.view().charges == 3);
local before = reads;
for _ = 1, 216000 do now = now + 1 / 60; gauge.pump(); assert(gauge.view().charges == 3); end
assert(reads == before and not gauge.needsPeriod(), 'one idle hour: no slot rescans or period polling');
gauge.periodChanged(); local old = gauge.requested();
gauge.periodChanged(); assert(not gauge.accept(0, 30000, old), 'reject stale period after merit change');
assert(gauge.accept(90000, 25000, gauge.requested()));
native = 90; gauge.pump();
assert(gauge.view().charges == 0 and gauge.view().nextSeconds == 40, 'old debt with new merits');
gauge.zone(true); gauge.pump(); assert(gauge.view() == nil and not gauge.needsPeriod());
gauge.zone(false); assert(gauge.needsPeriod());
assert(not gauge.accept(0, 30000, old), 'a pre-zone reply cannot restore the gauge');
gauge.context(1, 75); assert(gauge.view() == nil and not gauge.needsPeriod());
gauge.context(9, 74); assert(gauge.needsPeriod());
gauge.accept(0, 30000, gauge.requested()); native = nil; gauge.pump();
assert(gauge.view() == nil, 'unknown native timer must not invent charges');
native = 5; gauge.recastChanged(); gauge.pump(); assert(gauge.view().charges == 2);
print('Stable clock: all six periods, fractional boundaries, one idle hour, merits, stale replies, zones and unknown reads passed.');
