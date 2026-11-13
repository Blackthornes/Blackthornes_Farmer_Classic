-- Loot in a party or raid.
--
-- What matters: in a group the loot window shows what dropped, not what you
-- got, so the session's loot and Stats' gold wait for the game's own "You
-- receive loot" line (a roll you win too), while the mob's tally still reads
-- the window. Solo play counts the window as before.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("partyloot")

local ns = env.Load({ ui = true })
local Tracker = ns.Tracker
local TUI = ns.TrackerUI

local VENDOR = { [2592] = 10, [5637] = 50 }
_G.C_Item = { GetItemInfo = function(id)
    return "item", nil, 1, 1, 1, "", "", 1, "", "", VENDOR[id] or 0
end }
Tracker:OnEnable()
TUI:OnEnable()

local now = 1000
local plainTime = _G.GetTime
_G.GetTime = function() return now end
_G.LOOT_ITEM_SELF = "You receive loot: %s."
_G.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."

local grouped = true
local plainGroup = _G.IsInGroup
_G.IsInGroup = function() return grouped end

local plainSlotInfo = _G.GetLootSlotInfo
_G.GetLootSlotInfo = function(slot)
    local item = env.world.loot[slot]
    if not item then return nil end
    return "Interface\\Icons\\INV_Misc_Dust_01", item.name, item.quantity or 1, nil, 2, item.locked
end

local MOB = "Defias Bandit"
local WOOL, FANG = "Wool Cloth", "Large Fang"
local function Open(guid, loot)
    env.world.target = { name = MOB, level = 15, dead = true, guid = guid }
    env.world.loot = loot
    return Tracker:OnLoot()
end
local function Link(name) return "|cffffffff|Hitem:1::::|h[" .. name .. "]|h|r" end
local function Tally() return ns.db.tracker.mobs[MOB] end

-- Patterns from the client's words.
local name, count = Tracker.ParseLootLine("You receive loot: " .. Link(WOOL) .. "x3.")
suite.check("a stack line reads", name == WOOL and count == 3, name, count)
name, count = Tracker.ParseLootLine("You receive loot: " .. Link(FANG) .. ".")
suite.check("a single line reads", name == FANG and count == 1, name, count)
suite.check("someone else's line does not", Tracker.ParseLootLine("Bob receives loot: " .. Link(WOOL) .. ".") == nil)
suite.check("a secret line does not error", pcall(Tracker.ParseLootLine, env.Secret("line")))

-- Grouped: the window alone gives nothing.
Open("Creature-0-1-2-3-100-A", {
    { name = WOOL, id = 2592, quantity = 2 },
    { name = FANG, id = 5637, locked = true },
})
suite.check("the tally still has the wool", Tally().qty[WOOL] == 2, Tally().qty[WOOL])
suite.check("and the rolled fang", Tally().items[FANG] == 1)
suite.check("the session waits for the line", Tracker.sessionLoot[WOOL] == nil, Tracker.sessionLoot[WOOL])

Tracker:OnLootChat("You receive loot: " .. Link(WOOL) .. "x2.")
suite.check("your line counts the wool", Tracker.sessionLoot[WOOL] == 2, Tracker.sessionLoot[WOOL])
suite.check("under the mob", Tracker.sessionFrom[WOOL][MOB] == 2)
suite.check("no fang yet", Tracker.sessionLoot[FANG] == nil)

now = now + 60
Tracker:OnLootChat("You receive loot: " .. Link(FANG) .. ".")
suite.check("a roll you win counts", Tracker.sessionLoot[FANG] == 1, Tracker.sessionLoot[FANG])
Tracker:OnLootChat("You receive loot: " .. Link("Hearthstone") .. ".")
suite.check("a line no window showed counts nothing", Tracker.sessionLoot["Hearthstone"] == nil)

-- Someone else took it: no line, so it never counts.
Open("Creature-0-1-2-3-100-B", { { name = "Linen Cloth", quantity = 1 } })
suite.check("loot someone else took stays out", Tracker.sessionLoot["Linen Cloth"] == nil)

-- A line just before its window is held a moment.
now = now + 1
Tracker:OnLootChat("You receive loot: " .. Link("Ruined Pelt") .. ".")
Open("Creature-0-1-2-3-100-C", { { name = "Ruined Pelt", quantity = 1 } })
suite.check("a line before its window still counts", Tracker.sessionLoot["Ruined Pelt"] == 1,
    Tracker.sessionLoot["Ruined Pelt"])

-- Long after, an old window no longer matches.
now = now + Tracker.PEND_FOR + 1
Tracker:OnLootChat("You receive loot: " .. Link("Linen Cloth") .. ".")
suite.check("an old window does not match", Tracker.sessionLoot["Linen Cloth"] == nil)

-- Words in another order, as some languages have them.
local saved = _G.LOOT_ITEM_SELF_MULTIPLE
_G.LOOT_ITEM_SELF_MULTIPLE = "Beute: %2$dx %1$s."
name, count = Tracker.ParseLootLine("Beute: 4x " .. Link("Wolle") .. ".")
suite.check("a numbered word order still reads", name == "Wolle" and count == 4, name, count)
_G.LOOT_ITEM_SELF_MULTIPLE = saved

-- The chat event reaches it.
now = now + 1
Open("Creature-0-1-2-3-100-D", { { name = "Silk Cloth", quantity = 1 } })
ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, "CHAT_MSG_LOOT", "You receive loot: " .. Link("Silk Cloth") .. ".")
suite.check("the chat event counts silk", Tracker.sessionLoot["Silk Cloth"] == 1, Tracker.sessionLoot["Silk Cloth"])

-- Solo: the window counts as before.
grouped = false
Open("Creature-0-1-2-3-100-E", {
    { name = WOOL, id = 2592, quantity = 1 },
    { name = FANG, id = 5637, locked = true },
})
suite.check("solo wool counts from the window", Tracker.sessionLoot[WOOL] == 3, Tracker.sessionLoot[WOOL])
suite.check("solo locked slot still left out", Tracker.sessionLoot[FANG] == 1, Tracker.sessionLoot[FANG])
Tracker:OnLootChat("You receive loot: " .. Link(WOOL) .. ".")
suite.check("and a solo line adds nothing more", Tracker.sessionLoot[WOOL] == 3, Tracker.sessionLoot[WOOL])

-- An unreadable group answer counts as solo.
_G.IsInGroup = function() return env.Secret("group") end
suite.check("a secret group answer is solo", Tracker.InGroup() == false)

_G.IsInGroup = plainGroup
_G.GetTime = plainTime
_G.GetLootSlotInfo = plainSlotInfo
_G.C_Item = nil
_G.LOOT_ITEM_SELF, _G.LOOT_ITEM_SELF_MULTIPLE = nil, nil

suite.done()
