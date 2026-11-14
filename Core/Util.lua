-- Blackthornes Farmer -- Core/Util.lua
-- Small text helpers shared by the search and the window.

local _, ns = ...

local Util = {}
ns.Util = Util

function Util.Trim(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Is the client in English? The data names items, zones and skills in
--- English, so only another language needs the client's own names looked
--- up. A client that will not say counts as English, as before.
function Util.EnglishClient()
    if type(GetLocale) ~= "function" then return true end
    local ok, locale = pcall(GetLocale)
    if not ok or type(locale) ~= "string" then return true end
    return locale == "enUS" or locale == "enGB"
end

--- Strip the |cffffffff ... |r escapes, so text can be measured or compared.
function Util.StripColor(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function Util.Colored(colorKey, text)
    return ("|c%s%s|r"):format(ns.COLORS[colorKey] or ns.COLORS.text, text)
end

--- "1 spot" / "4 spots", because "1 spots" reads as a bug.
function Util.Plural(count, singular, plural)
    if count == 1 then return "1 " .. singular end
    return ("%d %s"):format(count, plural or (singular .. "s"))
end

--- A copy of `items` in the order a sortable heading asks for: by
--- `valueOf(item)` (a number or a string), lowest first when `ascending`,
--- else highest first. Items with nothing to sort by (nil) go last either
--- way, and ties keep the order they came in, so a heading never shuffles
--- rows it cannot tell apart.
function Util.SortBy(items, ascending, valueOf)
    local keyed = {}
    for index, item in ipairs(items or {}) do
        local value = valueOf(item)
        if type(value) == "string" then value = value:lower() end
        if value ~= nil and type(value) ~= "number" and type(value) ~= "string" then value = nil end
        keyed[index] = { item = item, value = value, position = index }
    end

    table.sort(keyed, function(a, b)
        if (a.value == nil) ~= (b.value == nil) then return b.value == nil end
        if a.value ~= nil and type(a.value) == type(b.value) and a.value ~= b.value then
            if ascending then return a.value < b.value end
            return a.value > b.value
        end
        return a.position < b.position
    end)

    local sorted = {}
    for index, entry in ipairs(keyed) do sorted[index] = entry.item end
    return sorted
end

--------------------------------------------------------------------------------
-- Item names in their rarity colour
--
-- The owner asked (2026-10-18) for item names to show in their rarity colour
-- everywhere: grey, white, green, blue, purple, orange, as the bags draw
-- them. An item's quality comes from the colour its loot link carried (kept
-- in the tracker's looks), else the client, by its ID (the database's, else
-- the one the loot link gave). A quality is kept once found, by ID and by
-- name; a miss stays a miss and asks the client to load the item once, so
-- nothing is asked every draw. When an item asked for arrives, the lists
-- that name items are told once (a short wait gathers a burst), and redraw.
--------------------------------------------------------------------------------

local qualityByID = {}
local qualityByName = {}
local requested = {}
local missedAt = {}
local hexOfQuality = {}
-- A miss is asked of the client again only after this long (or once the
-- item arrives), so a label drawn every frame never asks every frame.
Util.RARITY_RETRY = 5

-- Moves whenever a quality is learned late, so a row keyed by its text can
-- tell its colour may have changed.
Util.rarityVersion = 0

-- What redraws when a late quality comes in: [key] = function, each called
-- in a pcall.
Util.rarityWatchers = {}

-- The game's own colours, for a client that will not say.
local FALLBACK_HEX = {
    [0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd",
    [4] = "ffa335ee", [5] = "ffff8000", [6] = "ffe6cc80", [7] = "ff00ccff",
}

local function Number(value)
    local readable = ns.Harvest and ns.Harvest.ReadableNumber
    if readable then return readable(value) end
    return type(value) == "number" and value or nil
end

local function Channel(value)
    value = Number(value)
    if not value then return nil end
    return math.max(0, math.min(255, math.floor(value * 255 + 0.5)))
end

--- "ff1eff00" for a quality, 0 to 7; nil for anything else.
function Util.QualityHex(quality)
    quality = tonumber(quality)
    if not quality then return nil end
    local known = hexOfQuality[quality]
    if known then return known end

    local hex
    local colors = _G.ITEM_QUALITY_COLORS
    local color = type(colors) == "table" and colors[quality] or nil
    if type(color) == "table" then
        local r, g, b = Channel(color.r), Channel(color.g), Channel(color.b)
        if r and g and b then hex = ("ff%02x%02x%02x"):format(r, g, b) end
    end
    if not hex and type(C_Item) == "table" and type(C_Item.GetItemQualityColor) == "function" then
        local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
        r, g, b = ok and Channel(r), ok and Channel(g), ok and Channel(b)
        if r and g and b then hex = ("ff%02x%02x%02x"):format(r, g, b) end
    end
    hex = hex or FALLBACK_HEX[quality]
    if hex then hexOfQuality[quality] = hex end
    return hex
end

local function QualityOfColor(color)
    if type(color) ~= "string" then return nil end
    color = color:lower()
    for quality, hex in pairs(FALLBACK_HEX) do
        if hex == color then return quality end
    end
    local quality = ns.Tracker and ns.Tracker.QUALITY
    if type(quality) == "table" then
        for q, hex in pairs(quality) do
            if hex == color then return q end
        end
    end
    return nil
end

local function AskClient(id)
    local item = type(C_Item) == "table" and C_Item or nil
    if item and type(item.GetItemQualityByID) == "function" then
        local ok, quality = pcall(item.GetItemQualityByID, id)
        quality = ok and Number(quality) or nil
        if quality then return quality end
    end
    local getInfo = (item and item.GetItemInfo) or _G.GetItemInfo
    if type(getInfo) == "function" then
        local ok, quality = pcall(function() return select(3, getInfo(id)) end)
        quality = ok and Number(quality) or nil
        if quality then return quality end
    end
    return nil
end

local notifying = false

local function Notify()
    notifying = false
    for _, fn in pairs(Util.rarityWatchers) do pcall(fn) end
end

local function Arrived(itemID)
    local id = Number(itemID)
    if not (id and requested[id]) then return end
    requested[id] = nil
    missedAt[id] = nil
    local quality = AskClient(id)
    if not quality then return end
    qualityByID[id] = quality
    Util.rarityVersion = Util.rarityVersion + 1
    if notifying then return end
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        notifying = true
        C_Timer.After(0.3, Notify)
    else
        Notify()
    end
end

local listening = false

local function Request(id)
    if requested[id] then return end
    requested[id] = true
    if not listening and ns.RegisterEvent then
        listening = true
        ns.RegisterEvent(Util, "GET_ITEM_INFO_RECEIVED", function(_, _, itemID) Arrived(itemID) end)
    end
    local item = type(C_Item) == "table" and C_Item or nil
    if item and type(item.RequestLoadItemDataByID) == "function" then
        pcall(item.RequestLoadItemDataByID, id)
    end
end

--- The ID that goes with an item's name: the database's, else its loot link's.
function Util.ItemIDOf(name)
    if type(name) ~= "string" then return nil end
    local DB = ns.DB
    if DB and DB.items then
        local item = DB.items[name:lower()]
        if not item and type(DB.GetItem) == "function" then
            local ok, found = pcall(DB.GetItem, DB, name)
            item = ok and found or nil
        end
        if type(item) == "table" and tonumber(item.id) then return tonumber(item.id) end
    end
    local looks = ns.db and type(ns.db.tracker) == "table" and ns.db.tracker.looks
    local look = type(looks) == "table" and looks[name]
    if type(look) ~= "table" and ns.Tracker and ns.Tracker.rollLooks then
        local suffix = ns.Tracker.rollLooks[name]
        look = suffix and looks and looks[suffix]
    end
    return type(look) == "table" and tonumber(look.id) or nil
end

--- An item's quality, 0 to 7, by name and/or ID; nil while nobody knows.
function Util.ItemQuality(name, id)
    if type(name) ~= "string" then name = nil end
    id = tonumber(id)

    if id and qualityByID[id] then return qualityByID[id] end
    if name and qualityByName[name] then return qualityByName[name] end

    -- The colour its own loot link carried.
    if name then
        local looks = ns.db and type(ns.db.tracker) == "table" and ns.db.tracker.looks
        local look = type(looks) == "table" and looks[name]
        if type(look) ~= "table" and ns.Tracker and ns.Tracker.rollLooks and looks then
            local suffix = ns.Tracker.rollLooks[name]
            look = suffix and looks[suffix]
        end
        if type(look) == "table" then
            local quality = QualityOfColor(look.color)
            if quality then
                qualityByName[name] = quality
                return quality
            end
            id = id or tonumber(look.id)
        end
    end

    id = id or Util.ItemIDOf(name)
    if not id then return nil end
    if qualityByID[id] then return qualityByID[id] end

    local now = type(GetTime) == "function" and tonumber((select(2, pcall(GetTime)))) or 0
    local missed = missedAt[id]
    if missed and now >= missed and now - missed < Util.RARITY_RETRY then return nil end

    local quality = AskClient(id)
    if quality then
        qualityByID[id] = quality
        missedAt[id] = nil
        return quality
    end
    missedAt[id] = now
    Request(id)
    return nil
end

--- "ff1eff00" for an item, or nil while its quality is not known.
function Util.ItemHex(name, id)
    return Util.QualityHex(Util.ItemQuality(name, id))
end

--- An item's rarity colour as three numbers, or nil while not known.
function Util.ItemRGB(name, id)
    local hex = Util.ItemHex(name, id)
    if not hex then return nil end
    return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255,
        tonumber(hex:sub(7, 8), 16) / 255
end

--- `text` (the item's name when nil) wrapped in the item's rarity colour,
--- or as it is while the quality is not known. For showing only: never
--- save, compare or share what it gives.
function Util.ColorItem(name, id, text)
    text = text or name
    if type(text) ~= "string" or text == "" then return text end
    local hex = Util.ItemHex(name, id)
    if not hex then return text end
    return ("|c%s%s|r"):format(hex, text)
end

--- The item's rarity colour as hex, else the colour `colorKey` names
--- (ns.COLORS), for text that had one of its own before.
function Util.ItemHexOr(colorKey, name, id)
    return Util.ItemHex(name, id) or ns.COLORS[colorKey] or ns.COLORS.text
end

--- `text` (the name when nil) in the item's rarity colour, else in the
--- colour `colorKey` names.
function Util.ColorItemOr(colorKey, name, id, text)
    text = text or name
    if type(text) ~= "string" then return text end
    return ("|c%s%s|r"):format(Util.ItemHexOr(colorKey, name, id), text)
end

--- Redraw `fn` (in a pcall) when a quality comes in late.
function Util.OnRarity(key, fn)
    Util.rarityWatchers[key] = fn
end

--- For the tests: forget what was learned.
function Util.ForgetRarity()
    qualityByID, qualityByName, requested, missedAt = {}, {}, {}, {}
    hexOfQuality = {}
end

--------------------------------------------------------------------------------
-- Letting old entries go
--
-- Tables of corpses opened this session grew all session long. A corpse is
-- gone from the world long before half an hour, so an entry that old can go.
-- Each new entry looks at a few of the oldest and lets go of those past the
-- age, so nothing runs on a timer and no frame does much. Session tables only:
-- nothing saved goes through this.
--------------------------------------------------------------------------------

local function Now()
    if type(GetTime) ~= "function" then return nil end
    local ok, now = pcall(GetTime)
    if ok and type(now) == "number" then return now end
    return nil
end

--- A first in, first out list of keys with when each came in.
-- forget(key) is called for each key let go.
function Util.NewAging(seconds, forget, perStep)
    local aging = { keys = {}, times = {}, head = 1, seconds = seconds,
        perStep = perStep or 4, forget = forget }

    function aging:Add(key, now)
        now = now or Now()
        if key == nil or not now then return end
        local n = #self.keys + 1
        self.keys[n], self.times[n] = key, now
        self:Sweep(now)
    end

    function aging:Sweep(now)
        now = now or Now()
        if not now then return end
        local done = 0
        while done < self.perStep do
            local at = self.times[self.head]
            if not at or now - at < self.seconds then break end
            local key = self.keys[self.head]
            self.keys[self.head], self.times[self.head] = false, false
            self.head = self.head + 1
            done = done + 1
            pcall(self.forget, key)
        end
        -- Shift down now and then, so the lists don't keep their dead front.
        if self.head > 64 and self.head * 2 > #self.keys then
            local keys, times = {}, {}
            for i = self.head, #self.keys do
                keys[#keys + 1], times[#times + 1] = self.keys[i], self.times[i]
            end
            self.keys, self.times, self.head = keys, times, 1
        end
    end

    function aging:Clear()
        self.keys, self.times, self.head = {}, {}, 1
    end

    return aging
end
