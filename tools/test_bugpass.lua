-- The bug pass after 0.24.0 (2026-10-11).
--
-- What matters: a Pick Pocket window is never a kill, nor is any window
-- whose source the client shows alive; one loot window works its corpse
-- out once; a loot link the client hides moves nothing; your own mobs'
-- spots reach the arrow; walking away from a mailbox or bank lets goals
-- count gathering again; and the Settings arrow Check keeps its result.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("bugpass")

local ns = env.Load({ ui = true })
local Harvest, Tracker = ns.Harvest, ns.Tracker

ns.Harvest:OnEnable()
Tracker:OnEnable()

local fire = ns.eventFrame:GetScript("OnEvent")
local clock = 100
_G.GetTime = function() return clock end

local units = {}
local baseName, baseDead, baseGUID, basePlayer = UnitName, UnitIsDead, UnitGUID, UnitIsPlayer
_G.UnitName = function(unit) if units[unit] then return units[unit].name end return baseName(unit) end
_G.UnitIsDead = function(unit) if units[unit] then return units[unit].dead == true end return baseDead(unit) end
_G.UnitGUID = function(unit) if units[unit] then return units[unit].guid end return baseGUID(unit) end
_G.UnitIsPlayer = function(unit) if units[unit] then return false end return basePlayer(unit) end

local DEFIAS = "Defias Pathstalker"
local GUID = "Creature-0-1-2-3-121-0000AAAA"
local POCKET = { name = "Flash Pellet", id = 5140 }
local CLOTH = { name = "Linen Cloth", id = 2589 }

local function Window(guid, items)
    env.world.loot = items
    _G.GetLootSourceInfo = function(slot) if items[slot] then return guid, 1 end end
end

local function Kills(mob)
    local tally = Tracker:Store()[mob]
    return tally and tally.kills or 0
end

-- 1. Pick Pocket on a living mob you target, seen alive first.
env.world.target = nil
units.target = { name = DEFIAS, dead = false, guid = GUID }
fire(ns.eventFrame, "PLAYER_TARGET_CHANGED")
fire(ns.eventFrame, "UNIT_SPELLCAST_SENT", "player", DEFIAS, "Cast-1", 921)
fire(ns.eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 921)
Window(GUID, { POCKET })
fire(ns.eventFrame, "LOOT_OPENED")
fire(ns.eventFrame, "LOOT_CLOSED")
suite.check("a pick pocket is not a kill", Kills(DEFIAS) == 0, Kills(DEFIAS))
suite.check("nor a harvested corpse", Harvest.opened[GUID] == nil)
suite.check("its item goes in the session's loot", Tracker.sessionLoot[POCKET.name] == 1,
    Tracker.sessionLoot[POCKET.name])
suite.check("from the mob you picked", Tracker.sessionFrom[POCKET.name]
    and Tracker.sessionFrom[POCKET.name][DEFIAS] == 1)

-- 1b. A pocket with coin: the coin is yours too, and counted once.
local coinBefore = Tracker.sessionCopper
clock = clock + 30
fire(ns.eventFrame, "UNIT_SPELLCAST_SENT", "player", DEFIAS, "Cast-2", 921)
Window(GUID, { { name = "12 Copper", money = true } })
fire(ns.eventFrame, "LOOT_OPENED")
fire(ns.eventFrame, "LOOT_CLOSED")
suite.check("pocket coin counts", Tracker.sessionCopper - coinBefore == 12,
    Tracker.sessionCopper - coinBefore)
suite.check("still no kill", Kills(DEFIAS) == 0, Kills(DEFIAS))

-- 2. The same mob killed and looted later: a kill, with its own drop.
clock = clock + 30
units.target.dead = true
Window(GUID, { CLOTH })
fire(ns.eventFrame, "LOOT_OPENED")
fire(ns.eventFrame, "LOOT_CLOSED")
suite.check("the real kill counts", Kills(DEFIAS) == 1, Kills(DEFIAS))
suite.check("without the pocket's item", Tracker:Store()[DEFIAS].items[POCKET.name] == nil)

-- 3. A window naming a mob the client shows alive (a pick pocket on a
-- client whose cast this did not hear) is not a kill either.
local OTHER = "Creature-0-1-2-3-121-0000BBBB"
units.target = { name = DEFIAS, dead = false, guid = OTHER }
fire(ns.eventFrame, "PLAYER_TARGET_CHANGED")
clock = clock + 30
Window(OTHER, { POCKET })
fire(ns.eventFrame, "LOOT_OPENED")
fire(ns.eventFrame, "LOOT_CLOSED")
suite.check("a source still alive is no corpse", Kills(DEFIAS) == 1, Kills(DEFIAS))
units.target = nil

