-- Blackthornes Farmer -- Logic/Fishing.lua
-- What you catch, where you caught it, and how often.
--
-- The harvester and the kill tally both see a fishing catch and turn it away:
-- there is no corpse to pin it on. This is where it goes instead. Every
-- fishing loot window is one cast that landed something, counted against the
-- spot it was cast at: the zone, the subzone, and the school if you cast into
-- one. How often an item came up is casts that held it over casts there.
--
-- Below MIN_CASTS a spot shows counts, never percentages, the same rule and
-- the same number as kills.
--
-- Schools. The client does not tell an addon whether the bobber landed in a
-- school, so a cast is put down to a school only when you had your mouse over
-- one just before you started casting, or when you are recasting from the
-- same spot, facing the same way, as a cast that was. Anything less certain
-- is open water: open water is never put down to a school on a guess. The
-- cost is the other way round -- fish a school without ever mousing over it
-- and its catch lands in open water -- so mouse over a school once before
-- fishing it.
--
-- A fish that gets away opens no loot window, so it is not counted anywhere.
-- Your fishing skill is noted with each spot, as the lowest and highest you
-- had while fishing there.
--
-- Everything is kept in saved variables. Nothing is sent anywhere.

local _, ns = ...
local L = ns.L

local Fishing = ns.NewModule("Fishing")

local Util = ns.Util

-- Same threshold as kills and the harvest export, for the same reason.
local MIN_CASTS = 20

-- How long after your mouse leaves a school a cast still counts as into it.
-- Long enough to move the mouse off and press the key; short enough that a
-- school looked at a minute ago does not claim a cast somewhere else.
local HOVER_SECONDS = 8

-- What a spot is called when no school was under the mouse.
local OPEN_WATER = "open water"

Fishing.MIN_CASTS = MIN_CASTS
Fishing.OPEN_WATER = OPEN_WATER

-- A gap longer than this between two casts at the same spot is a break, not
-- fishing, so it never counts toward what an hour is worth.
Fishing.BREAK = 300
-- Time counted at a spot before an hour's worth is shown.
Fishing.MIN_SECONDS = 600

-- A spot's name as shown: open water in the client's words, a school as the
-- client named it. The kept name stays English (OPEN_WATER).
local function Shown(name)
    if name == OPEN_WATER then return L["open water"] end
    return name
end

-- The same, for the windows: the Grind tab's Fish view shows spot names.
Fishing.ShowName = Shown

-- This session only: casts per spot, the order spots were last fished in, and
-- how many casts in all. The panel's Fishing section shows only while
-- `sessionCasts` is above zero. `sessionCatch` is how many of each item came
-- up, for the session's gathered value.
Fishing.session = {}
Fishing.sessionCatch = {}
Fishing.recent = {}
Fishing.clock = 0
Fishing.sessionCasts = 0

--------------------------------------------------------------------------------
-- Schools
--------------------------------------------------------------------------------

-- Every fishing school in the game, by the endings their names share.
-- "Oily Blackmouth School", "Stonescale Eel Swarm", "Floating Wreckage",
-- "Patch of Elemental Water", "Lesser Floating Debris", "Oil Spill".
local SCHOOL_PATTERNS = {
    " School$",
    " Swarm$",
    "Wreckage$",
    "Floating Debris$",
    "Elemental Water$",
    "Churning Waters$",
    "^Oil Spill$",
}

--- Is `name` a fishing school's name?
function Fishing.IsSchool(name)
    if type(name) ~= "string" or name == "" then return false end

    for _, pattern in ipairs(SCHOOL_PATTERNS) do
        if name:find(pattern) then return true end
    end

    return false
end

--- The client's clock in seconds, or nil if it will not say.
local function Now()
    if type(GetTime) ~= "function" then return nil end
    local ok, now = pcall(GetTime)
    return ok and ns.Harvest.ReadableNumber(now) or nil
end

