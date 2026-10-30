-- The Grind tab's Fish view.
--
-- What matters: the spots you fished show up under their zone, pools apart
-- from open water; catch rates and what a cast is worth wait for MIN_CASTS
-- casts, and an hour's worth waits for MIN_SECONDS of timed fishing, saying
-- "Fish a while longer" until then; the time between two casts at one spot
-- counts only when it is under BREAK, so a walk away never does; a hidden
-- spot or item is left out; a click points the arrow where you fished; and
-- nothing but your own casts ever reaches any of it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("fishview")
local check = suite.check

local ns = env.Load({ ui = true, hideSkinning = true })
local Fishing, GrindGather, GrindingUI = ns.Fishing, ns.GrindGather, ns.GrindingUI
local Grinding, DB = ns.Grinding, ns.DB

-- No gathering skills, so the footer has nothing but the fishing skill.
ns.Spots.Skills = function() return nil end

-- Every fish is worth 4 copper, so a cast's worth is easy to check.
ns.Value.UnitPrice = function(_, id) if id then return 4, "auction" end end

local LAKE = Fishing.SpotKey("Elwynn Forest", "Crystal Lake", nil)
local POOL = Fishing.SpotKey("Elwynn Forest", "Crystal Lake",
    "Oily Blackmouth School")
local FAR = Fishing.SpotKey("Stranglethorn Vale", "The Riptide", nil)

--- Put casts into a spot's record straight, so the view has something to show.
local function Caught(key, zone, location, school, casts, items)
    local store = Fishing:Store()
    local spot = { zone = zone, location = location, school = school,
        casts = casts, items = {}, coords = { x = 42.5, y = 61.2 },
        minSkill = 50, maxSkill = 80 }
    for name, each in pairs(items) do
        spot.items[name] = { casts = each.casts, count = each.count, id = each.id }
    end
    store[key] = spot
    return spot
end

Caught(LAKE, "Elwynn Forest", "Crystal Lake", nil, 30, {
    ["Raw Brilliant Smallfish"] = { casts = 24, count = 24, id = 6291 },
    ["Raw Longjaw Mud Snapper"] = { casts = 6, count = 6, id = 6289 },
})
Caught(POOL, "Elwynn Forest", "Crystal Lake", "Oily Blackmouth School", 12, {
    ["Oily Blackmouth"] = { casts = 12, count = 12, id = 6358 },
})
Caught(FAR, "Stranglethorn Vale", "The Riptide", nil, 40, {
    ["Firefin Snapper"] = { casts = 40, count = 40, id = 6358 },
})

--------------------------------------------------------------------------------
-- One cast's pace
--------------------------------------------------------------------------------

local clock = 1000
Fishing.lastCast = nil

--- A cast lands at `key` at `at` seconds on the clock.
local function Cast(key, at)
    clock = at or clock
    Fishing:NotePace(key, clock)
end

Cast(LAKE, 1000)
check("the first cast times nothing",
    (ns.db.fishing.pace[LAKE] or {}).seconds == 0,
    (ns.db.fishing.pace[LAKE] or {}).seconds)
check("but it counts", ns.db.fishing.pace[LAKE].casts == 1)

Cast(LAKE, 1020)
check("the gap to the next cast at the same spot counts",
    ns.db.fishing.pace[LAKE].seconds == 20, ns.db.fishing.pace[LAKE].seconds)

-- Away for an hour, then back: the break never counts as fishing.
Cast(LAKE, 1020 + Fishing.BREAK + 60)
check("a gap longer than a break counts no seconds",
    ns.db.fishing.pace[LAKE].seconds == 20, ns.db.fishing.pace[LAKE].seconds)
check("though the cast still counts", ns.db.fishing.pace[LAKE].casts == 3)

-- A cast at another spot: the gap belongs to neither.
Cast(POOL, 1400)
Cast(LAKE, 1410)
check("a cast after one somewhere else times nothing",
    ns.db.fishing.pace[LAKE].seconds == 20, ns.db.fishing.pace[LAKE].seconds)
check("and the other spot has its own count",
    ns.db.fishing.pace[POOL].casts == 1 and ns.db.fishing.pace[POOL].seconds == 0)

