-- Blackthornes Farmer -- Logic/Grinding.lua
-- Where to grind (a player asked, the owner agreed 2026-10-09): pick a level
-- range and a kind of creature, humanoids for cloth and coin or beasts for
-- skinning, and see where mobs like that gather, zone by zone and camp by
-- camp.
--
-- Only what the addon already holds is used: the mobs in the data files,
-- and the ones you looted yourself (Logic/Harvest.lua). A mob the data has
-- never seen is not on the map, and nothing here makes up a spot, a level
-- or a type.
--
-- Creature types come from the game. Whenever you target a mob, put the
-- mouse over it or its nameplate comes into view, its type is read
-- (UnitCreatureType, inside a pcall) and kept account wide in
-- `creatureTypes` by mob name. The harvest export writes them into the
-- generated data file too, so what one player has seen ships to everyone.
-- A mob whose type nobody has seen yet is left out when a type is picked,
-- and the list says how many such mobs it left out.
--
-- What a mob gives is a fact from the data rather than a guess from its
-- type: "cloth" is a mob that drops an item in the Cloth category, and
-- "skinning" a source the data lists for skinning.
--
-- One mob in one zone: where the data has a spot confirmed on Forever, the
-- Classic rows for the same mob in that zone go, as the search treats one
-- spot (Data/Database.lua). Their levels are often wrong on Forever.

local _, ns = ...
local L = ns.L

local Grinding = ns.NewModule("Grinding")

local Util = ns.Util

-- The level steppers' range. The top is the game's level cap, never under
-- 60: mobs up to 60 are in the data even while the beta stops at 30.
Grinding.MIN_LEVEL = 1
Grinding.MAX_LEVEL = 60

--- The highest level the steppers reach: the game's cap, at least 60.
function Grinding.MaxLevel()
    local cap = ns.XP and ns.XP.MaxLevel and ns.XP.MaxLevel()
    if type(cap) == "number" and cap > Grinding.MAX_LEVEL then return cap end
    return Grinding.MAX_LEVEL
end

-- With no range picked, the band around your own level.
Grinding.BELOW = 2
Grinding.ABOVE = 2

-- Spots with no place name this close together (map percent) are one camp.
Grinding.NEAR = 6

-- The type chips, left to right. Any other type the game names (Giant,
-- Dragonkin, Mechanical, Critter) is "Other".
Grinding.TYPES = { "Humanoid", "Beast", "Undead", "Demon", "Elemental" }
Grinding.OTHER = "Other"

-- What a mob gives, as facts in the data; Ore and Herbs list nodes rather
-- than mobs, and Fish the spots you fished (Logic/GrindGather.lua). The
-- leather view keeps the key "skinning", as saved in grindGives before it
-- was called Leather.
Grinding.GIVES = {
    { key = "cloth", label = L["Cloth"] },
    { key = "skinning", label = L["Leather"] },
    { key = "ore", label = L["Ore"] },
    { key = "herbs", label = L["Herbs"] },
    { key = "fish", label = L["Fish"] },
}

--- Does the Grind tab list nodes, not mobs, for `gives`?
function Grinding.IsNodeView(gives)
    return gives == "ore" or gives == "herbs"
end

--- Does it list the spots you fished?
function Grinding.IsFishView(gives)
    return gives == "fish"
end

--- Your Skinning skill, or nil when you lack it or the client will not say.
function Grinding.SkinningSkill()
    local skills = ns.Spots and ns.Spots.Skills()
    return type(skills) == "table" and skills.Skinning or nil
end

--- The Leather view is offered while skinning shows, or while you know
--- Skinning even with "Hide skinning" ticked: picking it asks for leather.
function Grinding.OffersLeather()
    return ns.DB:ShowsSkinning() or Grinding.SkinningSkill() ~= nil
end

