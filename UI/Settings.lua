-- Blackthornes Farmer -- UI/Settings.lua
-- The settings window: every switch the addon has, in one place.
--
-- Built the way Tradeskills' Settings tab is (UI/SettingsPages.lua): pages
-- picked along the top, two columns of rows a page, a row being [label ..
-- control] on one line, and what it does in the row's tooltip or, with Show
-- descriptions ticked, underneath it. "Find a setting" searches every page.
--
-- Open it with /farm settings, right-click on the minimap button, the Settings
-- button in the search window, or from the game's own AddOns options list.
-- Every /farm command that changes something has a control here; the ones
-- that only list things in chat are typed (the owner, 2026-10-15).
--
-- Nothing here deletes anything. Wiping kill tallies, recorded loot, fishing,
-- gathering or map markers stays a typed two-word command, so a stray click
-- on this page can never cost data.

local _, ns = ...
local L = ns.L

local SettingsUI = ns.NewModule("SettingsUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local PADDING = 18
local HEADER = 36

local COLUMN_WIDTH = 310
local COLUMN_GAP = 18
-- Where the controls start: room for a label like "Kills and Loot Size:" in the
-- game's font, which runs wider than it looks.
local CONTROL_X = 170
-- As set above; FillBar may widen both to meet the switch along the top.
local BASE_COLUMN_WIDTH, BASE_CONTROL_X = COLUMN_WIDTH, CONTROL_X

-- Window sizes, in percent. Wide enough to matter on a 4K screen or a laptop,
-- narrow enough that neither end breaks the layout.
local SCALE_MIN = 70
local SCALE_MAX = 150
local SCALE_STEP = 10

local TITLE = "Blackthornes Farmer"

-- The pages along the top (UI/SettingsPages.lua), as Tradeskills' Settings
-- tab has them. Every setting kept its saved name; only its place moved.
local PAGES = {
    { key = "windows", text = L["UI"],
      tip = L["Window sizes and places, effects, text size and Farmer's windows"] },
    { key = "tally", text = L["KILLS"],
      tip = L["The kills and loot panel, its sounds, your top 15 and the XP bar"] },
    { key = "loot", text = L["LOOT"],
      tip = L["Recording what drops and its export, fishing and gathering, and skinning"] },
    { key = "map", text = L["MAP & GOALS"],
      tip = L["Node markers, grinding camps, goals and the goal arrow"] },
    { key = "sharing", text = L["SHARING"],
      tip = L["Share kills, drop rates and gathering with your other account"] },
    { key = "advanced", text = L["ADVANCED"],
      tip = L["The sister addons and What's New"] },
    { key = "about", text = L["ABOUT"],
      tip = L["How these addons are made, the version, the Discord and the other Blackthornes addons"] },
}

--------------------------------------------------------------------------------
-- Layout helpers
--------------------------------------------------------------------------------

--- Make room in a row for a second line of controls under its first, the
--- description moving down by `by`. Call it before anything changes the
--- row's description.
local function GrowRow(row, by)
    local top = row.compactHeight
    row.hint:ClearAllPoints()
    row.hint:SetPoint("TOPLEFT", 0, -(top + by))
    row.compactHeight = top + by
    row.fullHeight = row.fullHeight + by
    local described = ns.db and ns.db.settingsDescriptions == true
    row.shownHeight = described and row.fullHeight or row.compactHeight
    row:SetHeight(row.shownHeight)
end

--- A button on `row` that runs a /farm command, at `x` (CONTROL_X unless
--- given).
local function CommandButton(row, text, command, width, x)
    local button = Widgets.CreateButton(row, text, function()
        if type(command) == "function" then command() else ns.HandleSlash(command) end
    end, { width = width or 100, height = 20 })
    button:SetPoint("TOPLEFT", x or CONTROL_X, 0)
    return button
end

--- A row whose button runs a /farm command.
--- A "Transparent:" drop-down for one panel (UI/SeeThrough.lua): Off, Some,
--- More or Most clear.
local function SeeThroughRow(pages, page, column, id, label, description)
    local row = pages:Row(page, column, label, description)
    local names = ns.SeeThrough.Names()
    local stepper = Widgets.CreateChoice(row, {
        min = 0, max = #ns.SeeThrough.LEVELS, step = 1, value = 0,
        format = function(index) return names[index] end,
        onChange = function(index) ns.SeeThrough:Set(id, index) end,
    })
    ns.SettingsPages.FitStepper(stepper, { names[0], names[1], names[2], names[3] })
    stepper:SetPoint("TOPLEFT", CONTROL_X, -2)
    return stepper
end

--- An Off, Shift or Always drop-down for one tooltip line (UI/TooltipShift.lua).
--- `isOn()` reads the line's own setting and `setOn(on)` is its old tick box.
local function TooltipShiftStepper(row, key, isOn, setOn)
    local Shift = ns.TooltipShift
    local names = Shift.NAMES
    local stepper = Widgets.CreateChoice(row, {
        min = 0, max = 2, step = 1, value = Shift:Mode(isOn(), key),
        format = function(index) return names[index] end,
        onChange = function(index) Shift:Apply(index, key, isOn(), setOn) end,
    })
    ns.SettingsPages.FitStepper(stepper, { names[0], names[1], names[2] })
    stepper:SetPoint("TOPLEFT", CONTROL_X, -2)
    stepper.shiftKey, stepper.isOn = key, isOn
    return stepper
end

local function CommandRow(pages, page, column, label, description, buttonText, command)
    local row = pages:Row(page, column, label, description)
    return row, CommandButton(row, buttonText, command)
end

local function Percent(value)
    return ("%d%%"):format(value)
end

--------------------------------------------------------------------------------
-- Applying settings
--
-- Each of these is what one control does, kept apart from the control so the
-- tests can drive them and so a chat command could share them later.
--------------------------------------------------------------------------------

--- Saved spots are offsets in the window's own, scaled units, so a new size
--- would move it on screen. Changed from `from` percent to `to`, the keys
--- named are converted so the window's anchor stays where it is.
function SettingsUI.KeepSpot(keys, from, to)
    local db = ns.db
    if not (type(from) == "number" and type(to) == "number" and from > 0 and to > 0)
        or from == to then
        return
    end

    local ratio = from / to
    for _, key in ipairs(keys) do
        if type(db[key]) == "number" then db[key] = db[key] * ratio end
    end
end

--- `previous` is the size it had, when a player has just changed it; the
--- window then stays where it is on screen. Without it (at login) the saved
--- spot is already in the saved size's units.
function SettingsUI:ApplyWindowScale(previous)
    -- Converted even while the window is not built yet: it opens at the new size.
    if previous then SettingsUI.KeepSpot({ "x", "y" }, previous, ns.db.windowScale or 100) end

    local UI = ns.UI
    if UI and UI.frame then
        UI.frame:SetScale((ns.db.windowScale or 100) / 100)
        if previous and UI.RestorePosition then UI:RestorePosition() end

        -- Its columns are capped to what fits on screen at its size: drawn
        -- again, or a bigger window runs off the edge until the next search.
        if previous and UI.frame:IsShown() then
            if UI.tab == "rankings" and ns.RankingsUI then
                pcall(ns.RankingsUI.Render, ns.RankingsUI)
            elseif UI.Render then
                pcall(UI.Render, UI)
            end
        end
    end
end

--- `previous` is the size it had, when a player has just changed it; the
--- panel then stays where it is on screen. Without it (at login) the saved
--- spot is already in the saved size's units.
function SettingsUI:ApplyTrackerScale(previous)
    local TrackerUI = ns.TrackerUI
    if not TrackerUI then return end

    -- The tally panel is built lazily on some versions of it; building it
    -- early is harmless (it starts hidden) and means the size is right the
    -- first time it appears.
    local frame = TrackerUI.frame or (TrackerUI.Build and TrackerUI:Build())
    if frame then
        -- The saved size, kept on the screen (TrackerUI:DrawnPercent).
        local percent = TrackerUI.DrawnPercent and TrackerUI:DrawnPercent() or (ns.db.trackerScale or 100)
        if previous then
            SettingsUI.KeepSpot({ "trackerX", "trackerY", "trackerGroupX", "trackerGroupY" },
                previous, percent)
        end
        frame:SetScale(percent / 100)
        -- A new size can change whether it overlaps the group frames.
        if TrackerUI.Place then TrackerUI:Place() end
        -- The docked goals panel is as wide as this one is on screen.
        if TrackerUI.FollowGoals then TrackerUI:FollowGoals() end
    end
end

--- Show or put away the kill tally panel, exactly as /farm tracker does.
function SettingsUI:SetTrackerShown(shown)
    ns.db.trackerHidden = not shown

    local TrackerUI = ns.TrackerUI
    if not TrackerUI then return end

    if TrackerUI.Refresh then
        -- The docked panel decides for itself whether it has anything to show.
        TrackerUI:Refresh()
    elseif not shown then
        TrackerUI:Hide()
    elseif ns.Tracker and ns.Tracker.current and TrackerUI.ShowMob then
        TrackerUI:ShowMob(ns.Tracker.current)
    end
end

--- Pause or resume loot recording, and remember the choice across sessions.
function SettingsUI:SetRecording(on)
    ns.db.harvestPaused = not on

    if ns.Harvest:Capabilities().usable then
        ns.Harvest.enabled = on and true or false
    end
end

--- Put the search window and the tally panel back where, and how big, they
--- started.
function SettingsUI:ResetPositions()
    local defaults = ns.DEFAULTS
    local db = ns.db

    for _, key in ipairs({ "point", "relativePoint", "x", "y",
        "trackerPoint", "trackerX", "trackerY" }) do
        db[key] = defaults[key]
    end

    -- The search window's kept width goes too; the tabs grow it again from
    -- the next login, as wide as they need (UI:Claim).
    db.windowWidth = nil

    -- This window too: it goes back to the middle of the screen.
    db.settingsPoint = nil
    db.settingsRelativePoint = nil
    db.settingsX = nil
    db.settingsY = nil

    -- Not in the defaults: the tally anchors to its own point when this is
    -- absent, which is where it started.
    db.trackerRelativePoint = nil

    -- And its size, back to where it started.
    db.trackerWidth = nil
    db.trackerHeight = nil

    -- A spot picked for groups goes too; it goes back beside the group frames.
    db.trackerGroupX = nil
    db.trackerGroupY = nil

    if ns.UI and ns.UI.frame then ns.UI:RestorePosition() end

    if ns.TrackerUI and ns.TrackerUI.frame and ns.TrackerUI.RestorePosition then
        ns.TrackerUI:RestorePosition()
        if ns.TrackerUI.Place then ns.TrackerUI:Place() end
        if ns.TrackerUI.Refresh then ns.TrackerUI:Refresh() end
    end

    -- The goals panel goes back under the kills panel.
    if ns.GoalsUI and ns.GoalsUI.frame then ns.GoalsUI:Dock() end

    -- The loot feed goes back to its first place and size.
    if ns.LootFeed then ns.LootFeed:ResetPlace() end

    -- The goal arrow goes back to the top middle.
    if ns.ArrowUI then ns.ArrowUI:ResetPosition() end

    self:RestorePosition()
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------


--- When the switch along the top is wider than the two columns, the
--- columns grow to meet it, so no empty strip is left down the right
--- (2026-10-22). Half the room goes to the labels, half to the controls.
function SettingsUI:FillBar()
    local pages = self.pages
    if not (pages and pages.BarWidth) then return end
    COLUMN_WIDTH, CONTROL_X = BASE_COLUMN_WIDTH, BASE_CONTROL_X
    local natural = PADDING * 2 + COLUMN_WIDTH * 2 + COLUMN_GAP
    local ok, bar = pcall(pages.BarWidth, pages)
    if not ok or type(bar) ~= "number" or bar <= natural then return end
    local grow = math.floor((bar - natural) / 2)
    COLUMN_WIDTH = COLUMN_WIDTH + grow
    CONTROL_X = CONTROL_X + math.floor(grow / 2)
    pages.opts.columnWidth = COLUMN_WIDTH
    pages.opts.controlX = CONTROL_X
    pages.columnX[2] = PADDING + COLUMN_WIDTH + COLUMN_GAP
end

--- Give every stepper the widest one's width, never past `room`.
function SettingsUI.EvenSteppers(steppers, room)
    local widest = 0
    for _, stepper in ipairs(steppers) do
        local width = stepper.GetWidth and stepper:GetWidth()
        if type(width) == "number" and width > widest then widest = width end
    end
    if widest <= 0 then return end
    if type(room) == "number" and room > 0 then widest = math.min(widest, room) end
    for _, stepper in ipairs(steppers) do
        if stepper.SetWidth then stepper:SetWidth(widest) end
    end
    return widest
end

function SettingsUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesFarmerSettings", UIParent)
    frame:SetSize(COLUMN_WIDTH * 2 + COLUMN_GAP + PADDING * 2, 600)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    Theme.Fill(frame, "window")
    -- The house frame (UI/Titanforged.lua): the gold rim and corner gems,
    -- the name on a plate across the top and a red close gem.
    if ns.Titanforged then
        self.trim = ns.Titanforged:Dress(frame, {
            title = L["Farmer Settings"],
            close = function() SettingsUI:Hide() end,
        })
        local left, right, top, bottom = ns.Titanforged.Reach(self.trim)
        if frame.SetClampRectInsets then
            pcall(frame.SetClampRectInsets, frame, -left, right, top, -bottom)
        end
    else
        Theme.Border(frame, "borderLit")
    end
    Theme.Halo(frame, 8, 0.10)

    frame:SetScript("OnDragStart", function(self)
        -- Land an opening still running, or it would pull the window back.
        ns.Motion:Stop(self, "open", true)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SettingsUI:SavePosition()
    end)

    -- Escape closes it, like the game's own windows (see UI/Main.lua for
    -- why the keyboard is not taken instead).
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesFarmerSettings")
    end

    self.frame = frame
    self.controls = {}

    self:BuildHeader()

    self.pages = ns.SettingsPages.New(frame, {
        pages = PAGES,
        top = HEADER + 4,
        bottom = 48,
        padding = PADDING,
        columnWidth = COLUMN_WIDTH,
        columnGap = COLUMN_GAP,
        controlX = CONTROL_X,
        db = function() return ns.db end,
    })
    self:FillBar()

    -- Every +/- box and drop-down on every page comes out the same width,
    -- the widest one's, so they line up down the page (2026-10-22).
    local steppers = {}
    local makeStepper, makeChoice = Widgets.CreateStepper, Widgets.CreateChoice
    Widgets.CreateStepper = function(...)
        local stepper = makeStepper(...)
        steppers[#steppers + 1] = stepper
        return stepper
    end
    Widgets.CreateChoice = function(...)
        local choice = makeChoice(...)
        steppers[#steppers + 1] = choice
        return choice
    end
    local built, problem = pcall(function()
        self:BuildWindowsPage()
        self:BuildTallyPage()
        self:BuildLootPage()
        self:BuildMapPage()
        self:BuildSharingPage()
        self:BuildAdvancedPage()
        self:BuildAboutPage()
    end)
    Widgets.CreateStepper, Widgets.CreateChoice = makeStepper, makeChoice
    if not built then error(problem, 0) end
    SettingsUI.EvenSteppers(steppers, COLUMN_WIDTH - CONTROL_X)
    self.pages:Fit()

    -- The house size grip under the bottom right corner
    -- (Widgets.CreateSizeGrip), saved as `settingsScale`.
    local below = 0
    if self.trim and ns.Titanforged and ns.Titanforged.Reach then
        local _, _, _, bottom = ns.Titanforged.Reach(self.trim)
        if type(bottom) == "number" then below = bottom end
    end
    Widgets.ApplySize(frame, ns.db and ns.db.settingsScale)
    self.sizeGrip = Widgets.CreateSizeGrip(frame, {
        below = below,
        get = function() return ns.db and ns.db.settingsScale end,
        save = function(percent) if ns.db then ns.db.settingsScale = percent end end,
        done = function() SettingsUI:SavePosition() end,
    })

    local footer = Theme.CreateLabel(frame, "tiny", "dim")
    footer:SetPoint("BOTTOMLEFT", PADDING, 10)
    footer:SetPoint("BOTTOMRIGHT", -PADDING, 10)
    -- Two lines if it needs them, rather than cut off.
    footer:SetHeight(26)
    footer:SetWordWrap(true)
    footer:SetJustifyV("BOTTOM")
    footer:SetText(L["Changes save as you make them. Nothing here can delete your data. Clearing tallies or recorded loot takes a typed command."])
    self.footer = footer

    frame:Hide()
    return frame
end

function SettingsUI:BuildHeader()
    local frame = self.frame

    -- The window's name is on the plate across the top edge and the close
    -- gem on its corner (UI/Titanforged.lua), so the header keeps only the
    -- version, under the gem, over a gold rule fading from the left. Inside
    -- the rim, which a header out to the edge would cover.
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 8, -8)
    header:SetPoint("TOPRIGHT", -8, -8)
    header:SetHeight(HEADER - 8)

    local version = Theme.CreateLabel(header, "tiny", "dim", "RIGHT")
    version:SetPoint("BOTTOMRIGHT", -PADDING + 8, 6)
    version:SetText(ns.VersionLabel())

    local rule = header:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    Theme.SetGradientAlpha(rule, "HORIZONTAL", "accent", 0.6, 0.05)
end

--- UI: how the addon looks and where things sit.
function SettingsUI:BuildWindowsPage()
    local controls = self.controls
    local pages = self.pages

    pages:Section("windows", 1, L["WINDOWS"])

    -- The minimap button always shows (the owner, 2026-10-15), so it has no
    -- row here any more.
    local windowScaleRow = pages:Row("windows", 1, L["Window Size:"], nil)

    -- Any percent the window's grip can drag to, one dragged to shown as it is.
    controls.windowScale = Widgets.CreateStepper(windowScaleRow, {
        min = Widgets.SIZE_MIN or SCALE_MIN, max = Widgets.SIZE_MAX or SCALE_MAX,
        step = SCALE_STEP, value = 100, exact = true,
        format = Percent,
        onChange = function(value)
            local previous = ns.db.windowScale or 100
            ns.db.windowScale = value
            SettingsUI:ApplyWindowScale(previous)
        end,
    })
    controls.windowScale:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- The kills and loot panel's size, which its gold corner grip and
    -- /farm tracker size set too (the owner asked 2026-10-07): any percent
    -- from 50 to 150 on the stepper, one dragged to shown as it is, and
    -- Small, Normal and Large under it, the one in use lit green.
    local TrackerUI = ns.TrackerUI
    local trackerScaleRow = pages:Row("windows", 1, L["Kills and Loot Size:"], nil)

    controls.trackerScale = Widgets.CreateStepper(trackerScaleRow, {
        min = TrackerUI and TrackerUI.SCALE_MIN or SCALE_MIN,
        max = TrackerUI and TrackerUI.SCALE_MAX or SCALE_MAX,
        step = SCALE_STEP, value = 100, exact = true,
        format = Percent,
        onChange = function(value)
            if TrackerUI and TrackerUI.SetScalePercent then
                TrackerUI:SetScalePercent(value)
            else
                local previous = ns.db.trackerScale or 100
                ns.db.trackerScale = value
                SettingsUI:ApplyTrackerScale(previous)
            end
        end,
    })
    controls.trackerScale:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- The three named sizes, in a line under the stepper, ending where it
    -- ends. The row grows to fit them over its description. No hover: the
    -- names say it (the owner, 2026-10-15).
    controls.trackerSizes = {}
    local after
    for index = #(TrackerUI and TrackerUI.SIZES or {}), 1, -1 do
        local size = TrackerUI.SIZES[index]
        local button = Widgets.CreateButton(trackerScaleRow, size.text, function()
            ns.HandleSlash("tracker size " .. size.key)
        end, { width = 44, height = 18 })
        if after then
            button:SetPoint("RIGHT", after, "LEFT", -4, 0)
        else
            button:SetPoint("TOPRIGHT", controls.trackerScale, "BOTTOMRIGHT", 0, -4)
        end
        button.percent = size.percent
        controls.trackerSizes[index] = button
        after = button
    end
    if after then GrowRow(trackerScaleRow, 24) end

    local positionRow = pages:Row("windows", 1, L["Window Positions:"],
        L["Reset the UI windows to their defaults."])

    local reset = Widgets.CreateButton(positionRow, L["Set Default"], function()
        SettingsUI:ResetPositions()
        ns.Print(L["UI windows set to defaults."])
    end, { width = 110, height = 20 })
    reset:SetPoint("TOPLEFT", CONTROL_X, 0)
    controls.resetPositions = reset

    -- Every panel that stays on screen can let the world show through, all
    -- in one place (the owner, 2026-10-17). The glass comes back while the
    -- mouse is on a panel. The saved keys keep their see-through names.
    pages:Section("windows", 1, L["TRANSPARENT"])

    local trackerRow = pages:Row("windows", 1, L["Kills & Loot:"],
        L["Lets the world show through the panel. It goes dark again while your mouse is on it."])
    local names = ns.SeeThrough.Names()
    controls.seeThrough = Widgets.CreateChoice(trackerRow, {
        min = 0, max = #ns.TrackerUI.SEE_THROUGH_LEVELS, step = 1, value = 0,
        format = function(index) return names[index] end,
        onChange = function(index)
            if index > 0 then ns.TrackerUI:SetSeeThroughLevel(index) end
            ns.TrackerUI:SetSeeThrough(index > 0)
        end,
    })
    ns.SettingsPages.FitStepper(controls.seeThrough, { names[0], names[1], names[2], names[3] })
    controls.seeThrough:SetPoint("TOPLEFT", CONTROL_X, -2)

    controls.goalsSeeThrough = SeeThroughRow(pages, "windows", 1, "goals", L["Goals:"], nil)
    controls.goalSpotsSeeThrough = SeeThroughRow(pages, "windows", 1, "places", L["Where to Farm:"], nil)
    controls.rankUpSeeThrough = SeeThroughRow(pages, "windows", 1, "rankup", L["Top 15:"], nil)
    controls.recapSeeThrough = SeeThroughRow(pages, "windows", 1, "recap", L["Run Recap:"], nil)
    controls.xpBarSeeThrough = SeeThroughRow(pages, "windows", 1, "xpbar", L["XP Bar:"], nil)
    controls.lootFeedSeeThrough = SeeThroughRow(pages, "windows", 1, "lootfeed", L["Loot Feed:"], nil)

    pages:Section("windows", 2, L["EFFECTS"])

    -- Every window and both panels follow it, so it sits with the windows
    -- rather than under the kill tally. The saved key keeps its old name.
    local effectsRow = pages:Row("windows", 2, L["Effects:"], nil)

    local FX = ns.TrackerFX
    controls.effects = Widgets.CreateChoice(effectsRow, {
        min = 1, max = #FX.LEVELS, step = 1, value = #FX.LEVELS,
        format = function(index) return FX.LEVEL_NAMES[FX.LEVELS[index]] end,
        onChange = function(index) FX:SetLevel(FX.LEVELS[index]) end,
    })
    controls.effects:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- Bigger letters in the same windows, as Tradeskills has. Every size
    -- is read as text is drawn, so it waits for /reload.
    local textRow = pages:Row("windows", 2, L["Text Size:"], nil)
    controls.textSize = ns.SettingsPages.TextSizeControl(textRow, CONTROL_X, function() return ns.db end)

    -- Asked 2026-10-10: the game's own look for players who would rather
    -- the windows matched the rest of their screen. Read at login, so it
    -- waits for /reload as Text size does. See UI/BlizzardLook.lua.
    local styleRow = pages:Row("windows", 2, L["Window Style:"], nil)
    controls.windowStyle = SettingsUI:WindowStyleControl(styleRow)

    pages:Section("windows", 2, L["FARMER UI"])

    local _, searchButton = CommandRow(pages, "windows", 2, L["Farmer:"], nil, L["Open"], function()
            -- /farm on its own toggles the window, so with it already open
            -- this closed it. It opens it, on the Search tab.
            ns.UI:Show()
            ns.UI:ShowTab("search")
        end)
    controls.openSearch = searchButton

    local _, rankingsButton = CommandRow(pages, "windows", 2, L["Rankings:"], nil, L["Open"], "rankings")
    controls.rankings = rankingsButton

    -- The owner, 2026-10-14: Rankings without the mobs found only in dungeons.
    local outsideRow = pages:Row("windows", 2, L["Skip Dungeon Mobs:"],
        L["Rankings leave out mobs you only found in dungeons and raids."])
    controls.rankingsOutside = Widgets.CreateCheckbox(outsideRow, L["On"], function(checked)
        ns.Rankings:SetOutsideOnly(checked)
    end, false)
    controls.rankingsOutside:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The owner, 2026-10-18: worth per kill without Uncommon and better drops.
    local uncommonRow = pages:Row("windows", 2, L["Skip Uncommon Drops:"],
        L["Worth per kill leaves out Uncommon, Rare and Epic drops."])
    controls.rankingsSkipUncommon = Widgets.CreateCheckbox(uncommonRow, L["On"], function(checked)
        ns.Rankings:SetSkipUncommon(checked)
    end, false)
    controls.rankingsSkipUncommon:SetPoint("TOPLEFT", CONTROL_X, -2)

    local _, statsButton = CommandRow(pages, "windows", 2, L["Stats:"], nil, L["Open"], "charts")
    controls.statsTab = statsButton
end

-- The window styles in the order the stepper steps through them.
local WINDOW_STYLES = { "titanforged", "blizzard" }
local WINDOW_STYLE_NAMES = { titanforged = "Titanforged", blizzard = "Blizzard" }

--- The Window style row's control: a drop-down of Titanforged and
--- Blizzard, as Text size beside it is, with Reload under it while the
--- pick differs from what is drawn. :Sync() reads the saved pick back.
function SettingsUI:WindowStyleControl(row)
    local Look = ns.BlizzardLook
    local function Drawn() return Look and Look.Style() or "titanforged" end

    local reload
    local stepper = Widgets.CreateChoice(row, {
        min = 1, max = #WINDOW_STYLES, step = 1,
        format = function(value) return WINDOW_STYLE_NAMES[WINDOW_STYLES[value]] end,
        onChange = function(value)
            ns.db.windowStyle = WINDOW_STYLES[value]
            reload:SetShown(WINDOW_STYLES[value] ~= Drawn())
        end,
    })
    ns.SettingsPages.FitStepper(stepper, WINDOW_STYLE_NAMES)
    stepper:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- ReloadUI is allowed from a click, and saves everything first.
    reload = Widgets.CreateButton(row, L["Reload"], function()
        if ReloadUI then ReloadUI() end
    end, { width = 60, height = 20 })
    ns.SettingsPages.ReloadUnder(row, stepper, reload)
    reload:Hide()
    stepper.reload = reload

    function stepper:Sync()
        local wanted = Look and Look.Wanted() or "titanforged"
        local index = 1
        for i, key in ipairs(WINDOW_STYLES) do
            if key == wanted then index = i end
        end
        self:SetValue(index, true)
        reload:SetShown(wanted ~= Drawn())
    end

    return stepper
end

--- Kills: the kills and loot panel and what it says.
function SettingsUI:BuildTallyPage()
    local controls = self.controls
    local pages = self.pages

    pages:Section("tally", 1, L["KILLS AND LOOT"])

    local trackerRow = pages:Row("tally", 1, L["Kills and Loot:"], nil)

    controls.tracker = Widgets.CreateCheckbox(trackerRow, L["Show"], function(checked)
        SettingsUI:SetTrackerShown(checked)
    end, true)
    controls.tracker:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Only what the panel shows: every tally stays, so it is no reset. The
    -- button has its own hover, so the row has none.
    local clearRow = pages:Row("tally", 1, L["Clear Panel:"], nil)

    controls.clearPanel = ns.TrackerUI.ClearButton(clearRow, 64, 20)
    controls.clearPanel:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- Off by default: the panel starts empty at every login and /reload.
    local keepRow = pages:Row("tally", 1, L["Keep After Logout:"],
        L["Keeps the panel's kills and loot until you clear it."])

    controls.keepPanel = Widgets.CreateCheckbox(keepRow, L["On"], function(checked)
        ns.db.keepPanel = checked
    end, false)
    controls.keepPanel:SetPoint("TOPLEFT", CONTROL_X, -2)

    local groupRow = pages:Row("tally", 1, L["Move in a Group:"],
        L["Moves the panel away from party and raid frames. Drag it while in a group to pick the spot."])

    controls.dodgeGroup = Widgets.CreateCheckbox(groupRow, L["On"], function(checked)
        ns.TrackerUI:SetDodgeGroup(checked)
    end, true)
    controls.dodgeGroup:SetPoint("TOPLEFT", CONTROL_X, -2)

    local reportRow = pages:Row("tally", 1, L["Kills in Chat:"],
        L["Adds a line to your chat for each kill."])

    controls.report = Widgets.CreateCheckbox(reportRow, L["On"], function(checked)
        ns.db.trackerReport = checked
    end, false)
    controls.report:SetPoint("TOPLEFT", CONTROL_X, -2)

    local celebrateRow = pages:Row("tally", 1, L["Milestone Fanfare:"],
        L["A cheer when a mob, fishing spot or node hits 20 and its drop rates show."])

    controls.celebrate = Widgets.CreateCheckbox(celebrateRow, L["On"], function(checked)
        ns.db.trackerCelebrate = checked
    end, true)
    controls.celebrate:SetPoint("TOPLEFT", CONTROL_X, -2)

    local rareRow = pages:Row("tally", 1, L["Rare Drop Sound:"],
        L["A chime when something green or better drops."])

    controls.rareSound = Widgets.CreateCheckbox(rareRow, L["On"], function(checked)
        ns.db.trackerRareSound = checked
    end, true)
    controls.rareSound:SetPoint("TOPLEFT", CONTROL_X, -2)

    local rankUpRow = pages:Row("tally", 1, L["Rank-Up Pop-Up:"],
        L["Shows your top 15 for a moment when a kill moves a mob up."])

    controls.rankUp = Widgets.CreateCheckbox(rankUpRow, L["On"], function(checked)
        ns.db.rankUpPopup = checked
        if not checked and ns.RankUpUI then ns.RankUpUI:Hide() end
    end, true)
    controls.rankUp:SetPoint("TOPLEFT", CONTROL_X, -2)

    local rankUpSoundRow = pages:Row("tally", 1, L["Rank-Up Sound:"],
        L["A chime when a mob moves up your top 15."])

    controls.rankUpSound = Widgets.CreateCheckbox(rankUpSoundRow, L["On"], function(checked)
        ns.db.rankUpSound = checked
    end, true)
    controls.rankUpSound:SetPoint("TOPLEFT", CONTROL_X, -2)

    local bestRow = pages:Row("tally", 1, L["Best Session Cheer:"],
        L["A cheer when you beat your best gold an hour."])

    controls.statsBestCheer = Widgets.CreateCheckbox(bestRow, L["On"], function(checked)
        ns.db.statsBestCheer = checked
    end, true)
    controls.statsBestCheer:SetPoint("TOPLEFT", CONTROL_X, -2)

    local voiceRow = pages:Row("tally", 1, L["Voice Lines:"],
        L["A voice cheers big drops and finished goals."])

    controls.voice = Widgets.CreateCheckbox(voiceRow, L["On"], function(checked)
        ns.db.trackerVoice = checked
    end, true)
    controls.voice:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The mob you last looted, as the commands read it with no name. The
    -- chat-only lists stay typed commands (the owner, 2026-10-15).
    pages:Section("tally", 2, L["LAST MOB"])

    local _, lootButton = CommandRow(pages, "tally", 2, L["Loot Table:"],
        L["The full loot table of the mob you last looted."], L["Open"], "loot")
    controls.lootTable = lootButton

    pages:Section("tally", 2, L["TOP 15"])

    local _, topButton = CommandRow(pages, "tally", 2, L["Top 15:"], nil, L["Show"], "rankup show")
    controls.rankUpShow = topButton

    -- After an auction scan (Logic/TopFarm.lua, the owner asked 2026-10-14).
    local topFarmRow = pages:Row("tally", 2, L["After an Auction Scan:"],
        L["Your top 15 updates to the new prices after a scan. Only mobs you've killed 20 times count."])
    controls.topFarm = Widgets.CreateCheckbox(topFarmRow, L["On"], function(checked)
        ns.TopFarm:SetOn(checked)
    end, true)
    controls.topFarm:SetPoint("TOPLEFT", CONTROL_X, -2)
    controls.topFarmTry = CommandButton(topFarmRow, L["Try"], "topfarm test", 60, CONTROL_X + 70)

    -- The XP bar (UI/XPBar.lua, the owner asked 2026-10-13).
    pages:Section("tally", 2, L["XP BAR"])

    local xpRow = pages:Row("tally", 2, L["XP Bar:"],
        L["Shows your level, quest and rested XP, and about when you'll level. Drag it to move it."])
    controls.xpBar = Widgets.CreateCheckbox(xpRow, L["On"], function(checked)
        ns.XPBarUI:SetOn(checked)
    end, true)
    controls.xpBar:SetPoint("TOPLEFT", CONTROL_X, -2)

    local cheerRow = pages:Row("tally", 2, L["Level-Up Cheer:"],
        L["A card when you level up."])
    controls.xpBarCheer = Widgets.CreateCheckbox(cheerRow, L["On"], function(checked)
        ns.db.xpBarCheer = checked
    end, true)
    controls.xpBarCheer:SetPoint("TOPLEFT", CONTROL_X, -2)
    controls.xpBarTry = CommandButton(cheerRow, L["Try"], "xpbar try", 60, CONTROL_X + 70)

    local chimeRow = pages:Row("tally", 2, L["Chime Every Tenth:"],
        L["A soft chime at each tenth of a level."])
    controls.xpBarChime = Widgets.CreateCheckbox(chimeRow, L["On"], function(checked)
        ns.db.xpBarChime = checked
    end, true)
    controls.xpBarChime:SetPoint("TOPLEFT", CONTROL_X, -2)

    local gameRow = pages:Row("tally", 2, L["Hide Game's XP Bar:"],
        L["Hides the game's XP and reputation bars while yours shows."])
    controls.xpBarHideGame = Widgets.CreateCheckbox(gameRow, L["On"], function(checked)
        ns.XPBarUI:SetHideGame(checked)
    end, false)
    controls.xpBarHideGame:SetPoint("TOPLEFT", CONTROL_X, -2)

    local _, resetButton = CommandRow(pages, "tally", 2, L["XP Bar Position:"], nil,
        L["Set Default"], "xpbar reset")
    controls.xpBarReset = resetButton
end

--- Loot: recording what drops, its export, fishing and gathering.
function SettingsUI:BuildLootPage()
    local controls = self.controls
    local pages = self.pages

    pages:Section("loot", 1, L["LOOT RECORDING"])

    local recordRow = pages:Row("loot", 1, L["Record Drops:"],
        L["Counts what each corpse drops, so drop rates come from your own play."])

    controls.record = Widgets.CreateCheckbox(recordRow, L["On"], function(checked)
        SettingsUI:SetRecording(checked)
    end, true)
    controls.record:SetPoint("TOPLEFT", CONTROL_X, -2)

    self.recordRow = recordRow

    -- How much is recorded, and the button that hands it back.
    local block = CreateFrame("Frame", nil, pages.pages.loot.content)
    block:SetSize(COLUMN_WIDTH, 44)
    block.fixedHeight = 44
    pages:Place("loot", 1, block, -4)

    local summary = Theme.CreateLabel(block, "small", "text")
    summary:SetPoint("TOPLEFT", 0, 0)
    summary:SetWidth(COLUMN_WIDTH)
    self.harvestSummary = summary

    local export = Widgets.CreateButton(block, L["Export"], function()
        ns.UI:ShowExport(ns.Harvest:ExportAll(), L["Export: everything you looted"])
    end, { width = 80, height = 20 })
    export:SetPoint("TOPLEFT", 0, -22)
    controls.export = export

    -- Kept to the column beside the button, on two lines if the font needs
    -- them: on one it ran past the window's right edge.
    local exportHint = Theme.CreateLabel(block, "tiny", "dim")
    exportHint:SetPoint("LEFT", export, "RIGHT", 8, 0)
    exportHint:SetWidth(COLUMN_WIDTH - export:GetWidth() - 8)
    exportHint:SetWordWrap(true)
    exportHint:SetText(L["Your recorded loot as a data file."])
    self.exportHint = exportHint
    pages:Searchable("loot", block, L["export recorded loot data file"])

    local _, csvButton = CommandRow(pages, "loot", 1, L["Spreadsheet (CSV):"],
        L["Your loot, kills, gathering and fishing counts to paste into a spreadsheet."],
        L["Export"], "export csv")
    controls.exportCsv = csvButton

    -- The checks are typed only, as /farm harvest check (the owner,
    -- 2026-10-23); the chat-only lists are too (2026-10-15).

    -- Without Tradeskills (the owner asked 2026-10-12).
    pages:Section("loot", 1, L["PRICES"])

    local otherRow = pages:Row("loot", 1, L["TSM and Auctionator:"],
        L["Prices your drops with TradeSkillMaster or Auctionator when Tradeskills isn't loaded."])

    controls.otherPriceAddons = Widgets.CreateCheckbox(otherRow, L["On"], function(checked)
        ns.Value:SetUsesOtherAddons(checked)
    end, true)
    controls.otherPriceAddons:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Which one first (the owner, 2026-10-25).
    local orderRow = pages:Row("loot", 1, L["Price Order:"],
        L["Picks which addon's price is used first when both have one."])
    local orders = { "tsm", "auctionator" }
    local orderNames = { L["TSM First"], L["Auctionator First"] }
    controls.priceOrder = Widgets.CreateChoice(orderRow, {
        min = 1, max = 2, step = 1, value = 1,
        format = function(index) return orderNames[index] end,
        onChange = function(index) ns.Value:SetPriceOrder(orders[index]) end,
    })
    ns.SettingsPages.FitStepper(controls.priceOrder, orderNames)
    controls.priceOrder:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- How often green gear and better drops, by mob level (2026-10-13).
    pages:Section("loot", 1, L["WORLD DROPS"])

    local worldRow = pages:Row("loot", 1, L["World Drops:"],
        L["How often kills drop green gear or better, by mob level."])
    controls.worldDrops = Widgets.CreateCheckbox(worldRow, L["On"], function(checked)
        ns.WorldDrops:SetEnabled(checked)
    end, true)
    controls.worldDrops:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The loot feed (a player asked, the owner said build it 2026-10-19).
    pages:Section("loot", 1, L["LOOT FEED"])

    local feedRow = pages:Row("loot", 1, L["Loot Feed:"], nil)
    controls.lootFeed = Widgets.CreateCheckbox(feedRow, L["On"], function(checked)
        ns.LootFeed:SetEnabled(checked)
    end, false)
    controls.lootFeed:SetPoint("TOPLEFT", CONTROL_X, -2)

    local holdRow = pages:Row("loot", 1, L["Show For:"], nil)
    local function Seconds(value) return L.Format("%d seconds", value) end
    controls.lootFeedHold = Widgets.CreateStepper(holdRow, {
        min = ns.LootFeed.HOLD_MIN, max = ns.LootFeed.HOLD_MAX, step = 1, value = ns.LootFeed.HOLD,
        format = Seconds,
        onChange = function(value) ns.LootFeed:SetHold(value) end,
    })
    ns.SettingsPages.FitStepper(controls.lootFeedHold, { Seconds(ns.LootFeed.HOLD_MAX) })
    controls.lootFeedHold:SetPoint("TOPLEFT", CONTROL_X, -2)

    local worthRow = pages:Row("loot", 1, L["Show Worth:"], nil)
    controls.lootFeedWorth = Widgets.CreateCheckbox(worthRow, L["On"], function(checked)
        ns.LootFeed:SetShowsWorth(checked)
    end, true)
    controls.lootFeedWorth:SetPoint("TOPLEFT", CONTROL_X, -2)

    local placeRow = pages:Row("loot", 1, L["Feed Place:"], nil)
    controls.lootFeedMove = CommandButton(placeRow, L["Move"], "lootfeed move", 70)
    controls.lootFeedReset = CommandButton(placeRow, L["Reset"], "lootfeed reset", 70, CONTROL_X + 76)

    -- Drops only (a player asked, the owner agreed 2026-10-11).
    pages:Section("loot", 2, L["SKINNING"])

    local skinningRow = pages:Row("loot", 2, L["Hide Skinning:"],
        L["Leaves leather, hides and scales out of drops, kill worth, Rankings and Grind. You can still search for them."])

    controls.hideSkinning = Widgets.CreateCheckbox(skinningRow, L["On"], function(checked)
        ns.DB:SetShowSkinning(not checked)
    end, true)
    controls.hideSkinning:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The hide list (the owner asked 2026-10-11 for a blacklist).
    local _, hiddenButton = CommandRow(pages, "loot", 2, L["Hidden:"],
        L["Mobs, nodes and items you hid. Right-click one in a list to hide it."], L["Show"], "hidden")
    controls.hidden = hiddenButton

    local trashRow = pages:Row("loot", 2, L["Trash Can:"],
        L["When your bags are full, a gold can marks the item worth the least. Click it to pick the item up."])
    controls.trashCan = Widgets.CreateCheckbox(trashRow, L["On"], function(checked)
        ns.Trash:SetEnabled(checked)
    end, true)
    controls.trashCan:SetPoint("TOPLEFT", CONTROL_X, -2)

    local openRow = pages:Row("loot", 2, L["Opening Note:"],
        L["A note when you open a clam, sack or lockbox. After 10 it shows what one is worth."])
    controls.openNote = Widgets.CreateCheckbox(openRow, L["On"], function(checked)
        ns.OpenNote:SetEnabled(checked)
    end, true)
    controls.openNote:SetPoint("TOPLEFT", CONTROL_X, -2)
    local bagsFullRow = pages:Row("loot", 2, L["Bags Full Notice:"],
        L["A notice on screen when your bags fill up."])
    controls.bagsFull = Widgets.CreateCheckbox(bagsFullRow, L["On"], function(checked)
        ns.BagsFull:SetEnabled(checked)
    end, true)
    controls.bagsFull:SetPoint("TOPLEFT", CONTROL_X, -2)
    controls.bagsFullTry = CommandButton(bagsFullRow, L["Try"], "bagsfull test", 60, CONTROL_X + 70)
    local openButtonRow = pages:Row("loot", 2, L["Open Button:"],
        L["A button on the Kills & Loot panel opens clams, sacks and lockboxes, one per click."])
    controls.openButton = Widgets.CreateCheckbox(openButtonRow, L["On"], function(checked)
        ns.OpenButton:SetEnabled(checked)
    end, true)
    controls.openButton:SetPoint("TOPLEFT", CONTROL_X, -2)
    local autoOpenRow = pages:Row("loot", 2, L["Open After Loot:"],
        L["Opens the next clam, sack or lockbox each time you close a loot window."])
    controls.autoOpen = Widgets.CreateCheckbox(autoOpenRow, L["On"], function(checked)
        ns.OpenButton:SetAuto(checked)
    end, false)
    controls.autoOpen:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The fishing bar (UI/FishingBar.lua), off unless ticked.
    pages:Section("loot", 2, L["FISHING"])
    local fishingBarRow = pages:Row("loot", 2, L["Fishing Buttons:"], nil)
    controls.fishingBar = Widgets.CreateCheckbox(fishingBarRow, L["On"], function(checked)
        ns.FishingBar:SetEnabled(checked)
    end, false)
    controls.fishingBar:SetPoint("TOPLEFT", CONTROL_X, -2)
end

--- Map and goals: what is drawn on the maps, and the goals and their arrow.
function SettingsUI:BuildMapPage()
    local controls = self.controls
    local pages = self.pages

    pages:Section("map", 1, L["GATHERED NODE MARKERS"])

    local worldRow = pages:Row("map", 1, L["World Map:"],
        L["Marks where you gathered."])

    controls.markersWorld = Widgets.CreateCheckbox(worldRow, L["Show"], function(checked)
        ns.MapMarkers:SetWorld(checked)
    end, true)
    controls.markersWorld:SetPoint("TOPLEFT", CONTROL_X, -2)

    local minimapMarkersRow = pages:Row("map", 1, L["Minimap:"],
        L["The same marks around you. Hover one to see when you gathered it."])

    controls.markersMinimap = Widgets.CreateCheckbox(minimapMarkersRow, L["Show"], function(checked)
        ns.MapMarkers:SetMinimap(checked)
    end, true)
    controls.markersMinimap:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Sparkles on the node you face (the owner asked 2026-10-13).
    local sparkleRow = pages:Row("map", 1, L["Sparkles:"],
        L["Lights up the herb, ore, fishing school, chest, quest object or bobber in front of you."])

    controls.nodeSparkle = Widgets.CreateCheckbox(sparkleRow, L["On"], function(checked)
        ns.NodeSparkle:SetEnabled(checked)
    end, true)
    controls.nodeSparkle:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Sparkles or a beacon, a beam of light rising off the spot (the owner
    -- asked 2026-10-13).
    local styleNames = { sparkles = L["Sparkles"], beacon = L["Beacon"] }
    local sparkleStyleRow = pages:Row("map", 1, L["Sparkle Look:"],
        L["Beacon is a beam of light. Sparkles twinkle instead."])
    controls.sparkleStyle = Widgets.CreateChoice(sparkleStyleRow, {
        min = 1, max = #ns.NodeSparkle.STYLES, step = 1, value = 1,
        format = function(index) return styleNames[ns.NodeSparkle.STYLES[index]] end,
        onChange = function(index) ns.NodeSparkle:SetStyle(ns.NodeSparkle.STYLES[index]) end,
    })
    ns.SettingsPages.FitStepper(controls.sparkleStyle, styleNames)
    controls.sparkleStyle:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- What shows the way to the node on Era: the arrow and dots, the beam,
    -- or both (the owner, 2026-10-25).
    local pointerNames = { both = L["Arrow and Beam"], arrow = L["Arrow Only"], beam = L["Beam Only"] }
    local pointerRow = pages:Row("map", 1, L["Node Pointer:"],
        L["Shows the way to the node you face. The beam alone stands where the node is."])
    controls.nodePointer = Widgets.CreateChoice(pointerRow, {
        min = 1, max = #ns.NodeSparkle.POINTER_LOOKS, step = 1, value = 1,
        format = function(index) return pointerNames[ns.NodeSparkle.POINTER_LOOKS[index]] end,
        onChange = function(index) ns.NodeSparkle:SetPointerLook(ns.NodeSparkle.POINTER_LOOKS[index]) end,
    })
    ns.SettingsPages.FitStepper(controls.nodePointer, pointerNames)
    controls.nodePointer:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- A spoken line when the arrow finds a node (the owner, 2026-10-25).
    local voiceNames = { off = L["Off"], character = L["Your Character"], peon = L["Peon"], ping = L["Ping"] }
    local nodeVoiceRow = pages:Row("map", 1, L["Node Sound:"],
        L["A sound plays when the arrow finds a node. Your character says \"Follow me!\", a peon says \"Ready to work!\", or the map's ping plays."])
    controls.nodeVoice = Widgets.CreateChoice(nodeVoiceRow, {
        min = 1, max = #ns.NodeSparkle.VOICES, step = 1, value = 1,
        format = function(index) return voiceNames[ns.NodeSparkle.VOICES[index]] end,
        onChange = function(index)
            ns.NodeSparkle:SetVoice(ns.NodeSparkle.VOICES[index])
            ns.NodeSparkle:SayFound(nil, true)
        end,
    })
    ns.SettingsPages.FitStepper(controls.nodeVoice, voiceNames)
    controls.nodeVoice:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Each thing in its own colour, herbs and ore by your skill, and a
    -- corpse to skin (the owner, 2026-10-24).
    local sparkleColorsRow = pages:Row("map", 1, L["Sparkle Colors:"],
        L["Herbs and ore show your skill color. Quest things are blue. Chests, fish and your bobber are white."])
    controls.nodeSparkleColors = Widgets.CreateCheckbox(sparkleColorsRow, L["On"], function(checked)
        ns.NodeSparkle:SetColors(checked)
    end, true)
    controls.nodeSparkleColors:SetPoint("TOPLEFT", CONTROL_X, -2)

    local sparkleCorpsesRow = pages:Row("map", 1, L["Skinnable Corpses:"],
        L["A dead beast you can skin sparkles until you skin it."])
    controls.nodeSparkleCorpses = Widgets.CreateCheckbox(sparkleCorpsesRow, L["On"], function(checked)
        ns.NodeSparkle:SetCorpses(checked)
    end, true)
    controls.nodeSparkleCorpses:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The game's interact icon, out of sight without a controller (the
    -- owner asked 2026-10-13).
    local sparkleIconRow = pages:Row("map", 1, L["Hide Game Icon:"],
        L["Hides the game's icon over the thing you face, unless you use a controller."])
    controls.nodeSparkleHideIcon = Widgets.CreateCheckbox(sparkleIconRow, L["On"], function(checked)
        ns.NodeSparkle:SetHideIcon(checked)
    end, true)
    controls.nodeSparkleHideIcon:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The Grind tab (a player asked, the owner agreed 2026-10-09).
    pages:Section("map", 1, L["GRINDING"])

    local grindRow = pages:Row("map", 1, L["Grinding Camps:"],
        L["Where mobs of one level and type hang out."])

    controls.grindPins = Widgets.CreateCheckbox(grindRow, L["On Map"], function(checked)
        ns.GrindPins:SetOn(checked)
    end, true)
    controls.grindPins:SetPoint("TOPLEFT", CONTROL_X, -2)

    local openGrind = Widgets.CreateButton(grindRow, L["Open"], function()
        ns.Grinding:Command("")
    end, { width = 50, height = 20 })
    openGrind:SetPoint("TOPRIGHT", grindRow, "TOPRIGHT", 0, 0)
    controls.grindOpen = openGrind

    pages:Section("map", 1, L["TOOLTIPS"])

    local tooltipRow = pages:Row("map", 1, L["Where to Farm:"],
        L["Hover a material to see the best place to farm it."])

    -- Off, Shift or Always (2026-10-18): Shift shows it only while Shift is held.
    controls.itemTooltip = TooltipShiftStepper(tooltipRow, "whereToFarm",
        function() return ns.db.itemTooltip ~= false end,
        function(on)
            ns.db.itemTooltip = on
            if ns.ItemTooltip then ns.ItemTooltip.ForgetKept() end
        end)

    -- What crafting a material pays for your time, from Tradeskills
    -- (the owner said yes, 2026-10-15).
    local craftRow = pages:Row("map", 1, L["Craft or Sell:"],
        L["With Tradeskills, a material shows what an hour of farming it pays, sold or crafted."])
    controls.itemTooltipCraft = TooltipShiftStepper(craftRow, "craftOrSell",
        function() return ns.db.itemTooltipCraft ~= false end,
        function(on) ns.ItemTooltip:SetCraftEnabled(on) end)

    local killRow = pages:Row("map", 1, L["Kill Count:"],
        L["Hover a mob to see how many you've killed."])

    controls.killTooltip = TooltipShiftStepper(killRow, "killCount",
        function() return ns.db.killTooltip ~= false end,
        function(on) ns.KillTooltip:SetEnabled(on) end)

    -- The three drops worth most a kill, under the count (2026-10-14).
    local dropsRow = pages:Row("map", 1, L["Best Drops:"],
        L["The three drops worth the most from a mob."])
    controls.killTooltipDrops = TooltipShiftStepper(dropsRow, "bestDrops",
        function() return ns.db.killTooltipDrops ~= false end,
        function(on) ns.KillTooltip:SetDropsEnabled(on) end)

    -- "3/8" beside a quest mob's name (the owner picked it 2026-10-13).
    local questCountRow = pages:Row("map", 1, L["Quest Count:"],
        L["Shows 3/8 beside a mob your quest still needs."])
    controls.questMobCount = Widgets.CreateCheckbox(questCountRow, L["Show"], function(checked)
        ns.QuestMobs:SetEnabled(checked)
    end, true)
    controls.questMobCount:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Your kills beside a mob's nameplate (2026-10-15).
    local platesRow = pages:Row("map", 1, L["Nameplate Kills:"],
        L["Shows your kill count beside a mob's nameplate."])
    controls.killPlates = Widgets.CreateCheckbox(platesRow, L["Show"], function(checked)
        ns.KillPlates:SetEnabled(checked)
    end, true)
    controls.killPlates:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Where the count sits by the plate (a player asked, 2026-10-18).
    local sideNames = { above = L["Above"], below = L["Below"], left = L["Left"], right = L["Right"] }
    local platesSideRow = pages:Row("map", 1, L["Counter Position:"], nil)
    controls.killPlatesSide = Widgets.CreateChoice(platesSideRow, {
        min = 1, max = #ns.KillPlates.SIDES, step = 1, value = 3,
        format = function(index) return sideNames[ns.KillPlates.SIDES[index]] end,
        onChange = function(index) ns.KillPlates:SetSide(ns.KillPlates.SIDES[index]) end,
    })
    ns.SettingsPages.FitStepper(controls.killPlatesSide, sideNames)
    controls.killPlatesSide:SetPoint("TOPLEFT", CONTROL_X, -2)

    local platesWorthRow = pages:Row("map", 1, L["Nameplate Worth:"],
        L["Adds what one kill is worth once you have 20 kills."])
    controls.killPlatesWorth = Widgets.CreateCheckbox(platesWorthRow, L["Show"], function(checked)
        ns.KillPlates:SetWorthEnabled(checked)
    end, true)
    controls.killPlatesWorth:SetPoint("TOPLEFT", CONTROL_X, -2)

    pages:Section("map", 2, L["GOALS"])

    local goalsRow = pages:Row("map", 2, L["Goals Panel:"],
        L["Dock puts it back under the Kills & Loot panel."])
    controls.goals = CommandButton(goalsRow, L["Show"], "goals", 64)
    controls.goalsDock = CommandButton(goalsRow, L["Dock"], "goals dock", 64, CONTROL_X + 70)

    local killGoalRow = pages:Row("map", 2, L["Kill Goal:"], nil)
    controls.killGoal = CommandButton(killGoalRow, L["Open"], "killgoal", 64)
    controls.killGoalSummary = CommandButton(killGoalRow, L["Summary"], "killgoal summary", 64, CONTROL_X + 70)

    local bankRow = pages:Row("map", 2, L["Count the Bank:"],
        L["Goals count your bank as well as your bags."])

    controls.goalsBank = Widgets.CreateCheckbox(bankRow, L["On"], function(checked)
        if ns.Goals then ns.Goals:SetCountsBank(checked) end
    end, false)
    controls.goalsBank:SetPoint("TOPLEFT", CONTROL_X, -2)

    pages:Section("map", 2, L["GOAL ARROW"])

    local arrowRow = pages:Row("map", 2, L["Goal Arrow:"],
        L["Points to the nearest place to gather a goal."])

    controls.arrow = Widgets.CreateCheckbox(arrowRow, L["Show"], function(checked)
        ns.Arrow:SetOn(checked)
    end, false)
    controls.arrow:SetPoint("TOPLEFT", CONTROL_X, -2)

    local _, nextButton = CommandRow(pages, "map", 2, L["Next Place:"],
        L["Points the arrow at the next place for its goal."],
        L["Next"], "arrow next")
    controls.arrowNext = nextButton

    local tomtomRow = pages:Row("map", 2, L["Use TomTom:"],
        L["With TomTom installed, its arrow shows the way instead."])

    controls.tomtom = Widgets.CreateCheckbox(tomtomRow, L["On"], function(checked)
        ns.TomTom:SetOn(checked)
    end, true)
    controls.tomtom:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- A trip step by step to a far place (Logic/Travel.lua), on unless
    -- unticked.
    local routeRow = pages:Row("map", 2, L["Guide Me:"],
        L["When the place is in another zone or across the sea, the arrow leads you there step by step."])

    controls.arrowRoute = Widgets.CreateCheckbox(routeRow, L["On"], function(checked)
        ns.Travel:SetOn(checked)
    end, true)
    controls.arrowRoute:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- A glow where you kill the most (Logic/Heat.lua, a test feature).
    pages:Section("map", 2, L["KILL HEAT"])

    local heatWorldRow = pages:Row("map", 2, L["Heat on World Map:"],
        L["Glows where you kill what you're tracking."])

    controls.heatWorld = Widgets.CreateCheckbox(heatWorldRow, L["Show"], function(checked)
        ns.Heat:SetWorld(checked)
    end, false)
    controls.heatWorld:SetPoint("TOPLEFT", CONTROL_X, -2)

    local heatMinimapRow = pages:Row("map", 2, L["Heat on Minimap:"],
        L["The same glow around you, softer."])

    controls.heatMinimap = Widgets.CreateCheckbox(heatMinimapRow, L["Show"], function(checked)
        ns.Heat:SetMinimap(checked)
    end, false)
    controls.heatMinimap:SetPoint("TOPLEFT", CONTROL_X, -2)

    local heatLevelRow = pages:Row("map", 2, L["Heat Strength:"], nil)
    local heatNames = { L["Some"], L["More"], L["Most"] }
    controls.heatLevel = Widgets.CreateChoice(heatLevelRow, {
        min = 1, max = #heatNames, step = 1, value = 2,
        format = function(index) return heatNames[index] end,
        onChange = function(index) ns.Heat:SetLevel(index) end,
    })
    ns.SettingsPages.FitStepper(controls.heatLevel, heatNames)
    controls.heatLevel:SetPoint("TOPLEFT", CONTROL_X, -2)