--- The game tooltip just showed: if it is a school, remember which and when.
--
-- A unit or an item tooltip is never a school, whatever it is called: a mob
-- named "... Swarm" must not pass for one.
function Fishing:OnTooltipShown(unitOrItem)
    local tooltip = GameTooltip
    if not tooltip then return end

    if unitOrItem == nil then unitOrItem = ns.Harvest.TooltipShowsUnitOrItem(tooltip) end
    if unitOrItem then return end

    local line = _G.GameTooltipTextLeft1
    if not line or type(line.GetText) ~= "function" then return end

    local ok, text = pcall(line.GetText, line)
    local name = ok and ns.Harvest.Readable(text) or nil

    if name and Fishing.IsSchool(name) then
        self.hovered = { name = name, at = Now() }
    end
end

--- Which way you are facing, in radians, or nil if the client will not say.
local function Facing()
    if type(GetPlayerFacing) ~= "function" then return nil end
    local ok, facing = pcall(GetPlayerFacing)
    return ok and ns.Harvest.ReadableNumber(facing) or nil
end

-- How far "the same place, facing the same way" stretches: map percent and
-- radians. Standing still reads back exactly; this only absorbs rounding.
local SAME_SPOT = 0.05
local SAME_FACING = 0.02

--- A channel just started: if it is you, work out which school it is into.
--
-- Fishing is a channel, so this is the moment the cast leaves the rod. Any
-- other channel is overwritten by the next one; only a fishing cast is ever
-- followed by a fishing loot window.
--
-- A school counts when it was under the mouse in the last HOVER_SECONDS. Past
-- that, a cast still goes to the school the last one went to if you have not
-- moved or turned since: that is recasting into the same school, which you
-- do from a key without mousing over it again. Move or turn and it is open
-- water until you mouse over a school again.
function Fishing:OnChannelStart(unit)
    if ns.Harvest.Readable(unit) ~= "player" then return end

    local school
    local hovered = self.hovered
    local now = Now()
    local x, y = ns.Harvest:PlayerPosition()
    local facing = Facing()

    if hovered and hovered.at and now and now - hovered.at <= HOVER_SECONDS then
        school = hovered.name
    else
        local last = self.lastSchool
        if last and x and facing
            and math.abs(last.x - x) <= SAME_SPOT and math.abs(last.y - y) <= SAME_SPOT
            and math.abs(last.facing - facing) <= SAME_FACING then
            school = last.name
        end
    end

    -- Remembered only with a place and a facing to hold the next cast to.
    if school and x and facing then
        self.lastSchool = { name = school, x = x, y = y, facing = facing }
    else
        self.lastSchool = nil
    end

    self.cast = { school = school }
end

--------------------------------------------------------------------------------
-- Fishing skill
--------------------------------------------------------------------------------

--- Your fishing skill, or nil if the client will not say.
--
-- A retail engine answers through GetProfessions, a classic one through the
-- skill lines. Forever is the first with the content of the second, so both
-- are tried.
function Fishing:Skill()
    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        local ok, fishing = pcall(function() return select(4, GetProfessions()) end)
        local index = ok and ns.Harvest.ReadableNumber(fishing) or nil

        if index then
            local gotInfo, rank = pcall(function()
                return select(3, GetProfessionInfo(index))
            end)
            local skill = gotInfo and ns.Harvest.ReadableNumber(rank) or nil
            if skill and skill > 0 then return skill end
        end
    end

    if type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function" then
        local ok, lines = pcall(GetNumSkillLines)
        local count = ok and ns.Harvest.ReadableNumber(lines) or nil

        for index = 1, count or 0 do
            local gotLine, lineName, isHeader, _, rank = pcall(GetSkillLineInfo, index)
            local name = gotLine and not isHeader and ns.Harvest.Readable(lineName) or nil

            -- "Angeln" on a German client: the client's own name for it.
            if name and ns.Gathering.SkillOf(name, { "Fishing" }) then
                local skill = ns.Harvest.ReadableNumber(rank)
                if skill and skill > 0 then return skill end
                return nil
            end
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- The record
--------------------------------------------------------------------------------

