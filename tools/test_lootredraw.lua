-- Tests for the panel redraw during a loot window's read: it waits for the
-- next frame and every call until then shares one redraw, so pricing a long
-- session's loot never runs inside the loot event (2026-11-02, "script ran
-- too long" on a German client after many kills).

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("lootredraw")

local ns = env.Load({ ui = true })
local UI = ns.TrackerUI

local waiting = {}
local timerAfter = _G.C_Timer.After
_G.C_Timer.After = function(_, fn) waiting[#waiting + 1] = fn end

local renders = 0
local render = UI.Render
UI.Render = function(self, ...) renders = renders + 1 end

-- 1. Outside a loot read, a redraw is at once.
UI:Refresh()
suite.check("a redraw outside loot is at once", renders == 1 and #waiting == 0, renders)

-- 2. Inside one, three redraws wait and share one turn.
renders = 0
ns.readingLoot = true
UI:Refresh(); UI:Refresh(); UI:Refresh()
ns.readingLoot = nil
suite.check("nothing drawn inside the loot read", renders == 0, renders)
suite.check("one redraw waits", #waiting == 1, #waiting)

waiting[1]()
suite.check("the waiting redraw draws once", renders == 1, renders)

-- 3. A read left marked (the event cut short) never keeps the panel waiting.
renders, waiting = 0, {}
ns.readingLoot = true
UI:Refresh()
waiting[1]()
suite.check("drawn on the next frame even while still marked", renders == 1 and #waiting == 1, renders)
ns.readingLoot = nil

-- 4. A real loot window clears the mark after its readers.
local fire = ns.eventFrame:GetScript("OnEvent")
env.world.loot = { { name = "Large Fang", id = 5637 } }
fire(ns.eventFrame, "LOOT_READY")
fire(ns.eventFrame, "LOOT_CLOSED")
suite.check("the mark is gone after the read", ns.readingLoot == nil, ns.readingLoot)

UI.Render = render
_G.C_Timer.After = timerAfter
suite.done()
