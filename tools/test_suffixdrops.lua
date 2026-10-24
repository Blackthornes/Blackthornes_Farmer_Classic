-- Gear with a random suffix ("Lead Band of the Monkey", "... of the Owl")
-- drops under its whole name, so one green was spread over its suffixes
-- and took far longer to reach a rate (asked 2026-10-15). The readers count
-- the suffixes as the item; the saved records are never rewritten.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("suffixdrops")

local ns = env.Load()
local Harvest, Tracker = ns.Harvest, ns.Tracker

local BAND = 990101
local savedItem = C_Item
C_Item = setmetatable({
    GetItemNameByID = function(id) if id == BAND then return "Lead Band" end end,
}, { __index = savedItem })

--------------------------------------------------------------------------------
-- The item's own name
--------------------------------------------------------------------------------

Harvest.rollBase = {}
suite.check("the client names the item", Harvest.RollBase("Lead Band of the Monkey", BAND) == "Lead Band")
suite.check("a stat suffix too", Harvest.RollBase("Lead Band of Stamina", BAND) == "Lead Band")
suite.check("the item's own name is no suffix", Harvest.RollBase("Lead Band", BAND) == nil)
suite.check("no ID, no guess", Harvest.RollBase("Claw of the Bear", nil) == nil)
suite.check("an item the client has not loaded reads its animal suffix off the name",
    Harvest.RollBase("Staff of the Wolf", 990102) == "Staff")
C_Item.GetItemNameByID = function(id)
    if id == BAND then return "Lead Band" end
    if id == 990103 then return "Heart of the Wolf" end
end
Harvest.rollBase = {}
suite.check("the client's own name wins over the name's ending",
    Harvest.RollBase("Heart of the Wolf", 990103) == nil)
suite.check("with no client, the animal suffixes are read off the name",
    Harvest.RollBase("Priest's Mace of the Tiger", 990104) == "Priest's Mace")
suite.check("but not the one-stat ones", Harvest.RollBase("Robe of Power", 990105) == nil)

--------------------------------------------------------------------------------
-- Harvest records
--------------------------------------------------------------------------------

local record = {
    mob = "Defias Thug", zone = "Westfall", minLevel = 10, maxLevel = 11, corpses = 100,
    items = {
        ["Lead Band of the Monkey"] = { name = "Lead Band of the Monkey", corpses = 3, count = 3, id = BAND },
        ["Lead Band of the Owl"] = { name = "Lead Band of the Owl", corpses = 2, count = 2, id = BAND },
        ["Lead Band of Stamina"] = { name = "Lead Band of Stamina", corpses = 1, count = 1, id = BAND },
        ["Linen Cloth"] = { name = "Linen Cloth", corpses = 40, count = 55, id = 2589 },
    },
}
ns.Harvest.records["Defias Thug|Westfall|"] = record

local grouped = Harvest:GroupedItems(record)
suite.check("the suffixes are one item", grouped["Lead Band"] and grouped["Lead Band"].corpses == 6,
    grouped["Lead Band"] and grouped["Lead Band"].corpses)
suite.check("each suffix is gone from the grouped view", grouped["Lead Band of the Monkey"] == nil)
suite.check("other items are as they were", grouped["Linen Cloth"].count == 55)
suite.check("the saved record is untouched", record.items["Lead Band of the Owl"].corpses == 2
    and record.items["Lead Band"] == nil)

local rows = Harvest:ForItem("Lead Band")
suite.check("the item's rate counts every suffix", rows[1] and math.abs(rows[1].chance - 6) < 0.001,
    rows[1] and rows[1].chance)

local plain = { corpses = 5, items = { ["Linen Cloth"] = { corpses = 3, count = 3, id = 2589 } } }
suite.check("a record with no suffix is read as it is", Harvest:GroupedItems(plain) == plain.items)

local export = Harvest:ExportItem("Lead Band")
suite.check("the export names the item once", export and export:find('name = "Lead Band"', 1, true) ~= nil)
suite.check("with every suffix's corpses", export and export:find("6 of 100 corpses", 1, true) ~= nil)

--------------------------------------------------------------------------------
-- The kill tally
--------------------------------------------------------------------------------

local mob = Tracker:GetMob("Defias Thug")
mob.kills = 50
mob.items["Lead Band of the Monkey"] = 2
mob.items["Lead Band of the Owl"] = 1
mob.items["Linen Cloth"] = 20
local looks = Tracker:Looks()
looks["Lead Band of the Monkey"] = { id = BAND, color = "ff1eff00", icon = 1 }
looks["Lead Band of the Owl"] = { id = BAND, color = "ff1eff00", icon = 1 }

local summary = Tracker:Summary("Defias Thug")
local band
for _, item in ipairs(summary.items) do
    if item.name == "Lead Band" then band = item end
    suite.check("no suffix listed on its own", not item.name:find(" of the ", 1, true), item.name)
end
suite.check("the panel counts the suffixes as one", band and band.corpses == 3, band and band.corpses)
suite.check("with the item's rate", band and math.abs(band.chance - 6) < 0.001, band and band.chance)
suite.check("its look comes from a suffix", Tracker:LookOf("Lead Band").id == BAND)
suite.check("the tally keeps each suffix", mob.items["Lead Band of the Owl"] == 1 and mob.items["Lead Band"] == nil)

local folded = ns.Value.FoldSuffixes({
    { name = "Lead Band of the Monkey", perKill = 4, unit = 100, chance = 4 },
    { name = "Lead Band of the Owl", perKill = 2, unit = 100, chance = 2 },
    { name = "Linen Cloth", perKill = 10, unit = 25, chance = 40 },
})
suite.check("best drops name the item once", #folded == 2 and folded[1].name == "Lead Band", #folded)
suite.check("with the suffixes' worth together", folded[1].perKill == 6 and folded[1].chance == 6)

suite.check("the folded drop carries the item's ID", folded[1].id == BAND, folded[1].id)
suite.check("and a roll's loot link for its quality", folded[1].lookName == "Lead Band of the Monkey")
suite.check("so Skip Uncommon sees it is green", ns.Rankings.IsUncommonOrBetter(folded[1]) == true)

-- Hiding the item by its own name (the name the lists show) hides every
-- roll of it, so none of them counts toward a mob's worth.
local DB = ns.DB
ns.Value.UnitPrice = function() return 100, "auction" end
-- Does the mob's worth name an item, priced or not?
local function Mentions(item)
    local _, details = ns.Value:FromTally("Defias Thug")
    for _, list in ipairs({ details and details.priced or {}, details and details.unpriced or {} }) do
        for _, drop in ipairs(list) do
            local name = type(drop) == "table" and drop.name or drop
            if name:find(item, 1, true) then return true end
        end
    end
    return false
end
suite.check("the item counts before it's hidden", Mentions("Lead Band"))
suite.check("a roll is not hidden before", not DB:IsHiddenItem("Lead Band of the Owl"))
DB:Hide("item", "Lead Band")
suite.check("hiding the item hides its rolls", DB:IsHiddenItem("Lead Band of the Owl")
    and DB:IsHiddenItem("Lead Band of the Monkey"))
suite.check("other items stay shown", not DB:IsHiddenItem("Linen Cloth"))
suite.check("a hidden item's rolls leave the worth and best drops", not Mentions("Lead Band"))
suite.check("the rest still counts", Mentions("Linen Cloth"))
DB:Unhide("item", "Lead Band")
suite.check("Show again brings the rolls back", not DB:IsHiddenItem("Lead Band of the Owl"))

C_Item = savedItem
suite.done()
