-- What this session's haul is worth (2026-09-25).
--
-- The panel's title bar shows a "Gathered value" on its second line (moved
-- there from the top of THIS SESSION, 2026-09-27): the coin off
-- this session's kills plus every item looted or fished up, times its unit
-- price (the same price worth per kill uses). What matters: every stack and
-- every coin counts once, a second window on a skinned corpse adds only the
-- new leather, items with no price are left out and noted rather than
-- guessed, fishing alone still gets a total, and a reset starts it over.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("sessionvalue")

local ns = env.Load({ ui = true })
local Value = ns.Value
local Tracker = ns.Tracker
local Fishing = ns.Fishing
local TUI = ns.TrackerUI

-- Vendor and auction prices, as in test_value: the higher one wins.
local VENDOR = { [5637] = 10, [2934] = 5, [2318] = 15, [6291] = 1 }
local AUCTION = { [5637] = 50, [2934] = 3, [2318] = 40 }

_G.C_Item = {
    GetItemInfo = function(id)
        return "item", nil, 1, 1, 1, "", "", 1, "", "", VENDOR[id] or 0
    end,
}
_G.BlackthornesTS = { Prices = { GetValue = function(_, id) return AUCTION[id] end } }

TUI:OnEnable()

local function Line(left)
    for _, line in ipairs(TUI.shown or {}) do
        if line.left == left then return line end
    end
end

suite.check("nothing gathered has no total", Value:Session() == nil)
suite.check("and the empty panel shows none", TUI.titleLine == nil)
suite.check("so the title bar's second line reads 0c",
    TUI.titleRow.right:GetText() == Value.Coins(0), TUI.titleRow.right:GetText())
suite.check("no line of words under the title", (TUI.titleRow.left:GetText() or "") == "")
do
    local said
    local tip = _G.GameTooltip
    local old = tip.AddLine
    tip.AddLine = function(self, text, ...) said = said or text if old then return old(self, text, ...) end end
    local enter = TUI.titleRow:GetScript("OnEnter")
    if enter then enter(TUI.titleRow) end
    tip.AddLine = old
    suite.check("what the number is shows on hover", said == "Gathered value", said)
end

local serial = 0
local function Loot(mob, items, guid)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, guid = guid or ("C-" .. serial) }
    env.world.loot = items
    Tracker:OnLoot()
end

local FANG = { name = "Large Fang", id = 5637 }
local SCRAPS = { name = "Ruined Leather Scraps", id = 2934, quantity = 2 }
local LEATHER = { name = "Light Leather", id = 2318 }
local ROCK = { name = "Odd Rock" }  -- no id, no price anywhere
local COINS = { name = "12 Copper", money = true }

Loot("Mangy Wolf", { COINS, FANG, SCRAPS }, "W-1")

-- 12c coin + 1 fang at 50 + 2 scraps at 5 (vendor beats auction's 3).
local total, details = Value:Session()
suite.check("coin and loot add up", total == 12 + 50 + 2 * 5, total)
suite.check("the coin is kept apart", details.coin == 12, details.coin)

local line = TUI.titleLine
suite.check("the panel shows it", line and line.right == Value.Coins(72), line and line.right)
suite.check("in the good colour", line and line.rightColor == "good")
suite.check("in the title bar", TUI.titleRow.right:GetText() == Value.Coins(72),
    TUI.titleRow.right:GetText())
suite.check("not in the column", Line("Gathered value") == nil)
suite.check("the column starts with THIS SESSION", TUI.shown[1].left == "THIS SESSION")
suite.check("the panel is wide enough for the label and the value",
    TUI.frame:GetWidth() >= ns.Theme.TextWidth("small", "Gathered value")
        + ns.Theme.TextWidth("normal", Value.Money(72)) + 20, TUI.frame:GetWidth())

-- Skinning the same corpse: coin is not taken twice, the leather is new.
Loot("Mangy Wolf", { LEATHER }, "W-1")
total = Value:Session()
suite.check("skinning adds only the leather", total == 72 + 40, total)

-- A second kill with something unpriced.
Loot("Mangy Wolf", { COINS, ROCK }, "W-2")
total, details = Value:Session()
suite.check("an unpriced item is not guessed", total == 112 + 12, total)
suite.check("but is listed", details.unpriced[1] == "Odd Rock", details.unpriced[1])
suite.check("and noted on the panel", Line("1 item with no price left out") ~= nil)

-- Fishing adds its catches to the same total (the database knows the fish's id).
Fishing:Record("Elwynn Forest", nil, nil, { "Raw Brilliant Smallfish" },
    { ["Raw Brilliant Smallfish"] = 3 })
total = Value:Session()
suite.check("fished-up items count too", total == 124 + 3 * 1, total)

-- With only fishing done, the total sits under the Fishing heading.
Tracker:Reset()
TUI:Refresh()
total, details = Value:Session()
suite.check("a tracker reset keeps the fish", total == 3, total)
suite.check("and forgets the session's coin", details.coin == 0, details.coin)
suite.check("fishing alone still shows the total in the title bar",
    TUI.shown[1].left == "FISHING" and TUI.titleLine and TUI.titleLine.right == Value.Coins(3),
    TUI.titleLine and TUI.titleLine.right)

Fishing:Reset()
suite.check("resetting both starts over", Value:Session() == nil)

suite.done()
