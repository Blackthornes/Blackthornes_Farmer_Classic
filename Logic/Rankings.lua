-- Blackthornes Farmer -- Logic/Rankings.lua
-- Every mob we can put a value on, best first: what is worth farming?
--
-- The worth of a kill is Value:ForMob's number, nothing new. What this adds is
-- the ordering, and keeping two kinds of number apart that must never be
-- ranked against each other:
--
--   measured   your own tally, MIN_KILLS kills or more, coin included;
--   estimate   the database's drop rates, one of each item, no coin.
--
-- An estimate leaves coin out and assumes one of each drop, so it runs low; put
-- in one list with measured values it would sink below mobs that are worth
-- less. So each is ranked on its own, measured first.
--
-- A mob you have killed but not enough times to value, and with no estimate
-- either, is not ranked at all. It is listed with how many kills it still
-- needs, since that is the way onto the board.

local _, ns = ...
local L = ns.L

local Rankings = ns.NewModule("Rankings")

-- Kinds whose `name` is a creature. A node or a school has no kill to value.
local CREATURE_KINDS = { mob = true, skinning = true }

--- Every mob name the database gives a drop rate for.
local function RatedMobs(names)
    for name, entries in pairs(ns.DB:ByName()) do
        for _, entry in ipairs(entries) do
            local source = entry.source
            if source.chance and CREATURE_KINDS[source.kind or "mob"] then
                names[name] = true
                break
            end
        end
    end
end

--- Where the database puts a mob and at what level: the lowest band first,
--- as the search lists it. Nil when the database does not know the mob.
function Rankings:Spot(mobName)
    -- One zone's line of a mob (Tracker's "One line a zone") looks in that
    -- zone first.
    local name, zone = ns.Tracker.SplitKey(mobName)
    local best, here

    for _, entry in ipairs(ns.DB:ByName()[name] or {}) do
        local source = entry.source
        -- Classic's generated rows are for the search (Data_ClassicDrops).
        if CREATURE_KINDS[source.kind or "mob"] and not source.searchOnly then
            if not best or (source.minLevel or 0) < (best.minLevel or 0) then
                best = source
            end
            if zone and source.zone == zone
                and (not here or (source.minLevel or 0) < (here.minLevel or 0)) then
                here = source
            end
        end
    end

    return here or best
end

--- The levels you met a mob at, from your own loot records: { min, max } by
--- mob name. Laid out once and kept until a corpse is recorded
--- (Harvest.changes) or LEVELS_KEEP seconds pass, since the board asks for
--- every mob in one go. A mob the database has no row for (most of what the
--- shipped data leaves out) still gets a level this way.
Rankings.LEVELS_KEEP = 60

function Rankings:OwnLevels()
    local Harvest = ns.Harvest
    local changes = Harvest and Harvest.changes or 0
    local now = GetTime and GetTime() or 0
    local kept = self.ownLevels
    if kept and kept.changes == changes and now - kept.at < self.LEVELS_KEEP then
        return kept.levels
    end

    -- By name, and by each zone's line key, for a mob split by zone.
    local levels = {}
    local function Note(key, low, high)
        local seen = levels[key]
        if seen then
            seen.min = math.min(seen.min, low)
            seen.max = math.max(seen.max, high)
        else
            levels[key] = { min = low, max = high }
        end
    end
    for _, record in pairs(Harvest and Harvest.records or {}) do
        local mob, low, high = record.mob, tonumber(record.minLevel), tonumber(record.maxLevel)
        if type(mob) == "string" and low then
            high = high or low
            Note(mob, low, high)
            if type(record.zone) == "string" then
                Note(ns.Tracker.ZoneKey(mob, record.zone), low, high)
            end
        end
    end

    self.ownLevels = { changes = changes, at = now, levels = levels }
    return levels
end

--- A mob's level for the board: "18-19". The levels you met it at first,
--- like where you farm it, else the database's, else nil.
--- Returns the text and the lowest level, for sorting.
function Rankings:LevelFor(mobName, spot)
    local levels = self:OwnLevels()
    local own = levels[mobName] or levels[ns.Tracker.NameOf(mobName)]
    if own then
        return ns.Search:LevelText({ minLevel = own.min, maxLevel = own.max }), own.min
    end
    if spot and spot.minLevel then
        return ns.Search:LevelText(spot), tonumber(spot.minLevel)
    end
    return nil, nil
