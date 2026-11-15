-- Loot beacons: a beam over the body you can loot.
--
-- What matters: off until ticked; a dead creature the interact key picks
-- gets the beam while it still has loot (the game's answer, else not opened
-- yet); a live one, a looted one or a hidden one gets nothing; once looted
-- the skinnable sparkle takes over; colour, height and width follow their
-- settings; it works with sparkles off and keeps the game's settings on;
-- the command and the Settings rows set the same keys.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("lootbeacon")

local ns = env.Load({ ui = true })
local NodeSparkle = ns.NodeSparkle

local cvars = { SoftTargetInteract = "1", SoftTargetNameplateInteract = "0", SoftTargetInteractRange = "10", SoftTargetInteractArc = "0",
    SoftTargetIconGameObject = "0", SoftTargetIconInteract = "0" }
_G.C_CVar = {
    GetCVar = function(name) return cvars[name] end,
    SetCVar = function(name, value) cvars[name] = tostring(value); return true end,
}
_G.InCombatLockdown = function() return false end

local facing = {}
local plate = CreateFrame("Frame")
local realName, realGuid = _G.UnitName, _G.UnitGUID
_G.UnitName = function(unit)
    if unit == "softinteract" then return facing.name end
    return realName(unit)
end
_G.UnitGUID = function(unit)
    if unit == "softinteract" then return facing.guid end
    return realGuid(unit)
end
_G.C_NamePlate = {
    GetNamePlateForUnit = function(unit)
        if unit == "softinteract" and facing.guid then return plate end
        return nil
    end,
}
local dead = true
_G.UnitIsDead = function(unit) if unit == "softinteract" then return dead end return false end
_G.UnitLevel = function() return 12 end
local canLoot = nil   -- nil: the client has no answer
_G.CanLootUnit = function() return canLoot end

local function Face(name, guid)
    facing = { name = name, guid = guid }
    return NodeSparkle:SafeRefresh()
end

local BOAR = "Creature-0-1-2-3-3099-0000000002"
local WOLF = "Creature-0-1-2-3-3100-0000000003"

suite.check("off by default", ns.db.lootBeacon ~= true and not NodeSparkle:LootOn())
suite.check("a body gets nothing while it is off", Face("Dire Mottled Boar", BOAR) == "nothing")

ns.HandleSlash("lootbeacon on")
suite.check("on is saved", ns.db.lootBeacon == true)
canLoot = true
suite.check("a body you can loot gets the beam", Face("Dire Mottled Boar", BOAR) == "shown")
suite.check("it is the loot beam", NodeSparkle.shownLoot == true)
suite.check("in gold", NodeSparkle.tint == NodeSparkle.LOOT_COLORS.gold)
suite.check("its plate stays on", NodeSparkle:FitPlateToTarget() == "1")
canLoot = false
suite.check("one the game says is empty does not", Face("Dire Mottled Boar", BOAR) == "nothing")
dead = false
canLoot = true
suite.check("a live one does not", Face("Dire Mottled Boar", BOAR) == "nothing")
dead = true

-- Without the game's answer: not opened yet means loot.
canLoot = nil
suite.check("without the game's answer, an unopened body counts", Face("Plainstrider", WOLF) == "shown")
ns.Harvest.opened[WOLF] = { 1 }
suite.check("and once opened it goes", Face("Plainstrider", WOLF) == "nothing")
ns.Harvest.opened[WOLF] = nil

ns.DB:Hide("source", "Plainstrider")
suite.check("a hidden mob gets nothing", Face("Plainstrider", WOLF) == "nothing")
ns.DB:Unhide("source", "Plainstrider")

suite.check("an object is not a body", Face("Copper Vein", "GameObject-0-1-2-3-1731-0000ABCDEF") ~= "shown"
    or NodeSparkle.shownLoot ~= true)

