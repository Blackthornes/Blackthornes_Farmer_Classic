-- Map markers where herbs and ore were gathered.
--
-- What matters: a gather marks the exact spot, on the map it was on; the same
-- node gathered again is the same marker, not a second one; the saved list
-- cannot grow for ever; an unreadable position marks nothing but the gather
-- still counts; the minimap places markers the right way round, turning with
-- you when it turns and leaving off what is past its edge; the world map shows
-- only the map it is on, at a size that ignores zoom; each map has a switch
-- that the settings page and /farm markers share; clearing needs a confirm and
-- leaves the gathering record alone; and the hover says what and when.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("markers")

local clock, wall = 500, 1000000

local ns = env.Load({ ui = true })
local Gathering, MapMarkers = ns.Gathering, ns.MapMarkers

_G.GetTime = function() return clock end
_G.time = function() return wall end

-- Elwynn-sized: 3000 yards across, 2000 down.
_G.C_Map.GetMapWorldSize = function(mapID)
    if mapID == 21 or mapID == 37 then return 3000, 2000 end
    return nil
end

-- 200 yards from the middle of the minimap to its rim.
_G.Minimap.GetViewRadius = function() return 200 end

local cvars = { rotateMinimap = "0" }
_G.GetCVar = function(name) return cvars[name] end
local facing = 0
_G.GetPlayerFacing = function() return facing end

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

suite.check("markers are on by default on both maps",
    MapMarkers.WorldOn() and MapMarkers.MinimapOn())

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

local PEACEBLOOM = { { name = "Peacebloom", id = 2447 } }
local COPPER = { { name = "Copper Ore", id = 2770 } }

env.world.target = nil
env.world.zone, env.world.subZone = "Elwynn Forest", "Goldshire"
env.world.mapID = 37
env.world.position = { 0.45, 0.68 }

--------------------------------------------------------------------------------
-- Recording the spot
--------------------------------------------------------------------------------

Gather(HERB_GATHERING, "Peacebloom", PEACEBLOOM)

