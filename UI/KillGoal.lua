-- Blackthornes Farmer -- UI/KillGoal.lua
-- The kill goal's two windows (Logic/KillGoal.lua; the owner said build it
-- from a mockup, 2026-10-20):
--
--   New Goal: an Item or Kills switch (Item opens the search, as the goals
--   panel's Set another always did), How Many, Which Mobs (any mob, or one
--   you pick with the arrows), Cancel and Start.
--
--   Goal Done!: the kills, the time, the gold, gold an hour and the XP, what
--   each mob dropped and the best drop, with New Goal and Got It. It opens
--   by itself when a goal is done, and again from the goals panel's card,
--   the Stats tab and /farm killgoal summary.
--
-- Both wear the house frame and its size grip, one size for both
-- (`killGoalScale`, account wide, never rename it).

local _, ns = ...
local L = ns.L

local KillGoalUI = ns.NewModule("KillGoalUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local PADDING = 14
local NEW_WIDTH, NEW_HEIGHT = 340, 262
local SUMMARY_WIDTH = 400
local ROW = 44
local TILE = 46

-- How many mobs Which Mobs offers: the one you target, then this
-- session's, then your most killed.
KillGoalUI.MOST_CHOICES = 20

local function Dress(frame, title, onClose)
    Theme.Fill(frame, "window")
    local trim
    if ns.Titanforged then
        trim = ns.Titanforged:Dress(frame, { title = title, close = onClose })
        local left, right, top, bottom = ns.Titanforged.Reach(trim)
        if frame.SetClampRectInsets then
            pcall(frame.SetClampRectInsets, frame, -left, right, top, -bottom)
        end
    else
        Theme.Border(frame, "borderLit")
    end

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    Widgets.ApplySize(frame, ns.db and ns.db.killGoalScale)
    frame.sizeGrip = Widgets.CreateSizeGrip(frame, {
        below = trim and select(4, ns.Titanforged.Reach(trim)) or 0,
        get = function() return ns.db and ns.db.killGoalScale end,
        save = function(percent) if ns.db then ns.db.killGoalScale = percent end end,
    })
end

local function NewFrame(name, width, height)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(width, height)
    frame:SetPoint("CENTER", 0, 60)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, name) end
    return frame
end

local function Glass(frame, index)
    local back = frame:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(frame)
    back:SetColorTexture(Theme.Unpack(index % 2 == 1 and "glass" or "glassAlt"))
    local line = frame:CreateTexture(nil, "BORDER")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(Theme.Unpack("border", 0.6))
    return back
end

--------------------------------------------------------------------------------
-- New Goal
--------------------------------------------------------------------------------

--- Opens the search so an item goal can be set, as the goals panel's Set
--- another always did.
local function OpenItemSearch()
    local UI = ns.UI
    if not UI then return end
    UI:Show()
    if UI.tab ~= "search" then UI:ShowTab("search") end
    if UI.searchBox then UI.searchBox:SetFocus() end
end

--- The mob you have targeted, if you could attack it.
local function TargetMob()
    if type(UnitExists) ~= "function" or type(UnitName) ~= "function" then return nil end
    local ok, name = pcall(function()
        if not UnitExists("target") then return nil end
        if type(UnitIsPlayer) == "function" and UnitIsPlayer("target") then return nil end
        if type(UnitCanAttack) == "function" and not UnitCanAttack("player", "target") then return nil end
        return UnitName("target")
    end)
    if not ok then return nil end
    return ns.Harvest.Readable(name)
end

