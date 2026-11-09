-- Your quest count beside quest mobs' names.
--
-- What matters: a mob whose tooltip carries an objective not yet met shows
-- that count beside its nameplate's name; else a quest log objective that
-- names it; a met count, a player, an object or a plain mob shows nothing;
-- a plate going away takes its count; a quest log change reads the plates
-- again; a secret value costs nothing worse; /farm questcount and the
-- Settings box turn it off and on.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("questmobs")

local ns = env.Load({ ui = true })
local QuestMobs = ns.QuestMobs

local units = {}       -- [token] = { guid, name, player, lines }
local plates = {}      -- [token] = frame
local realName, realGuid = _G.UnitName, _G.UnitGUID
_G.UnitGUID = function(unit) if units[unit] then return units[unit].guid end return realGuid(unit) end
_G.UnitName = function(unit) if units[unit] then return units[unit].name end return realName(unit) end
_G.UnitIsPlayer = function(unit) return units[unit] and units[unit].player or false end
_G.C_NamePlate = { GetNamePlateForUnit = function(unit) return plates[unit] end }
_G.C_TooltipInfo = { GetUnit = function(unit)
    local lines = {}
    for i, text in ipairs(units[unit] and units[unit].lines or {}) do lines[i] = { leftText = text } end
    return { lines = lines }
end }

local function Mob(token, name, lines, guid, player)
    units[token] = { name = name, lines = lines, guid = guid or ("Creature-0-1-2-3-2955-" .. token), player = player }
    plates[token] = plates[token] or CreateFrame("Frame")
    return QuestMobs:Update(token)
end

suite.check("on by default", ns.DEFAULTS.questMobCount == true)
suite.check("the tooltip's count shows", Mob("nameplate1", "Plainstrider", { "Plainstrider", "Level 8", "Plainstrider Beak: 3/8" }) == "3/8")
suite.check("beside the name", QuestMobs.CountIn("Plainstrider slain: 2/10") == "2/10")
suite.check("a count already met shows nothing", Mob("nameplate2", "Plainstrider", { "Plainstrider", "Plainstrider Beak: 8/8" }) == nil)
suite.check("a plain mob shows nothing", Mob("nameplate3", "Kodo", { "Kodo", "Level 9" }) == nil)
suite.check("a player shows nothing", Mob("nameplate4", "Bob", { "Bob", "Quest: 1/2" }, "Player-1-0001", true) == nil)
suite.check("an object shows nothing", Mob("nameplate5", "Peacebloom", { "Peacebloom", "1/2" }, "GameObject-0-1-2-3-1-0") == nil)
suite.check("a secret guid costs nothing worse", Mob("nameplate6", "Kodo", { "Kodo", "1/2" }, env.Secret("string")) == nil)

-- Not on the tooltip: the quest log names it.
_G.C_QuestLog = {
    GetNumQuestLogEntries = function() return 1 end,
    GetInfo = function() return { questID = 9 } end,
    GetQuestObjectives = function() return { { text = "Galak Centaur slain: 0/6", numFulfilled = 0, numRequired = 6, finished = false } } end,
}
suite.check("an objective in the log that names it", Mob("nameplate7", "Galak Centaur", { "Galak Centaur" }) == "0/6")

-- The plate goes; the count goes with it.
suite.check("it shows over the plate", QuestMobs:Shown(plates.nameplate1) == "3/8")
QuestMobs:Removed("nameplate1")
suite.check("a plate going away takes its count", QuestMobs:Shown(plates.nameplate1) == nil)

-- The quest log moves on: every plate is read again.
units.nameplate7.lines = { "Galak Centaur", "Galak Centaur slain: 1/6" }
QuestMobs:UpdateAll()
suite.check("read again after the log changes", QuestMobs:Update("nameplate7") == "1/6")

