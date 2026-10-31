-- Quest items in the loot lists.
--
-- What matters (a player asked, the owner said yes, 2026-10-18): a quest
-- item a mob drops shows as "Quest" on the Loot tab and in the loot table's
-- Per Kill column, and its icon's hover says "Quest item". It stays worth
-- nothing, so the session's gold is the same, and it no longer counts as an
-- item "with no price left out". Other loot with no price keeps "no price".

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("questloot")

local ns = env.Load({ ui = true })
local Tracker, Value, TrackerUI, LootTableUI = ns.Tracker, ns.Value, ns.TrackerUI, ns.LootTableUI

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local QUEST, PRICED, UNPRICED = 9001, 9002, 9003
-- The client: the quest item is class 12 and sells for nothing; the fang
-- sells for 25 copper; the odd rock has no price and is not a quest item.
_G.GetItemInfoInstant = function(id)
    id = tonumber(id)
    if id == QUEST then return id, "Quest", "Quest", "", 1, 12, 0 end
    if id == PRICED or id == UNPRICED then return id, "Trade Goods", "Other", "", 1, 7, 0 end
    return nil
end
_G.C_Item = {
    GetItemInfoInstant = _G.GetItemInfoInstant,
    GetItemInfo = function(id)
        id = tonumber(id)
        local sell = id == PRICED and 25 or 0
        return "item", nil, 1, 1, 1, "", "", 1, "", "", sell
    end,
}

local serial = 0
local function Kill()
    serial = serial + 1
    env.world.target = { name = "Kobold Tunneler", level = 6, dead = true,
        guid = "Creature-0-1-2-3-475-" .. serial }
    env.world.loot = {
        { name = "Gold Dust Sample", id = QUEST },
        { name = "Large Fang", id = PRICED },
        { name = "Odd Rock", id = UNPRICED },
    }
    Tracker:OnLoot()
end
for _ = 1, 20 do Kill() end

suite.check("the quest item is a quest item", Value:IsQuest("Gold Dust Sample") == true)
suite.check("the fang is not", Value:IsQuest("Large Fang") == false)
suite.check("nor is the odd rock", Value:IsQuest("Odd Rock") == false)
suite.check("the quest item has no worth", Value:WorthOf("Gold Dust Sample") == nil)

-- The Loot tab.
local byName = {}
for _, entry in ipairs(TrackerUI:SessionItems()) do byName[entry.name] = entry end
suite.check("the Loot tab lists the quest item", byName["Gold Dust Sample"] ~= nil)
suite.check("marked as a quest item", byName["Gold Dust Sample"] and byName["Gold Dust Sample"].quest == true)
suite.check("with no value", byName["Gold Dust Sample"] and byName["Gold Dust Sample"].value == nil)
suite.check("the odd rock is not marked", byName["Odd Rock"] and not byName["Odd Rock"].quest)

local lines = {}
TrackerUI:LootLines(function(line) lines[#lines + 1] = line; return line end)
local below, notes = {}, {}
for _, line in ipairs(lines) do
    if line.style == "loot" then below[line.item] = line.right end
    if line.style == "note" then notes[#notes + 1] = line.left end
end
suite.check("it says Quest beside its name", below["Gold Dust Sample"] == "Quest", below["Gold Dust Sample"])
suite.check("the odd rock still says no price", below["Odd Rock"] == "no price", below["Odd Rock"])

-- The session's gold and the "left out" note.
local total, details = Value:Session()
suite.check("the gold counts only the fang", total == 20 * 25, total)
suite.check("one quest item counted apart", details.quest == 1, details.quest)
suite.check("only the odd rock is left out", #details.unpriced == 1 and details.unpriced[1] == "Odd Rock")
local note = false
for _, text in ipairs(notes) do if text == "1 item with no price left out" then note = true end end
suite.check("the note counts one item", note, table.concat(notes, " | "))

-- Only a quest item: still something gathered, worth nothing.
Tracker.sessionLoot = { ["Gold Dust Sample"] = 3 }
Tracker.sessionCopper = 0
local onlyTotal, onlyDetails = Value:Session()
suite.check("a quest item alone is worth 0", onlyTotal == 0, onlyTotal)
suite.check("and leaves nothing out", onlyDetails and #onlyDetails.unpriced == 0)

-- The loot table.
local data = LootTableUI:Table("Kobold Tunneler")
local rows = {}
for _, row in ipairs(data and data.rows or {}) do rows[row.name] = row end
suite.check("the loot table marks the quest item", rows["Gold Dust Sample"] and rows["Gold Dust Sample"].quest == true)
suite.check("with no per kill worth", rows["Gold Dust Sample"] and rows["Gold Dust Sample"].perKill == nil)
suite.check("the fang keeps its worth", rows["Large Fang"] and rows["Large Fang"].perKill ~= nil and not rows["Large Fang"].quest)
suite.check("the odd rock is not marked", rows["Odd Rock"] and not rows["Odd Rock"].quest)

suite.done()
return suite
