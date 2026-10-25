-- Your kill count beside mobs' nameplates.
--
-- What matters: a mob you can attack shows 0/20 in gold to the left of its
-- nameplate and counts up as it is killed; from 20 kills it shows the
-- whole count, and the worth only with "Worth on nameplates" ticked and
-- only from your own kills; friendly NPCs, players, pets, critters, objects
-- and hidden mobs get nothing; a kill reads only plates of that mob again
-- and pops its count with a "+1", never on a plate that only appeared;
-- a plate going away takes its count; a secret value costs nothing worse;
-- /farm plates and the Settings boxes turn it off and on.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("killplates")

local ns = env.Load({ ui = true })
local KillPlates = ns.KillPlates

_G.GetTime = function() return 1000 end

local units = {}       -- [token] = { guid, name, player, pet, friendly, kind }
local plates = {}      -- [token] = frame
local realName, realGuid = _G.UnitName, _G.UnitGUID
_G.UnitGUID = function(unit) if units[unit] then return units[unit].guid end return realGuid(unit) end
_G.UnitName = function(unit) if units[unit] then return units[unit].name end return realName(unit) end
_G.UnitIsPlayer = function(unit) return units[unit] and units[unit].player or false end
_G.UnitPlayerControlled = function(unit) return units[unit] and units[unit].pet or false end
_G.UnitCanAttack = function(_, unit) return units[unit] ~= nil and not units[unit].friendly end
_G.UnitCreatureType = function(unit) return units[unit] and (units[unit].kind or "Beast") or nil end
_G.C_NamePlate = { GetNamePlateForUnit = function(unit) return plates[unit] end }

local reads = 0
local realForMob = ns.Value.ForMob
ns.Value.ForMob = function(_, name)
    reads = reads + 1
    if name == "Plainstrider" then return 120, { basis = "tally", priced = {} } end
    if name == "Kodo" then return 300, { basis = "database", priced = {} } end
    return nil
end

local serial = 0
local function Mob(token, name, extra)
    serial = serial + 1
    local unit = { name = name, guid = ("Creature-0-1-2-3-%d-%08d"):format(2955, serial) }
    for key, value in pairs(extra or {}) do unit[key] = value end
    units[token] = unit
    plates[token] = plates[token] or CreateFrame("Frame")
    return KillPlates:Update(token)
end

ns.db.tracker = ns.db.tracker or {}
ns.db.tracker.mobs = ns.db.tracker.mobs or {}

local function Kills(name, kills)
    ns.db.tracker.mobs[name] = { kills = kills, items = {} }
    ns.KillTooltip.ForgetKept()
end

local function Plain(text)
    return text and text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") or nil
end

suite.check("on by default", ns.DEFAULTS.killPlates == true)
suite.check("the worth is off by default", ns.DEFAULTS.killPlatesWorth == false)

suite.check("a mob never killed shows 0/20", Plain(Mob("nameplate1", "Plainstrider")) == "0/20")
suite.check("in bright gold, easy to see on red ground", (Mob("nameplate1", "Plainstrider") or ""):find("^|cffffe7a0") ~= nil)
Kills("Plainstrider", 7)
suite.check("it counts up", Plain(Mob("nameplate1", "Plainstrider")) == "7/20")
suite.check("it shows over the plate", Plain(KillPlates:Shown(plates.nameplate1)) == "7/20")

Kills("Plainstrider", 64)
suite.check("from 20 it's the whole count", Plain(Mob("nameplate1", "Plainstrider")) == "64")

