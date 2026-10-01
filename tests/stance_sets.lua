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
assert(not optim.isStanceSet(), 'new sets default off')
local opts = {job='RDM',level=75,weights={Accuracy={perUnit=1}}}
assert(optim.buildBestSet(opts).slots.Head == other.Name)
assert(optim.setStanceSet(true))
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
assert(optim.saveWeights())
optim.setStanceSet(false)
assert(optim.loadWeights())
assert(optim.isStanceSet(), 'reload preserves flag')
optim.bindSetWeights('RDM','Idle')
assert(not optim.isStanceSet(), 'flag stays per set')
optim.renameSetKey('RDM','Melee','Stance')
optim.bindSetWeights('RDM','Stance')
assert(optim.isStanceSet(), 'rename preserves flag')
local payload = assert(optim.renderJobWeightsTextAt(nil,'RDM'))
optim.setStanceSet(false)
assert(optim.importJobWeightsTextAt(nil,payload,'RDM','RDM'))
assert(optim.isStanceSet(), 'export/import preserves stance-only set')
sp.active = function() return 'cexi' end
assert(stance.apply(hat,hat.Stats,ctx)==hat.Stats, 'AXI only')
os.remove(tmp)
print('OK -- stance scoring, totals, defaults, persistence, rename and export/import')
