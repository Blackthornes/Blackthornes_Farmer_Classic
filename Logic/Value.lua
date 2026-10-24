-- Blackthornes Farmer -- Logic/Value.lua
-- What a kill is worth, priced by Blackthornes Tradeskills.
--
-- Tradeskills scans the auction house and keeps a market value per item for
-- your realm and faction. When both addons are loaded, this reads those prices
-- -- read only, straight from Tradeskills in game, nothing copied or written
-- -- and turns a mob's drops into one number: copper per kill.
--
--   per kill = coin per kill
--            + for each item: (how many dropped / kills) x unit price
--
-- A unit price is the auction market value, or what a vendor pays if that is
-- more (nobody sells grey scraps on the auction house for less than the
-- vendor gives). A grey item is only ever its vendor price, whatever the
-- auction house says. Without Tradeskills, TradeSkillMaster's or Auctionator's
-- price stands in when one of them is loaded (the owner asked 2026-10-12;
-- `otherPriceAddons`, on unless unticked); with none of them only the vendor
-- price is known, and the value says so.
--
-- Where the numbers come from, best first:
--   1. your own tally, once a mob has MIN_KILLS kills -- measured amounts and
--      coin, the real thing;
--   2. the database's drop rates for that mob -- one of each item at its
--      rate, no coin, so an underestimate, and labelled as one.
-- Below that there is no value at all. A price times a guessed rate is a
-- guess with a gold sign on it.

local _, ns = ...
local L = ns.L

local Value = ns.NewModule("Value")

local Util = ns.Util

--------------------------------------------------------------------------------
-- Prices
--------------------------------------------------------------------------------

--- Tradeskills' price module, if it is loaded and looks like we expect.
function Value:Prices()
    local ts = _G.BlackthornesTS
    if type(ts) ~= "table" then return nil end

    local prices = ts.Prices
    if type(prices) ~= "table" or type(prices.GetValue) ~= "function" then return nil end

    return prices
end

function Value:HasAuctionPrices()
    return self:PriceSource() ~= nil
end

--------------------------------------------------------------------------------
-- TradeSkillMaster and Auctionator, when Tradeskills is not loaded
--------------------------------------------------------------------------------
-- Read only, inside a pcall, through each addon's own API, with no TOC
-- dependency. Tradeskills, when loaded, already asks them itself for items
-- it has not priced, so they are read here only without it:
--   TSM_API.GetCustomPriceValue("DBMarket", "i:<itemID>")
--   Auctionator.API.v1.GetAuctionPriceByItemID("Blackthornes_Farmer", itemID)
-- TSM first. Prices are read many times a draw, so each answer is kept
-- OTHER_CACHE_FOR seconds.

Value.OTHER_CACHE_FOR = 60
Value.OTHER_MAX_PRICE = 1e11   -- above this is not a price (10 million gold)
local otherCache = {}          -- [itemID] = { copper or false, at }

local function Clock()
    if type(GetTime) ~= "function" then return 0 end
    local ok, now = pcall(GetTime)
    return ok and tonumber(now) or 0
end

function Value:UsesOtherAddons()
    return not (ns.db and ns.db.otherPriceAddons == false)
end

local function TSMCall()
    local api = rawget(_G, "TSM_API")
    if type(api) ~= "table" or type(api.GetCustomPriceValue) ~= "function" then return nil end
    return api.GetCustomPriceValue
end

local function AuctionatorCall()
    local addon = rawget(_G, "Auctionator")
    local api = type(addon) == "table" and type(addon.API) == "table" and addon.API.v1
    if type(api) ~= "table" or type(api.GetAuctionPriceByItemID) ~= "function" then return nil end
    return api.GetAuctionPriceByItemID
end

local function Copper(ok, value)
    if not ok or type(value) ~= "number" or value ~= value then return nil end
    if value <= 0 or value > Value.OTHER_MAX_PRICE then return nil end
    return math.floor(value + 0.5)
end

