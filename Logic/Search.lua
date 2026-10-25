-- Blackthornes Farmer -- Logic/Search.lua
-- Ranked search over the database, and the display lines the window and the
-- chat output both print.
--
-- The ranking is the whole feature. One box has to answer two questions --
-- "where do I get this" and "what is worth farming here" -- without the second
-- ever burying the first, so an item whose *name* matches always outranks one
-- that merely happens to drop in a zone you named.

local _, ns = ...
local L = ns.L

local Search = ns.NewModule("Search")

local Util = ns.Util

local SCORE = {
    exact    = 100,
    prefix   = 60,
    infix    = 30,
    category = 20,
    zone     = 15,
    source   = 10,
}

--- How well `needle` matches `haystack`. Higher is better; 0 is no match.
local function MatchScore(haystack, needle)
    if not haystack or haystack == "" then return 0 end
    if haystack == needle then return SCORE.exact end

    local start = haystack:find(needle, 1, true)
    if start == 1 then return SCORE.prefix end
    if start then return SCORE.infix end

    return 0
end

--- "crates" as "crate", "boxes" as "box": the query with a plural ending
--- taken off, or nil when it has none. Short words are left alone.
function Search.Singular(query)
    if type(query) ~= "string" or #query < 4 then return nil end
    local single = query:match("^(.-[^aeiou])es$") and query:match("^(.-)es$")
    if single and (single:match("[sx]$") or single:match("[cs]h$") or single:match("z$")) then
        return single
    end
    single = query:match("^(.-[^s])s$")
    return single
end

--- A name's score for the query, or for its singular when that is better.
local function NameScore(name, query, single)
    if type(name) ~= "string" then return 0 end
    local lower = name:lower()
    local score = MatchScore(lower, query)
    if single then
        local other = MatchScore(lower, single)
        if other > score then score = other end
    end
    return score
end

