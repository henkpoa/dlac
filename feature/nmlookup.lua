--[[
    dlac/feature/nmlookup.lua -- `/dl nm [name]`: which notorious monsters are
    in this zone, what pops them, and the FilterScan filter that shows only
    those spawn points.

    Henrik, 2026-08-03: "it's always annoying to find out PH IDs etc, also
    filterscan addon can track off of name and Index. It would be nice to give
    you an NM name, and you can look up the place holder IDs and even indexes
    if possible and give me a filterscan filter I can apply."

    WHAT MAKES THIS ANSWERABLE OFFLINE
    data/nmdata.lua (tools/gen_nmdata.py, from a local server clone) already
    holds the finished arithmetic: per zone, every NM and its placeholders as
    TARGET INDEXES. Index = mobid & 0xFFF -- the same value FilterScan derives
    from the zone NPC DAT (bit.band(id, 0x0FFF)), so the numbers here are the
    numbers it matches on. Nothing is computed from live memory except "which
    zone am I in", which comes from feature/location (the central service --
    memory: central-services, consume never re-derive).

    THE FILTER FilterScan's own rule (filterscan.lua, packet 0x00F4) is:
        n:find(v) or tidx == tonumber(v, 16) or v == tostring(tidx)
    -- a widescan row survives if ANY filter term matches its name as a Lua
    pattern, its index as HEX, or its index as DECIMAL. We emit plain decimal
    indexes: the PHs plus the NM itself, so the camp shows the moment it pops.
    Terms are OR-ed, so an unrelated row whose index happens to equal one of
    ours read as hex can also survive -- that only ever ADDS a row, it can
    never hide a placeholder, so it is left alone rather than papered over.

    MATCHING is deliberately forgiving (Henrik: "try to take the one that is
    closest resemblance"): exact, then prefix, then substring, then an edit
    distance. A weak best match is still shown, but labelled as a guess so a
    typo never silently answers about the wrong monster.

    Zone scope: the current zone first. If the name is not an NM here we say
    so and name the zone it IS in rather than dead-ending on "not found" --
    the indexes travel with you.
]]--

local M = {};

local function try(name)
    local ok, m = pcall(require, name);
    return (ok and type(m) == 'table') and m or nil;
end

local _cfmt = try('dlac\\chatfmt');
local function sayMsg(s)  if _cfmt then _cfmt.msg(s)  else print('[dlac] ' .. tostring(s)); end end
local function sayGood(s) if _cfmt then _cfmt.good(s) else print('[dlac] ' .. tostring(s)); end end
local function sayWarn(s) if _cfmt then _cfmt.warn(s) else print('[dlac] ' .. tostring(s)); end end

-- The generated table. A missing/old file degrades the feature OFF rather
-- than erroring (the nativemp rule).
M.data = try('dlac\\data\\nmdata') or {};
-- Zone names come from the one zone table everything else uses.
local _zones = try('dlac\\data\\zones') or {};
-- Live zone id via the central location service; injectable for headless
-- tests (a FUNCTION, not a value -- memory: headless-tests-and-ffxi-lac).
local _loc = try('dlac\\feature\\location');
M.zoneReader = function()
    if _loc ~= nil and type(_loc.zoneId) == 'function' then return _loc.zoneId(); end
    return nil;
end;

-- ---------------------------------------------------------------------------
-- small helpers
-- ---------------------------------------------------------------------------

function M.zoneName(zid)
    local z = _zones[zid];
    if type(z) == 'table' and type(z.n) == 'string' then return z.n; end
    return 'zone ' .. tostring(zid);
end

