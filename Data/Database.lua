-- Blackthornes Farmer -- Data/Database.lua
-- The item database and the API the data files register through.
--
-- Deliberately not a flat drop table. Every entry is an item with a list of
-- sources, and a source says what kind of thing it is, where it is, and what
-- level you will be fighting at. That shape is what lets one search answer
-- "where do I get this" and "what is worth farming here" from the same rows.

local _, ns = ...

local DB = ns.NewModule("DB")

local Util = ns.Util

-- items[lowercase name] = item; order keeps iteration stable across sessions.
DB.items = {}
DB.order = {}

-- Counts every item or source added, so the index by name below knows when
-- it is out of date. The data only changes while the files load.
DB.changes = 0

-- Where a row's facts came from. Everything seeded from Classic is "classic"
-- until somebody actually confirms it on Forever, because Forever is classic
-- content on a retail engine and its drop tables are nobody's to assume. A
-- wrong farming spot costs an hour of someone's evening, so the window says
-- which rows have been checked rather than presenting all of them as equal.
DB.PROVENANCE = {
    classic = "from Classic data",
    forever = "confirmed on Forever",
    guild   = "measured by your guild",
}

-- Which wins when two provenances name the same spot: looted here by this
-- addon's own data, then measured by guildmates (Logic/GuildShare.lua),
-- then Classic.
DB.RANK = { classic = 1, guild = 2, forever = 3 }

DB.DEFAULT_PROVENANCE = "classic"

-- What a source actually is. Every source names one of these so the window can
-- label it; an unknown kind falls back to the raw string rather than vanishing.
DB.KIND_LABEL = {
    mob       = "mob",
    node      = "mining node",
    herb      = "herb node",
    skinning  = "skinning",
    fishing   = "fishing",
    container = "container",
    vendor    = "vendor",
    quest     = "quest",
}

--[[----------------------------------------------------------------------------
  Data files call:

    ns.DB:RegisterItem({
      name     = "Copper Ore",
      id       = 2770,                -- optional, for item links later
      category = "Mining",
      aliases  = { "copper" },        -- optional extra search terms
      note     = "...",               -- optional one-liner
      sources  = {
        { kind = "node", name = "Copper Vein", zone = "Durotar",
          minLevel = 1, maxLevel = 10, requires = "Mining 1",
          location = "Tiragarde Keep", coords = { 55.4, 12.8 }, chance = 35,
          provenance = "forever" },   -- omit until somebody has checked in game
      },
    })

  Only `zone` and `minLevel` are required. `location` is where in the zone,
  `coords` is { x, y } on the zone map, and `chance` is a drop rate in percent.
  Everything optional is simply not drawn when it is missing, so a thin entry
  and a fully researched one live in the same list without one looking broken.

  Registering a name that already exists merges the new sources into the
  existing item, so the database can be split across as many files as we like
  and a later data pack can extend what ships here.
------------------------------------------------------------------------------]]

