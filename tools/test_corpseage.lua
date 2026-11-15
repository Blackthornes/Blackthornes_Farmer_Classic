-- Corpses opened this session are let go after half an hour, a few at a
-- time as new ones come in. Nothing saved is touched.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("corpseage")

local ns = env.Load()
local Util = ns.Util

-- The helper on its own.
local gone = {}
local aging = Util.NewAging(100, function(key) gone[key] = true end, 2)
aging:Add("a", 0)
aging:Add("b", 10)
aging:Add("c", 50)
suite.check("nothing goes while young", next(gone) == nil)
aging:Add("d", 105)
suite.check("the oldest goes past the age", gone.a == true)
suite.check("a younger one stays", gone.b == nil and gone.c == nil)
aging:Add("e", 500)
suite.check("a few a step, no more", gone.b and gone.c and not gone.d)
aging:Sweep(500)
suite.check("the next step takes the rest", gone.d == true and not gone.e)

local many = Util.NewAging(1, function() end, 4)
for i = 1, 400 do many:Add(i, i * 10) end
suite.check("the lists stay short", #many.keys < 100, #many.keys)

-- Harvest and Tracker.
local Harvest, Tracker = ns.Harvest, ns.Tracker
local saved = {}
for k, v in pairs(Harvest.records or {}) do saved[k] = v end

Harvest.opened["Creature-old"] = { items = {} }
Harvest:Aging():Add("Creature-old", 1000)
Harvest.shown["Creature-shown"] = true
Harvest:Aging():Add("Creature-shown", 1000)
Tracker.corpses["Creature-old"] = {}
Tracker:Aging():Add("Creature-old", 1000)
Tracker.areaLooted["Creature-area"] = true
Tracker:Aging():Add("Creature-area", 1000)

Harvest.opened["Creature-new"] = { items = {} }
Harvest:Aging():Add("Creature-new", 1000 + 31 * 60)
Tracker.corpses["Creature-new"] = {}
Tracker:Aging():Add("Creature-new", 1000 + 31 * 60)

suite.check("an opened corpse 31 minutes old goes", Harvest.opened["Creature-old"] == nil)
suite.check("so does one only shown", Harvest.shown["Creature-shown"] == nil)
suite.check("the kill's corpse goes", Tracker.corpses["Creature-old"] == nil)
suite.check("an area looted one goes", Tracker.areaLooted["Creature-area"] == nil)
suite.check("a fresh one stays", Harvest.opened["Creature-new"] ~= nil
    and Tracker.corpses["Creature-new"] ~= nil)

local same = true
for k, v in pairs(saved) do if Harvest.records[k] ~= v then same = false end end
suite.check("the saved records are untouched", same)

suite.done()
