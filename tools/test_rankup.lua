-- The rank-up pop-up (the owner, 2026-10-13): your top 15 by worth per kill,
-- shown for a few seconds when a kill moves a mob up it or onto it.
--
-- What must hold:
--   1. A kill that moves its mob up into or within the top 15 shows the
--      card, starting from the old order and ending on the new, with the
--      climb ("+3") on the mob; a kill that moves nothing, or moves a mob
--      down, shows nothing.
--   2. A mob new to the board says NEW; on its 20th kill the milestone
--      fanfare has played, so the chime does not play over it.
--   3. Never in a fight: it waits for the fight to end, then shows.
--   4. The mob pushed out of the top 15 slides off the bottom.
--   5. /farm rankup off, and sound off, are kept; Settings has both, and
--      Show it opens the board as it stands.
--   6. It holds while the mouse is over it, then fades and hides.
--   7. Only mobs whose kill count moved are valued again.
--   8. It can be dragged; its spot is kept and used, and Set Default
--      (/farm rankup reset) puts it back beside the kills panel.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("rankup")

local ns = env.Load({ ui = true })
local Tracker = ns.Tracker
local RankUp = ns.RankUp
local RankUpUI = ns.RankUpUI

_G.C_Item = { GetItemInfo = function() return "item", nil, 1, 1, 1, "", "", 1, "", "", 0 end }

