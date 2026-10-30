-- Camp worth on the Grind tab: what a camp earns you in an hour.
--
-- What matters: only your own kills and picks in the camp's subzone count,
-- never shipped or guild data; under Tracker.MIN_KILLS kills the band says
-- to farm a while and the mobs' worth reads "--"; each mob's YOUR KILLS is
-- its share of the camp ("88 (35%)") or "7/20" while short; herbs you
-- picked there get a row; the hover adds AN HOUR HERE; Best Worth sorts
-- camps by it; and nothing new is saved.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("campworth")
local check = suite.check

local ns = env.Load({ ui = true })
local CampWorth, Grinding, GrindingUI, UI = ns.CampWorth, ns.Grinding, ns.GrindingUI, ns.UI
local DB, Value, Tracker = ns.DB, ns.Value, ns.Tracker

env.world.zone = "Westfall"
env.world.subZone = ""

local ZONE = "Camp Vale"

DB:RegisterItem({ name = "Camp Cloth", category = "Cloth", sources = {
    { name = "Camp Bandit", zone = ZONE, location = "Bandit Camp", coords = { 40, 40 },
        minLevel = 24, maxLevel = 25, chance = 30 },
    { name = "Camp Thug", zone = ZONE, location = "Bandit Camp", coords = { 42, 41 },
        minLevel = 25, maxLevel = 26, chance = 20 },
    { name = "Camp Ghoul", zone = ZONE, location = "Old Crypt", coords = { 70, 20 },
        minLevel = 24, maxLevel = 25, chance = 20 },
    { name = "Camp Ogre", zone = ZONE, location = "Ogre Den", coords = { 10, 10 },
        minLevel = 24, maxLevel = 25, chance = 20 },
} })

-- Prices: the cloth sells for 1s, a Peacebloom for 10c.
local prices = { ["Camp Cloth"] = 100 }
Value.WorthOf = function(_, name) return prices[name], prices[name] and "vendor" or nil end
Value.UnitPrice = function(_, id) if id == 2447 then return 10 end return nil end

-- Your own play.
local mobs = Tracker:Store()
mobs["Camp Bandit"] = { kills = 90, places = { ["Bandit Camp, " .. ZONE] = 90 },
    items = { ["Camp Cloth"] = 45 }, coinKills = 90, copper = 1800 }
mobs["Camp Thug"] = { kills = 30, places = { ["Bandit Camp, " .. ZONE] = 10, ["Elsewhere, " .. ZONE] = 20 },
    items = { ["Camp Cloth"] = 30 }, coinKills = 30, copper = 0 }
mobs["Camp Ghoul"] = { kills = 7, places = { ["Old Crypt, " .. ZONE] = 7 }, items = {} }
-- The ogres: the data says they drop cloth, but you never killed one.

ns.db.farmStats = ns.db.farmStats or {}
ns.db.farmStats.pace = ns.db.farmStats.pace or {}
ns.db.farmStats.pace["Camp Bandit"] = { kills = 10, seconds = 300 }
ns.db.farmStats.pace["Camp Thug"] = { kills = 10, seconds = 600 }

ns.db.gathering = ns.db.gathering or {}
ns.db.gathering.nodes = ns.db.gathering.nodes or {}
ns.db.gathering.nodes["camp:peacebloom"] = { zone = ZONE, location = "Bandit Camp", node = "Peacebloom",
    kind = "herb", gathers = 20, items = { Peacebloom = { gathers = 20, count = 40, id = 2447 } } }
ns.db.gathering.pace = ns.db.gathering.pace or {}
ns.db.gathering.pace[ZONE .. "|Peacebloom"] = { seconds = 1200, gathers = 20 }

local before = {}
for key in pairs(ns.db) do before[key] = true end

local camp = { zone = ZONE, location = "Bandit Camp", label = "Bandit Camp", mobs = {} }
local crypt = { zone = ZONE, location = "Old Crypt", label = "Old Crypt", mobs = {} }
local den = { zone = ZONE, location = "Ogre Den", label = "Ogre Den", mobs = {} }