--- Every spot fished, kept in saved variables from one session to the next.
function Fishing:Store()
    local db = ns.db

    if type(db.fishing) ~= "table" then db.fishing = {} end
    if type(db.fishing.spots) ~= "table" then db.fishing.spots = {} end

    return db.fishing.spots
end

function Fishing.SpotKey(zone, location, school)
    return ("%s|%s|%s"):format(zone or "?", location or "", school or "")
end

function Fishing:GetSpot(zone, location, school)
    local key = Fishing.SpotKey(zone, location, school)
    local spots = self:Store()
    local spot = spots[key]

    if type(spot) ~= "table" then
        spot = { zone = zone, location = location, school = school }
        spots[key] = spot
    end

    spot.casts = tonumber(spot.casts) or 0
    if type(spot.items) ~= "table" then spot.items = {} end

    return spot, key
end

--- What a spot is called: its school, or open water.
function Fishing.SpotName(spot)
    return spot.school or OPEN_WATER
end

--------------------------------------------------------------------------------
-- How long your casts take
--
-- The time between two casts at the same spot, when it is under BREAK, so
-- a walk away and back, a flight or a night off never count. Only your own
-- casts reach it, and only the seconds and how many casts they covered are
-- kept: what the casts gave is already in the spot's record.
--
-- Kept account wide in `fishing.pace[spot key]`, never renamed.
--------------------------------------------------------------------------------

function Fishing:PaceStore()
    local db = ns.db
    if type(db.fishing) ~= "table" then db.fishing = {} end
    if type(db.fishing.pace) ~= "table" then db.fishing.pace = {} end
    return db.fishing.pace
end

--- One cast at `key`: the gap since the one before it there.
function Fishing:NotePace(key, now)
    if type(key) ~= "string" then return end
    now = now or Now()

    local store = self:PaceStore()
    local entry = store[key]
    if type(entry) ~= "table" then
        entry = {}
        store[key] = entry
    end
    entry.seconds = tonumber(entry.seconds) or 0
    entry.casts = (tonumber(entry.casts) or 0) + 1

    local last = self.lastCast
    if now and last and last.key == key then
        local gap = now - last.at
        if gap > 0 and gap < Fishing.BREAK then entry.seconds = entry.seconds + gap end
    end
    if now then self.lastCast = { key = key, at = now } end

    -- Moves with every cast, so what reads the pace knows to look again.
    Fishing.paceVersion = (Fishing.paceVersion or 0) + 1
end

--- How long one cast at `key` takes, in seconds, once MIN_SECONDS of
--- fishing are behind it. Nil before that.
function Fishing:SecondsPerCast(key)
    local entry = type(ns.db.fishing) == "table" and type(ns.db.fishing.pace) == "table"
        and ns.db.fishing.pace[key]
    if type(entry) ~= "table" then return nil end
    local seconds = tonumber(entry.seconds) or 0
    local casts = tonumber(entry.casts) or 0
    if seconds < Fishing.MIN_SECONDS or casts <= 0 then return nil end
    return seconds / casts
end

