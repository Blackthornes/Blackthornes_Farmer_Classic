-- See-through for the other panels (UI/SeeThrough.lua, the owner asked
-- 2026-10-16): the goals panel, Where to farm, the rank-up board, the run
-- recap and the XP bar, and the loot feed (2026-10-19).
--
-- What matters: each is off unless picked, so it looks as it always has;
-- each has its own saved key; picked, its dark glass thins to the level and
-- the mouse brings it back; a row made later follows; a shadow a word
-- already had is put back when it is turned off; and the command and
-- Settings write the same keys.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("seethroughpanels")

local ns = env.Load({ ui = true })
local SeeThrough = ns.SeeThrough

-- The loot feed starts at Some (it is new and off until ticked); the
-- checks below start every panel from off.
suite.check("the loot feed starts at Some", SeeThrough:Level("lootfeed") == 1)
ns.db.lootFeedSeeThrough = 0

ns.GoalsUI:Build()
ns.GoalsUI:BuildSpots()
ns.RankUpUI:Build()
ns.RecapUI:Build()
ns.XPBarUI:Build()
ns.LootFeed:Build()

local function Near(a, b) return type(a) == "number" and math.abs(a - b) < 0.001 end
local function Settle() ns.Motion:FinishAll() end

local function Track(id)
    for _, part in ipairs(SeeThrough.states[id].parts) do
        local texture = part.texture
        if not rawget(texture, "_tracked") then
            texture._tracked = true
            texture.SetAlpha = function(self, value) self._alpha = value end
        end
    end
end

local function AllAt(id, shown)
    for _, part in ipairs(SeeThrough.states[id].parts) do
        if not Near(part.texture._alpha, math.max(shown, part.floor)) then return false end
    end
    return true
end