--- Where auction prices come from now: "tradeskills", "tsm", "auctionator"
--- ("tsm" when both of the last two are loaded), or nil for vendor only.
function Value:PriceSource()
    if self:Prices() then return "tradeskills" end
    if not self:UsesOtherAddons() then return nil end
    if TSMCall() then return "tsm" end
    if AuctionatorCall() then return "auctionator" end
    return nil
end

--- TradeSkillMaster's, else Auctionator's market value for one, in copper.
function Value:OtherPrice(itemID)
    if type(itemID) ~= "number" or not self:UsesOtherAddons() then return nil end
    local tsm, auctionator = TSMCall(), AuctionatorCall()
    if not tsm and not auctionator then return nil end

    local now = Clock()
    local kept = otherCache[itemID]
    if kept and now - kept[2] < self.OTHER_CACHE_FOR and now >= kept[2] then
        return kept[1] or nil
    end

    local copper
    if tsm then copper = Copper(pcall(tsm, "DBMarket", "i:" .. itemID)) end
    if not copper and auctionator then
        copper = Copper(pcall(auctionator, "Blackthornes_Farmer", itemID))
    end
    otherCache[itemID] = { copper or false, now }
    return copper
end

--- Turn reading TSM and Auctionator on or off.
function Value:SetUsesOtherAddons(on)
    if not ns.db then return end
    ns.db.otherPriceAddons = on and true or false
    otherCache = {}
end

-- What item tooltips said a vendor pays, kept for the session.
local tooltipSellPrice = {}

-- Items whose tooltip could not be read yet (the client is still fetching
-- the item): when each was asked. The Rankings board prices hundreds of
-- items a draw, and asking the client for every unloaded one again on every
-- kill was a hitch, so one is asked again once the item arrives
-- (GET_ITEM_INFO_RECEIVED), or after a short wait if that never comes.
local waiting = {}
local WAIT = 5

local function Now()
    if type(GetTime) ~= "function" then return 0 end
    local ok, now = pcall(GetTime)
    return ok and tonumber(now) or 0
end

--- The item arrived: its tooltip can be read now.
function Value:ItemArrived(itemID)
    local id = ns.Harvest.ReadableNumber(itemID)
    if id then waiting[id] = nil end
end

function Value:OnEnable()
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", function(_, _, itemID) Value:ItemArrived(itemID) end)
end

--- What the item's tooltip says a vendor pays for one, or nil when it shows
--- no sell price. Forever changed some sell prices from Classic's and only
--- the tooltip has the new one: Greater Magic Wand's says 1c while the item
--- info still says Classic's 15s 35c (2026-10-03).
function Value:TooltipSellPrice(itemID)
    local known = tooltipSellPrice[itemID]
    if known ~= nil then return known or nil end

    local getTooltip = C_TooltipInfo and C_TooltipInfo.GetItemByID
    if type(getTooltip) ~= "function" then return nil end

    local asked = itemID and waiting[itemID]
    local now = Now()
    if asked and now - asked < WAIT and now >= asked then return nil end

    local ok, price, read = pcall(function()
        local data = getTooltip(itemID)
        if type(data) ~= "table" or type(data.lines) ~= "table" or #data.lines == 0 then return nil, false end

        local enum = Enum and Enum.TooltipDataLineType
        local sellType = (type(enum) == "table" and enum.SellPrice) or 11
        for _, line in ipairs(data.lines) do
            if type(line) == "table" and line.type == sellType and type(line.price) == "number" then
                return line.price, true
            end
        end
        return nil, true
    end)
    if not ok then return nil end

    -- Only a tooltip that was there to read is kept. One for an item the
    -- client has not loaded yet says "Retrieving item information" and no
    -- price, so "no sell price" is only kept once the item is loaded;
    -- kept sooner, the stale item info price would win for the session.
    price = ns.Harvest.ReadableNumber(price)
    if read and not price then
        local cached = C_Item and C_Item.IsItemDataCachedByID
        if type(cached) == "function" then
            local gotCached, isCached = pcall(cached, itemID)
            local plain, loaded = pcall(function() return isCached == true end)
            if not (gotCached and plain and loaded) then read = false end
        end
    end
    if read then
        tooltipSellPrice[itemID] = price or false
        waiting[itemID] = nil
    elseif itemID then
        waiting[itemID] = now
    end
    return price