-- Forever's plate puts the level just past the bar, where the name ends:
-- the count goes past the level, never on it.
local function Text() local t = env.Stub(); t.GetObjectType = function() return "FontString" end; return t end
local levelPlate = CreateFrame("Frame")
levelPlate.UnitFrame = { name = Text(), LevelFrame = env.Stub({ _shown = true }) }
levelPlate.UnitFrame.name._right = 100
levelPlate.UnitFrame.LevelFrame._right = 130
levelPlate.UnitFrame.LevelFrame.GetRight = function(self) return self._right end
levelPlate.UnitFrame.name.GetRight = function(self) return self._right end
plates.nameplate8 = levelPlate
Mob("nameplate8", "Strigid Owl", { "Strigid Owl", "Strigid Owl slain: 0/8" })
local label = QuestMobs:LabelFor(levelPlate)
-- Tied to the name, never to the level: on Forever the level sits on a
-- guarded part of the plate, and a count tied to it can't show in a fight.
suite.check("the count is tied to the name, not the level", label and label.frame._point[2] == levelPlate.UnitFrame.name)
suite.check("and pushed past where the level ends", label and label.frame._point[4] == 4 + 30)
suite.check("it shows", QuestMobs:Shown(levelPlate) == "0/8")
local namePlate = CreateFrame("Frame")
namePlate.UnitFrame = { name = Text(), LevelFrame = env.Stub({ _shown = false }) }
plates.nameplate9 = namePlate
Mob("nameplate9", "Strigid Owl", { "Strigid Owl", "Strigid Owl slain: 0/8" })
label = QuestMobs:LabelFor(namePlate)
suite.check("with no level showing, beside the name", label and label.frame._point[2] == namePlate.UnitFrame.name)
suite.check("and past where the level would be", label and (label.frame._point[4] or 0) >= QuestMobs.LEVEL_ROOM)
local scanPlate = CreateFrame("Frame")
local lvl = Text(); lvl._shown = true; lvl.IsShown = function() return true end; lvl.GetText = function() return "10" end
scanPlate.UnitFrame = env.Stub({ name = Text() })
scanPlate.UnitFrame.GetRegions = function() return lvl end
scanPlate.UnitFrame.GetChildren = function() end
plates.nameplate10 = scanPlate
Mob("nameplate10", "Kobold Tunneler", { "Kobold Tunneler", "Kobold Tunneler slain: 1/10" })
label = QuestMobs:LabelFor(scanPlate)
suite.check("a level under another name is found too", QuestMobs.RightOf(scanPlate) == lvl)
suite.check("but the count is still tied to the name", label and label.frame._point[2] == scanPlate.UnitFrame.name)
suite.check("past the level's room when its edge can't be read", label and label.frame._point[4] >= QuestMobs.LEVEL_ROOM)
-- A guarded part of the plate (the cast bar) hands back a secret for
-- IsShown and its edge: never compared, the count still shows by the name.
local secrets = {}
local realIsSecret = _G.issecretvalue
_G.issecretvalue = function(v) return secrets[v] == true end
local secretShown, secretRight = env.Secret("boolean"), env.Secret("number")
secrets[secretShown], secrets[secretRight] = true, true
local guarded = CreateFrame("Frame")
local castBar = Text(); castBar.IsShown = function() return secretShown end
castBar.GetRight = function() return secretRight end
castBar.GetText = function() return secretRight end
guarded.UnitFrame = env.Stub({ name = Text(), LevelFrame = castBar })
guarded.UnitFrame.GetRegions = function() return castBar end
guarded.UnitFrame.GetChildren = function() end
plates.nameplate12 = guarded
local okGuarded = pcall(Mob, "nameplate12", "Kobold Vermin", { "Kobold Vermin", "Kobold Vermin slain: 3/10" })
label = QuestMobs:LabelFor(guarded)
suite.check("a secret on the plate raises nothing", okGuarded)
suite.check("and the count still shows by the name", label and label.frame._point[2] == guarded.UnitFrame.name and QuestMobs:Shown(guarded) == "3/10")
suite.check("a secret counts as not shown", QuestMobs.RightOf(guarded) == guarded.UnitFrame.name)
_G.issecretvalue = realIsSecret
-- Every read off a plate's own pieces goes through Plain, so a secret is
-- never compared, added or joined outside a pcall.
local source = io.open("UI/QuestMobs.lua"):read("*a")
local bare = {}
for line in source:gmatch("[^\n]+") do
    local read = line:find("[%w_]+:IsShown%(%)") or line:find(":GetRight%(%)") or line:find(":GetText%(%)")
        or line:find(":GetObjectType%(%)") or line:find(":GetEffectiveScale%(%)")
    if read and (line:find("piece:") or line:find("name:") or line:find("own:")) then
        if not line:find("Plain%(function") then
            bare[#bare + 1] = line
        end
    end
end
suite.check("no plate read skips Plain", #bare == 0, table.concat(bare, " | "))

-- A spot the game refuses still leaves the count showing, by the plate.
local stubborn = CreateFrame("Frame")
stubborn.UnitFrame = { name = Text() }
plates.nameplate11 = stubborn
units.nameplate11 = nil
local realAnchor = QuestMobs.Anchor
QuestMobs.Anchor = function() return stubborn.UnitFrame.name, 4 end
local refused = CreateFrame("Frame")
local realCreate = _G.CreateFrame
_G.CreateFrame = function(...) local f = realCreate(...); f.SetPoint = function(self, p, to, ...) if to == stubborn.UnitFrame.name then error("blocked") end self._point = { p, to, ... } end return f end
Mob("nameplate11", "Kobold Miner", { "Kobold Miner", "Kobold Miner slain: 2/10" })
_G.CreateFrame, QuestMobs.Anchor = realCreate, realAnchor
label = QuestMobs:LabelFor(stubborn)
suite.check("a refused spot still shows the count by the plate", label and label.frame._point[2] == stubborn and QuestMobs:Shown(stubborn) == "2/10")

-- In a fight the plate's edges are secret and the game can refuse a move,
-- so a count already placed keeps its spot; out of one it follows the level.
local fighting = false
_G.InCombatLockdown = function() return fighting end
levelPlate.UnitFrame.LevelFrame._right = 150
fighting = true
QuestMobs:Update("nameplate8")
suite.check("in a fight the count keeps its place", label and QuestMobs:LabelFor(levelPlate).frame._point[4] == 4 + 30)
suite.check("and still shows", QuestMobs:Shown(levelPlate) == "0/8")
fighting = false
QuestMobs:Update("nameplate8")
suite.check("out of a fight it follows the level", QuestMobs:LabelFor(levelPlate).frame._point[4] == 4 + 50)
suite.check("a count's spot is never cleared", not source:find("ClearAllPoints", 1, true))
-- Hidden and shown again, the frame keeps its spot (a frame with no points
-- can't be placed in a fight).
QuestMobs:Hide(levelPlate)
fighting = true
QuestMobs:Update("nameplate8")
suite.check("hidden and back in a fight, it still has its spot", QuestMobs:LabelFor(levelPlate).frame._point[4] == 4 + 50)
fighting = false

-- A plate first seen in a fight, whose spot the game refuses without a
-- word (no error, no point), shows once the fight ends.
local refusedPlate = CreateFrame("Frame")
refusedPlate.UnitFrame = { name = Text() }
plates.nameplate13 = refusedPlate
local blocked = true
_G.CreateFrame = function(...)
    local f = realCreate(...)
    f.SetPoint = function(self, ...) if not blocked then self._point = { ... } end end
    f.GetNumPoints = function(self) return rawget(self, "_point") and 1 or 0 end
    return f
end
fighting = true
Mob("nameplate13", "Kobold Geomancer", { "Kobold Geomancer", "Kobold Geomancer slain: 0/10" })
_G.CreateFrame = realCreate
label = QuestMobs:LabelFor(refusedPlate)
suite.check("a refused spot in a fight shows nothing yet", label and rawget(label.frame, "_point") == nil and QuestMobs:Shown(refusedPlate) == "0/10")
suite.check("and is noted for the fight's end", QuestMobs.waiting == true)
blocked, fighting = false, false
QuestMobs:OnEnable()
local handler = _G.BlackthornesFarmerEventFrame:GetScript("OnEvent")
handler(_G.BlackthornesFarmerEventFrame, "PLAYER_REGEN_ENABLED")
label = QuestMobs:LabelFor(refusedPlate)
suite.check("the fight's end places it by the name", label and rawget(label.frame, "_point") and label.frame._point[2] == refusedPlate.UnitFrame.name)
suite.check("and nothing waits any more", not QuestMobs.waiting)

ns.HandleSlash("questcount")
suite.check("/farm questcount turns it off", ns.db.questMobCount == false)
suite.check("and nothing shows", QuestMobs:Update("nameplate7") == nil)
ns.HandleSlash("questcount on")
suite.check("/farm questcount on turns it on", ns.db.questMobCount == true)

ns.SettingsUI:Show()
local box = ns.SettingsUI.controls.questMobCount
suite.check("the settings page shows it on", box:GetChecked())
box:GetScript("OnClick")(box)
suite.check("unticking it turns it off", ns.db.questMobCount == false)
box:GetScript("OnClick")(box)
suite.check("and ticking it back on", ns.db.questMobCount == true)
ns.SettingsUI:Hide()

_G.C_QuestLog, _G.C_TooltipInfo = nil, nil
suite.done()