local version = Fishing.paceVersion
Cast(LAKE, 1420)
check("every cast moves the pace version", Fishing.paceVersion > version)

--------------------------------------------------------------------------------
-- An hour's worth waits for enough time
--------------------------------------------------------------------------------

check("no seconds a cast before MIN_SECONDS", Fishing:SecondsPerCast(LAKE) == nil)
check("and so no worth an hour", Fishing:WorthPerHour(LAKE) == nil)

-- Fish the lake for twenty minutes, twenty seconds a cast.
ns.db.fishing.pace[LAKE] = { seconds = 1200, casts = 60 }
check("twenty minutes is enough to time a cast",
    Fishing:SecondsPerCast(LAKE) == 20, Fishing:SecondsPerCast(LAKE))

local perCast = Fishing:WorthPerCast(LAKE)
check("a cast's worth comes off what it caught",
    perCast and math.abs(perCast - 30 / 30 * 4) < 0.001, perCast)
check("an hour is that at your own pace",
    math.abs(Fishing:WorthPerHour(LAKE) - perCast * 180) < 0.001,
    Fishing:WorthPerHour(LAKE))

-- One cast under the threshold is still no pace.
ns.db.fishing.pace[POOL] = { seconds = Fishing.MIN_SECONDS - 1, casts = 10 }
check("a second under the threshold is not timed yet",
    Fishing:SecondsPerCast(POOL) == nil)

--------------------------------------------------------------------------------
-- A spot, as the view reads it
--------------------------------------------------------------------------------

local function SpotFor(key)
    for _, summary in ipairs(Fishing:Spots()) do
        if summary.key == key then return GrindGather:FishSpot(summary) end
    end
end

local lake = SpotFor(LAKE)
check("the lake is a spot", lake ~= nil)
check("shown as open water", lake.shown == "Open water", lake and lake.shown)
check("and it is no pool", not lake.school)
check("with its zone in English", lake.zone == "Elwynn Forest", lake.zone)
check("its casts", lake.casts == 30, lake.casts)
check("rated past the threshold", lake.rated)
check("its best catch first",
    lake.best and lake.best.name == "Raw Brilliant Smallfish", lake.best and lake.best.name)
check("timed, so an hour shows", lake.timed and lake.perHour ~= nil)
check("and where you fished it", type(lake.coords) == "table")

local pool = SpotFor(POOL)
check("a pool reads as itself",
    pool and pool.shown == "Oily Blackmouth School", pool and pool.shown)
check("and knows it is a pool", pool.school)
check("under twenty casts it is not rated", not pool.rated, pool.casts)
check("it says how many more casts rates need", pool.needed == 8, pool.needed)
check("it has no worth a cast yet", pool.perCast == nil)
check("nor an hour", pool.perHour == nil and not pool.timed)

--------------------------------------------------------------------------------
-- The text the rows show
--------------------------------------------------------------------------------

check("a rated spot's best catch is a percent",
    GrindingUI.CatchText(lake) == "Raw Brilliant Smallfish, 80%",
    GrindingUI.CatchText(lake))
check("an unrated one counts instead",
    GrindingUI.CatchText(pool) == "Oily Blackmouth, 12 so far",
    GrindingUI.CatchText(pool))

local texts = GrindingUI:FishTexts(lake)
check("the spot column is its name", texts.mob == "Open water", texts.mob)
check("the casts column is the count", texts.count == "30", texts.count)
check("per cast is coin", texts.worth == ns.Value.Coins(lake.perCast), texts.worth)
check("an hour is coin too", texts.hour == ns.Value.Coins(lake.perHour), texts.hour)
check("and it is not waiting", not texts.waiting)

local waiting = GrindingUI:FishTexts(pool)
check("an untimed spot asks for more fishing",
    waiting.hour == "Fish a while longer", waiting.hour)
check("and says so", waiting.waiting)

--------------------------------------------------------------------------------
-- Zones
--------------------------------------------------------------------------------

