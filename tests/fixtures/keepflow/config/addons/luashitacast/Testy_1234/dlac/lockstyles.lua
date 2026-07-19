-- LGF fixture: legacy-tier lockstyle file for the keep-on-subjob flow test
-- (tests\run_tests.lua, LGF series). Box 3 saved, keep option on.
return {
    active = 3,
    keepSub = true,
    onload = {},
    slots = {
        [3] = { name = 'test', set = { Body = 'Foo' } },
    },
};
