-- The fishing panel (a player asked, the owner said build it, 2026-11-02).
--
-- What must hold:
--   1. Off unless ticked; Settings and /farm fishpanel turn it on and off,
--      and the strip under the Fishing window's buttons takes no room while off.
--   2. A fish never caught at any spot is new: it is cheered once, and only then.
--   3. A cast counts toward the session: casts, catches and fish.
--   4. Pause holds the clock and the counts; Start Over clears them.
--   5. Best hour at a spot is kept once enough time is behind it, and a
--      better hour is cheered once.
--   6. Fishing:Record tells the panel, and nothing changes while it is off.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("fishingpanel")

local now = 1000
local ns = env.Load({ ui = true })
_G.GetTime = function() return now end

local Panel, Fishing = ns.FishingPanel, ns.Fishing
suite.check("the panel loads", Panel ~= nil)

local cheers = {}
Panel.Cheer = function(_, text) cheers[#cheers + 1] = text end

local FISH, OTHER = "Raw Brilliant Smallfish", "Raw Longjaw Mud Snapper"

-- 1. Off by default.
suite.check("off unless ticked", Panel:Enabled() == false)
suite.check("no room taken while off", Panel:StripHeight() == 0)
local cmd = ns.commands.fishpanel
suite.check("/farm fishpanel is a command", cmd and type(cmd.fn) == "function")
cmd.fn("on")
suite.check("/farm fishpanel on turns it on", Panel:Enabled() == true and ns.db.fishingPanel == true)
suite.check("the strip takes room while on", Panel:StripHeight() > 0)
cmd.fn("off")
suite.check("/farm fishpanel off turns it off", Panel:Enabled() == false)
cmd.fn("")
suite.check("/farm fishpanel alone flips it", Panel:Enabled() == true)

-- 6 (off). Nothing counts while off.
Panel:SetEnabled(false)
Panel:StartOver()
Fishing:Record("Elwynn Forest", "Goldshire", nil, { FISH }, nil, 20)
suite.check("nothing counted while off", Panel:Session().casts == 0 and #cheers == 0)

-- 2. New fish. FISH is now caught at a spot, so only OTHER is new.
Panel:SetEnabled(true)
Panel:StartOver()
local fresh = Panel:Fresh({ FISH, OTHER })
suite.check("a fish caught before is not new", not (fresh and fresh[FISH]))
suite.check("a fish never caught is new", fresh and fresh[OTHER] == true)

Fishing:Record("Elwynn Forest", "Goldshire", nil, { OTHER }, nil, 20)
suite.check("a new fish is cheered", #cheers == 1, cheers[1])
suite.check("the cheer says it is the first", cheers[1] and cheers[1]:find("First one you've ever caught.", 1, true))
suite.check("it shows as new this session", Panel:Session().new[OTHER] == true)
Fishing:Record("Elwynn Forest", "Goldshire", nil, { OTHER }, nil, 20)
suite.check("a second one is not cheered", #cheers == 1)

-- 3. Counts.
local s = Panel:Session()
suite.check("casts counted", s.casts == 2, s.casts)
suite.check("catches counted", s.caught == 2 and s.fish[OTHER] == 2)
Fishing:Record("Elwynn Forest", "Goldshire", nil, { FISH }, { [FISH] = 3 }, 20)
suite.check("a stack counts each fish", s.caught == 5 and s.fish[FISH] == 3, s.caught)

-- 4. Pause and Start Over.
now = now + 100
local before = Panel:Seconds()
Panel:TogglePause()
now = now + 500
suite.check("pause holds the clock", Panel:Seconds() == before)
Fishing:Record("Elwynn Forest", "Goldshire", nil, { FISH }, nil, 20)
suite.check("pause holds the counts", Panel:Session().casts == 3)
Panel:TogglePause()
now = now + 10
suite.check("the clock runs again", Panel:Seconds() == before + 10)
Panel:StartOver()
suite.check("Start Over clears the session", Panel:Session().casts == 0 and Panel:Session().caught == 0)

-- 5. Best hour at a spot.
ns.db.fishingPanelBest = nil
local KEY = "spot-test"
for _ = 1, 20 do
    now = now + 40
    Panel:NoteSpot(KEY, 100)
end
suite.check("a best hour is kept after enough time", Panel:BestAt(KEY) ~= nil, Panel:BestAt(KEY))
suite.check("the first best is not cheered", #cheers == 1)
local first = Panel:BestAt(KEY)
for _ = 1, 10 do
    now = now + 20
    Panel:NoteSpot(KEY, 500)
end
suite.check("a better hour is kept", Panel:BestAt(KEY) > first)
suite.check("a better hour is cheered", #cheers == 2 and cheers[2]:find("Best Hour Yet", 1, true), cheers[2])
for _ = 1, 5 do
    now = now + 20
    Panel:NoteSpot(KEY, 500)
end
suite.check("cheered once a session", #cheers == 2)
local held = Panel:Session().spots[KEY].seconds
now = now + 1000
Panel:NoteSpot(KEY, 0)
suite.check("a long gap adds no time", Panel:Session().spots[KEY].seconds == held)

-- The Fish Log reads every spot.
local rows = Panel:LogRows()
suite.check("the log lists what was caught", #rows >= 2)
suite.check("most caught first", rows[1].count >= rows[2].count)

-- Classic's Fishing window: the strip sits under the lure line and the
-- window grows by its height while the panel is on, and not while off.
local Bar = ns.FishingBar
Bar:Build()
Panel:SetEnabled(false)
Bar:FitButtons()
local plain = Bar.frame:GetHeight()
Panel:SetEnabled(true)
suite.check("the Fishing window grows by the strip", Bar.frame:GetHeight() == plain + Panel:StripHeight(),
    tostring(Bar.frame:GetHeight()))
suite.check("the strip shows under the buttons", Panel.strip and Panel.strip:IsShown())
Panel:SetEnabled(false)
suite.check("turned off, the window is its usual height", Bar.frame:GetHeight() == plain)
suite.check("turned off, the strip hides", not Panel.strip:IsShown())

suite.done()