end

--- A wrapping line of small text under a row's control, for a status.
local function StatusText(row, y)
    local text = Theme.CreateLabel(row, "tiny", "muted")
    text:SetPoint("TOPLEFT", 0, y)
    text:SetWidth(COLUMN_WIDTH)
    text:SetJustifyH("LEFT")
    if text.SetWordWrap then text:SetWordWrap(true) end
    return text
end

--- Sharing: kills, drop rates and gathering with your other account.
function SettingsUI:BuildSharingPage()
    local controls = self.controls
    local pages = self.pages

    pages:Section("sharing", 1, L["YOUR OTHER ACCOUNT"])

    local shareRow = pages:Row("sharing", 1, L["Share With Your Other Account:"],
        L["Swaps your kill counts, drop rates, gathering and fishing with your other account while both are logged in. What comes in merges with your totals and can't be taken back out."])
    controls.share = Widgets.CreateCheckbox(shareRow, L["On"], function(checked)
        ns.Share:SetEnabled(checked)
        SettingsUI:Refresh()
    end, false)
    controls.share:SetPoint("TOPLEFT", CONTROL_X, -2)

    local namesRow = pages:Row("sharing", 1, L["Other Accounts Characters:"],
        L["Type your other account's character names, with commas. Name one of yours in Farmer there too."])
    GrowRow(namesRow, 26)
    local names = Widgets.CreateSearchBox(namesRow, L["Ana Smith, Bob Jones"], nil, function(text)
        ns.Share:SetNames(text)
        SettingsUI:Refresh()
    end, { plain = true })
    names:SetPoint("TOPLEFT", 0, -26)
    names:SetWidth(COLUMN_WIDTH)
    names:SetHeight(20)
    controls.shareNames = names
    -- What came in from the names typed, and when (Share:Status).
    GrowRow(namesRow, 30)
    controls.shareStatus = StatusText(namesRow, -50)

    local _, syncButton = CommandRow(pages, "sharing", 1, L["Sync Now:"],
        L["Swaps anything new right now. It also does this every ten minutes."], L["Sync"], "share sync")
    controls.shareSync = syncButton

    pages:Section("sharing", 1, L["WITH ANOTHER PLAYER"])

    local _, giveButton = CommandRow(pages, "sharing", 1, L["Give My Data:"],
        L["Turns your counts into text you can send to another player."],
        L["Make Text"], "give")
    controls.shareGive = giveButton

    local _, takeButton = CommandRow(pages, "sharing", 1, L["Take Their Data:"],
        L["Paste what another player gave you. You'll see what it adds before anything changes."], L["Paste"], "take")
    controls.shareTake = takeButton

    -- Logic/GuildShare.lua: the same with guildmates who use Farmer.
    pages:Section("sharing", 2, L["YOUR GUILD"])

    local guildRow = pages:Row("sharing", 2, L["Share With Guild:"],
        L["Swaps drops with guildmates who use Farmer. Their drop rates fill in until you have your own. Your kills and Rankings stay yours."])
    controls.shareGuild = Widgets.CreateCheckbox(guildRow, L["On"], function(checked)
        ns.GuildShare:SetOn(checked)
        SettingsUI:Refresh()
    end, false)
    controls.shareGuild:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- What came in from the guild, and when (GuildShare:Status).
    local guildStatusRow = pages:Row("sharing", 2, L["Guild Status:"], nil)
    GrowRow(guildStatusRow, 30)
    controls.guildStatus = StatusText(guildStatusRow, -18)
