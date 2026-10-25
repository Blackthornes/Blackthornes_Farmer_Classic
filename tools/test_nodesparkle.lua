-- Sparkles on the herb or ore node you face.
--
-- What matters: a herb or vein the interact key points at sparkles, over the
-- game's nameplate for it; a mob, a chest, a hidden node or no nameplate
-- gets nothing; turning it on sets the game's two settings only where they
-- were lower, keeping the old values, and turning it off puts them back; in
-- a fight the settings wait; a secret guid costs nothing worse than the
-- sparkle; /farm sparkle and the Settings box turn it off and on.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("nodesparkle")

local ns = env.Load({ ui = true })
local NodeSparkle = ns.NodeSparkle

-- The game's settings.
local cvars = { SoftTargetInteract = "1", SoftTargetNameplateInteract = "0", SoftTargetInteractRange = "10", SoftTargetInteractArc = "0",
    SoftTargetIconGameObject = "0", SoftTargetIconInteract = "0" }
local sets = 0
_G.C_CVar = {
    GetCVar = function(name) return cvars[name] end,
    SetCVar = function(name, value) cvars[name] = tostring(value); sets = sets + 1; return true end,
}
local fighting = false
_G.InCombatLockdown = function() return fighting end

-- What the interact key points at, and its nameplate.
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
local plateShown = true
_G.C_NamePlate = {
    GetNamePlateForUnit = function(unit)
        if unit == "softinteract" and facing.guid and plateShown then return plate end
        return nil
    end,
}

local function Face(name, guid)
    facing = { name = name, guid = guid }
    return NodeSparkle:SafeRefresh()
end

local VEIN = "GameObject-0-1-2-3-1731-0000ABCDEF"

suite.check("on by default", ns.DEFAULTS.nodeSparkle == true)

suite.check("a copper vein sparkles", Face("Copper Vein", VEIN) == "shown")
suite.check("the sparkle shows", NodeSparkle.frame and NodeSparkle.frame:IsShown())
suite.check("a herb the data knows sparkles", Face("Peacebloom", VEIN) == "shown")
suite.check("any case", Face("peacebloom", VEIN) == "shown")
suite.check("a mob does not", Face("Kobold Vermin", "Creature-0-1-2-3-6-0000000001") == "nothing")
suite.check("and the sparkle goes", not NodeSparkle.frame:IsShown())
suite.check("a chest sparkles", Face("Battered Chest", VEIN) == "shown")
suite.check("a fishing school sparkles", Face("Oily Blackmouth School", VEIN) == "shown")
suite.check("your fishing bobber does", Face("Fishing Bobber", VEIN) == "shown")
suite.check("a mailbox does not", Face("Mailbox", VEIN) == "notnode")
_G.C_QuestLog = {
    GetNumQuestLogEntries = function() return 2 end,
    GetInfo = function(i) if i == 1 then return { isHeader = true } end return { questID = 77 } end,
    GetQuestObjectives = function() return { { text = "Venture Co. Documents: 0/1", finished = false } } end,
}
NodeSparkle:QuestLogChanged()
suite.check("an object a quest wants sparkles", Face("Venture Co. Documents", VEIN) == "shown")
_G.C_QuestLog.GetQuestObjectives = function() return { { text = "Venture Co. Documents: 1/1", finished = true } } end
NodeSparkle:QuestLogChanged()
suite.check("not once that objective is done", Face("Venture Co. Documents", VEIN) == "notnode")
-- A quest pickup named something other than its objective: the game's
-- tooltip for it carries the objective's count.
_G.C_QuestLog.GetQuestObjectives = function() return { { text = "9/15 Windstone Cluster", finished = false } } end
NodeSparkle:QuestLogChanged()
suite.check("a pickup named apart from its objective gets nothing without a tooltip", Face("Shiny Windstone", VEIN) == "notnode")
local tipLines
_G.C_TooltipInfo = { GetUnit = function(unit)
    if unit == "softinteract" and tipLines then return { lines = tipLines } end
    return nil
end }
tipLines = { { leftText = "Shiny Windstone" }, { leftText = "Harvesting Windstones" }, { leftText = " - 9/15 Windstone Cluster" } }
suite.check("its tooltip's objective count makes it sparkle", Face("Shiny Windstone", VEIN) == "shown")
tipLines = { { leftText = "Shiny Windstone" }, { leftText = "Windstone Cluster" } }
suite.check("so does an objective named on its tooltip", Face("Shiny Windstone", VEIN) == "shown")
tipLines = { { leftText = "Shiny Windstone" }, { leftText = "15/15 Windstone Cluster" } }
suite.check("not a finished count", Face("Shiny Windstone", VEIN) == "notnode")
tipLines = nil
_G.C_TooltipInfo = nil

