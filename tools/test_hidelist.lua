-- The hide list: mobs, nodes and items a player never wants to see.
--
-- What matters: empty, nothing changes; a hidden mob or node leaves the
-- search's spots, Rankings, Grind and the kills panel; a hidden item leaves
-- the search, a mob's drops and worth, and the Loot tab; nothing recorded
-- is touched, and Show again (or /farm unhide) puts it all back; the
-- right-click menu hides only what is clicked.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("hidelist")

local ns = env.Load({ ui = true })
local DB, Search, Tracker, Value = ns.DB, ns.Search, ns.Tracker, ns.Value

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

_G.C_Item = { GetItemInfo = function() return "item", nil, 1, 1, 1, "", "", 1, "", "", 10 end }

local function Names(results)
    local names = {}
    for _, result in ipairs(results) do names[result.item.name] = true end
    return names
end

local function SpotNames(results, itemName)
    local names = {}
    for _, result in ipairs(results) do
        if result.item.name == itemName then
            for _, source in ipairs(result.sources or result.item.sources) do
                if source.name then names[source.name] = true end
            end
        end
    end
    return names
end

-- Some wolves of your own, this session.
local serial = 0
local function Kill(mob, items)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, guid = "Creature-0-1-2-3-77-" .. serial }
    env.world.loot = items
    Tracker:OnLoot()
end
for _ = 1, 20 do
    Kill("Mangy Wolf", { { name = "Large Fang", id = 5637 }, { name = "Wolf Paw", id = 3300 } })
    Kill("Kobold Vermin", { { name = "Linen Cloth" } })
end

-- A cloth mob the data has, to hide.
local linen = Search:Run("linen cloth")
local someMob
for name in pairs(SpotNames(linen, "Linen Cloth")) do someMob = someMob or name end

local function PanelMobs()
    local names = {}
    for _, summary in ipairs(Tracker:SessionMobs()) do names[summary.mob] = true end
    return names
end

local function Ranked()
    local names = {}
    local board = ns.Rankings:Build()
    for _, group in pairs(board) do
        for _, entry in ipairs(group) do names[entry.mob] = true end
    end
    return names
end

local function DropNames(mob)
    local names = {}
    for _, item in ipairs(Tracker:Summary(mob).items) do names[item.name] = true end
    return names
end

--------------------------------------------------------------------------------
-- Empty
--------------------------------------------------------------------------------

