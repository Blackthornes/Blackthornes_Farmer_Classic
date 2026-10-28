-- The arrow's way there (Logic/Travel.lua, UI/TravelCard.lua,
-- UI/TravelMap.lua).
--
-- What matters: it is off until ticked; across the sea it takes the
-- quickest way the character can (a flight it knows, then the boat of its
-- side, then a walk), never a flight it has not learned or the other side's
-- boat; the steps read as players say them and their numbers hold as you
-- go, the ones behind you kept for the card; on a flight the plan stays as
-- it is; Stop ends the trip for that place only; a walk through other zones
-- aims at the spot you crossed before; and the card and the map line follow
-- the steps still ahead.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("travel")

local clock = 100
local ns = env.Load({ ui = true })
local Travel, TravelCard, TravelMap = ns.Travel, ns.TravelCard, ns.TravelMap

_G.GetTime = function() return clock end
local faction = "Alliance"
_G.UnitFactionGroup = function() return faction end
local onTaxi = false
_G.UnitOnTaxi = function() return onTaxi end
_G.InCombatLockdown = function() return false end

local printed = {}
local print = ns.Print
ns.Print = function(text, ...) printed[#printed + 1] = tostring(text) return print(text, ...) end

-- The shipped docks: every boat and zeppelin leaves from a dock that is
-- there, and Orgrimmar's two zeppelins from their own platforms on the
-- one tower (the Undercity one was a road sign out by Razor Hill).
local shipped = Travel.DATA
for _, ride in ipairs(shipped.rides) do
    suite.check("the " .. ride[1] .. " to " .. ride[2] .. " ride has both docks",
        shipped.docks[ride[1]] ~= nil and shipped.docks[ride[2]] ~= nil)
end
local toUndercity, toGromgol = shipped.docks.orgrimmar, shipped.docks.orgrimmargromgol
local apart = math.sqrt((toUndercity[3] - toGromgol[3]) ^ 2 + (toUndercity[4] - toGromgol[4]) ^ 2)
suite.check("Orgrimmar's zeppelins leave from one tower", apart > 5 and apart < 50, apart)
suite.check("not from the road sign", math.abs(toUndercity[4] - -4397.8) > 200, toUndercity[4])
suite.check("Undercity's zeppelin leaves from its tower, not the sign below",
    math.abs(shipped.docks.undercity[3] - 1981.6) > 50, shipped.docks.undercity[3])

-- Every shipped flight carries how far it really goes, from its points in
-- the tables, never shorter than the straight line between its ends.
local shippedPaths, shippedLengths = shipped.paths, shipped.lengths or {}
suite.check("a length for every flight", #shippedLengths * 2 == #shippedPaths, #shippedLengths)
local short
for index = 1, #shippedPaths - 1, 2 do
    local a, b = shipped.flights[shippedPaths[index]], shipped.flights[shippedPaths[index + 1]]
    local line = math.sqrt((a[4] - b[4]) ^ 2 + (a[5] - b[5]) ^ 2)
    if (shippedLengths[(index + 1) / 2] or 0) < line then short = shippedPaths[index] .. "-" .. shippedPaths[index + 1] end
end
suite.check("none shorter than a straight line", short == nil, short)

-- A small world: Stormwind and Menethil on one side of the sea, Theramore
-- on the other.
local DATA = Travel.DATA
DATA.flights = {
    [1] = { "Stormwind, Elwynn", "A", 0, 0, -200, "Elwynn" },
    [2] = { "Menethil Harbor, Wetlands", "A", 0, 3000, 1000, "Wetlands" },
    [3] = { "Booty Bay, Stranglethorn", "H", 0, -3000, 500, "Stranglethorn" },
}
DATA.paths = { 1, 2, 2, 1, 2, 3 }
DATA.docks = {
    menethil = { "Menethil Harbor", 0, 3050, 1000, "Wetlands" },
    theramore = { "Theramore", 1, -3000, -3000, "Dustwallow Marsh" },
}
DATA.rides = { { "menethil", "theramore", "boat", "A" } }
DATA.lengths = nil

local guessStops = Travel:Stops("A", { [1] = true, [2] = true })
local guessed = Travel:Rides(guessStops, "A")["f1"][1].cost
DATA.lengths = { 9600 }
local flown = Travel:Rides(guessStops, "A")["f1"][1].cost
suite.check("a flight's real length sets its time", flown == 9600 / Travel.FLIGHT_SPEED and flown ~= guessed, flown)
DATA.lengths = { 0 }
suite.check("an unknown length falls back to a guess", Travel:Rides(guessStops, "A")["f1"][1].cost == guessed)
DATA.lengths = nil

local start = { continent = 0, north = 0, west = 0, zone = "Elwynn Forest" }
local goal = { continent = 1, north = -3200, west = -3000, zone = "Dustwallow Marsh", name = "Mirefin camp" }

--------------------------------------------------------------------------------
-- The quickest way
--------------------------------------------------------------------------------

local legs, cost = Travel:Search(start, goal, "A", { [1] = true, [2] = true })
local steps = Travel.Steps(legs)
suite.check("across the sea there is a way", legs ~= nil and cost > 0)
suite.check("fly, boat, then walk", #steps == 3 and steps[1].kind == "fly" and steps[2].kind == "boat"
    and steps[3].kind == "walk", #steps)
suite.check("the flight goes to Menethil", steps[1].to.name == "Menethil Harbor")

local walked = Travel.Steps((Travel:Search(start, goal, "A", {})))
suite.check("no flight learned: walk to the dock, then the boat",
    #walked == 2 and walked[1].kind == "boat", #walked)
local slower = select(2, Travel:Search(start, goal, "A", {}))
suite.check("and that takes longer", slower > cost)

suite.check("the other side's boat is never taken", Travel:Search(start, goal, "H", { [1] = true }) == nil)
suite.check("nor the other side's flight master",
    not Travel:Stops("A", { [3] = true })["f3"])

local hearth = { continent = 1, north = -3100, west = -3000, zone = "Dustwallow Marsh", name = "Theramore" }
local quick = Travel.Steps((Travel:Search(start, goal, "A", { [1] = true, [2] = true }, hearth)))
suite.check("a Hearthstone landing near the place wins", quick[1].kind == "hearth" and #quick == 2)

--------------------------------------------------------------------------------
-- The words
--------------------------------------------------------------------------------

suite.check("flight masters by their short name", Travel.ShortName("Stormwind, Elwynn") == "Stormwind")
local line, small = Travel.StepWords(steps[1])
suite.check("a flight", line == "Fly to Menethil Harbor" and small == "Talk to the flight master", line)
line, small = Travel.StepWords(steps[2], true)
suite.check("on the dock", line == "Wait here for the boat to Theramore" and small == "Get on when it stops", line)
line = Travel.StepWords(quick[1])
suite.check("the Hearthstone", line == "Use your Hearthstone")

--------------------------------------------------------------------------------
-- A trip as you go
--------------------------------------------------------------------------------

Travel.WorldOf = function(_, target) return target.place end
local target = { name = "Mirefin camp", zone = "Dustwallow Marsh", place = goal }
ns.db.travelFlights = { [UnitGUID("player")] = { [1] = true, [2] = true } }

ns.db.arrowRoute = nil
suite.check("on when never set", Travel.IsOn())
ns.db.arrowRoute = false
suite.check("off once unticked", Travel:Use(target, start, clock) == nil and not Travel.IsOn())
ns.db.arrowRoute = true

local trip = Travel:Use(target, start, clock)
suite.check("step 1 of 3", trip and trip.index == 1 and trip.count == 3, trip and trip.count)
suite.check("the arrow aims at the flight master", trip.north == 0 and trip.west == -200)

clock = clock + 1
local dock = { continent = 0, north = 3040, west = 1000, zone = "Wetlands" }
Travel.due = true
trip = Travel:Use(target, dock, clock)
suite.check("landed: step 2 of 3", trip.index == 2 and trip.count == 3, trip.index .. "/" .. trip.count)
suite.check("the flight is behind you", #trip.plan.behind == 1 and trip.plan.behind[1].kind == "fly")
suite.check("standing on the dock", trip.atStop and trip.line == "Wait here for the boat to Theramore", trip.line)
suite.check("chat says what's next", printed[#printed] and printed[#printed]:find("Theramore") ~= nil,
    printed[#printed])

local rows = TravelCard.Rows(trip.plan)
suite.check("the card: done, now, then the rest", #rows == 3 and rows[1].done and rows[2].now
    and not rows[3].now, #rows)
suite.check("numbered from the start", rows[1].title:find("^1%. ") and rows[2].title:find("^2%. "))
suite.check("about how long", TravelCard.TimeText(trip.plan):find("minute") ~= nil)

-- The card's close gem puts only the card away; the trip goes on.
TravelCard:Update({ trip = trip })
TravelCard:Close()
suite.check("closing the card keeps the trip", Travel.stopped == nil and Travel.plan ~= nil)
TravelCard:Update({ trip = trip })
suite.check("and the card stays closed for this place", TravelCard.closedKey == trip.plan.key
    and TravelCard.frame and not TravelCard.frame:IsShown())
TravelCard:Update({ trip = { plan = { key = "elsewhere", steps = trip.plan.steps, done = 0 } } })
suite.check("a new place brings it back", TravelCard.closedKey == nil and TravelCard.frame:IsShown())
TravelCard:Hide()

local mapLegs = TravelMap.Legs(trip.plan, dock)
suite.check("the map line: to the boat, the boat, the walk",
    #mapLegs == 3 and mapLegs[2].kind == "boat" and mapLegs[3].kind == "walk", #mapLegs)
suite.check("a boat is dashed", #TravelMap.Pieces("boat", 0, 0, 1, 0) > 5)
suite.check("a walk is one line", #TravelMap.Pieces("walk", 0, 0, 1, 0) == 1)

-- On the boat: the plan holds, whatever is due.
onTaxi = true
clock = clock + 100
Travel.due = true
local held = Travel:Use(target, { continent = 0, north = 0, west = 0, zone = "Wetlands" }, clock)
suite.check("on a ride the plan stays", held.index == 2 and held.plan == trip.plan)
onTaxi = false

--------------------------------------------------------------------------------
-- Stop
--------------------------------------------------------------------------------

Travel:StopTrip()
suite.check("Stop ends the trip", Travel:Use(target, dock, clock) == nil)
local other = { name = "Mudrock camp", zone = "Dustwallow Marsh", place = goal }
suite.check("a new place has a trip again", Travel:Use(other, dock, clock) ~= nil)

--------------------------------------------------------------------------------
-- Walking through other zones
--------------------------------------------------------------------------------

suite.check("next door is no trip", not Travel.WorthATrip(start,
    { continent = 0, north = -100, west = 0, zone = "Duskwood" }))
suite.check("two zones over is", Travel.WorthATrip(start,
    { continent = 0, north = -3000, west = 0, zone = "Stranglethorn Vale" }))

Travel:NoteCrossing("Elwynn Forest", "Duskwood", { continent = 0, north = -900, west = 40 })
local _, north, west, toward = Travel:Toward(start,
    { continent = 0, north = -3000, west = 0, zone = "Stranglethorn Vale" })
suite.check("aims at where you crossed before", north == -900 and west == 40 and toward == "Duskwood",
    tostring(north) .. "," .. tostring(toward))
Travel:NoteCrossing("Elwynn Forest", "Duskwood", { continent = 0, north = -1000, west = 40 })
suite.check("and keeps the average of the walks", ns.db.travelCrossings["Elwynn Forest|Duskwood"][2] == -950)
Travel:NoteCrossing("Elwynn Forest", "Tanaris", { continent = 0, north = 0, west = 0 })
suite.check("zones that don't touch keep nothing", ns.db.travelCrossings["Elwynn Forest|Tanaris"] == nil)

--------------------------------------------------------------------------------
-- The same file in every addon
--------------------------------------------------------------------------------

suite.check("a flight master's short zone is the zone", Travel.Defaults.ZoneOf("Elwynn") == "Elwynn Forest")
suite.check("a capital is the zone it sits in", Travel.Host.ZoneOf("Stormwind City") == "Elwynn Forest",
    tostring(Travel.Host.ZoneOf("Stormwind City")))

-- Another addon's copy learned a flight this one has not.
local otherDB = { travelFlights = { [UnitGUID("player")] = { [3] = true } } }
local otherCopy = setmetatable({ Host = { DB = function() return otherDB end } }, { __index = Travel })
_G.BlackthornesTravel.copies.Other = { version = 1, module = otherCopy }
suite.check("flights another addon learned count", Travel:AllFlights()[3] == true and Travel:AllFlights()[1] == true)
suite.check("but are kept in that addon's save", not ns.db.travelFlights[UnitGUID("player")][3])
otherDB.travelCrossings = { ["Westfall|Duskwood"] = { 0, -500, 900, 1 } }
suite.check("and where you crossed with it loaded", select(2, Travel:Crossing("Westfall", "Duskwood")) == -500)
_G.BlackthornesTravel.copies.Other = nil

-- Show the Way in an addon without a dial: the steps as lines and the
-- next stop to pin.
ns.TravelHost.Here = function() return start end
local mapPos = Travel.MapPos
Travel.MapPos = function(continent, north, west) return { map = 1429, x = 0.5, y = 0.5 } end
local guide = Travel:Guide(target)
suite.check("Guide gives the steps as lines", guide and #guide.lines == 3 and guide.lines[1] == "1. Fly to Menethil Harbor",
    guide and guide.lines[1])
suite.check("and the next stop to pin", guide.point and guide.point.map == 1429 and guide.point.name == "Fly to Menethil Harbor")
ns.db.arrowRoute = false
suite.check("Guide is off with the setting", Travel:Guide(target) == nil)
Travel.MapPos = mapPos

suite.done()
