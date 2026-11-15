-- Rows on one item match by name, zone and subzone in any case, with each
-- name lowered once and kept.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("lowernames")

local ns = env.Load()
local DB = ns.DB

suite.check("lowers a name", DB.Lower("Elwynn Forest") == "elwynn forest")
suite.check("the same answer twice", DB.Lower("Elwynn Forest") == DB.Lower("Elwynn Forest"))

local item = DB:RegisterItem({ name = "Lower Test Item", category = "Cloth" })
DB:AddSource(item or "Lower Test Item", { name = "Case Mob", zone = "Durotar", location = "Razor Hill", minLevel = 1, maxLevel = 2 })
DB:AddSource(item or "Lower Test Item", { name = "case mob", zone = "DUROTAR", location = "razor hill", minLevel = 1, maxLevel = 2, provenance = "forever" })
DB:AddSource(item or "Lower Test Item", { name = "Case Mob", zone = "Durotar", location = "Valley of Trials", minLevel = 1, maxLevel = 2 })
local added = DB:GetItem("Lower Test Item")
suite.check("a row in another case takes the place of the one there", added and #added.sources == 2,
    added and #added.sources)

suite.done()
