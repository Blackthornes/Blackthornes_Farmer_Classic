-- The map gem: a gold gem on the world map that hides every Farmer mark at
-- once and brings back the ones that were on (a player asked, 2026-11-10).
--
-- What matters: a click turns off exactly the marks that were on and keeps
-- which; the next click puts back only those; with nothing kept it brings
-- back the camps and gathered nodes; it only flips the settings that were
-- already there, so Settings agrees; the menu ticks each; "Map Button:" and
-- /farm markers button hide and show the gem.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("maptoggle")
local check = suite.check

local ns = env.Load({ ui = true })
local MapToggle = ns.MapToggle

check("the module loads", type(MapToggle) == "table")
check("three kinds of mark", #MapToggle.Kinds() == 3)

-- Camps and nodes on, heat off (the usual).
ns.db.grindPins, ns.db.markersWorld, ns.db.heatWorld = nil, nil, false
check("something shows at first", MapToggle.AnyOn())

MapToggle:Toggle()
check("a click hides them all", not MapToggle.AnyOn())
check("camps saved off", ns.db.grindPins == false)
check("nodes saved off", ns.db.markersWorld == false)
check("keeps which were on", ns.db.mapMarksKept.grindPins and ns.db.mapMarksKept.markersWorld
    and not ns.db.mapMarksKept.heatWorld)

MapToggle:Toggle()
check("the next click brings camps back", ns.GrindPins.IsOn())
check("and nodes", ns.MapMarkers.WorldOn())
check("but not the heat that was off", not ns.Heat.WorldOn())

-- Only the heat on: a click and back brings only the heat.
ns.GrindPins:SetOn(false)
ns.MapMarkers:SetWorld(false)
ns.Heat:SetWorld(true)
MapToggle:Toggle()
check("heat hidden", not ns.Heat.WorldOn())
MapToggle:Toggle()
check("heat back", ns.Heat.WorldOn())
check("camps stay off", not ns.GrindPins.IsOn())
check("nodes stay off", not ns.MapMarkers.WorldOn())

-- Nothing kept: the usual two come back.
ns.Heat:SetWorld(false)
ns.db.mapMarksKept = nil
MapToggle:Toggle()
check("nothing kept brings camps", ns.GrindPins.IsOn())
check("and nodes", ns.MapMarkers.WorldOn())
check("never the heat", not ns.Heat.WorldOn())

-- The menu.
local menu = MapToggle:Menu()
check("right-click opens the menu", menu ~= nil)
local first = menu and menu.lines[1]
check("the camps line is ticked", first and first.label:GetText():find("Grinding Camps") ~= nil
    and first.label:GetText():find("Check") ~= nil)
ns.RowMenu:Pick(first)
check("picking it turns camps off", not ns.GrindPins.IsOn())
check("the nodes are left alone", ns.MapMarkers.WorldOn())

-- The gem on a map.
local map = CreateFrame("Frame", nil, UIParent)
local gem = MapToggle:Build(map)
check("the gem is made", gem ~= nil and MapToggle.gem == gem)
check("built once", MapToggle:Build(map) == gem)
check("shows while the button is on", MapToggle.ButtonOn() and gem:IsShown())

ns.HandleSlash("markers button off")
check("/farm markers button off", ns.db.mapButton == false and not MapToggle.ButtonOn())
check("the gem hides", not gem:IsShown())
ns.HandleSlash("markers button on")
check("/farm markers button on", MapToggle.ButtonOn() and gem:IsShown())

MapToggle:SetButton(false)
check("SetButton saves it", ns.db.mapButton == false)
MapToggle:SetButton(true)

suite.done()