end

-- What a vendor pays and whether an item is grey never change in a session,
-- so each is kept once the client has answered. A render prices the same
-- items many times over; without these it asked the client every time.
local vendorPrice = {}
local poor = {}

local function SellPriceOf(getInfo, itemID)
    return select(11, getInfo(itemID))
end

local function QualityOf(getInfo, itemID)
    return select(3, getInfo(itemID))
end

--- What a vendor pays for one: the tooltip's price, else the item info's.
function Value:VendorPrice(itemID)
    local known = vendorPrice[itemID]
    if known ~= nil then return known or nil end

    local getInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    if type(getInfo) ~= "function" then return nil end

    local ok, sellPrice = pcall(SellPriceOf, getInfo, itemID)
    if not ok then return nil end

    local fromTooltip = self:TooltipSellPrice(itemID)
    if fromTooltip then sellPrice = fromTooltip end

    local copper = ns.Harvest.ReadableNumber(sellPrice)
    if not (copper and copper > 0) then copper = nil end

    -- Kept only once both sides have answered: the tooltip read settled and
    -- the item info loaded (a sell price, even 0), so a price still on its
    -- way is asked for again next time.
    if itemID and tooltipSellPrice[itemID] ~= nil and (fromTooltip or ns.Harvest.ReadableNumber(sellPrice)) then
        vendorPrice[itemID] = copper or false
    end

    return copper
end

--- Tradeskills' market value for one, in copper; without Tradeskills,
--- TradeSkillMaster's or Auctionator's.
function Value:AuctionPrice(itemID)
    local prices = self:Prices()
    if not prices then return self:OtherPrice(itemID) end

    local ok, copper = pcall(prices.GetValue, prices, itemID)
    if not ok then return nil end

    copper = ns.Harvest.ReadableNumber(copper)
    if copper and copper > 0 then return copper end

    return nil
end

--- True for a grey (poor quality) item: from the client's item info, else
--- from the colour of a loot link we have seen for it. The second answer
--- says whether the quality is known at all: false while the client is
--- still loading an item no grey link was seen for.
function Value:IsPoor(itemID)
    local known = poor[itemID]
    if known ~= nil then return known, true end

    local getInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    if type(getInfo) == "function" then
        local ok, quality = pcall(QualityOf, getInfo, itemID)
        quality = ok and ns.Harvest.ReadableNumber(quality) or nil
        if quality then
            if itemID then poor[itemID] = quality == 0 end
            return quality == 0, true
        end
    end

    -- Item info not cached yet: a loot link's colour says the same thing.
    if itemID and self:GreyLinks()[itemID] then
        poor[itemID] = true
        return true, true
    end
    if itemID and self.greyLinks and self.greyLinks.colored[itemID] then
        return false, true
    end

    return false, false
end

--- Item ids a grey loot link has been seen for, from the kept looks. Walked
--- once per change to the looks, not once per item priced.
function Value:GreyLinks()
    local Tracker = ns.Tracker
    local version = Tracker and Tracker.looksVersion or 0
    local kept = self.greyLinks
    if kept and kept.version == version then return kept.ids end

    local ids, colored = {}, {}
    local grey = Tracker and Tracker.QUALITY and Tracker.QUALITY[0]
    if grey and Tracker.Looks then
        for _, look in pairs(Tracker:Looks()) do
            if type(look) == "table" and look.id and look.color then
                if look.color == grey then ids[look.id] = true else colored[look.id] = true end
            end
        end
    end
    -- `colored`: a link seen in another colour, so not grey.
    self.greyLinks = { version = version, ids = ids, colored = colored }
    return ids
end

