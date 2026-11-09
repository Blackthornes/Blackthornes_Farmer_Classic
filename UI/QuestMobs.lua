-- Blackthornes Farmer -- UI/QuestMobs.lua
-- Your quest count beside the name of a mob a quest still wants.
--
-- The owner picked it (2026-10-13, from a mockup of three light touches):
-- "3/8" in gold just right of the name over a mob that counts for an
-- unfinished objective in the quest log, nothing else. Only where the game
-- draws a nameplate the addon can read (not inside dungeons, where they
-- are kept from addons).
--
-- The count is the game's own: the objective lines the mob's tooltip
-- carries (C_TooltipInfo.GetUnit), else an unfinished objective in the
-- quest log that names the mob. "Quest count" on the Map & goals page
-- (`questMobCount`, on unless unticked; never rename it) and `/farm
-- questcount`.
--
-- Nothing is written on a game frame: each count is Farmer's own frame on
-- UIParent, anchored past the nameplate's level (else its name, else the
-- plate), never parented to it. Smooth play: a plate is read when it appears, and every
-- plate showing is read again once, 0.3 s after a burst of quest log
-- events; the text is set only when it changed. No OnUpdate, no ticker.
-- Every client value is read in a pcall.

local _, ns = ...
local L = ns.L

local QuestMobs = ns.NewModule("QuestMobs")

QuestMobs.SETTLE = 0.3

local labels = {}      -- [plate] = { frame, text, shown }
local plateOf = {}     -- [unit token] = plate

local function Field(object, key)
    if type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

local function Readable(value)
    return ns.Harvest and ns.Harvest.Readable(value) or nil
end

function QuestMobs:IsEnabled()
    return not (ns.db and ns.db.questMobCount == false)
end

--------------------------------------------------------------------------------
-- The count
--------------------------------------------------------------------------------

--- "3/8" from a line, when it is a count not yet met.
function QuestMobs.CountIn(text)
    if type(text) ~= "string" then return nil end
    local have, need = text:match("(%d+)%s*/%s*(%d+)")
    have, need = tonumber(have), tonumber(need)
    if not have or not need or need <= 0 or have >= need then return nil end
    return ("%d/%d"):format(have, need)
end

--- The count off the mob's tooltip lines, the game's own answer.
local function FromTooltip(unit)
    local get = Field(_G.C_TooltipInfo, "GetUnit")
    if type(get) ~= "function" then return nil end
    local ok, data = pcall(get, unit)
    local lines = ok and Field(data, "lines")
    if type(lines) ~= "table" then return nil end
    -- The first line is the name; a count on any later one is a quest's.
    for index = 2, #lines do
        local count = QuestMobs.CountIn(Readable(Field(lines[index], "leftText")))
        if count then return count end
    end
    return nil
end

--- The count off an unfinished objective in the log that names the mob.
local function FromQuestLog(name)
    if type(name) ~= "string" or #name < 3 then return nil end
    local log = _G.C_QuestLog
    local count = Field(log, "GetNumQuestLogEntries")
    local info = Field(log, "GetInfo")
    local objectives = Field(log, "GetQuestObjectives")
    if type(count) ~= "function" or type(info) ~= "function" or type(objectives) ~= "function" then return nil end
    local lower = name:lower()
    local ok, entries = pcall(count)
    for index = 1, (ok and type(entries) == "number") and entries or 0 do
        local read, entry = pcall(info, index)
        local questID = read and type(entry) == "table" and not entry.isHeader and entry.questID
        if questID then
            local got, list = pcall(objectives, questID)
            for _, objective in ipairs(got and type(list) == "table" and list or {}) do
                local text = type(objective) == "table" and Readable(objective.text)
                if type(text) == "string" and not objective.finished and text:lower():find(lower, 1, true) then
                    local have, need = tonumber(objective.numFulfilled), tonumber(objective.numRequired)
                    local shown = have and need and need > 0 and have < need and ("%d/%d"):format(have, need)
                    shown = shown or QuestMobs.CountIn(text)
                    if shown then return shown end
                end
            end
        end
    end
    return nil
end

