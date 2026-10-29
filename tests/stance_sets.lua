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
-- stances.lua is hand-kept: each table must equal the pack's generated
-- latent rows, both ways. Duelist Stance = latent 30000 (RDM_STANCE_AT_LEAST)
-- at power 2, Focus or Trance; Composure = latent 30001 (RDM_STANCE_EXACTLY)
-- at power 1; Divine Guard and Divine Fury = latent 30002
-- (PLD_STANCE_EXACTLY) at power 1 and 2.
local packStances = dofile('servers/ascensionxi/stances.lua')
local rdm, pld = packStances.RDM, packStances.PLD
local latents = dofile('servers/ascensionxi/data/latentstats.lua')
local claimed = {}
local function parity(t, cond, power, name)
    claimed[cond .. '@' .. power] = true
    local gen = {}
    for id, rows in pairs(latents) do
        for _, r in ipairs(rows) do
            if r.cond == cond and r.param == power then
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
parity(pld.divineguard, 'PLD_STANCE_EXACTLY', 1, 'Divine Guard')
parity(pld.divinefury, 'PLD_STANCE_EXACTLY', 2, 'Divine Fury')
-- Every stance latent row in the pack belongs to one of those tables: a new
-- power (Trance only, say) or a new job's stance latent needs a decision.
for id, rows in pairs(latents) do
    for _, r in ipairs(rows) do
        if tostring(r.cond):find('_STANCE_', 1, true) then
            assert(claimed[r.cond .. '@' .. r.param],
                ('item %d: %s at power %s; decide which Set Type counts it'):format(id, r.cond, tostring(r.param)))
        end
    end
end
-- gearoptim's Set Types are Normal, 1-Hit WS and exactly stancestats' TYPES.
local want = {normal = true, ws1 = true}
for _, id in ipairs(stance.TYPES) do want[id] = true end
for id in pairs(want) do assert(optim.SET_TYPES[id] == true, 'gearoptim lacks Set Type ' .. id) end
for id in pairs(optim.SET_TYPES) do assert(want[id], 'stancestats.TYPES lacks Set Type ' .. id) end
-- Paladin (2026-10-25): Divine Guard and Divine Fury, each with its own rows.
optim.bindSetWeights('PLD','Tank')
assert(optim.setSetType('divineguard'))
local gctx = optim.stanceContext(75)
assert(gctx.stanceSet and gctx.stanceType == 'divineguard' and gctx.job == 'PLD')
local gallant = {}
for slot,id in pairs({Head=12515,Body=12644,Hands=13967,Legs=14220,Feet=14095}) do
    gallant[slot]={Id=id,Level=50,Stats={}}
end
local gtotals = oracle.setStats(gallant,gctx).stats
assert(gtotals.Enmity == 8 and gtotals.VIT == 10 and gtotals.AGI == 6 and gtotals.ShieldSkill == 7
    and gtotals.CoverDuration == 5 and gtotals.CoverMagicRanged == 1, 'Divine Guard counts the Gallant rows')
assert(not gtotals.Accuracy and not gtotals.STR, "and not Divine Fury's")
assert(optim.setSetType('divinefury'))
local fctx = optim.stanceContext(75)
assert(fctx.stanceSet and fctx.stanceType == 'divinefury')
local ftotals = oracle.setStats(gallant,fctx).stats
assert(ftotals.Accuracy == 12 and ftotals.STR == 11 and ftotals.DEX == 6 and ftotals.Attack == 8,
    'Divine Fury counts the Gallant rows')
assert(not ftotals.Enmity and not ftotals.VIT, "and not Divine Guard's")
local valorHead = {Id=15078, Level=73, Stats={}}
local vf = stance.apply(valorHead,valorHead.Stats,fctx)
assert(vf.PaladinLightDuration == 15 and vf.SkillchainDamage == 5 and not vf.RampartDuration, 'Valor Coronet in Divine Fury')
assert(stance.apply(valorHead,valorHead.Stats,gctx).RampartDuration == 15, 'Valor Coronet in Divine Guard')
assert(stance.apply(valorHead,valorHead.Stats,{level=72,job='PLD',stanceSet=true,stanceType='divinefury'}) == valorHead.Stats,
    'a piece above the planned level adds nothing')
assert(stance.apply(gallant.Head,{},{level=75,job='RDM',stanceSet=true,stanceType='divineguard'}).VIT == nil,
    'Paladin rows are Paladin only')