function DB:RegisterItem(def)
    if type(def) ~= "table" or type(def.name) ~= "string" or def.name == "" then
        ns.Warn("skipped a data entry with no name")
        return nil
    end

    local key = def.name:lower()
    local item = self.items[key]
    self.changes = (self.changes or 0) + 1

    if not item then
        item = {
            name     = def.name,
            id       = def.id,
            category = def.category or "Misc",
            aliases  = {},
            note     = def.note,
            sources  = {},
        }
        self.items[key] = item
        self.order[#self.order + 1] = key
    else
        item.id       = item.id or def.id
        item.category = def.category or item.category
        item.note     = item.note or def.note
    end

    for _, alias in ipairs(def.aliases or {}) do
        item.aliases[#item.aliases + 1] = alias
    end

    for _, source in ipairs(def.sources or {}) do
        self:AddSource(item, source)
    end

    return item
end

--- Add one source to an item, given either the item table or its name.
--- The source already recorded for this same spot, if there is one.
--
-- Same creature or node, same zone, same subzone. Compared case-insensitively
-- because the two sides come from different places: the seed files are typed
-- by hand and the harvested ones come back from the client.
local function SameSpot(item, source)
    if type(source.name) ~= "string" or source.name == "" then return nil end

    local name = source.name:lower()
    local zone = source.zone:lower()
    local location = (source.location or ""):lower()

    for index, existing in ipairs(item.sources) do
        if type(existing.name) == "string"
            and existing.name:lower() == name
            and type(existing.zone) == "string"
            and existing.zone:lower() == zone
            and (existing.location or ""):lower() == location then
            return index, existing
        end
    end

    return nil
end

--- A Classic row and a measured one (looted here, or the guild's) for the
--- same creature in the same zone, when SameSpot finds no exact match. The
--- generated Classic rows (Data/Data_ClassicDrops.lua) name no subzone, and
--- a looted row always does, so they would otherwise sit side by side.
local function SameMob(item, source)
    if type(source.name) ~= "string" or source.name == "" then return nil end

    local name = source.name:lower()
    local zone = source.zone:lower()
    local classic = source.provenance == DB.DEFAULT_PROVENANCE

    for index, existing in ipairs(item.sources) do
        if type(existing.name) == "string"
            and existing.name:lower() == name
            and type(existing.zone) == "string"
            and existing.zone:lower() == zone
            -- A generated row gives way to any row already there, the
            -- hand-typed ones included, and a measured row takes its place.
            and (source.searchOnly or (existing.searchOnly and not classic)) then
            return index, existing
        end
    end

    return nil
end

function DB:AddSource(item, source)
    if type(item) == "string" then
        item = self.items[item:lower()]
    end

    if not item or type(source) ~= "table" then return nil end
    self.changes = (self.changes or 0) + 1

    -- A source with nowhere to go is not a lead, it is noise.
    if type(source.zone) ~= "string" or source.zone == "" then
        ns.Warn(("skipped a source with no zone on %s"):format(item.name))
        return nil
    end

    source.kind = source.kind or "mob"
    -- An item the data names a skinning spot for comes from skinning, also
    -- where it was looted (a skin opens a loot window too): DB:FromSkinning.
    if source.kind == "skinning" then item.fromSkinning = true end
    source.minLevel = source.minLevel or source.level
    source.maxLevel = source.maxLevel or source.minLevel

    -- Unmarked means nobody has checked it on Forever, which is the honest
    -- default for anything carried over from Classic.
    if not self.PROVENANCE[source.provenance] then
        source.provenance = self.DEFAULT_PROVENANCE
    end

    -- Coordinates are map percentages. A malformed pair is dropped rather than
    -- stored, because a row that points somewhere wrong is worse than a row
    -- that admits it does not know: one wastes a flight, the other does not.
    if source.coords then
        local x, y = source.coords[1], source.coords[2]

        if type(x) ~= "number" or type(y) ~= "number"
            or x < 0 or x > 100 or y < 0 or y > 100 then
            ns.Warn(("dropped bad coordinates on %s in %s"):format(item.name, source.zone))
            source.coords = nil
        end
    end

    -- Same reasoning for a nonsense drop rate.
    if source.chance and (type(source.chance) ~= "number"
        or source.chance <= 0 or source.chance > 100) then
        ns.Warn(("dropped a bad drop rate on %s in %s"):format(item.name, source.zone))
        source.chance = nil
    end

    -- Measured beats carried over. The two can disagree, and when they do the
    -- Classic row is the wrong one: Witchwing Slayers are level 20-21 in
    -- Classic and 16-17 on Forever, so showing both sends somebody to a camp
    -- four levels off, under a drop rate nobody measured here. One row per
    -- spot, and the one that was actually looted wins.
    --
    -- Only across provenances. Two rows of the same kind for one spot are a
    -- data-entry duplicate, which is not this function's problem to guess at.
    local index, existing = SameSpot(item, source)
    if not existing then
        index, existing = SameMob(item, source)
        if existing and source.searchOnly then return nil end
    end

    -- A guild row is taken out again when guild sharing is turned off, so
    -- it keeps the row it stood in for (DB:RemoveSource puts it back).
    if existing and existing.provenance ~= source.provenance then
        local rank = self.RANK[source.provenance] or 1
        local over = self.RANK[existing.provenance] or 1
        if rank > over then
            if source.provenance == "guild" then source.replaced = existing end
            item.sources[index] = source
            return source
        end

        if rank < over then
            return nil
        end
    end

    item.sources[#item.sources + 1] = source
    return source
end

--- Take back out a source added after the data loaded, putting back the
--- row it replaced, if any.
function DB:RemoveSource(item, source)
    if type(item) ~= "table" or type(item.sources) ~= "table" then return false end
    for index, existing in ipairs(item.sources) do
        if existing == source then
            if source.replaced then
                item.sources[index] = source.replaced
            else
                table.remove(item.sources, index)
            end
            self.changes = (self.changes or 0) + 1
            return true
        end
    end
    return false
end

--- Take back out an item added after the data loaded.
function DB:RemoveItem(item)
    if type(item) ~= "table" or type(item.name) ~= "string" then return false end
    local key = item.name:lower()
    if self.items[key] ~= item then return false end
    self.items[key] = nil
    for index, name in ipairs(self.order) do
        if name == key then
            table.remove(self.order, index)
            break
        end
    end
    self.changes = (self.changes or 0) + 1
    return true
end

--- The item named `name`: by the database's own (English) name, else by the
--- name the client gives its ID, so a German "Leinenstoff" is Linen Cloth.
--- A second answer, true, says it was found by the client's name.
function DB:GetItem(name)
    if type(name) ~= "string" then return nil end
    local trimmed = Util.Trim(name)
    local key = trimmed:lower()
    local item = self.items[key]
    if item then return item end

    item = self:ByClientName(key, trimmed)
    if item then return item, true end
    return nil
end

--------------------------------------------------------------------------------
-- The client's own item names
--
-- The data names items in English. A German client names them in German,
-- and that is what a player types, links or has Tradeskills pass to a goal.
-- So the name the client gives each item's ID is kept beside it, as names
-- arrive: a few items a frame, started the first time a name is not found
-- (or a search runs), and one item more on each GET_ITEM_INFO_RECEIVED. On
-- an English client every name is the database's own, so none of this
-- runs there.
--------------------------------------------------------------------------------

-- [lower case client name] = item, only where it differs from the data's.
DB.clientNames = {}
-- [item] = the client's name for it, where it differs.
DB.clientNameOf = {}
-- [item ID] = true once the client has named it.
DB.clientNamed = {}
-- Moves whenever a client name is learned (Search keeps its last answer by it).
DB.namesVersion = 0
-- How many items a frame the names are read for.
DB.NAMES_PER_FRAME = 25
-- [lower case name] = namesVersion when the client last knew no item by it,
-- so a name asked for again and again (the rankings value every drop) asks
-- the client once until a new name comes in.
DB.clientMisses = {}

--- Every item with an ID, by ID. Built again only after the data changed.
function DB:ByID()
    if self.byID and self.byIDAt == self.changes then return self.byID end
    local byID = {}
    for _, key in ipairs(self.order) do
        local item = self.items[key]
        if item.id and not byID[item.id] then byID[item.id] = item end
    end
    self.byID, self.byIDAt = byID, self.changes
    return byID
end

local function Plain(value)
    local readable = ns.Harvest and ns.Harvest.Readable
    if readable then return readable(value) end
    return type(value) == "string" and value or nil
end

--- The name the client gives item `id`, or nil while it will not say.
function DB.ClientItemName(id)
    local item = type(C_Item) == "table" and C_Item or nil
    if item and type(item.GetItemNameByID) == "function" then
        local ok, name = pcall(item.GetItemNameByID, id)
        name = ok and Plain(name) or nil
        if name and name ~= "" then return name end
    end
    local getInfo = (item and item.GetItemInfo) or _G.GetItemInfo
    if type(getInfo) == "function" then
        local ok, name = pcall(getInfo, id)
        name = ok and Plain(name) or nil
        if name and name ~= "" then return name end
    end
    return nil
end

--- Keep the client's name for `item`, when it gives one. True once named.
function DB:NoteClientName(item)
    if not (item and item.id) then return false end
    if self.clientNamed[item.id] then return true end

    local name = DB.ClientItemName(item.id)
    if not name then return false end
    self.clientNamed[item.id] = true

    local key = name:lower()
    if key ~= item.name:lower() then
        self.clientNames[key] = self.clientNames[key] or item
        self.clientNameOf[item] = name
        self.namesVersion = self.namesVersion + 1
    end
    return true
end

--- Start reading the client's names, once, a few items a frame.
function DB:LearnClientNames()
    if self.learning then return end
    if Util.EnglishClient() then return end
    self.learning = true

    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", function(_, _, itemID)
        local id = ns.Harvest and ns.Harvest.ReadableNumber(itemID)
        local item = id and DB:ByID()[id]
        if item then DB:NoteClientName(item) end
    end)

    local index = 0
    local function Step()
        local stop = math.min(#self.order, index + DB.NAMES_PER_FRAME)
        for i = index + 1, stop do
            local item = self.items[self.order[i]]
            if item.id then self:NoteClientName(item) end
        end
        index = stop
        if index < #self.order and type(C_Timer) == "table" and type(C_Timer.After) == "function" then
            C_Timer.After(0, Step)
        end
    end
    Step()
end

--- The item whose client name is `key` (lower case), or nil.
--
-- Until the names are all in, the client is asked about this one name too
-- (`name` as typed): one it has loaded (a link, an item in the bags)
-- answers with its ID.
function DB:ByClientName(key, name)
    self:LearnClientNames()
    if not self.learning then return nil end
    local item = self.clientNames[key]
    if item then return item end
    if self.clientMisses[key] == self.namesVersion then return nil end

    local getInfo = (type(C_Item) == "table" and C_Item.GetItemInfo) or _G.GetItemInfo
    if type(getInfo) == "function" then
        local ok, link = pcall(function() return select(2, getInfo(name or key)) end)
        link = ok and Plain(link) or nil
        local id = link and tonumber(link:match("item:(%d+)"))
        item = id and self:ByID()[id]
        if item then self:NoteClientName(item) end
        -- Only the item the client named that way.
        if item and self.clientNames[key] == item then return item end
    end

    self.clientMisses[key] = self.namesVersion
    return nil
end

--- The client's name for `item`, where it differs from the data's; nil
--- otherwise. Read from what is kept, never from the client.
function DB:ClientName(item)
    return item and self.clientNameOf[item] or nil
end

function DB:CountItems()
    return #self.order
end

function DB:CountSources()
    local total = 0
    for _, key in ipairs(self.order) do
        total = total + #self.items[key].sources
    end
    return total
end

--- Every source by the name of its mob or node: [name] = { { item, source },
--- ... }, items in registration order and each item's sources in order, as
--- walking Iterate would find them. Built on first use and again only after
--- a source is added, so valuing a mob no longer walks the whole database.
function DB:ByName()
    local stamp = self.changes .. ":" .. self.hiddenVersion
    if self.byName and self.byNameAt == stamp then return self.byName end

    local byName = {}
    for _, key in ipairs(self.order) do
        local item = self.items[key]
        for _, source in ipairs(item.sources or {}) do
            local name = source.name
            if type(name) == "string" and not self:HidesSource(source, item) then
                local list = byName[name]
                if not list then
                    list = {}
                    byName[name] = list
                end
                list[#list + 1] = { item = item, source = source }
            end
        end
    end

    self.byName, self.byNameAt = byName, stamp
    return byName
end

--------------------------------------------------------------------------------
-- Skinning, shown or left out
--
-- A player asked for Farmer to show drops only, without skinning (the owner
-- agreed 2026-10-11, and asked for it on by default). "Hide skinning" in
-- Settings (`hideSkinning`, account wide, on unless unticked; never rename
-- it) and /farm skinning. Ticked, what Farmer lists as where to farm and what a kill is worth leaves out
-- every skinning spot, and every item that comes from skinning: a skin
-- opens a loot window like a corpse does, so recorded loot has the leather
-- as one of the mob's drops, and only the item tells them apart. Nothing
-- recorded is changed or deleted; unticking it puts it all back. A goal
-- is the player's own ask, so goals and their arrow still follow one.
--------------------------------------------------------------------------------

-- Moves whenever the setting or the hide list below does, so what was
-- worked out before is worked out again on its next draw.
DB.hiddenVersion = 0

-- What redraws when it moves, each called inside a pcall and doing nothing
-- for a window not built: [name] = function.
DB.hideWatchers = {}

--- Is skinning shown? (Only once "Hide skinning" is unticked.)
function DB:ShowsSkinning()
    return ns.db ~= nil and ns.db.hideSkinning == false
end

--- Does the item named `name` come from skinning? The data names a
--- skinning spot for it (leather, hides, scales), or this account has seen
--- it in a skinning window (DB:WasSkinned), which catches what the data
--- misses: Forever's own skins, and ones it only lists as a drop.
function DB:FromSkinning(name)
    local item = type(name) == "table" and name or self:GetItem(name)
    if item ~= nil and item.fromSkinning == true then return true end
    return self:WasSkinned(item or name)
end

--------------------------------------------------------------------------------
-- The hide list
--
-- The owner asked (2026-10-11) for a blacklist beside Hide skinning: a mob,
-- a node or an item the player never wants to see. Right-click a row in the
-- search, Rankings, Grind or the kills panel ("Hide"), or /farm hide and a
-- name; the Hidden window (/farm hidden, Settings > Loot) lists them with
-- Show again. Kept account wide in `hiddenItems` and `hiddenSources`
-- ([lower case name] = the name as shown; never rename either). Like
-- skinning, it only leaves things out of what is shown: nothing recorded is
-- changed. A goal still follows its item.
--------------------------------------------------------------------------------

--- The saved list for "item" or "source" (a mob or a node), made on first use.
function DB:HiddenList(kind)
    local db = ns.db
    if not db then return {} end
    local key = kind == "item" and "hiddenItems" or "hiddenSources"
    if type(db[key]) ~= "table" then db[key] = {} end
    return db[key]
end

--- How the list keys an item: the data's own (English) name when it knows
--- the item, so a German client's name hides the same entry.
local function ItemKey(name)
    local item = type(name) == "table" and name or DB:GetItem(name)
    if item then return item.name:lower(), item.name end
    if type(name) ~= "string" then return nil end
    local trimmed = Util.Trim(name)
    if trimmed == "" then return nil end
    return trimmed:lower(), trimmed
end

--------------------------------------------------------------------------------
-- Skinned on this account
--
-- Every item a skinning window gave is noted, account wide, in
-- `skinnedItems` ([lower case name] = the name; never rename it), keyed like
-- the hide list. "Hide skinning" then leaves it out wherever it counts,
-- though the data never named a skinning spot for it. Only a note: nothing
-- recorded changes, and unticking shows it again.
--------------------------------------------------------------------------------

--- Has this account skinned the item (or item named `name`)?
function DB:WasSkinned(name)
    local db = ns.db
    local list = db and db.skinnedItems
    if type(list) ~= "table" or next(list) == nil then return false end
    local key = ItemKey(name)
    return key ~= nil and list[key] ~= nil
end

--- A skinning window gave `names`: note the ones not noted yet. While
--- skinning is hidden, what shows them redraws once.
function DB:NoteSkinned(names)
    local db = ns.db
    if not db or type(names) ~= "table" then return end
    if type(db.skinnedItems) ~= "table" then db.skinnedItems = {} end
    local list, added = db.skinnedItems, false
    for _, name in ipairs(names) do
        local key, shown = ItemKey(name)
        if key and list[key] == nil then
            list[key] = shown
            added = true
        end
    end
    if added and not self:ShowsSkinning() then self:HiddenChanged() end
end

local function SourceKey(name)
    if type(name) ~= "string" then return nil end
    local trimmed = Util.Trim(name)
    if trimmed == "" then return nil end
    return trimmed:lower(), trimmed
end

--- Is anything on the hide list? (Most players never use it, so every
--- check below costs one look when it is empty.)
function DB:HidesAny(kind)
    local db = ns.db
    local list = db and db[kind == "item" and "hiddenItems" or "hiddenSources"]
    return type(list) == "table" and next(list) ~= nil
end

--- Is the mob or node named `name` on the hide list?
function DB:IsHiddenSource(name)
    if not self:HidesAny("source") then return false end
    local key = SourceKey(name)
    return key ~= nil and self:HiddenList("source")[key] ~= nil
end

--- The item's own name for a random suffix ("Primal Leggings of the
--- Monkey" is Primal Leggings), or nil when `name` has none.
local function RollBaseOf(name)
    local Harvest, Tracker = ns.Harvest, ns.Tracker
    if type(name) ~= "string" or not (Harvest and Harvest.RollBase and Tracker) then return nil end
    local ok, base = pcall(function() return Harvest.RollBase(name, Tracker:LookOf(name).id) end)
    return ok and base ~= name and base or nil
end

--- Is the item (or item named `name`) on the hide list? A random suffix
--- counts as its item, so hiding Primal Leggings hides every roll of it
--- (the lists show the item once, by its own name).
function DB:IsHiddenItem(name)
    if not self:HidesAny("item") then return false end
    local list = self:HiddenList("item")
    local key = ItemKey(name)
    if key ~= nil and list[key] ~= nil then return true end
    local base = RollBaseOf(name)
    local baseKey = base and ItemKey(base)
    return baseKey ~= nil and list[baseKey] ~= nil
end

--- Is the item named `name` (or the item itself) left out right now: from
--- skinning while skinning is hidden, or on the hide list?
function DB:HidesItem(name)
    if not self:ShowsSkinning() and self:FromSkinning(name) then return true end
    return self:IsHiddenItem(name)
end

--- Is `source` of `item` left out right now?
function DB:HidesSource(source, item)
    if type(source) ~= "table" then return false end
    if not self:ShowsSkinning() and (source.kind == "skinning"
        or (item ~= nil and self:FromSkinning(item))) then
        return true
    end
    if item ~= nil and self:IsHiddenItem(item) then return true end
    return self:IsHiddenSource(source.name)
end

--- Something hidden or shown again: what was worked out before is worked
--- out again, and what shows it redraws.
function DB:HiddenChanged()
    self.hiddenVersion = self.hiddenVersion + 1
    for _, redraw in pairs(self.hideWatchers) do pcall(redraw) end
end

--- Put `name` on the hide list as an "item" or a "source". Returns the name
--- as kept, or nil when there is no name.
function DB:Hide(kind, name)
    local key, shown
    if kind == "item" then key, shown = ItemKey(name) else key, shown = SourceKey(name) end
    if not key then return nil end
    self:HiddenList(kind)[key] = shown
    self:HiddenChanged()
    return shown
end

--- Take `name` off the hide list. Returns the name it had, or nil when it
--- was not on it.
function DB:Unhide(kind, name)
    local key
    if kind == "item" then key = ItemKey(name) else key = SourceKey(name) end
    local list = self:HiddenList(kind)
    local had = key and list[key]
    if not had then return nil end
    list[key] = nil
    self:HiddenChanged()
    return had
end

--- Everything on the hide list, A to Z: { { kind, name }, ... }.
function DB:HiddenEntries()
    local out = {}
    for _, kind in ipairs({ "source", "item" }) do
        for _, name in pairs(self:HidesAny(kind) and self:HiddenList(kind) or {}) do
            if type(name) == "string" then out[#out + 1] = { kind = kind, name = name } end
        end
    end
    table.sort(out, function(a, b)
        if a.name:lower() ~= b.name:lower() then return a.name:lower() < b.name:lower() end
        return a.kind < b.kind
    end)
    return out
end

--- Show skinning or leave it out, and redraw what lists it.
function DB:SetShowSkinning(on)
    on = on and true or false
    if ns.db then ns.db.hideSkinning = not on end
    self:HiddenChanged()
end

--- Every item, in registration order.
function DB:Iterate()
    local index = 0
    return function()
        index = index + 1
        local key = self.order[index]
        if key then return self.items[key] end
    end
end

function DB:KindLabel(kind)
    return self.KIND_LABEL[kind] or kind
end

-- Short tag for the column view, where "mining node" is too wide to fit.
DB.KIND_TAG = {
    mob       = "MOB",
    node      = "ORE",
    herb      = "HERB",
    skinning  = "SKIN",
    fishing   = "FISH",
    container = "BOX",
    vendor    = "NPC",
    quest     = "QUEST",
}

function DB:KindTag(kind)
    return self.KIND_TAG[kind] or string.upper(kind or "?")
end

--- "Durnholde Keep, 80.6 45.2" -- whichever parts are known.
function DB:WhereText(source)
    local coords = source.coords

    if source.location and coords then
        return ("%s  %.1f, %.1f"):format(source.location, coords[1], coords[2])
    end

    if source.location then return source.location end
    if coords then return ("%.1f, %.1f"):format(coords[1], coords[2]) end

    return nil
end

--- How many sources come from each provenance, for `/farm data`.
function DB:CountByProvenance()
    local counts = {}

    for key in pairs(self.PROVENANCE) do
        counts[key] = 0
    end

    for _, key in ipairs(self.order) do
        for _, source in ipairs(self.items[key].sources) do
            local kind = source.provenance or self.DEFAULT_PROVENANCE
            counts[kind] = (counts[kind] or 0) + 1
        end
    end

    return counts
end

--[[----------------------------------------------------------------------------
  Creature types, as the Forever client names them ("Humanoid", "Beast"),
  by mob name. Only ever filled from what the game itself said: the harvest
  export writes the types the addon read off mobs in game
  (Logic/Grinding.lua), and the generated data file hands them back here:

    DB:CreatureTypes({ ["Witchwing Slayer"] = "Humanoid" })

  Nothing is typed in by hand or guessed from a mob's name or drops. A mob
  with no entry is a mob whose type nobody has seen yet.
------------------------------------------------------------------------------]]

DB.creatureTypes = {}

function DB:CreatureTypes(map)
    if type(map) ~= "table" then return end
    for name, kind in pairs(map) do
        if type(name) == "string" and name ~= "" and type(kind) == "string" and kind ~= "" then
            self.creatureTypes[name] = kind
        end
    end
end
