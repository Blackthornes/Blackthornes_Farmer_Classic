-- The item icons on the gathering markers, fishing markers, and herbs or
-- veins that sit within a few meters of each other.
--
-- What matters: a spot keeps a count of what it gave; a world map marker
-- shows the icon of the item it gave most, else what that node gave anywhere,
-- else the plain herb or ore; it is grey until your own grow-back time says
-- the node is back, then in full color; the hover lists what the spot gave,
-- with icons and counts, above the lines it had; a cast into a school you
-- moused over marks the spot in full color in a blue ring, never teaching a
-- grow-back time; a cast with no school marks nothing; a herb or vein within
-- about 3 meters of a spot of its own kind joins it whatever its name, a herb
-- never joins a vein and fishing never joins; older saves with two that close
-- draw as one on the world map, and the save keeps both.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("mapicons")

local clock, wall = 500, 1000000

local ns = env.Load({ ui = true })
local Gathering, MapMarkers, Respawn = ns.Gathering, ns.MapMarkers, ns.Respawn

_G.GetTime = function() return clock end
_G.time = function() return wall end

-- 3000 yards across, 2000 down.
_G.C_Map.GetMapWorldSize = function(mapID)
    if mapID == 37 then return 3000, 2000 end
    return nil
end

local ICON = { [2447] = 133939, [2770] = 135232, [2771] = 135240, [6358] = 133888 }
_G.C_Item = _G.C_Item or {}
_G.C_Item.GetItemIconByID = function(id) return ICON[id] end

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local fire = ns.eventFrame:GetScript("OnEvent")
local HERB_GATHERING, MINING = 2366, 2575
local casts = 0

