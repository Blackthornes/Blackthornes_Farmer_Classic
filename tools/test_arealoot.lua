-- Area loot and locked slots in the kill tally.
--
-- What matters: with area loot only the corpse you opened is the kill and
-- gets the drops in its tally, but everything the window gives goes into the
-- session's loot, coin and value, once; and a slot the client shows locked (a
-- roll, or the master looter's) stays in the mob's tally but is left out of
-- what the session says you got.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("arealoot")

local ns = env.Load({ ui = true })
local Tracker = ns.Tracker
local TUI = ns.TrackerUI

-- Vendor prices: 10c a Wool Cloth, 5c a Linen Cloth, 50c a Large Fang.
local VENDOR = { [2592] = 10, [2589] = 5, [5637] = 50 }
_G.C_Item = { GetItemInfo = function(id)
    return "item", nil, 1, 1, 1, "", "", 1, "", "", VENDOR[id] or 0
end }

TUI:OnEnable()

local MOB = "Defias Bandit"
local WOOL = { name = "Wool Cloth", id = 2592 }
local LINEN = { name = "Linen Cloth", id = 2589 }
local FANG = { name = "Large Fang", id = 5637 }

local function Open(guid, loot, sources)
    env.world.target = { name = MOB, level = 15, dead = true, guid = guid }
    env.world.loot = loot
    _G.GetLootSourceInfo = sources and function(slot) return unpack(sources[slot] or {}) end or nil
    return Tracker:OnLoot()
end

local function Tally()
    return ns.db.tracker.mobs[MOB]
end

--------------------------------------------------------------------------------
-- One window, three corpses: A targeted, B and C pulled in
--------------------------------------------------------------------------------

local A, B, C = "Creature-0-1-2-3-100-A", "Creature-0-1-2-3-100-B", "Creature-0-1-2-3-100-C"
local window = {
    { name = WOOL.name, id = WOOL.id, quantity = 6 },
    { name = LINEN.name, id = LINEN.id, quantity = 1 },
    { name = "1 Silver", money = true },
}
local sources = {
    { A, 2, B, 3, C, 1 },      -- the wool: 2 off the corpse you opened
    { B, 1 },                  -- the linen is all B's
    { A, 25, B, 40, C, 35 },   -- the coin, in copper
}

suite.check("the corpse you opened is a kill", Open(A, window, sources) == true)
suite.check("one kill, not three", Tracker:SessionKills() == 1, Tracker:SessionKills())
suite.check("the tally takes only its own wool", Tally().qty[WOOL.name] == 2, Tally().qty[WOOL.name])
suite.check("and none of B's linen", Tally().items[LINEN.name] == nil)
suite.check("and only its own coin", Tracker:CoinPerKill(MOB) == 25, Tracker:CoinPerKill(MOB))

suite.check("the session has all six wool", Tracker.sessionLoot[WOOL.name] == 6,
    Tracker.sessionLoot[WOOL.name])
suite.check("and the linen", Tracker.sessionLoot[LINEN.name] == 1, Tracker.sessionLoot[LINEN.name])
suite.check("and the whole silver", Tracker.sessionCopper == 100, Tracker.sessionCopper)
suite.check("listed under the mob you opened", Tracker.sessionFrom[WOOL.name][MOB] == 6)
suite.check("another corpse's item gets its look too", Tracker:LookOf(LINEN.name).id == LINEN.id)
suite.check("so the value has all of it", ns.Value:Session() == 100 + 6 * 10 + 1 * 5, ns.Value:Session())

TUI:SetTab("loot")
local rows = {}
for _, line in ipairs(TUI.shown) do
    if line.item then rows[line.item] = line end
end
suite.check("the Loot tab says six wool", rows[WOOL.name] and rows[WOOL.name].count == 6,
    rows[WOOL.name] and rows[WOOL.name].count)
suite.check("and lists the linen", rows[LINEN.name] ~= nil)
TUI:SetTab("farm")

-- The same corpse opened again (something was left): nothing twice.
suite.check("coming back is not a kill", Open(A, window, sources) == false)
suite.check("the wool is not counted again", Tracker.sessionLoot[WOOL.name] == 6,
    Tracker.sessionLoot[WOOL.name])