end

--- Advanced: debug output, the data the addon carries, and the commands.
--- About (UI/About.lua): the note on how the addons are made, then the
--- version, the Discord and the other Blackthornes addons.
function SettingsUI:BuildAboutPage()
    local pages = self.pages
    local About = ns.About
    if not About then return end
    pages:Section("about", 1, L["HOW THESE ADDONS ARE MADE"])
    local note = pages:Place("about", 1, About:Note(pages.pages.about.content, COLUMN_WIDTH))
    pages:Searchable("about", note, note.words)
    pages:Section("about", 2, L["ABOUT"])
    local info = pages:Place("about", 2, About:Info(pages.pages.about.content, COLUMN_WIDTH))
    pages:Searchable("about", info, info.words)

    -- Logic/Contribute.lua: drops sent to help Farmer's data, off until
    -- ticked, and offered only where it can send (North America) and while
    -- someone is named to send to. Its words wrap under the box, since they
    -- run long.
    if not (ns.Contribute:InRegion() and ns.Contribute:HasRecipients()) then return end
    local text = L["Share your data with Blackthornes to improve the Farmer AddOn."]
    local holder = CreateFrame("Frame", nil, pages.pages.about.content)
    holder:SetSize(COLUMN_WIDTH, 36)
    local box = Widgets.CreateCheckbox(holder, text, function(checked)
        ns.Contribute:SetOn(checked)
        SettingsUI:Refresh()
    end, false)
    box:SetPoint("TOPLEFT", 0, -2)
    box:SetWidth(COLUMN_WIDTH)
    box.label:ClearAllPoints()
    box.label:SetPoint("TOPLEFT", box.box, "TOPRIGHT", 6, 1)
    box.label:SetWidth(COLUMN_WIDTH - 24)
    box.label:SetJustifyH("LEFT")
    if box.label.SetWordWrap then box.label:SetWordWrap(true) end
    local ok, tall = pcall(box.label.GetStringHeight, box.label)
    tall = ok and tonumber(tall) or 0
    if tall < 14 then tall = 28 end
    box:SetHeight(math.max(18, tall + 2))
    holder:SetHeight(math.max(18, tall + 2) + 6)
    pages:Place("about", 2, holder, -14)
    pages:Searchable("about", holder, text)
    self.controls.shareDrops = box