-- 4. Another spell's cast says nothing about pockets.
suite.check("Pick Pocket by its id", Harvest.IsPickPocket(921))
suite.check("another spell is not it", not Harvest.IsPickPocket(133))
suite.check("nor a secret one", not Harvest.IsPickPocket(env.Secret("number")))

-- 5. One loot window builds the dungeon mob's name once, however many
-- slots and readers ask.
local DUNGEON = "Creature-0-4621-389-76516-99998-0000CB0C4D"
local builds = 0
_G.C_TooltipInfo = { GetHyperlink = function() builds = builds + 1 return nil end }
clock = clock + 30
Window(DUNGEON, { CLOTH, POCKET, { name = "Wool Cloth", id = 2592 } })
fire(ns.eventFrame, "LOOT_OPENED")
fire(ns.eventFrame, "LOOT_CLOSED")
suite.check("the corpse is read once a window", builds == 1, builds)
_G.C_TooltipInfo = nil

-- 6. A loot link the client keeps hidden teaches nothing, so the looks
-- are not walked again for it.
local before = Tracker.looksVersion or 0
local baseLink = GetLootSlotLink
_G.GetLootSlotLink = function() return env.Secret("string") end
Tracker:NoteLook(1, "Hidden Thing")
Tracker:NoteLook(1, "Hidden Thing")
_G.GetLootSlotLink = baseLink
suite.check("a hidden link moves no version", (Tracker.looksVersion or 0) == before,
    Tracker.looksVersion)

_G.GetLootSourceInfo = nil
_G.UnitName, _G.UnitIsDead, _G.UnitGUID, _G.UnitIsPlayer = baseName, baseDead, baseGUID, basePlayer

-- 7. Your own mob's spot is a spot the arrow can point at.
Harvest.records["Test Boar|Elwynn Forest|"] = {
    mob = "Test Boar", zone = "Elwynn Forest", corpses = 3, coords = { 41.2, 63.5 },
    items = { ["Test Tusk"] = { name = "Test Tusk", corpses = 2, count = 2 } },
}
local spot
for _, candidate in ipairs(ns.Spots:Candidates("Test Tusk")) do
    if candidate.name == "Test Boar" then spot = candidate end
end
suite.check("your mob is a place", spot ~= nil)
suite.check("with where you found it", spot and spot.coords and spot.coords[1] == 41.2,
    spot and spot.coords and spot.coords[1])

-- 8. Walking away from the mailbox, with no MAIL_CLOSED.
local Goals = ns.Goals
Goals:OnEnable()
fire(ns.eventFrame, "MAIL_SHOW")
suite.check("at the mailbox, away", Goals.away.mail == true)
fire(ns.eventFrame, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 17)
suite.check("walking off ends it", Goals.away.mail == nil)
fire(ns.eventFrame, "BANKFRAME_OPENED")
fire(ns.eventFrame, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 3)
suite.check("another interaction leaves the bank open", Goals.away.bank == true)
fire(ns.eventFrame, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 8)
suite.check("the banker's ends it", Goals.away.bank == nil)
suite.check("kinds by the game's numbers", Goals.InteractionKind(21) == "auction"
    and Goals.InteractionKind(5) == "vendor" and Goals.InteractionKind("x") == nil)

-- 9. A goal's name steps down a size before it would wrap, never "...".
local Theme, GoalsUI = ns.Theme, ns.GoalsUI
local baseWidth = Theme.TextWidth
local PER = { normal = 7, small = 6, tiny = 5 }
Theme.TextWidth = function(size, text) return #(text or "") * (PER[size] or 7) end
suite.check("a name that fits stays normal", GoalsUI.NameSize("Copper Ore", 200) == "normal")
suite.check("a long one goes small", GoalsUI.NameSize(("x"):rep(30), 200) == "small")
suite.check("a longer one tiny", GoalsUI.NameSize(("x"):rep(38), 200) == "tiny")
Theme.TextWidth = baseWidth