local spots = Gathering:Spots()
suite.check("a gather marks one spot", #spots == 1, #spots)
suite.check("on the map you were on", spots[1].map == 37, spots[1].map)
suite.check("as fractions of that map", spots[1].x == 0.45 and spots[1].y == 0.68)
suite.check("named for the node", spots[1].node == "Peacebloom")
suite.check("a herb", spots[1].kind == "herb")
suite.check("with when", spots[1].last == wall and spots[1].first == wall)
suite.check("and what it gave", spots[1].items and spots[1].items.Peacebloom == 1)
suite.check("the node record still has its percent coordinates",
    Gathering:Summary(Gathering.NodeKey("Elwynn Forest", "Goldshire", "Peacebloom"))
        .node.coords[1] == 45)

-- Back to the same herb once it respawns, a step to one side.
wall = wall + 600
env.world.position = { 0.4505, 0.6803 }
Gather(HERB_GATHERING, "Peacebloom", PEACEBLOOM)
suite.check("the same node again is the same marker", #Gathering:Spots() == 1, #Gathering:Spots())
suite.check("counted twice", spots[1].gathers == 2, spots[1].gathers)
suite.check("last gathered moves on", spots[1].last == wall)
suite.check("first gathered does not", spots[1].first == wall - 600)

-- A different node in the same place is its own marker.
Gather(MINING, "Copper Vein", COPPER)
suite.check("a vein beside it is a second marker", #Gathering:Spots() == 2)
suite.check("an ore", Gathering:Spots()[2].kind == "ore")

-- The same kind of herb across the field is another.
env.world.position = { 0.47, 0.68 }
Gather(HERB_GATHERING, "Peacebloom", PEACEBLOOM)
suite.check("the same herb 60 yards off is its own marker", #Gathering:Spots() == 3)

-- Somewhere the client will not say where you are.
env.world.position = { env.Secret("x"), env.Secret("y") }
local before = Gathering:Summary(Gathering.NodeKey("Elwynn Forest", "Goldshire", "Peacebloom")).gathers
Gather(HERB_GATHERING, "Peacebloom", PEACEBLOOM)
suite.check("an unreadable position marks nothing", #Gathering:Spots() == 3)
suite.check("but the gather still counts",
    Gathering:Summary(Gathering.NodeKey("Elwynn Forest", "Goldshire", "Peacebloom")).gathers
        == before + 1)

env.world.mapID = nil
Gather(HERB_GATHERING, "Peacebloom", PEACEBLOOM)
suite.check("no map, no marker", #Gathering:Spots() == 3)

env.world.mapID = 37
env.world.position = { 0.45, 0.68 }

--------------------------------------------------------------------------------
-- The minimap
--------------------------------------------------------------------------------

local function Shown(pool)
    local shown = {}
    for _, pin in ipairs(pool and pool.pins or {}) do
        if pin:IsShown() then shown[#shown + 1] = pin end
    end
    return shown
end

local function PinFor(pool, node)
    for _, pin in ipairs(Shown(pool)) do
        if pin.spot.node == node then return pin end
    end
end

local function Near(a, b) return math.abs(a - b) < 0.01 end

-- Just the one test vein: 100 yards east of you.
Gathering:ClearSpots()
Gathering:AddSpot(37, 0.45 + 100 / 3000, 0.68, "Copper Vein", "ore")
MapMarkers:DrawMinimap()

local vein = PinFor(MapMarkers.minimapPool, "Copper Vein")
suite.check("a spot in range is on the minimap", vein ~= nil)
local p = vein._point
suite.check("anchored to the minimap's centre", p[2] == Minimap and p[3] == "CENTER")
-- 100 of 200 yards is half way to the rim of a 140-pixel minimap: 35 pixels.
suite.check("east is to the right", Near(p[4], 35) and Near(p[5], 0), ("%s, %s"):format(p[4], p[5]))

-- North is up: map y runs down.
Gathering:AddSpot(37, 0.45, 0.68 - 50 / 2000, "Silverleaf", "herb")
MapMarkers:DrawMinimap()
p = PinFor(MapMarkers.minimapPool, "Silverleaf")._point
suite.check("north is up", Near(p[4], 0) and Near(p[5], 17.5), ("%s, %s"):format(p[4], p[5]))

-- A turning minimap, facing west: east is behind you, so down.
cvars.rotateMinimap = "1"
facing = math.pi / 2
MapMarkers:DrawMinimap()
p = PinFor(MapMarkers.minimapPool, "Copper Vein")._point
suite.check("a turning minimap turns the markers", Near(p[4], 0) and Near(p[5], -35),
    ("%s, %s"):format(p[4], p[5]))
cvars.rotateMinimap = "0"
facing = 0

-- Past the rim.
Gathering:AddSpot(37, 0.45 + 300 / 3000, 0.68, "Tin Vein", "ore")
MapMarkers:DrawMinimap()
suite.check("a spot past the rim is left off", PinFor(MapMarkers.minimapPool, "Tin Vein") == nil)
suite.check("the others stay", #Shown(MapMarkers.minimapPool) == 2)

-- On another map.
Gathering:AddSpot(21, 0.45, 0.68, "Briarthorn", "herb")
MapMarkers:DrawMinimap()
suite.check("a spot on another map is not on this one",
    PinFor(MapMarkers.minimapPool, "Briarthorn") == nil)

-- Markers are reused, not hidden and shown, so a hovered one keeps its tooltip.
local first = PinFor(MapMarkers.minimapPool, "Copper Vein")
MapMarkers:DrawMinimap()
suite.check("a redraw reuses the same marker", PinFor(MapMarkers.minimapPool, "Copper Vein") == first)

-- Standing still, a second passing only moves the age fade: the markers are
-- not gathered up and placed again (that was a once-a-second hitch).
do
    local placed = 0
    local real = MapMarkers.PlaceMinimap
    MapMarkers.PlaceMinimap = function(...) placed = placed + 1; return real(...) end
    local alpha
    first.SetAlpha = function(_, value) alpha = value end
    wall = wall + 3600
    MapMarkers:DrawMinimap()
    MapMarkers.PlaceMinimap = real
    suite.check("a second passing standing still places nothing again", placed == 0, placed)
    suite.check("but the age fade still moves",
        alpha ~= nil and alpha == MapMarkers.AlphaFor(first.spot.last, wall), alpha)
    first.SetAlpha = nil
    wall = wall - 3600
    MapMarkers:Refresh()
end

-- Somewhere with no readable position: nothing on the minimap.
env.world.position = nil
MapMarkers:DrawMinimap()
suite.check("no position, no minimap markers", #Shown(MapMarkers.minimapPool) == 0)
env.world.position = { 0.45, 0.68 }

-- The step driver keeps it current.
MapMarkers:Step(1)
suite.check("the driver draws the minimap", #Shown(MapMarkers.minimapPool) == 2)

-- A herb that has grown back is a blip the minimap draws on its own map, and
-- addon frames are drawn over that map. So a minimap marker must leave the
-- middle clear for the blip: an empty frame, no icon and no fill.
local framePin = Shown(MapMarkers.minimapPool)[1]
suite.check("a minimap marker is hollow", framePin.hollow == true and rawget(framePin, "icon") == nil
    and rawget(framePin, "ring") == nil)
suite.check("drawn as corner brackets", #framePin.corners == 8)
suite.check("sitting just above the minimap and the heat glow, under anything else on it",
    rawget(framePin, "_frameLevel") == Minimap:GetFrameLevel() + MapMarkers.MINIMAP_ABOVE, rawget(framePin, "_frameLevel"))

--------------------------------------------------------------------------------
-- The world map
--------------------------------------------------------------------------------

local canvas = env.Stub({ _width = 1000, _height = 667 })
local shownMap = 37

_G.WorldMapFrame = env.Stub({ _shown = true })
WorldMapFrame.GetCanvas = function() return canvas end
WorldMapFrame.GetMapID = function() return shownMap end
WorldMapFrame.ScrollContainer = { GetCanvasScale = function() return 2 end }

MapMarkers:Refresh()
local world = MapMarkers.worldPool

suite.check("the world map shows this map's spots", #Shown(world) == 3, #Shown(world))
local silver = PinFor(world, "Silverleaf")
p = silver._point
suite.check("placed on the canvas from its top left", p[2] == canvas and p[3] == "TOPLEFT")
suite.check("low among the map's pins, over the heat glow, so anything else draws over it",
    rawget(silver, "_frameLevel") == canvas:GetFrameLevel() + MapMarkers.WORLD_ABOVE, rawget(silver, "_frameLevel"))
-- Zoomed in 2x, so the marker is drawn at half scale and placed in its own units.
suite.check("at the spot, whatever the zoom",
    Near(p[4], 0.45 * 1000 * 2) and Near(p[5], -(0.68 - 50 / 2000) * 667 * 2),
    ("%s, %s"):format(p[4], p[5]))

shownMap = 21
MapMarkers:Step(1)
suite.check("another map shows only its own", #Shown(world) == 1
    and PinFor(world, "Briarthorn") ~= nil)

WorldMapFrame._shown = false
MapMarkers:Step(1)
suite.check("a closed map shows nothing", #Shown(world) == 0)
-- Put away once: the driver asks ten times a second while the map is closed.
local hides = 0
for _, pin in ipairs(world.pins) do
    local realHide = pin.Hide
    pin.Hide = function(self) hides = hides + 1; return realHide(self) end
end
MapMarkers:Step(1)
MapMarkers:Step(1)
suite.check("and pins already put away are left alone", hides == 0, hides)
WorldMapFrame._shown = true
shownMap = 37
MapMarkers:Step(1)

--------------------------------------------------------------------------------
-- Hovering
--------------------------------------------------------------------------------

-- A minimap marker hovers on its check only; a world one on all of it.
local function Hover(pin)
    local target = rawget(pin, "hit") or pin
    target:GetScript("OnEnter")(target)
end

suite.check("a minimap marker leaves its middle to the minimap",
    rawget(framePin, "hit") ~= nil and framePin:GetScript("OnEnter") == nil)

wall = wall + 12 * 60
GameTooltip._lines = {}
Hover(silver)
suite.check("the hover names the node", GameTooltip._lines[1] == "Silverleaf", GameTooltip._lines[1])
suite.check("and when", GameTooltip._lines[2] == "Gathered, last 12 min ago", GameTooltip._lines[2])
suite.check("and that its grow-back time is still being learned",
    GameTooltip._lines[3] == "Grows back: ?  (learning, 0 of 3 returns)", GameTooltip._lines[3])
suite.check("and nothing more", GameTooltip._lines[4] == nil, GameTooltip._lines[4])

Gathering:AddSpot(37, 0.45, 0.68 - 50 / 2000, "Silverleaf", "herb")
GameTooltip._lines = {}
Hover(silver)
suite.check("a node taken twice says so", GameTooltip._lines[2] == "Gathered 2 times, last just now",
    GameTooltip._lines[2])

suite.check("ago: minutes", MapMarkers.Ago(0, 125) == "2 min ago")
suite.check("ago: hours", MapMarkers.Ago(0, 3 * 3600 + 5) == "3 h ago")
suite.check("ago: yesterday", MapMarkers.Ago(0, 86400 + 5) == "yesterday")
suite.check("ago: days", MapMarkers.Ago(0, 3 * 86400) == "3 days ago")
suite.check("ago: unknown", MapMarkers.Ago(nil, 5) == nil)

suite.check("a fresh gather is drawn strongest",
    MapMarkers.AlphaFor(100, 100) > MapMarkers.AlphaFor(100, 100 + MapMarkers.OLD))
suite.check("fading on the way", MapMarkers.AlphaFor(0, MapMarkers.FRESH + 60) < MapMarkers.AlphaFor(0, 0)
    and MapMarkers.AlphaFor(0, MapMarkers.FRESH + 60) > MapMarkers.AlphaFor(0, MapMarkers.OLD))

--------------------------------------------------------------------------------
-- What the marker shows
--------------------------------------------------------------------------------

local function SpotOf(node)
    for _, spot in ipairs(Gathering:Spots()) do
        if spot.node == node then return spot end
    end
end


_G.GetItemIcon = function(id) return 100000 + id end
suite.check("the marker shows the item you got there",
    MapMarkers:IconFor({ node = "Peacebloom", kind = "herb", items = { Peacebloom = 2 } }) == 102447)
suite.check("a spot saved before keeping it finds the item by its node's name",
    MapMarkers:IconFor({ node = "Peacebloom", kind = "herb" }) == 102447)
suite.check("a node nothing is known about keeps the plain herb",
    MapMarkers:IconFor({ node = "Nothing Known", kind = "herb" }) == MapMarkers.ICONS.herb)
suite.check("and a school the plain fish",
    MapMarkers:IconFor({ node = "Nothing Known", kind = "fish" }) == MapMarkers.ICONS.fish)
_G.GetItemIcon = nil

MapMarkers:Refresh()
silver = PinFor(world, "Silverleaf")
suite.check("while its grow-back time is learned, the marker stays grey",
    silver.back == false and type(silver.backAt) ~= "number")

for _ = 1, ns.Respawn.MIN_RETURNS do ns.Respawn:Learn(37, "Silverleaf", 300) end
Gathering:AddSpot(37, 0.45, 0.68 - 50 / 2000, "Silverleaf", "herb", { "Silverleaf" })
MapMarkers:Step(1)
silver = PinFor(world, "Silverleaf")
suite.check("just taken, it is grey until it should be back",
    silver.back == false and silver.backAt == wall + 300, silver.backAt)

local placed, alpha = 0, nil
local realPoint, realAlpha = silver.SetPoint, silver.SetAlpha
silver.SetPoint = function(self, ...) placed = placed + 1; return realPoint(self, ...) end
silver.SetAlpha = function(self, value) alpha = value; return realAlpha(self, value) end
wall = wall + 301
MapMarkers:Step(1)
suite.check("once the timer says it's back, it colors in", silver.back == true)
suite.check("at full strength", alpha and Near(alpha, MapMarkers.FRESH_ALPHA), alpha)
suite.check("without placing the markers again", placed == 0, placed)
silver.SetPoint, silver.SetAlpha = realPoint, realAlpha

-- A cast into a school you moused over.
local OILY = { { name = "Oily Blackmouth", id = 6358 } }
ns.Fishing.cast = { school = "Oily Blackmouth School" }
env.world.fishing = true
env.world.loot = OILY
fire(ns.eventFrame, "LOOT_OPENED")
fire(ns.eventFrame, "LOOT_CLOSED")
env.world.fishing = false

local school = SpotOf("Oily Blackmouth School")
suite.check("a catch from a school marks the spot", school ~= nil and school.kind == "fish")
suite.check("with the fish it gave", school and school.items["Oily Blackmouth"] == 1)
suite.check("a school never teaches a grow-back time",
    ns.Respawn:Estimate(37, "Oily Blackmouth School").returns == 0)

MapMarkers:Refresh()
local pool = PinFor(world, "Oily Blackmouth School")
suite.check("a school shows on the world map, in full color", pool ~= nil and pool.back == true)
GameTooltip._lines = {}
Hover(pool)
suite.check("its hover lists the fish", GameTooltip._lines[2] == "Oily Blackmouth x1", GameTooltip._lines[2])
suite.check("and says it was fished", GameTooltip._lines[3] == "Fished, last just now",
    GameTooltip._lines[3])
suite.check("and nothing about growing back", GameTooltip._lines[4] == nil, GameTooltip._lines[4])
MapMarkers:Step(1)

--------------------------------------------------------------------------------
-- Switches
--------------------------------------------------------------------------------

ns.HandleSlash("markers minimap off")
suite.check("/farm markers minimap off", ns.db.markersMinimap == false and ns.db.markersWorld)
suite.check("takes them off the minimap at once", #Shown(MapMarkers.minimapPool) == 0)
suite.check("and leaves the world map", #Shown(world) == 4)

ns.HandleSlash("markers map off")
suite.check("/farm markers map off", ns.db.markersWorld == false)
suite.check("takes them off the world map", #Shown(world) == 0)

ns.HandleSlash("markers on")
suite.check("/farm markers on turns both on", ns.db.markersWorld and ns.db.markersMinimap)
suite.check("and they come back", #Shown(world) == 4 and #Shown(MapMarkers.minimapPool) == 3,
    #Shown(MapMarkers.minimapPool))

ns.HandleSlash("markers off")
suite.check("/farm markers off turns both off", not ns.db.markersWorld and not ns.db.markersMinimap)

-- The settings page is the same switch.
ns.SettingsUI:Show()
local controls = ns.SettingsUI.controls
suite.check("the page shows them off", not controls.markersWorld:GetChecked()
    and not controls.markersMinimap:GetChecked())
controls.markersWorld:GetScript("OnClick")(controls.markersWorld)
suite.check("ticking World map turns it on", ns.db.markersWorld == true)
controls.markersMinimap:GetScript("OnClick")(controls.markersMinimap)
suite.check("ticking Minimap turns it on", ns.db.markersMinimap == true)
ns.SettingsUI:Hide()

--------------------------------------------------------------------------------
-- Clearing, and the cap
--------------------------------------------------------------------------------

local marked = #Gathering:Spots()
local gathers = Gathering:CountGathers()

ns.HandleSlash("markers clear")
suite.check("clear alone deletes nothing", #Gathering:Spots() == marked)

ns.HandleSlash("markers clear confirm")
suite.check("clear confirm removes the markers", #Gathering:Spots() == 0)
suite.check("but not the gathering record", Gathering:CountGathers() == gathers)
suite.check("and the maps empty at once", #Shown(world) == 0)

for index = 1, Gathering.MAX_SPOTS + 1 do
    wall = wall + 1
    Gathering:AddSpot(99, (index % 50) / 50, math.floor(index / 50) / 50, "Herb " .. index, "herb")
end
suite.check("the saved list stops at its cap", #Gathering:Spots() == Gathering.MAX_SPOTS)
suite.check("dropping the oldest", Gathering:Spots()[1].node == "Herb 2", Gathering:Spots()[1].node)

suite.done()
