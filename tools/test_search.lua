-- Searching and the lines it produces.
--
-- The ranking is the feature: one box answers both "where do I get this" and
-- "what is worth farming here", and the second must never bury the first. So
-- these check the order results come back in, not just that they come back.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("search")

local ns = env.Load()
local Search = ns.Search

--------------------------------------------------------------------------------
-- Ranking
--------------------------------------------------------------------------------

local exact = Search:Run("copper ore")
suite.check("an exact name ranks first",
    exact[1] and exact[1].item.name == "Copper Ore",
    exact[1] and exact[1].item.name)

local partial = Search:Run("mithril")
suite.check("a partial name matches",
    partial[1] and partial[1].item.name == "Mithril Ore",
    partial[1] and partial[1].item.name)

local alias = Search:Run("spider silk")
suite.check("an alias matches",
    alias[1] and alias[1].item.name == "Spider's Silk",
    alias[1] and alias[1].item.name)

local byZone = Search:Run("westfall")
suite.check("a zone returns what is farmable there", #byZone > 0, #byZone)

for _, result in ipairs(byZone) do
    -- Westfall Deed is a name match, and says so.
    suite.check("a zone match never claims to be a name match",
        result.why ~= "name" or result.item.name:lower():find("westfall", 1, true) ~= nil,
        result.item.name)
end

local byMob = Search:Run("defias")
-- Items named for them (Defias Script) come first, as name matches.
local mobFirst
for _, result in ipairs(byMob) do
    if result.why ~= "name" then mobFirst = result.item.name break end
end
suite.check("a mob name finds what it drops", mobFirst == "Linen Cloth", mobFirst)

local byCategory = Search:Run("herbalism")
suite.check("a category returns its items", #byCategory > 3, #byCategory)

-- "Copper" is in the name of one item and the zone list of none, so a name
-- match has to come out above the alias-only and zone-only matches.
local mixed = Search:Run("copper")
suite.check("name matches sort above weaker matches",
    mixed[1] and mixed[1].why == "name", mixed[1] and mixed[1].why)

suite.check("nonsense finds nothing", #Search:Run("qqzzxx") == 0)
suite.check("an empty query finds nothing", #Search:Run("") == 0)
suite.check("whitespace is not a query", #Search:Run("   ") == 0)

--------------------------------------------------------------------------------
-- Ordering within an item
--------------------------------------------------------------------------------

local copper = ns.DB:GetItem("Copper Ore")
local sorted = Search:SortedSources(copper)

for index = 2, #sorted do
    suite.check("sources sort by level",
        sorted[index].minLevel >= sorted[index - 1].minLevel,
        ("%d after %d"):format(sorted[index].minLevel, sorted[index - 1].minLevel))
end

suite.check("sorting does not disturb the stored order",
    #copper.sources == #sorted)

--------------------------------------------------------------------------------
-- Lines
--------------------------------------------------------------------------------

local Util = ns.Util

local line = Util.StripColor(Search:SourceLine(sorted[1]))

suite.check("a source line names the zone",
    line:find(sorted[1].zone, 1, true) ~= nil, line)

suite.check("a source line shows the level band",
    line:find(Search:LevelText(sorted[1]), 1, true) ~= nil, line)

-- A herb node is named after the herb, so it carries no name of its own and
-- must not print its kind twice.
local dreamfoil = ns.DB:GetItem("Dreamfoil")
local herbLine = Util.StripColor(Search:SourceLine(dreamfoil.sources[1]))
local _, occurrences = herbLine:gsub("herb node", "")

suite.check("an unnamed node does not repeat its kind", occurrences == 1, herbLine)

-- No row carries a Forever marker on Classic Era.
suite.check("Classic rows are unmarked",
    not Util.StripColor(Search:SourceLine(sorted[1])):find("[Forever]", 1, true))

local confirmed = { kind = "mob", name = "a checked mob", zone = "Durotar",
    minLevel = 5, maxLevel = 8, provenance = "forever" }

suite.check("nor a confirmed row",
    not Util.StripColor(Search:SourceLine(confirmed)):find("Forever", 1, true))

local lines, total = Search:BuildLines("copper ore", 12)
suite.check("building lines produces output", #lines > 1, #lines)
suite.check("building lines reports a total", total >= 1, total)

local missed = Search:BuildLines("qqzzxx", 12)
suite.check("a miss explains itself",
    Util.StripColor(missed[1]):find("Nothing found", 1, true) ~= nil, missed[1])

-- A broad query must not dump the whole database into the window.
local broad, broadTotal = Search:BuildLines("mob drop", 2)
suite.check("a broad query is capped", broadTotal > 2, broadTotal)
suite.check("the cap says how much was left out",
    Util.StripColor(broad[#broad]):find("and %d+ more") ~= nil, broad[#broad])

--------------------------------------------------------------------------------
-- Rare drops
--
-- "%d" printed a rate under one percent as "0%", which reads as never.
--------------------------------------------------------------------------------

local rare = { kind = "mob", name = "a rare mob", zone = "Durotar", minLevel = 5, chance = 0.4 }
local rareLine = Util.StripColor(Search:SourceLine(rare))
suite.check("a rate under one percent reads <1%", rareLine:find("<1%", 1, true) ~= nil, rareLine)
suite.check("not 0%", rareLine:find("0%", 1, true) == nil, rareLine)

rare.chance = 7.5
rareLine = Util.StripColor(Search:SourceLine(rare))
suite.check("a small rate keeps its decimal", rareLine:find("~7.5%", 1, true) ~= nil, rareLine)

rare.chance = 38
rareLine = Util.StripColor(Search:SourceLine(rare))
suite.check("a common rate is about a whole number", rareLine:find("~38%", 1, true) ~= nil, rareLine)

--------------------------------------------------------------------------------
-- A search for a place or a mob shows that place or mob
--
-- "/farm defias" listed every mob that drops linen, all 93 rows of it, with
-- the first Defias at row 51.
--------------------------------------------------------------------------------

local function Matches(source, text)
    -- Not ipairs: a spot with no location would end the list early.
    local fields = { source.zone, source.location, source.name }
    for i = 1, 3 do
        local field = fields[i]
        if field and field:lower():find(text, 1, true) then return true end
    end
    return false
end

for _, query in ipairs({ "defias", "westfall", "wailing caverns" }) do
    local rows = Search:BuildRows(query)
    local strays = 0
    for _, row in ipairs(rows) do
        -- An item named for it (Westfall Deed) shows all its spots.
        if row.type == "source" and not Matches(row.source, query)
            and not row.item.name:lower():find(query, 1, true) then
            strays = strays + 1
        end
    end
    suite.check(("%s: every spot shown is one it named"):format(query), strays == 0, strays)
end

local linen = ns.DB:GetItem("Linen Cloth")
local linenHeading
for _, row in ipairs(Search:BuildRows("defias")) do
    if row.type == "item" and row.item == linen then linenHeading = row break end
end
suite.check("the item heading says how many of its spots are shown",
    linenHeading and linenHeading.count < #linen.sources,
    linenHeading and linenHeading.count)
suite.check("in so many words",
    Search:SpotsText(5, 47) == "5 of 47 spots" and Search:SpotsText(3, 3) == "3 spots",
    Search:SpotsText(5, 47))

local linenLine
for _, line in ipairs(Search:BuildLines("defias", 5)) do
    if Util.StripColor(line):find("^Linen Cloth ") then linenLine = Util.StripColor(line) break end
end
suite.check("chat says it too", linenLine and linenLine:find(
    ("of %d spots"):format(#linen.sources), 1, true) ~= nil, linenLine)

-- Named by its own name, an item still shows everywhere it comes from.
local byName = 0
for _, row in ipairs(Search:BuildRows("linen cloth")) do
    if row.type == "source" and row.item == linen then byName = byName + 1 end
end
suite.check("a name match keeps every spot", byName == #linen.sources, byName)

-- Its filter chips come from the spots shown: Wailing Caverns' items are
-- fished elsewhere, but not there.
local caverns = Search:KindsInResults("wailing caverns")
local fishing = false
for _, kind in ipairs(caverns) do if kind == "fishing" then fishing = true end end
suite.check("no chip for a kind found only elsewhere", not fishing, table.concat(caverns, ","))

--------------------------------------------------------------------------------
-- The kind filter comes before the cap
--
-- Capped first, the chips for a zone that matched many items showed one
-- herb, or nothing but "and 55 more items".
--------------------------------------------------------------------------------

for _, kind in ipairs(Search:KindsInResults("barrens")) do
    local expected = 0
    for _, result in ipairs(Search:Run("barrens")) do
        for _, source in ipairs(result.sources or result.item.sources) do
            if source.kind == kind then expected = expected + 1 break end
        end
    end

    local rows, total = Search:BuildRows("barrens", { kind = kind, max = 3 })
    local shown, wrong = 0, 0
    for _, row in ipairs(rows) do
        if row.type == "item" then shown = shown + 1 end
        if row.type == "source" and row.source.kind ~= kind then wrong = wrong + 1 end
    end

    suite.check(("%s: its chip shows its items"):format(kind),
        shown == math.min(3, expected) and wrong == 0, ("%d shown, %d wrong"):format(shown, wrong))
    suite.check(("%s: and counts all of them"):format(kind), total == expected, total)
    suite.check(("%s: the rest are owned up to"):format(kind),
        expected <= 3 or rows[#rows].type == "more", rows[#rows].type)
end

suite.done()
