-- The kill tracker.
--
-- What matters: a kill is counted once however many times its corpse is
-- opened, no percentage appears before MIN_KILLS, the rate is corpses that held
-- the item over kills, chat stays quiet unless asked, and the tally survives a
-- reload while the session count does not.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("tracker")

local ns = env.Load({ ui = true })
local Tracker = ns.Tracker

-- PLAYER_LOGIN: registers LOOT_OPENED for both the harvester and the tracker.
ns.Harvest:OnEnable()
Tracker:OnEnable()
ns.TrackerUI:OnEnable()

--- The panel line whose left text is `left`, as last drawn.
local function Line(left)
    for index, line in ipairs(ns.TrackerUI.shown or {}) do
        if line.left == left then return line, index end
    end
end

suite.check("the panel is on from the start", ns.TrackerUI.frame:IsShown())
suite.check("it sits down the left side",
    ns.TrackerUI.frame._point[1] == "TOPLEFT" and ns.TrackerUI.frame._point[4] == 8,
    table.concat({ tostring(ns.TrackerUI.frame._point[1]), tostring(ns.TrackerUI.frame._point[4]) }, " "))
suite.check("empty, it says so", Line("Nothing killed yet this session.") ~= nil)
suite.check("and is only as tall as that", ns.TrackerUI.frame:GetHeight() < ns.TrackerUI.TOP + 60,
    ns.TrackerUI.frame:GetHeight())

-- A screenshot, 2026-09-25: "Nothing killed yet this se..." -- a line
-- with no value stopped where the value column would have started.
suite.check("a line with no value runs the full width",
    ns.TrackerUI.lines[1].leftStop == 8, ns.TrackerUI.lines[1].leftStop)

local fire = ns.eventFrame:GetScript("OnEvent")

local serial = 0

--- Open one corpse through the real event, as the client would.
local function Loot(mob, items, guid)
    if guid == nil then
        serial = serial + 1
        guid = "Creature-0-1-2-3-" .. serial
    end

    env.world.target = { name = mob, level = 8, dead = true, isPlayer = false,
        guid = guid or nil }
    env.world.loot = items or {}
    fire(ns.eventFrame, "LOOT_OPENED")
end

local function ChatSince(mark)
    local lines = {}
    for index = mark + 1, #env.chat do lines[#lines + 1] = env.chat[index] end
    return table.concat(lines, "\n")
end

local BOAR = "Mottled Boar"
local SCRAPS = { name = "Ruined Leather Scraps", id = 2934 }
local MEAT = { name = "Chunk of Boar Meat", id = 769 }
local COINS = { name = "12 Copper", money = true }

--------------------------------------------------------------------------------
-- Counting
--------------------------------------------------------------------------------

Loot(BOAR, { SCRAPS, COINS })
Loot(BOAR, { MEAT })
Loot(BOAR, {})