--- One unit's worth and where the number came from ("auction" or "vendor").
-- A grey item is only ever worth what a vendor pays (2026-09-25): the
-- auction house is no price for vendor trash, whatever a scan once saw.
function Value:UnitPrice(itemID)
    if not itemID then return nil end

    local vendor = self:VendorPrice(itemID)
    local isPoor, sure = self:IsPoor(itemID)
    -- Not known yet counts as grey: right after login a grey the client
    -- had not loaded took a thin market's auction price (a 3c fang at 50s).
    -- Asking has the client load it, and the next draw has its quality.
    if isPoor or not sure then
        if vendor then return vendor, "vendor" end
        return nil
    end

    local auction = self:AuctionPrice(itemID)

    if auction and (not vendor or auction >= vendor) then return auction, "auction" end
    if vendor then return vendor, "vendor" end

    return nil
end

--- The item id for a name: from the loot link, else the database.
function Value:ItemID(name)
    local look = ns.Tracker and ns.Tracker:LookOf(name)
    if look and look.id then return look.id end

    local item = ns.DB and ns.DB:GetItem(name)
    if item and item.id then return item.id end

    return nil
end

--------------------------------------------------------------------------------
-- What a clam or a sack is worth opened
--------------------------------------------------------------------------------

-- A clam, a sack or a lockbox you opened from your bags is worth what came
-- out of it, once you've opened enough to say (Containers keeps them by
-- name). 10 openings, or it says nothing (the owner picked 10 over 20,
-- 2026-10-15, so it shows sooner).
Value.MIN_OPENS = 10

