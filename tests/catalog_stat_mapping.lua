table.insert(package.searchers or package.loaders, 1, function(name)
 local rel = name:match('^dlac\\(.+)$'); if rel then return loadfile((rel:gsub('\\', '/')) .. '.lua'); end
end)
local sp = require('dlac\\gear\\serverpack'); sp._configLoader = function() return {server='ascensionxi'} end; sp.init()
local ci = require('dlac\\gear\\catalogindex')
package.loaded['dlac\\gear'] = {NameToObject={}}
ashita = {events={register=function() end}}
local optim = require('dlac\\gear\\gearoptim')
local fmt = require('dlac\\gear\\gearfmt'); fmt.configure({effStats=function(r) return r.Stats end})
local r = ci.rawById(12642)
local score = optim.score(r.Stats, {EnfeeblingMagicSkill={perUnit=2}})
print('tooltip: '..fmt.fullStatList(r.Stats))
print('list: '..fmt.statSummary(r))
print('score: '..score)
assert(score == 30, 'Warlock tabard must score 15 enfeebling skill x 2 = 30')
assert(fmt.fullStatList(r.Stats):find('Enfeebling',1,true), 'tooltip must name enfeebling skill')
assert(fmt.statSummary(r):find('Enfeebling',1,true), 'list must include enfeebling skill')
assert(fmt.statSummary(r):find('(+1 more)',1,true), 'summary must disclose omitted stats')
local aliases = require('dlac\\gear\\modaliases')
local sd = require('dlac\\gear\\statdefs')
local checked, found = 0, {}
for _, rec in pairs(ci.rawIndex()) do
 for key, value in pairs(rec.Stats or {}) do
  assert(not aliases[key], rec.Name .. ': raw server modifier ' .. key)
  found[key] = true
 end
end
for raw, canonical in pairs(aliases) do
 assert(sd.byKey[canonical], 'unregistered canonical stat: ' .. canonical)
 assert(sd.canon(raw) == canonical, 'stat metadata alias: ' .. raw)
 assert(found[canonical], 'catalog lost stat: ' .. canonical)
 assert(optim.score({[canonical]=15}, {[raw]={perUnit=2}}) == 30,
  'legacy weight must still score: ' .. raw)
 assert(optim.score({[raw]=15}, {[canonical]={perUnit=2}}) == 30,
  'old stat table must still score: ' .. raw)
 checked = checked + 1
end
assert(optim.score(r.Stats, {EnfeeblingMagicSkill={perUnit=2,cap=10}}) == 20)
assert(optim.score({EvasionSkill=5}, {Evasion={perUnit=2}}) == 0,
 'evasion skill must not be conflated with evasion')
assert(sd.canon('EVASION') == 'EvasionSkill' and sd.canon('evasion') == 'Evasion')
assert(optim.score({Evasion=7,EvasionSkill=5}, {evasion={perUnit=2}}) == 14)
assert(optim.score({Evasion=7,EvasionSkill=5}, {EVASION={perUnit=2}}) == 10)
assert(optim.score({WindInstrumentSkill=5}, {WindResistance={perUnit=2}}) == 0,
 'wind instrument skill must not be conflated with elemental resistance')
print('OK -- ' .. checked .. ' modifier aliases, catalog vocabulary, display and scoring')