local summary = Tracker:Summary(BOAR)
suite.check("three corpses are three kills", summary.kills == 3, summary.kills)
suite.check("all three this session", summary.session == 3, summary.session)
suite.check("coins are not an item", #summary.items == 2, #summary.items)
suite.check("no rates before the threshold", summary.rated == false)
suite.check("it says how many more are needed", summary.needed == 17, summary.needed)

suite.check("the harvester still records alongside it",
    ns.Harvest:CountCorpses() == 3, ns.Harvest:CountCorpses())

-- A small line over the cards names their two numbers (2026-10-13).
do
    local columns, columnsAt, bandAt
    for index, line in ipairs(ns.TrackerUI:Lines()) do
        if line.style == "columns" and not columnsAt then columns, columnsAt = line, index end
        if line.style == "mob" and not bandAt then bandAt = index end
    end
    suite.check("the column names sit over the first card",
        columnsAt ~= nil and bandAt ~= nil and columnsAt < bandAt, tostring(columnsAt))
    suite.check("and say which number is which",
        columns and columns.badge == "This session" and columns.column == "All time")
end

-- Skin the last one: same corpse, same guid, a new item.
local skinned = "Creature-0-1-2-3-skin"
Loot(BOAR, { SCRAPS }, skinned)
local before = Tracker:Summary(BOAR).kills
Loot(BOAR, { { name = "Light Leather", id = 2318 } }, skinned)

summary = Tracker:Summary(BOAR)
suite.check("opening a corpse twice is one kill", summary.kills == before, summary.kills)

local leather
for _, item in ipairs(summary.items) do
    if item.name == "Light Leather" then leather = item end
end
suite.check("what the second opening found is counted", leather and leather.corpses == 1)

-- And coming back for the same scraps does not count them twice.
Loot(BOAR, { SCRAPS }, skinned)
for _, item in ipairs(Tracker:Summary(BOAR).items) do
    if item.name == SCRAPS.name then
        suite.check("an item counts once per corpse", item.corpses == 2, item.corpses)
    end
end

-- No guid (an instance can refuse it): every opening counts, rather than none.
local noGuid = Tracker:Summary(BOAR).kills
Loot(BOAR, {}, false)
Loot(BOAR, {}, false)
suite.check("without a guid each opening is a kill",
    Tracker:Summary(BOAR).kills == noGuid + 2, Tracker:Summary(BOAR).kills)

--------------------------------------------------------------------------------
-- The panel before the threshold
--------------------------------------------------------------------------------

local UI = ns.TrackerUI

suite.check("the panel is showing", UI.frame:IsShown())

local boarLine = Line(BOAR)
suite.check("it lists the mob", boarLine ~= nil)
suite.check("with its all-time kills", boarLine and boarLine.right == "6",
    boarLine and boarLine.right)
suite.check("and this session's beside them", boarLine and boarLine.badge == "+6",
    boarLine and boarLine.badge)
-- Under it, a progress bar like a goal's (2026-09-27).
local _, boarBandAt = Line(BOAR)
if UI.shown[boarBandAt + 1].style == "place" then boarBandAt = boarBandAt + 1 end
local boarBar = UI.shown[boarBandAt + 1]
suite.check("a progress bar sits under the band", boarBar and boarBar.style == "progress",
    boarBar and boarBar.style)
suite.check("filling toward 20", boarBar and math.abs(boarBar.progress - 0.3) < 1e-9,
    boarBar and boarBar.progress)
suite.check("its count reads like a goal's",
    boarBar and ns.Util.StripColor(boarBar.right) == "6 / 20", boarBar and boarBar.right)
suite.check("one mark passed at 6 of 20", boarBar and boarBar.milestone == 1,
    boarBar and boarBar.milestone)
suite.check("not yet the last stretch", boarBar and not boarBar.final)
suite.check("the band itself has no thin bar now", boarLine and boarLine.bar == nil)
suite.check("the countdown comes straight after the bar",
    UI.shown[boarBandAt + 2] and UI.shown[boarBandAt + 2].left == "14 more kills for drop rates",
    UI.shown[boarBandAt + 2] and UI.shown[boarBandAt + 2].left)

local barRow = UI.lines[boarBandAt + 1]
suite.check("the bar row shows its bar", barRow and barRow.progress.track:IsShown())
suite.check("and the row above it does not", not UI.lines[boarBandAt].progress.track:IsShown())

local session = Line("THIS SESSION")
suite.check("the session heading totals kills",
    session and session.right == "6 kills", session and session.right)

-- Scraps: once from the first boar, once from the skinned one (the return
-- visit adds none).
-- This session's loot is on the Loot tab (2026-09-28).
UI:SetTab("loot")
local scrapsLoot = Line(SCRAPS.name)
suite.check("session loot adds up quantities",
    scrapsLoot and scrapsLoot.count == 2, scrapsLoot and scrapsLoot.count)
suite.check("and says which mob it came from",
    scrapsLoot and scrapsLoot.sub == BOAR .. " 2", scrapsLoot and scrapsLoot.sub)
suite.check("the Loot tab is saved", ns.db.trackerTab == "loot")
UI:SetTab("farm")

local _, boarAt = Line(BOAR)
local itemUnder
for index = boarAt + 1, #UI.shown do
    if UI.shown[index].style == "icons" then itemUnder = UI.shown[index].icons[1] break end
end
suite.check("items under a mob show as counts, not percentages",
    itemUnder and itemUnder.text:find("%", 1, true) == nil, itemUnder and itemUnder.text)
suite.check("and it says how many more kills",
    Line("14 more kills for drop rates") ~= nil)

-- Two slots of one item in a window add up in the session loot.
Loot(BOAR, { { name = "Chunk of Boar Meat", quantity = 2 }, { name = "Chunk of Boar Meat", quantity = 1 } })
UI:SetTab("loot")
local meatLoot = Line(MEAT.name)
suite.check("two slots of one item both count toward loot",
    meatLoot and meatLoot.count == 4, meatLoot and meatLoot.count)
UI:SetTab("farm")

--------------------------------------------------------------------------------
-- How items look
--------------------------------------------------------------------------------

local look = Tracker:LookOf(SCRAPS.name)
suite.check("an item's icon is kept from the loot window",
    look.icon == "Interface\\Icons\\INV_Misc_Dust_01", look.icon)
suite.check("and its colour from the loot link", look.color == "ffffffff", look.color)
suite.check("an item never looted has no look, not an error",
    next(Tracker:LookOf("Nothing Such")) == nil)

suite.check("LinkColor: a spelled-out colour",
    Tracker.LinkColor("|cff1eff00|Hitem:2318|h[Light Leather]|h|r") == "ff1eff00")
suite.check("LinkColor: a named quality",
    Tracker.LinkColor("|cnIQ3:|Hitem:1|h[x]|h|r") == Tracker.QUALITY[3])
suite.check("LinkColor: not a link", Tracker.LinkColor("Light Leather") == nil)

--------------------------------------------------------------------------------
-- Chat is quiet by default
--------------------------------------------------------------------------------

suite.check("reporting starts off", ns.db.trackerReport == false)

local mark = #env.chat
Loot(BOAR, { SCRAPS })
suite.check("a kill says nothing in chat when reporting is off", #env.chat == mark,
    ChatSince(mark))

ns.HandleSlash("report on")
suite.check("/farm report on turns it on", ns.db.trackerReport == true)

mark = #env.chat
Loot(BOAR, { MEAT })
local said = ChatSince(mark)
suite.check("a kill is reported", said:find("kill 9", 1, true) ~= nil, said)
suite.check("before the threshold it says how many more",
    said:find("11 more for drop rates", 1, true) ~= nil, said)
suite.check("before the threshold it gives no percentage",
    said:find("%", 1, true) == nil, said)

-- Opening the same corpse again is not a kill, so it is not reported.
Loot(BOAR, { SCRAPS }, "Creature-report")
mark = #env.chat
Loot(BOAR, { MEAT }, "Creature-report")
suite.check("a second opening is not reported", #env.chat == mark, ChatSince(mark))

--------------------------------------------------------------------------------
-- Past the threshold
--------------------------------------------------------------------------------

ns.HandleSlash("report off")

-- Take the boar tally to exactly 19 kills, then look at a clean mob instead
-- where the arithmetic is easy to check by hand.
local WOLF = "Mangy Wolf"
local FANG = { name = "Wolf Fang" }
local HIDE = { name = "Ruined Leather Scraps" }

-- 20 kills: fang on 5 of them, scraps on 1.
for index = 1, 19 do
    Loot(WOLF, index <= 5 and { FANG } or {})
end

summary = Tracker:Summary(WOLF)
suite.check("19 kills is not enough", summary.rated == false)

-- The last stretch: green, and the countdown cheers.
local _, wolfBandAt = Line(WOLF)
if UI.shown[wolfBandAt + 1].style == "place" then wolfBandAt = wolfBandAt + 1 end
local wolfBar = UI.shown[wolfBandAt + 1]
suite.check("at 19 of 20 the bar is in its last stretch",
    wolfBar and wolfBar.style == "progress" and wolfBar.final == true)
suite.check("with every mark passed", wolfBar and wolfBar.milestone == 3)
suite.check("and the countdown says so in green",
    UI.shown[wolfBandAt + 2].left == "1 more kill for drop rates!"
    and UI.shown[wolfBandAt + 2].leftColor == "good", UI.shown[wolfBandAt + 2].left)

ns.HandleSlash("report on")
mark = #env.chat
Loot(WOLF, { HIDE })

summary = Tracker:Summary(WOLF)
suite.check("20 kills is enough", summary.rated == true)
suite.check("the best-seen item comes first", summary.items[1].name == "Wolf Fang")
suite.check("the rate is corpses over kills", summary.items[1].chance == 25,
    summary.items[1].chance)

said = ChatSince(mark)
suite.check("the report on the 20th kill has rates",
    said:find("Wolf Fang", 1, true) ~= nil and said:find("25%", 1, true) ~= nil, said)
suite.check("and names the rarer drop too", said:find("5%", 1, true) ~= nil, said)

local _, wolfAt = Line(WOLF)
-- Under the band: where it was killed, what a kill is worth, then its drops.
local wolfIcons
for index = wolfAt + 1, #UI.shown do
    local line = UI.shown[index]
    if line.style == "progress" then suite.check("the progress bar is gone once rates show", false) end
    if line.style == "icons" then wolfIcons = line break end
    if line.style == "mob" then break end
end
suite.check("the latest mob is listed first",
    wolfAt and wolfAt < select(2, Line(BOAR)), wolfAt)
suite.check("its items switch to percentages",
    wolfIcons and wolfIcons.icons[1].item == "Wolf Fang" and wolfIcons.icons[1].text == "25%",
    wolfIcons and wolfIcons.icons[1].text)
suite.check("coloured by how good the rate is",
    wolfIcons and wolfIcons.icons[2].textColor == "muted", wolfIcons and wolfIcons.icons[2].textColor)
suite.check("the boar, no longer the one you are on, folds to one line",
    Line(BOAR) and Line(BOAR).folded == true)
suite.check("with its loot as small icons", Line(BOAR) and #Line(BOAR).minis > 0)
suite.check("and the countdown goes", Line("0 more kills for drop rates") == nil)

ns.HandleSlash("report off")

suite.check("FormatChance: under one percent", Tracker.FormatChance(0.4) == "<1%")
suite.check("FormatChance: one decimal under ten", Tracker.FormatChance(7.5) == "7.5%")
suite.check("FormatChance: no trailing .0", Tracker.FormatChance(5) == "5%",
    Tracker.FormatChance(5))
suite.check("FormatChance: whole above ten", Tracker.FormatChance(42.6) == "43%")

--------------------------------------------------------------------------------
-- What is not a kill
--------------------------------------------------------------------------------

local kills = Tracker:Summary(WOLF).kills

env.world.fishing = true
Loot(WOLF, { FANG })
env.world.fishing = false
suite.check("fishing is not a kill", Tracker:Summary(WOLF).kills == kills)

env.world.target = { name = "Blackthornes", dead = true, isPlayer = true, guid = "Player-1" }
env.world.loot = { FANG }
fire(ns.eventFrame, "LOOT_OPENED")
suite.check("a player corpse is not a kill", Tracker:Summary("Blackthornes") == nil)

-- Instances: a secret guid is a kill we cannot recognise again, and a secret
-- item name loses only that item. Neither is an error.
env.world.target = { name = WOLF, level = 8, dead = true, guid = env.Secret("guid") }
env.world.loot = { { name = env.Secret("item") }, FANG }

local ok, err = pcall(fire, ns.eventFrame, "LOOT_OPENED")
suite.check("secret values do not raise", ok, err)
suite.check("a secret guid still counts the kill",
    Tracker:Summary(WOLF).kills == kills + 1, Tracker:Summary(WOLF).kills)

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

mark = #env.chat
ns.HandleSlash("kills mangy")
said = ChatSince(mark)
suite.check("/farm kills finds a mob by prefix", said:find("Mangy Wolf", 1, true) ~= nil, said)

mark = #env.chat
ns.HandleSlash("kills nobody")
said = ChatSince(mark)
suite.check("/farm kills says when it has nothing", said:find("no kills of nobody", 1, true), said)

ns.HandleSlash("tracker")
suite.check("/farm tracker hides the panel", ns.db.trackerHidden and not UI.frame:IsShown())

Loot(WOLF, {})
suite.check("a hidden panel stays hidden on the next kill", not UI.frame:IsShown())

ns.HandleSlash("tracker")
suite.check("/farm tracker brings it back", not ns.db.trackerHidden and UI.frame:IsShown())

--------------------------------------------------------------------------------
-- Where each kill happened
--------------------------------------------------------------------------------

local BAT = "Vampiric Duskbat"
env.world.zone, env.world.subZone = "Tirisfal Glades", "Brightwater Lake"
Loot(BAT, {})
Loot(BAT, {})
env.world.subZone = "Agamand Mills"
Loot(BAT, {})
env.world.subZone = nil
Loot(BAT, {})

local places, unplaced = ns.Tracker:Places(BAT)
suite.check("each kill notes its subzone and zone",
    places[1].name == "Brightwater Lake, Tirisfal Glades" and places[1].kills == 2,
    places[1] and places[1].name)
suite.check("most kills first, then by name",
    places[2].name == "Agamand Mills, Tirisfal Glades" and places[3].name == "Tirisfal Glades",
    places[2] and places[2].name)
suite.check("outside any subzone it is the zone alone", places[3].kills == 1)
suite.check("every kill has a place", unplaced == 0, unplaced)

-- A skinning window on the same corpse is not a second kill somewhere.
env.world.subZone = "Brightwater Lake"
Loot(BAT, {}, "Creature-bat-skin")
env.world.subZone = "Agamand Mills"
Loot(BAT, {}, "Creature-bat-skin")
places = ns.Tracker:Places(BAT)
suite.check("a corpse opened twice counts in one place",
    places[1].kills == 3 and places[2].kills == 1, places[1].kills)

-- A zone the client will not name: the kill counts, with no place.
local realZone = env.world.zone
env.world.zone = env.Secret("string")
Loot(BAT, {})
env.world.zone = realZone
places, unplaced = ns.Tracker:Places(BAT)
suite.check("an unreadable zone still counts the kill",
    ns.Tracker:Summary(BAT).kills == 6, ns.Tracker:Summary(BAT).kills)
suite.check("but gives it no place", unplaced == 1, unplaced)

ns.TrackerUI:Refresh()
local _, batAt = Line(BAT)
local placeLine = batAt and ns.TrackerUI.shown[batAt + 1]
suite.check("the panel shows the top place under the mob",
    placeLine and placeLine.style == "place"
        and placeLine.left == "Brightwater Lake, Tirisfal Glades",
    placeLine and placeLine.left)
suite.check("and how many more places there are",
    placeLine and placeLine.right == "+2 more", placeLine and placeLine.right)

suite.check("the places read as one line",
    ns.Tracker.PlacesText(places, 2)
        == "Brightwater Lake, Tirisfal Glades (3); Agamand Mills, Tirisfal Glades (1); +1 more",
    ns.Tracker.PlacesText(places, 2))

local mark = #env.chat
ns.HandleSlash("kills " .. BAT)
local said = ChatSince(mark)
suite.check("/farm kills says where", said:find("Brightwater Lake, Tirisfal Glades (3)", 1, true) ~= nil, said)
suite.check("and owns up to kills with no place",
    said:find("1 kill with no place", 1, true) ~= nil, said)

-- A tally from before places were kept: its kills are counted as unplaced,
-- not shared out among the places that come after.
ns.db.tracker.mobs["Old Timer"] = { kills = 9, items = {} }
places, unplaced = ns.Tracker:Places("Old Timer")
suite.check("an old tally has no places", #places == 0 and unplaced == 9, unplaced)
env.world.subZone = "The Bulwark"
Loot("Old Timer", {})
places, unplaced = ns.Tracker:Places("Old Timer")
suite.check("and starts noting them from the next kill",
    #places == 1 and places[1].kills == 1 and unplaced == 9, unplaced)
env.world.zone, env.world.subZone = "Silverpine Forest", "The Sepulcher"

suite.check("a subzone named like its zone is the zone once",
    ns.Tracker.PlaceName("Undercity", "Undercity") == "Undercity")
suite.check("no zone, no place", ns.Tracker.PlaceName(nil, "Somewhere") == nil)

--------------------------------------------------------------------------------
-- Across a reload
--------------------------------------------------------------------------------

local saved = BlackthornesFarmerDB
local wolfKills = Tracker:Summary(WOLF).kills

ns = env.Load({ ui = true })
BlackthornesFarmerDB = saved
ns.LoadSavedVariables()

summary = ns.Tracker:Summary(WOLF)
suite.check("the tally survives a reload", summary and summary.kills == wolfKills,
    summary and summary.kills)
suite.check("the session count starts again", summary.session == 0, summary.session)
suite.check("so do the corpses it remembers", next(ns.Tracker.corpses) == nil)

--------------------------------------------------------------------------------
-- Reset
--------------------------------------------------------------------------------

ns.HandleSlash("tracker reset")
suite.check("reset alone asks for confirmation", ns.Tracker:Summary(WOLF) ~= nil)

local harvested = ns.Harvest:CountCorpses()
ns.Tracker:Looks()["Reset Test Cloth"] = { id = 4306, color = "ffffffff" }

ns.HandleSlash("tracker reset confirm")
suite.check("and keeps what each item looks like, for its price",
    ns.Tracker:Looks()["Reset Test Cloth"] and ns.Tracker:Looks()["Reset Test Cloth"].id == 4306)
suite.check("reset confirm clears it", ns.Tracker:Summary(WOLF) == nil)
suite.check("and leaves the harvest alone", ns.Harvest:CountCorpses() == harvested,
    ns.Harvest:CountCorpses())

--------------------------------------------------------------------------------
-- A long session
--------------------------------------------------------------------------------

-- The reload above left a fresh addon with nothing listening; log it in.
ns.Harvest:OnEnable()
ns.Tracker:OnEnable()
ns.TrackerUI:OnEnable()
fire = ns.eventFrame:GetScript("OnEvent")

for index = 1, 30 do
    Loot("Kobold " .. index, { { name = "Linen Cloth" } })
end

--- Whether the lines showing fit a panel `height` tall.
local function Fits(height)
    local TUI = ns.TrackerUI
    local used = 0
    for _, line in ipairs(TUI.shown) do used = used + TUI:LineHeight(line, TUI.frame:GetWidth()) end
    return used <= height - TUI.TOP - 16, used
end

local shown = ns.TrackerUI.shown
suite.check("a long session fills the panel and no more", Fits(420) and #shown > 5, #shown)
suite.check("folded, thirty mobs take a line each", #shown >= 15, #shown)
suite.check("the bottom edge says how many more are below",
    ns.TrackerUI.moreLabel:IsShown()
    and ns.TrackerUI.moreLabel:GetText():find("more below, scroll", 1, true) ~= nil,
    ns.TrackerUI.moreLabel:GetText())
suite.check("a full panel stops growing at its tallest",
    ns.TrackerUI.frame:GetHeight() <= 420, ns.TrackerUI.frame:GetHeight())
suite.check("and the newest mob is still at the top",
    Line("Kobold 30") ~= nil and Line("Kobold 30").folded == false)

-- The wheel scrolls (2026-09-28: no more cutting off).
local top = shown[1]
ns.TrackerUI:ScrollBy(4)
suite.check("scrolling moves the column", ns.TrackerUI.scroll == 4 and ns.TrackerUI.shown[1] ~= top,
    ns.TrackerUI.scroll)
ns.TrackerUI:ScrollBy(999)
suite.check("no further than the last line", ns.TrackerUI.scroll == ns.TrackerUI.maxScroll
    and Line("Kobold 1") ~= nil, ns.TrackerUI.scroll)
suite.check("and nothing is left below", not ns.TrackerUI.moreLabel:IsShown())
ns.TrackerUI:ScrollBy(-999)
suite.check("and back to the top", ns.TrackerUI.scroll == 0)
local wheel = ns.TrackerUI.frame:GetScript("OnMouseWheel")
wheel(ns.TrackerUI.frame, -1)
suite.check("the mouse wheel scrolls it", ns.TrackerUI.scroll > 0, ns.TrackerUI.scroll)
wheel(ns.TrackerUI.frame, 1)

-- A folded mob opens with a click on its band, and folds again.
local _, koboldAt = Line("Kobold 28")
local koboldRow = koboldAt and ns.TrackerUI.lines[koboldAt]
if koboldRow then koboldRow:GetScript("OnMouseUp")(koboldRow, "LeftButton") end
suite.check("clicking a folded band opens it", Line("Kobold 28") and Line("Kobold 28").folded == false)
_, koboldAt = Line("Kobold 28")
koboldRow = ns.TrackerUI.lines[koboldAt]
koboldRow:GetScript("OnMouseUp")(koboldRow, "LeftButton")
suite.check("and again folds it", Line("Kobold 28").folded == true)

--------------------------------------------------------------------------------
-- Resizing
--------------------------------------------------------------------------------

local TUI = ns.TrackerUI

-- The first row with a value on the right (the gathered value that used to be
-- row 2 is in the title bar now).
local valued
for index, line in ipairs(TUI.shown) do
    if line.right and line.right ~= "" and line.style ~= "heading" then valued = TUI.lines[index] break end
end
suite.check("a line with a value stops short of it",
    valued and valued.leftStop > 8, valued and valued.leftStop)

ns.db.trackerWidth, ns.db.trackerHeight = 400, 200
TUI:Refresh()
suite.check("a saved width is the width", TUI.frame:GetWidth() == 400, TUI.frame:GetWidth())
suite.check("a saved height caps the lines", Fits(200), #TUI.shown)
suite.check("and the panel is no taller than it",
    TUI.frame:GetHeight() <= 200, TUI.frame:GetHeight())

ns.db.trackerWidth, ns.db.trackerHeight = 5, 99999
suite.check("too narrow is held at the minimum", TUI:Width() == 180, TUI:Width())
suite.check("too tall is held at the maximum", TUI:MaxHeight() == 1000, TUI:MaxHeight())
ns.db.trackerWidth, ns.db.trackerHeight = nil, nil

-- Drag the grip: press, the frame is sized by the drag, release.
local press = TUI.grip:GetScript("OnMouseDown")
local release = TUI.grip:GetScript("OnMouseUp")
suite.check("the panel has a resize grip", type(press) == "function" and type(release) == "function")

-- The client left the panel hanging from its bottom after an earlier drag.
TUI.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 8, 300)
TUI.frame._left, TUI.frame._top = 8, 900
local heightBefore = TUI.frame:GetHeight()
press(TUI.grip)
suite.check("pressing the grip leaves the corner under the cursor",
    TUI.frame:GetHeight() == heightBefore, TUI.frame:GetHeight())
suite.check("pressing the grip starts sizing", TUI.sizing == true)
local pinned = TUI.frame._point
suite.check("pressing the grip pins the panel by its top",
    pinned[1] == "TOPLEFT" and pinned[3] == "BOTTOMLEFT" and pinned[4] == 8 and pinned[5] == 900,
    table.concat(pinned, ",", 3))
TUI.frame:SetWidth(320)
TUI.frame:SetHeight(260)
TUI.frame:GetScript("OnSizeChanged")(TUI.frame)
suite.check("mid-drag the lines follow the drag", Fits(260), #TUI.shown)
release(TUI.grip)

suite.check("letting go saves the width", ns.db.trackerWidth == 320, ns.db.trackerWidth)
suite.check("and the height", ns.db.trackerHeight == 260, ns.db.trackerHeight)
suite.check("and stops sizing", TUI.sizing == false)
suite.check("the panel keeps the new width", TUI.frame:GetWidth() == 320, TUI.frame:GetWidth())
suite.check("letting go keeps the top where it was",
    TUI.frame._point[1] == "TOPLEFT" and TUI.frame._point[5] == 900, TUI.frame._point[1])
suite.check("and saves it by the top",
    ns.db.trackerPoint == "TOPLEFT" and ns.db.trackerRelativePoint == "BOTTOMLEFT"
        and ns.db.trackerY == 900, ns.db.trackerPoint)

-- Moving the panel: the client re-anchors it to the centre on the way.
TUI.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
TUI.frame._left, TUI.frame._top = 100, 700
TUI.frame:GetScript("OnDragStop")(TUI.frame)
suite.check("a moved panel is saved by its top",
    ns.db.trackerPoint == "TOPLEFT" and ns.db.trackerX == 100 and ns.db.trackerY == 700,
    ns.db.trackerPoint)

ns.SettingsUI:ResetPositions()
suite.check("putting windows back resets the size too",
    ns.db.trackerWidth == nil and TUI:Width() == 260, ns.db.trackerWidth)

ns.HandleSlash("tracker off")
suite.check("/farm tracker off hides it", not ns.TrackerUI.frame:IsShown())
ns.HandleSlash("tracker on")
suite.check("/farm tracker on shows it", ns.TrackerUI.frame:IsShown())

--------------------------------------------------------------------------------
-- A panel saved where the first version put it moves to the left, once
--------------------------------------------------------------------------------

ns = env.Load({ ui = true })
BlackthornesFarmerDB = { trackerPoint = "RIGHT", trackerRelativePoint = "RIGHT",
    trackerX = -220, trackerY = 120 }
ns.LoadSavedVariables()
ns.TrackerUI:OnEnable()

local point = ns.TrackerUI.frame._point
suite.check("an old right-side panel moves to the left",
    point[1] == "TOPLEFT" and point[4] == 8, point[1])

-- Dragged somewhere after that, it stays there.
ns.db.trackerPoint, ns.db.trackerRelativePoint = "TOPLEFT", "BOTTOMLEFT"
ns.db.trackerX, ns.db.trackerY = 40, 600
ns.TrackerUI:RestorePosition()
point = ns.TrackerUI.frame._point
suite.check("a panel moved after that stays moved",
    point[1] == "TOPLEFT" and point[3] == "BOTTOMLEFT" and point[4] == 40 and point[5] == 600,
    point[1])

-- One saved by an earlier version from its centre is re-pinned by its top.
ns.db.trackerPoint, ns.db.trackerRelativePoint = "LEFT", "LEFT"
ns.db.trackerX, ns.db.trackerY = 40, 0
ns.TrackerUI.frame._left, ns.TrackerUI.frame._top = 40, 650
ns.TrackerUI:RestorePosition()
point = ns.TrackerUI.frame._point
suite.check("a panel saved from its centre is pinned by its top where it sits",
    point[1] == "TOPLEFT" and point[4] == 40 and point[5] == 650, point[1])
suite.check("and saved that way", ns.db.trackerPoint == "TOPLEFT" and ns.db.trackerY == 650,
    ns.db.trackerPoint)

suite.done()