--- What one opening of `name` gives, in copper, or nil under MIN_OPENS or
--- with nothing in it priced. Returns worth, details { opens, priced =
--- { { name, id, chance, each, unit, perOpen } }, unpriced = { names } },
--- most worth first; `each` is how many came out of an opening that gave it.
--- Items on the hide list are left out.
function Value:Contents(name)
    local Containers = ns.Containers
    if not (Containers and name) then return nil end

    local ok, entry = pcall(Containers.Entry, Containers, name)
    if not ok or type(entry) ~= "table" or type(entry.items) ~= "table" then return nil end

    local opens = tonumber(entry.opens) or 0
    if opens < self.MIN_OPENS then return nil end

    local details = { opens = opens, priced = {}, unpriced = {} }
    local total = 0

    for item, got in pairs(entry.items) do
        local times = type(got) == "table" and tonumber(got.opens) or 0
        local hidden = ns.DB and ns.DB:HidesItem(item)
        if times > 0 and not hidden then
            local id = got.id or self:ItemID(item)
            local count = tonumber(got.count) or times
            local unit = self:UnitPrice(id)
            if unit then
                local perOpen = count / opens * unit
                total = total + perOpen
                details.priced[#details.priced + 1] = { name = item, id = id,
                    chance = times / opens * 100, each = count / times, unit = unit,
                    perOpen = perOpen }
            else
                details.unpriced[#details.unpriced + 1] = item
            end
        end
    end

    if #details.priced == 0 then return nil end

    table.sort(details.priced, function(a, b) return a.perOpen > b.perOpen end)
    table.sort(details.unpriced)

    return total, details
end

--- One of `name` (an item looted off a mob) is worth: what's inside when
--- it's a clam or a sack you've opened enough and that pays more, else
--- UnitPrice. Returns copper and "contents", "auction" or "vendor".
function Value:WorthOf(name, id)
    local unit, from = self:UnitPrice(id or self:ItemID(name))
    local inside = self:Contents(name)

    if inside and (not unit or inside > unit) then return inside, "contents" end

    return unit, from
end

--------------------------------------------------------------------------------
-- Quest items
--------------------------------------------------------------------------------

-- [itemID] = true or false, once the client has said.
local questItems = {}

-- The client's item class for quest items.
Value.QUEST_CLASS = 12

--- Is this a quest item? A player asked (2026-10-18, the owner said yes) to
--- see them in the loot lists as quest items, not as loot with no price.
--- They stay worth nothing, so no total changes. The client's item class
--- first, else the data's category; false when neither says so.
function Value:IsQuest(name, id)
    id = tonumber(id or self:ItemID(name))
    if id then
        local known = questItems[id]
        if known ~= nil then return known end

        local instant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
        if type(instant) == "function" then
            local ok, found, _, _, _, _, classID = pcall(instant, id)
            classID = ok and found ~= nil and tonumber(classID) or nil
            if classID then
                questItems[id] = classID == Value.QUEST_CLASS
                return questItems[id]
            end
        end
    end

    local item = name and ns.DB and ns.DB.GetItem and ns.DB:GetItem(name)
    return type(item) == "table" and item.category == "Quest item" or false
end

--------------------------------------------------------------------------------
-- A mob's worth
--------------------------------------------------------------------------------

--- Copper per kill from your own tally, or nil below MIN_KILLS.
-- Returns value, details: { basis = "tally", kills, copper, priced = {...},
-- unpriced = {...} } where each priced entry is { name, perKill, unit, from,
-- chance } (chance in percent of kills).
function Value:FromTally(mobName)
    local Tracker = ns.Tracker
    -- A line's key: a mob's name, or one zone's line of it.
    local mob = Tracker and Tracker:Tally(mobName)
    if type(mob) ~= "table" then return nil end

    local kills = tonumber(mob.kills) or 0
    if kills < Tracker.MIN_KILLS then return nil end

    local details = { basis = "tally", kills = kills, priced = {}, unpriced = {} }

    -- Coin over the kills that recorded it; items as how often each drops
    -- (every kill counts) times how many come at once (from the kills that
    -- recorded amounts). Old tallies with neither get no coin and one each.
    local coin = Tracker:CoinPerKill(mobName) or 0
    local total = coin

    details.coin = coin

    -- Skinning left out ("Hide skinning") and items on the hide list
    -- (DB:HidesItem) are left out of the worth.
    for name, corpses in pairs(type(mob.items) == "table" and mob.items or {}) do
        if ns.DB and ns.DB:HidesItem(name) then corpses = nil end
        local perCorpse = corpses and Tracker:StackSize(mobName, name)
        local unit, from
        if corpses then unit, from = self:WorthOf(name) end

        if not corpses then
            -- Left out: neither priced nor listed as unpriced.
        elseif unit then
            local perKill = (tonumber(corpses) or 0) / kills * perCorpse * unit
            total = total + perKill
            details.priced[#details.priced + 1] = { name = name, perKill = perKill, unit = unit,
                from = from, chance = (tonumber(corpses) or 0) / kills * 100 }
        else
            details.unpriced[#details.unpriced + 1] = name
        end
    end

    -- Nothing priced and no coin is not "worth nothing": it is unknown.
    if #details.priced == 0 and coin == 0 then return nil end

    details.priced = Value.FoldSuffixes(details.priced)
    table.sort(details.priced, function(a, b) return a.perKill > b.perKill end)
    table.sort(details.unpriced)

    return total, details
end

--- Priced drops with an item's random suffixes ("of the Monkey") put
--- together under the item's own name, so the best drops name the item
--- once. The worth is the same either way.
function Value.FoldSuffixes(priced)
    local Harvest, Tracker = ns.Harvest, ns.Tracker
    if not (Harvest and Harvest.RollBase and Tracker) then return priced end

    local out, byName = {}, {}
    for _, entry in ipairs(priced) do
        local base = Harvest.RollBase(entry.name, Tracker:LookOf(entry.name).id)
        local into = base and byName[base]
        if base and not into then
            -- Every roll shares the item's ID and quality, so the first
            -- roll's loot link stands in for them (Skip Uncommon reads it).
            into = { name = base, perKill = 0, chance = 0, from = entry.from,
                id = entry.id or Tracker:LookOf(entry.name).id, lookName = entry.name }
            byName[base] = into
            out[#out + 1] = into
        end
        if into then
            into.perKill = into.perKill + entry.perKill
            into.chance = into.chance + (entry.chance or 0)
            into.unit = into.chance > 0 and into.perKill / (into.chance / 100) or entry.unit
        else
            out[#out + 1] = entry
        end
    end
    return out
end

--- Copper per kill from the database's drop rates for this mob, or nil when
--- none of its drops has both a rate and a price.
function Value:FromDatabase(mobName)
    if not (ns.DB and mobName) then return nil end

    local details = { basis = "database", priced = {}, unpriced = {}, coin = 0 }
    local total, seen = 0, {}

    -- One zone's line of a mob reads that zone's rows, when the database
    -- has any there.
    local name, zone = mobName, nil
    if ns.Tracker and ns.Tracker.SplitKey then name, zone = ns.Tracker.SplitKey(mobName) end
    local rows = ns.DB:ByName()[name] or {}
    if zone then
        local here = {}
        for _, entry in ipairs(rows) do
            if entry.source and entry.source.zone == zone then here[#here + 1] = entry end
        end
        if #here > 0 then rows = here end
    end

    for _, entry in ipairs(rows) do
        local item, source = entry.item, entry.source
        if source.chance and not seen[item.name] then
            seen[item.name] = true

            local unit, from = self:WorthOf(item.name, item.id)

            if unit then
                local perKill = source.chance / 100 * unit
                total = total + perKill
                details.priced[#details.priced + 1] = { name = item.name, perKill = perKill,
                    unit = unit, from = from, chance = source.chance, id = item.id }
            else
                details.unpriced[#details.unpriced + 1] = item.name
            end
        end
    end

    if #details.priced == 0 then return nil end

    table.sort(details.priced, function(a, b) return a.perKill > b.perKill end)
    table.sort(details.unpriced)

    return total, details
end

--- The best value we have for a mob: your tally first, then the database.
function Value:ForMob(mobName)
    local value, details = self:FromTally(mobName)
    if value then return value, details end

    return self:FromDatabase(mobName)
end

--------------------------------------------------------------------------------
-- This session's haul
--------------------------------------------------------------------------------

--- What everything gathered this session is worth, in copper: the coin off
--- your kills, plus every item looted, fished up or gathered times its unit
--- price.
-- Returns total, details { coin, priced = count, unpriced = { names }, quest
-- = count or nil }, or
-- nil when nothing has been gathered yet. Items with no price are left out of
-- the total and listed, never guessed.
function Value:Session()
    local Tracker, Fishing, Gathering = ns.Tracker, ns.Fishing, ns.Gathering

    -- Skinning while it is hidden, and items on the hide list
    -- (DB:HidesItem), are left out of the worth and the gold per hour.
    local counts = {}
    local function Take(list)
        for name, count in pairs(list or {}) do
            if not (ns.DB and ns.DB:HidesItem(name)) then
                counts[name] = (counts[name] or 0) + count
            end
        end
    end
    Take(Tracker and Tracker.sessionLoot)
    Take(Fishing and Fishing.sessionCatch)
    Take(Gathering and Gathering.sessionItems)

    local coin = Tracker and tonumber(Tracker.sessionCopper) or 0
    local details = { coin = coin, priced = 0, unpriced = {} }
    local total = coin

    for name, count in pairs(counts) do
        -- A clam or a sack counts what's inside once you've opened enough.
        local unit = self:WorthOf(name)
        if unit then
            total = total + count * unit
            details.priced = details.priced + 1
        elseif self:IsQuest(name) then
            -- Worth nothing, and no price is missing for it.
            details.quest = (details.quest or 0) + 1
        else
            details.unpriced[#details.unpriced + 1] = name
        end
    end

    if details.priced == 0 and coin == 0 and #details.unpriced == 0 and not details.quest then
        return nil
    end

    table.sort(details.unpriced)

    return total, details
end

--------------------------------------------------------------------------------
-- Showing it
--------------------------------------------------------------------------------

--- "1g 2s 3c", dropping empty units; "0c" for nothing.
function Value.Money(copper)
    copper = math.floor((tonumber(copper) or 0) + 0.5)

    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper % 10000 / 100)
    local rest = copper % 100

    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end

    -- Past a gold, copper is noise: "1g 3c" said it and "1g 2s 3c" did not.
    if gold == 0 and (rest > 0 or #parts == 0) then parts[#parts + 1] = rest .. "c" end

    return table.concat(parts, " ")
end

-- The game's own coin colours (2026-09-28: "gold for g, silver for
-- s, copper for c").
local COIN_COLORS = { g = "ffffd700", s = "ffc7c7cf", c = "ffeda55f" }
Value.COIN_COLORS = COIN_COLORS

--- Value.Money, each part in its coin's colour: "|cffffd7001g|r ...". For
--- anything drawn on screen; Money stays plain for sums and tests.
function Value.Coins(copper)
    return (Value.Money(copper):gsub("(%d+)([gsc])", function(amount, unit)
        return ("|c%s%s%s|r"):format(COIN_COLORS[unit], amount, unit)
    end))
end

--- What the prices are, in a few words, for the end of a value line.
function Value:PriceNote(details)
    local auction = false
    for _, entry in ipairs(details.priced) do
        if entry.from == "auction" then auction = true end
    end

    if details.basis == "database" then
        return auction and L["auction prices, database rates"] or L["vendor prices, database rates"]
    end
    return auction and L["auction prices"] or L["vendor prices"]
end

--- A mob named loosely, spelled its own way whatever the case typed: one
--- you have killed or the database has by that exact name, else one whose
--- name starts with it, your own kills first. Nil when neither knows it.
function Value:ResolveMob(text)
    local wanted = Util.Trim(text or ""):lower()
    local found = ns.Tracker and ns.Tracker:ResolveMob(text or "")

    -- Your own kill by its full name, or the mob you last looted when
    -- nothing was typed. A start of a name waits: the database may have a
    -- mob by exactly that name.
    if found and (wanted == "" or found:lower() == wanted) then return found end
    if wanted == "" or not ns.DB then return found end

    local prefix
    for item in ns.DB:Iterate() do
        for _, source in ipairs(item.sources or {}) do
            local name = source.name
            local kind = source.kind or "mob"
            if type(name) == "string" and (kind == "mob" or kind == "skinning") then
                local lowered = name:lower()
                if lowered == wanted then return name end
                if lowered:sub(1, #wanted) == wanted and (not prefix or name < prefix) then
                    prefix = name
                end
            end
        end
    end

    return found or prefix
end

ns.RegisterCommand("value", L["what a mob is worth per kill, from Tradeskills prices"], function(rest)
    local wanted = Util.Trim(rest or "")
    local mobName = Value:ResolveMob(wanted) or (wanted ~= "" and wanted) or nil

    if not mobName then
        ns.Print(L["name a mob: /farm value <mob>."])
        return
    end

    local value, details = Value:ForMob(mobName)

    if not value then
        local summary = ns.Tracker:Summary(mobName)
        if summary and not summary.rated then
            ns.Print(summary.needed == 1
                and L.Format("%s: 1 more kill before it has a value.", mobName)
                or L.Format("%s: %d more kills before it has a value.", mobName, summary.needed))
        else
            ns.Print(L.Format("%s: none of its drops have both a rate and a price yet.", mobName))
        end
        return
    end

    ns.Print(L.Format("%s: about %s a kill %s",
        Util.Colored("accent", mobName),
        Value.Coins(value),
        Util.Colored("muted", ("(%s)"):format(Value:PriceNote(details)))))

    if details.coin and details.coin > 0 then
        ns.PrintRaw(L.Format("  coin  %s", Value.Coins(details.coin)))
    end

    for index = 1, math.min(#details.priced, 6) do
        local entry = details.priced[index]
        ns.PrintRaw(("  %s  %s"):format(entry.name,
            Value.Coins(entry.perKill)))
    end

    if #details.unpriced > 0 then
        ns.PrintRaw(Util.Colored("muted", L.Format("  no price yet: %s",
            table.concat(details.unpriced, ", "))))
    end

    if not Value:HasAuctionPrices() then
        ns.PrintRaw(Util.Colored("muted",
            L["  No auction prices are loaded, so these are vendor prices."]))
    end
end)