--- Which Mobs' choices: nil for any mob first, then mob names.
function KillGoalUI.Choices()
    local choices, seen = { false }, {}
    local function Add(name)
        if type(name) ~= "string" or name == "" or seen[name] then return end
        if #choices > KillGoalUI.MOST_CHOICES then return end
        if ns.DB and ns.DB.IsHiddenSource and ns.DB:IsHiddenSource(name) then return end
        seen[name] = true
        choices[#choices + 1] = name
    end

    Add(TargetMob())

    local function ByCount(counts)
        local names = {}
        for name, count in pairs(counts) do
            if type(name) == "string" and not name:find("\t", 1, true) then
                names[#names + 1] = { name = name, count = tonumber(count) or 0 }
            end
        end
        table.sort(names, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return a.name < b.name
        end)
        for _, entry in ipairs(names) do Add(entry.name) end
    end

    local Tracker = ns.Tracker
    if Tracker and type(Tracker.session) == "table" then ByCount(Tracker.session) end
    if Tracker then
        local ok, mobs = pcall(Tracker.Store, Tracker)
        if ok and type(mobs) == "table" then
            local kills = {}
            for name, mob in pairs(mobs) do
                if type(mob) == "table" then kills[name] = tonumber(mob.kills) or 0 end
            end
            ByCount(kills)
        end
    end
    return choices
end

function KillGoalUI:BuildNew()
    if self.new then return self.new end

    local frame = NewFrame("BlackthornesFarmerKillGoalNew", NEW_WIDTH, NEW_HEIGHT)
    Dress(frame, L["New Goal"], function() KillGoalUI:HideNew() end)
    self.new = frame

    local switch = Widgets.CreateTabStrip(frame, {
        { key = "item", text = L["Item"] },
        { key = "kills", text = L["Kills"] },
    }, function(key)
        if key == "item" then
            KillGoalUI:HideNew()
            OpenItemSearch()
        end
    end)
    switch:SetPoint("TOP", frame, "TOP", 0, -32)
    frame.switch = switch

    local howMany = Theme.CreateLabel(frame, "small", "text")
    howMany:SetPoint("TOPLEFT", PADDING, -76)
    howMany:SetText(L["How Many:"])

    local box = Widgets.CreateSearchBox(frame, "", nil, function() KillGoalUI:StartGoal() end, { plain = true })
    box:SetPoint("TOPLEFT", PADDING + 110, -70)
    box:SetPoint("TOPRIGHT", -PADDING, -70)
    frame.box = box

    local which = Theme.CreateLabel(frame, "small", "text")
    which:SetPoint("TOPLEFT", PADDING, -112)
    which:SetText(L["Which Mobs:"])

    -- A drop-down of the mobs (the owner, 2026-10-23: drop-downs, never
    -- < > pickers).
    local mobs = Widgets.CreateDropdown(frame, {}, function(value)
        KillGoalUI.pick = value
        KillGoalUI:ShowPick()
    end, { width = 200 })
    mobs:SetPoint("TOPLEFT", PADDING + 110, -106)
    mobs:SetPoint("TOPRIGHT", -PADDING, -106)
    frame.mobs = mobs
    frame.mob = mobs.label

    local hint = Theme.CreateLabel(frame, "tiny", "muted")
    hint:SetPoint("TOPLEFT", PADDING, -138)
    hint:SetPoint("TOPRIGHT", -PADDING, -138)
    hint:SetWordWrap(true)
    frame.hint = hint

    local note = Theme.CreateLabel(frame, "tiny", "dim")
    note:SetPoint("BOTTOMLEFT", PADDING, PADDING + 34)
    note:SetPoint("BOTTOMRIGHT", -PADDING, PADDING + 34)
    note:SetWordWrap(true)
    note:SetText(L["Counts only kills from the moment you press Start."])

    local start = Widgets.CreateButton(frame, L["Start"], function() KillGoalUI:StartGoal() end,
        { primary = true, width = 90 })
    start:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
    local cancel = Widgets.CreateButton(frame, L["Cancel"], function() KillGoalUI:HideNew() end, { width = 90 })
    cancel:SetPoint("RIGHT", start, "LEFT", -8, 0)

    if ns.SharedWindow and ns.SharedWindow.KeepSpot then ns.SharedWindow.KeepSpot(frame, "farmer.killgoalnew") end
    return frame
end

--- Which Mobs moved by `by`.
function KillGoalUI:Step(by)
    local choices = self.choices or { false }
    self.pick = ((self.pick or 1) - 1 + by) % #choices + 1
    self:ShowPick()
end

function KillGoalUI:PickedMob()
    local choices = self.choices or {}
    return choices[self.pick or 1] or nil
end

function KillGoalUI:ShowPick()
    local frame = self.new
    if not frame then return end
    local mob = self:PickedMob()
    local options = {}
    for index, name in ipairs(self.choices or { false }) do
        options[index] = { text = name or L["Any Mob"], value = index }
    end
    frame.mobs.options = options
    frame.mobs:SetValue(self.pick or 1)
    local first = (self.choices or {})[2]
    if not mob and first then
        frame.hint:SetText(L.Format("Or pick one mob, like %s.", first))
    else
        frame.hint:SetText("")
    end
end

function KillGoalUI:ShowNew()
    local frame = self:BuildNew()
    self.choices = KillGoalUI.Choices()
    self.pick = 1
    -- Starts on the mob you have targeted, when there is one.
    local target = TargetMob()
    if target and self.choices[2] == target then self.pick = 2 end
    self:ShowPick()

    if frame.switch.selected ~= "kills" then frame.switch:Select("kills") end
    local current = ns.KillGoal:Current()
    frame.box:SetText(tostring(current and not current.done and current.target or 1000))
    frame:Show()
    local edit = frame.box.editBox
    if edit then pcall(edit.SetFocus, edit) end
    return frame
end

function KillGoalUI:HideNew()
    if self.new then self.new:Hide() end
end

function KillGoalUI:StartGoal()
    local frame = self.new
    if not frame then return nil end
    local ok, text = pcall(frame.box.GetText, frame.box)
    local goal, why = ns.KillGoal:Start(ok and text or nil, self:PickedMob())
    if not goal then
        ns.Print(L.Format("Couldn't start it: %s.", why or ""))
        return nil
    end
    self:HideNew()
    if self.summary then self.summary:Hide() end
    if ns.GoalsUI then pcall(ns.GoalsUI.Show, ns.GoalsUI) end
    return goal
end

--------------------------------------------------------------------------------
-- Goal Done!
--------------------------------------------------------------------------------

--- The four tiles' words: { label, value } each.
function KillGoalUI.Tiles(summary)
    local KillGoal = ns.KillGoal
    local perHour = KillGoal.PerHour(summary)
    local xp
    if (tonumber(summary.levels) or 0) >= 2 then
        xp = L.Format("%d levels", summary.levels)
    elseif (tonumber(summary.levels) or 0) == 1 then
        xp = L["1 level"]
    else
        xp = L.Format("%s XP", ns.XP and ns.XP.Comma(summary.xp) or tostring(summary.xp or 0))
    end
    return {
        { L["Time"], ns.XP and ns.XP.Duration(summary.seconds) or tostring(summary.seconds) },
        { L["Gold"], ns.Value.Coins(summary.gold or 0) },
        { L["Gold an Hour"], perHour and ns.Value.Coins(perHour) or "--" },
        { L["XP Gained"], xp },
    }
end

--- A mob's drops as one line: "Linen Cloth x96, Wool Cloth x58", each in
--- its rarity colour, the most first.
function KillGoalUI.ItemsLine(row, most)
    local parts = {}
    for index, item in ipairs(row.items or {}) do
        if index > (most or 6) then break end
        parts[#parts + 1] = L.Format("%s x%d", Util.ColorItem(item.name), item.count)
    end
    return table.concat(parts, ", ")
end

function KillGoalUI:BuildSummary()
    if self.summary then return self.summary end

    local frame = NewFrame("BlackthornesFarmerKillGoalSummary", SUMMARY_WIDTH, 300)
    Dress(frame, L["Goal Done!"], function() frame:Hide() end)
    self.summary = frame

    local headline = Theme.CreateLabel(frame, "title", "accent", "CENTER")
    headline:SetPoint("TOP", 0, -34)
    frame.headline = headline

    frame.tiles = {}
    local tileWidth = (SUMMARY_WIDTH - PADDING * 2 - 3 * 6) / 4
    for index = 1, 4 do
        local tile = CreateFrame("Frame", nil, frame)
        tile:SetSize(tileWidth, TILE)
        tile:SetPoint("TOPLEFT", PADDING + (index - 1) * (tileWidth + 6), -64)
        Glass(tile, index)
        tile.label = Theme.CreateLabel(tile, "tiny", "muted", "CENTER")
        tile.label:SetPoint("TOP", 0, -7)
        tile.value = Theme.CreateLabel(tile, "normal", "text", "CENTER")
        tile.value:SetPoint("BOTTOM", 0, 8)
        frame.tiles[index] = tile
    end

    local heading = Theme.CreateLabel(frame, "tiny", "accent")
    heading:SetPoint("TOPLEFT", PADDING, -64 - TILE - 14)
    heading:SetText(L["WHAT EACH MOB DROPPED"])
    frame.heading = heading

    frame.rows = {}

    local best = Theme.CreateLabel(frame, "small", "muted")
    best:SetWordWrap(true)
    frame.best = best

    local done = Widgets.CreateButton(frame, L["Got It"], function() KillGoalUI:GotIt() end,
        { primary = true, width = 90 })
    done:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
    local again = Widgets.CreateButton(frame, L["New Goal"], function()
        KillGoalUI:GotIt()
        KillGoalUI:ShowNew()
    end, { width = 90 })
    again:SetPoint("RIGHT", done, "LEFT", -8, 0)

    if ns.SharedWindow and ns.SharedWindow.KeepSpot then ns.SharedWindow.KeepSpot(frame, "farmer.killgoalsummary") end
    return frame
end

function KillGoalUI:Row(index)
    local frame = self.summary
    local row = frame.rows[index]
    if row then return row end

    row = CreateFrame("Frame", nil, frame)
    row:SetHeight(ROW)
    Glass(row, index)
    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("TOPLEFT", 8, -6)
    row.kills = Theme.CreateLabel(row, "small", "muted", "RIGHT")
    row.kills:SetPoint("TOPRIGHT", -8, -6)
    row.items = Theme.CreateLabel(row, "tiny", "text")
    row.items:SetPoint("TOPLEFT", 8, -22)
    row.items:SetPoint("TOPRIGHT", -8, -22)
    row.items:SetWordWrap(true)
    if row.items.SetMaxLines then pcall(row.items.SetMaxLines, row.items, 2) end
    frame.rows[index] = row
    return row
end

function KillGoalUI:ShowSummary()
    local summary = ns.KillGoal:Last()
    if not summary then return nil end
    local frame = self:BuildSummary()

    frame.headline:SetText(L.Format("%d kills", summary.kills or 0))

    for index, tile in ipairs(KillGoalUI.Tiles(summary)) do
        frame.tiles[index].label:SetText(tile[1])
        frame.tiles[index].value:SetText(tile[2])
    end

    local top = 64 + TILE + 30
    local shown = 0
    for index, mob in ipairs(summary.mobs or {}) do
        if index > ns.KillGoal.SHOWN_MOBS then break end
        local row = self:Row(index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", PADDING, -(top + (index - 1) * ROW))
        row:SetPoint("TOPRIGHT", -PADDING, -(top + (index - 1) * ROW))
        row.name:SetText(mob.name)
        row.kills:SetText(L.Format("%d kills", mob.kills or 0))
        row.items:SetText(KillGoalUI.ItemsLine(mob))
        row:Show()
        shown = index
    end
    for index = shown + 1, #frame.rows do frame.rows[index]:Hide() end

    local y = top + shown * ROW + 10
    frame.best:ClearAllPoints()
    frame.best:SetPoint("TOPLEFT", PADDING, -y)
    frame.best:SetPoint("TOPRIGHT", -PADDING, -y)
    if summary.best then
        frame.best:SetText(L.Format("Best drop: %s", Util.ColorItem(summary.best)))
        frame.best:Show()
        y = y + 22
    else
        frame.best:Hide()
    end

    frame:SetHeight(y + PADDING + 22 + 12)
    frame:Show()
    return frame
end

--- Got It: the window closes and a finished goal leaves the panel. The
--- summary stays for the Stats tab.
function KillGoalUI:GotIt()
    if self.summary then self.summary:Hide() end
    ns.KillGoal:ClearDone()
end