local played = {}
_G.PlaySoundFile = function(path)
    played[#played + 1] = path
    return true
end
_G.PlaySound = function() return true end

local fighting = false
_G.InCombatLockdown = function() return fighting end

RankUp:OnEnable()

local serial = 0
local function Kill(mob, copper)
    serial = serial + 1
    env.world.target = { name = mob, level = 10, dead = true, guid = "K-" .. serial }
    env.world.loot = copper and copper > 0 and { { name = copper .. " Copper", money = true } } or {}
    Tracker:OnLoot()
end

-- Sixteen measured mobs, Mob 01 best (290c a kill) down to Mob 16 (140c).
local function Name(index) return ("Mob %02d"):format(index) end
for index = 1, 16 do
    for _ = 1, 20 do Kill(Name(index), 300 - 10 * index) end
end

local function Settle()
    ns.Motion:FinishAll()
    ns.Motion:FinishAll()
end

local function Reset()
    RankUpUI:Hide()
    played = {}
end

local valued = 0
local realEntry = ns.Rankings.Entry
ns.Rankings.Entry = function(self, name)
    valued = valued + 1
    return realEntry(self, name)
end

-- The kills above came before any order was laid out (in game it is done
-- a few frames after login); start from login.
RankUp:Forget()

-- The order is laid out a few mobs a frame after login; the test runs it
-- through at once.
local entered = ns.eventFrame:GetScript("OnEvent")
entered(ns.eventFrame, "PLAYER_ENTERING_WORLD")
suite.check("the order is laid out over frames after login", RankUp.building ~= nil)
RankUp:Step(RankUp.SLICE)
suite.check("a few mobs a frame", RankUp.building and #RankUp.building.queue == 16 - RankUp.SLICE,
    RankUp.building and #RankUp.building.queue)
RankUp:BuildNow()
suite.check("and then all of them", RankUp.snapshot and #RankUp.snapshot.list == 16,
    RankUp.snapshot and #RankUp.snapshot.list)
suite.check("best first", RankUp.snapshot.list[1].mob == "Mob 01" and RankUp.snapshot.list[16].mob == "Mob 16")

--------------------------------------------------------------------------------
-- 1. A climb
--------------------------------------------------------------------------------

Reset()
valued = 0
-- Mob 12 (180c) gets a rich kill: (180 * 20 + 1000) / 21 = 219c, ninth.
Kill(Name(12), 1000)
suite.check("only the mob killed is valued again", valued == 1, valued)
suite.check("a climb shows the card", RankUpUI:IsShown())
suite.check("it starts from the old order",
    RankUpUI.items and (function()
        for _, item in ipairs(RankUpUI.items) do
            if item.picked then return item.from == 11 and item.to == 8 end
        end
    end)())

local picked
for _, item in ipairs(RankUpUI.items) do
    if item.picked then picked = item end
end
suite.check("the mob that moved is the one picked", picked and picked.mob == "Mob 12")
suite.check("its worth counts up from the old", picked.fromValue == 180 and math.floor(picked.value) == 219,
    tostring(picked.fromValue) .. " " .. tostring(picked.value))
suite.check("it is lit as the row picked", picked.row.active:IsShown() and picked.row.edge:IsShown())
suite.check("it is still moving", ns.Motion:Running(RankUpUI.frame, "swap"))
suite.check("no chime before it lands", #played == 0, #played)

Settle()
suite.check("it lands at ninth", picked.row.rank:GetText() == "9", picked.row.rank:GetText())
suite.check("with its climb", picked.row.chip:IsShown() and picked.row.chip.label:GetText() == "+3",
    picked.row.chip.label:GetText())
suite.check("and the chime",
    #played == 1 and played[1]:find("rank-up.ogg", 1, true) ~= nil, played[1])
suite.check("the foot says what moved",
    RankUpUI.foot:GetText():find("Mob 12 moved up", 1, true) ~= nil, RankUpUI.foot:GetText())

-- A mob it passed slid down one.
for _, item in ipairs(RankUpUI.items) do
    if item.mob == Name(9) then
        suite.check("the mobs it passed slide down one", item.from == 8 and item.to == 9)
    end
end

-- The rows sit on the stripes; the stripes stay by place.
suite.check("the stripes take glass by place",
    RankUpUI.stripes[1]._shown ~= false and #RankUpUI.stripes == 15)

--------------------------------------------------------------------------------
-- 6. Holding and fading
--------------------------------------------------------------------------------

local frame = RankUpUI.frame
frame.IsMouseOver = function() return true end
RankUpUI:Tick(RankUpUI.HOLD + 1)
suite.check("the mouse over it keeps it up", frame:IsShown() and not RankUpUI.fading)
frame.IsMouseOver = function() return false end
RankUpUI:Tick(RankUpUI.HOLD - 1)
suite.check("it holds for a few seconds", frame:IsShown() and not RankUpUI.fading)
RankUpUI:Tick(1.5)
suite.check("then fades", RankUpUI.fading)
Settle()
suite.check("and is gone", not frame:IsShown())

--------------------------------------------------------------------------------
-- 1b. Nothing to show
--------------------------------------------------------------------------------

Reset()
Kill(Name(3), 0)
suite.check("a kill that moves its mob down shows nothing", not RankUpUI:IsShown())
Kill(Name(1), 290)
suite.check("nor does one that moves nothing", not RankUpUI:IsShown())

--------------------------------------------------------------------------------
-- 4. Into the top 15 from below it
--------------------------------------------------------------------------------

Reset()
Kill(Name(16), 3000)
suite.check("a mob climbing into the top 15 shows it", RankUpUI:IsShown())
local pushed
for _, item in ipairs(RankUpUI.items) do
    if item.picked then picked = item end
    if item.from == 14 and not item.picked then pushed = item end
end
suite.check("from below the list", picked.mob == "Mob 16" and picked.from == 15, picked.from)
suite.check("and the old fifteenth slides off the bottom", pushed and pushed.to == RankUp.TOP,
    pushed and pushed.to)
Settle()

--------------------------------------------------------------------------------
-- 2. New to the board
--------------------------------------------------------------------------------

Reset()
for _ = 1, 19 do Kill("Fresh Boar", 250) end
suite.check("a mob short of 20 kills is not on the board", not RankUpUI:IsShown())
Kill("Fresh Boar", 250)
suite.check("the 20th kill puts it on, with the card", RankUpUI:IsShown())
for _, item in ipairs(RankUpUI.items) do
    if item.picked then picked = item end
end
suite.check("sliding in at its place", picked.mob == "Fresh Boar" and picked.slideIn
    and picked.from == picked.to)
Settle()
suite.check("tagged NEW", picked.row.chip.label:GetText() == "NEW", picked.row.chip.label:GetText())
local chimes = 0
for _, path in ipairs(played) do
    if path:find("rank-up.ogg", 1, true) then chimes = chimes + 1 end
end
suite.check("the fanfare played and the chime did not", chimes == 0
    and played[1] and played[1]:find("drop-rates-unlocked", 1, true) ~= nil, table.concat(played, ","))
suite.check("the foot says it is on the board",
    RankUpUI.foot:GetText():find("Fresh Boar is on your board now", 1, true) ~= nil)

--------------------------------------------------------------------------------
-- 3. Never in a fight
--------------------------------------------------------------------------------

Reset()
fighting = true
Kill(Name(15), 3000)
suite.check("in a fight it waits", not RankUpUI:IsShown() and RankUp.waiting)
fighting = false
entered(ns.eventFrame, "PLAYER_REGEN_ENABLED")
suite.check("and shows when the fight ends", RankUpUI:IsShown())
Settle()

--------------------------------------------------------------------------------
-- 5. Switches
--------------------------------------------------------------------------------

Reset()
ns.HandleSlash("rankup sound off")
suite.check("sound off is kept", ns.db.rankUpSound == false)
Kill(Name(14), 3000)
Settle()
suite.check("it still shows, with no chime", RankUpUI:IsShown() and #played == 0, #played)

Reset()
ns.HandleSlash("rankup off")
suite.check("off is kept", ns.db.rankUpPopup == false)
Kill(Name(13), 4000)
suite.check("and nothing shows", not RankUpUI:IsShown())
ns.HandleSlash("rankup on")
ns.HandleSlash("rankup sound on")
suite.check("both come back", RankUp.On() and RankUp.SoundOn())

ns.HandleSlash("rankup show")
suite.check("show holds up the board as it stands", RankUpUI:IsShown()
    and RankUpUI.foot:GetText():find("Your best mobs", 1, true) ~= nil)
local still = true
for _, item in ipairs(RankUpUI.items) do
    if item.picked or item.from ~= item.to then still = false end
end
suite.check("with nothing moving", still)
Settle()

--------------------------------------------------------------------------------
-- Effects off: the new order, nothing moving.
--------------------------------------------------------------------------------

Reset()
ns.db.trackerEffects = "off"
Kill(Name(10), 5000)
suite.check("with effects off it shows the new order at once",
    RankUpUI:IsShown() and not ns.Motion:Running(RankUpUI.frame))
ns.db.trackerEffects = nil

-- The card is a window too: the house size grip, its size its own.
suite.check("it wears the size grip", RankUpUI.sizeGrip ~= nil)

-- Clicking a row opens that mob's loot table.
local opened
local realShow = ns.LootTableUI.Show
ns.LootTableUI.Show = function(_, mob) opened = mob; return true end
local row = RankUpUI.items[1].row
row:GetScript("OnClick")(row, "LeftButton")
ns.LootTableUI.Show = realShow
suite.check("a click on a row opens its loot table", opened == RankUpUI.items[1].mob, opened)
row:GetScript("OnClick")(row, "RightButton")
suite.check("a right-click puts it away", not RankUpUI:IsShown())

--------------------------------------------------------------------------------
-- The rank on the kills panel's cards
--------------------------------------------------------------------------------

local function RankLine(mob)
    local lines, inCard = ns.TrackerUI:Lines(), false
    for _, line in ipairs(lines) do
        if line.style == "mob" then inCard = line.mob == mob end
        if inCard and line.style == "value" and line.left == "Rank" then return line.right end
    end
    return nil
end

Reset()
Kill(Name(9), 300)
local rank, ranked = RankUp:RankOf(Name(9))
suite.check("a ranked mob's card shows its place", rank and RankLine(Name(9)) == ("#%d of %d"):format(rank, ranked),
    tostring(RankLine(Name(9))))
for _ = 1, 3 do Kill("Young Boar", 50) end
suite.check("a mob short of 20 kills shows no rank", RankLine("Young Boar") == nil)

-- With the pop-up off the order still follows the kills.
ns.HandleSlash("rankup off")
Kill(Name(16), 90000)
suite.check("the rank follows a climb with the pop-up off", RankUp:RankOf(Name(16)) == 1
    and not RankUpUI:IsShown(), RankUp:RankOf(Name(16)))
suite.check("and the card says so", RankLine(Name(16)) and RankLine(Name(16)):find("^#1 of") ~= nil,
    tostring(RankLine(Name(16))))
ns.HandleSlash("rankup on")
Settle()

-- A reset clears the tallies; the order follows without a pop-up.
Reset()
Tracker:Reset()
Kill("Lone Wolf", 10)
suite.check("after a reset nothing pops up", not RankUpUI:IsShown())
suite.check("and the order is empty", #RankUp.snapshot.list == 0, #RankUp.snapshot.list)

-- Drag it somewhere: the spot is kept and used from then on.
local card = RankUpUI:Build()
card._left, card._top = 300, 700
card:GetScript("OnDragStart")(card)
card:GetScript("OnDragStop")(card)
suite.check("a drag keeps its top left", ns.db.rankUpX == 300 and ns.db.rankUpY == 700,
    tostring(ns.db.rankUpX) .. "," .. tostring(ns.db.rankUpY))
RankUpUI:Place()
suite.check("and it opens there", card._point[1] == "TOPLEFT" and card._point[2] == UIParent
    and card._point[4] == 300 and card._point[5] == 700)
ns.HandleSlash("rankup reset")
suite.check("reset forgets the spot", ns.db.rankUpX == nil and ns.db.rankUpY == nil)
suite.check("and it goes back to its usual place", not (card._point[4] == 300 and card._point[5] == 700))

suite.done()
