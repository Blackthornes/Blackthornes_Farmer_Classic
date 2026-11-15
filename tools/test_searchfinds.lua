-- Search finds what you looted, gathered or fished even when the data has
-- never heard of it, and "crates" finds Crate.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("searchfinds")

local ns = env.Load()
local Search = ns.Search

--------------------------------------------------------------------------------
-- Plurals
--------------------------------------------------------------------------------

suite.check("crates is crate", Search.Singular("crates") == "crate", Search.Singular("crates"))
suite.check("boxes is box", Search.Singular("boxes") == "box", Search.Singular("boxes"))
suite.check("ores is ore", Search.Singular("ores") == "ore", Search.Singular("ores"))
suite.check("glass stays", Search.Singular("glass") == nil, Search.Singular("glass"))
suite.check("cloth has none", Search.Singular("cloth") == nil)

local ores = Search:Run("copper ores")
suite.check("a plural finds the item", ores[1] and ores[1].item.name == "Copper Ore",
    ores[1] and ores[1].item.name)

for _, result in ipairs(Search:Run("craters")) do
    suite.check("a plural never matches a zone the shorter way",
        result.why ~= "zone", result.item.name)
end

--------------------------------------------------------------------------------
-- Your own finds
--------------------------------------------------------------------------------

local before = #Search:Run("crate")

ns.Harvest.records["Ruin Ghoul|Ruins of Lordaeron|"] = {
    mob = "Ruin Ghoul", zone = "Ruins of Lordaeron", minLevel = 22, maxLevel = 24,
    corpses = 40,
    items = {
        ["Sealed Supply Crate"] = { corpses = 10, count = 10, id = 990001 },
        ["Linen Cloth"] = { corpses = 12, count = 15, id = 2589 },
    },
}
ns.Harvest.records["Mystery Bat|Elwynn Forest|"] = {
    mob = "Mystery Bat", zone = "Elwynn Forest", minLevel = 5, maxLevel = 5,
    corpses = 3,
    items = { ["Sealed Supply Crate"] = { corpses = 1, count = 1, id = 990001 } },
}
ns.db.gathering = { nodes = { ["Durotar||Odd Chest"] = {
    zone = "Durotar", node = "Odd Chest", kind = "chest", gathers = 2,
    items = { ["Dusty Crate"] = { gathers = 2, count = 2 } },
} } }
ns.db.fishing = { spots = { ["Westfall||"] = {
    zone = "Westfall", casts = 25,
    items = { ["Floating Crate"] = { casts = 5, count = 5 } },
} } }
ns.Harvest.changes = (ns.Harvest.changes or 0) + 1
Search.found = nil

local results = Search:Run("crates")
local byName = {}
for _, result in ipairs(results) do byName[result.item.name] = result.item end

local sealed = byName["Sealed Supply Crate"]
suite.check("a looted crate the data does not know is found", sealed ~= nil)
suite.check("both spots it came from are listed", sealed and #sealed.sources == 2,
    sealed and #sealed.sources)
local rated, thin
for _, source in ipairs(sealed and sealed.sources or {}) do
    if source.name == "Ruin Ghoul" then rated = source else thin = source end
end
suite.check("a rate once 20 corpses are behind it", rated and math.abs(rated.chance - 25) < 0.01,
    rated and rated.chance)
suite.check("no rate off 3 corpses", thin and thin.chance == nil)
suite.check("the count shows instead", thin and thin.dropText == "1 in 3", thin and thin.dropText)
suite.check("no count once there is a rate", rated and rated.dropText == nil)
suite.check("the chat line says the count", thin and Search:SourceLine(thin):find("1 in 3", 1, true) ~= nil)
suite.check("marked as measured on Forever", rated and rated.provenance == "forever")
suite.check("a gathered crate is found", byName["Dusty Crate"] ~= nil)
suite.check("a fished crate is found", byName["Floating Crate"] ~= nil)
suite.check("the found item keeps its ID", sealed and sealed.id == 990001)
suite.check("more than before", #Search:Run("crate") > before)

suite.check("an item the data knows is not listed twice", (function()
    local count = 0
    for _, result in ipairs(Search:Run("linen cloth")) do
        if result.item.name == "Linen Cloth" then count = count + 1 end
    end
    return count == 1
end)())

-- A known item keeps its rows and gains the spots you found it.
local linen = ns.DB:GetItem("Linen Cloth")
local shipped = #linen.sources
local linenResult
for _, result in ipairs(Search:Run("linen cloth")) do
    if result.item.name == "Linen Cloth" then linenResult = result.item end
end
local ghoul
for _, source in ipairs(linenResult and linenResult.sources or {}) do
    if source.name == "Ruin Ghoul" then ghoul = source end
end
suite.check("your own spot is added to an item the data knows", ghoul ~= nil)
suite.check("with its rate", ghoul and math.abs(ghoul.chance - 30) < 0.01, ghoul and ghoul.chance)
suite.check("the data's spots are all still there", linenResult and #linenResult.sources == shipped + 1,
    linenResult and #linenResult.sources)
suite.check("the database item is not changed", #linen.sources == shipped)
suite.check("it keeps its Goal button", linenResult and not linenResult.found)

-- A spot the data already lists is not listed twice.
local first = linen.sources[1]
ns.Harvest.records["dupe"] = {
    mob = first.name, zone = first.zone, corpses = 30,
    items = { ["Linen Cloth"] = { corpses = 3, count = 3, id = 2589 } },
}
ns.Harvest.changes = ns.Harvest.changes + 1
Search.found = nil
local twice = 0
for _, result in ipairs(Search:Run("linen cloth")) do
    if result.item.name == "Linen Cloth" then
        for _, source in ipairs(result.item.sources) do
            if ns.DB.KindOf(source) == ns.DB.KindOf(first) and source.name == first.name and source.zone == first.zone then
                twice = twice + 1
            end
        end
    end
end
suite.check("a spot the data has is listed once", twice == 1, twice)
ns.Harvest.records["dupe"] = nil
ns.Harvest.changes = ns.Harvest.changes + 1
Search.found = nil

suite.check("nothing is added to the database", ns.DB:GetItem("Sealed Supply Crate") == nil)

suite.check("a find's mob finds it too", (function()
    for _, result in ipairs(Search:Run("ruin ghoul")) do
        if result.item.name == "Sealed Supply Crate" then return true end
    end
    return false
end)())

ns.DB:Hide("item", "Sealed Supply Crate")
local hidden = false
for _, result in ipairs(Search:Run("sealed supply")) do
    if result.item.name == "Sealed Supply Crate" then hidden = true end
end
suite.check("a hidden find stays hidden", not hidden)
ns.DB:Unhide("item", "Sealed Supply Crate")

local rows = Search:BuildRows("sealed supply")
suite.check("the window draws it", rows[1] and rows[1].type == "item"
    and rows[1].item.name == "Sealed Supply Crate", rows[1] and rows[1].type)

suite.done()
