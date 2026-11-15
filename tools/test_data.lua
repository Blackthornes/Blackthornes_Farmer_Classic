-- The seed database holds together: every item is findable, every source says
-- where to go and at what level, and every row declares where its facts came
-- from.
--
-- These are the invariants the window's layout quietly assumes. A source with
-- no zone renders as a blank line, and one with no level sorts to the top as
-- if it were the lowest-level option in the list, which is worse than missing.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("data")

local ns = env.Load()
local DB = ns.DB

suite.check("items loaded", DB:CountItems() > 0, DB:CountItems())
suite.check("sources loaded", DB:CountSources() > 0, DB:CountSources())

for item in DB:Iterate() do
    suite.check(("%s has at least one source"):format(item.name), #item.sources > 0)
    suite.check(("%s has a category"):format(item.name),
        type(item.category) == "string" and item.category ~= "")

    for _, source in ipairs(item.sources) do
        suite.check(("%s source has a zone"):format(item.name),
            type(source.zone) == "string" and source.zone ~= "")

        suite.check(("%s source in %s has a level"):format(item.name, source.zone),
            type(source.minLevel) == "number")

        suite.check(("%s source in %s has a sane level band"):format(item.name, source.zone),
            source.maxLevel >= source.minLevel,
            ("%s-%s"):format(tostring(source.minLevel), tostring(source.maxLevel)))

        suite.check(("%s source in %s declares its provenance"):format(item.name, source.zone),
            DB.PROVENANCE[source.provenance] ~= nil, source.provenance)

        suite.check(("%s source in %s has a known kind"):format(item.name, source.zone),
            DB.KIND_LABEL[DB.KindOf(source)] ~= nil, source.kind)
    end
end

--------------------------------------------------------------------------------
-- Item ids
--------------------------------------------------------------------------------

-- Two items claiming one id means one of them is wrong, and it matters more
-- than it looks: the harvester registers what it measured under the id off
-- the loot link, and the first id an item was given wins. A seed row with
-- the wrong id would quietly outrank the client's right one.
--
-- Found two when this check was added: Mountain Silversage carried Golden
-- Sansam's 13464, and Large Fang carried Strider Meat's 5469.
local byId = {}

for item in DB:Iterate() do
    if item.id then
        suite.check(("%s and %s do not share id %d"):format(
                byId[item.id] or "?", item.name, item.id),
            byId[item.id] == nil)
        byId[item.id] = item.name
    end
end

--------------------------------------------------------------------------------
-- Mob drops
--------------------------------------------------------------------------------

-- The point of the mob-drop data is naming the mob. A row that says only
-- "Eastern Plaguelands, level 53-60" is not something anyone can act on.
local mobSources, namedMobSources = 0, 0

for item in DB:Iterate() do
    for _, source in ipairs(item.sources) do
        if DB.KindOf(source) == "mob" then
            mobSources = mobSources + 1
            if source.name and source.name ~= "" then
                namedMobSources = namedMobSources + 1
            end
        end
    end
end

suite.check("the database has mob drops in it", mobSources > 20, mobSources)
suite.check("every mob source names the mob", namedMobSources == mobSources,
    ("%d of %d"):format(namedMobSources, mobSources))

--------------------------------------------------------------------------------
-- Provenance
--------------------------------------------------------------------------------

local counts = DB:CountByProvenance()

suite.check("provenance counts cover every source",
    (counts.classic or 0) + (counts.forever or 0) == DB:CountSources())

-- Everything shipped is Classic data. If this ever fails it is because
-- somebody marked a row confirmed, which is fine -- but the claim is that they
-- checked it in game, so the failing test is the prompt to say so in the
-- commit rather than a mistake to paper over.
suite.check("seed data is all Classic-sourced", (counts.forever or 0) == 0,
    counts.forever)

-- The generated harvest file is the one exception, and it is exempt for the
-- reason the rule exists: those rows were measured on Forever by counting
-- corpses, not claimed by somebody editing a number. It is absent in CI and
-- present on a machine that has actually farmed, so this only runs when there
-- is something to check.
if env.HasHarvested() then
    local harvested = env.Load({ harvested = true })
    local withHarvest = harvested.DB:CountByProvenance()

    -- It adds Forever rows and never a Classic one. The classic count can
    -- still fall, because a measured row replaces the carried-over row for
    -- the same spot rather than sitting beside it -- so the check is that it
    -- never RISES, and that every row lost that way gained a Forever row.
    suite.check("the harvested file adds no Classic rows",
        (withHarvest.classic or 0) <= (counts.classic or 0),
        ("%d classic before, %d after"):format(
            counts.classic or 0, withHarvest.classic or 0))

    local superseded = (counts.classic or 0) - (withHarvest.classic or 0)

    suite.check("every Classic row it displaced became a Forever one",
        (withHarvest.forever or 0) >= superseded,
        ("%d displaced, %d forever"):format(superseded, withHarvest.forever or 0))

    suite.check("and it contributes at least one",
        (withHarvest.forever or 0) > 0, withHarvest.forever)

    for _, item in pairs(harvested.DB.items) do
        for _, source in ipairs(item.sources) do
            if source.provenance == "forever" then
                suite.check(("measured %s in %s names its mob"):format(
                    item.name, source.zone), source.name ~= nil)
                -- A fishing row borrows its zone's level band from the other
                -- data (Fishing:ZoneBand), and a city like Undercity has none,
                -- so there it rightly has no level.
                -- A drop looted inside a dungeon or raid is filed from the
                -- loot window, which names the mob's ID but not its level, and
                -- has no map spot (Harvest:Corpse); the window shows "??".
                local inDungeon = source.kind ~= "fishing" and source.coords == nil
                local needsLevel = (source.kind ~= "fishing" and not inDungeon)
                    or (source.kind == "fishing" and harvested.Fishing:ZoneBand(source.zone) ~= nil)
                suite.check(("measured %s in %s carries a level"):format(
                    item.name, source.zone), not needsLevel or source.minLevel ~= nil)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Registering the same name merges
--------------------------------------------------------------------------------

local before = DB:GetItem("Copper Ore")
local beforeCount = #before.sources

DB:RegisterItem({
    name = "Copper Ore",
    sources = { { kind = "node", zone = "Testing Grounds", minLevel = 1, maxLevel = 2 } },
})

suite.check("re-registering merges rather than replacing",
    #DB:GetItem("Copper Ore").sources == beforeCount + 1)

suite.check("merging does not create a second item",
    DB:GetItem("Copper Ore") == before)

--------------------------------------------------------------------------------
-- Bad data is refused, not stored
--------------------------------------------------------------------------------

suite.check("an item with no name is refused", DB:RegisterItem({}) == nil)
suite.check("a non-table is refused", DB:RegisterItem("Copper Ore") == nil)

local item = DB:RegisterItem({
    name = "Zone Free Test Item",
    sources = { { kind = "mob", name = "nowhere in particular" } },
})

suite.check("a source with no zone is dropped", #item.sources == 0)

--------------------------------------------------------------------------------
-- The new fields
--------------------------------------------------------------------------------

-- Coordinates point somewhere. A pair outside the map, or a string where a
-- number belongs, is worse than no coordinates at all: it sends someone on a
-- flight to nowhere instead of letting them read the landmark name.
local function SourceWithCoords(coords)
    local item = DB:RegisterItem({
        name = "Coordinate Test " .. tostring(coords and coords[1] or "none"),
        sources = { { kind = "mob", name = "x", zone = "Durotar",
            minLevel = 5, coords = coords } },
    })
    return item.sources[1]
end

suite.check("good coordinates are kept", SourceWithCoords({ 45.5, 68.2 }).coords ~= nil)
suite.check("coordinates off the map are dropped",
    SourceWithCoords({ 145, 20 }).coords == nil)
suite.check("negative coordinates are dropped", SourceWithCoords({ -4, 20 }).coords == nil)
suite.check("a half pair is dropped", SourceWithCoords({ 40 }).coords == nil)
suite.check("a text coordinate is dropped", SourceWithCoords({ "40", 20 }).coords == nil)

local function SourceWithChance(chance)
    local item = DB:RegisterItem({
        name = "Chance Test " .. tostring(chance),
        sources = { { kind = "mob", name = "x", zone = "Durotar",
            minLevel = 5, chance = chance } },
    })
    return item.sources[1]
end

suite.check("a real drop rate is kept", SourceWithChance(35).chance == 35)
suite.check("a rate over 100 is dropped", SourceWithChance(140).chance == nil)
suite.check("a zero rate is dropped", SourceWithChance(0).chance == nil)

--------------------------------------------------------------------------------
-- The fully researched items
--
-- These are the worked examples of what a finished item looks like, and they
-- are what the rest of the data is meant to be copied from. If the standard
-- slips here it slips everywhere, so every row of theirs has to carry the mob,
-- where in the zone it stands, and its level band.
--
-- A drop rate is listed when somebody has one and never required. The owner's
-- rule, 2026-09-23: "a drop rate is only something we list if we do. it
-- should not preclude a listed drop though." A spot known to drop the item is
-- worth listing without a number beside it; demanding the number kept real
-- spots out, and the only way to satisfy the demand was to invent one. What
-- is still required is that a researched item has a real body of rated rows,
-- so "researched" keeps meaning somebody did the work.
--
-- Add an item to this list when you finish researching it.
--------------------------------------------------------------------------------

local RESEARCHED = { "Wool Cloth", "Linen Cloth", "Silk Cloth" }

for _, name in ipairs(RESEARCHED) do
    local item = DB:GetItem(name)

    suite.check(name .. " is in the database", item ~= nil)
    suite.check(name .. " has a serious number of spots", #item.sources >= 15,
        #item.sources)

    local withCoords, zones, zoneCount, rated = 0, {}, 0, 0

    for _, source in ipairs(item.sources) do
        suite.check(("every %s row names its mob"):format(name),
            source.name and source.name ~= "", source.zone)

        -- Classic's generated rows (Data/Data_ClassicDrops.lua) are leads
        -- for the search and name no subzone.
        suite.check(("every %s row names where in the zone"):format(name),
            source.searchOnly or (source.location and source.location ~= ""), source.name)

        -- Absent is fine. Present and malformed is not.
        suite.check(("a %s drop rate, where there is one, is a number"):format(name),
            source.chance == nil or type(source.chance) == "number", source.name)

        if source.chance then rated = rated + 1 end

        suite.check(("every %s row has a level band"):format(name),
            source.minLevel and source.maxLevel, source.name)

        -- A level band that runs backwards sorts the list wrongly and reads as
        -- a typo, which is usually what it is.
        suite.check(("every %s row has a forward level band"):format(name),
            source.maxLevel >= source.minLevel, source.name)

        -- The window draws these as "zone / location", so a location that
        -- repeats its zone reads as "Razorfen Kraul / Razorfen Kraul".
        -- An instance belongs to the zone its door is in.
        suite.check(("no %s row repeats its zone as its location"):format(name),
            source.location ~= source.zone, source.location)

        if source.coords then withCoords = withCoords + 1 end

        if not zones[source.zone] then
            zones[source.zone] = true
            zoneCount = zoneCount + 1
        end
    end

    suite.check(name .. " has coordinates on some rows", withCoords > 0, withCoords)
    suite.check(name .. " has a real body of rated rows", rated >= 15, rated)
    suite.check(name .. " spans several zones", zoneCount >= 4, zoneCount)
end

-- The three cloth brackets should not overlap much: if Linen and Silk covered
-- the same levels, one of them is wrong about what it is for.
local function LevelSpan(name)
    local low, high = 99, 0
    for _, source in ipairs(DB:GetItem(name).sources) do
        low = math.min(low, source.minLevel)
        high = math.max(high, source.maxLevel)
    end
    return low, high
end

local linenLow = select(1, LevelSpan("Linen Cloth"))
local woolLow = select(1, LevelSpan("Wool Cloth"))
local silkLow = select(1, LevelSpan("Silk Cloth"))

suite.check("the cloth brackets climb in order",
    linenLow < woolLow and woolLow < silkLow,
    ("linen %d, wool %d, silk %d"):format(linenLow, woolLow, silkLow))

--------------------------------------------------------------------------------
-- Where text
--------------------------------------------------------------------------------

suite.check("landmark and coordinates read together",
    DB:WhereText({ location = "Durnholde Keep", coords = { 80, 60 } })
        :find("Durnholde Keep", 1, true) ~= nil)

suite.check("a landmark alone is enough",
    DB:WhereText({ location = "Render's Camp" }) == "Render's Camp")

suite.check("coordinates alone still read",
    DB:WhereText({ coords = { 80, 60 } }) == "80.0, 60.0")

suite.check("nothing known reads as nothing", DB:WhereText({}) == nil)

--------------------------------------------------------------------------------
-- One row per spot: measured beats carried over
--------------------------------------------------------------------------------
--
-- The owner farmed Witchwing Slayers on 2026-09-21 and measured them at level
-- 16-17. The Classic row shipped for that same camp says 20-21. Both showing
-- at once is worse than either alone: the Classic one carries a drop rate
-- nobody checked here, and it sends you to a camp four levels off.

local function Sources(name)
    return DB.items[name:lower()].sources
end

DB:RegisterItem({
    name = "Test Cloth",
    sources = {
        { name = "Test Harpy", zone = "The Barrens", location = "The Dry Hills",
          minLevel = 20, maxLevel = 21, chance = 22 },
    },
})

suite.check("a carried-over row lands", #Sources("Test Cloth") == 1)
suite.check("and is Classic by default",
    Sources("Test Cloth")[1].provenance == "classic")

DB:AddSource("Test Cloth", { name = "Test Harpy", zone = "The Barrens",
    location = "The Dry Hills", minLevel = 16, maxLevel = 17,
    provenance = "forever" })

suite.check("measuring the same spot replaces it rather than adding",
    #Sources("Test Cloth") == 1, #Sources("Test Cloth"))
suite.check("and the measured levels are what survives",
    Sources("Test Cloth")[1].minLevel == 16
        and Sources("Test Cloth")[1].provenance == "forever",
    Sources("Test Cloth")[1].minLevel)

-- Load order must not decide it. The harvested file comes last in the TOC
-- today, but a rearranged TOC should not quietly undo a measurement.
DB:AddSource("Test Cloth", { name = "Test Harpy", zone = "The Barrens",
    location = "The Dry Hills", minLevel = 20, maxLevel = 21, chance = 22 })

suite.check("a carried-over row cannot displace a measured one",
    #Sources("Test Cloth") == 1 and Sources("Test Cloth")[1].minLevel == 16,
    Sources("Test Cloth")[1].minLevel)

-- Only the same spot. A different camp is a different answer to the question.
DB:AddSource("Test Cloth", { name = "Test Harpy", zone = "The Barrens",
    location = "Witchwing Terrace", minLevel = 19, maxLevel = 20 })

suite.check("another subzone is kept", #Sources("Test Cloth") == 2)

DB:AddSource("Test Cloth", { name = "Test Harpy", zone = "Stonetalon Mountains",
    minLevel = 19, maxLevel = 20 })

suite.check("another zone is kept", #Sources("Test Cloth") == 3)

DB:AddSource("Test Cloth", { name = "Test Raptor", zone = "The Barrens",
    location = "The Dry Hills", minLevel = 19, maxLevel = 20 })

suite.check("another creature in the same place is kept",
    #Sources("Test Cloth") == 4)

-- Two rows of the same provenance are a data-entry duplicate, which this is
-- deliberately not in the business of guessing about.
DB:AddSource("Test Cloth", { name = "Test Raptor", zone = "The Barrens",
    location = "The Dry Hills", minLevel = 19, maxLevel = 20 })

suite.check("two carried-over rows for one spot are left alone",
    #Sources("Test Cloth") == 5, #Sources("Test Cloth"))

suite.done()