--- Count one cast that landed something. Returns the spot.
--
-- `items` are names, each once; `quantities` how many of each came up.
function Fishing:Record(zone, location, school, items, quantities, skill, coords)
    local spot, key = self:GetSpot(zone, location, school)

    spot.casts = spot.casts + 1

    for _, name in ipairs(items or {}) do
        local entry = spot.items[name]

        if type(entry) ~= "table" then
            entry = { casts = 0, count = 0 }
            spot.items[name] = entry
        end

        entry.casts = (tonumber(entry.casts) or 0) + 1
        entry.count = (tonumber(entry.count) or 0) + (quantities and quantities[name] or 1)
        self.sessionCatch[name] = (self.sessionCatch[name] or 0) + (quantities and quantities[name] or 1)
        if ns.Stats then ns.Stats:Loot("fish", name, quantities and quantities[name] or 1) end

        -- Kept here as well as with the item's looks, so the export has it
        -- from the fishing record alone.
        entry.id = entry.id or ns.Tracker:LookOf(name).id
    end

    if skill then
        spot.minSkill = math.min(tonumber(spot.minSkill) or skill, skill)
        spot.maxSkill = math.max(tonumber(spot.maxSkill) or skill, skill)
    end

    if coords and not spot.coords then
        spot.coords = { coords[1], coords[2] }
    end

    -- Made with Luremaster and a lure: noted beside the record, so it
    -- never reaches anyone's rates (Logic/Legacy.lua).
    local boost = ns.Legacy and ns.Legacy:CastBoost()
    if boost then ns.Legacy.Note(spot, "casts", items, quantities, boost) end

    self:NotePace(key)

    self.session[key] = (self.session[key] or 0) + 1
    self.sessionCasts = self.sessionCasts + 1
    self.clock = self.clock + 1
    self.recent[key] = self.clock

    -- Whichever you did last goes on top of the panel.
    ns.lastLoot = "fishing"

    if ns.TrackerUI then ns.TrackerUI:Refresh() end

    -- The cast that unlocks catch rates gets the same fanfare as a mob's
    -- 20th kill (2026-09-25).
    if spot.casts == MIN_CASTS then
        self:Celebrate(key)
    end

    return spot
end

--- Catch rates just unlocked at a spot: the kill tally's fanfare, with the
--- same /farm celebrate switch.
function Fishing:Celebrate(key)
    if ns.db.trackerCelebrate == false then return end

    local summary = self:Summary(key)
    if not summary then return end

    local where = summary.place and L.Format(" in %s", summary.place) or ""
    local line = L.Format("Catch rates unlocked for %s%s after %d casts.",
        Util.Colored("accent", Shown(summary.name)), where, summary.casts)

    local best = summary.items[1]
    if best then
        line = line .. L.Format(" Best catch: %s %s.", Util.ColorItem(best.name, best.id),
            Util.Colored("good", ns.Tracker.FormatChance(best.chance)))
    end

    ns.Tracker:Fanfare(line,
        { title = L["CATCH RATES UNLOCKED"], subject = L.Format("%s  |  %d casts",
            (Shown(summary.name):gsub("^%l", string.upper)), summary.casts), key = "spot:" .. tostring(key) })
end

--- One spot's catch, best-caught first.
function Fishing:Summary(key, clean)
    local spot = self:Store()[key]
    if type(spot) ~= "table" then return nil end
    -- For the export: casts made with Luremaster left out.
    if clean and ns.Legacy then spot = ns.Legacy.Without(spot, "casts") end

    local casts = tonumber(spot.casts) or 0
    local items = {}

    for name, entry in pairs(type(spot.items) == "table" and spot.items or {}) do
        local held = type(entry) == "table" and tonumber(entry.casts) or 0
        items[#items + 1] = {
            name = name,
            casts = held,
            count = type(entry) == "table" and tonumber(entry.count) or held,
            id = type(entry) == "table" and tonumber(entry.id) or nil,
            chance = casts > 0 and math.min(100, held / casts * 100) or 0,
        }
    end

    table.sort(items, function(a, b)
        if a.casts ~= b.casts then return a.casts > b.casts end
        return a.name < b.name
    end)

    return {
        key = key,
        spot = spot,
        name = Fishing.SpotName(spot),
        place = ns.Tracker.PlaceName(ns.Spots.Show(spot.zone), spot.location),
        casts = casts,
        session = self.session[key] or 0,
        rated = casts >= MIN_CASTS,
        needed = math.max(0, MIN_CASTS - casts),
        items = items,
    }
end

