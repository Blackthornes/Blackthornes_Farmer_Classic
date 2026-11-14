-- The shortcuts that keep Farmer cheap give the same answers as the long way.
--
-- The database index by name finds what walking every item finds, and is
-- built again when a source is added; a vendor price still on its way is
-- asked for again; one loot window's sources are read once; the minimap
-- markers are left alone while nothing they show has changed; and a
-- player-only event is lifted to every unit when another handler wants them.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("perf")

local ns = env.Load({ ui = true })
local DB, Value = ns.DB, ns.Value

--------------------------------------------------------------------------------
-- The index by name
--------------------------------------------------------------------------------

local walked, indexed = 0, 0
local mismatch
for item in DB:Iterate() do
    for _, source in ipairs(item.sources) do
        if type(source.name) == "string" then
            walked = walked + 1
            local found = false
            for _, indexed in ipairs(DB:ByName()[source.name] or {}) do
                if indexed == source and DB:ItemOf(indexed) == item then found = true end
            end
            if not found then mismatch = mismatch or (item.name .. " / " .. source.name) end
        end
    end
end
for _, entries in pairs(DB:ByName()) do indexed = indexed + #entries end
suite.check("every named source is in the index", mismatch == nil, mismatch)
suite.check("and nothing else is", walked == indexed, walked .. " vs " .. indexed)
suite.check("the index is kept between calls", DB:ByName() == DB:ByName())

-- A hide change lays the names out again, but keeps the source-to-item map.
local map = DB.sourceItem
DB:Hide("item", "Perf Test Nothing")
DB:ByName()
suite.check("a hide change keeps the item map", DB.sourceItem == map)
DB:Unhide("item", "Perf Test Nothing")

DB:RegisterItem({ name = "Perf Test Fang", id = 990001, category = "Leather",
    sources = { { kind = "mob", name = "Perf Test Wolf", zone = "Elwynn Forest", minLevel = 5, chance = 40 } } })
local wolf = DB:ByName()["Perf Test Wolf"]
suite.check("a source added later is indexed", wolf and #wolf == 1 and DB:ItemOf(wolf[1]).name == "Perf Test Fang")

_G.C_Item = {
    GetItemInfo = function(id)
        if id == 990001 then return "Perf Test Fang", nil, 1, 1, 1, "", "", 1, "", "", 25 end
        return nil
    end,
}
local value, details = Value:FromDatabase("Perf Test Wolf")
suite.check("the database value reads the index", value == 10 and details.priced[1].name == "Perf Test Fang", value)
suite.check("a mob the database does not know has no value", Value:FromDatabase("Nobody At All") == nil)
suite.check("rankings find the mob through the index", ns.Rankings:Spot("Perf Test Wolf") ~= nil)

--------------------------------------------------------------------------------
-- Vendor prices kept only once known
--------------------------------------------------------------------------------

local sell = nil
_G.C_Item = {
    GetItemInfo = function(id)
        if id ~= 990002 or sell == nil then return nil end
        return "Perf Test Hide", nil, 1, 1, 1, "", "", 1, "", "", sell
    end,
    IsItemDataCachedByID = function() return sell ~= nil end,
}
local tooltipAsks = 0
_G.C_TooltipInfo = { GetItemByID = function() tooltipAsks = tooltipAsks + 1; return { lines = { { type = 0 } } } end }
suite.check("not loaded yet: no price", Value:VendorPrice(990002) == nil)
-- The tooltip is not asked again until the client says the item arrived: a
-- board that prices hundreds of items a draw asked for every unloaded one
-- on every kill.
Value:VendorPrice(990002)
suite.check("still waiting, the tooltip is not asked again", tooltipAsks == 1, tooltipAsks)
sell = 7
Value:ItemArrived(990002)  -- what GET_ITEM_INFO_RECEIVED calls
suite.check("loaded later: the price is read", Value:VendorPrice(990002) == 7, Value:VendorPrice(990002))
suite.check("and the tooltip was asked once more", tooltipAsks == 2, tooltipAsks)
sell = 9
suite.check("and kept for the session", Value:VendorPrice(990002) == 7)
_G.C_TooltipInfo = nil

--------------------------------------------------------------------------------
-- One loot window's sources read once
--------------------------------------------------------------------------------

local asked = 0
_G.GetNumLootItems = function() return 3 end
_G.GetLootSourceInfo = function(slot)
    asked = asked + 1
    return "Creature-0-0-0-0-100-0000000001", 1
end
ns.Harvest:LootSources()
ns.Harvest:LootSources()
suite.check("outside a loot read every call asks", asked == 6, asked)
asked = 0
ns.Harvest.lootReading = {}
local first = ns.Harvest:LootSources()
local second = ns.Harvest:LootSources()
ns.Harvest.lootReading = nil
suite.check("inside one it asks once", asked == 3 and first == second, asked)
suite.check("and reads the corpse", #first == 1)

--------------------------------------------------------------------------------
-- Player-only events
--------------------------------------------------------------------------------

local unitAsked, allAsked = 0, 0
local frame = ns.eventFrame
local plainRegister, unitRegister = frame.RegisterEvent, frame.RegisterUnitEvent
frame.RegisterUnitEvent = function(_, _, unit) if unit == "player" then unitAsked = unitAsked + 1 end end
frame.RegisterEvent = function() allAsked = allAsked + 1 end
local owner = {}
ns.RegisterPlayerEvent(owner, "UNIT_PERF_TEST", function() end)
suite.check("a player-only event asks for the player", unitAsked == 1 and allAsked == 1, unitAsked .. "/" .. allAsked)
ns.RegisterPlayerEvent(owner, "UNIT_PERF_TEST", function() end)
suite.check("a second player-only handler changes nothing", unitAsked == 1 and allAsked == 1)
ns.RegisterEvent(owner, "UNIT_PERF_TEST", function() end)
suite.check("a handler for every unit lifts the filter", allAsked == 2, allAsked)
ns.UnregisterEvent(owner, "UNIT_PERF_TEST")
frame.RegisterEvent, frame.RegisterUnitEvent = plainRegister, unitRegister

suite.done()