--- The Skinning a mob of `level` needs, by Classic's rule (not yet checked
--- on Forever): 1 to level 10, then ten a level to 20, then five a level.
function Grinding.SkinSkill(level)
    level = tonumber(level)
    if not level then return nil end
    if level <= 10 then return math.max(1, (level - 10) * 10) end
    if level <= 20 then return (level - 10) * 10 end
    return level * 5
end

-- Sources whose `name` is a creature.
local CREATURE_KINDS = { mob = true, skinning = true }

-- What the game says for a mob with no type.
local NO_TYPE = { ["Not specified"] = true }

local LISTED_TYPE = {}
for _, kind in ipairs(Grinding.TYPES) do LISTED_TYPE[kind] = true end

-- Every creature type by the game's ID, in English. A client in another
-- language names them in its own ("Wildtier"), and the client's name for
-- each ID (C_CreatureInfo.GetCreatureTypeInfo) says which one it is, so
-- the types are kept and shipped in English whatever the client.
Grinding.TYPE_IDS = {
    [1] = "Beast", [2] = "Dragonkin", [3] = "Demon", [4] = "Elemental", [5] = "Giant",
    [6] = "Undead", [7] = "Humanoid", [8] = "Critter", [9] = "Mechanical", [10] = "Not specified",
}
local ENGLISH_TYPE = {}
for _, kind in pairs(Grinding.TYPE_IDS) do ENGLISH_TYPE[kind] = true end

-- The words players see for each type (and Other), in the game's own
-- German where there is a translation. The types themselves stay English.
local TYPE_LABELS = {
    Beast = L["Beast"], Dragonkin = L["Dragonkin"], Demon = L["Demon"],
    Elemental = L["Elemental"], Giant = L["Giant"], Undead = L["Undead"],
    Humanoid = L["Humanoid"], Critter = L["Critter"], Mechanical = L["Mechanical"],
    Other = L["Other"],
}

--- A type (English, as kept) in the words players read.
function Grinding.TypeLabel(kind)
    return TYPE_LABELS[kind] or kind
end