local zones = GrindGather:FishZones()
check("both zones are listed", #zones == 2, #zones)

local function ZoneFor(name)
    for _, zone in ipairs(zones) do
        if zone.zone == name then return zone end
    end
end

local elwynn = ZoneFor("Elwynn Forest")
check("Elwynn holds its two spots", elwynn and elwynn.count == 2, elwynn and elwynn.count)
check("and adds up their casts", elwynn.casts == 42, elwynn.casts)
check("the spot you cast at most comes first",
    elwynn.spots[1].key == LAKE, elwynn.spots[1].shown)

local stv = ZoneFor("Stranglethorn Vale")
check("the other zone is there too", stv and stv.casts == 40, stv and stv.casts)

check("the zone band names the zone and counts both",
    GrindingUI.FishZoneText(elwynn):find("Elwynn Forest", 1, true)
        and GrindingUI.FishZoneText(elwynn):find("2 spots", 1, true)
        and GrindingUI.FishZoneText(elwynn):find("42 casts", 1, true),
    GrindingUI.FishZoneText(elwynn))

--------------------------------------------------------------------------------
-- The chip and the view
--------------------------------------------------------------------------------

local has = false
for _, gives in ipairs(Grinding.GIVES) do
    if gives.key == "fish" then has = true end
end
check("Fish is one of the chips", has)
check("and the view knows itself", Grinding.IsFishView("fish")
    and not Grinding.IsFishView("ore") and not Grinding.IsFishView("cloth"))

ns.HandleSlash("grind fish")
check("/farm grind fish picks the view", Grinding:Gives() == "fish", Grinding:Gives())
check("and the list is laid out for fish", GrindingUI.Layout() == "fish",
    GrindingUI.Layout())

local rows = GrindingUI.list.data or {}
local bands, spots = 0, 0
for _, row in ipairs(rows) do
    if row.type == "fishzone" then bands = bands + 1 end
    if row.type == "spot" then spots = spots + 1 end
end
check("a band for each zone", bands == 2, bands)
check("and a row for each spot", spots == 3, spots)
check("the levels are ignored: a spot has no level", GrindingUI.zones == nil)

check("the headings are the fish ones",
    GrindingUI.HeadingText("fish", "mob") == "SPOT"
        and GrindingUI.HeadingText("fish", "count") == "CASTS"
        and GrindingUI.HeadingText("fish", "gives") == "BEST CATCH"
        and GrindingUI.HeadingText("fish", "worth") == "PER CAST"
        and GrindingUI.HeadingText("fish", "hour") == "AN HOUR",
    GrindingUI.HeadingText("fish", "gives"))

-- The footer is the count or the skill only; the hint is the last line of
-- a row's hover (2026-10-29).
local footer = GrindingUI.FooterText("fish")
check("the footer gives no help line", not footer:find("Click", 1, true), footer)
local hint = GrindingUI.RowHint("fish")
check("the hover says to mouse over a pool first",
    hint:find("Mouse over a pool before you cast", 1, true), hint)

--------------------------------------------------------------------------------
-- Sorting
--------------------------------------------------------------------------------

local sorted = GrindingUI:SortedSpots(elwynn.spots)
check("with no sort picked, the spot you cast at most comes first",
    sorted[1].key == LAKE, sorted[1].shown)

ns.db.grindColumns = { key = "count", ascending = true }
sorted = GrindingUI:SortedSpots(elwynn.spots)
check("fewest casts first when asked", sorted[1].key == POOL, sorted[1].shown)

ns.db.grindColumns = { key = "count", ascending = false }
sorted = GrindingUI:SortedSpots(elwynn.spots)
check("and most casts first the other way", sorted[1].key == LAKE, sorted[1].shown)

ns.db.grindColumns = { key = "mob", ascending = true }
sorted = GrindingUI:SortedSpots(elwynn.spots)
check("by name, Oily comes before Open", sorted[1].key == POOL, sorted[1].shown)

ns.db.grindColumns = { key = "hour", ascending = false }
sorted = GrindingUI:SortedSpots(elwynn.spots)
check("by an hour, the timed spot wins over the one with none",
    sorted[1].key == LAKE, sorted[1].shown)
ns.db.grindColumns = nil

--------------------------------------------------------------------------------
-- A click points the arrow
--------------------------------------------------------------------------------

local camp = GrindGather.FishCamp(lake)
check("the camp is where you fished", camp.zone == "Elwynn Forest"
    and camp.coords and camp.coords.x == 42.5, camp.zone)
check("with one place on it", #camp.mobs == 1 and camp.mobs[1].name == "Open water")
check("the chat line names the spot and its zone",
    GrindGather.FishLine(lake):find("Open water", 1, true)
        and GrindGather.FishLine(lake):find("30 casts", 1, true),
    GrindGather.FishLine(lake))

local aimed = nil
local realGrind = ns.Arrow.Grind
ns.Arrow.Grind = function(_, at) aimed = at end

for index, row in ipairs(GrindingUI.list.data or {}) do
    if row.type == "spot" and row.spot.key == LAKE then
        GrindingUI:OnRowClick(row, "LeftButton", index)
        break
    end
end
check("a click on a spot aims the arrow there",
    aimed and aimed.zone == "Elwynn Forest", aimed and aimed.zone)

-- A spot the client never read a place for points nowhere and says so.
local noplace = { shown = "Open water", zone = "Elwynn Forest", casts = 5 }
aimed = nil
local mark = #env.chat
GrindingUI:OnRowClick({ type = "spot", spot = noplace }, "LeftButton", 1)
check("a spot with no place aims nothing", aimed == nil)
check("and says why",
    table.concat(env.chat, "\n", mark + 1):find("didn't read where you fished", 1, true),
    table.concat(env.chat, "\n", mark + 1))
ns.Arrow.Grind = realGrind

--------------------------------------------------------------------------------
-- Hiding
--------------------------------------------------------------------------------

DB:Hide("source", "Oily Blackmouth School")
check("a hidden spot leaves the view", SpotFor(POOL) == nil)
local elwynnAfter
for _, zone in ipairs(GrindGather:FishZones()) do
    if zone.zone == "Elwynn Forest" then elwynnAfter = zone end
end
check("Elwynn now holds the lake alone",
    elwynnAfter and elwynnAfter.count == 1 and elwynnAfter.spots[1].key == LAKE,
    elwynnAfter and elwynnAfter.count)
DB:Unhide("source", "Oily Blackmouth School")

DB:Hide("item", "Raw Brilliant Smallfish")
local hidden = SpotFor(LAKE)
check("a hidden item leaves a spot's catches",
    hidden and hidden.best and hidden.best.name == "Raw Longjaw Mud Snapper",
    hidden and hidden.best and hidden.best.name)
check("and its casts are untouched", hidden.casts == 30, hidden.casts)
DB:Unhide("item", "Raw Brilliant Smallfish")

--------------------------------------------------------------------------------
-- Your own casts, and nothing else
--------------------------------------------------------------------------------

-- What goes out over sharing is the spots' own counts. The pace is yours
-- alone: it never leaves this account, so a share can never time your hour.
ns.db.fishing.pace[LAKE].mark = "would not go"
local exported = ns.Share.Export and ns.Share.Export("f") or nil
check("sharing carries the spots",
    exported == nil or type(exported) == "table")
local text = ns.Harvest:ExportAll()
check("and the export never carries the pace",
    not text:find("would not go", 1, true))
ns.db.fishing.pace[LAKE].mark = nil

local kept = {}
for key in pairs(Fishing:Store()) do kept[#kept + 1] = key end
check("the three spots are the ones kept", #kept == 3, #kept)

ns.db.fishing.spots = {}
check("no spots means no zones", #GrindGather:FishZones() == 0)

local list = GrindingUI:FishRows(GrindGather:FishZones())
check("and the list says to go fishing",
    #list == 1 and tostring(list[1].text):find("haven't fished anywhere yet", 1, true),
    list[1] and list[1].text)

--------------------------------------------------------------------------------
-- One window width, with the new chip
--------------------------------------------------------------------------------

local widths = {}
for _, gives in ipairs(Grinding.GIVES) do
    Grinding:SetGives(gives.key)
    GrindingUI:Render()
    widths[#widths + 1] = GrindingUI.TargetWidth()
end
local same = true
for _, width in ipairs(widths) do
    if width ~= widths[1] then same = false end
end
check("every chip keeps the one window width", same, table.concat(widths, " "))

suite.done()
