-- The farm window (2026-09-28: three items a mob was "limiting").
--
-- What matters: the panel has Farm and Loot tabs and remembers which; the
-- mob you are on leads, open and glowing, with every item it has dropped
-- as icons, and the rest fold to a line; the Sort button steps through its
-- orders and the one you are on still leads; the Loot tab lists every item
-- this session by value with medals and where each came from; the tab not
-- showing gets a dot when something lands there; money is drawn in the
-- game's coin colours; and per hour waits until it means something.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("farmwindow")

local ns = env.Load({ ui = true })
local Value = ns.Value
local Tracker = ns.Tracker
local TUI = ns.TrackerUI

local VENDOR = { [5637] = 10, [2934] = 5, [2318] = 15, [2589] = 20, [4690] = 900 }
local AUCTION = { [5637] = 50, [2589] = 60 }

_G.C_Item = {
    GetItemInfo = function(id)
        return "item", nil, 1, 1, 1, "", "", 1, "", "", VENDOR[id] or 0
    end,
}
_G.BlackthornesTS = { Prices = { GetValue = function(_, id) return AUCTION[id] end } }

TUI:OnEnable()

local function Line(left)
    for index, line in ipairs(TUI.shown or {}) do
        if line.left == left then return line, index end
    end
end

local serial = 0
local function Loot(mob, items)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, guid = "F-" .. serial }
    env.world.loot = items
    Tracker:OnLoot()
end

local FANG = { name = "Large Fang", id = 5637 }
local SCRAPS = { name = "Ruined Leather Scraps", id = 2934, quantity = 2 }
local WOOL = { name = "Wool Cloth", id = 2589, quantity = 3 }
local CLOAK = { name = "Scouting Cloak", id = 4690 }
local PAW = { name = "Wolf Paw", id = 1 }
local TOOTH = { name = "Sharp Tooth", id = 2 }
local EYE = { name = "Wolf Eye", id = 3 }
local TAIL = { name = "Wolf Tail", id = 4 }

--------------------------------------------------------------------------------
-- Coins
--------------------------------------------------------------------------------

suite.check("gold, silver and copper each in the game's colour",
    Value.Coins(12345) == "|cffffd7001g|r |cffc7c7cf23s|r", Value.Coins(12345))
suite.check("copper in copper", Value.Coins(7) == "|cffeda55f7c|r", Value.Coins(7))
suite.check("plain once the colours come off", ns.Util.StripColor(Value.Coins(12345)) == Value.Money(12345))

--------------------------------------------------------------------------------
-- The Farm tab
--------------------------------------------------------------------------------

suite.check("the Farm tab shows first", TUI:Tab() == "farm")

-- Six different items off one wolf: more than the three the panel used to show.
Loot("Mangy Wolf", { FANG, SCRAPS, PAW, TOOTH, EYE, TAIL })
Loot("Kobold Worker", { WOOL })