optim.bindSetWeights('RDM','Melee')
optim.bindSetWeights('RDM','WS')
assert(optim.setSetType('ws1'))
optim.bindSetWeights('RDM','Enfeeble')
assert(optim.setSetType('composure'))
optim.bindSetWeights('PLD','Guard')
assert(optim.setSetType('divineguard'))
optim.bindSetWeights('RDM','Melee')
assert(optim.saveWeights())
optim.setSetType('normal')
assert(optim.loadWeights())
assert(optim.setType() == 'stance', 'reload preserves the type')
assert(optim.setTypeOf('RDM','WS') == 'ws1', 'and every other set\'s, read unbound')
assert(optim.setTypeOf('RDM','Enfeeble') == 'composure', 'Composure too')
assert(optim.setTypeOf('RDM','Nowhere') == 'normal')
assert(optim.setTypeOf('WAR','WS') == 'normal', 'types are per job')
assert(optim.setTypeOf('PLD','Guard') == 'divineguard' and optim.setTypeOf('PLD','Tank') == 'divinefury',
    'Divine Guard and Divine Fury too')
-- An older dlac reads only stancePerSet: the file keeps the stance sets
-- there too, and only them.
local f = assert(io.open(tmp,'rb')); local text = f:read('*a'); f:close()
local legacy = text:match('stancePerSet = (%b{})')
assert(legacy and legacy:find('"RDM|Melee"',1,true) and not legacy:find('"RDM|WS"',1,true), 'legacy block = stance sets')
assert(not legacy:find('"RDM|Enfeeble"',1,true), 'an older dlac must not plan a Composure set as Duelist Stance')
assert(not legacy:find('"PLD|',1,true), 'nor a Paladin stance set as a stance set')
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
assert(labels('PLD') == 'Normal / 1-Hit WS / Divine Guard / Divine Fury', labels('PLD'))
assert(labels('WAR','divinefury') == 'Normal / 1-Hit WS / Berserk / Divine Fury', 'a Paladin stance set elsewhere can be set back')
assert(stance.label('RDM','composure') == 'Composure' and stance.label('RDM') == 'Duelist Stance')
assert(stance.label('PLD','divineguard') == 'Divine Guard' and stance.label('PLD','divinefury') == 'Divine Fury')
assert(stance.label('PLD') == nil, 'Paladin has no plain stance table')
-- The hover card (2026-10-29): every stance bonus a piece has, one line per
-- stance in menu order, whatever job, level or set is in view.
local fmt = require('dlac\\gear\\gearfmt')
local function lines(id) return table.concat(fmt.stanceLines({Id=id}), ' | ') end
assert(lines(12642) == 'Composure: Enfeebling Magic Skill+15 | Duelist Stance: Accuracy+5 Attack+5', lines(12642))
assert(lines(12644) == 'Divine Guard: VIT+4 Enmity+2 Shield Skill+5 | Divine Fury: Accuracy+6 STR+5', lines(12644))
assert(lines(16678) == 'Berserk: Attack+10', lines(16678))
assert(lines(19978) == 'Composure: INT+4 MND+4 | Duelist Stance: Enhancing Magic Skill+4 EnspellDamage+2'
    or lines(19978) == 'Composure: INT+4 MND+4 | Duelist Stance: EnspellDamage+2 Enhancing Magic Skill+4', lines(19978))
assert(lines(99999) == '', 'a piece without stance gear gets no line')
assert(fmt.stanceLines({}) and #fmt.stanceLines({}) == 0 and #fmt.stanceLines(nil) == 0)
assert(#stance.bonusesOf({Id=15078, Level=75}) == 2, 'Valor Coronet: both stances, read without a level')
sp.active = function() return 'cexi' end
assert(stance.apply(hat,hat.Stats,ctx)==hat.Stats, 'AXI only')
assert(stance.label('RDM') == nil and stance.label('RDM','composure') == nil, 'no stance menu row off AXI')
assert(stance.label('PLD','divineguard') == nil, 'nor a Paladin one')
assert(lines(12644) == '' and #stance.bonusesOf({Id=12515}) == 0, 'no stance lines off AXI')
os.remove(tmp)
print('OK -- Set Type: stance, Composure, Divine Guard and Divine Fury scoring, totals, defaults, persistence, migration, rename, export/import, the menu and the hover card')