-- One looted before (and kept as a gather) that gave the objective's item.
ns.db.gathering = ns.db.gathering or {}
ns.db.gathering.nodes = ns.db.gathering.nodes or {}
ns.db.gathering.nodes["Zephras Isle|Thendal|Shiny Windstone"] = { node = "Shiny Windstone", kind = "quest",
    gathers = 1, items = { ["Windstone Cluster"] = { gathers = 1, count = 1 } } }
suite.check("an object that gave the objective's item before sparkles", Face("Shiny Windstone", VEIN) == "shown")
_G.C_QuestLog.GetQuestObjectives = function() return { { text = "15/15 Windstone Cluster", finished = true } } end
NodeSparkle:QuestLogChanged()
suite.check("not once that objective is done either", Face("Shiny Windstone", VEIN) == "notnode")
_G.C_QuestLog = nil
suite.check("facing nothing", Face(nil, nil) == "nothing")

-- A node the player gathered that the data does not know (say, Forever's).
ns.db.gathering = ns.db.gathering or {}
ns.db.gathering.nodes = ns.db.gathering.nodes or {}
ns.db.gathering.nodes["Elwynn Forest||Silberblatt"] = { node = "Silberblatt", kind = "herb", gathers = 3, items = {} }
suite.check("a node you gathered sparkles, in the client's language", Face("Silberblatt", VEIN) == "shown")

-- With the game's icon on the nameplate, the sparkles gather round it.
local icon = CreateFrame("Frame")
icon.GetObjectType = function() return "Frame" end
plate.UnitFrame = { SoftTargetFrame = icon }
NodeSparkle:HideSparkle()
suite.check("round the game's icon", Face("Copper Vein", VEIN) == "shown" and NodeSparkle.Icon(plate) == icon)
suite.check("down on the node, under the icon", NodeSparkle:Drop(plate) == NodeSparkle.DROP)
plate.GetEffectiveScale = function() return 0.5 end
suite.check("less far down for a plate drawn smaller", NodeSparkle:Drop(plate) < NodeSparkle.DROP)
plate.GetEffectiveScale = nil
plate.UnitFrame = nil
suite.check("no icon to read, still a sparkle", NodeSparkle.Icon(plate) == nil)

plateShown = false
-- Era makes no nameplate for objects: the marker stands on screen instead,
-- with the node's name under it.
suite.check("no nameplate, a marker on screen", Face("Copper Vein", VEIN) == "screen")
suite.check("the marker shows", NodeSparkle.frame:IsShown())
suite.check("with the node's name", NodeSparkle.nameText:IsShown() and NodeSparkle.nameText:GetText() == "Copper Vein")
NodeSparkle:SetStyle("sparkles")
suite.check("a new look keeps the name", NodeSparkle.nameText:IsShown() and NodeSparkle.nameText:GetText() == "Copper Vein")
NodeSparkle:SetStyle("beacon")
suite.check("no beam on screen", not NodeSparkle.beacon.holder:IsShown() and not NodeSparkle.sparks[1].holder:IsShown())
suite.check("no spot known, no arrow", not (NodeSparkle.pointer and NodeSparkle.pointer.frame:IsShown()))

-- A spot you gathered it at before: the arrow by your feet points there.
local realPosition, realSize, realSpots, realFacing = ns.Harvest.PlayerMapPosition, ns.Gathering.MapSize, ns.Gathering.SpotsOn, ns.Arrow.Facing
local here = { x = 0.5, y = 0.5 }
local turnTo = 0
ns.Harvest.PlayerMapPosition = function() return 1429, here.x, here.y end
ns.Gathering.MapSize = function() return 1000, 1000 end
local spots = { { map = 1429, x = 0.49, y = 0.5, node = "Copper Vein" } }   -- 10 yards west
ns.Gathering.SpotsOn = function() return spots end
ns.Arrow.Facing = function() return turnTo end
suite.check("a known spot: the marker on screen", Face("Copper Vein", VEIN) == "screen")
suite.check("the arrow shows", NodeSparkle.pointer and NodeSparkle.pointer.frame:IsShown())
suite.check("facing north, it turns left toward the west", math.abs(NodeSparkle:PointerTurn("Copper Vein") - math.pi / 2) < 1e-6)
turnTo = math.pi / 2
suite.check("facing west, it points straight ahead", math.abs(NodeSparkle:PointerTurn("Copper Vein")) < 1e-6)
suite.check("a dotted trail with it", #NodeSparkle.pointer.pieces == 1 + #NodeSparkle.TRAIL)
suite.check("in the node's colour", NodeSparkle.pointer.pieces[1].texture)
spots[1].x = 0.4   -- 100 yards off: too far to be the one you face
suite.check("too far, no arrow", not NodeSparkle:AimPointer())
spots[1].x, spots[1].node, spots[1].also = 0.49, "Tin Vein", { ["Copper Vein"] = true }
suite.check("a vein that grew on that spot counts", NodeSparkle:AimPointer())
here.x = 0.4901
suite.check("standing on it, no arrow", not NodeSparkle:AimPointer())
here.x = 0.5
plateShown = true
suite.check("a nameplate: no arrow", Face("Copper Vein", VEIN) == "shown" and not NodeSparkle.pointer.frame:IsShown())
plateShown = false
Face("Copper Vein", VEIN)
suite.check("the arrow goes with the marker", NodeSparkle.pointer.frame:IsShown() and Face(nil, nil) == "nothing"
    and not NodeSparkle.pointer.frame:IsShown())
ns.Harvest.PlayerMapPosition, ns.Gathering.MapSize, ns.Gathering.SpotsOn, ns.Arrow.Facing = realPosition, realSize, realSpots, realFacing
NodeSparkle.fishing = true
suite.check("the bobber on screen gets nothing", Face("Fishing Bobber", VEIN) == "nothing" and not NodeSparkle.frame:IsShown())
NodeSparkle.fishing = nil
suite.check("a mob on screen gets nothing", Face("Kobold Vermin", "Creature-0-1-2-3-6-0000000001") == "nothing"
    and not NodeSparkle.frame:IsShown())
plateShown = true
suite.check("a nameplate again: no name under it", Face("Copper Vein", VEIN) == "shown" and not NodeSparkle.nameText:IsShown())
plateShown = true

ns.DB:Hide("source", "Copper Vein")
suite.check("a hidden node does not", Face("Copper Vein", VEIN) == "notnode")
ns.DB:Unhide("source", "Copper Vein")

suite.check("a secret guid costs nothing worse", Face("Copper Vein", env.Secret("string")) == "nothing")

-- The game's settings.
NodeSparkle:SetEnabled(true)
suite.check("turns on the interact target", cvars.SoftTargetInteract == "3", cvars.SoftTargetInteract)
suite.check("and its nameplate", cvars.SoftTargetNameplateInteract == "1")
suite.check("looks farther", cvars.SoftTargetInteractRange == "15")
suite.check("and all the way round", cvars.SoftTargetInteractArc == "2")
suite.check("turns on the game's icon over objects", cvars.SoftTargetIconGameObject == "1" and cvars.SoftTargetIconInteract == "1")
suite.check("keeping what they were", ns.db.nodeSparkleCVars.SoftTargetInteract == "1"
    and ns.db.nodeSparkleCVars.SoftTargetNameplateInteract == "0")

local before = sets
NodeSparkle:ApplySettings()
suite.check("nothing set twice", sets == before)

cvars.SoftTargetInteractRange = "100"
NodeSparkle:ApplySettings()
suite.check("a reach Farmer set to 100 comes back down", cvars.SoftTargetInteractRange == "15")
suite.check("still keeping the player's own", ns.db.nodeSparkleCVars.SoftTargetInteractRange == "10")

NodeSparkle:SetEnabled(false)
suite.check("off puts them back", cvars.SoftTargetInteract == "1" and cvars.SoftTargetNameplateInteract == "0"
    and cvars.SoftTargetInteractRange == "10" and cvars.SoftTargetInteractArc == "0"
    and cvars.SoftTargetIconGameObject == "0" and cvars.SoftTargetIconInteract == "0")
suite.check("and forgets them", next(ns.db.nodeSparkleCVars) == nil)
suite.check("off shows nothing", Face("Copper Vein", VEIN) == "off")

cvars.SoftTargetInteract = "3"
NodeSparkle:SetEnabled(true)
suite.check("a setting already on is left alone", ns.db.nodeSparkleCVars.SoftTargetInteract == nil)
NodeSparkle:SetEnabled(false)
suite.check("and stays on after", cvars.SoftTargetInteract == "3")
cvars.SoftTargetInteract = "1"

fighting = true
NodeSparkle:SetEnabled(true)
suite.check("in a fight nothing is set", cvars.SoftTargetInteract == "1")
fighting = false
NodeSparkle:ApplySettings()
suite.check("after the fight it is", cvars.SoftTargetInteract == "3")

-- The command and the Settings box.
ns.HandleSlash("sparkle")
suite.check("/farm sparkle turns it off", ns.db.nodeSparkle == false)
suite.check("and puts the settings back", cvars.SoftTargetInteract == "1")
ns.HandleSlash("sparkle on")
suite.check("/farm sparkle on turns it on", ns.db.nodeSparkle == true)

ns.SettingsUI:Show()
local box = ns.SettingsUI.controls.nodeSparkle
suite.check("the settings page shows it on", box:GetChecked())
box:GetScript("OnClick")(box)
suite.check("unticking it turns it off", ns.db.nodeSparkle == false)
box:GetScript("OnClick")(box)
suite.check("and ticking it back on", ns.db.nodeSparkle == true)

suite.check("a beacon unless sparkles are picked", NodeSparkle:Style() == "beacon")
ns.db.nodeSparkleStyle, ns.db.nodeSparkleStylePicked = "sparkles", nil
suite.check("the first default's sparkles become the beacon", NodeSparkle:Style() == "beacon")
ns.HandleSlash("sparkle sparkles")
suite.check("sparkles picked stay sparkles", NodeSparkle:Style() == "sparkles")
Face("Copper Vein", VEIN)
ns.HandleSlash("sparkle beacon")
suite.check("/farm sparkle beacon picks the beacon", ns.db.nodeSparkleStyle == "beacon")
suite.check("the beacon shows", NodeSparkle.beacon.holder:IsShown())
suite.check("and the sparkles go", not NodeSparkle.sparks[1].holder:IsShown())
ns.SettingsUI:Show()
suite.check("the settings page shows the beacon", ns.SettingsUI.controls.sparkleStyle:GetValue() == 2)
ns.SettingsUI.controls.sparkleStyle:SetValue(1)
suite.check("stepping back to sparkles", ns.db.nodeSparkleStyle == "sparkles"
    and NodeSparkle.sparks[1].holder:IsShown() and not NodeSparkle.beacon.holder:IsShown())

-- The game's icon, out of sight without a controller.
local gameIcon = CreateFrame("Frame")
gameIcon.GetObjectType = function() return "Frame" end
local iconAlpha = 0.8
gameIcon.GetAlpha = function() return iconAlpha end
gameIcon.SetAlpha = function(_, a) iconAlpha = a end
plate.UnitFrame = { SoftTargetFrame = gameIcon }
ns.HandleSlash("sparkle on")
suite.check("hidden by default", ns.DEFAULTS.nodeSparkleHideIcon == true)
Face("Copper Vein", VEIN)
suite.check("no controller: the game's icon goes see-through", iconAlpha == 0)
Face("Mailbox", VEIN)
suite.check("on anything the interact key picks", iconAlpha == 0)
cvars.GamePadEnable = "1"
Face("Copper Vein", VEIN)
suite.check("a controller brings it back as it was", iconAlpha == 0.8)
cvars.GamePadEnable = "0"
_G.C_GamePad = { IsEnabled = function() return true end }
Face("Copper Vein", VEIN)
suite.check("a controller the game reports does too", iconAlpha == 0.8)
_G.C_GamePad = nil
Face("Copper Vein", VEIN)
suite.check("hidden again without it", iconAlpha == 0)
fighting = true
iconAlpha = 0.5
Face("Copper Vein", VEIN)
suite.check("nothing touched in a fight", iconAlpha == 0.5)
fighting = false
Face("Copper Vein", VEIN)
ns.HandleSlash("sparkle icon")
suite.check("/farm sparkle icon shows it", ns.db.nodeSparkleHideIcon == false and iconAlpha == 0.8)
ns.HandleSlash("sparkle icon hide")
suite.check("/farm sparkle icon hide hides it", ns.db.nodeSparkleHideIcon == true and iconAlpha == 0)
ns.SettingsUI:Show()
local iconBox = ns.SettingsUI.controls.nodeSparkleHideIcon
suite.check("the settings box shows it ticked", iconBox:GetChecked())
iconBox:GetScript("OnClick")(iconBox)
suite.check("unticking shows the icon", ns.db.nodeSparkleHideIcon == false and iconAlpha == 0.8)
iconBox:GetScript("OnClick")(iconBox)
ns.NodeSparkle:SetEnabled(false)
suite.check("turning sparkles off gives the icon back", iconAlpha == 0.8)
ns.NodeSparkle:SetEnabled(true)
local keep = ns.db.nodeSparkleCVars
ns.db.nodeSparkleCVars = {}
Face("Copper Vein", VEIN)
suite.check("an icon the player turned on themselves is left alone", iconAlpha == 0.8)
ns.db.nodeSparkleCVars = keep

-- The plate's name, bars and level, which the game draws over every NPC and
-- object the interact key picks once Farmer turns those plates on.
local function Piece(start)
    local piece = { alpha = start }
    piece.GetAlpha = function(self) return self.alpha end
    piece.SetAlpha = function(self, a) self.alpha = a end
    return piece
end
local nameText, healthBar = Piece(1), Piece(0.9)
plate.UnitFrame = {
    SoftTargetFrame = gameIcon,
    name = nameText,
    GetRegions = function() return nameText end,
    GetChildren = function() return healthBar, gameIcon end,
}
ns.db.nodeSparkleHideIcon = true
Face("Copper Vein", VEIN)
suite.check("an object's plate name and bars go see-through", nameText.alpha == 0 and healthBar.alpha == 0 and iconAlpha == 0)
local NPC = "Creature-0-1-2-3-3346-0000000002"
Face("Kaja", NPC)
suite.check("a vendor's bars do, but its name stays", nameText.alpha == 1 and healthBar.alpha == 0)
ns.db.nodeSparkleHideIcon = false
Face("Kaja", NPC)
suite.check("the icon can show without the plate", iconAlpha == 0.8 and healthBar.alpha == 0 and nameText.alpha == 1)
ns.db.nodeSparkleHideIcon = true
cvars.nameplateShowFriends = "1"
Face("Kaja", NPC)
suite.check("friendly nameplates on: the vendor keeps its plate", nameText.alpha == 1 and healthBar.alpha == 0.9)
cvars.nameplateShowFriends = "0"
local realCanAttack = _G.UnitCanAttack
_G.UnitCanAttack = function() return true end
Face("Kobold Vermin", NPC)
suite.check("a mob you could fight keeps its plate", nameText.alpha == 1 and healthBar.alpha == 0.9)
_G.UnitCanAttack = realCanAttack
Face("Kaja", NPC)
fighting = true
healthBar.alpha = 0.7
Face("Kaja", NPC)
suite.check("nothing touched in a fight either", healthBar.alpha == 0.7)
fighting = false
Face("Kaja", NPC)
ns.NodeSparkle:SetEnabled(false)
suite.check("turning sparkles off gives the plate back", nameText.alpha == 1 and healthBar.alpha == 0.9)
ns.NodeSparkle:SetEnabled(true)
Face("Kaja", NPC)
ns.NodeSparkle:UnveilAll()
suite.check("a fight starting gives the plate back, so a mob it goes to keeps its bars",
    nameText.alpha == 1 and healthBar.alpha == 0.9)
keep = ns.db.nodeSparkleCVars
ns.db.nodeSparkleCVars = {}
Face("Kaja", NPC)
suite.check("plates the player turned on themselves are left alone", nameText.alpha == 1)
ns.db.nodeSparkleCVars = keep
plate.UnitFrame = nil

-- The interact plate is only for objects: on an NPC the game moves its
-- name onto the plate, white and cut short, so the setting goes back to the
-- player's own while a creature is picked, and on again for an object.
ns.NodeSparkle:SetEnabled(true)
suite.check("an object keeps the interact plate on", Face("Copper Vein", VEIN) and cvars.SoftTargetNameplateInteract == "1")
Face("Kaja", NPC)
suite.check("an NPC gets the player's own setting back", cvars.SoftTargetNameplateInteract == "0")
suite.check("and the player's value is still kept", ns.db.nodeSparkleCVars.SoftTargetNameplateInteract == "0")
Face(nil, nil)
suite.check("facing nothing turns it on again for the next node", cvars.SoftTargetNameplateInteract == "1")
Face("Kaja", NPC)
fighting = true
Face("Copper Vein", VEIN)
suite.check("never changed in a fight", cvars.SoftTargetNameplateInteract == "0")
fighting = false
Face("Copper Vein", VEIN)
suite.check("back on for an object after the fight", cvars.SoftTargetNameplateInteract == "1")
Face("Kaja", NPC)
ns.NodeSparkle:SetEnabled(false)
suite.check("turning sparkles off leaves the player's own", cvars.SoftTargetNameplateInteract == "0")
Face("Copper Vein", VEIN)
suite.check("and nothing raises it while off", cvars.SoftTargetNameplateInteract == "0")
ns.NodeSparkle:SetEnabled(true)
keep = ns.db.nodeSparkleCVars
ns.db.nodeSparkleCVars = {}
cvars.SoftTargetNameplateInteract = "1"
Face("Kaja", NPC)
suite.check("a plate the player turned on is left alone", cvars.SoftTargetNameplateInteract == "1")
ns.db.nodeSparkleCVars = keep

-- Fishing: a cast lands past the usual reach, so the reach goes up while
-- the Fishing channel runs, and comes back when it ends.
NodeSparkle:SetEnabled(true)
cvars.SoftTargetInteractRange = "15"
ns.db.nodeSparkleFishingRange = nil
NodeSparkle:FishingStarted(12345)
suite.check("another channel leaves the reach alone", cvars.SoftTargetInteractRange == "15" and not NodeSparkle.fishing)
NodeSparkle:FishingStarted(7620)
suite.check("fishing reaches as far as the bobber lands",
    cvars.SoftTargetInteractRange == tostring(NodeSparkle.FISHING_RANGE), cvars.SoftTargetInteractRange)
suite.check("keeping what it was", ns.db.nodeSparkleFishingRange == "15")
suite.check("the bobber far out shows", Face("Fishing Bobber", VEIN) == "shown")
suite.check("a bobber named a little differently too", Face("Fishing Bobber (Forever)", VEIN) == "shown")
NodeSparkle:FishingStopped()
suite.check("the reach comes back after the cast", cvars.SoftTargetInteractRange == "15" and ns.db.nodeSparkleFishingRange == nil)
suite.check("and the bobber goes with the cast", Face("Fishing Bobber (Forever)", VEIN) == "notnode")
cvars.SoftTargetInteractRange = "50"
NodeSparkle:FishingStarted(7620)
suite.check("a reach already farther is left alone", cvars.SoftTargetInteractRange == "50" and ns.db.nodeSparkleFishingRange == nil)
NodeSparkle:FishingStopped()
cvars.SoftTargetInteractRange = "15"
fighting = true
NodeSparkle:FishingStarted(7620)
suite.check("nothing set in a fight", cvars.SoftTargetInteractRange == "15")
NodeSparkle:FishingStopped()
fighting = false
NodeSparkle:FishingStarted(7620)
fighting = true
NodeSparkle:FishingStopped()
suite.check("a fight ending the cast waits to put it back", cvars.SoftTargetInteractRange == tostring(NodeSparkle.FISHING_RANGE))
fighting = false
NodeSparkle:LowerReach()
suite.check("and puts it back after", cvars.SoftTargetInteractRange == "15")
NodeSparkle:FishingStarted(7620)
NodeSparkle:SetEnabled(false)
suite.check("turning it off mid-cast puts the reach back", ns.db.nodeSparkleFishingRange == nil)
NodeSparkle:FishingStopped()
NodeSparkle:SetEnabled(true)
NodeSparkle:FishingStarted(7620)
NodeSparkle.fishing = nil   -- the game closed mid-cast
NodeSparkle:LowerReach()
suite.check("a reach left raised is put back at the next login", cvars.SoftTargetInteractRange == "15")

-- Colours (the owner, 2026-10-24): herbs and ore by your skill, quest
-- things blue, chests, schools and the bobber white, gold when off.
local C = NodeSparkle.COLORS
local realSkills = ns.Spots.Skills
local skills = { Mining = 10 }
ns.Spots.Skills = function() return skills end
suite.check("colours on by default", ns.DEFAULTS.nodeSparkleColors == true)
suite.check("corpses off by default", ns.DEFAULTS.nodeSparkleCorpses == false)
local skill, need = NodeSparkle:NodeNeeds("Copper Vein")
suite.check("a vein knows its need", skill == "Mining" and need == 1)
Face("Copper Vein", VEIN)
suite.check("a vein just reached is orange", NodeSparkle.tint == C.orange)
skills.Mining = 30
Face("Copper Vein", VEIN)
suite.check("further on it is yellow", NodeSparkle.tint == C.yellow)
skills.Mining = 200
Face("Copper Vein", VEIN)
suite.check("far past it stays green", NodeSparkle.tint == C.green)
skills = { Herbalism = 50 }
Face("Copper Vein", VEIN)
suite.check("without Mining it is grey and still shows", NodeSparkle.tint == C.grey and NodeSparkle.frame:IsShown())
suite.check("too low is grey", NodeSparkle.SkillColor(40, 65, true) == C.grey)
skills = nil
Face("Copper Vein", VEIN)
suite.check("no skills read is gold", NodeSparkle.tint == NodeSparkle.GOLD)
Face("Battered Chest", VEIN)
suite.check("a chest is white", NodeSparkle.tint == C.white)
Face("Fishing Bobber", VEIN)
suite.check("the bobber is white", NodeSparkle.tint == C.white)
skills = { Mining = 30 }
ns.HandleSlash("sparkle colors off")
suite.check("colors off is saved", ns.db.nodeSparkleColors == false)
Face("Copper Vein", VEIN)
suite.check("and everything is gold", NodeSparkle.tint == NodeSparkle.GOLD)
ns.HandleSlash("sparkle colors on")
Face("Copper Vein", VEIN)
suite.check("colors come back", NodeSparkle.tint == C.yellow)
NodeSparkle:SetStyle("sparkles")
suite.check("a new look keeps the colour", NodeSparkle.tint == C.yellow and #NodeSparkle.sparks[1].tinted == 2)
NodeSparkle:SetStyle("beacon")

-- A corpse you can skin (off until ticked).
local CORPSE = "Creature-0-1-2-3-3099-0000000002"
local dead, level = true, 12
local realDead, realLevel = _G.UnitIsDead, _G.UnitLevel
_G.UnitIsDead = function(unit) if unit == "softinteract" then return dead end return realDead and realDead(unit) end
_G.UnitLevel = function(unit) if unit == "softinteract" then return level end return realLevel and realLevel(unit) end
local realTips = _G.C_TooltipInfo
local tipLines = { { leftText = "Dire Mottled Boar" }, { leftText = "Skinnable" } }
_G.C_TooltipInfo = { GetUnit = function() return { lines = tipLines } end }
skills = { Skinning = 30 }
suite.check("a corpse gets nothing while it is off", Face("Dire Mottled Boar", CORPSE) == "nothing")
ns.HandleSlash("sparkle corpses on")
suite.check("corpses on is saved", ns.db.nodeSparkleCorpses == true)
suite.check("a skinnable corpse sparkles", Face("Dire Mottled Boar", CORPSE) == "shown")
suite.check("in your Skinning's colour", NodeSparkle.tint == C.orange)
suite.check("its plate stays on", NodeSparkle:FitPlateToTarget() == "1")
dead = false
suite.check("a live beast does not", Face("Dire Mottled Boar", CORPSE) == "nothing")
dead = true
tipLines = { { leftText = "Dire Mottled Boar" } }
suite.check("one that can't be skinned does not", Face("Dire Mottled Boar", CORPSE) == "nothing")
tipLines = { { leftText = "Dire Mottled Boar" }, { leftText = "Skinnable" } }
skills = { Mining = 30 }
suite.check("not without Skinning", Face("Dire Mottled Boar", CORPSE) == "nothing")
skills = { Skinning = 30 }
Face("Dire Mottled Boar", CORPSE)
ns.GrindGather:NoteSkin("Dire Mottled Boar", CORPSE, {}, {})
suite.check("once skinned it goes", not NodeSparkle.frame:IsShown()
    and Face("Dire Mottled Boar", CORPSE) == "nothing")
ns.HandleSlash("sparkle corpses off")
suite.check("corpses off again", ns.db.nodeSparkleCorpses == false)
_G.UnitIsDead, _G.UnitLevel, _G.C_TooltipInfo = realDead, realLevel, realTips
ns.Spots.Skills = realSkills

ns.HandleSlash("sparkle check")
suite.check("the check is kept for a report", ns.db.lastProbe and ns.db.lastProbe.check == "sparkle check")

ns.SettingsUI:Hide()

suite.done()