end

function SettingsUI:BuildAdvancedPage()
    local controls = self.controls
    local pages = self.pages

    pages:Section("advanced", 1, L["ADVANCED"])

    -- Debug and the checks are typed only (/farm debug, the owner,
    -- 2026-10-23): players don't need them.

    -- Core/SisterNote.lua: one chat line, once, naming the Blackthornes
    -- addons the player does not have. Off here is off in all of them.
    local sistersRow = pages:Row("advanced", 1, L["Sister Addons:"],
        L["Says once in chat which Blackthornes addons you don't have."])

    controls.sisters = Widgets.CreateCheckbox(sistersRow, L["On"], function(checked)
        ns.SisterNote:SetOn(checked)
    end, true)
    controls.sisters:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- UI/WhatsNew.lua: one window after an update for every Blackthornes
    -- addon. Off here is off in all of them, as the sister note is.
    local _, whatsNewButton = CommandRow(pages, "advanced", 1, L["What's New:"], nil,
        L["Open"], "whatsnew")
    controls.whatsnew = whatsNewButton

    local whatsNewRow = pages:Row("advanced", 1, L["What's New After Updates:"],
        L["Opens What's New the first time you play after an update."])
    controls.whatsNewPopup = Widgets.CreateCheckbox(whatsNewRow, L["On"], function(checked)
        ns.WhatsNew:SetOn(checked)
    end, true)
    controls.whatsNewPopup:SetPoint("TOPLEFT", CONTROL_X, -2)

    local whatsNewMotionRow = pages:Row("advanced", 1, L["What's New Motion:"], nil)
    controls.whatsNewMotion = Widgets.CreateCheckbox(whatsNewMotionRow, L["On"], function(checked)
        ns.WhatsNew:SetMotionOn(checked)
    end, true)
    controls.whatsNewMotion:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The chat-only commands (help, chat, stats, data, list) have no button
    -- here: they are typed only (the owner, 2026-10-15).
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