-- 10. The arrow check is typed only now (the owner, 2026-10-23) and still
-- keeps its result for "read the probe".
local kept
local baseKeep = ns.KeepCheck
ns.KeepCheck = function(name) kept = name end
ns.HandleSlash("arrow check")
ns.KeepCheck = baseKeep
suite.check("/farm arrow check keeps the check", kept == "arrow check", tostring(kept))

local UI = ns.UI
UI:Build()

-- 11. The Grind tab redraws on a level or a new zone while it shows, and
-- not while it does not.
ns.GrindingUI:OnEnable()
local renders = 0
local baseRender = ns.GrindingUI.Render
ns.GrindingUI.Render = function() renders = renders + 1 end
UI.frame:Show()
UI.grindView:Show()
fire(ns.eventFrame, "ZONE_CHANGED_NEW_AREA")
fire(ns.eventFrame, "PLAYER_LEVEL_UP", 12)
suite.check("a new zone and a level redraw it", renders == 2, renders)
UI.grindView:Hide()
fire(ns.eventFrame, "ZONE_CHANGED_NEW_AREA")
suite.check("hidden, it is left alone", renders == 2, renders)
ns.GrindingUI.Render = baseRender
UI.frame:Hide()

-- 12. Opening the window on a search draws the list once.
local draws = 0
local baseDraw = UI.Render
UI.Render = function(self, ...) draws = draws + 1 return baseDraw(self, ...) end
UI.lastQuery = nil
UI.tab = "search"
ns.db.lastTab = "search"
UI:Toggle()
suite.check("one draw on opening", draws == 1, draws)
UI.Render = baseDraw
UI:Hide()

-- 13. A middle-click on the minimap button brings back the Kills & Loot
-- panel and the goals when they were closed (the owner, 2026-10-28); with
-- both up it toggles the goals, and with none it says how to make one.
-- Left and right clicks are unchanged.
UI:BuildMinimapButton()
local mini = UI.minimapButton
local miniClick = mini and mini:GetScript("OnClick")
local toggles, hints, opened, settings, shows, trackerShown = 0, 0, 0, 0, 0, 0
local baseGoalsToggle, basePrint, baseOpen = GoalsUI.Toggle, ns.Print, UI.Toggle
local baseGoalsShow, baseTracker = GoalsUI.Show, ns.SettingsUI.SetTrackerShown
local baseSettings = ns.SettingsUI.Toggle
local baseList = ns.Goals.List
local baseHidden = ns.db.trackerHidden
GoalsUI.Toggle = function() toggles = toggles + 1 end
GoalsUI.Show = function() shows = shows + 1 end
ns.SettingsUI.SetTrackerShown = function(_, on) if on then trackerShown = trackerShown + 1 end ns.db.trackerHidden = not on end
ns.Print = function(text) if tostring(text):find("no goals yet", 1, true) then hints = hints + 1 end end
UI.Toggle = function() opened = opened + 1 end
ns.SettingsUI.Toggle = function() settings = settings + 1 end
ns.db.trackerHidden = false
ns.Goals.List = function() return {} end
if miniClick then miniClick(mini, "MiddleButton") end
suite.check("no goals: a hint, nothing toggled", hints == 1 and toggles == 0, hints .. "/" .. toggles)
ns.Goals.List = function() return { { item = "Copper Ore" } } end
if GoalsUI.frame then GoalsUI.frame:Hide() end
ns.db.trackerHidden = true
if miniClick then miniClick(mini, "MiddleButton") end
suite.check("closed panels come back", trackerShown == 1 and shows == 1 and toggles == 0,
    trackerShown .. "/" .. shows .. "/" .. toggles)
if GoalsUI.frame then GoalsUI.frame:Show() end
if miniClick then miniClick(mini, "MiddleButton") end
suite.check("with both up it toggles the goals", toggles == 1 and trackerShown == 1, toggles)
if GoalsUI.frame then GoalsUI.frame:Hide() end
if miniClick then miniClick(mini, "LeftButton") miniClick(mini, "RightButton") end
suite.check("left opens the window, right the settings", opened == 1 and settings == 1,
    opened .. "/" .. settings)
GoalsUI.Toggle, ns.Print, UI.Toggle = baseGoalsToggle, basePrint, baseOpen
GoalsUI.Show, ns.SettingsUI.SetTrackerShown = baseGoalsShow, baseTracker
ns.SettingsUI.Toggle, ns.Goals.List = baseSettings, baseList
ns.db.trackerHidden = baseHidden

suite.done()