ns.db.killPlatesWorth = true
local withWorth = Plain(Mob("nameplate1", "Plainstrider")) or ""
suite.check("with the worth ticked, the worth follows", withWorth:find("^64  ") ~= nil and #withWorth > 5, withWorth)
local before = reads
Mob("nameplate2", "Plainstrider")
suite.check("a second plate uses the kept worth", reads == before, reads - before)
Kills("Kodo", 40)
suite.check("never a worth from the database's rates", Plain(Mob("nameplate3", "Kodo")) == "40")
ns.db.killPlatesWorth = false

suite.check("a friendly NPC never killed shows nothing", Mob("nameplate4", "Innkeeper", { friendly = true }) == nil)
suite.check("a player shows nothing", Mob("nameplate5", "Bob", { player = true, guid = "Player-1-0001" }) == nil)
suite.check("a pet shows nothing", Mob("nameplate6", "Wolf", { pet = true }) == nil)
suite.check("a critter shows nothing", Mob("nameplate7", "Rabbit", { kind = "Critter" }) == nil)
suite.check("an object shows nothing", Mob("nameplate8", "Peacebloom", { guid = "GameObject-0-1-2-3-1-0" }) == nil)
suite.check("a secret guid costs nothing worse", Mob("nameplate9", "Kodo", { guid = env.Secret("string") }) == nil)

ns.DB:Hide("source", "Kodo")
suite.check("a hidden mob shows nothing", KillPlates:Shown(plates.nameplate3) == nil)
ns.DB:Unhide("source", "Kodo")
suite.check("and comes back when shown again", Plain(KillPlates:Shown(plates.nameplate3)) == "40")

-- A kill: only plates of that mob are read again.
Kills("Plainstrider", 65)
local updated = {}
local realUpdate = KillPlates.Update
KillPlates.Update = function(self, unit) updated[#updated + 1] = unit; return realUpdate(self, unit) end
KillPlates:Killed("Plainstrider")
KillPlates.Update = realUpdate
suite.check("a kill reads only that mob's plates", #updated == 2, #updated)
suite.check("and they show the new count", Plain(KillPlates:Shown(plates.nameplate2)) == "65")

-- A kill pops the count; a plate that only appears does not.
do
    local cheered = {}
    local realCheer = KillPlates.Cheer
    KillPlates.Cheer = function(self, entry) cheered[#cheered + 1] = entry; return realCheer(self, entry) end
    Kills("Plainstrider", 66)
    KillPlates:Killed("Plainstrider")
    suite.check("a kill pops each plate of that mob", #cheered == 2, #cheered)
    local count = #cheered
    KillPlates:Killed("Plainstrider")
    suite.check("no pop when the count did not move", #cheered == count, #cheered)
    Mob("nameplate1", "Plainstrider")
    suite.check("no pop for a plate that only appeared", #cheered == count, #cheered)
    KillPlates.Cheer = realCheer
end

-- The animations: the game's own, built once, and Window effects decide.
do
    local played = {}
    local function Group(tag)
        local group = { anims = {} }
        function group:CreateAnimation(kind)
            local anim = setmetatable({ kind = kind }, { __index = function(t, k)
                local f = function(self, ...) rawset(self, "_" .. k, { ... }) end
                rawset(t, k, f); return f end })
            group.anims[#group.anims + 1] = anim
            return anim
        end
        function group:Stop() end
        function group:Play() played[#played + 1] = tag end
        return group
    end
    local entry = KillPlates:LabelOf(plates.nameplate1)
    entry.cheers = nil
    local saved = { entry.frame.CreateAnimationGroup, entry.frame.CreateTexture, entry.frame.CreateFontString }
    entry.frame.CreateAnimationGroup = function() return Group("pop") end
    entry.frame.CreateTexture = function()
        local t = env.Stub(); t.CreateAnimationGroup = function() return Group("glow") end; return t
    end
    entry.frame.CreateFontString = function()
        local t = env.Stub(); t.CreateAnimationGroup = function() return Group("plus") end; return t
    end
    local realLevel = ns.Motion.Level
    ns.Motion.Level = function() return "full" end
    suite.check("full effects play the pop, glow and +1",
        KillPlates:Cheer(entry) == "full" and table.concat(played, ",") == "pop,glow,plus", table.concat(played, ","))
    local made = entry.cheers
    played = {}
    ns.Motion.Level = function() return "subtle" end
    KillPlates:Cheer(entry)
    suite.check("subtle keeps only the +1", table.concat(played, ",") == "plus", table.concat(played, ","))
    suite.check("the pieces are made once", entry.cheers == made)
    played = {}
    ns.Motion.Level = function() return "off" end
    suite.check("off plays nothing", KillPlates:Cheer(entry) == nil and #played == 0)
    ns.Motion.Level = realLevel
    entry.frame.CreateAnimationGroup, entry.frame.CreateTexture, entry.frame.CreateFontString = saved[1], saved[2], saved[3]
    entry.cheers = nil
end

-- The crown Farmer gave you on a mob shows beside its name too.
Kills("Plainstrider", 99)
suite.check("no crown before the 100th kill", Plain(Mob("nameplate1", "Plainstrider")) == "99")
Kills("Plainstrider", 100)
KillPlates:Killed("Plainstrider")
local crowned = KillPlates:Shown(plates.nameplate1) or ""
suite.check("the 100th kill puts the crown on its plate",
    crowned:find(ns.TrackerUI.CROWN, 1, true) ~= nil, crowned)
suite.check("after the count, next to the name", crowned:sub(-#ns.TrackerUI.CROWN) == ns.TrackerUI.CROWN, crowned)
Kills("Plainstrider", 250)
local laurel = Mob("nameplate1", "Plainstrider") or ""
suite.check("the laurel comes with it from 250", laurel:find("Laurel", 1, true) ~= nil, laurel)
Kills("Plainstrider", 1000)
local bane = Mob("nameplate1", "Plainstrider") or ""
suite.check("the legendary crown at 1000", bane:find(ns.TrackerUI.LEGENDARY_CROWN, 1, true) ~= nil, bane)
Kills("Plainstrider", 65)
Mob("nameplate1", "Plainstrider")

KillPlates:Removed("nameplate2")
suite.check("a plate going away takes its count", KillPlates:Shown(plates.nameplate2) == nil)

ns.HandleSlash("plates")
suite.check("/farm plates turns it off", ns.db.killPlates == false)
suite.check("and nothing shows", KillPlates:Shown(plates.nameplate1) == nil)
ns.HandleSlash("plates on")
suite.check("/farm plates on turns it on", ns.db.killPlates == true)
ns.HandleSlash("plates worth on")
suite.check("/farm plates worth on turns the worth on", ns.db.killPlatesWorth == true)
ns.HandleSlash("plates worth off")
suite.check("/farm plates worth off turns it off", ns.db.killPlatesWorth == false)

ns.SettingsUI:Show()
local box = ns.SettingsUI.controls.killPlates
suite.check("the settings page shows it on", box:GetChecked())
box:GetScript("OnClick")(box)
suite.check("unticking it turns it off", ns.db.killPlates == false)
box:GetScript("OnClick")(box)
suite.check("and ticking it back on", ns.db.killPlates == true)
local worthBox = ns.SettingsUI.controls.killPlatesWorth
suite.check("the worth box starts unticked", not worthBox:GetChecked())
worthBox:GetScript("OnClick")(worthBox)
suite.check("ticking it turns the worth on", ns.db.killPlatesWorth == true)
ns.SettingsUI:Hide()

-- Counter Position: where the count sits beside the plate.
suite.check("left of the name unless picked", ns.DEFAULTS.killPlatesSide == "left" and KillPlates:Side() == "left")
local namePlate = CreateFrame("Frame")
local nameText = CreateFrame("Frame")
nameText.GetObjectType = function() return "FontString" end
local castBar = CreateFrame("StatusBar")
castBar.GetObjectType = function() return "StatusBar" end
namePlate.UnitFrame = { name = nameText, castBar = castBar }
plates.nameplate1 = namePlate
Mob("nameplate1", "Plainstrider")
local function Anchor()
    for _, entry in pairs({ KillPlates:LabelOf(namePlate) }) do
        local point = entry.frame._point
        return point[1], point[2], point[3]
    end
end
local p1, to, p2 = Anchor()
suite.check("left: its right edge by the name's left", p1 == "RIGHT" and to == nameText and p2 == "LEFT")
KillPlates:SetSide("above")
p1, to, p2 = Anchor()
suite.check("above: over the name", p1 == "BOTTOM" and to == nameText and p2 == "TOP")
KillPlates:SetSide("below")
p1, to, p2 = Anchor()
suite.check("below: under the cast bar, clear of the name and bars", p1 == "TOP" and to == castBar and p2 == "BOTTOM")
KillPlates:SetSide("right")
p1, to, p2 = Anchor()
suite.check("right: past the name", p1 == "LEFT" and to == nameText and p2 == "RIGHT")
ns.QuestMobs:Show(namePlate, "3/8")
local quest = ns.QuestMobs:LabelFor(namePlate)
p1, to, p2 = Anchor()
suite.check("right: past the quest count when one shows", quest and to == quest.text and p1 == "LEFT")
ns.QuestMobs:Hide(namePlate)
p1, to = Anchor()
suite.check("and back by the name when it goes", to == nameText)
KillPlates:SetSide("sideways")
suite.check("a side that isn't one is left alone", ns.db.killPlatesSide == "right")
ns.SettingsUI:Show()
local sideStepper = ns.SettingsUI.controls.killPlatesSide
suite.check("Settings shows the side picked", sideStepper:GetValue() == 4)
sideStepper:SetValue(1)
suite.check("the stepper picks the side", ns.db.killPlatesSide == "above")
sideStepper:SetValue(3)
suite.check("and back to left", ns.db.killPlatesSide == "left")
ns.SettingsUI:Hide()

-- A live mob's nameplate inside a dungeon: what it lets the kill count read.
do
    local plate = CreateFrame("Frame")
    local oldName, oldGuid = _G.UnitName, _G.UnitGUID
    local Harvest = ns.Harvest
    local function Lines() return table.concat(ns.db.lastProbe and ns.db.lastProbe.lines or {}, "\n") end
    local realPlates = _G.C_NamePlate
    _G.C_NamePlate = { GetNamePlateForUnit = function(unit)
        if unit == "nameplate1" then return plate end
    end }
    _G.UnitName = function() return env.Secret("string") end
    _G.UnitGUID = function() return env.Secret("string") end
    ns.KillPlates:Update("nameplate1")
    Harvest.checkArmed = true
    local ran, why = pcall(Harvest.RunArmedCheck, Harvest)
    suite.check("a hidden nameplate does not raise", ran, why)
    suite.check("it counts the nameplates", Lines():find("nameplates: %d+"), Lines())
    suite.check("it describes the plate's mob",
        Lines():find("nameplate1 name: unreadable", 1, true), Lines())
    suite.check("and whether the kill count shows there",
        Lines():find("nameplate1 kill count: not shown", 1, true), Lines())
    ns.KillPlates:Removed("nameplate1")
    _G.C_NamePlate = realPlates
    _G.UnitName, _G.UnitGUID = oldName, oldGuid
end


ns.Value.ForMob = realForMob
_G.C_NamePlate = nil
suite.done()