--- Put every control back in step with what is saved.
--
-- Called whenever the page opens and after any /farm command, because each
-- of these can also be changed by typing, and a page showing a stale switch
-- is worse than no page.
--- Records came in: the status lines catch up, a moment later and only
--- while Settings shows.
function SettingsUI:ShareStatusChanged()
    if self.statusSoon then return end
    self.statusSoon = true
    C_Timer.After(2, function()
        SettingsUI.statusSoon = nil
        local controls = SettingsUI.controls
        if not (SettingsUI.frame and SettingsUI.frame:IsShown() and controls and controls.guildStatus) then return end
        controls.shareStatus:SetText(ns.Share:Status() or "")
        controls.guildStatus:SetText(ns.GuildShare:Status() or "")
    end)
end

function SettingsUI:Refresh()
    if not (self.frame and self.frame:IsShown() and ns.db) then return end

    local db = ns.db
    local controls = self.controls

    controls.windowScale:SetValue(db.windowScale or 100, true)
    local tallyPercent = ns.TrackerUI and ns.TrackerUI.DrawnPercent and ns.TrackerUI:DrawnPercent()
        or db.trackerScale or 100
    controls.trackerScale:SetValue(tallyPercent, true)
    for _, button in ipairs(controls.trackerSizes or {}) do
        button:SetLabelColor(button.percent == tallyPercent and "good" or nil)
    end
    controls.sisters:SetChecked(ns.SisterNote:IsOn())
    controls.whatsNewPopup:SetChecked(ns.WhatsNew:IsOn())
    controls.whatsNewMotion:SetChecked(ns.WhatsNew:IsMotionOn())
    controls.share:SetChecked(db.shareData == true)
    controls.shareNames:SetText(db.shareNames or "")
    controls.shareGuild:SetChecked(db.shareGuild == true)
    controls.shareStatus:SetText(ns.Share:Status() or "")
    controls.guildStatus:SetText(ns.GuildShare:Status() or "")
    if controls.shareDrops then controls.shareDrops:SetChecked(db.shareDrops == true) end
    controls.markersWorld:SetChecked(db.markersWorld ~= false)
    controls.markersMinimap:SetChecked(db.markersMinimap ~= false)
    controls.heatWorld:SetChecked(db.heatWorld == true)
    controls.heatMinimap:SetChecked(db.heatMinimap == true)
    controls.heatLevel:SetValue(ns.Heat:Level(), true)
    controls.nodeSparkle:SetChecked(db.nodeSparkle ~= false)
    controls.sparkleStyle:SetValue(ns.NodeSparkle:Style() == "sparkles" and 1 or 2, true)
    for index, look in ipairs(ns.NodeSparkle.POINTER_LOOKS) do
        if look == ns.NodeSparkle:PointerLook() then controls.nodePointer:SetValue(index, true) end
    end
    for index, voice in ipairs(ns.NodeSparkle.VOICES) do
        if voice == ns.NodeSparkle:Voice() then controls.nodeVoice:SetValue(index, true) end
    end
    controls.nodeSparkleHideIcon:SetChecked(db.nodeSparkleHideIcon ~= false)
    controls.nodeSparkleColors:SetChecked(db.nodeSparkleColors ~= false)
    controls.nodeSparkleCorpses:SetChecked(db.nodeSparkleCorpses == true)
    for _, name in ipairs({ "itemTooltip", "itemTooltipCraft", "killTooltip", "killTooltipDrops" }) do
        local stepper = controls[name]
        stepper:SetValue(ns.TooltipShift:Mode(stepper.isOn(), stepper.shiftKey), true)
    end
    controls.questMobCount:SetChecked(db.questMobCount ~= false)
    controls.killPlates:SetChecked(db.killPlates ~= false)
    controls.killPlatesWorth:SetChecked(db.killPlatesWorth == true)
    do
        local side = ns.KillPlates:Side()
        for index, each in ipairs(ns.KillPlates.SIDES) do
            if each == side then controls.killPlatesSide:SetValue(index, true) end
        end
    end
    controls.hideSkinning:SetChecked(db.hideSkinning ~= false)
    controls.otherPriceAddons:SetChecked(db.otherPriceAddons ~= false)
    controls.priceOrder:SetValue(db.priceOrder == "auctionator" and 2 or 1, true)
    controls.worldDrops:SetChecked(db.worldDrops ~= false)
    controls.rankingsOutside:SetChecked(db.rankingsOutside == true)
    controls.rankingsSkipUncommon:SetChecked(db.rankingsSkipUncommon == true)
    controls.trashCan:SetChecked(db.trashCan ~= false)
    controls.openNote:SetChecked(db.openNote ~= false)
    controls.lootFeed:SetChecked(db.lootFeed == true)
    controls.lootFeedHold:SetValue(ns.LootFeed:Hold(), true)
    controls.lootFeedWorth:SetChecked(db.lootFeedWorth ~= false)
    controls.bagsFull:SetChecked(db.bagsFullNotice ~= false)
    controls.openButton:SetChecked(db.openButton ~= false)
    controls.fishingBar:SetChecked(db.fishingBar == true)
    controls.autoOpen:SetChecked(db.autoOpen == true)
    controls.arrow:SetChecked(db.arrowShown == true)
    controls.tomtom:SetChecked(db.useTomTom ~= false)
    controls.arrowRoute:SetChecked(db.arrowRoute ~= false)
    controls.grindPins:SetChecked(db.grindPins ~= false)

    controls.tracker:SetChecked(not db.trackerHidden)
    controls.dodgeGroup:SetChecked(db.trackerDodgeGroup ~= false)
    controls.keepPanel:SetChecked(db.keepPanel == true)
    controls.seeThrough:SetValue(db.trackerSeeThrough == true and ns.TrackerUI:SeeThroughLevel() or 0, true)
    controls.goalsSeeThrough:SetValue(ns.SeeThrough:Level("goals"), true)
    controls.goalSpotsSeeThrough:SetValue(ns.SeeThrough:Level("places"), true)
    controls.rankUpSeeThrough:SetValue(ns.SeeThrough:Level("rankup"), true)
    controls.recapSeeThrough:SetValue(ns.SeeThrough:Level("recap"), true)
    controls.xpBarSeeThrough:SetValue(ns.SeeThrough:Level("xpbar"), true)
    controls.lootFeedSeeThrough:SetValue(ns.SeeThrough:Level("lootfeed"), true)
    controls.report:SetChecked(db.trackerReport == true)
    controls.celebrate:SetChecked(db.trackerCelebrate ~= false)

    local ok, bank = pcall(function() return ns.Goals:CountsBank() end)
    controls.goalsBank:SetChecked(ok and bank == true)

    local level = ns.TrackerFX.Level()
    for index, name in ipairs(ns.TrackerFX.LEVELS) do
        if name == level then controls.effects:SetValue(index, true) end
    end
    controls.rareSound:SetChecked(ns.TrackerFX.RareSoundOn())
    if ns.RankUp then
        controls.rankUp:SetChecked(ns.RankUp.On())
        controls.rankUpSound:SetChecked(ns.RankUp.SoundOn())
        controls.topFarm:SetChecked(ns.TopFarm.On())
        controls.statsBestCheer:SetChecked(ns.db.statsBestCheer ~= false)
    end
    controls.voice:SetChecked(ns.TrackerFX.VoiceOn())
    if ns.XPBarUI then
        controls.xpBar:SetChecked(ns.XPBarUI.On())
        controls.xpBarCheer:SetChecked(ns.XPBarUI.CheerOn())
        controls.xpBarChime:SetChecked(ns.XPBarUI.ChimeOn())
        controls.xpBarHideGame:SetChecked(ns.XPBarUI.HidesGame())
    end
    controls.textSize:Sync()
    controls.windowStyle:Sync()

    local usable = ns.Harvest:Capabilities().usable

    controls.record:SetChecked(usable and not db.harvestPaused)
    controls.record:SetDisabled(not usable)

    if not usable and not self.recordUnusable then
        self.recordUnusable = true
        self.recordRow:SetDescription(L["This client does not let addons read the loot window, so nothing can be recorded."])
        self.pages:Fit()
    end

    local corpses = ns.Harvest:CountCorpses()

    if corpses == 0 then
        self.harvestSummary:SetText(Util.Colored("muted", L["Nothing recorded yet."]))
    else
        self.harvestSummary:SetText(L.Format("%s recorded from %s.",
            Util.Plural(corpses, L["corpse"], L["corpses"]),
            Util.Plural(ns.Harvest:CountMobs(), L["mob"], L["mobs"])))
    end

    self.pages:Refresh()
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