--------------------------------------------------------------------------------
-- Kills and picks are read by subzone
--------------------------------------------------------------------------------

local entry, gathered = CampWorth:Kills(camp)
check("only kills in the camp count", entry.total == 100, tostring(entry.total))
check("each mob's own kills there", entry.mobs["Camp Bandit"] == 90 and entry.mobs["Camp Thug"] == 10)
check("herbs picked in the subzone", #gathered == 1 and gathered[1].node == "Peacebloom" and gathered[1].picks == 20)
check("no kills, no camp", CampWorth:Kills(den).total == 0)
check("an unnamed camp has none", CampWorth:Kills({ zone = ZONE }).total == 0)

--------------------------------------------------------------------------------
-- The camp's hour
--------------------------------------------------------------------------------

local result = CampWorth:Work(camp)
check("enough kills: ready", result.ready == true)
-- Bandits: 90 kills at 30 s, 50c cloth + 20c coin each. Thugs: 10 at 60 s,
-- 1s cloth. Peacebloom: 20 picks at 60 s, 20c each.
-- 2700 + 600 + 1200 = 4500 s; 4500 + 1000 + 1800 + 400 copper in all.
local expected = math.floor((4500 + 1000 + 1800 + 400) * 3600 / 4500 + 0.5)
check("gold an hour from your own play", result.perHour == expected,
    tostring(result.perHour) .. " vs " .. expected)
check("coin is its own line", math.abs((result.coin or 0) - 1800 * 3600 / 4500) < 0.01)
check("best mob first", result.lines[1].name == "Camp Bandit")
check("herb priced", result.herbs[1].perHour and math.abs(result.herbs[1].perHour - 400 * 3600 / 4500) < 0.01)
check("hours from your pace", math.abs(result.hours - 4500 / 3600) < 0.001)
check("hours text", CampWorth.HoursText(result.hours) == "From your 1.3 hours here.",
    CampWorth.HoursText(result.hours))
check("kill mix", result.mix == "You kill about 9 Camp Bandits for every Camp Thug.", tostring(result.mix))

local short = CampWorth:Work(crypt)
check("under 20 kills: not ready", short.ready == false and short.kills == 7)
check("never from shipped data", CampWorth:Work(den).ready == false)

-- The band.
local band, color = CampWorth.BandText(result)
check("band says this camp", band:find("This camp:", 1, true) and band:find("an hour", 1, true) and color == "muted")
check("short band says farm a while", CampWorth.BandText(short) == "Farm here a while to see")
check("pending band is blank", CampWorth.BandText(nil) == "")

-- YOUR KILLS.
check("count and share", CampWorth.KillsText(90, 100) == "90 (90%)", CampWorth.KillsText(90, 100))
local text, isShort = CampWorth.KillsText(7, 7)
check("short shows x/20", text == "7/20" and isShort == true, tostring(text))
check("none shows blank", CampWorth.KillsText(nil, 100) == "")

-- Plurals.
check("plural dog", CampWorth.Plural("Mangy Dog") == "Mangy Dogs")
check("plural wolf", CampWorth.Plural("Gray Wolf") == "Gray Wolves", CampWorth.Plural("Gray Wolf"))
check("plural man", CampWorth.Plural("Defias Watchman") == "Defias Watchmen")
check("plural fly", CampWorth.Plural("Blood Fly") == "Blood Flies")
check("plural lynx", CampWorth.Plural("Lynx") == "Lynxes")

--------------------------------------------------------------------------------
-- The worker and the Grind tab
--------------------------------------------------------------------------------

CampWorth.results, CampWorth.queue, CampWorth.queued = {}, {}, {}
check("worked out a few a frame", CampWorth:For(camp) == nil and #CampWorth.queue == 1)
check("short camp answers at once", CampWorth:For(crypt).ready == false)
CampWorth:Step(99)
check("worker answers", CampWorth:Known(camp) == expected)
check("kept until something moves", CampWorth:For(camp) == CampWorth:For(camp))

-- A hidden mob is left out.
DB:Hide("source", "Camp Thug")
CampWorth.results = {}
local hidden = CampWorth:Work(camp)
check("hidden mob left out", hidden.ready and #hidden.lines == 1 and hidden.lines[1].name == "Camp Bandit")
DB:Unhide("source", "Camp Thug")
CampWorth.results = {}
CampWorth:For(camp); CampWorth:Step(99)

-- The hour card.
local lines = GrindingUI.HourLines(CampWorth:For(camp))
local seen = {}
for _, line in ipairs(lines) do seen[line[1]] = line end
check("card heading", lines[1][1] == "AN HOUR HERE")
check("card names mobs in plural", seen["Camp Bandits"] ~= nil)
check("card has coin", seen["Coin"] ~= nil)
check("card has herb", seen["Peacebloom"] ~= nil)
check("card total", seen["In all"] ~= nil)
check("card note", lines[#lines][1]:find("From your", 1, true) ~= nil)

-- Mob and herb rows.
local mobTexts = GrindingUI:MobTexts({ name = "Camp Bandit", minLevel = 24, maxLevel = 25 }, camp)
check("mob kills share", mobTexts.kills == "90 (90%)", tostring(mobTexts.kills))
local ghoul = GrindingUI:MobTexts({ name = "Camp Ghoul", minLevel = 24, maxLevel = 25 }, crypt)
check("short mob shows x/20 and --", ghoul.kills == "7/20" and ghoul.killsShort and ghoul.worth == "--")
local herbTexts = GrindingUI:HerbTexts(gathered[1], camp)
check("herb row name", herbTexts.mob == "Peacebloom (herb)")
check("herb row picks", herbTexts.kills == "20 picked")
check("herb row worth", herbTexts.worth ~= "--" and herbTexts.worth ~= "")

-- Best Worth.
local found = false
for _, entry in ipairs(Grinding.SORTS or {}) do
    if entry.key == "worth" and entry.label == "Best Worth" then found = true end
end
check("Best Worth in the sort menu", found)
check("not the default", Grinding.Sort() ~= "worth")

ns.db.grindMin, ns.db.grindMax = 24, 26
Grinding:SetSort("worth")
local camps = Grinding:Camps()
local order = {}
for _, each in ipairs(camps) do
    if each.zone == ZONE then order[#order + 1] = each.location end
end
check("ready camp first", order[1] == "Bandit Camp", table.concat(order, ", "))
Grinding:SetSort("busiest")

-- Rows and footer.
UI:ShowTab("grind")
GrindingUI:Render()
local rows = GrindingUI:Rows(camps, 0, 24, 26)
local herbRow = false
for _, row in ipairs(rows) do if row.type == "herb" and row.camp.location == "Bandit Camp" then herbRow = true end end
check("herb row inside its camp", herbRow)
-- The footer only counts; what a camp's worth comes from is the rows' hover.
check("footer", GrindingUI.FooterText("mobs") == "")
check("row hint", GrindingUI.RowHint("mobs") == "A camp's worth comes from your own kills and picks there.")

-- Ore stays as it was.
local Layouts = GrindingUI.LAYOUTS
if Layouts and Layouts.nodes then
    local hasKills = false
    for _, key in ipairs(Layouts.nodes) do if key == "kills" then hasKills = true end end
    check("ore view has no YOUR KILLS", not hasKills)
end

-- Nothing new saved.
local added = {}
for key in pairs(ns.db) do if not before[key] then added[#added + 1] = key end end
local allowed = { grindMin = true, grindMax = true, grindSort = true, hiddenSources = true, hiddenItems = true }
local stray = {}
for _, key in ipairs(added) do if not allowed[key] then stray[#stray + 1] = key end end
check("nothing new saved", #stray == 0, table.concat(stray, ", "))

suite.done()