--- What to show over `unit`, or nil: a mob (never a player or an object)
--- a quest still wants.
function QuestMobs:CountFor(unit)
    if type(UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    guid = ok and Readable(guid) or nil
    if type(guid) ~= "string" or not (guid:find("^Creature%-") or guid:find("^Vehicle%-")) then return nil end
    if type(UnitIsPlayer) == "function" then
        local read, player = pcall(UnitIsPlayer, unit)
        if read and type(player) == "boolean" and player then return nil end
    end
    local count = FromTooltip(unit)
    if count then return count end
    local name
    if type(UnitName) == "function" then
        local read, value = pcall(UnitName, unit)
        name = read and Readable(value) or nil
    end
    return FromQuestLog(name)
end

--------------------------------------------------------------------------------
-- The labels
--------------------------------------------------------------------------------

local function PlateFor(unit)
    local forUnit = Field(_G.C_NamePlate, "GetNamePlateForUnit")
    if type(forUnit) ~= "function" then return nil end
    local ok, plate = pcall(forUnit, unit)
    if ok and type(plate) == "table" then return plate end
    return nil
end

--- The nameplate's name text, when the game lets us read it.
local function NameOf(plate)
    local name = Field(Field(plate, "UnitFrame"), "name")
    if type(name) ~= "table" then return nil end
    local ok, kind = pcall(function() return name:GetObjectType() end)
    if ok and kind == "FontString" then return name end
    return nil
end

local function Showing(piece)
    if type(piece) ~= "table" then return false end
    local ok, shown = pcall(function() return piece:IsShown() end)
    return ok and shown == true
end

--- What sits furthest right on the plate's name line. Forever's plate
--- draws the name inside the health bar and the mob's level just past
--- the bar's end, so a count laid beside the name landed on the level
--- (a player saw "0/8" over the "6", 2026-11-05, and "1/10" over the
--- "10" again on 2026-11-08). Read for its edge only, never anchored to
--- (see QuestMobs.Anchor). The level's frame or text when it shows,
--- else any short number the plate shows on its own (the level under
--- another field name), else the name. The second answer is true when
--- the edge is the level; nil when nothing can be read.
local LEVEL_FIELDS = { "LevelFrame", "levelText", "LevelText", "level", "Level" }

local function LevelLike(piece)
    if not Showing(piece) then return false end
    local ok, kind = pcall(function() return piece:GetObjectType() end)
    if not ok or kind ~= "FontString" then return false end
    local read, text = pcall(function() return piece:GetText() end)
    if not read or type(text) ~= "string" then return false end
    local same, matched = pcall(string.match, text, "^%s*[%d%?]+%+?%s*$")
    return same and matched ~= nil
end

local function ScanForLevel(frame, depth)
    if type(frame) ~= "table" or depth > 2 then return nil end
    local ok, regions = pcall(function() return { frame:GetRegions() } end)
    if ok then
        for _, region in ipairs(regions) do
            if LevelLike(region) then return region end
        end
    end
    local okKids, kids = pcall(function() return { frame:GetChildren() } end)
    if okKids then
        for _, kid in ipairs(kids) do
            local found = ScanForLevel(kid, depth + 1)
            if found then return found end
        end
    end
    return nil
end

function QuestMobs.RightOf(plate)
    local unitFrame = Field(plate, "UnitFrame")
    local levelFrame = Field(unitFrame, "LevelFrame")
    local pieces = { levelFrame, Field(levelFrame, "levelText") }
    for _, key in ipairs(LEVEL_FIELDS) do
        pieces[#pieces + 1] = Field(unitFrame, key)
        pieces[#pieces + 1] = Field(Field(unitFrame, "healthBar"), key)
    end
    for i = 1, #pieces do
        if Showing(pieces[i]) then return pieces[i], true end
    end
    local found = ScanForLevel(unitFrame, 0)
    if found then return found, true end
    return NameOf(plate), false
end

--- Room left past the name for a level the plate shows but won't name:
--- as wide as "60" in the plate's own font, and a little more.
QuestMobs.LEVEL_ROOM = 22

local function LevelRoom()
    local ok, width = pcall(ns.Theme.TextWidth, "normal", "60")
    if ok and type(width) == "number" and width > 0 then
        return math.max(QuestMobs.LEVEL_ROOM, math.ceil(width) + 8)
    end
    return QuestMobs.LEVEL_ROOM
end

--- Where the count goes: always beside the plate's name (else the plate),
--- pushed right past the level by how far the level reaches. Never
--- anchored to the level itself: on Forever it sits on a part of the plate
--- the game guards, and a frame tied to it can't be shown in a fight, so
--- the count went missing (2026-11-09). Only the level's edge is read.
-- @return anchor, gap
local function EdgeRight(piece)
    local ok, right = pcall(function() return piece:GetRight() end)
    if not ok or type(right) ~= "number" then return nil end
    local okScale, scale = pcall(function() return piece:GetEffectiveScale() end)
    if not okScale or type(scale) ~= "number" or scale <= 0 then scale = 1 end
    return right * scale
end

function QuestMobs.Anchor(plate, own)
    local name = NameOf(plate)
    if not name then return plate, 2 end
    local edge, isLevel = QuestMobs.RightOf(plate)
    if not isLevel or edge == name then return name, 4 + LevelRoom() end
    local levelRight, nameRight = EdgeRight(edge), EdgeRight(name)
    if not levelRight or not nameRight then return name, 4 + LevelRoom() end
    local scale = 1
    if own then
        local ok, value = pcall(function() return own:GetEffectiveScale() end)
        if ok and type(value) == "number" and value > 0 then scale = value end
    end
    local reach = (levelRight - nameRight) / scale
    if reach < 0 or reach > 200 then return name, 4 + LevelRoom() end
    return name, 4 + math.ceil(reach)
end

local function Label(plate)
    local entry = labels[plate]
    if entry then return entry end
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(40, 16)
    pcall(frame.EnableMouse, frame, false)
    local text = ns.Theme.CreateLabel(frame, "normal", "accent")
    text:SetPoint("LEFT")
    pcall(text.SetShadowOffset, text, 1, -1)
    frame:Hide()
    entry = { frame = frame, text = text }
    labels[plate] = entry
    return entry
end

function QuestMobs:Show(plate, count)
    local entry = Label(plate)
    if entry.shown ~= count then
        entry.text:SetText(count)
        entry.shown = count
    end
    -- Looked at again each time, since the game can show the level a
    -- moment after the plate; points are set only when the spot moved.
    local anchor, gap = QuestMobs.Anchor(plate, entry.frame)
    if entry.placed ~= anchor or entry.gap ~= gap then
        entry.frame:ClearAllPoints()
        local ok = pcall(entry.frame.SetPoint, entry.frame, "LEFT", anchor, "RIGHT", gap, 0)
        if not ok then entry.frame:SetPoint("LEFT", plate, "RIGHT", 2, 0) end
        entry.placed, entry.gap = anchor, gap
    end
    local was = entry.frame:IsShown()
    entry.frame:Show()
    if not was and ns.KillPlates then ns.KillPlates:QuestMoved(plate) end
end

--- The count's frame and text over a plate while it shows, for the kill
--- count to sit clear of it.
function QuestMobs:LabelFor(plate)
    local entry = plate and labels[plate]
    if entry and entry.frame:IsShown() then return entry end
    return nil
end

--- The count showing over a plate, or nil.
function QuestMobs:Shown(plate)
    local entry = plate and labels[plate]
    return entry and entry.frame:IsShown() and entry.shown or nil
end

function QuestMobs:Hide(plate)
    local entry = plate and labels[plate]
    if not entry then return end
    local was = entry.frame:IsShown()
    entry.frame:Hide()
    entry.frame:ClearAllPoints()
    entry.placed, entry.gap, entry.shown = nil, nil, nil
    if was and ns.KillPlates then ns.KillPlates:QuestMoved(plate) end
end

--- Read one plate's mob again.
-- @return the count shown, or nil
function QuestMobs:Update(unit)
    local plate = PlateFor(unit)
    local old = plateOf[unit]
    if old and old ~= plate then self:Hide(old) end
    plateOf[unit] = plate
    if not plate then return nil end
    local count = self:IsEnabled() and self:CountFor(unit) or nil
    if count then self:Show(plate, count) else self:Hide(plate) end
    return count
end

function QuestMobs:Removed(unit)
    local plate = plateOf[unit]
    plateOf[unit] = nil
    self:Hide(plate)
end

--- Every plate showing, read again.
function QuestMobs:UpdateAll()
    self.pending = nil
    for unit in pairs(plateOf) do self:Update(unit) end
end

function QuestMobs:Soon()
    if self.pending then return end
    self.pending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(self.SETTLE, function() QuestMobs:UpdateAll() end)
    else
        self:UpdateAll()
    end
end

function QuestMobs:SetEnabled(on)
    ns.db.questMobCount = on and true or false
    self:UpdateAll()
end

local function Safe(fn)
    return function(...)
        local ok = pcall(fn, ...)
        return ok
    end
end

function QuestMobs:OnEnable()
    ns.RegisterEvent(self, "NAME_PLATE_UNIT_ADDED", Safe(function(_, _, unit)
        if type(unit) == "string" then QuestMobs:Update(unit) end
    end))
    ns.RegisterEvent(self, "NAME_PLATE_UNIT_REMOVED", Safe(function(_, _, unit)
        if type(unit) == "string" then QuestMobs:Removed(unit) end
    end))
    ns.RegisterEvent(self, "QUEST_LOG_UPDATE", function() QuestMobs:Soon() end)
    ns.RegisterEvent(self, "UNIT_QUEST_LOG_CHANGED", function() QuestMobs:Soon() end)
end

ns.RegisterCommand("questcount", L["your quest count beside quest mobs' names on or off"], function(rest)
    local argument = ns.Util.Trim(rest or ""):lower()
    local on
    if argument == "on" then on = true
    elseif argument == "off" then on = false
    else on = not QuestMobs:IsEnabled() end
    QuestMobs:SetEnabled(on)
    ns.Print(on and L["quest count on quest mobs on."] or L["quest count on quest mobs off."])
    if ns.SettingsUI then ns.SettingsUI:Refresh() end
end)
