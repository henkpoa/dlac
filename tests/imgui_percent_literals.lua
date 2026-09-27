-- lua tests/imgui_percent_literals.lua [file ...]
-- Narrow source guard: direct literal arguments (including literal concatenation)
-- to printf-style widgets. Dynamic expressions still need call-site review.
local function tokens(source)
    local out, pos, line = {}, 1, 1;
    local function advance(last)
        local _, n = source:sub(pos, last):gsub('\n', '');
        line, pos = line + n, last + 1;
    end
    while pos <= #source do
        local rest = source:sub(pos, pos + 1);
        local comment = rest:sub(1, 2) == '--';
        local start = comment and pos + 2 or pos;
        local eq = source:match('^%[(=*)%[', start);
        if eq then
            local _, last = source:find(']' .. eq .. ']', start + #eq + 2, true);
            assert(last, 'unterminated long string/comment');
            if not comment then
                out[#out + 1] = { kind = 'string', value = source:sub(start + #eq + 2, last - #eq - 2), line = line };
            end
            advance(last);
        elseif comment then
            advance((source:find('\n', pos, true) or (#source + 1)) - 1);
        elseif rest:match('^%s') then
            advance(pos);
        elseif rest:sub(1, 1) == "'" or rest:sub(1, 1) == '"' then
            local quote, last = rest:sub(1, 1), pos + 1;
            while last <= #source do
                local ch = source:sub(last, last);
                if ch == '\\' then last = last + 2;
                elseif ch == quote then break;
                else last = last + 1; end
            end
            local literal = source:sub(pos, last);
            local value = assert(load('return ' .. literal, 'literal', 't', {}))();
            out[#out + 1] = { kind = 'string', value = value, line = line };
            advance(last);
        else
            local value = source:match('^[%a_][%w_]*', pos) or rest:match('^%.%.') or rest:sub(1, 1);
            out[#out + 1] = { kind = 'code', value = value, line = line };
            advance(pos + #value - 1);
        end
    end
    return out;
end

local function violations(source)
    local ts, bad = tokens(source), {};
    for i, t in ipairs(ts) do
        if t.kind == 'code' and (t.value == 'SetTooltip' or t.value == 'TextWrapped')
            and ts[i - 1] and ts[i - 1].value == '.' and ts[i + 1] and ts[i + 1].value == '(' then
            local j, text = i + 2, '';
            while ts[j] and ts[j].kind == 'string' do
                text = text .. ts[j].value;
                j = j + 1;
                if ts[j] and ts[j].value == '..' then j = j + 1; else break; end
            end
            if ts[j] and ts[j].value == ')' and text:gsub('%%%%', ''):find('%%') then
                bad[#bad + 1] = t.line;
            end
        end
    end
    return bad;
end

assert(#violations([[imgui.SetTooltip('0%')]]) == 1);
assert(#violations([[imgui.TextWrapped('safe ' .. '100%')]]) == 1);
assert(#violations('imgui.TextWrapped([=[100%]=])') == 1);
assert(#violations([[imgui.SetTooltip('100%%%')]]) == 1);
assert(#violations([[imgui.SetTooltip('0%% .. 100%%')]]) == 0);
assert(#violations([[imgui.Selectable('100%'); imgui.SetTooltip(esc('100%'));]]) == 0);
assert(#violations("-- imgui.SetTooltip('100%')\nlocal s = \"imgui.TextWrapped('100%')\"") == 0);

local files = { ... };
if #files == 0 then
    local pipe = assert(io.popen('git ls-files "*.lua"'));
    for file in pipe:lines() do
        if not file:match('^tests/') and not file:match('^dlacprobe/') then files[#files + 1] = file; end
    end
    assert(pipe:close());
end
local failures = 0;
for _, file in ipairs(files) do
    local f = assert(io.open(file, 'rb'));
    local source = f:read('*a'); f:close();
    local bad = (source:find('SetTooltip', 1, true) or source:find('TextWrapped', 1, true)) and violations(source) or {};
    for _, line in ipairs(bad) do
        io.stderr:write(file .. ':' .. line .. ': lone percent in literal printf-style widget text\n');
        failures = failures + 1;
    end
end
assert(failures == 0, tostring(failures) .. ' unsafe literal(s)');
print('ImGui percent literals: PASS (' .. #files .. ' files)');