suite.check("nor the coin", Tracker.sessionCopper == 100, Tracker.sessionCopper)

-- A window whose sources the client does not say: all of it is the kill's.
Open("Creature-0-1-2-3-100-D", { { name = WOOL.name, id = WOOL.id, quantity = 3 } }, nil)
suite.check("without sources the kill takes the whole slot", Tally().qty[WOOL.name] == 5,
    Tally().qty[WOOL.name])
suite.check("and the session counts it once", Tracker.sessionLoot[WOOL.name] == 9,
    Tracker.sessionLoot[WOOL.name])

-- An unreadable quantity on another corpse's slot still counts one.
Open("Creature-0-1-2-3-100-E",
    { { name = WOOL.name, id = WOOL.id, quantity = 1 }, { name = LINEN.name, id = LINEN.id, quantity = env.Secret("quantity") } },
    { { "Creature-0-1-2-3-100-E", 1 }, { "Creature-0-1-2-3-100-F", 2 } })
suite.check("an unreadable amount counts as one", Tracker.sessionLoot[LINEN.name] == 2,
    Tracker.sessionLoot[LINEN.name])

--------------------------------------------------------------------------------
-- Locked slots
--------------------------------------------------------------------------------

-- The client's sixth answer about a slot is whether it is locked.
local plainSlotInfo = _G.GetLootSlotInfo
_G.GetLootSlotInfo = function(slot)
    local item = env.world.loot[slot]
    if not item then return nil end
    return "Interface\\Icons\\INV_Misc_Dust_01", item.name, item.quantity or 1, nil, 2, item.locked
end

local woolBefore = Tracker.sessionLoot[WOOL.name]
Open("Creature-0-1-2-3-100-G", {
    { name = FANG.name, id = FANG.id, locked = true },
    { name = WOOL.name, id = WOOL.id, quantity = 2 },
}, nil)
suite.check("a locked drop is in the mob's tally", Tally().items[FANG.name] == 1, Tally().items[FANG.name])
suite.check("with its amount", Tally().qty[FANG.name] == 1)
suite.check("but not in the session's loot", Tracker.sessionLoot[FANG.name] == nil,
    Tracker.sessionLoot[FANG.name])
suite.check("the unlocked wool beside it counts", Tracker.sessionLoot[WOOL.name] == woolBefore + 2,
    Tracker.sessionLoot[WOOL.name])
suite.check("so the value leaves the fang out", ns.Value:Session()
    == 100 + Tracker.sessionLoot[WOOL.name] * 10 + Tracker.sessionLoot[LINEN.name] * 5,
    ns.Value:Session())

-- Locked on another corpse in an area loot: not yours either.
Open("Creature-0-1-2-3-100-H", {
    { name = WOOL.name, id = WOOL.id, quantity = 1 },
    { name = FANG.name, id = FANG.id, locked = true },
}, { { "Creature-0-1-2-3-100-H", 1 }, { "Creature-0-1-2-3-100-I", 1 } })
suite.check("another corpse's locked drop stays out", Tracker.sessionLoot[FANG.name] == nil,
    Tracker.sessionLoot[FANG.name])

-- A locked answer the client will not let us read counts as not locked.
local fangsBefore = Tally().items[FANG.name]
local ok = pcall(Open, "Creature-0-1-2-3-100-J", { { name = FANG.name, id = FANG.id, locked = env.Secret("locked") } }, nil)
suite.check("an unreadable lock does not stop the kill", ok and Tally().items[FANG.name] == fangsBefore + 1)
suite.check("and counts as yours", Tracker.sessionLoot[FANG.name] == 1, Tracker.sessionLoot[FANG.name])

-- Fishing and gathering read the window through the same function.
env.world.loot = { { name = "Raw Brilliant Smallfish", quantity = 2, locked = true } }
local names, quantities = Tracker:LootedItems(true)
suite.check("any-source reads keep every slot", names[1] == "Raw Brilliant Smallfish"
    and quantities["Raw Brilliant Smallfish"] == 2)

_G.GetLootSlotInfo = plainSlotInfo
_G.GetLootSourceInfo = nil
_G.C_Item = nil

suite.done()