--- Ranked search. Returns an array of { item, score, why, sources }.
--
-- `sources` is set when the item was found through some of its sources (a
-- zone, a landmark or a mob) and holds just those. A search for "defias"
-- wants the Defias, not every mob in the game that drops linen.
function Search:Run(query)
    local results = {}

    query = Util.Trim(query):lower()
    if query == "" then return results end

    -- A keystroke asks twice, once for the chips and once for the rows, so
    -- the last answer is kept while the data it came from stands. Callers
    -- never change what comes back.
    -- On a client in another language the names it gives the items are
    -- searched too ("leinen" finds Linen Cloth), read as they come in.
    ns.DB:LearnClientNames()

    -- "greens" or "world drops" leads with the mobs best for green gear
    -- (Logic/WorldDrops.lua), which move with every corpse.
    local WorldDrops = ns.WorldDrops
    local world = WorldDrops and WorldDrops:IsEnabled() and WorldDrops.IsQuery(query)
    local harvest = world and (ns.Harvest and ns.Harvest.changes or 0) or nil

    local found = self:FoundVersion()

    local last = self.lastRun
    if last and last.query == query and last.changes == ns.DB.changes
        and last.found == found
        and last.names == ns.DB.namesVersion and last.hidden == ns.DB.hiddenVersion
        and last.harvest == harvest then
        self.hidHit = last.hidHit
        return last.results
    end

    -- An item on the hide list is no result; a mob or node on it is not
    -- among an item's spots, and an item left with none is no result.
    -- "Hide skinning" leaves skinning out of a mob's worth and the other
    -- lists, never out of the search: leather is still something you can
    -- look up (the owner, 2026-10-15). `hidHit` says something matched and
    -- was hidden, for what an empty search says.
    self.hidHit = false
    local hidesSources = ns.DB:HidesAny("source")

    -- "crates" finds Crate too. Only names are matched the shorter way: a
    -- zone or a mob would turn "crates" into Un'Goro Crater.
    local single = Search.Singular(query)

    local function Consider(item)
        local score, why = NameScore(item.name, query, single), "name"
        local matched

        for _, alias in ipairs(item.aliases) do
            local aliasScore = NameScore(alias, query, single)
            if aliasScore > score then
                score, why = aliasScore, "name"
            end
        end

        local clientName = ns.DB:ClientName(item)
        if clientName then
            local clientScore = NameScore(clientName, query, single)
            if clientScore > score then score, why = clientScore, "name" end
        end

        if score == 0 and MatchScore(item.category:lower(), query) > 0 then
            score, why = SCORE.category, "category"
        end

        if score == 0 then
            for _, source in ipairs(item.sources) do
                local how

                -- The zone as the client names it too ("Wald von Elwynn").
                local shown = ns.Spots and ns.Spots.Show(source.zone)
                if MatchScore(source.zone:lower(), query) > 0
                    or (shown and shown ~= source.zone and MatchScore(shown:lower(), query) > 0) then
                    how = "zone"

                -- A landmark is how people actually name a farming spot to
                -- each other: "Durnholde", "Raven Hill". Worth matching.
                elseif source.location and MatchScore(source.location:lower(), query) > 0 then
                    how = "location"

                elseif source.name and MatchScore(source.name:lower(), query) > 0 then
                    how = "source"
                end

                if how then
                    matched = matched or {}
                    matched[#matched + 1] = source

                    -- The first source that matches ranks the item; the
                    -- rest are only listed under it.
                    if score == 0 then
                        score, why = how == "source" and SCORE.source or SCORE.zone, how
                    end
                end
            end
        end

        if score > 0 and hidesSources then
            local all = matched or item.sources
            local kept = {}
            for _, source in ipairs(all) do
                if not ns.DB:IsHiddenSource(source.name) then kept[#kept + 1] = source end
            end
            if #kept == 0 then
                score = 0
                self.hidHit = true
            elseif #kept < #all then
                matched = kept
            end
        end

        if score > 0 and ns.DB:IsHiddenItem(item) then
            self.hidHit = true
        elseif score > 0 then
            results[#results + 1] = { item = item, score = score, why = why, sources = matched }
        end
    end

    -- An item the data knows also lists the spots you found it that the
    -- data does not have yet (Search:FoundItems' `extra`).
    local foundItems = self:FoundItems()
    for item in ns.DB:Iterate() do Consider(self:WithYourSpots(item)) end

    -- What you looted, gathered or fished that the data has never heard of
    -- (Search:FoundItems): found the same way.
    for _, item in ipairs(foundItems) do Consider(item) end

    table.sort(results, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.item.name < b.item.name
    end)

    local worldItem = world and WorldDrops:SearchItem()
    if worldItem then table.insert(results, 1, { item = worldItem, score = math.huge, why = "name" }) end

    self.lastRun = { query = query, changes = ns.DB.changes, names = ns.DB.namesVersion,
        hidden = ns.DB.hiddenVersion, harvest = harvest, found = found, hidHit = self.hidHit,
        results = results }
    return results
end

--------------------------------------------------------------------------------
-- Your own finds
--
-- The search reads the database: what ships with the addon, folded in from
-- the owner's own play at each release, and the guild's rows. Anything a
-- player loots, gathers or fishes that the data has never heard of (a crate
-- Forever added, a drop off a new mob) was in their records but no search
-- found it. So every item in the player's own harvest, gathering and
-- fishing records that the database does not know becomes a result of its
-- own, with the spots it came from. An item the data does know keeps its
-- rows and gains the spots you found it that the data does not list (a
-- player looted clams off a mob the data never named for them). Built only
-- when a search runs and the records moved, at most every FOUND_GAP
-- seconds; nothing is saved and
-- nothing is added to the database, so Rankings, the tooltips and the Grind
-- tab never see it. Guild data never reaches it.
--------------------------------------------------------------------------------

Search.FOUND_GAP = 5
-- A rate shows once this many corpses, gathers or casts are behind it, as
-- the harvest's own export has it.
Search.FOUND_SAMPLE = 20

--- What the found items are built from: moves when a corpse, a gather or
--- a cast is recorded, or the data or the client's names change.
function Search:FoundVersion()
    local key = ("%d:%d:%d:%d:%d:%d"):format(
        ns.Containers and ns.Containers.changes or 0,
        ns.Harvest and ns.Harvest.changes or 0,
        ns.Gathering and ns.Gathering.clock or 0,
        ns.Fishing and ns.Fishing.clock or 0,
        ns.DB.changes or 0, ns.DB.namesVersion or 0)
    local now = GetTime and GetTime() or 0
    local built = self.found
    if built and built.key ~= key and now - built.at < self.FOUND_GAP then
        return built.key
    end
    return key
end

-- Gathering's kinds as the database names them.
local GATHER_KIND = { herb = "herb", ore = "node" }

local function Rate(part, whole)
    part, whole = tonumber(part), tonumber(whole)
    if not (part and whole and whole >= Search.FOUND_SAMPLE and part > 0) then return nil end
    return math.min(100, part / whole * 100)
end

-- Under FOUND_SAMPLE there is no rate yet, so the drop column says how
-- many it came from instead ("7 in 12"), as the World drops rows do.
local function Count(part, whole)
    part, whole = tonumber(part), tonumber(whole)
    if not (part and whole and part > 0 and whole > 0) or whole >= Search.FOUND_SAMPLE then return nil end
    return L.Format("%1$d in %2$d", part, whole)
end

local function Coords(coords)
    if type(coords) ~= "table" then return nil end
    local x, y = tonumber(coords[1]), tonumber(coords[2])
    if not (x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100) then return nil end
    return { x, y }
end

local function Text(value)
    return type(value) == "string" and value ~= "" and value or nil
end

--- Every item in your own records the database does not know, as search
--- items: { name, id, category, aliases, sources, found = true }.
function Search:FoundItems()
    local key = self:FoundVersion()
    local built = self.found
    if built and built.key == key then return built.items end

    local items, byName = {}, {}
    -- [the data's name] = { known item, spots the data already has, extra spots }
    local extra, knownOf = {}, {}
    local DB = ns.DB
    local Harvest = ns.Harvest

    local function SpotKey(kind, name, zone)
        return ("%s|%s|%s"):format(kind or "", (name or ""):lower(), (zone or ""):lower())
    end

    local function AddKnown(known, source)
        local entry = extra[known.name]
        if not entry then
            entry = { item = known, has = {}, sources = {}, mine = {} }
            for _, have in ipairs(type(known.sources) == "table" and known.sources or {}) do
                -- A Classic row is no reason to leave your own spot out:
                -- yours shows and the Classic one goes (WithYourSpots).
                if type(have) == "table" and have.provenance ~= "classic" then
                    entry.has[SpotKey(have.kind, have.name, have.zone)] = true
                end
            end
            extra[known.name] = entry
        end
        local key = SpotKey(source.kind, source.name, source.zone)
        if entry.has[key] then return end
        entry.has[key] = true
        entry.mine[key] = true
        source.provenance = "forever"
        entry.sources[#entry.sources + 1] = source
    end

    local function Add(name, id, source)
        if type(name) ~= "string" or name == "" or type(source.zone) ~= "string" then return end
        local item = byName[name]
        if item == nil then
            local known = DB:GetItem(name)
            if known then
                byName[name] = false
                knownOf[name] = known
                return AddKnown(known, source)
            end
            if Harvest and Harvest.NameLooksLikeMoney and Harvest:NameLooksLikeMoney(name) then
                byName[name] = false
                return
            end
            item = { name = name, id = tonumber(id), category = L["Your finds"],
                aliases = {}, sources = {}, found = true }
            byName[name] = item
            items[#items + 1] = item
        elseif item == false then
            local known = knownOf[name]
            if known then AddKnown(known, source) end
            return
        end
        item.id = item.id or tonumber(id)
        source.provenance = "forever"
        item.sources[#item.sources + 1] = source
    end

    for _, record in pairs(Harvest and Harvest.records or {}) do
        if type(record) == "table" and type(record.items) == "table" then
            local mob = Harvest.ShowName and Harvest.ShowName(record.mob) or record.mob
            -- An item's random suffixes count as the item (Harvest:GroupedItems).
            local grouped = Harvest.GroupedItems and Harvest:GroupedItems(record) or record.items
            for name, entry in pairs(grouped) do
                if type(entry) == "table" then
                    Add(name, entry.id, { kind = "mob", name = Text(mob), zone = Text(record.zone),
                        location = Text(record.location), coords = Coords(record.coords),
                        minLevel = tonumber(record.minLevel), maxLevel = tonumber(record.maxLevel),
                        chance = Rate(entry.corpses, record.corpses),
                        dropText = Count(entry.corpses, record.corpses) })
                end
            end
        end
    end

    local gathering = ns.db and type(ns.db.gathering) == "table" and ns.db.gathering.nodes
    for _, node in pairs(type(gathering) == "table" and gathering or {}) do
        if type(node) == "table" and type(node.items) == "table" then
            for name, entry in pairs(node.items) do
                if type(entry) == "table" then
                    Add(name, entry.id, { kind = GATHER_KIND[node.kind] or "container",
                        name = Text(node.node), zone = Text(node.zone),
                        location = Text(node.location), coords = Coords(node.coords),
                        chance = Rate(entry.gathers, node.gathers),
                        dropText = Count(entry.gathers, node.gathers) })
                end
            end
        end
    end

    local fishing = ns.db and type(ns.db.fishing) == "table" and ns.db.fishing.spots
    for _, spot in pairs(type(fishing) == "table" and fishing or {}) do
        if type(spot) == "table" and type(spot.items) == "table" then
            local school = ns.Fishing and ns.Fishing.SpotName and ns.Fishing.SpotName(spot) or spot.school
            for name, entry in pairs(spot.items) do
                if type(entry) == "table" then
                    Add(name, entry.id, { kind = "fishing", name = Text(school), zone = Text(spot.zone),
                        location = Text(spot.location), coords = Coords(spot.coords),
                        chance = Rate(entry.casts, spot.casts),
                        dropText = Count(entry.casts, spot.casts) })
                end
            end
        end
    end

    -- What came out of the clams and sacks you opened from your bags: where
    -- you got the clam, from your own kills, and how often one held it.
    local Containers = ns.Containers
    local opened = Containers and ns.db and type(ns.db.containers) == "table"
        and ns.db.containers.opened
    for container, entry in pairs(type(opened) == "table" and opened or {}) do
        entry = Containers:Entry(container)
        if entry and type(entry.items) == "table" then
            local seen = {}
            for _, record in pairs(Harvest and Harvest.records or {}) do
                local dropped = type(record) == "table" and type(record.items) == "table"
                    and record.items[container]
                local zone = type(dropped) == "table" and Text(record.zone)
                if zone and not seen[zone:lower()] then
                    seen[zone:lower()] = true
                    for name, got in pairs(entry.items) do
                        if type(got) == "table" then
                            Add(name, got.id, { kind = "container", name = container, zone = zone,
                                location = Text(record.location), coords = Coords(record.coords),
                                minLevel = tonumber(record.minLevel), maxLevel = tonumber(record.maxLevel),
                                chance = Rate(got.opens, entry.opens),
                                dropText = Count(got.opens, entry.opens) })
                        end
                    end
                end
            end
        end
    end

    table.sort(items, function(a, b) return a.name < b.name end)
    self.found = { key = key, at = GetTime and GetTime() or 0, items = items,
        extra = extra, merged = {} }
    return items
end

--- `item` as the search shows it: the data's item, or, when you found it
--- somewhere the data does not list, a copy with those spots added after
--- the data's own. The database item itself is never changed. Reads what
--- the last Search:FoundItems built.
function Search:WithYourSpots(item)
    local built = self.found
    local entry = built and built.extra and built.extra[item.name]
    if not (entry and entry.item == item and #entry.sources > 0) then return item end
    local copy = built.merged[item.name]
    if copy then return copy end
    copy = {}
    for k, v in pairs(item) do copy[k] = v end
    local sources = {}
    for _, source in ipairs(item.sources or {}) do
        local key = ("%s|%s|%s"):format(source.kind or "", (source.name or ""):lower(), (source.zone or ""):lower())
        if not (source.provenance == "classic" and entry.mine[key]) then sources[#sources + 1] = source end
    end
    for _, source in ipairs(entry.sources) do sources[#sources + 1] = source end
    copy.sources = sources
    built.merged[item.name] = copy
    return copy
end

--- An item's sources (or only `sources`, some of them), lowest level first,
--- so the closest to your level is at the top rather than wherever the data
--- file happened to list it.
function Search:SortedSources(item, sources)
    local sorted = {}
    for index, source in ipairs(sources or item.sources) do
        sorted[index] = source
    end
    -- The best mobs for green gear are already best first.
    if item.keepOrder then return sorted end

    table.sort(sorted, function(a, b)
        local aLow, bLow = a.minLevel or 0, b.minLevel or 0
        if aLow ~= bLow then return aLow < bLow end

        local aHigh, bHigh = a.maxLevel or aLow, b.maxLevel or bLow
        if aHigh ~= bHigh then return aHigh < bHigh end

        return (a.zone or "") < (b.zone or "")
    end)

    return sorted
end

--------------------------------------------------------------------------------
-- Sorting and grouping a search's spots
--
-- A player asked (2026-10-05) to sort by drop rate and by what a kill is
-- worth, to section by zone, and for the spots closest to them. The window's
-- column headings sort each item's spots (UI/Main.lua); with no heading
-- chosen they stay lowest level first, as SortedSources has them.
--
-- "Closest" knows no map distances, so it means: your own zone first, then
-- zones by how near their levels are to yours. A spot with nothing to sort
-- by (no drop rate, no worth) is never guessed at: it goes last, whichever
-- way round the sort runs.
--------------------------------------------------------------------------------

--- The player's level and zone, each nil when the client will not say.
function Search:Here()
    local level
    if UnitLevel then
        local ok, value = pcall(UnitLevel, "player")
        level = ok and ns.Harvest.ReadableNumber(value) or nil
        if level and level <= 0 then level = nil end
    end

    local zone = ns.Harvest and (ns.Harvest:Where()) or nil
    return level, zone
end

--- How far a spot is from you, for "closest": 0 up in your own zone, 1000 up
--- anywhere else, and within either, how many levels its band is from yours
--- (0 inside it). Nil when nothing is known: no zone or level of yours, and
--- no level on the spot.
function Search.Distance(source, level, zone)
    -- Your zone as the client names it, the data's in English (Spots.English
    -- knows the client's name once the map has told it).
    local Spots = ns.Spots
    local here = zone and (source.zone == zone
        or (Spots and Spots.English(source.zone) == Spots.English(zone)))
    local away = here and 0 or 1000

    local low = tonumber(source.minLevel)
    local high = tonumber(source.maxLevel) or low
    local gap = 50
    if level and low then
        if level < low then gap = low - level
        elseif level > high then gap = level - high
        else gap = 0 end
    elseif not zone then
        return nil
    end

    return away + gap
end

--- What a kill of the spot's mob is worth, and how sure: 2 your own tally,
--- 1 an estimate from the database's rates, nil no worth (not a mob, or
--- nothing priced). `cache` keeps each mob's answer for one draw.
function Search:Worth(source, cache)
    if not (source.name and (source.kind or "mob") == "mob" and ns.Value) then return nil end

    cache = cache or {}
    local known = cache[source.name]
    if known == nil then
        local worth, details = ns.Value:ForMob(source.name)
        known = worth and { worth = worth, sure = details and details.basis == "tally" and 2 or 1 } or false
        cache[source.name] = known
    end

    if not known then return nil end
    return known.worth, known.sure
end

-- The headings a search can be sorted by, and which way each starts:
-- names A to Z, levels and distance lowest first, rates and worth highest.
Search.SORT_KEYS = { name = true, where = true, level = true, drop = true, value = true }
Search.SORT_STARTS_LOW = { name = true, where = true, level = true }

--- `sources` (already lowest level first) in the order `sort` asks for:
--- { key = one of SORT_KEYS, ascending = true or false }, or nil to leave
--- them as they are. Ties, and spots with nothing to sort by, keep the order
--- they came in, the second lot after the rest.
function Search:SortSources(sources, sort, cache)
    local key = sort and sort.key
    if not (key and Search.SORT_KEYS[key]) then return sources end

    local level, zone = self:Here()
    local ascending = sort.ascending and true or false

    local keyed = {}
    for index, source in ipairs(sources) do
        local value, rank
        if key == "name" then
            value = (source.name or source.requires or ns.DB:KindLabel(source.kind) or ""):lower()
        elseif key == "where" then
            value = Search.Distance(source, level, zone)
        elseif key == "level" then
            value = tonumber(source.minLevel)
        elseif key == "drop" then
            value = tonumber(source.chance)
        elseif key == "value" then
            value, rank = self:Worth(source, cache)
        end
        keyed[index] = { source = source, value = value, rank = rank or 0, position = index }
    end

    table.sort(keyed, function(a, b)
        if (a.value == nil) ~= (b.value == nil) then return b.value == nil end
        if a.value == nil then return a.position < b.position end

        -- Your own tally's worth is never ranked in with an estimate's:
        -- estimates leave out coin and run low (Rankings keeps them apart
        -- the same way). Measured ones come first either way round.
        if a.rank ~= b.rank then return a.rank > b.rank end

        if a.value ~= b.value then
            if ascending then return a.value < b.value end
            return a.value > b.value
        end
        return a.position < b.position
    end)

    local sorted = {}
    for index, entry in ipairs(keyed) do sorted[index] = entry.source end
    return sorted
end

--- `sources` sectioned by zone: { { zone, sources = {...} }, ... }, the zones
--- in the order their first spot comes in, so whatever the spots are sorted
--- by, the zone with the best of them leads.
function Search.ByZone(sources)
    local groups, index = {}, {}
    for _, source in ipairs(sources) do
        local zone = source.zone or "?"
        local group = index[zone]
        if not group then
            group = { zone = zone, sources = {} }
            index[zone] = group
            groups[#groups + 1] = group
        end
        group.sources[#group.sources + 1] = source
    end
    return groups
end

function Search:LevelText(source)
    if not source.minLevel then return "??" end

    if source.maxLevel and source.maxLevel ~= source.minLevel then
        return ("%d-%d"):format(source.minLevel, source.maxLevel)
    end

    return tostring(source.minLevel)
end

--- A database drop rate as a line gives it: "~4%", or "<1%" for a rare
--- drop, which "%d" printed as "0%".
function Search:ChanceText(chance)
    local text = ns.Tracker.FormatChance(chance)
    if chance < 1 then return text end
    return "~" .. text
end

--- "12 spots", or "3 of 12 spots" when only some of them are shown.
function Search:SpotsText(shown, total)
    if shown < total then
        return L.Format("%d of %d spots", shown, total)
    end
    return Util.Plural(total, L["spot"], L["spots"])
end

--- One source as a line, e.g.
---   [10-20] Westfall - Copper Vein (mining node, needs Mining 1)
--- A source with no name of its own -- a herb node, which is just called after
--- the herb -- drops the name rather than printing the kind twice.
function Search:SourceLine(source)
    local detail = ns.DB:KindLabel(source.kind)

    if source.requires then
        detail = L.Format("%s, needs %s", detail, source.requires)
    end

    if source.chance then
        detail = ("%s, %s"):format(detail, self:ChanceText(source.chance))
    elseif source.dropText then
        detail = ("%s, %s"):format(detail, source.dropText)
    end

    local line = ("%s %s"):format(
        Util.Colored("muted", "[" .. self:LevelText(source) .. "]"), source.zone)

    if source.name then
        line = line .. Util.Colored("muted", " - ") .. source.name
    end

    local where = ns.DB:WhereText(source)
    if where then
        line = line .. Util.Colored("muted", " @ ") .. where
    end

    line = line .. " " .. Util.Colored("accent", "(" .. detail .. ")")

    -- Classic Era marks no row [Forever] (docs/CLASSIC_DIFFERENCES.md).

    if source.note then
        line = line .. " " .. Util.Colored("muted", source.note)
    end

    return line
end

--- `shown` is how many of its spots are listed under it, when not all.
function Search:ItemHeader(item, shown)
    return ("%s %s"):format(
        Util.Colored("text", item.name),
        Util.Colored("muted", ("(%s, %s)"):format(
            item.category, self:SpotsText(shown or #item.sources, #item.sources))))
end

--- What an empty search says. When the hide list is what emptied it, it
--- says so, rather than that nothing is known.
function Search:NothingFoundText(query)
    if self.hidHit then
        return L.Format("Everything that matches \"%s\" is on your hide list (/farm hidden).", query)
    end
    return L.Format('Nothing found for "%s". Try part of a name, a zone, or a category.', query)
end

--- Flat display lines for a query, shared by the window and `/farm chat`.
-- @return lines, total number of matching items
function Search:BuildLines(query, maxItems)
    local results = self:Run(query)
    local total = #results
    local lines = {}

    maxItems = maxItems or 12

    if total == 0 then
        lines[1] = Util.Colored("muted", self:NothingFoundText(query))
        return lines, 0
    end

    local shown = math.min(total, maxItems)

    for index = 1, shown do
        local result = results[index]
        local item = result.item
        local sources = self:SortedSources(item, result.sources)

        lines[#lines + 1] = self:ItemHeader(item, #sources)

        if item.note then
            lines[#lines + 1] = "  " .. Util.Colored("muted", item.note)
        end

        for _, source in ipairs(sources) do
            lines[#lines + 1] = "  " .. self:SourceLine(source)
        end

        if index < shown then
            lines[#lines + 1] = " "
        end
    end

    if total > shown then
        lines[#lines + 1] = " "
        lines[#lines + 1] = Util.Colored("muted",
            L.Format("... and %d more. Narrow the search to see them.", total - shown))
    end

    return lines, total
end

--------------------------------------------------------------------------------
-- Rows for the window
--
-- The window draws columns rather than sentences, so it needs the parts, not a
-- formatted string. Chat still gets BuildLines above, because a chat frame has
-- no columns to draw into.
--------------------------------------------------------------------------------

--- @param opts { max = item cap, kind = only this source kind, sort = { key,
---   ascending } (SortSources), byZone = a "zone" row over each zone's spots }
-- @return rows, matching item count, total sources drawn
function Search:BuildRows(query, opts)
    opts = opts or {}

    local maxItems = opts.max or 40
    local rows = {}
    local total, drawn = 0, 0
    -- The caller's per-draw worth cache, when it has one, so a mob priced
    -- for the sort is not priced again for the row.
    local worth = opts.worth or {}

    -- The kind filter comes before the cap. Capped first, a chip could show
    -- nothing but "and 55 more items" while its kind sat further down.
    for _, result in ipairs(self:Run(query)) do
        local item = result.item
        local sources = self:SortedSources(item, result.sources)

        -- A kind filter that empties an item hides the item too, rather than
        -- leaving a heading with nothing under it.
        if opts.kind then
            local kept = {}
            for _, source in ipairs(sources) do
                if source.kind == opts.kind then
                    kept[#kept + 1] = source
                end
            end
            sources = kept
        end

        if #sources > 0 then
            total = total + 1
        end

        -- Past the cap an item is only counted, for the "more" line.
        if #sources > 0 and total <= maxItems then
            rows[#rows + 1] = { type = "item", item = item, count = #sources }

            if item.note then
                rows[#rows + 1] = { type = "note", text = item.note }
            end

            sources = self:SortSources(sources, opts.sort, worth)

            if opts.byZone then
                for _, group in ipairs(Search.ByZone(sources)) do
                    rows[#rows + 1] = { type = "zone", item = item, zone = group.zone,
                        count = #group.sources }
                    for _, source in ipairs(group.sources) do
                        rows[#rows + 1] = { type = "source", item = item, source = source }
                        drawn = drawn + 1
                    end
                end
            else
                for _, source in ipairs(sources) do
                    rows[#rows + 1] = { type = "source", item = item, source = source }
                    drawn = drawn + 1
                end
            end
        end
    end

    if total > maxItems then
        rows[#rows + 1] = {
            type = "more",
            text = L.Format("and %d more items. Narrow the search to see them.", total - maxItems),
        }
    end

    return rows, total, drawn
end

--- Which source kinds a query actually turns up, so the filter chips can show
--- only the ones worth clicking.
function Search:KindsInResults(query)
    local seen, order = {}, {}

    for _, result in ipairs(self:Run(query)) do
        for _, source in ipairs(result.sources or result.item.sources) do
            if not seen[source.kind] then
                seen[source.kind] = true
                order[#order + 1] = source.kind
            end
        end
    end

    table.sort(order)
    return order
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

--- `/farm <text>`: search, and show the results in the window.
function ns.RunSearch(query)
    query = Util.Trim(query)
    if query == "" then return end

    if ns.UI and ns.UI.Search then
        ns.UI:Search(query)
    else
        ns.Search:PrintResults(query)
    end
end

-- The kinds of material the search window suggests for your level, in the
-- order it shows them.
Search.SUGGEST_CATEGORIES = { "Cloth", "Leatherworking", "Mining", "Herbalism" }

--- One item per suggested category that suits a character of `level`: the
--- one with the most places whose level band takes it in. Nothing for a
--- category where no band does. For the empty search window. With your
--- gathering skills (`skills`, Spots.Skills; read here when not given), a
--- node or herb a profession you have cannot take yet is not counted, so a 20-Mining
--- miner is never offered Mithril.
function Search:ForLevel(level, skills)
    level = tonumber(level) or 0
    if level <= 0 then return {} end
    if skills == nil and ns.Spots and ns.Spots.Skills then
        local ok, read = pcall(ns.Spots.Skills)
        skills = ok and read or nil
    end
    local player = skills and { skills = skills } or nil

    local best = {}

    for item in ns.DB:Iterate() do
        local fits = 0
        if ns.DB:HidesItem(item) then fits = -1 end
        for _, source in ipairs(item.sources) do
            local low = tonumber(source.minLevel)
            local high = tonumber(source.maxLevel) or (low and low + 10)
            local profession, needed, have
            if player then profession, needed, have = ns.Spots.SkillNeed(source, player) end
            local canGather = not profession or have == nil or have >= needed
            if fits >= 0 and canGather and low and low <= level and level <= high then fits = fits + 1 end
        end

        local pick = best[item.category]
        if fits > 0 and (not pick or fits > pick.fits) then
            best[item.category] = { item = item, fits = fits }
        end
    end

    local picks = {}
    for _, category in ipairs(self.SUGGEST_CATEGORIES) do
        if best[category] then picks[#picks + 1] = best[category].item end
    end
    return picks
end

function Search:PrintResults(query)
    local lines, total = self:BuildLines(query, 5)

    ns.Print(L.Format("results for %s (%s):",
        Util.Colored("accent", query), Util.Plural(total, L["item"], L["items"])))

    for _, line in ipairs(lines) do
        if Util.Trim(Util.StripColor(line)) ~= "" then
            ns.PrintRaw(line)
        end
    end
end

ns.RegisterCommand("chat", L["print results to chat instead of the window"], function(rest)
    if Util.Trim(rest) == "" then
        ns.Print(L["usage: /farm chat <text>"])
        return
    end
    ns.Search:PrintResults(rest)
end)

-- Skinning shown or left out (DB:SetShowSkinning, the Settings row "Show
-- skinning").
ns.RegisterCommand("skinning", L["show skinning, or leave it out and show only drops: on or off"], function(rest)
    local word = Util.Trim(rest or ""):lower()
    local on
    if word == "on" or word == "show" then
        on = true
    elseif word == "off" or word == "hide" then
        on = false
    else
        on = not ns.DB:ShowsSkinning()
    end
    ns.DB:SetShowSkinning(on)
    ns.Print(on and L["skinning is shown again."]
        or L["skinning is hidden, so you only see drops. /farm skinning brings it back."])
    if ns.SettingsUI then ns.SettingsUI:Refresh() end
end)

ns.RegisterCommand("stats", L["how much data is loaded"], function()
    ns.Print(L.Format("%s, %s loaded",
        Util.Plural(ns.DB:CountItems(), L["item"], L["items"]),
        Util.Plural(ns.DB:CountSources(), L["farming spot"], L["farming spots"])))
end)

ns.RegisterCommand("data", L["where the data came from"], function()
    local counts = ns.DB:CountByProvenance()

    ns.Print(L["data sources:"])

    for key, label in pairs(ns.DB.PROVENANCE) do
        ns.PrintRaw(("  %s  %s"):format(
            Util.Colored(key == "forever" and "good" or "muted",
                Util.Plural(counts[key] or 0, L["spot"], L["spots"])),
            Util.Colored("muted", label)))
    end
end)

ns.RegisterCommand("list", L["list every item in the database"], function()
    ns.Print(L.Format("Farmer knows %s:", Util.Plural(ns.DB:CountItems(), L["item"], L["items"])))

    local row = {}
    for item in ns.DB:Iterate() do
        row[#row + 1] = item.name

        if #row == 4 then
            ns.PrintRaw("  " .. table.concat(row, ", "))
            row = {}
        end
    end

    if #row > 0 then
        ns.PrintRaw("  " .. table.concat(row, ", "))
    end
end)