--- Every spot fished this session, most recent first, as summaries.
function Fishing:SessionSpots()
    local spots = {}

    for key in pairs(self.session) do
        local summary = self:Summary(key)
        if summary then spots[#spots + 1] = summary end
    end

    table.sort(spots, function(a, b)
        return (self.recent[a.key] or 0) > (self.recent[b.key] or 0)
    end)

    return spots
end

--- Every spot ever fished, most casts first; only those in `zone` if given.
-- `clean` leaves out casts made with Luremaster (the export).
function Fishing:Spots(zone, clean)
    local spots = {}

    for key, spot in pairs(self:Store()) do
        if type(spot) == "table" and (not zone or spot.zone == zone) then
            local summary = self:Summary(key, clean)
            if summary and summary.casts > 0 then spots[#spots + 1] = summary end
        end
    end

    table.sort(spots, function(a, b)
        if a.casts ~= b.casts then return a.casts > b.casts end
        return a.key < b.key
    end)

    return spots
end

function Fishing:CountCasts(clean)
    local total = 0
    for _, spot in pairs(self:Store()) do
        if type(spot) == "table" then
            if clean and ns.Legacy then spot = ns.Legacy.Without(spot, "casts") end
            total = total + (tonumber(spot.casts) or 0)
        end
    end
    return total
end

--- What one cast at a spot is worth, in copper, once it has MIN_CASTS.
--
-- Priced the way a kill is: each item's amount over the casts, times its unit
-- price. Nil below the threshold, or when nothing it caught has a price.
function Fishing:WorthPerCast(key)
    local summary = self:Summary(key)
    if not (summary and summary.rated and ns.Value) then return nil end

    local total, priced = 0, 0

    for _, item in ipairs(summary.items) do
        local unit = ns.Value:UnitPrice(ns.Value:ItemID(item.name))
        if unit then
            total = total + item.count / summary.casts * unit
            priced = priced + 1
        end
    end

    if priced == 0 then return nil end

    return total
end

--- What an hour at a spot is worth, in copper: a cast's worth over how
--- long a cast takes there. Nil until the spot has both.
function Fishing:WorthPerHour(key)
    local perCast = self:WorthPerCast(key)
    local seconds = self:SecondsPerCast(key)
    if not (perCast and seconds and seconds > 0) then return nil end
    return perCast * 3600 / seconds
end

function Fishing:Reset()
    -- Shared and imported counts went with the records: their ledgers too.
    if ns.Share and ns.Share.ForgetSection then ns.Share:ForgetSection("f") end
    ns.db.fishing = nil
    self.session = {}
    self.sessionCatch = {}
    self.recent = {}
    self.sessionCasts = 0
    self.cast = nil
    self.lastSchool = nil
    self.lastCast = nil
    Fishing.paceVersion = (Fishing.paceVersion or 0) + 1

    if ns.TrackerUI then ns.TrackerUI:Refresh() end
end

--------------------------------------------------------------------------------
-- Reading the loot window
--------------------------------------------------------------------------------

--- Is the open loot window a fishing catch?
function Fishing:IsCatch()
    if not ns.Harvest:Capabilities().fishingLoot then return false end

    local ok, fishing = pcall(IsFishingLoot)
    if not ok then return false end

    -- Read before it is believed, like everything else off this client: a
    -- comparison is what a secret value refuses, so a flag that cannot be
    -- read is not a catch. Older clients said 1 rather than true.
    local readable, answer = pcall(function() return fishing == true or fishing == 1 end)
    return readable and answer == true
end

function Fishing:OnLoot()
    if not self:IsCatch() then return end
    -- A catch flashes the fishing bar's Cast plaque, once a window.
    if not self.lootOpen and ns.FishingBar and ns.FishingBar.Caught then
        pcall(ns.FishingBar.Caught, ns.FishingBar)
    end

    -- The same pause as the harvester: recording off means nothing recorded.
    if ns.db.harvestPaused then return end

    -- One window is one cast. A second LOOT_OPENED before it closes is the
    -- same catch.
    if self.lootOpen then return end
    if self.watchingClose then self.lootOpen = true end

    local cast = self.cast
    self.cast = nil

    local zone, location = ns.Harvest:Where()
    local items, quantities = ns.Tracker:LootedItems(true)

    local x, y = ns.Harvest:PlayerPosition()

    -- A cast into a school you moused over goes on the maps beside your
    -- herbs and veins, where you stood to fish it.
    local school = cast and cast.school
    if school and ns.Gathering then
        local mapID, mapX, mapY = ns.Harvest:PlayerMapPosition()
        if mapID then
            ns.Gathering:AddSpot(mapID, mapX, mapY, school, "fish", items, quantities)
        end
    end

    return self:Record(zone, location, cast and cast.school or nil, items, quantities,
        self:Skill(), x and { x, y } or nil)
end

--------------------------------------------------------------------------------
-- Export
--
-- Rows for the data files, in the same shape the harvester writes for mobs:
-- kind = "fishing", named for the school or open water, marked provenance =
-- "forever", and with a rate only from MIN_CASTS casts up.
--------------------------------------------------------------------------------

local function Escape(text)
    return (tostring(text):gsub("\\", "\\\\"):gsub('"', '\\"'))
end

--- The level band the database already gives a zone, from its node and
--- fishing rows, which carry the zone's band. Nil when it has none.
function Fishing:ZoneBand(zone)
    if not (ns.DB and zone) then return nil end

    local low, high
    -- Your spot keeps the client's name for the zone; the data's is English.
    local english = ns.Spots and ns.Spots.English(zone) or zone

    for item in ns.DB:Iterate() do
        for _, source in ipairs(item.sources or {}) do
            if (source.zone == zone or source.zone == english) and (source.kind == "fishing" or source.kind == "node")
                and source.minLevel then
                low = math.min(low or source.minLevel, source.minLevel)
                high = math.max(high or source.maxLevel or source.minLevel,
                    source.maxLevel or source.minLevel)
            end
        end
    end

    return low, high
end

--- Every item caught, with the spots it came from: { name, id, rows }.
-- `clean` leaves out casts made with Luremaster (the export).
function Fishing:Items(clean)
    local byName, order = {}, {}

    for _, summary in ipairs(self:Spots(nil, clean)) do
        -- A spot the client would not name the zone of points nowhere, so it
        -- stays in the record and out of the data.
        local items = summary.spot.zone and summary.items or {}

        for _, item in ipairs(items) do
            local entry = byName[item.name]

            if not entry then
                entry = { name = item.name, casts = 0, rows = {} }
                byName[item.name] = entry
                order[#order + 1] = entry
            end

            entry.casts = entry.casts + item.casts
            entry.rows[#entry.rows + 1] = { summary = summary, item = item }
        end
    end

    table.sort(order, function(a, b)
        if a.casts ~= b.casts then return a.casts > b.casts end
        return a.name < b.name
    end)

    return order
end

function Fishing:ExportItem(entry)
    local out = {}
    local id

    for _, row in ipairs(entry.rows) do
        id = id or row.item.id
    end

    id = id or ns.Tracker:LookOf(entry.name).id

    out[#out + 1] = "DB:RegisterItem({"
    out[#out + 1] = ('    name = "%s",'):format(Escape(entry.name))
    if id then out[#out + 1] = ("    id = %d,"):format(id) end
    out[#out + 1] = "    sources = {"

    for _, row in ipairs(entry.rows) do
        local spot, summary = row.summary.spot, row.summary
        local fields = {
            'kind = "fishing"',
            ('name = "%s"'):format(Escape(Fishing.SpotName(spot))),
            ('zone = "%s"'):format(Escape(spot.zone or "?")),
        }

        if spot.location then
            fields[#fields + 1] = ('location = "%s"'):format(Escape(spot.location))
        end

        if type(spot.coords) == "table" and spot.coords[1] then
            fields[#fields + 1] = ("coords = { %.1f, %.1f }"):format(spot.coords[1], spot.coords[2])
        end

        local low, high = self:ZoneBand(spot.zone)
        if low then
            fields[#fields + 1] = ("minLevel = %d"):format(low)
            fields[#fields + 1] = ("maxLevel = %d"):format(high)
        end

        local chance = summary.rated and ns.Harvest.ExportChance(row.item.chance)
        if chance then fields[#fields + 1] = chance end

        fields[#fields + 1] = 'provenance = "forever"'

        out[#out + 1] = ("        { %s },"):format(table.concat(fields, ", "))

        local note = summary.rated
            and ("            -- %d of %d casts"):format(row.item.casts, summary.casts)
            or ("            -- %d of %d casts: too few for a rate"):format(row.item.casts, summary.casts)

        if spot.minSkill then
            note = note .. (spot.minSkill == spot.maxSkill
                and ("; fishing skill %d"):format(spot.minSkill)
                or ("; fishing skill %d-%d"):format(spot.minSkill, spot.maxSkill))
        end

        out[#out + 1] = note
    end

    out[#out + 1] = "    },"
    out[#out + 1] = "})"

    return table.concat(out, "\n")
end

--- Every catch as data-file blocks, or nil when nothing has been caught.
function Fishing:ExportBlocks()
    local items = self:Items(true)
    if #items == 0 then return nil end

    local out = {}
    for _, entry in ipairs(items) do
        out[#out + 1] = self:ExportItem(entry)
        out[#out + 1] = ""
    end

    return table.concat(out, "\n")
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Fishing:OnEnable()
    if not ns.Harvest:Capabilities().usable then return end

    ns.OnLootWindow(self, function() Fishing:OnLoot() end)

    -- Without LOOT_CLOSED a window cannot be told from the next one, so the
    -- one-window-one-cast guard is only armed when the client has it.
    self.watchingClose = ns.RegisterEvent(self, "LOOT_CLOSED", function()
        Fishing.lootOpen = false
    end)

    ns.RegisterPlayerEvent(self, "UNIT_SPELLCAST_CHANNEL_START", function(_, _, unit)
        Fishing:OnChannelStart(unit)
    end)

    ns.Harvest.WatchTooltip("Fishing", function(_, unitOrItem)
        Fishing:OnTooltipShown(unitOrItem)
    end)
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local function PrintSpot(summary)
    local skill = ""
    local spot = summary.spot

    if spot.minSkill then
        skill = spot.minSkill == spot.maxSkill
            and L.Format(", skill %d", spot.minSkill)
            or L.Format(", skill %d-%d", spot.minSkill, spot.maxSkill)
    end

    ns.PrintRaw(("%s  %s"):format(
        Util.Colored("accent", Shown(summary.name)),
        Util.Colored("muted", ("%s, %s%s"):format(summary.place or "?",
            Util.Plural(summary.casts, L["cast"], L["casts"]), skill))))

    for _, item in ipairs(summary.items) do
        local right = summary.rated and ns.Tracker.FormatChance(item.chance)
            or L.Format("%d of %d", item.casts, summary.casts)
        ns.PrintRaw(("  %s %s"):format(Util.ColorItem(item.name, item.id), Util.Colored("muted", right)))
    end

    if not summary.rated then
        ns.PrintRaw(Util.Colored("muted", summary.needed == 1
            and L["  1 more cast for catch rates."]
            or L.Format("  %d more casts for catch rates.", summary.needed)))
    end
end

ns.RegisterCommand("fishing", L["what you've caught in this zone (all for everywhere)"], function(rest)
    local argument = Util.Trim(rest):lower()

    if argument == "reset" then
        ns.Print(L.Format("this deletes all %s you have recorded, for good. Type /farm fishing reset confirm to do it.",
            Util.Plural(Fishing:CountCasts(), L["fishing cast"], L["fishing casts"])))
        return
    end

    if argument == "reset confirm" then
        Fishing:Reset()
        ns.Print(L["your fishing counts are cleared."])
        return
    end

    local zone = argument ~= "all" and ns.Harvest:Where() or nil
    local spots = Fishing:Spots(zone)

    if #spots == 0 and zone then
        local total = Fishing:CountCasts()
        if total == 0 then
            ns.Print(L["nothing caught yet. Fish something and try again."])
        else
            ns.Print(L.Format("nothing caught in %s yet. /farm fishing all shows everywhere.", zone))
        end
        return
    end

    if #spots == 0 then
        ns.Print(L["nothing caught yet. Fish something and try again."])
        return
    end

    ns.Print(zone and L.Format("caught in %s:", zone) or L["caught everywhere:"])
    for _, summary in ipairs(spots) do PrintSpot(summary) end
end)