end

--------------------------------------------------------------------------------
-- Outside dungeons only
--------------------------------------------------------------------------------

-- The owner asked (2026-10-14) for a tick box on Rankings that leaves out mobs
-- found only in dungeons. Off unless ticked, kept in `rankingsOutside`
-- (account wide, never rename it). The rank-up pop-up and the top farm
-- alert after an auction scan rank the same board, so they follow it too.

--- Moves whenever the tick box does, so what was laid out for the other
--- answer is laid out again (RankUp).
Rankings.outsideVersion = 0

function Rankings.OutsideOnly()
    return ns.db ~= nil and ns.db.rankingsOutside == true
end

function Rankings:SetOutsideOnly(on)
    if not ns.db then return end
    on = on and true or false
    if (ns.db.rankingsOutside == true) == on then return end
    ns.db.rankingsOutside = on
    self.outsideVersion = self.outsideVersion + 1
    -- The rank-up order sees the version move and is laid out again.
    if ns.RankingsUI then ns.RankingsUI:Refresh() end
end

--------------------------------------------------------------------------------
-- Skip Uncommon and better
--------------------------------------------------------------------------------

-- The owner asked (2026-10-18) for a tick box on Rankings that leaves
-- Uncommon, Rare and Epic drops out of what a kill is worth, so the board
-- ranks what a mob gives every time. Off unless ticked, kept in
-- `rankingsSkipUncommon` (account wide, never rename it). It moves
-- `outsideVersion` too, so the rank-up order is laid out again.

function Rankings.SkipUncommon()
    return ns.db ~= nil and ns.db.rankingsSkipUncommon == true
end

function Rankings:SetSkipUncommon(on)
    if not ns.db then return end
    on = on and true or false
    if (ns.db.rankingsSkipUncommon == true) == on then return end
    ns.db.rankingsSkipUncommon = on
    self.outsideVersion = self.outsideVersion + 1
    if ns.RankingsUI then ns.RankingsUI:Refresh() end
end

--- Is a priced drop Uncommon or better? Its loot link's colour, else the
--- client's quality. A drop whose quality is not known yet stays in.
function Rankings.IsUncommonOrBetter(drop)
    local WorldDrops = ns.WorldDrops
    if not (WorldDrops and WorldDrops.QualityOf and drop) then return false end
    local id = drop.id
    if not id and ns.Tracker and ns.Tracker.LookOf then id = ns.Tracker:LookOf(drop.name).id end
    if not id and ns.Value.ItemID then id = ns.Value:ItemID(drop.name) end
    local quality = WorldDrops.QualityOf(id, drop.lookName or drop.name)
    return type(quality) == "number" and quality >= 2
end

