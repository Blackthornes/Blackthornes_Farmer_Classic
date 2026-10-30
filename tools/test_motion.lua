-- The glowup's animations (2026-09-27: "give it an overall glowup,
-- keep the dopamine hits, add animations where you think they're good").
--
-- What matters: tweens land where they were headed, a new one in the same slot
-- replaces the old, Off lands everything at once, an error inside a tween is
-- dropped rather than raised, and the search window's new pieces (level
-- suggestions, the sliding tab line, rows arriving) draw without the client.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("motion")

local ns = env.Load({ ui = true })
local Motion = ns.Motion
local UI = ns.UI

--------------------------------------------------------------------------------
-- The clock
--------------------------------------------------------------------------------

local owner = {}
local seen = {}
Motion:Run(owner, "a", 1, function(p) seen[#seen + 1] = p end, { ease = false })

suite.check("a tween draws its start at once", seen[1] == 0, seen[1])
suite.check("and is running", Motion:Running(owner, "a"))

Motion:Step(0.5)
suite.check("half way through, half way", math.abs(seen[#seen] - 0.5) < 1e-6, seen[#seen])

Motion:Step(0.6)
suite.check("it lands at its end", seen[#seen] == 1, seen[#seen])
suite.check("and stops", not Motion:Running(owner, "a"))

-- A second tween in the same slot replaces the first.
local first, second = 0, 0
Motion:Run(owner, "b", 1, function(p) first = p end)
Motion:Run(owner, "b", 1, function(p) second = p end)
Motion:Step(2)
suite.check("a replaced tween stops where it was", first == 0, first)
suite.check("its replacement runs to the end", second == 1, second)

-- A delay holds it at its start.
local delayed
Motion:Run(owner, "c", 0.2, function(p) delayed = p end, { delay = 0.5 })
Motion:Step(0.3)
suite.check("a delayed tween waits at its start", delayed == 0, delayed)
Motion:Step(0.5)
suite.check("then runs", delayed == 1, delayed)

-- Done is called once, at the end.
local done = 0
Motion:Run(owner, "d", 0.1, function() end, { done = function() done = done + 1 end })
Motion:Step(1)
Motion:Step(1)
suite.check("done is called once", done == 1, done)

-- An error in a tween is dropped, not raised, and does not stop the others.
local other
Motion:Run(owner, "bad", 1, function(p) if p > 0 then error("boom") end end)
Motion:Run(owner, "good", 1, function(p) other = p end)
local ok = pcall(Motion.Step, Motion, 0.5)
suite.check("a failing tween does not raise", ok)
suite.check("and is dropped", not Motion:Running(owner, "bad"))
Motion:Step(1)
suite.check("the others carry on", other == 1, other)

-- Blend turns round from wherever it was.
local value
Motion:Blend(owner, "hover", 1, 1, function(v) value = v end)
Motion:Step(0.5)
suite.check("a blend moves toward its target", math.abs(value - 0.5) < 1e-6, value)
Motion:Blend(owner, "hover", 0, 1, function(v) value = v end)
suite.check("turning back starts from where it was", math.abs(value - 0.5) < 1e-6, value)
Motion:Step(1)
suite.check("and lands", value == 0, value)

-- FinishAll lands everything.
local landed
Motion:Run(owner, "e", 5, function(p) landed = p end)
Motion:FinishAll()
suite.check("FinishAll lands a running tween", landed == 1, landed)
suite.check("and nothing is left running", #Motion.tweens == 0)

-- Off: every tween lands at its end at once.
ns.db.trackerEffects = "off"
local instant
Motion:Run(owner, "f", 5, function(p) instant = p end)
suite.check("with effects off a tween lands at once", instant == 1, instant)
suite.check("and nothing is running", not Motion:Running(owner, "f"))
ns.db.trackerEffects = nil

-- The back-eased curve starts at 0, ends at 1, and overshoots between.
suite.check("EaseOutBack starts at 0", math.abs(Motion.EaseOutBack(0)) < 1e-6)
suite.check("and ends at 1", math.abs(Motion.EaseOutBack(1) - 1) < 1e-6)
suite.check("and overshoots on the way", Motion.EaseOutBack(0.7) > 1)

--------------------------------------------------------------------------------
-- Suggestions for your level
--------------------------------------------------------------------------------

local picks = ns.Search:ForLevel(12)
local names = {}
for _, item in ipairs(picks) do names[item.category] = item.name end

suite.check("level 12 gets a cloth", names.Cloth ~= nil)
suite.check("and an ore", names.Mining ~= nil)
suite.check("and it is one a level 12 can farm: Copper or Tin",
    names.Mining == "Copper Ore" or names.Mining == "Tin Ore", names.Mining)
suite.check("no more than one of each kind", #picks <= #ns.Search.SUGGEST_CATEGORIES, #picks)
suite.check("nothing before the level is known", #ns.Search:ForLevel(0) == 0)

local high = ns.Search:ForLevel(58)
local highNames = {}
for _, item in ipairs(high) do highNames[item.category] = item.name end
suite.check("level 58 is not sent to Copper", highNames.Mining ~= "Copper Ore", highNames.Mining)

--------------------------------------------------------------------------------
-- The search window
--------------------------------------------------------------------------------

UI:Build()
UI:Show()
UI:Search("")
Motion:FinishAll()

suite.check("an empty search shows what to type", UI.empty:IsShown())
suite.check("with suggestions for your level", UI.suggestChips[1] and UI.suggestChips[1]:IsShown())
suite.check("under a caption naming the level",
    (UI.emptyCaption:GetText() or ""):find("LEVEL") ~= nil, UI.emptyCaption:GetText())

-- A suggestion searches for its item.
local chip = UI.suggestChips[1]
chip:GetScript("OnClick")(chip, "LeftButton")
Motion:FinishAll()
suite.check("clicking a suggestion searches for it", UI.lastQuery == chip.itemName, UI.lastQuery)
suite.check("and the empty panel goes", not UI.empty:IsShown())

-- New results arrive; the same results redrawn do not.
UI:Search("linen")
suite.check("new results arrive", UI.lastShape ~= nil and Motion:Running(UI.list.rows[1], "arrive"))
Motion:FinishAll()
UI:Search("linen ")
suite.check("the same results do not arrive again", not Motion:Running(UI.list.rows[1], "arrive"))

-- The item heading carries the item's icon.
local heading
for _, row in ipairs(UI.list.rows) do
    local data = rawget(row, "data")
    if data and data.type == "item" then heading = row break end
end
suite.check("an item heading has its icon", heading and heading.itemIcon:IsShown())
suite.check("and its band", heading and heading.band:IsShown())

-- The gold line along the hanging tabs follows the chosen tab.
local strip = UI.tabStrip
UI:ShowTab("rankings")
Motion:FinishAll()
suite.check("the tab line moves to Rankings", strip.selected == "rankings"
    and strip.lineX == UI.tabs.rankings.left, strip.lineX)
UI:ShowTab("search")
Motion:FinishAll()
suite.check("and back to Search", strip.selected == "search" and strip.lineX == UI.tabs.search.left)

-- Buttons ease under the mouse and back.
local button = ns.Widgets.CreateButton(UI.frame, "Open", function() end)
button:GetScript("OnEnter")(button)
Motion:FinishAll()
suite.check("a button lights under the mouse", Motion:Value(button, "hover") == 1)
button:GetScript("OnLeave")(button)
Motion:FinishAll()
suite.check("and settles when it leaves", Motion:Value(button, "hover") == 0)

--------------------------------------------------------------------------------
-- The other windows
--------------------------------------------------------------------------------

-- Kill some wolves so there is a loot table and a board to draw.
ns.TrackerUI:OnEnable()
local serial = 0
local function Loot(mob, items)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, guid = "M-" .. serial }
    env.world.loot = items
    ns.Tracker:OnLoot()
end
for _ = 1, 21 do Loot("Mangy Wolf", { { name = "10 Copper", money = true } }) end
Motion:FinishAll()

local LTU = ns.LootTableUI
suite.check("the loot table opens", LTU:Show("Mangy Wolf"))
suite.check("counting its kills up", Motion:Running(LTU.kills, "count"))
Motion:FinishAll()
suite.check("and lands on the full count", LTU.kills:GetText() == "21  " .. ns.Util.Colored("good", "+21"),
    LTU.kills:GetText())

-- A redraw while open does not count up again.
LTU:Refresh()
suite.check("a redraw does not count up again", not Motion:Running(LTU.kills, "count"))
LTU:Hide()

-- Rankings: the top of a board wears a medal.
UI:ShowTab("rankings")
Motion:FinishAll()
local medalled
for _, row in ipairs(ns.RankingsUI.list.rows) do
    local data = rawget(row, "data")
    if data and data.entry and data.entry.rank == 1 then medalled = row end
end
suite.check("the top mob has a medal", medalled and medalled.medal:IsShown())
suite.check("three medals, gold first", #ns.RankingsUI.MEDALS == 3
    and ns.RankingsUI.MEDALS[1][1] > ns.RankingsUI.MEDALS[1][3])
UI:ShowTab("search")

-- Settings fades up as it opens and lands fully drawn.
ns.SettingsUI:Show()
Motion:FinishAll()
suite.check("settings opens", ns.SettingsUI.frame:IsShown())

-- Opened again before the first opening lands, a window starts from where it
-- was put, not from a few pixels down, so it never creeps down the screen.
do
    local frame = env.Stub()
    frame:SetPoint("TOPLEFT", nil, "BOTTOMLEFT", 100, 500)
    Motion:Open(frame)
    Motion:Step(0.05)
    Motion:Open(frame)
    Motion:FinishAll()
    local _, _, _, x, y = frame:GetPoint()
    suite.check("reopened mid-opening, it lands where it was", x == 100 and y == 500, y)
end

-- The glow round a window flares as it opens and settles where it rests.
do
    local frame = env.Stub()
    frame:SetPoint("CENTER", nil, "CENTER", 0, 0)
    ns.Theme.Halo(frame, 8, 0.1)
    suite.check("a halo has four sides", #frame.haloTextures == 4)
    local seen = {}
    local SetHalo = ns.Theme.SetHalo
    ns.Theme.SetHalo = function(f, alpha, key) seen[#seen + 1] = alpha; return SetHalo(f, alpha, key) end
    Motion:Open(frame)
    Motion:FinishAll()
    ns.Theme.SetHalo = SetHalo
    suite.check("it flares brighter than it rests", seen[1] and seen[1] > 0.1, seen[1])
    suite.check("and settles at rest", math.abs((seen[#seen] or 0) - 0.1) < 1e-6, seen[#seen])
end

-- A halo in another colour keeps it as it flares, rather than turning gold.
do
    local frame = env.Stub()
    frame:SetPoint("CENTER", nil, "CENTER", 0, 0)
    ns.Theme.Halo(frame, 8, 0.1, "good")
    local keys = {}
    local SetGradientAlpha = ns.Theme.SetGradientAlpha
    ns.Theme.SetGradientAlpha = function(texture, orientation, key, ...)
        keys[key] = true
        return SetGradientAlpha(texture, orientation, key, ...)
    end
    Motion:Open(frame)
    Motion:FinishAll()
    ns.Theme.SetGradientAlpha = SetGradientAlpha
    suite.check("a green halo flares green", keys.good == true and keys.accent == nil)
end

suite.done()