function SettingsUI:SavePosition()
    if not (ns.db and self.frame) then return end

    local point, _, relativePoint, x, y = self.frame:GetPoint()

    ns.db.settingsPoint = point
    ns.db.settingsRelativePoint = relativePoint
    ns.db.settingsX = x
    ns.db.settingsY = y
end

function SettingsUI:RestorePosition()
    if not self.frame then return end

    local db = ns.db or {}

    if ns.Motion then ns.Motion:Stop(self.frame, "open", true) end
    self.frame:ClearAllPoints()
    self.frame:SetPoint(db.settingsPoint or "CENTER", UIParent,
        db.settingsRelativePoint or "CENTER", db.settingsX or 0, db.settingsY or 0)
end

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------

function SettingsUI:Show()
    self:Build()

    if not self.frame:IsShown() then
        self:RestorePosition()
        self.frame:Show()
        ns.Motion:Open(self.frame)
    end

    self:Refresh()
end

function SettingsUI:Hide()
    if self.frame then self.frame:Hide() end
end

function SettingsUI:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

--------------------------------------------------------------------------------
-- The game's own AddOns options list
--
-- Forever runs retail's Settings panel, so the addon can have an entry under
-- Options > AddOns. That entry is a small launcher rather than this page
-- squeezed into Blizzard's frame: the page is built for its own dark window,
-- and a button that opens it is one click either way.
--
-- Every call is guarded: nothing documents which of these this client ships,
-- and a missing options entry is no reason for the addon to fail to load.
--------------------------------------------------------------------------------