--- A worth and its details with Uncommon and better drops taken out: coin
--- and the drops left. A fresh details table; the one given is untouched.
function Rankings.WithoutUncommon(value, details)
    local kept = {}
    for key, field in pairs(details) do kept[key] = field end
    kept.priced = {}
    local total = tonumber(details.coin) or 0
    for _, drop in ipairs(details.priced or {}) do
        if not Rankings.IsUncommonOrBetter(drop) then
            kept.priced[#kept.priced + 1] = drop
            total = total + (drop.perKill or 0)
        end
    end
    if #kept.priced == #(details.priced or {}) then return value, details end
    return total, kept
end

--------------------------------------------------------------------------------
-- Vendor only
--------------------------------------------------------------------------------

-- The owner said build it (2026-10-27, from a mockup): a tick box on Rankings
-- that counts every drop at what a vendor pays, never the auction house, so
-- the board ranks what a kill sells for at a vendor. Coin still counts. Off
-- unless ticked, kept in `rankingsVendorOnly` (account wide, never rename
-- it). It moves `outsideVersion` too, so the rank-up order is laid out again.

function Rankings.VendorOnly()
    return ns.db ~= nil and ns.db.rankingsVendorOnly == true
end

function Rankings:SetVendorOnly(on)
    if not ns.db then return end
    on = on and true or false
    if (ns.db.rankingsVendorOnly == true) == on then return end
    ns.db.rankingsVendorOnly = on
    self.outsideVersion = self.outsideVersion + 1
    if ns.RankingsUI then ns.RankingsUI:Refresh() end
end

--- What a vendor pays for one of a priced drop, or nil when none does.
function Rankings.VendorPriceOf(drop)
    if drop.from == "vendor" then return drop.unit end
    local id = drop.id
    if not id and ns.Tracker and ns.Tracker.LookOf then id = ns.Tracker:LookOf(drop.name).id end
    if not id and ns.Value.ItemID then id = ns.Value:ItemID(drop.name) end
    local vendor = id and ns.Value:VendorPrice(id)
    return (type(vendor) == "number" and vendor > 0) and vendor or nil
end

--- A worth and its details with every drop at what a vendor pays: coin and
--- the drops a vendor buys, best first. A drop no vendor buys leaves. A
--- fresh details table; the one given is untouched.
function Rankings.AtVendor(value, details)
    local kept = {}
    for key, field in pairs(details) do kept[key] = field end
    kept.priced = {}
    local total = tonumber(details.coin) or 0
    for _, drop in ipairs(details.priced or {}) do
        local vendor = Rankings.VendorPriceOf(drop)
        local unit = tonumber(drop.unit)
        if vendor and unit and unit > 0 then
            local copy = {}
            for key, field in pairs(drop) do copy[key] = field end
            copy.perKill = (drop.perKill or 0) / unit * vendor
            copy.unit, copy.from = vendor, "vendor"
            kept.priced[#kept.priced + 1] = copy
            total = total + copy.perKill
        end
    end
    table.sort(kept.priced, function(a, b) return a.perKill > b.perKill end)
    return total, kept
end

--- The zone part of a kill's place, "The Sepulcher, Silverpine Forest":
--- the zone the client named (GetRealZoneText), which inside a dungeon is
--- the dungeon.
local function PlaceZone(place)
    return ns.Tracker.PlaceZone(place)
end

--- Is a database row for a mob inside a dungeon? A row from Classic's data
--- names the dungeon as its subzone ("The Deadmines" in Westfall). A row
--- recorded in game has the dungeon as its zone; its subzone is the open
--- world's when the zone is not (Ruins of Lordaeron in Tirisfal Glades).
local function SourceInside(source)
    local Spots = ns.Spots
    if Spots.IsInstance(source.zone) then return true end
    return (source.provenance or "classic") == "classic" and Spots.IsInstance(source.location)
end

--- Is `mobName` found only in dungeons and raids? Told by where your kills
--- of it were (every kill with a place inside one), else by where the
--- database puts it (every place inside one). A mob neither tells about,
--- killed before places were kept and not in the data, counts as outside.
function Rankings:InDungeon(mobName)
    local Spots = ns.Spots
    -- One zone's line is inside when its zone is.
    local name, zone = ns.Tracker.SplitKey(mobName)
    if zone then return Spots.IsInstance(zone) and true or false end
    local places = ns.Tracker:Places(mobName)
    if #places > 0 then
        for _, place in ipairs(places) do
            if not Spots.IsInstance(PlaceZone(place.name)) then return false end
        end
        return true
    end

    local any = false
    for _, entry in ipairs(ns.DB:ByName()[name] or {}) do
        local source = entry.source
        if CREATURE_KINDS[source.kind or "mob"] then
            if not SourceInside(source) then return false end
            any = true
        end
    end
    return any
end

--- Is `mobName` left off the board? Hidden, or in a dungeon while the tick
--- box says outside only.
function Rankings:LeftOut(mobName)
    local Tracker = ns.Tracker
    local name, zone = Tracker.SplitKey(mobName)
    if ns.DB:IsHiddenSource(name) then return true end
    -- A name killed in two zones is ranked a line a zone, never as a whole.
    if not zone and Tracker:IsSplit(name) then return true end
    return self.OutsideOnly() and self:InDungeon(mobName)
end

--- One entry for a mob, or nil when it is on no list.
function Rankings:Entry(mobName)
    local value, details = ns.Value:ForMob(mobName)
    if value and self.SkipUncommon() then value, details = self.WithoutUncommon(value, details) end
    if value and self.VendorOnly() then value, details = self.AtVendor(value, details) end
    local summary = ns.Tracker:Summary(mobName)
    local spot = self:Spot(mobName)

    local entry = {
        mob = mobName,
        value = value,
        details = details,
        kills = summary and summary.kills or 0,
        needed = summary and summary.needed or 0,
        spot = spot,
    }
    entry.level, entry.minLevel = self:LevelFor(mobName, spot)

    -- Where you farm it beats where the database says it lives.
    local places = summary and summary.places
    if places and places[1] then
        entry.where = places[1].name
    elseif spot then
        local landmark = ns.DB:WhereText(spot)
        local zone = ns.Spots.Show(spot.zone)
        entry.where = landmark and (zone .. ", " .. landmark) or zone
    end

    if value then
        entry.group = details.basis == "tally" and "measured" or "estimate"
        entry.best = details.priced[1]
    elseif summary and summary.kills > 0 then
        -- Enough kills but nothing priced: it waits on prices, not kills.
        entry.group = "pending"
        entry.unpriced = summary.rated
    else
        return nil
    end

    return entry
end

--- The board: { measured = {...}, estimate = {...}, pending = {...} }, each
--- entry { mob, value, details, kills, needed, where, level, best, rank }.
-- Measured and estimates are ranked by worth per kill; pending by how close
-- each is to MIN_KILLS.
function Rankings:Build()
    local names = {}

    -- A line for each zone of a name killed in more than one.
    for key in pairs(ns.Tracker:Tallies()) do
        if type(key) == "string" then names[key] = true end
    end
    RatedMobs(names)

    local board = { measured = {}, estimate = {}, pending = {} }

    for name in pairs(names) do
        -- A mob on the hide list is not ranked (DB:IsHiddenSource), nor a
        -- dungeon's with "Outside dungeons only" ticked.
        local entry = not self:LeftOut(name) and self:Entry(name)
        if entry then
            local list = board[entry.group]
            list[#list + 1] = entry
        end
    end

    local function ByValue(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.mob < b.mob
    end

    table.sort(board.measured, ByValue)
    table.sort(board.estimate, ByValue)
    table.sort(board.pending, function(a, b)
        if a.needed ~= b.needed then return a.needed < b.needed end
        return a.mob < b.mob
    end)

    for _, group in ipairs({ "measured", "estimate" }) do
        for rank, entry in ipairs(board[group]) do
            entry.rank = rank
        end
    end

    return board
end

ns.RegisterCommand("rankings", L["mobs ranked by what a kill is worth, or only those outside dungeons"], function(arg)
    local word, value = (arg or ""):lower():match("^(%S*)%s*(%S*)")
    if word == "outside" then
        if value == "on" or value == "off" then
            Rankings:SetOutsideOnly(value == "on")
        else
            Rankings:SetOutsideOnly(not Rankings.OutsideOnly())
        end
        ns.Print(Rankings.OutsideOnly() and L["Rankings show only mobs outside dungeons."]
            or L["Rankings show mobs from dungeons too."])
        if ns.SettingsUI then ns.SettingsUI:Refresh() end
        return
    end
    if word == "uncommon" then
        if value == "on" or value == "off" then
            Rankings:SetSkipUncommon(value == "on")
        else
            Rankings:SetSkipUncommon(not Rankings.SkipUncommon())
        end
        ns.Print(Rankings.SkipUncommon() and L["Rankings leave Uncommon and better drops out of worth per kill."]
            or L["Rankings count every drop in worth per kill."])
        if ns.SettingsUI then ns.SettingsUI:Refresh() end
        return
    end
    if word == "vendor" then
        if value == "on" or value == "off" then
            Rankings:SetVendorOnly(value == "on")
        else
            Rankings:SetVendorOnly(not Rankings.VendorOnly())
        end
        ns.Print(Rankings.VendorOnly() and L["Rankings count every drop at what a vendor pays."]
            or L["Rankings count drops at their best price."])
        if ns.SettingsUI then ns.SettingsUI:Refresh() end
        return
    end
    ns.UI:Show()
    ns.UI:ShowTab("rankings")
end)

-- The short form, kept out of the help list so it is not there twice.
ns.commands.rank = ns.commands.rankings