suite.check("nothing is hidden at first", #DB:HiddenEntries() == 0)
suite.check("a cloth mob is a spot", someMob ~= nil)
suite.check("the wolves are on the panel", PanelMobs()["Mangy Wolf"])
suite.check("and ranked", Ranked()["Mangy Wolf"])
local worth = Value:FromTally("Mangy Wolf")
suite.check("and worth something", worth and worth > 0, worth)

--------------------------------------------------------------------------------
-- A mob
--------------------------------------------------------------------------------

local redrawn = 0
DB.hideWatchers.test = function() redrawn = redrawn + 1 end

ns.HandleSlash("hide Mangy Wolf")
suite.check("/farm hide puts a mob on the list", DB:IsHiddenSource("Mangy Wolf"))
suite.check("any case", DB:IsHiddenSource("mangy wolf"))
suite.check("what shows it redraws", redrawn == 1, redrawn)
suite.check("the wolves leave the panel", not PanelMobs()["Mangy Wolf"])
suite.check("but the kobolds stay", PanelMobs()["Kobold Vermin"])
suite.check("and leave Rankings", not Ranked()["Mangy Wolf"])
suite.check("their tally is untouched", Tracker:Store()["Mangy Wolf"].kills == 20)

ns.HandleSlash("hide mob " .. someMob)
suite.check("the cloth mob leaves Linen Cloth's spots",
    not SpotNames(Search:Run("linen cloth"), "Linen Cloth")[someMob])
suite.check("but Linen Cloth is still found", Names(Search:Run("linen cloth"))["Linen Cloth"])
local camped = false
for _, mob in pairs(ns.Grinding:Mobs().all) do
    if mob.name == someMob then camped = true end
end
suite.check("and leaves Grind", not camped)

--------------------------------------------------------------------------------
-- An item
--------------------------------------------------------------------------------

ns.HandleSlash("hide Large Fang")
suite.check("an item the data knows goes on the item list", DB:IsHiddenItem("Large Fang"))
ns.HandleSlash("unhide Mangy Wolf")
suite.check("/farm unhide shows the wolves again", not DB:IsHiddenSource("Mangy Wolf")
    and PanelMobs()["Mangy Wolf"])
suite.check("without the fang among their drops", not DropNames("Mangy Wolf")["Large Fang"])
suite.check("but with the paw", DropNames("Mangy Wolf")["Wolf Paw"])
local less = Value:FromTally("Mangy Wolf")
suite.check("their worth leaves the fang out", less and less < worth, less)
suite.check("a fang search finds nothing", not Names(Search:Run("large fang"))["Large Fang"])
suite.check("and says it is hidden", Search:NothingFoundText("large fang"):find("hide list", 1, true) ~= nil)
local onLootTab = false
for _, entry in ipairs(ns.TrackerUI:SessionItems()) do
    if entry.name == "Large Fang" then onLootTab = true end
end
suite.check("the Loot tab leaves it out", not onLootTab)
suite.check("the tally still counts it", Tracker:Store()["Mangy Wolf"].items["Large Fang"] == 20)

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

ns.HandleSlash("hidden")
local window = ns.HiddenUI
suite.check("/farm hidden opens the list", window.frame and window.frame:IsShown())
local data = window.list.data
suite.check("it lists both", #data == 2, #data)
suite.check("A to Z", data[1].name:lower() < data[2].name:lower(), data[1] and data[1].name)
suite.check("the empty note is out of sight", not window.empty:IsShown())

local fang
for _, entry in ipairs(data) do if entry.name == "Large Fang" then fang = entry end end
window:ShowAgain(fang)
suite.check("Show again takes it off", not DB:IsHiddenItem("Large Fang"))
suite.check("the list follows", #window.list.data == 1, #window.list.data)
suite.check("the fang is back", DropNames("Mangy Wolf")["Large Fang"]
    and Value:FromTally("Mangy Wolf") == worth)
window:ShowAgain(window.list.data[1])
suite.check("emptied, it says how to hide", window.empty:IsShown())
ns.HandleSlash("hidden")
suite.check("typed again it closes", not window.frame:IsShown())

--------------------------------------------------------------------------------
-- Right-click
--------------------------------------------------------------------------------

-- Timers wait, as the game's do.
local waiting = {}
local realAfter = C_Timer.After
C_Timer.After = function(_, fn) waiting[#waiting + 1] = fn end

local opened = ns.HideMenu:Open({ { kind = "source", name = "Kobold Vermin" }, { kind = "item", name = "Linen Cloth" } })
local menu = ns.HideMenu.frame
suite.check("a right-click opens the menu", opened and menu:IsShown())
suite.check("with a line each", menu.lines[1]:IsShown() and menu.lines[2]:IsShown()
    and not menu.lines[3]:IsShown())
suite.check("named", menu.lines[1].label:GetText() == "Hide Kobold Vermin", menu.lines[1].label:GetText())
-- The house menu: a gold rim, dark glass lines a shade apart, and the gold
-- edge only on the line under the mouse.
suite.check("a gold rim", menu.borderTextures ~= nil and menu.inner and menu.inner.borderTextures ~= nil)
suite.check("glass lines a shade apart", menu.lines[1].stripe and menu.lines[2].stripe
    and menu.lines[1].stripe ~= menu.lines[2].stripe)
suite.check("each with the hover light", menu.lines[1].edge and menu.lines[1].highlight)
local lit = {}
local realLight = ns.Widgets.SetRowLight
ns.Widgets.SetRowLight = function(row, value) lit[row] = value end
menu.lines[1]:GetScript("OnEnter")(menu.lines[1])
suite.check("the line under the mouse lights", lit[menu.lines[1]] == 1 and lit[menu.lines[2]] == nil)
menu.lines[1]:GetScript("OnLeave")(menu.lines[1])
suite.check("and goes dark again", lit[menu.lines[1]] == 0)
ns.Widgets.SetRowLight = realLight
-- At the mouse, not the middle of the screen (a player found it there).
local point = menu._point
suite.check("it opens at the mouse", point and point[1] == "TOPLEFT" and point[3] == "BOTTOMLEFT"
    and point[4] == 600 - 6 and point[5] == 500 + 6, point and table.concat({ tostring(point[1]),
    tostring(point[4]), tostring(point[5]) }, " "))
local realScale = UIParent.GetEffectiveScale
UIParent.GetEffectiveScale = function() return 2 end
ns.HideMenu:Open({ { kind = "item", name = "Wool Cloth" } })
suite.check("at the mouse at any UI scale", menu._point[4] == 300 - 6 and menu._point[5] == 250 + 6,
    menu._point[4])
UIParent.GetEffectiveScale = realScale
ns.HideMenu:Open({ { kind = "source", name = "Kobold Vermin" }, { kind = "item", name = "Linen Cloth" } })
suite.check("nothing is hidden by opening it", #DB:HiddenEntries() == 0)
menu.lines[1]:GetScript("OnClick")(menu.lines[1])
suite.check("its line hides that one", DB:IsHiddenSource("Kobold Vermin") and not DB:IsHiddenItem("Linen Cloth"))
suite.check("and it closes", not menu:IsShown())
-- Never come onto, it goes by itself; and its waiting timer from before
-- does not close one opened since.
waiting = {}
ns.HideMenu:Open({ { kind = "item", name = "Linen Cloth" } })
local first = waiting[1]
ns.HideMenu:Open({ { kind = "item", name = "Wool Cloth" } })
first()
suite.check("an old timer leaves a newer menu", menu:IsShown())
waiting[#waiting]()
suite.check("left alone, it goes", not menu:IsShown())
suite.check("having hidden nothing", not DB:IsHiddenItem("Linen Cloth") and not DB:IsHiddenItem("Wool Cloth"))
C_Timer.After = realAfter

-- A row's own action goes first and runs on a click (2026-10-29).
local ran = false
ns.HideMenu:Open({ { kind = "action", text = "Open Loot Table", run = function() ran = true end },
    { kind = "item", name = "Wool Cloth" } })
suite.check("the row's action is the first line", menu.lines[1].label:GetText() == "Open Loot Table"
    and menu.lines[2].label:GetText():find("Wool Cloth", 1, true) ~= nil)
menu.lines[1]:GetScript("OnClick")(menu.lines[1])
suite.check("and does what a click does", ran and not DB:IsHiddenItem("Wool Cloth") and not menu:IsShown())

suite.check("one already hidden is not offered",
    not ns.HideMenu:Open({ { kind = "source", name = "Kobold Vermin" } }))

-- The search window's rows offer the mob and the item.
local choices
local realOpen = ns.HideMenu.Open
ns.HideMenu.Open = function(_, list) choices = list end
ns.UI:OnRowClick({ type = "source", item = DB:GetItem("Linen Cloth"),
    source = { name = "Defias Thug", zone = "Elwynn Forest" } }, "RightButton")
ns.HideMenu.Open = realOpen
suite.check("a spot's right-click offers its mob and its item", choices and #choices == 2
    and choices[1].name == "Defias Thug" and choices[2].name == "Linen Cloth")

ns.HandleSlash("unhide Kobold Vermin")
suite.check("all shown again", #DB:HiddenEntries() == 0)

DB.hideWatchers.test = nil

return suite
