table.insert(package.searchers or package.loaders, 1, function(name)
    local rel = name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end)
local sp = require('dlac\\gear\\serverpack')
sp._configLoader = function() return {server='ascensionxi'} end
sp.init()
local hat = {Id=12513, Name="Warlock's Chapeau", Level=50, Jobs={'RDM'}, Stats={Accuracy=1}}
local other = {Id=99999, Name='Ordinary hat', Level=50, Jobs={'RDM'}, Stats={Accuracy=5}}
package.loaded['dlac\\gear'] = {Head={hat,other}, NameToObject={}}
ashita = {events={register=function() end}}
local oracle = require('dlac\\gear\\gearoracle')
local optim = require('dlac\\gear\\gearoptim')
local stance = require('dlac\\gear\\stancestats')
local tmp = os.tmpname()
optim.weightsPath = function() return tmp end
optim.bindSetWeights('RDM','Melee')
assert(optim.setType() == 'normal', 'new sets default to Normal')
local opts = {job='RDM',level=75,weights={Accuracy={perUnit=1}}}
assert(optim.buildBestSet(opts).slots.Head == other.Name)
assert(optim.setSetType('ws1'))
assert(optim.buildBestSet(opts).slots.Head == other.Name, '1-Hit WS adds no stance bonus')
assert(not optim.stanceContext(75).stanceSet)
assert(not optim.setSetType('bogus'), 'an unknown type is refused')
assert(optim.setType() == 'ws1', 'and changes nothing')
assert(optim.setSetType('stance'))
assert(optim.buildBestSet(opts).slots.Head == hat.Name, 'stance changes best weighted pick')
local ctx = optim.stanceContext(75)
ctx.augStats = {[12513]={Accuracy=2}}
assert(oracle.stats(hat,ctx).Accuracy == 9)
assert(oracle.setStats({Head=hat},ctx).stats.Accuracy == 9, 'view and scoring agree')
assert(hat.Stats.Accuracy == 1, 'catalog must not mutate')
assert(stance.apply(hat,hat.Stats,{level=49,job='RDM',stanceSet=true}) == hat.Stats)
assert(stance.apply(hat,hat.Stats,{level=75,job='WAR',stanceSet=true}) == hat.Stats)
local comp = {}
for slot,id in pairs({Head=12513,Body=12642,Hands=13965,Legs=14218,Feet=14093}) do
    comp[slot]={Id=id,Level=50,Stats={}}
end
local totals=oracle.setStats(comp,optim.stanceContext(75)).stats
assert(totals.Accuracy==26 and totals.Attack==17 and totals.EnspellDamage==2)
local duel = {Id=15076, Level=74, Stats={}}
assert(stance.apply(duel,duel.Stats,optim.stanceContext(75)).EnhancingMagicSkill == 15, "Duelist's Chapeau under Focus/Trance")
-- stances.lua is hand-kept: its RDM table must equal the pack's generated
-- latent 30000 rows (RDM_STANCE_AT_LEAST, power 2 = Focus or Trance), both ways.
local rdm = dofile('servers/ascensionxi/stances.lua').RDM
local gen = {}
for id, rows in pairs(dofile('servers/ascensionxi/data/latentstats.lua')) do
    for _, r in ipairs(rows) do
        if r.cond == 'RDM_STANCE_AT_LEAST' then
            assert(r.param == 2, ('item %d: a stance latent at power %s; decide whether Duelist Stance counts it'):format(id, tostring(r.param)))
            gen[id] = gen[id] or {}
            gen[id][r.stat] = (gen[id][r.stat] or 0) + r.add
        end
    end
end
for id, stats in pairs(gen) do
    for k, v in pairs(stats) do
        assert(rdm[id] and rdm[id][k] == v, ('stances.lua RDM lacks item %d %s+%d'):format(id, k, v))
    end
end
for id, stats in pairs(rdm) do
    if type(id) == 'number' then
        for k, v in pairs(stats) do
            assert(gen[id] and gen[id][k] == v, ('stances.lua RDM item %d %s=%s has no latent row'):format(id, k, tostring(v)))
        end
    end
end
optim.bindSetWeights('RDM','WS')
assert(optim.setSetType('ws1'))
optim.bindSetWeights('RDM','Melee')
assert(optim.saveWeights())
optim.setSetType('normal')
assert(optim.loadWeights())
assert(optim.setType() == 'stance', 'reload preserves the type')
assert(optim.setTypeOf('RDM','WS') == 'ws1', 'and every other set\'s, read unbound')
assert(optim.setTypeOf('RDM','Nowhere') == 'normal')
assert(optim.setTypeOf('WAR','WS') == 'normal', 'types are per job')
-- An older dlac reads only stancePerSet: the file keeps the stance sets
-- there too, and only them.
local f = assert(io.open(tmp,'rb')); local text = f:read('*a'); f:close()
local legacy = text:match('stancePerSet = (%b{})')
assert(legacy and legacy:find('"RDM|Melee"',1,true) and not legacy:find('"RDM|WS"',1,true), 'legacy block = stance sets')
optim.bindSetWeights('RDM','Idle')
assert(optim.setType() == 'normal', 'type stays per set')
optim.renameSetKey('RDM','Melee','Stance')
optim.bindSetWeights('RDM','Stance')
assert(optim.setType() == 'stance', 'rename preserves the type')
local payload = assert(optim.renderJobWeightsTextAt(nil,'RDM'))
optim.setSetType('normal')
optim.bindSetWeights('RDM','WS'); optim.setSetType('normal')
assert(optim.importJobWeightsTextAt(nil,payload,'RDM','RDM'))
assert(optim.setTypeOf('RDM','Stance') == 'stance' and optim.setTypeOf('RDM','WS') == 'ws1',
    'export/import preserves type-only sets')
-- A file from before the Set Type: a ticked Stance Set is a 'stance' set.
f = assert(io.open(tmp,'wb'))
f:write('return { perSet = {}, stancePerSet = { ["RDM|Old"] = true, ["WAR|Axe"] = true }, typePerSet = { ["RDM|Mix"] = "ws1" } }')
f:close()
assert(optim.loadWeights())
assert(optim.setTypeOf('RDM','Old') == 'stance' and optim.setTypeOf('WAR','Axe') == 'stance', 'old flags load as stance')
assert(optim.setTypeOf('RDM','Mix') == 'ws1', 'a typed set keeps its type')
-- The menu: the job's stance where the pack has stance gear for it.
local function labels(job, cur)
    local out = {}
    for _, o in ipairs(optim.setTypeOptions(job, cur)) do out[#out+1] = o.label end
    return table.concat(out, ' / ')
end
assert(labels('RDM') == 'Normal / 1-Hit WS / Duelist Stance', labels('RDM'))
assert(labels('WAR') == 'Normal / 1-Hit WS / Berserk', labels('WAR'))
assert(labels('BLM') == 'Normal / 1-Hit WS', 'no stance gear, no stance row')
assert(labels('BLM','stance') == 'Normal / 1-Hit WS / Stance', 'a stance set elsewhere can be set back')
sp.active = function() return 'cexi' end
assert(stance.apply(hat,hat.Stats,ctx)==hat.Stats, 'AXI only')
assert(stance.label('RDM') == nil, 'no stance menu row off AXI')
os.remove(tmp)
print('OK -- Set Type: stance scoring, totals, defaults, persistence, migration, rename, export/import and the menu')
