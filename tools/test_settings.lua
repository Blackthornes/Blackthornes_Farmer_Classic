-- The settings window.
--
-- What matters is that every way in opens it, that each control changes the
-- same saved value its chat command does, that the page shows what is saved
-- rather than what it last drew, and that nothing on it can delete data.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("settings")

local ns = env.Load({ ui = true })
local UI, SettingsUI = ns.UI, ns.SettingsUI

suite.check("the module is loaded", SettingsUI ~= nil)

-- A client with retail's Settings API, recording what is registered.
local registered = {}
_G.Settings = {
    RegisterCanvasLayoutCategory = function(panel, name)
        return { panel = panel, name = name }
    end,
    RegisterAddOnCategory = function(category)
        registered[#registered + 1] = category
    end,
}

-- PLAYER_LOGIN, as the client runs it.
for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

--------------------------------------------------------------------------------
-- Ways in
--------------------------------------------------------------------------------

suite.check("it starts closed", not (SettingsUI.frame and SettingsUI.frame:IsShown()))

ns.HandleSlash("settings")
suite.check("/farm settings opens it", SettingsUI.frame:IsShown())

ns.HandleSlash("settings")
suite.check("typing it again closes it", not SettingsUI.frame:IsShown())

ns.HandleSlash("options")
suite.check("/farm options is the same command", SettingsUI.frame:IsShown())
SettingsUI:Hide()

-- The aliases are not printed as separate lines in /farm help.
local listed = {}
for _, name in ipairs(ns.commandOrder) do listed[name] = true end
suite.check("help lists settings", listed.settings)
suite.check("help does not repeat it as options", not listed.options)

local click = UI.minimapButton:GetScript("OnClick")
click(UI.minimapButton, "RightButton")
suite.check("right-clicking the minimap button opens it", SettingsUI.frame:IsShown())
suite.check("and does not open the search window", not UI.frame:IsShown())
click(UI.minimapButton, "RightButton")
suite.check("right-clicking again closes it", not SettingsUI.frame:IsShown())

click(UI.minimapButton, "LeftButton")
suite.check("left-click still opens the search window", UI.frame:IsShown())
UI:Hide()

suite.check("the search window has a Settings button", UI.settingsButton ~= nil)
UI.settingsButton:GetScript("OnClick")(UI.settingsButton, "LeftButton")
suite.check("which opens it", SettingsUI.frame:IsShown())
SettingsUI:Hide()

suite.check("it is in the game's AddOns options", #registered == 1, #registered)
suite.check("under the addon's name",
    registered[1] and registered[1].name == "Blackthornes Farmer")

--------------------------------------------------------------------------------
-- Controls write what the commands write
--------------------------------------------------------------------------------

SettingsUI:Show()
local controls = SettingsUI.controls

local function Toggle(control)
    control:GetScript("OnClick")(control)
end

-- The minimap button always shows (the owner, 2026-10-15): no row here.
suite.check("there is no minimap row", controls.minimap == nil)
suite.check("the minimap button shows", UI.minimapButton:IsShown())

Toggle(controls.report)
suite.check("chat report writes the /farm report setting", ns.db.trackerReport == true)


Toggle(controls.tracker)
suite.check("the tally box writes the /farm tracker setting", ns.db.trackerHidden == true)
Toggle(controls.tracker)
suite.check("and back", ns.db.trackerHidden == false)

-- Debug and the checks are typed only (the owner, 2026-10-23).
suite.check("there is no debug box", controls.debug == nil)
suite.check("nor a check button", controls.arrowCheck == nil and controls.sparkleCheck == nil
    and controls.harvestCheck == nil and controls.gatheringCheck == nil)
ns.HandleSlash("debug")
suite.check("/farm debug turns debug output on", ns.db.debug == true)
ns.HandleSlash("debug off")
suite.check("and /farm debug off turns it off", ns.db.debug == false)
local helpListsDebug = false
for _, name in ipairs(ns.commandOrder) do
    if name == "debug" then helpListsDebug = true end
end
suite.check("help does not list it", not helpListsDebug)

suite.check("the sister addons box starts ticked", controls.sisters:GetChecked())
Toggle(controls.sisters)
suite.check("unticking it turns the note off", ns.db.sisterNote == false)
Toggle(controls.sisters)
suite.check("and ticking it turns it back on", ns.db.sisterNote == true)

-- Recording.
suite.check("recording starts on", ns.Harvest.enabled and controls.record:GetChecked())
Toggle(controls.record)
suite.check("unticking it pauses recording", ns.Harvest.enabled == false)
suite.check("and remembers that for next login", ns.db.harvestPaused == true)

env.Loot(ns, { name = "Dalaran Apprentice", level = 22, guid = "paused-1" },
    { { name = "Wool Cloth", id = 2592 } })
suite.check("a paused recorder records nothing", ns.Harvest:CountCorpses() == 0,
    ns.Harvest:CountCorpses())

Toggle(controls.record)
suite.check("ticking it resumes", ns.Harvest.enabled and ns.db.harvestPaused == false)

Toggle(controls.celebrate)
suite.check("the fanfare box writes the /farm celebrate setting", ns.db.trackerCelebrate == false)
Toggle(controls.celebrate)
suite.check("and back", ns.db.trackerCelebrate == true)

Toggle(controls.goalsBank)
suite.check("the bank box writes the /farm goal bank setting", ns.Goals:CountsBank() == true)
Toggle(controls.goalsBank)
suite.check("and back", ns.Goals:CountsBank() == false)

--------------------------------------------------------------------------------
-- The pages along the top, as Tradeskills' Settings tab has them
--------------------------------------------------------------------------------

local pages = SettingsUI.pages
suite.check("it opens on the first page", pages.shown == "windows", pages.shown)
suite.check("with the window rows showing", pages.pages.windows.content:IsShown()
    and not pages.pages.tally.content:IsShown())
local tallyPart
for _, part in ipairs(pages.switch) do
    if part.key == "tally" then tallyPart = part end
end
tallyPart.button:GetScript("OnClick")(tallyPart.button)
suite.check("a click on the switch shows that page", pages.pages.tally.content:IsShown()
    and not pages.pages.windows.content:IsShown())
suite.check("and the page is remembered", ns.db.settingsPage == "tally")
suite.check("the page picked is gold", tallyPart.label._color[1] == ns.Theme.colors.accent[1])
SettingsUI:Hide()
SettingsUI:Show()
suite.check("it opens again on the page left", pages.shown == "tally", pages.shown)

-- What a setting does is a tooltip until Show descriptions is ticked.
local reportRow = controls.report._parent
suite.check("descriptions start hidden", ns.db.settingsDescriptions == false
    and not reportRow.hint:IsShown())
GameTooltip._lines = {}
reportRow:GetScript("OnEnter")(reportRow)
suite.check("a row lights under the mouse", reportRow.hover:IsShown())
suite.check("and says what it does in a tooltip", GameTooltip._lines[1] ~= nil
    and GameTooltip._lines[1]:find("for each kill", 1, true) ~= nil, GameTooltip._lines[1])
local before = SettingsUI.frame:GetHeight()
pages.describe:GetScript("OnClick")(pages.describe)
suite.check("Show descriptions is saved", ns.db.settingsDescriptions == true)
suite.check("and puts the words under the rows", reportRow.hint:IsShown())
suite.check("and the window grows to fit them", SettingsUI.frame:GetHeight() > before)
pages.describe:GetScript("OnClick")(pages.describe)
suite.check("unticked, the window goes back", SettingsUI.frame:GetHeight() == before)

-- The kill tally's size buttons sit under its stepper, over its words.
local sizeRow = controls.trackerScale._parent
suite.check("the tally size row makes room for its buttons", sizeRow.compactHeight == 48
    and sizeRow.hint._point[3] == -48, sizeRow.compactHeight)

-- Find a setting.
pages.find:SetText("tomtom")
pages:Search("tomtom")
suite.check("the search shows the page that has it", pages.shown == "map", pages.shown)
local lit = 0
for _, entry in ipairs(pages.searchables) do
    if entry.glow:IsShown() then lit = lit + 1 end
end
suite.check("and lights only what matches", lit == 1, lit)
pages:Search("export")
suite.check("the export button can be found too", pages.shown == "loot", pages.shown)
pages:Search("")
lit = 0
for _, entry in ipairs(pages.searchables) do
    if entry.glow:IsShown() then lit = lit + 1 end
end
suite.check("an empty search lights nothing", lit == 0)

-- Text size, saved as a word, waits for a reload.
controls.textSize:Pick(controls.textSize:GetValue() + 1)
suite.check("Text size saves Large", ns.db.textSize == "large")
suite.check("and offers Reload", controls.textSize.reload:IsShown())
suite.check("under the stepper, at its right edge", controls.textSize.reload._point[1] == "TOPRIGHT"
    and controls.textSize.reload._point[2] == controls.textSize
    and controls.textSize.reload._point[3] == "BOTTOMRIGHT")
suite.check("the Window style's Reload sits the same way", controls.windowStyle.reload._point[1] == "TOPRIGHT"
    and controls.windowStyle.reload._point[2] == controls.windowStyle
    and controls.windowStyle.reload._point[3] == "BOTTOMRIGHT")
controls.textSize:Pick(controls.textSize:GetValue() - 1)
suite.check("back to Normal needs no reload", ns.db.textSize == "normal"
    and not controls.textSize.reload:IsShown())

-- Every /farm command has a button or control here.
local ran = {}
local realSlash = ns.HandleSlash
ns.HandleSlash = function(text) ran[#ran + 1] = text end
local buttons = {
    rankings = "rankings", lootTable = "loot",
    goals = "goals", goalsDock = "goals dock", arrowNext = "arrow next",
    shareSync = "share sync",
    shareGive = "give",
    shareTake = "take",
    hidden = "hidden",
    whatsnew = "whatsnew",
    rankUpShow = "rankup show",
    xpBarTry = "xpbar try",
    topFarmTry = "topfarm test",
    lootFeedMove = "lootfeed move",
    lootFeedReset = "lootfeed reset",
    xpBarReset = "xpbar reset",
    statsTab = "charts",
    killGoal = "killgoal", killGoalSummary = "killgoal summary",
}
local wrong = {}
for key, command in pairs(buttons) do
    ran = {}
    controls[key]:GetScript("OnClick")(controls[key])
    if ran[1] ~= command then wrong[#wrong + 1] = key end
end
ns.HandleSlash = realSlash
suite.check("the command buttons run their commands", #wrong == 0, table.concat(wrong, ", "))

-- Open it opens the search window and leaves it open: /farm on its own
-- toggles, which closed a window already open.
do
    local shown, tab = 0, nil
    local realShow, realShowTab = ns.UI.Show, ns.UI.ShowTab
    ns.UI.Show = function() shown = shown + 1 end
    ns.UI.ShowTab = function(_, key) tab = key end
    controls.openSearch:GetScript("OnClick")(controls.openSearch)
    controls.openSearch:GetScript("OnClick")(controls.openSearch)
    ns.UI.Show, ns.UI.ShowTab = realShow, realShowTab
    suite.check("Open it opens the search window, never closes it", shown == 2 and tab == "search")
end

-- Each command a player can type is reached from the page: by a button
-- above, a control that writes the same setting, or the window itself.
local covered = {
    settings = true, tracker = true, worlddrops = true, report = true, celebrate = true,
    raresound = true, voice = true, effects = true, markers = true, heat = true, tooltip = true, killcount = true, sparkle = true, questcount = true, plates = true, numbers = true,
    seethrough = true, transparent = true, arrow = true, openbutton = true, fishingbar = true, grind = true, trash = true, opennote = true, bagsfull = true, export = true, sisters = true, skinning = true, hide = true, unhide = true,
}
for _, command in pairs(buttons) do covered[command:match("^(%S*)")] = true end
-- Chat-only commands are typed only (the owner, 2026-10-15): the ones that
-- just list things in chat have no button here.
local chatOnly = {
    kills = true, value = true, fishing = true, where = true, goal = true,
    help = true, chat = true, stats = true, data = true, list = true,
    -- The checks too (the owner, 2026-10-23).
    harvest = true, gathering = true,
}
local missing = {}
for _, name in ipairs(ns.commandOrder) do
    if not covered[name] and not chatOnly[name] then missing[#missing + 1] = name end
end
suite.check("the minimap command is gone", not (function()
    for _, name in ipairs(ns.commandOrder) do
        if name == "minimap" then return true end
    end
end)())
suite.check("every /farm command has a button or control", #missing == 0, table.concat(missing, ", "))

--------------------------------------------------------------------------------
-- Sizes
--------------------------------------------------------------------------------

local scaled
UI.frame.SetScale = function(_, value) scaled = value end

local stepper = controls.windowScale
suite.check("the size starts at 100%", stepper:GetValue() == 100, stepper:GetValue())
suite.check("and says so", stepper.text:GetText() == "100%", stepper.text:GetText())

stepper.plus:GetScript("OnClick")(stepper.plus)
suite.check("+ steps the size up", ns.db.windowScale == 110, ns.db.windowScale)
suite.check("and resizes the window", scaled and math.abs(scaled - 1.1) < 1e-9, scaled)

for _ = 1, 20 do stepper.plus:GetScript("OnClick")(stepper.plus) end
suite.check("it stops at the top of its range", ns.db.windowScale == 150, ns.db.windowScale)

for _ = 1, 20 do stepper.minus:GetScript("OnClick")(stepper.minus) end
suite.check("and at the bottom, where the grip stops", ns.db.windowScale == 50, ns.db.windowScale)

stepper:SetValue(103)
suite.check("a dragged size shows as it is", ns.db.windowScale == 103, ns.db.windowScale)
stepper:SetValue(100)

local trackerScaled
ns.TrackerUI:Build().SetScale = function(_, value) trackerScaled = value end
controls.trackerScale.minus:GetScript("OnClick")(controls.trackerScale.minus)
suite.check("the tally has its own size", ns.db.trackerScale == 90 and ns.db.windowScale == 100)
suite.check("which resizes the tally", trackerScaled and math.abs(trackerScaled - 0.9) < 1e-9,
    trackerScaled)

-- Its saved spot is in its own, scaled units: a new size converts it, so the
-- panel stays where it is on screen rather than jumping.
local function Near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-9 end
ns.db.trackerX, ns.db.trackerY = 9, -180
ns.db.trackerGroupX, ns.db.trackerGroupY = 270, 540
controls.trackerScale.plus:GetScript("OnClick")(controls.trackerScale.plus)
suite.check("a bigger tally keeps its spot on screen",
    ns.db.trackerScale == 100 and Near(ns.db.trackerX, 8.1) and Near(ns.db.trackerY, -162),
    tostring(ns.db.trackerX) .. ", " .. tostring(ns.db.trackerY))
suite.check("its spot for groups too",
    Near(ns.db.trackerGroupX, 243) and Near(ns.db.trackerGroupY, 486),
    tostring(ns.db.trackerGroupX) .. ", " .. tostring(ns.db.trackerGroupY))
ns.db.trackerGroupX, ns.db.trackerGroupY = nil, nil

-- At login the saved spot is already in the saved size's units.
ns.db.trackerX = 8
SettingsUI:ApplyTrackerScale()
suite.check("putting the size back at login leaves the spot alone", ns.db.trackerX == 8)

-- The search window the same way.
ns.db.x, ns.db.y = 110, 44
stepper.plus:GetScript("OnClick")(stepper.plus)
suite.check("a bigger search window keeps its spot on screen",
    ns.db.windowScale == 110 and Near(ns.db.x, 100) and Near(ns.db.y, 40),
    tostring(ns.db.x) .. ", " .. tostring(ns.db.y))
stepper.minus:GetScript("OnClick")(stepper.minus)
suite.check("and back", ns.db.windowScale == 100 and Near(ns.db.x, 110), tostring(ns.db.x))

-- Open, it is drawn again, so its columns fit the screen at the new size.
local render = UI.Render
local drawn = 0
UI.Render = function() drawn = drawn + 1 end
UI:Build()
UI.frame:Show()
UI.tab = "search"
stepper.plus:GetScript("OnClick")(stepper.plus)
suite.check("an open search window is drawn again at its new size", drawn == 1, drawn)
UI.frame:Hide()
stepper.minus:GetScript("OnClick")(stepper.minus)
suite.check("a closed one waits until it opens", drawn == 1, drawn)
UI.Render = render

-- The docked goals panel is as wide as the tally on screen: a new size
-- redraws it straight away, not on the next kill.
local GoalsUI = ns.GoalsUI
local goalsFrame, goalsRender = GoalsUI.frame, GoalsUI.Render
local redrawn = false
GoalsUI.frame = env.Stub({ _shown = true })
GoalsUI.lastBase = -1
GoalsUI.Render = function(self) redrawn = true; self.lastBase = self:Width() end
local goalsX = ns.db.goalsX
ns.db.goalsX = nil
controls.trackerScale.minus:GetScript("OnClick")(controls.trackerScale.minus)
suite.check("a new tally size redraws the docked goals panel", redrawn)
controls.trackerScale.plus:GetScript("OnClick")(controls.trackerScale.plus)
GoalsUI.frame, GoalsUI.Render, ns.db.goalsX = goalsFrame, goalsRender, goalsX

--------------------------------------------------------------------------------
-- The page follows the saved values
--------------------------------------------------------------------------------

ns.HandleSlash("report off")
suite.check("typing a command while it is open updates the page",
    controls.report:GetChecked() == false)



ns.HandleSlash("harvest off")
suite.check("/farm harvest off unticks recording", controls.record:GetChecked() == false)
suite.check("and is remembered", ns.db.harvestPaused == true)
ns.HandleSlash("harvest on")
suite.check("/farm harvest on ticks it", controls.record:GetChecked() == true)

--------------------------------------------------------------------------------
-- Positions
--------------------------------------------------------------------------------

ns.db.point, ns.db.x, ns.db.y = "TOPLEFT", 4000, -4000
ns.db.trackerPoint, ns.db.trackerX = "BOTTOM", 9999

SettingsUI:ResetPositions()

suite.check("the search window goes back", ns.db.point == ns.DEFAULTS.point
    and ns.db.x == ns.DEFAULTS.x and ns.db.y == ns.DEFAULTS.y)
suite.check("so does the tally", ns.db.trackerPoint == ns.DEFAULTS.trackerPoint
    and ns.db.trackerX == ns.DEFAULTS.trackerX)

--------------------------------------------------------------------------------
-- Nothing here deletes data
--------------------------------------------------------------------------------

env.Loot(ns, { name = "Dalaran Apprentice", level = 22, guid = "kept-1" },
    { { name = "Wool Cloth", id = 2592 } })
local corpses = ns.Harvest:CountCorpses()
suite.check("recording works again", corpses == 1, corpses)

-- Every button and box on the page, pressed.
for _, control in pairs(controls) do
    local onClick = control.GetScript and control:GetScript("OnClick")
    if onClick then onClick(control) end
end

suite.check("no control on the page clears recorded loot",
    ns.Harvest:CountCorpses() == corpses, ns.Harvest:CountCorpses())

--------------------------------------------------------------------------------
-- The export hint stays inside the window
--
-- On one line it ran past the window's right edge in the game's font.
--------------------------------------------------------------------------------

local hint = SettingsUI.exportHint
local exportButton = hint._point[2]
-- A settings column's width, 310 or more when the switch along the top
-- makes the window wider.
local columnWidth = SettingsUI.pages.opts.columnWidth
suite.check("the export hint is kept to its column beside the button",
    exportButton:GetWidth() + 8 + hint:GetWidth() <= columnWidth, hint:GetWidth())
suite.check("and has room for its text on two lines",
    ns.Theme.TextWidth("tiny", hint:GetText()) <= 2 * hint:GetWidth(), hint:GetText())

--------------------------------------------------------------------------------
-- A client without the options API
--------------------------------------------------------------------------------

_G.Settings = nil
_G.InterfaceOptions_AddCategory = nil
SettingsUI.optionsPanel = nil

local ok, result = pcall(SettingsUI.RegisterGameOptions, SettingsUI)
suite.check("no options API is not an error", ok, result)
suite.check("it just reports it was not registered", result == false)

_G.Settings = { RegisterCanvasLayoutCategory = function() error("nope") end,
    RegisterAddOnCategory = function() end }
SettingsUI.optionsPanel = nil
ok, result = pcall(SettingsUI.RegisterGameOptions, SettingsUI)
suite.check("an options API that raises is not an error either", ok and result == false, result)
_G.Settings = nil

-- A gap below the item above is a step down: a positive one moved the
-- About page's share box up over the Butler line (2026-10-17).
do
    local file = io.open("UI/Settings.lua", "r")
    local source = file and file:read("*a") or ""
    if file then file:close() end
    local upward = {}
    for gap in source:gmatch("pages:Place%b(),?") do
        local n = gap:match(",%s*(%-?%d+)%)$")
        if n and tonumber(n) > 0 then upward[#upward + 1] = gap end
    end
    suite.check("no setting is placed above the one before it", #upward == 0,
        table.concat(upward, " "))
end

--------------------------------------------------------------------------------
-- Even +/- boxes and no empty strip on the right (2026-10-22)
--------------------------------------------------------------------------------

do
    local pages = SettingsUI.pages
    local opts = pages.opts
    local columns = opts.padding * 2 + opts.columnWidth * 2 + opts.columnGap
    suite.check("the two columns reach the switch's width, with no strip left over",
        columns >= pages:BarWidth() - 1, columns .. " vs " .. pages:BarWidth())
    suite.check("the second column starts after the first",
        pages.columnX[2] == opts.padding + opts.columnWidth + opts.columnGap, pages.columnX[2])

    local widths, count = {}, 0
    local seen = {}
    for _, control in pairs(SettingsUI.controls) do
        if type(control) == "table" and control.SetValue and control.GetWidth
            and rawget(control, "value") ~= nil and not seen[control] then
            seen[control] = true
            count = count + 1
            widths[math.floor(control:GetWidth() + 0.5)] = true
        end
    end
    local kinds = 0
    for _ in pairs(widths) do kinds = kinds + 1 end
    suite.check("every +/- box and drop-down on the pages is one width", count > 0 and kinds == 1, count .. " boxes, " .. kinds .. " widths")

    local made = SettingsUI.EvenSteppers({
        { w = 100, GetWidth = function(s) return s.w end, SetWidth = function(s, w) s.w = w end },
        { w = 160, GetWidth = function(s) return s.w end, SetWidth = function(s, w) s.w = w end },
    }, 140)
    suite.check("the widest wins, kept inside the column", made == 140, made)
end

suite.done()