local function Gather(spell, node, items)
    casts = casts + 1
    local id = "Cast-" .. casts
    fire(ns.eventFrame, "UNIT_SPELLCAST_SENT", "player", node, id, spell)
    clock = clock + 2
    fire(ns.eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", id, spell)
    env.world.loot = items
    fire(ns.eventFrame, "LOOT_OPENED")
    fire(ns.eventFrame, "LOOT_CLOSED")
    clock = clock + 1
end

env.world.target = nil
env.world.zone, env.world.subZone = "Elwynn Forest", "Goldshire"
env.world.mapID = 37
env.world.position = { 0.45, 0.68 }

local COPPER = { { name = "Copper Ore", id = 2770, quantity = 2 }, { name = "Rough Stone", id = 2835 } }

--------------------------------------------------------------------------------
-- What a spot gave
--------------------------------------------------------------------------------

Gather(MINING, "Copper Vein", COPPER)
local spot = Gathering:Spots()[1]
suite.check("a spot keeps what it gave", type(spot.items) == "table"
    and spot.items["Copper Ore"] == 2 and spot.items["Rough Stone"] == 1)

local items = MapMarkers.SpotItems(spot)
suite.check("most first", items[1].name == "Copper Ore" and items[2].name == "Rough Stone")
suite.check("its icon is the game's icon for the item it gave most",
    MapMarkers:IconFor(spot) == 135232, MapMarkers:IconFor(spot))

-- A spot saved before spots kept items: what its node gave anywhere.
local old = Gathering:AddSpot(37, 0.2, 0.2, "Copper Vein", "ore")
suite.check("an older spot reads its node's record", MapMarkers:IconFor(old) == 135232)

-- Nothing known about it: the plain one.
local unknown = Gathering:AddSpot(37, 0.3, 0.3, "Odd Vein", "ore")
suite.check("no icon known keeps the plain ore", MapMarkers:IconFor(unknown) == MapMarkers.ICONS.ore)

--------------------------------------------------------------------------------
-- The world map: grey until it is back
--------------------------------------------------------------------------------

Gathering:ClearSpots()
Gather(MINING, "Copper Vein", COPPER)
spot = Gathering:Spots()[1]

local canvas = env.Stub({ _width = 1000, _height = 667 })
_G.WorldMapFrame = env.Stub({ _shown = true })
WorldMapFrame.GetCanvas = function() return canvas end
WorldMapFrame.GetMapID = function() return 37 end
WorldMapFrame.ScrollContainer = { GetCanvasScale = function() return 1 end }

MapMarkers:Refresh()
local pin = MapMarkers.worldPool and MapMarkers.worldPool.pins[1]
suite.check("the spot shows on the world map", pin ~= nil and pin.spot == spot)
local seen = {}
pin.icon.SetTexture = function(_, value) seen.texture = value end
pin.icon.SetDesaturated = function(_, value) seen.grey = value end
pin.ring.SetVertexColor = function(_, r, g, b) seen.ring = { r, g, b } end
MapMarkers.worldKey = nil
MapMarkers:Refresh()

local gold = { ns.Theme.Unpack("accent") }
local blue = { ns.Theme.Unpack("pool") }
local function Same(a, b) return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end

suite.check("the world marker shows the item's icon", seen.texture == 135232, seen.texture)
suite.check("grey while no grow-back time is known", seen.grey == true and pin.back == false)
suite.check("in a gold ring", Same(seen.ring, gold))

for _ = 1, Respawn.MIN_RETURNS do Respawn:Learn(37, "Copper Vein", 600) end
MapMarkers.worldKey = nil
MapMarkers:Refresh()
suite.check("still grey before that time is up", seen.grey == true and pin.backAt == spot.last + 600)

wall = wall + 601
MapMarkers:Step(1)
suite.check("in full color once it should be back, by itself", seen.grey == false and pin.back == true)

--------------------------------------------------------------------------------
-- The hover
--------------------------------------------------------------------------------

GameTooltip._lines = {}
pin:GetScript("OnEnter")(pin)
suite.check("the hover names the node", GameTooltip._lines[1] == "Copper Vein", GameTooltip._lines[1])
suite.check("then what it gave, with icons and counts",
    GameTooltip._lines[2] == "|T135232:14:14|t Copper Ore x2" and GameTooltip._lines[3] == "Rough Stone x1",
    GameTooltip._lines[2])
suite.check("then how often you gathered it",
    GameTooltip._lines[4] == "Gathered, last 10 min ago", GameTooltip._lines[4])

--------------------------------------------------------------------------------
-- Within 3 meters
--------------------------------------------------------------------------------

-- 2 yards over, Era grows Tin on the spot: the same place.
env.world.position = { 0.45 + 2 / 3000, 0.68 }
Gather(MINING, "Tin Vein", { { name = "Tin Ore", id = 2771 } })
suite.check("another vein 2 yards off joins the spot", #Gathering:Spots() == 1, #Gathering:Spots())
suite.check("which keeps its name", spot.node == "Copper Vein" and spot.gathers == 2)
suite.check("adds what it gave", spot.items["Tin Ore"] == 1)
suite.check("and notes the other", spot.also and spot.also["Tin Vein"] == true)
suite.check("which teaches nothing about the first one's time",
    Respawn:Estimate(37, "Copper Vein").returns == Respawn.MIN_RETURNS)
suite.check("and counts as gathered on this map", Respawn:Gathered(37, "Tin Vein"))

-- 6 yards over: its own.
env.world.position = { 0.45 + 6 / 3000, 0.68 }
Gather(MINING, "Tin Vein", { { name = "Tin Ore", id = 2771 } })
suite.check("one 6 yards off is its own spot", #Gathering:Spots() == 2)

-- A herb on the vein is never joined to it.
env.world.position = { 0.45, 0.68 }
Gather(HERB_GATHERING, "Peacebloom", { { name = "Peacebloom", id = 2447 } })
suite.check("a herb beside a vein is its own spot", #Gathering:Spots() == 3)

-- An older save with two veins that close: drawn as one, the newest.
local saved = Gathering:Spots()
saved[#saved + 1] = { map = 37, x = 0.45 + 1 / 3000, y = 0.68, node = "Old Vein", kind = "ore",
    gathers = 1, first = 1, last = 1 }
local joined = Gathering.Joined(Gathering:SpotsOn(37))
local count, oldShown = 0, false
for _, entry in ipairs(joined) do
    if entry.kind == "ore" then count = count + 1 end
    if entry.node == "Old Vein" then oldShown = true end
end
suite.check("older spots that close draw as one", count == 2 and not oldShown, count)
suite.check("and the save keeps both", #Gathering:Spots() == 4)
Gathering:SpotsChanged()
MapMarkers:Refresh()
local drawn = 0
for index = 1, MapMarkers.worldPool.used do
    if MapMarkers.worldPool.pins[index].spot.node == "Old Vein" then drawn = drawn + 1 end
end
suite.check("the world map leaves the older one out", drawn == 0)

--------------------------------------------------------------------------------
-- Fishing
--------------------------------------------------------------------------------

Gathering:ClearSpots()
env.world.position = { 0.5, 0.5 }
local function Catch(school, fish)
    ns.Fishing.cast = school and { school = school } or nil
    env.world.fishing = true
    env.world.loot = fish
    fire(ns.eventFrame, "LOOT_OPENED")
    fire(ns.eventFrame, "LOOT_CLOSED")
    env.world.fishing = false
end

local OILY = { { name = "Oily Blackmouth", id = 6358 } }
Catch(nil, OILY)
suite.check("a cast with no school marks nothing", #Gathering:Spots() == 0, #Gathering:Spots())

Catch("Oily Blackmouth School", OILY)
local fish = Gathering:Spots()[1]
suite.check("a catch from a school marks the spot", fish ~= nil and fish.kind == "fish" and fish.map == 37)
suite.check("with what it gave", fish and fish.items["Oily Blackmouth"] == 1)

wall = wall + 120
env.world.position = { 0.5 + 2 / 3000, 0.5 }
Catch("Oily Blackmouth School", OILY)
suite.check("the same school again is the same marker", #Gathering:Spots() == 1 and fish.gathers == 2)
suite.check("which teaches no grow-back time",
    Respawn:Estimate(37, "Oily Blackmouth School").returns == 0)
suite.check("nor counts as a node gathered here", not Respawn:Gathered(37, "Oily Blackmouth School"))

-- Another school a step away never joins it.
Catch("Floating Wreckage", { { name = "Raw Brilliant Smallfish", id = 6291 } })
suite.check("another school a step away is its own", #Gathering:Spots() == 2)
local together = Gathering.Joined(Gathering:SpotsOn(37))
suite.check("and both draw", #together == 2)

Gathering:ClearSpots()
Catch("Oily Blackmouth School", OILY)
Catch("Oily Blackmouth School", OILY)
MapMarkers:Refresh()
local fishPin = MapMarkers.worldPool.pins[1]
suite.check("a school is in full color", fishPin.back == true and fishPin.spot.kind == "fish")
suite.check("at full strength", MapMarkers.PinAlpha(fishPin, wall) == MapMarkers.FRESH_ALPHA)
wall = wall + 99999
MapMarkers:Step(1)
suite.check("and stays so", fishPin.back == true
    and MapMarkers.PinAlpha(fishPin, wall) == MapMarkers.FRESH_ALPHA)

GameTooltip._lines = {}
fishPin:GetScript("OnEnter")(fishPin)
suite.check("its hover lists the fish", GameTooltip._lines[2] == "|T133888:14:14|t Oily Blackmouth x2",
    GameTooltip._lines[2])
suite.check("and how often you fished there",
    tostring(GameTooltip._lines[3]):find("^Fished 2 times, last") ~= nil, GameTooltip._lines[3])
suite.check("and nothing about growing back", GameTooltip._lines[4] == nil, GameTooltip._lines[4])

local once = { map = 37, x = 0.1, y = 0.1, node = "Oily Blackmouth School", kind = "fish", gathers = 1, last = wall }
fishPin.spot = once
GameTooltip._lines = {}
fishPin:GetScript("OnEnter")(fishPin)
suite.check("a school saved without its catch lists what that school gave you",
    GameTooltip._lines[2] == "|T133888:14:14|t Oily Blackmouth x4", GameTooltip._lines[2])
suite.check("fished once reads Fished", tostring(GameTooltip._lines[3]):find("^Fished, last") ~= nil,
    GameTooltip._lines[3])

suite.done()