-- "354,355,356,357,358,359" -> "354-359"; keeps gaps ("73, 75-77").
local function runs(list)
    if list == nil or #list == 0 then return ''; end
    local s = {};
    for _, v in ipairs(list) do s[#s + 1] = v; end
    table.sort(s);
    local out, i = {}, 1;
    while i <= #s do
        local j = i;
        while j < #s and s[j + 1] == s[j] + 1 do j = j + 1; end
        if j > i then
            out[#out + 1] = string.format('%d-%d', s[i], s[j]);
        else
            out[#out + 1] = tostring(s[i]);
        end
        i = j + 1;
    end
    return table.concat(out, ', ');
end
M.runs = runs;

local function fmtDur(sec)
    sec = tonumber(sec) or 0;
    if sec >= 3600 then
        local h = sec / 3600;
        if h == math.floor(h) then return string.format('%dh', h); end
        return string.format('%.1fh', h);
    end
    if sec >= 60 then return string.format('%dm', math.floor(sec / 60)); end
    return string.format('%ds', sec);
end
M.fmtDur = fmtDur;

-- ---------------------------------------------------------------------------
-- fuzzy match
-- ---------------------------------------------------------------------------

local function norm(s)
    return (tostring(s or ''):lower():gsub('[^%a%d]', ''));
end

-- Classic Levenshtein, two-row. Names are short; this is not hot.
local function lev(a, b)
    local la, lb = #a, #b;
    if la == 0 then return lb; end
    if lb == 0 then return la; end
    local prev, cur = {}, {};
    for j = 0, lb do prev[j] = j; end
    for i = 1, la do
        cur[0] = i;
        local ca = a:byte(i);
        for j = 1, lb do
            local cost = (ca == b:byte(j)) and 0 or 1;
            local d = prev[j] + 1;
            local ins = cur[j - 1] + 1;
            if ins < d then d = ins; end
            local sub = prev[j - 1] + cost;
            if sub < d then d = sub; end
            cur[j] = d;
        end
        for j = 0, lb do prev[j] = cur[j]; end
    end
    return prev[lb];
end
M.lev = lev;

-- Higher is better. 0 means "no resemblance at all".
function M.score(query, name)
    local q, n = norm(query), norm(name);
    if q == '' or n == '' then return 0; end
    if q == n then return 1000; end
    if n:sub(1, #q) == q then return 900 - (#n - #q); end
    if n:find(q, 1, true) ~= nil then return 800 - (#n - #q); end
    -- every word of the query appears somewhere (handles "baldarich steel")
    local all, any = true, false;
    for w in tostring(query):lower():gmatch('[%a%d]+') do
        any = true;
        if n:find(w, 1, true) == nil then all = false; break; end
    end
    if any and all then return 700; end
    local d = lev(q, n);
    local longest = (#q > #n) and #q or #n;
    local sim = 1 - (d / longest);
    if sim < 0.5 then return 0; end            -- unrelated; don't guess wildly
    return math.floor(sim * 600);
end

-- The score a cross-zone answer must beat. Inside your zone a loose guess is
-- cheap (a handful of candidates, and you can see what is around you); across
-- all 221 zones a loose guess is just noise, so the whole-game fallback only
-- accepts a real name hit -- exact, prefix, substring, or every word present.
M.ANYWHERE_FLOOR = 700;

-- Ties are common: Nyzul Isle and the Dynamis zones carry their own copies of
-- many NM names, and those copies are instanced pops with no placeholders.
-- When the score ties, prefer the entry that HAS placeholders -- that is the
-- open-world camp, and it is the only one this command can hand you a useful
-- filter for.
local function beats(s, e, bestS, bestE)
    if bestE == nil then return s > 0; end
    if s ~= bestS then return s > bestS; end
    local has  = (e.ph ~= nil and #e.ph > 0);
    local bhas = (bestE.ph ~= nil and #bestE.ph > 0);
    return has and not bhas;
end

-- Best entry for `query` within one zone. -> entry, score
function M.matchInZone(zid, query)
    local list = M.data[zid];
    if type(list) ~= 'table' then return nil, 0; end
    local best, bestScore = nil, 0;
    for _, e in ipairs(list) do
        local s = M.score(query, e.n);
        if beats(s, e, bestScore, best) then best, bestScore = e, s; end
    end
    return best, bestScore;
end

-- Best entry anywhere. -> entry, score, zoneId
-- Zone ids are walked in order so the answer never depends on hash order.
function M.matchAnywhere(query)
    local zids = {};
    for zid, list in pairs(M.data) do
        if type(list) == 'table' then zids[#zids + 1] = zid; end
    end
    table.sort(zids);
    local best, bestScore, bestZone = nil, 0, nil;
    for _, zid in ipairs(zids) do
        for _, e in ipairs(M.data[zid]) do
            local s = M.score(query, e.n);
            if beats(s, e, bestScore, best) then best, bestScore, bestZone = e, s, zid; end
        end
    end
    return best, bestScore, bestZone;
end

-- ---------------------------------------------------------------------------
-- rendering
-- ---------------------------------------------------------------------------

-- The FilterScan argument: placeholders + the NM, decimal, comma separated.
function M.filterFor(entry)
    if type(entry) ~= 'table' then return nil; end
    local seen, all = {}, {};
    for _, t in ipairs({ entry.ph or {}, entry.nm or {} }) do
        for _, v in ipairs(t) do
            if not seen[v] then seen[v] = true; all[#all + 1] = v; end
        end
    end
    if #all == 0 then return nil; end
    table.sort(all);
    local parts = {};
    for _, v in ipairs(all) do parts[#parts + 1] = tostring(v); end
    return table.concat(parts, ',');
end

-- Lines describing one NM. `guess` marks a weak match.
function M.describe(entry, zid, guess)
    local out = {};
    if type(entry) ~= 'table' then return out; end
    local where = M.zoneName(zid);
    out[#out + 1] = string.format('%s -- %s', entry.n, where);
    if guess then
        out[#out + 1] = '  (closest match to what you typed -- not an exact name)';
    end
    if entry.ph == nil or #entry.ph == 0 then
        out[#out + 1] = string.format('  NM index %s -- no placeholders: the server pops this one another way (pop item, timed, or forced).', runs(entry.nm or {}));
        local f = M.filterFor(entry);
        if f ~= nil then out[#out + 1] = '  /filterscan ' .. f; end
        return out;
    end
    local phcount = #entry.ph;
    local bits = string.format('  placeholder: %s x%d', entry.p or '?', phcount);
    if entry.c ~= nil then bits = bits .. string.format(', %d%% per kill', entry.c); end
    if type(entry.w) == 'table' and entry.w[1] ~= nil then
        if entry.w[2] ~= nil and entry.w[2] ~= entry.w[1] then
            bits = bits .. string.format(', repop %s-%s', fmtDur(entry.w[1]), fmtDur(entry.w[2]));
        else
            bits = bits .. string.format(', repop %s', fmtDur(entry.w[1]));
        end
    end
    out[#out + 1] = bits;
    out[#out + 1] = string.format('  NM index %s  |  PH indexes %s',
        runs(entry.nm or {}), runs(entry.ph));
    out[#out + 1] = '  /filterscan ' .. (M.filterFor(entry) or '');
    return out;
end

-- Lines listing every NM in a zone.
function M.listLines(zid)
    local out = {};
    local list = M.data[zid];
    if type(list) ~= 'table' or #list == 0 then
        out[#out + 1] = string.format('%s: no notorious monsters in the table.', M.zoneName(zid));
        return out;
    end
    local withPh, without = {}, {};
    for _, e in ipairs(list) do
        if e.ph ~= nil and #e.ph > 0 then withPh[#withPh + 1] = e; else without[#without + 1] = e; end
    end
    out[#out + 1] = string.format('%s -- %d NM(s), %d with placeholders:',
        M.zoneName(zid), #list, #withPh);
    for _, e in ipairs(withPh) do
        out[#out + 1] = string.format('  %-26s PH %s x%d  (%s)',
            e.n, e.p or '?', #e.ph, runs(e.ph));
    end
    if #without > 0 then
        local names = {};
        for _, e in ipairs(without) do names[#names + 1] = e.n; end
        out[#out + 1] = '  no placeholders (pop item / timed / forced): ' .. table.concat(names, ', ');
    end
    out[#out + 1] = '  /dl nm <name> for one NM\'s indexes and a ready filter.';
    return out;
end

-- ---------------------------------------------------------------------------
-- /dl nm [name] [apply]
-- ---------------------------------------------------------------------------

function M.command(rest)
    rest = tostring(rest or ''):gsub('^%s+', ''):gsub('%s+$', '');

    if next(M.data) == nil then
        sayWarn('nm: data/nmdata.lua is missing or empty -- re-run tools/gen_nmdata.py.');
        return;
    end

    -- Trailing `apply`. `%s*` not `%s+` so a bare `/dl nm apply` is understood
    -- as the verb too, instead of being hunted for as an NM called "apply".
    local apply = false;
    local stripped = rest:gsub('%s*apply%s*$', '');
    if stripped ~= rest then apply = true; rest = stripped; end

    local zid = M.zoneReader();

    -- bare: list this zone
    if rest == '' then
        if zid == nil then
            sayWarn('nm: cannot read your zone right now -- try again once you are loaded in.');
            return;
        end
        local lines = M.listLines(zid);
        for i, line in ipairs(lines) do
            if i == 1 then sayGood(line); else sayMsg(line); end
        end
        -- Asked to apply, but a zone-wide list is not one camp. Say so rather
        -- than dropping the word on the floor.
        if apply then
            sayWarn('  nothing to apply -- name one NM: /dl nm <name> apply');
        end
        return;
    end

    -- named: this zone first, then anywhere
    local entry, score, foundZone = nil, 0, zid;
    if zid ~= nil then entry, score = M.matchInZone(zid, rest); end
    local elsewhereNote = nil;
    if entry == nil or score < M.ANYWHERE_FLOOR then
        local e2, s2, z2 = M.matchAnywhere(rest);
        if e2 ~= nil and s2 >= M.ANYWHERE_FLOOR and s2 > score then
            if zid ~= nil and z2 ~= zid then
                elsewhereNote = string.format('not in %s -- that one is in %s',
                    M.zoneName(zid), M.zoneName(z2));
            end
            entry, score, foundZone = e2, s2, z2;
        end
    end

    if entry == nil or score == 0 then
        sayWarn(string.format('nm: nothing resembling "%s" in the NM table.', rest));
        if zid ~= nil then sayMsg('  /dl nm  lists what is in this zone.'); end
        return;
    end

    if elsewhereNote ~= nil then sayWarn('nm: ' .. elsewhereNote); end
    local lines = M.describe(entry, foundZone, score < 800);
    for i, line in ipairs(lines) do
        if i == 1 then sayGood(line); else sayMsg(line); end
    end

    if apply then
        local f = M.filterFor(entry);
        if f == nil then
            sayWarn('  nothing to filter on for that one.');
        else
            local ok = pcall(function()
                AshitaCore:GetChatManager():QueueCommand(-1, '/filterscan ' .. f);
            end);
            if ok then
                sayGood('  applied (FilterScan must be loaded for this to bite).');
            else
                sayWarn('  could not send the command -- paste the line above instead.');
            end
        end
    end
end

ashita.events.register('command', 'dlac-nmlookup-cmd', function(e)
    pcall(function()
        local raw = tostring(e.command or '');
        local a, rest = raw:match('^/dl%s+(%S+)%s*(.*)$');
        if a == nil then a, rest = raw:match('^/dlac%s+(%S+)%s*(.*)$'); end
        if a == nil then return; end
        a = a:lower();
        if a ~= 'nm' and a ~= 'nms' and a ~= 'placeholder' and a ~= 'ph' then return; end
        e.blocked = true;
        M.command(rest);
    end);
end);

return M;