-- [the client's name] = English, read once the client names every ID.
local clientTypes

local function ClientTypes()
    if clientTypes then return clientTypes end
    local info = type(C_CreatureInfo) == "table" and C_CreatureInfo.GetCreatureTypeInfo
    if type(info) ~= "function" then return {} end

    local found, complete = {}, true
    for id, english in pairs(Grinding.TYPE_IDS) do
        local ok, name = pcall(function()
            local data = info(id)
            return type(data) == "table" and data.name or nil
        end)
        name = ok and ns.Harvest.Readable(name) or nil
        if name and name ~= "" then found[name] = english else complete = false end
    end
    if complete then clientTypes = found end
    return found
end

--- A type the client named, in English: itself on an English client, else
--- the type with that name on this client. Nil when it is no type known.
function Grinding.EnglishType(kind)
    if type(kind) ~= "string" then return nil end
    if ENGLISH_TYPE[kind] or Util.EnglishClient() then return kind end
    return ClientTypes()[kind]
end

--------------------------------------------------------------------------------
-- Creature types
--------------------------------------------------------------------------------

--- The types learned in game, by mob name (account wide).
function Grinding:Store()
    if not ns.db then return {} end
    if type(ns.db.creatureTypes) ~= "table" then ns.db.creatureTypes = {} end
    return ns.db.creatureTypes
end

--- Read the type of the mob `unit` names, and keep it. Called from
--- Harvest:NoteUnit for every mob you meet, so it stays cheap: one pcall,
--- and a write only when the type is new.
function Grinding:Learn(unit, name)
    if type(name) ~= "string" or name == "" then return end
    if type(UnitCreatureType) ~= "function" then return end

    local ok, value = pcall(UnitCreatureType, unit)
    local kind = ok and ns.Harvest.Readable(value) or nil
    -- Kept in English; a name this client cannot put in English is left out
    -- rather than shipped in another language.
    kind = Grinding.EnglishType(kind)
    if not kind or kind == "" or NO_TYPE[kind] then return end

    local store = self:Store()
    if store[name] ~= kind then
        store[name] = kind
        self.typesVersion = (self.typesVersion or 0) + 1
    end
end

--- A mob's type: what you saw in game, else what the shipped data says.
--- Nil when nobody has seen it.
function Grinding.TypeOf(name)
    local learned = ns.db and type(ns.db.creatureTypes) == "table" and ns.db.creatureTypes[name]
    -- One saved in the client's language before types were kept in English.
    if type(learned) == "string" then return Grinding.EnglishType(learned) or learned end
    return ns.DB.creatureTypes[name]
end

--- A seed-file group ("spiders", "wolves and bears") rather than a mob the
--- client could ever name, so its type can never be learned.
function Grinding.IsGroup(name)
    return type(name) == "string" and name:sub(1, 1) == name:sub(1, 1):lower()
end

--- The chip a type falls under: itself when it has one, else "Other".
function Grinding.Chip(kind)
    if not kind then return nil end
    return LISTED_TYPE[kind] and kind or Grinding.OTHER
end

--- The learned types as a data-file block, for the harvest export. Only
--- mobs the data or the harvest knows, so it never lists a quest giver you
--- moused over in town.
function Grinding:ExportBlock()
    local names = {}
    for _, mob in pairs(self:Mobs().all) do names[mob.name] = true end

    local rows = {}
    for name, kind in pairs(self:Store()) do
        -- In English: an old one saved in another language is put in English
        -- or left out.
        kind = names[name] and Grinding.EnglishType(kind)
        if kind then rows[#rows + 1] = { name, kind } end
    end
    if #rows == 0 then return nil end
    table.sort(rows, function(a, b) return a[1] < b[1] end)

    -- Guarded, because Equipment's and Pets' tools read this file with a DB
    -- that has only RegisterItem.
    local out = { "if DB.CreatureTypes then DB:CreatureTypes({" }
    for _, row in ipairs(rows) do
        out[#out + 1] = ('    ["%s"] = "%s",'):format(
            row[1]:gsub("\\", "\\\\"):gsub('"', '\\"'), row[2]:gsub('"', '\\"'))
    end
    out[#out + 1] = "}) end"
    return table.concat(out, "\n"), #rows
end

--------------------------------------------------------------------------------
-- The level range and the filters
--------------------------------------------------------------------------------

local function Clamp(level)
    level = math.floor((tonumber(level) or Grinding.MIN_LEVEL) + 0.5)
    return math.max(Grinding.MIN_LEVEL, math.min(Grinding.MaxLevel(), level))
end
Grinding.Clamp = Clamp

--- The level band to show, low and high. The one you picked, else the band
--- around your level, and the whole range when the game will not say it.
function Grinding:Range()
    local db = ns.db or {}
    local low, high = tonumber(db.grindMin), tonumber(db.grindMax)
    if low and high then return Clamp(low), Clamp(high) end

    local level = ns.Spots:Player().level
    if not level then return Grinding.MIN_LEVEL, Grinding.MaxLevel() end
    return Clamp(level - Grinding.BELOW), Clamp(level + Grinding.ABOVE)
end

--- True while the range follows your level rather than one you picked.
function Grinding:FollowsLevel()
    local db = ns.db or {}
    return not (tonumber(db.grindMin) and tonumber(db.grindMax))
end

--- Pick a range. The ends are swapped when the low one is the higher.
function Grinding:SetRange(low, high)
    low, high = Clamp(low), Clamp(high)
    if low > high then low, high = high, low end
    ns.db.grindMin, ns.db.grindMax = low, high
    return low, high
end

--- Back to the band around your level.
function Grinding:FollowLevel()
    ns.db.grindMin, ns.db.grindMax = nil, nil
end

--- The type picked, or nil for any.
function Grinding:Type()
    local kind = ns.db and ns.db.grindType
    if kind == Grinding.OTHER or LISTED_TYPE[kind] then return kind end
    return nil
end

function Grinding:SetType(kind)
    if kind ~= Grinding.OTHER and not LISTED_TYPE[kind] then kind = nil end
    ns.db.grindType = kind
end

--- What the list shows: "cloth" or "skinning" (Leather) mobs, "ore" or
--- "herbs" nodes, or nil for any mob.
function Grinding:Gives()
    local gives = ns.db and ns.db.grindGives
    -- Skinning left out (DB:ShowsSkinning) lets a picked Leather go too,
    -- unless you know Skinning.
    if gives == "skinning" and not Grinding.OffersLeather() then return nil end
    for _, entry in ipairs(Grinding.GIVES) do
        if entry.key == gives then return gives end
    end
    return nil
end

function Grinding:SetGives(gives)
    local known = false
    for _, entry in ipairs(Grinding.GIVES) do
        if entry.key == gives then known = true end
    end
    ns.db.grindGives = known and gives or nil
end

--- The orders the camps can be listed in (the Sort menu).
Grinding.SORTS = {
    { key = "busiest", label = L["Busiest"], tip = L["Camps with the most mobs first."] },
    { key = "nearest", label = L["Nearest"], tip = L["Camps closest to you first."] },
    { key = "level", label = L["Level"], tip = L["The lowest level camps first."] },
    { key = "levelnear", label = L["Level, then nearest"],
      tip = L["The lowest level camps first, and the nearest first when levels match."] },
    { key = "worth", label = L["Best Worth"], tip = L["Camps that earn the most an hour first."] },
}

local function KnownSort(key)
    for _, entry in ipairs(Grinding.SORTS) do
        if entry.key == key then return entry end
    end
    return nil
end

--- The order the camps are listed in. Saved as grindSort; before the menu
--- there was only Nearest first (grindNearFirst), which is still read.
function Grinding.Sort()
    local db = ns.db
    if db == nil then return "busiest" end
    if KnownSort(db.grindSort) then return db.grindSort end
    return db.grindNearFirst == true and "nearest" or "busiest"
end

function Grinding:SetSort(key)
    if KnownSort(key) then ns.db.grindSort = key end
end

--- The menu's words for an order: "Level, then nearest".
function Grinding.SortLabel(key)
    local entry = KnownSort(key or Grinding.Sort())
    return entry and entry.label or ""
end

--- Nearest camps first, rather than the busiest.
function Grinding.NearFirst()
    return Grinding.Sort() == "nearest"
end

function Grinding:SetNearFirst(on)
    self:SetSort(on and "nearest" or "busiest")
end

--------------------------------------------------------------------------------
-- The mobs
--------------------------------------------------------------------------------

local function Key(...)
    local parts = {}
    for index = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(index, ...) or "")
    end
    return table.concat(parts, "|"):lower()
end

--- What the list is built from changed: the data, the harvest, the types.
local function Stamp()
    return ("%d:%d:%d:%d:%s"):format(ns.DB:CountSources(),
        ns.Harvest and ns.Harvest:CountCorpses() or 0, Grinding.typesVersion or 0,
        ns.DB.hiddenVersion or 0, Grinding.OffersLeather() and "skin" or "")
end

--- Every mob spot known, one per mob, zone and place in the zone:
--- { all = { [key] = mob } }. Each mob is { name, zone, location, coords,
--- minLevel, maxLevel, forever, cloth, skinning, drops = { [item] = rate },
--- corpses, leathers = { [item] = true }, skinSkill, dropSpot }. dropSpot
--- is a spot something other than skinning names.
function Grinding:Mobs()
    local stamp = Stamp()
    if self.cache and self.cacheStamp == stamp then return self.cache end

    local all = {}

    local function Spot(name, zone, location)
        local key = Key(name, zone, location)
        local mob = all[key]
        if not mob then
            mob = { name = name, zone = zone, location = location, drops = {}, leathers = {} }
            all[key] = mob
        end
        return mob
    end

    -- Levels and spots from Forever rows win over Classic ones on one mob;
    -- each is kept apart until the end.
    local function Note(mob, forever, minLevel, maxLevel, coords)
        local band = forever and "foreverBand" or "classicBand"
        if minLevel then
            local seen = mob[band]
            if not seen then
                mob[band] = { minLevel, maxLevel or minLevel }
            else
                seen[1] = math.min(seen[1], minLevel)
                seen[2] = math.max(seen[2], maxLevel or minLevel)
            end
        end
        if type(coords) == "table" and tonumber(coords[1]) and tonumber(coords[2]) then
            if forever and not mob.foreverCoords then mob.foreverCoords = coords end
            if not forever and not mob.classicCoords then mob.classicCoords = coords end
        end
        if forever then mob.forever = true end
    end

    -- With skinning left out ("Hide skinning", DB:HidesItem), a skinning
    -- spot is no camp and leather is no mob's drop; the mob a looted hide
    -- was recorded on is still a spot.
    -- With Leather offered (you know Skinning), skinning spots are kept
    -- for it, marked, and only the Leather view lists them (Camps).
    local skinning = Grinding.OffersLeather()
    for item in ns.DB:Iterate() do
        local cloth = item.category == "Cloth"
        local itemHidden = ns.DB:HidesItem(item)
        for _, source in ipairs(item.sources or {}) do
            -- Classic's generated drop rows are for the search only
            -- (Data/Data_ClassicDrops.lua): the camps stay as they were.
            if not source.searchOnly and CREATURE_KINDS[source.kind or "mob"] and type(source.name) == "string"
                and type(source.zone) == "string" and (skinning or source.kind ~= "skinning")
                and not ns.DB:IsHiddenSource(source.name) then
                local mob = Spot(source.name, source.zone, source.location)
                Note(mob, source.provenance == "forever", source.minLevel, source.maxLevel, source.coords)
                if source.kind == "skinning" then
                    mob.skinning = true
                    mob.leathers[item.name] = true
                    local need = ns.GrindGather and ns.GrindGather.SkillNumber(source.requires)
                    if need then mob.skinSkill = math.min(mob.skinSkill or need, need) end
                else
                    mob.dropSpot = true
                end
                if cloth then mob.cloth = true end
                if source.kind ~= "skinning" and not itemHidden then
                    mob.drops[item.name] = math.max(mob.drops[item.name] or 0, source.chance or 0)
                end
            end
        end
    end

    -- Mobs you looted yourself, whatever they dropped.
    local records = ns.Harvest and ns.Harvest.records or {}
    for _, record in pairs(records) do
        if type(record) == "table" and type(record.mob) == "string" and type(record.zone) == "string"
            and not ns.DB:IsHiddenSource(record.mob) then
            -- Kept under the client's zone name ("Wald von Elwynn"); in
            -- English, so it is the data's camp and confirms its spot.
            local mob = Spot(record.mob, ns.Spots.English(record.zone), record.location)
            Note(mob, true, tonumber(record.minLevel), tonumber(record.maxLevel), record.coords)
            mob.corpses = (mob.corpses or 0) + (tonumber(record.corpses) or 0)
            mob.dropSpot = true
            for name in pairs(type(record.items) == "table" and record.items or {}) do
                local item = ns.DB:GetItem(name)
                if item and item.category == "Cloth" then mob.cloth = true end
                -- A skin you took on it: leather it gives.
                if ns.DB:FromSkinning(item or name) then
                    mob.leathers[item and item.name or name] = true
                    if skinning then mob.skinning = true end
                end
            end
        end
    end

    -- A mob confirmed on Forever in a zone: its Classic-only spots in that
    -- zone go.
    local confirmed = {}
    for _, mob in pairs(all) do
        if mob.forever then confirmed[Key(mob.name, mob.zone)] = true end
    end

    -- Skins you took yourself.
    local skins = skinning and ns.db and type(ns.db.skinLog) == "table" and ns.db.skinLog or {}
    for _, mob in pairs(all) do
        local entry = skins[mob.name]
        if type(entry) == "table" and type(entry.items) == "table" then
            mob.skinning = true
            for name in pairs(entry.items) do mob.leathers[name] = true end
        end
    end

    for key, mob in pairs(all) do
        if not mob.forever and confirmed[Key(mob.name, mob.zone)] then
            all[key] = nil
        else
            local band = mob.foreverBand or mob.classicBand
            mob.minLevel, mob.maxLevel = band and band[1], band and band[2]
            mob.coords = mob.foreverCoords or mob.classicCoords
            mob.foreverBand, mob.classicBand = nil, nil
            mob.foreverCoords, mob.classicCoords = nil, nil
        end
    end

    self.cache = { all = all }
    self.cacheStamp = stamp
    return self.cache
end

--- Does `mob` fall in the level band low..high? Any overlap counts.
function Grinding.InRange(mob, low, high)
    if not mob.minLevel then return false end
    return mob.minLevel <= high and (mob.maxLevel or mob.minLevel) >= low
end

--- Does `mob` give what `gives` asks for?
function Grinding.GivesWhat(mob, gives)
    if not gives then return true end
    return mob[gives] == true
end

--------------------------------------------------------------------------------
-- Camps
--------------------------------------------------------------------------------

local function Distance(a, b)
    local dx, dy = a[1] - b[1], a[2] - b[2]
    return math.sqrt(dx * dx + dy * dy)
end

--- The member whose spot sits nearest the middle of them all: a real spot,
--- never an average nobody stood on.
local function MiddleSpot(mobs)
    local sumX, sumY, count = 0, 0, 0
    for _, mob in ipairs(mobs) do
        if mob.coords then
            sumX, sumY, count = sumX + mob.coords[1], sumY + mob.coords[2], count + 1
        end
    end
    if count == 0 then return nil end

    local middle = { sumX / count, sumY / count }
    local best, bestDistance
    for _, mob in ipairs(mobs) do
        if mob.coords then
            local distance = Distance(mob.coords, middle)
            if not bestDistance or distance < bestDistance then best, bestDistance = mob, distance end
        end
    end
    return best.coords
end

--- The camps for a filter: { low, high, type, gives }, each field optional
--- (the saved ones when nil). Returns the camps best first, and how many
--- mobs a type filter left out because their type is not known yet.
--
-- A camp is one named place in a zone (a subzone), or, for spots with no
-- place name, the spots within NEAR of each other; mobs with neither are
-- "around the zone". Each is { zone, location, coords, mobs, count,
-- minLevel, maxLevel, forever, unknown, hops, travel, label }.
function Grinding:Camps(filter)
    filter = filter or {}
    local low, high = filter.low, filter.high
    if not (low and high) then low, high = self:Range() end
    local kind = filter.type
    if kind == nil then kind = self:Type() end
    if kind == false then kind = nil end
    local gives = filter.gives
    if gives == nil then gives = self:Gives() end
    if gives == false then gives = nil end

    local camps, byKey, loose = {}, {}, {}
    local unknownTotal = 0

    -- Ore and Herbs are nodes, never camps of mobs.
    if Grinding.IsNodeView(gives) then return camps, 0, low, high end
    -- A spot only skinning names is the Leather view's, unless skinning shows.
    local skinOnlyShown = gives == "skinning" or ns.DB:ShowsSkinning()

    local function Camp(key, zone, location, coords)
        local camp = byKey[key]
        if not camp then
            camp = { zone = zone, location = location, anchor = coords, mobs = {}, unknown = 0 }
            byKey[key] = camp
            camps[#camps + 1] = camp
        end
        return camp
    end

    local function Place(mob)
        if mob.location then
            return Camp(Key(mob.zone, mob.location), mob.zone, mob.location)
        end
        if mob.coords then
            -- Joins the nearest unnamed camp in the zone within NEAR.
            local zoneKey = Key(mob.zone)
            loose[zoneKey] = loose[zoneKey] or {}
            for _, camp in ipairs(loose[zoneKey]) do
                if Distance(camp.anchor, mob.coords) <= Grinding.NEAR then return camp end
            end
            local camp = Camp(Key(mob.zone, "@", #loose[zoneKey] + 1), mob.zone, nil, mob.coords)
            table.insert(loose[zoneKey], camp)
            return camp
        end
        return Camp(Key(mob.zone, "*"), mob.zone, nil)
    end

    -- Sorted first, so the camps and their names come out the same each time.
    local list = {}
    for _, mob in pairs(self:Mobs().all) do list[#list + 1] = mob end
    table.sort(list, function(a, b)
        if a.zone ~= b.zone then return a.zone < b.zone end
        if (a.location or "") ~= (b.location or "") then return (a.location or "") < (b.location or "") end
        return a.name < b.name
    end)

    for _, mob in ipairs(list) do
        if Grinding.InRange(mob, low, high) and Grinding.GivesWhat(mob, gives)
            and (mob.dropSpot or skinOnlyShown) then
            local mobType = Grinding.TypeOf(mob.name)
            if not kind or Grinding.Chip(mobType) == kind then
                local camp = Place(mob)
                camp.mobs[#camp.mobs + 1] = mob
                mob.type = mobType
            elseif not mobType and not Grinding.IsGroup(mob.name) then
                -- A group row ("spiders") is not a mob anyone can target
                -- to learn its type, so it is never asked for.
                unknownTotal = unknownTotal + 1
                -- Only counted on a camp that shows; see below.
                local camp = Place(mob)
                camp.unknown = camp.unknown + 1
            end
        end
    end

    local player = ns.Spots:Player()
    local shown = {}

    for _, camp in ipairs(camps) do
        if #camp.mobs > 0 then
            table.sort(camp.mobs, function(a, b)
                if (a.minLevel or 0) ~= (b.minLevel or 0) then return (a.minLevel or 0) < (b.minLevel or 0) end
                return a.name < b.name
            end)

            camp.count = #camp.mobs
            for _, mob in ipairs(camp.mobs) do
                camp.minLevel = math.min(camp.minLevel or mob.minLevel, mob.minLevel)
                camp.maxLevel = math.max(camp.maxLevel or mob.maxLevel, mob.maxLevel or mob.minLevel)
                if mob.forever then camp.forever = true end
            end

            camp.coords = MiddleSpot(camp.mobs)
            camp.anchor = nil
            if camp.location then
                camp.label = camp.location
            elseif camp.coords then
                camp.label = L.Format("around %.0f, %.0f", camp.coords[1], camp.coords[2])
            else
                camp.label = L["around the zone"]
            end

            if ns.Spots.ZoneOf(camp.zone) and player.zone then
                camp.hops, camp.travel = ns.Spots.Hops(player.zone, camp.zone)
            end

            shown[#shown + 1] = camp
        end
    end

    local order = Grinding.Sort()
    local FAR = 99

    -- Best Worth: what each camp earned you an hour (CampWorth), read once
    -- before the sort; camps with too few of your kills go last.
    local worth = {}
    if order == "worth" and ns.CampWorth then
        for _, camp in ipairs(shown) do
            local ok, perHour = pcall(ns.CampWorth.Known, ns.CampWorth, camp)
            worth[camp] = ok and perHour or nil
        end
    end

    table.sort(shown, function(a, b)
        local hopsA, hopsB = a.hops or FAR, b.hops or FAR
        if order == "worth" and worth[a] ~= worth[b] then
            if worth[a] and worth[b] then return worth[a] > worth[b] end
            return worth[a] ~= nil
        end
        if order == "nearest" and hopsA ~= hopsB then return hopsA < hopsB end
        if order == "level" or order == "levelnear" then
            if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
            if order == "levelnear" and hopsA ~= hopsB then return hopsA < hopsB end
            if a.maxLevel ~= b.maxLevel then return a.maxLevel < b.maxLevel end
        end
        if a.count ~= b.count then return a.count > b.count end
        if (a.forever and true or false) ~= (b.forever and true or false) then return a.forever == true end
        if hopsA ~= hopsB then return hopsA < hopsB end
        if a.zone ~= b.zone then return a.zone < b.zone end
        return (a.label or "") < (b.label or "")
    end)

    return shown, unknownTotal, low, high
end

--- One camp as a chat line: "The Barrens, The Dry Hills (14-18): 4 mobs".
function Grinding:Line(camp)
    local text = ("%s, %s (%s): %s"):format(Util.Colored("accent", ns.Spots.Show(camp.zone)), camp.label,
        ns.Search:LevelText(camp), Util.Plural(camp.count, L["mob"], L["mobs"]))
    local distance = ns.Spots.DistanceText(camp.hops, camp.zone, camp.travel)
    if distance ~= "" then text = text .. ", " .. distance end
    return text
end

--------------------------------------------------------------------------------
-- Command
--------------------------------------------------------------------------------

local function Open()
    if ns.UI and ns.UI.ShowTab then
        ns.UI:Show()
        ns.UI:ShowTab("grind")
    end
end

--- /farm grind [low high] [type] [cloth|leather|ore|herbs|any], "sort <order>", or "pins on|off".
function Grinding:Command(rest)
    local words = {}
    for word in Util.Trim(rest or ""):lower():gmatch("%S+") do words[#words + 1] = word end

    if words[1] == "sort" then
        local wanted = { busiest = "busiest", busy = "busiest", nearest = "nearest", near = "nearest",
            level = "level", levelnear = "levelnear", both = "levelnear", worth = "worth", best = "worth" }
        local key = wanted[words[2] or ""]
        -- "level then nearest", "level nearest"
        if key == "level" and (words[#words] == "nearest" or words[#words] == "near") then key = "levelnear" end
        if key then
            self:SetSort(key)
            ns.Print(L.Format("grinding camps sorted by: %s.", Util.Colored("accent", Grinding.SortLabel(key))))
            Open()
        else
            ns.Print(L["sort by busiest, nearest, level, level nearest, or worth."])
        end
        return
    end

    if words[1] == "pins" or words[1] == "map" then
        if ns.GrindPins then
            local on = words[2] == "on" or (words[2] ~= "off" and not ns.GrindPins.IsOn())
            ns.GrindPins:SetOn(on)
            ns.Print(L.Format("grinding camps on the world map: %s.",
                Util.Colored("accent", on and L["on"] or L["off"])))
        end
        return
    end

    local numbers = {}
    for _, word in ipairs(words) do
        local low, high = word:match("^(%d+)%-(%d+)$")
        if low then
            numbers[#numbers + 1], numbers[#numbers + 2] = tonumber(low), tonumber(high)
        elseif tonumber(word) then
            numbers[#numbers + 1] = tonumber(word)
        elseif word == "me" or word == "mine" then
            self:FollowLevel()
        elseif word == "any" or word == "all" then
            self:SetType(nil)
            self:SetGives(nil)
        elseif word == "cloth" or word == "skinning" or word == "skin" or word == "leather" then
            self:SetGives(word == "cloth" and "cloth" or "skinning")
        elseif word == "ore" or word == "mining" or word == "herbs" or word == "herb" or word == "herbalism" then
            self:SetGives((word == "ore" or word == "mining") and "ore" or "herbs")
        elseif word == "fish" or word == "fishing" then
            self:SetGives("fish")
        else
            local typed = word:gsub("s$", "")
            for _, kind in ipairs(Grinding.TYPES) do
                if kind:lower() == typed then self:SetType(kind) end
            end
            if typed == "other" then self:SetType(Grinding.OTHER) end
        end
    end

    if numbers[1] then self:SetRange(numbers[1], numbers[2] or numbers[1]) end

    Open()
end

ns.RegisterCommand("grind", L["where mobs of a level and type gather, or ore and herbs: /farm grind 15-20 humanoid, /farm grind ore"], function(rest)

    Grinding:Command(rest)
end)