local over = {}
for _, id in ipairs(SeeThrough.ORDER) do
    local state = SeeThrough.states[id]
    suite.check(id .. " is handed over", state and state.frame and state.watch, id)
    suite.check(id .. " has glass", state and #state.parts >= 1, id)
    suite.check(id .. " is off unless picked", SeeThrough:Level(id) == 0
        and ns.db[SeeThrough.PANELS[id].key] == 0, id)
    suite.check(id .. "'s watcher sleeps while off", state.watch:GetScript("OnUpdate") == nil, id)
    state.frame.IsMouseOver = function() return over[id] == true end
end

-- Each key is its own.
local keys = {}
for _, id in ipairs(SeeThrough.ORDER) do keys[SeeThrough.PANELS[id].key] = true end
suite.check("six keys of their own", (function()
    local n = 0
    for _ in pairs(keys) do n = n + 1 end
    return n == 6 and not keys.trackerSeeThrough
end)())

for _, id in ipairs(SeeThrough.ORDER) do
    Track(id)
    SeeThrough:Set(id, 2)
    Settle()
    local keep = SeeThrough.LEVELS[2]
    suite.check(id .. ": More thins its glass", AllAt(id, keep), id)
    suite.check(id .. ": the watcher runs", SeeThrough.states[id].watch:GetScript("OnUpdate") ~= nil, id)

    local watch = SeeThrough.states[id].watch
    over[id] = true
    watch:GetScript("OnUpdate")(watch, 1)
    Settle()
    suite.check(id .. ": the mouse brings the glass back", AllAt(id, 1), id)
    over[id] = false
    watch:GetScript("OnUpdate")(watch, 1)
    Settle()
    suite.check(id .. ": and it goes again", AllAt(id, keep), id)
end

-- Only the panel picked changes.
SeeThrough:Set("goals", 0)
suite.check("turning one off leaves the others", SeeThrough:On("places") and not SeeThrough:On("goals"))
suite.check("off, its glass is solid", AllAt("goals", 1))
suite.check("and its watcher sleeps", SeeThrough.states.goals.watch:GetScript("OnUpdate") == nil)

-- A row made later starts see-through.
SeeThrough:Set("rankup", 3)
Settle()
local row = ns.RankUpUI:Row(40)
local found
for _, part in ipairs(SeeThrough.states.rankup.parts) do
    if part.texture == row.active then found = part end
end
suite.check("a new rank-up row is glass too", found ~= nil)
suite.check("its gold keeps a floor", found and found.floor > SeeThrough.LEVELS[3])

local card = ns.GoalsUI:Card(40)
local cardGlass = false
for _, part in ipairs(SeeThrough.states.goals.parts) do
    if part.texture == card.band then cardGlass = true end
end
suite.check("a new goal card is glass too", cardGlass)

-- A word's own shadow comes back when it is turned off.
local label = {}
label.GetObjectType = function() return "FontString" end
label.GetShadowOffset = function() return 2, -2 end
label.GetShadowColor = function() return 0, 0, 0, 0.9 end
label.SetShadowColor = function(self, r, g, b, a) self.color = { r, g, b, a } end
label.SetShadowOffset = function(self, x, y) self.offset = { x, y } end
local holder = { GetRegions = function() return label end }
SeeThrough.ShadeAll(holder, true)
suite.check("words get a black shadow", label.offset[1] == 1 and label.offset[2] == -1)
SeeThrough.ShadeAll(holder, false)
suite.check("and get their own back after", label.offset[1] == 2 and label.offset[2] == -2
    and Near(label.color[4], 0.9))

-- A level not on the list is refused.
suite.check("a level not on the list is refused", SeeThrough:Set("recap", 9) == false)
suite.check("a panel not on the list is refused", SeeThrough:Set("nope", 1) == false)

-- The command: "transparent" is the word players see; "seethrough" still works.
ns.HandleSlash("transparent goals more")
suite.check("/farm transparent goals more", ns.db.goalsSeeThrough == 2)
ns.HandleSlash("transparent goals off")
suite.check("/farm transparent goals off", ns.db.goalsSeeThrough == 0)
local listed = {}
for _, name in ipairs(ns.commandOrder) do listed[name] = true end
suite.check("help lists transparent, not the old word", listed.transparent and not listed.seethrough)
ns.HandleSlash("seethrough xpbar most")
suite.check("/farm seethrough xpbar most", ns.db.xpBarSeeThrough == 3)
ns.HandleSlash("seethrough xpbar off")
suite.check("/farm seethrough xpbar off", ns.db.xpBarSeeThrough == 0)
SeeThrough:Set("recap", 0)
ns.HandleSlash("seethrough recap")
suite.check("alone it turns it on at More", ns.db.recapSeeThrough == 2)
ns.HandleSlash("seethrough recap")
suite.check("and off again", ns.db.recapSeeThrough == 0)
ns.HandleSlash("seethrough places some")
suite.check("/farm seethrough places some", ns.db.goalSpotsSeeThrough == 1)
ns.HandleSlash("seethrough places nonsense")
suite.check("a word it doesn't know changes nothing", ns.db.goalSpotsSeeThrough == 1)

-- Settings writes the same keys.
ns.SettingsUI:Show()
local controls = ns.SettingsUI.controls
for control, id in pairs({ goalsSeeThrough = "goals", goalSpotsSeeThrough = "places",
    rankUpSeeThrough = "rankup", recapSeeThrough = "recap", xpBarSeeThrough = "xpbar",
    lootFeedSeeThrough = "lootfeed" }) do
    suite.check(control .. " is on the page", controls[control] ~= nil, control)
    if controls[control] then
        controls[control]:SetValue(3)
        suite.check(control .. " writes " .. id, SeeThrough:Level(id) == 3, control)
        controls[control]:SetValue(0)
        suite.check(control .. " turns it off", SeeThrough:Level(id) == 0, control)
    end
end
-- The XP bar thins as a whole, not only its well; its gold keeps enough
-- to read.
local xp = ns.XPBarUI
local fillPart, bandPart
for _, part in ipairs(SeeThrough.states.xpbar.parts) do
    if part.texture == xp.fill then fillPart = part end
    if part.texture == xp.rested then bandPart = part end
end
suite.check("the XP bar's gold is glass", fillPart ~= nil and Near(fillPart.floor, xp.GOLD_FLOOR))
suite.check("and so are its bands", bandPart ~= nil)
Track("xpbar")
SeeThrough:Set("xpbar", 3)
Settle()
suite.check("at Most the gold thins but stays readable", Near(xp.fill._alpha, xp.GOLD_FLOOR)
    and Near(xp.rested._alpha, SeeThrough.LEVELS[3]))
SeeThrough:Set("xpbar", 0)
Settle()
suite.check("off puts the bar back", Near(xp.fill._alpha, 1) and Near(xp.rested._alpha, 1))

-- All six sit together on the UI page (the owner, 2026-10-17).
for _, control in ipairs({ "seeThrough", "goalsSeeThrough", "goalSpotsSeeThrough",
    "rankUpSeeThrough", "recapSeeThrough", "xpBarSeeThrough", "lootFeedSeeThrough" }) do
    local found
    for _, entry in ipairs(ns.SettingsUI.pages.searchables or {}) do
        if entry.frame == controls[control]._parent then found = entry.page end
    end
    suite.check(control .. " is on the General page", found == "general", tostring(found))
end

-- The Kills & Loot row is one stepper over its two keys.
controls.seeThrough:SetValue(3)
suite.check("Kills & Loot Most turns it on", ns.db.trackerSeeThrough == true
    and ns.db.trackerSeeThroughLevel == 3)
controls.seeThrough:SetValue(0)
suite.check("Off turns it off and keeps the level", ns.db.trackerSeeThrough == false
    and ns.db.trackerSeeThroughLevel == 3)
controls.seeThrough:SetValue(1)
suite.check("Some turns it on again", ns.db.trackerSeeThrough == true
    and ns.db.trackerSeeThroughLevel == 1)
controls.seeThrough:SetValue(0)
ns.SettingsUI:Hide()

suite.done()
