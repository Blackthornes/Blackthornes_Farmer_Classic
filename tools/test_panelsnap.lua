-- Snap Panels (UI/PanelSnap.lua, the owner, 2026-10-29): Kills & Loot,
-- Goals and Where to Farm snap together into one column, on unless
-- unticked, never in a fight. Dropped near Kills & Loot's bottom edge the
-- goals panel hangs under it again; Where to Farm dropped near the goals
-- panel's bottom opens under it from then on.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("panelsnap")

local ns = env.Load({ ui = true })
local Snap = ns.PanelSnap

suite.check("it is on until unticked", Snap:IsOn() and ns.db.snapPanels == nil)

local function Place(frame, left, top, width, height)
    frame._left, frame._top = left, top
    frame._width, frame._height = width, height
    frame._shown = true
end

ns.GoalsUI:Build()
local tracker = CreateFrame("Frame", nil, UIParent)
local realTracker = ns.TrackerUI.frame
ns.TrackerUI.frame = tracker
Place(tracker, 100, 600, 300, 200)

local goals = ns.GoalsUI.frame
ns.db.goalsX, ns.db.goalsY = 500, 300
Place(goals, 110, 390, 300, 120)

suite.check("near means its top by the other's bottom, overlapping", Snap.Near(goals, tracker))
Place(goals, 110, 300, 300, 120)
suite.check("far below is not near", not Snap.Near(goals, tracker))
Place(goals, 700, 400, 300, 120)
suite.check("off to the side is not near", not Snap.Near(goals, tracker))

-- Dropped near, it docks; dropped far, it keeps its own place.
Place(goals, 110, 390, 300, 120)
goals:GetScript("OnDragStop")(goals)
suite.check("the goals panel dropped under Kills & Loot hangs there again",
    ns.db.goalsX == nil and ns.db.goalsY == nil)

Place(goals, 600, 200, 300, 120)
goals:GetScript("OnDragStop")(goals)
suite.check("dropped away, it keeps its own place", ns.db.goalsX == 600, ns.db.goalsX)

-- Kills & Loot dropped with its bottom by a loose goals panel's top.
Place(goals, 110, 395, 300, 120)
suite.check("Kills & Loot dropped over a loose goals panel picks it up",
    Snap:TrackerDropped() and ns.db.goalsX == nil)

-- Never in a fight.
ns.db.goalsX = 600
_G.InCombatLockdown = function() return true end
suite.check("never in a fight", not Snap:GoalsDropped() and ns.db.goalsX == 600)
_G.InCombatLockdown = function() return false end

-- Unticked, nothing snaps.
Snap:SetOn(false)
suite.check("unticked saves false", ns.db.snapPanels == false and not Snap:IsOn())
suite.check("and nothing snaps", not Snap:GoalsDropped() and ns.db.goalsX == 600)
Snap:SetOn(true)

-- Where to Farm.
local spots = ns.GoalsUI:BuildSpots()
Place(goals, 110, 390, 300, 120)
Place(spots, 120, 265, 300, 200)
suite.check("Where to Farm dropped under the goals panel opens under it",
    Snap:SpotsDropped(spots) and ns.db.goalSpotsUnder == true and Snap:SpotsUnder())
Place(spots, 600, 600, 300, 200)
suite.check("dragged away, it opens beside it as before",
    not Snap:SpotsDropped(spots) and ns.db.goalSpotsUnder == nil and not Snap:SpotsUnder())

ns.TrackerUI.frame = realTracker
suite.done()
