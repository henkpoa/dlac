-- ===========================================================================
-- (Re)generate the Gear Oracle golden-output goldens (issue #72, PRD #69 gate).
-- Run from the dlac addon root:   lua5.4 tests/gen_goldens.lua
--
-- Writes tests/golden/*.golden from tests/goldenfixtures.lua's capture(). Run
-- this ONLY after an INTENTIONAL builder/format change, and REVIEW the diff:
-- a golden change is a claim that a field-tuned ladder's output moved, which the
-- Phase 2 stat-glue migration by definition must NOT do (that migration must
-- reproduce these goldens byte-identically). smoke_ui section 12 asserts it.
-- ===========================================================================

local sep = package.config:sub(1, 1);
local fixtures = dofile('tests' .. sep .. 'goldenfixtures.lua');

if sep == '\\' then os.execute('mkdir "tests\\golden" >nul 2>&1');
else os.execute('mkdir -p "tests/golden" >/dev/null 2>&1'); end

local goldens = fixtures.capture();
local names = {};
for name in pairs(goldens) do names[#names + 1] = name; end
table.sort(names);

for _, name in ipairs(names) do
    local text = goldens[name];
    if text == nil then
        print('SKIP ' .. name .. ' -- capture returned nil');
    else
        local p = fixtures.pathFor(name);
        local f = assert(io.open(p, 'wb'), 'cannot write ' .. p);
        f:write(text);
        f:close();
        print(string.format('wrote %s (%d bytes)', p, #text));
    end
end
