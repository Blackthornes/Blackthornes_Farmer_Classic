-- Skinning in the kill tally.
--
-- What matters: a corpse you skin after looting it is still one kill, and
-- what the skinning gives is counted even when the corpse already gave some
-- of the same item; a corpse you only skin (someone else's kill) is no kill
-- and changes no drop rate, but its leather is in the session's loot; and
-- without Gathering's skinning check every window counts as it always did.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("skinning")

local ns = env.Load({ ui = true })
local Tracker = ns.Tracker
local TUI = ns.TrackerUI

_G.C_Item = { GetItemInfo = function() return "item", nil, 1, 1, 1, "", "", 1, "", "", 0 end }
local now = 1000
_G.GetTime = function() return now end

TUI:OnEnable()

-- Gathering's answer, while the window is from your own Skinning cast.
local skinningNow = false
local realIsSkinning = rawget(ns.Gathering, "IsSkinning")
ns.Gathering.IsSkinning = function() return skinningNow end

local function Open(mob, guid, loot, skinning)
    skinningNow = skinning and true or false
    env.world.target = { name = mob, level = 8, dead = true, guid = guid }
    env.world.loot = loot
    local result = Tracker:OnLoot()
    skinningNow = false
    now = now + 5
    return result
end

local function Item(name, n) return { name = name, quantity = n or 1 } end

local WOLF = "Mangy Wolf"
local COIN = { name = "40 Copper", money = true }

--------------------------------------------------------------------------------
-- Yours and theirs
--------------------------------------------------------------------------------

local function Unlocks()
    local count = 0
    for _, line in ipairs(env.chat) do
        if line:find("Drop rates unlocked", 1, true) then count = count + 1 end
    end
    return count
end

-- Twenty wolves of yours, looted then skinned, and twenty more that someone
-- else killed and looted and you only skinned.
for index = 1, 40 do
    local guid = "Creature-0-1-2-3-200-" .. index
    if index % 2 == 1 then
        local loot = { COIN }
        if index % 4 == 1 then loot[2] = Item("Wolf Fang") end
        Open(WOLF, guid, loot, false)
        Open(WOLF, guid, { Item("Light Leather") }, true)
    else
        Open(WOLF, guid, { Item("Light Leather") }, true)
    end
    if index == 38 then
        suite.check("nineteen real kills unlock nothing", Unlocks() == 0, Unlocks())
    end
end
suite.check("rates unlock at the twentieth real kill", Unlocks() == 1, Unlocks())

local summary = Tracker:Summary(WOLF)
local fang, leather
for _, item in ipairs(summary.items) do
    if item.name == "Wolf Fang" then fang = item end
    if item.name == "Light Leather" then leather = item end
end
suite.check("only the corpses you looted are kills", summary.kills == 20, summary.kills)
suite.check("so a fang on half of them is 50%", fang and Tracker.FormatChance(fang.chance) == "50%",
    fang and Tracker.FormatChance(fang.chance))
suite.check("and coin per kill is what a kill drops", Tracker:CoinPerKill(WOLF) == 40, Tracker:CoinPerKill(WOLF))
suite.check("your own leather is still the wolf's drop", leather and leather.corpses == 20,
    leather and leather.corpses)
suite.check("every skin is in the session's loot", Tracker.sessionLoot["Light Leather"] == 40,
    Tracker.sessionLoot["Light Leather"])
suite.check("under the wolf", Tracker.sessionFrom["Light Leather"][WOLF] == 40)

-- A skin-only window adds nothing to the kill count, the streak or the tally.
local streak, kills, qty = Tracker.streak, Tracker:SessionKills(), ns.db.tracker.mobs[WOLF].qty["Light Leather"]
suite.check("only skinning returns no kill", Open(WOLF, "Creature-0-1-2-3-200-99", { Item("Light Leather", 2) }, true) == false)
suite.check("the session's kills stay", Tracker:SessionKills() == kills, Tracker:SessionKills())
suite.check("the streak stays", Tracker.streak == streak, Tracker.streak)
suite.check("the tally's amounts stay", ns.db.tracker.mobs[WOLF].qty["Light Leather"] == qty)
suite.check("the two skins are yours", Tracker.sessionLoot["Light Leather"] == 42,
    Tracker.sessionLoot["Light Leather"])

-- A mob you never killed: no card, but its leather is on the Loot tab.
Open("Plainstrider", "Creature-0-1-2-3-201-1", { Item("Ruined Leather Scraps", 3) }, true)
suite.check("a mob you only skinned has no tally", ns.db.tracker.mobs["Plainstrider"] == nil)
TUI:SetTab("loot")
local scrapsRow
for _, line in ipairs(TUI.shown) do
    if line.item == "Ruined Leather Scraps" then scrapsRow = line end
end
suite.check("its leather is on the Loot tab", scrapsRow and scrapsRow.count == 3, scrapsRow and scrapsRow.count)
suite.check("from the mob you skinned", scrapsRow and scrapsRow.sub == "Plainstrider 3", scrapsRow and scrapsRow.sub)
TUI:SetTab("farm")

-- Without a guid (an instance can refuse it) a skinning window is still no kill.
kills = Tracker:SessionKills()
Open(WOLF, nil, { Item("Light Leather") }, true)
suite.check("no guid, skinning is still no kill", Tracker:SessionKills() == kills, Tracker:SessionKills())

--------------------------------------------------------------------------------
-- The same item looted and then skinned
--------------------------------------------------------------------------------

local BOAR = "Mottled Boar"
local guid = "Creature-0-1-2-3-202-1"
local scrapsBefore = Tracker.sessionLoot["Ruined Leather Scraps"] or 0
Open(BOAR, guid, { Item("Ruined Leather Scraps", 1) }, false)
Open(BOAR, guid, { Item("Ruined Leather Scraps", 2) }, true)
local boar = ns.db.tracker.mobs[BOAR]
suite.check("looted then skinned is one kill", boar.kills == 1, boar.kills)
suite.check("one corpse held scraps", boar.items["Ruined Leather Scraps"] == 1, boar.items["Ruined Leather Scraps"])
suite.check("three scraps came off it", boar.qty["Ruined Leather Scraps"] == 3, boar.qty["Ruined Leather Scraps"])
suite.check("and the session has all three", Tracker.sessionLoot["Ruined Leather Scraps"] == scrapsBefore + 3,
    Tracker.sessionLoot["Ruined Leather Scraps"])
suite.check("so a corpse that held them gave three", Tracker:StackSize(BOAR, "Ruined Leather Scraps") == 3)

-- Coming back for what was left is still not counted twice.
Open(BOAR, guid, { Item("Ruined Leather Scraps", 2) }, false)
suite.check("leftovers seen again add nothing", boar.qty["Ruined Leather Scraps"] == 3,
    boar.qty["Ruined Leather Scraps"])

--------------------------------------------------------------------------------
-- Your own kill that dropped nothing
--
-- 2026-10-05: a Savannah Huntress killed and skinned never showed on the Farm
-- tab. Her corpse held nothing, so no window opened until the skin.
--------------------------------------------------------------------------------

local HUNTRESS = "Savannah Huntress"
local tapDenied = false
_G.UnitIsTapDenied = function(unit) return unit == "target" and tapDenied end

--- Targeted alive first, as a fight does.
local function Fought(guid)
    env.world.target = { name = HUNTRESS, level = 8, dead = false, guid = guid }
    ns.Harvest:NoteUnit("target")
end

-- One looted before a /reload looks unopened to this session, and the
-- client still calls it yours; never seen alive, skinning it is no kill.
kills = Tracker:SessionKills()
suite.check("your corpse from before a /reload, skinned, is no kill",
    Open(HUNTRESS, "Creature-0-1-2-3-300-0", { Item("Light Leather") }, true) == false
    and Tracker:SessionKills() == kills)

-- The harvest reads the same window first (its loot reader is earlier in
-- the TOC) and counts the same corpses.
local Harvest = ns.Harvest
local wasEnabled = Harvest.enabled
Harvest.enabled = true
local function Harvested(guid)
    skinningNow = true
    env.world.target = { name = HUNTRESS, level = 8, dead = true, guid = guid }
    env.world.loot = { Item("Light Leather") }
    Harvest:RecordCorpse()
    skinningNow = false
end

local corpsesBefore = Harvest:CountCorpses()
Harvested("Creature-0-1-2-3-300-0")
suite.check("nor a corpse the harvest records", Harvest:CountCorpses() == corpsesBefore)

Fought("Creature-0-1-2-3-300-1")
Harvested("Creature-0-1-2-3-300-1")
suite.check("your empty kill, skinned, is a corpse the harvest records, so its rates count it",
    Harvest:CountCorpses() == corpsesBefore + 1, Harvest:CountCorpses() .. " from " .. corpsesBefore)
Harvest.enabled = wasEnabled

suite.check("your empty kill, skinned, is a kill",
    Open(HUNTRESS, "Creature-0-1-2-3-300-1", { Item("Light Leather") }, true) == true)
suite.check("one more kill this session", Tracker:SessionKills() == kills + 1, Tracker:SessionKills())
suite.check("and the leather is her drop", ns.db.tracker.mobs[HUNTRESS].items["Light Leather"] == 1)
suite.check("skinning it again adds no kill",
    Open(HUNTRESS, "Creature-0-1-2-3-300-1", { Item("Light Leather") }, true) == false
    and Tracker:SessionKills() == kills + 1)

tapDenied = true
Fought("Creature-0-1-2-3-300-2")
suite.check("someone else's kill, skinned, is still no kill",
    Open(HUNTRESS, "Creature-0-1-2-3-300-2", { Item("Light Leather") }, true) == false)
tapDenied = false

-- Area loot took this one's drops with another corpse's: skinning it is no kill.
local A, B = "Creature-0-1-2-3-300-A", "Creature-0-1-2-3-300-B"
_G.GetLootSourceInfo = function(slot) if slot == 1 then return A, 1, B, 1 end end
Open(HUNTRESS, A, { Item("Ruined Leather Scraps", 2) })
_G.GetLootSourceInfo = nil
kills = Tracker:SessionKills()
Fought(B)
suite.check("a corpse an area loot emptied, skinned, is no kill",
    Open(HUNTRESS, B, { Item("Light Leather") }, true) == false and Tracker:SessionKills() == kills)
_G.UnitIsTapDenied = nil

--------------------------------------------------------------------------------
-- Without the skinning check
--------------------------------------------------------------------------------

ns.Gathering.IsSkinning = nil
kills = Tracker:SessionKills()
Open(WOLF, "Creature-0-1-2-3-200-100", { Item("Light Leather") }, true)
suite.check("without it, a window is a kill as before", Tracker:SessionKills() == kills + 1,
    Tracker:SessionKills())

ns.Gathering.IsSkinning = realIsSkinning
_G.GetTime = nil
_G.C_Item = nil

suite.done()