-- Looted, the skinnable sparkle takes over.
local realSkills = ns.Spots.Skills
ns.Spots.Skills = function() return { Skinning = 30 } end
local realTips = _G.C_TooltipInfo
_G.C_TooltipInfo = { GetUnit = function() return { lines = { { leftText = "Dire Mottled Boar" }, { leftText = "Skinnable" } } } end }
ns.db.nodeSparkleCorpses = true
canLoot = true
Face("Dire Mottled Boar", BOAR)
suite.check("the loot beam wins while it has loot", NodeSparkle.shownLoot == true)
canLoot = false
suite.check("looted, the skinnable sparkle shows", Face("Dire Mottled Boar", BOAR) == "shown"
    and NodeSparkle.shownLoot ~= true)
ns.db.nodeSparkleCorpses = false
_G.C_TooltipInfo = realTips
ns.Spots.Skills = realSkills

-- Colour and size.
canLoot = true
ns.HandleSlash("lootbeacon color purple")
suite.check("color is saved", ns.db.lootBeaconColor == "purple")
Face("Plainstrider", WOLF)
suite.check("and shows", NodeSparkle.tint == NodeSparkle.LOOT_COLORS.purple)
ns.HandleSlash("lootbeacon color pink")
suite.check("a colour we don't have changes nothing", ns.db.lootBeaconColor == "purple")
ns.HandleSlash("lootbeacon color gold")
suite.check("gold saves as nothing", ns.db.lootBeaconColor == nil)
ns.HandleSlash("lootbeacon height 150")
ns.HandleSlash("lootbeacon width 75%")
suite.check("height and width are saved", ns.db.lootBeaconHeight == 150 and ns.db.lootBeaconWidth == 75)
Face("Dire Mottled Boar", BOAR)
suite.check("the beam takes the size", NodeSparkle.beacon.size == "75:150")
ns.HandleSlash("lootbeacon height 999")
suite.check("too tall is held at 200", ns.db.lootBeaconHeight == 200)
ns.HandleSlash("lootbeacon height 100")
suite.check("100 saves as nothing", ns.db.lootBeaconHeight == nil)
suite.check("sizes keep to steps", NodeSparkle.LootSize(110) == 100 and NodeSparkle.LootSize(10) == 50)
suite.check("colours have names", NodeSparkle.LootColorLabel("red") == "Red"
    and NodeSparkle.LootColorLabel("nope") == "Gold")

-- Sparkles off, loot beacons still work and keep the game's settings.
ns.HandleSlash("sparkle off")
suite.check("sparkles off keeps the settings on for loot beacons", cvars.SoftTargetInteract == "3")
suite.check("a body still gets the beam", Face("Dire Mottled Boar", BOAR) == "shown")
suite.check("a vein does not", Face("Copper Vein", "GameObject-0-1-2-3-1731-0000ABCDEF") == "off")
ns.HandleSlash("lootbeacon off")
suite.check("off is saved", ns.db.lootBeacon == false)
suite.check("with both off the settings go back", cvars.SoftTargetInteract == "1")
suite.check("and nothing shows", Face("Dire Mottled Boar", BOAR) == "off")
ns.HandleSlash("sparkle on")

-- Settings rows.
ns.SettingsUI:Show()
local controls = ns.SettingsUI.controls
suite.check("the Settings rows are there", controls.lootBeacon and controls.lootBeaconColor
    and controls.lootBeaconHeight and controls.lootBeaconWidth)
ns.HandleSlash("lootbeacon on")
ns.HandleSlash("lootbeacon color blue")
ns.SettingsUI:Refresh()
suite.check("the tick box follows", controls.lootBeacon:GetChecked() == true)
suite.check("the colour follows", controls.lootBeaconColor:GetValue() == 4)
controls.lootBeaconColor:Pick(6)
suite.check("picking red saves it", ns.db.lootBeaconColor == "red")

ns.HandleSlash("sparkle check")
local found = false
for _, line in ipairs(ns.db.lastProbe and ns.db.lastProbe.lines or {}) do
    if line:find("loot beacon") then found = true end
end
suite.check("the check has a loot beacon line", found)

ns.SettingsUI:Hide()

suite.done()
