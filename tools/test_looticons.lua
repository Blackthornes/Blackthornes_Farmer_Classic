-- Loot with no icon.
--
-- What matters: the loot window gives no icon for an item the game has not
-- loaded yet (most often gear with a random suffix), and the panel showed a
-- question mark for it from then on. A look with no icon now takes it from
-- its item ID, and a suffix with an icon stands in for its item.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("looticons")

local ns = env.Load()
local Tracker = ns.Tracker

local BAND, RING, LOST = 990201, 990202, 990203
local ICONS = { [BAND] = 134001, [RING] = 134002 }
local asks = 0

local savedItem = C_Item
C_Item = setmetatable({
    GetItemIconByID = function(id) asks = asks + 1; return ICONS[id] end,
    GetItemNameByID = function(id) if id == BAND then return "Lead Band" end end,
}, { __index = savedItem })
local savedInstant = _G.GetItemInfoInstant
_G.GetItemInfoInstant = nil

local now = 500
local savedTime = _G.GetTime
_G.GetTime = function() return now end

local looks = Tracker:Looks()

-- Looted before the game had the item: an ID from the link, no icon.
looks["Lead Band of the Monkey"] = { id = BAND, color = "ff1eff00" }
suite.check("a look with no icon takes it from the item's ID",
    Tracker:LookOf("Lead Band of the Monkey").icon == 134001)
suite.check("and keeps it", looks["Lead Band of the Monkey"].icon == 134001)

asks = 0
Tracker:LookOf("Lead Band of the Monkey")
suite.check("an icon already kept is not asked for again", asks == 0, asks)

looks["Old Ring"] = { id = RING, icon = "Interface\\Icons\\Own", color = "ff1eff00" }
suite.check("an icon the loot window gave stays",
    Tracker:LookOf("Old Ring").icon == "Interface\\Icons\\Own")

-- An item the game gives no icon for is asked once, then left a while.
looks["Lost Thing"] = { id = LOST }
asks = 0
suite.check("no icon to give, none made up", Tracker:LookOf("Lost Thing").icon == nil)
for _ = 1, 20 do Tracker:LookOf("Lost Thing") end
suite.check("asked once, not on every draw", asks == 1, asks)
now = now + Tracker.ICON_RETRY + 1
ICONS[LOST] = 134003
suite.check("asked again later, and found", Tracker:LookOf("Lost Thing").icon == 134003)

looks["No ID"] = { color = "ffffffff" }
suite.check("a look with no ID is left alone", Tracker:LookOf("No ID").icon == nil)
suite.check("a name never looted is still an empty look", next(Tracker:LookOf("Never Seen")) == nil)

-- A secret icon is not kept.
local savedGet = C_Item.GetItemIconByID
looks["Secret Thing"] = { id = 990204 }
C_Item.GetItemIconByID = function() return env.Secret("icon") end
suite.check("a secret icon is not kept", Tracker:LookOf("Secret Thing").icon == nil)
C_Item.GetItemIconByID = savedGet

-- Without GetItemIconByID, the instant item info gives it.
C_Item.GetItemIconByID = nil
_G.GetItemInfoInstant = function(id) return id, "Armor", "Misc", "", 134009, 4, 0 end
looks["Other Way"] = { id = 990205 }
suite.check("the instant item info's icon serves too", Tracker:LookOf("Other Way").icon == 134009)
_G.GetItemInfoInstant = nil
C_Item.GetItemIconByID = savedGet

-- A suffix with an icon stands in for its item.
looks["Tin Band of the Owl"] = { color = "ff1eff00" }
looks["Tin Band of the Bear"] = { icon = "Interface\\Icons\\Band", color = "ff1eff00" }
Tracker.rollLooks["Tin Band"] = "Tin Band of the Owl"
ns.db.tracker.mobs = ns.db.tracker.mobs or {}
ns.db.tracker.mobs["Icon Test Mob"] = {
    kills = 30,
    items = { ["Tin Band of the Owl"] = 2, ["Tin Band of the Bear"] = 1 },
}
local savedBase = ns.Harvest.RollBase
ns.Harvest.RollBase = function(name)
    return name:match("^(Tin Band) of ") or nil
end
local summary = Tracker:Summary("Icon Test Mob")
ns.Harvest.RollBase = savedBase
suite.check("the mob's tally reads", type(summary) == "table")
suite.check("the suffix with an icon stands in",
    Tracker:LookOf("Tin Band").icon == "Interface\\Icons\\Band", Tracker.rollLooks["Tin Band"])

C_Item = savedItem
_G.GetItemInfoInstant = savedInstant
_G.GetTime = savedTime

suite.done()