local kobold, koboldAt = Line("Kobold Worker")
local wolf = Line("Mangy Wolf")
suite.check("the mob you are on leads", koboldAt and wolf and koboldAt < select(2, Line("Mangy Wolf")))
suite.check("open", kobold and kobold.folded == false)
suite.check("and glowing", kobold and kobold.live == true)
suite.check("the one before folds to a line", wolf and wolf.folded == true)
suite.check("with every item it dropped as small icons", wolf and #wolf.minis == 6,
    wolf and #wolf.minis)
suite.check("and the bar toward 20 kills under its count", wolf and wolf.bar == 1 / 20, wolf and wolf.bar)

-- Opened, the wolf shows all six as icons.
TUI:Toggle("mob:Mangy Wolf")
local icons
for index = select(2, Line("Mangy Wolf")) + 1, #TUI.shown do
    if TUI.shown[index].style == "icons" then icons = TUI.shown[index] break end
end
suite.check("opened, every item is an icon", icons and #icons.icons == 6, icons and #icons.icons)
suite.check("each with its count", icons and icons.icons[1].text == "1", icons and icons.icons[1].text)
suite.check("and what the count means", icons and icons.icons[1].about == "1 of 1 kills",
    icons and icons.icons[1].about)
suite.check("clicking an icon opens the mob's table", icons and icons.icons[1].mob == "Mangy Wolf")
TUI:Toggle("mob:Mangy Wolf")
suite.check("and it folds again", Line("Mangy Wolf").folded == true)

-- The one you are on can be folded too.
TUI:Toggle("mob:Kobold Worker", true)
suite.check("the one you are on folds when asked", Line("Kobold Worker").folded == true)
TUI:Toggle("mob:Kobold Worker", true)
suite.check("and opens again", Line("Kobold Worker").folded == false)

--------------------------------------------------------------------------------
-- Sort
--------------------------------------------------------------------------------

Loot("Mangy Wolf", { FANG })
Loot("Mangy Wolf", { FANG })
Loot("Gnoll Brute", { SCRAPS })
Loot("Kobold Worker", { WOOL })

local function Bands()
    local names = {}
    for _, line in ipairs(TUI.shown) do
        if line.style == "mob" then names[#names + 1] = line.left end
    end
    return table.concat(names, ",")
end

suite.check("recent first by default", Bands() == "Kobold Worker,Gnoll Brute,Mangy Wolf", Bands())
TUI:NextSort()
suite.check("then by worth per kill", TUI:Sort("farm") == "worth", TUI:Sort("farm"))
TUI:NextSort()
suite.check("then by kills this session", TUI:Sort("farm") == "kills")
suite.check("the most killed next, the one you are on still first",
    Bands() == "Kobold Worker,Mangy Wolf,Gnoll Brute", Bands())
suite.check("saved", ns.db.trackerSort == "kills")
suite.check("and named on the button", TUI.toolbar.sort.label:GetText() == "Sort: Kills",
    TUI.toolbar.sort.label:GetText())
TUI:NextSort()
TUI:NextSort()
suite.check("round to recent again", TUI:Sort("farm") == "recent")

-- The button opens a drop-down of the same orders, the one in use ticked.
local sortLines = TUI:SortLines()
suite.check("the Sort drop-down lists every order", #sortLines == #TUI.SORTS.farm
    and sortLines[1].checked and not sortLines[2].checked)
sortLines[3].run()
suite.check("a line picks its order", TUI:Sort("farm") == "kills" and ns.db.trackerSort == "kills")
TUI:SetSort("recent")

--------------------------------------------------------------------------------
-- The Loot tab
--------------------------------------------------------------------------------

suite.check("no dot on the Farm tab you are on", not TUI.tabs[1].dot:IsShown())
suite.check("a dot on the Loot tab: loot landed there", TUI.tabs[2].dot:IsShown())

TUI.tabs[2]:GetScript("OnClick")(TUI.tabs[2])
suite.check("clicking the tab switches to it", TUI:Tab() == "loot" and ns.db.trackerTab == "loot")
suite.check("and its dot goes", not TUI.tabs[2].dot:IsShown())

local rows = {}
for _, line in ipairs(TUI.shown) do
    if line.style == "loot" then rows[#rows + 1] = line end
end
-- Wool: 6 at 60c = 3s 60c. Fang: 3 at 50c. Scraps: 4 at 5c.
suite.check("best earners first", rows[1] and rows[1].item == "Wool Cloth"
    and rows[2].item == "Large Fang", rows[1] and rows[1].item)
suite.check("ranked", rows[1].rank == 1 and rows[2].rank == 2)
suite.check("with how many", rows[1].right == "x6", rows[1].right)
suite.check("and what they are worth, in coin colours", rows[1].below == Value.Coins(360), rows[1].below)
suite.check("and where they came from", rows[1].sub == "Kobold Worker 6", rows[1].sub)
local scraps
for _, row in ipairs(rows) do if row.item == SCRAPS.name then scraps = row end end
suite.check("two mobs, most first", scraps and scraps.sub == "Gnoll Brute 2, Mangy Wolf 2"
    or scraps and scraps.sub == "Mangy Wolf 2, Gnoll Brute 2", scraps and scraps.sub)
local paw
for _, row in ipairs(rows) do if row.item == PAW.name then paw = row end end
suite.check("an item with no price says so", paw and paw.below == "no price", paw and paw.below)
suite.check("and sorts last", paw and paw.rank > 3)

local drawn = TUI.lines[1]
suite.check("the top three wear medals", drawn.medal:IsShown())
suite.check("the Loot tab's rows are two lines tall",
    TUI:LineHeight(rows[1], 260) > TUI:LineHeight({ style = "note" }, 260))

-- A second source.
Loot("Kobold Worker", { CLOAK })
suite.check("the Farm tab gets a dot when a kill lands there", TUI.tabs[1].dot:IsShown())
local cloak
for _, line in ipairs(TUI.shown) do if line.item == CLOAK.name then cloak = line end end
suite.check("a new item goes straight to its place", cloak and cloak.rank == 1, cloak and cloak.rank)

TUI:NextSort()
suite.check("the Loot tab sorts by count next", TUI:Sort("loot") == "count")
suite.check("the Farm tab's order is its own", TUI:Sort("farm") == "recent")
TUI:NextSort()
TUI:NextSort()

TUI:SetTab("farm")
suite.check("back on Farm", TUI:Tab() == "farm")
suite.check("its dot goes", not TUI.tabs[1].dot:IsShown())

--------------------------------------------------------------------------------
-- Per hour
--------------------------------------------------------------------------------

local now = 1000
_G.GetTime = function() return now end
TUI.startedAt = nil
TUI:Refresh()
suite.check("per hour waits a few minutes", TUI:PerHour() == nil)
now = now + 3600
local hour = TUI:PerHour()
suite.check("then says what the session earns an hour",
    hour and math.abs(hour - Value:Session()) < 1, hour)
TUI:Refresh()
suite.check("on the toolbar", TUI.toolbar.left:GetText():find("Per hour", 1, true) ~= nil,
    TUI.toolbar.left:GetText())
_G.GetTime = nil

suite.done()