function SettingsUI:RegisterGameOptions()
    if self.optionsPanel then return end

    local panel = CreateFrame("Frame")
    panel.name = TITLE

    local title = Theme.CreateLabel(panel, "title", "accent")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(TITLE)

    local blurb = Theme.CreateLabel(panel, "normal", "text")
    blurb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    blurb:SetText(L["Farmer's settings have a window of their own."])

    local open = Widgets.CreateButton(panel, L["Open Farmer settings"], function()
        -- The game's panel is left as it is: hiding a stock frame runs the
        -- game's own code as this addon and taints it (Equipment's Edit
        -- Mode error, 2026-10-10). Farmer's window is top level in the
        -- dialog layer, so it comes up over the panel.
        SettingsUI:Show()
    end, { width = 170, height = 24 })
    open:SetPoint("TOPLEFT", blurb, "BOTTOMLEFT", 0, -14)

    local hint = Theme.CreateLabel(panel, "small", "muted")
    hint:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -10)
    hint:SetText(L["Or type /farm settings, or right-click the minimap button."])

    self.optionsPanel = panel

    local registered = false

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        registered = pcall(function()
            local category = Settings.RegisterCanvasLayoutCategory(panel, TITLE)
            Settings.RegisterAddOnCategory(category)
            SettingsUI.optionsCategory = category
        end)
    end

    -- The older options API, in case this client still has it instead.
    if not registered and type(InterfaceOptions_AddCategory) == "function" then
        registered = pcall(InterfaceOptions_AddCategory, panel)
    end

    if not registered then
        ns.Debug("no game options panel to register with; /farm settings still works")
    end

    return registered
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function SettingsUI:OnEnable()
    -- Sizes are saved, so put them back before anything is seen.
    self:ApplyWindowScale()
    self:ApplyTrackerScale()

    local ok, err = pcall(self.RegisterGameOptions, self)
    if not ok then
        ns.Debug("could not add Farmer to the game's options:", tostring(err))
    end
end

ns.RegisterCommand("settings", L["open the settings window"], function()
    SettingsUI:Toggle()
end)

-- Common names for the same thing, so a guess works. Kept out of the help
-- list, which would otherwise print the same line three times.
ns.commands.options = ns.commands.settings
ns.commands.config = ns.commands.settings
