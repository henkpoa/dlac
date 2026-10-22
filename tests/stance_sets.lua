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
assert(not totals.EnfeeblingMagicSkill, 'Duelist Stance leaves the Composure rows out')
-- Composure (2026-10-22): Red Mage's support stance, with its own rows.
assert(optim.setSetType('composure'))
local cctx = optim.stanceContext(75)
assert(cctx.stanceSet and cctx.stanceType == 'composure')
local ctotals = oracle.setStats(comp,cctx).stats
assert(ctotals.EnfeeblingMagicSkill == 15 and ctotals.HealingMagicSkill == 10 and ctotals.ConserveMP == 3,
    "Composure counts the Warlock's rows")
assert(not ctotals.Accuracy and not ctotals.Attack, "and not Duelist Stance's")
assert(optim.buildBestSet(opts).slots.Head == other.Name, "Composure adds nothing to the Warlock's Chapeau")
assert(stance.apply(duel,duel.Stats,cctx).EnfeeblingMagicSkill == 15, "Duelist's Chapeau under Composure")
assert(optim.setSetType('stance'))
-- stances.lua is hand-kept: each RDM table must equal the pack's generated
-- latent rows, both ways. Duelist Stance = latent 30000 (RDM_STANCE_AT_LEAST)
-- at power 2, Focus or Trance; Composure = latent 30001 (RDM_STANCE_EXACTLY)
-- at power 1.
local rdm = dofile('servers/ascensionxi/stances.lua').RDM
local latents = dofile('servers/ascensionxi/data/latentstats.lua')
local function parity(t, cond, power, name)
    local gen = {}
    for id, rows in pairs(latents) do
        for _, r in ipairs(rows) do
            if r.cond == cond then
                assert(r.param == power, ('item %d: %s at power %s; decide whether %s counts it'):format(id, cond, tostring(r.param), name))
                gen[id] = gen[id] or {}
                gen[id][r.stat] = (gen[id][r.stat] or 0) + r.add
            end
        end
    end
    assert(next(gen), name .. ': the pack has no ' .. cond .. ' rows')
    for id, stats in pairs(gen) do
        for k, v in pairs(stats) do
            assert(t[id] and t[id][k] == v, ('stances.lua %s lacks item %d %s+%d'):format(name, id, k, v))
        end
    end
    for id, stats in pairs(t) do
        if type(id) == 'number' then
            for k, v in pairs(stats) do
                assert(gen[id] and gen[id][k] == v, ('stances.lua %s item %d %s=%s has no latent row'):format(name, id, k, tostring(v)))
            end
        end
    end
end
parity(rdm.stance, 'RDM_STANCE_AT_LEAST', 2, 'Duelist Stance')
parity(rdm.composure, 'RDM_STANCE_EXACTLY', 1, 'Composure')
optim.bindSetWeights('RDM','WS')
assert(optim.setSetType('ws1'))
optim.bindSetWeights('RDM','Enfeeble')
assert(optim.setSetType('composure'))
optim.bindSetWeights('RDM','Melee')
assert(optim.saveWeights())
optim.setSetType('normal')
assert(optim.loadWeights())
assert(optim.setType() == 'stance', 'reload preserves the type')
assert(optim.setTypeOf('RDM','WS') == 'ws1', 'and every other set\'s, read unbound')
assert(optim.setTypeOf('RDM','Enfeeble') == 'composure', 'Composure too')
assert(optim.setTypeOf('RDM','Nowhere') == 'normal')
assert(optim.setTypeOf('WAR','WS') == 'normal', 'types are per job')
-- An older dlac reads only stancePerSet: the file keeps the stance sets
-- there too, and only them.
local f = assert(io.open(tmp,'rb')); local text = f:read('*a'); f:close()
local legacy = text:match('stancePerSet = (%b{})')
assert(legacy and legacy:find('"RDM|Melee"',1,true) and not legacy:find('"RDM|WS"',1,true), 'legacy block = stance sets')
assert(not legacy:find('"RDM|Enfeeble"',1,true), 'an older dlac must not plan a Composure set as Duelist Stance')
optim.bindSetWeights('RDM','Idle')
assert(optim.setType() == 'normal', 'type stays per set')
optim.renameSetKey('RDM','Melee','Stance')
optim.bindSetWeights('RDM','Stance')
assert(optim.setType() == 'stance', 'rename preserves the type')
local payload = assert(optim.renderJobWeightsTextAt(nil,'RDM'))
optim.setSetType('normal')
optim.bindSetWeights('RDM','WS'); optim.setSetType('normal')
optim.bindSetWeights('RDM','Enfeeble'); optim.setSetType('normal')
assert(optim.importJobWeightsTextAt(nil,payload,'RDM','RDM'))
assert(optim.setTypeOf('RDM','Stance') == 'stance' and optim.setTypeOf('RDM','WS') == 'ws1'
    and optim.setTypeOf('RDM','Enfeeble') == 'composure', 'export/import preserves type-only sets')
-- A file from before the Set Type: a ticked Stance Set is a 'stance' set.
f = assert(io.open(tmp,'wb'))
f:write('return { perSet = {}, stancePerSet = { ["RDM|Old"] = true, ["WAR|Axe"] = true }, typePerSet = { ["RDM|Mix"] = "ws1" } }')
f:close()
assert(optim.loadWeights())
assert(optim.setTypeOf('RDM','Old') == 'stance' and optim.setTypeOf('WAR','Axe') == 'stance', 'old flags load as stance')
assert(optim.setTypeOf('RDM','Mix') == 'ws1', 'a typed set keeps its type')
-- The menu: each stance the pack has gear for on that job.
local function labels(job, cur)
    local out = {}
    for _, o in ipairs(optim.setTypeOptions(job, cur)) do out[#out+1] = o.label end
    return table.concat(out, ' / ')
end
assert(labels('RDM') == 'Normal / 1-Hit WS / Composure / Duelist Stance', labels('RDM'))
assert(labels('WAR') == 'Normal / 1-Hit WS / Berserk', 'Composure only where the pack has it')
assert(labels('BLM') == 'Normal / 1-Hit WS', 'no stance gear, no stance row')
assert(labels('BLM','stance') == 'Normal / 1-Hit WS / Stance', 'a stance set elsewhere can be set back')
assert(labels('BLM','composure') == 'Normal / 1-Hit WS / Composure', 'a Composure set too')
assert(stance.label('RDM','composure') == 'Composure' and stance.label('RDM') == 'Duelist Stance')
sp.active = function() return 'cexi' end
assert(stance.apply(hat,hat.Stats,ctx)==hat.Stats, 'AXI only')
assert(stance.label('RDM') == nil and stance.label('RDM','composure') == nil, 'no stance menu row off AXI')
os.remove(tmp)
print('OK -- Set Type: stance and Composure scoring, totals, defaults, persistence, migration, rename, export/import and the menu')
