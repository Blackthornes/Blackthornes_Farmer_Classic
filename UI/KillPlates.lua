-- Blackthornes Farmer -- UI/KillPlates.lua
-- Your kill count to the left of a mob's nameplate, as its tooltip has it.
--
--   7/20 [Plainstrider]           (gold, until drop rates unlock at 20)
--   134 [Plainstrider]            (your kills from 20 on)
--   134  1s 20c [Plainstrider]    (with "Worth on nameplates" ticked)
--   134 (crown) [Plainstrider]    (from 100 kills, the kills panel's mark)
--
-- A player asked, the owner said build it (2026-10-15). The numbers are
-- the tooltip's own (KillTooltip.Kills, KillTooltip:Worth), so the two
-- never disagree, and the worth only shows from 20 of your own kills,
-- never from the database's rates. "Kill count on nameplates"
-- (`killPlates`, on unless unticked) and "Worth on nameplates"
-- (`killPlatesWorth`, off unless ticked) on the Map & goals page, account
-- wide, never rename either; `/farm plates [on|off|worth on|off]`.
-- "Counter Position" picks where it sits (a player asked, the owner said
-- yes 2026-10-18, since it covered another nameplate addon's text):
-- `killPlatesSide`, "above", "below", "left" or "right", "left" unless
-- picked, account wide, never rename it. Above sits over the name, below
-- under the health and cast bars, right past the quest count, so none of
-- them covers the plate's own text.
--
-- Which mobs: the same as the tooltip. A creature you can attack, or one
-- you have killed; never a player, a pet or a critter, and never a hidden
-- mob. Only where the game lets addons read a nameplate (not inside
-- dungeons), and only the plates the player has turned on.
--
-- Nothing is written on a game frame: each count is Farmer's own frame on
-- UIParent, anchored to the left of the nameplate's name (or the plate),
-- never parented to it, as UI/QuestMobs.lua does on the right. Smooth play:
-- a plate is read when it appears, and again only when a mob of the same
-- name is killed, a setting changes or the hide list moves; the worth is
-- the tooltip's kept answer, and the text is set only when it changed. No
-- OnUpdate, no ticker. Every client value is read in a pcall.
--
-- Easy to see on any ground (the owner, 2026-10-25, after it was lost on
-- Durotar's red earth): a bright gold count, a size up, with a dark
-- outline. When a kill moves it, the count pops (grows, glows gold and
-- settles) and a green "+1" rises off it and fades (`KillPlates:Cheer`).
-- Animations the game plays, so nothing runs per frame here; Window
-- effects Subtle keeps only the "+1", Off neither. Like the other kill
-- marks, never announced.

local ADDON, ns = ...
local L = ns.L

local KillPlates = ns.NewModule("KillPlates")

local labels = {}      -- [plate] = { frame, text, shown }
local plateOf = {}     -- [unit token] = plate
local nameOf = {}      -- [unit token] = the mob's name, as its kills are kept

local GOLD = "ffffe7a0"
local WHITE = "ffe6e8ec"

local function Field(object, key)
    if type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

function KillPlates:IsEnabled()
    return not (ns.db and ns.db.killPlates == false)
end

KillPlates.SIDES = { "above", "below", "left", "right" }
local IS_SIDE = { above = true, below = true, left = true, right = true }

--- Where the count sits beside the plate: "left" unless picked.
function KillPlates:Side()
    local side = ns.db and ns.db.killPlatesSide
    if IS_SIDE[side] then return side end
    return "left"
end

function KillPlates:WorthEnabled()
    return self:IsEnabled() and ns.db and ns.db.killPlatesWorth == true or false
end

--------------------------------------------------------------------------------
-- The text
--------------------------------------------------------------------------------

--- What to show for a mob of this name, from its kills.
function KillPlates:TextFor(name)
    local Tooltip = ns.KillTooltip
    local kills = Tooltip.Kills(name)
    local need = ns.Tracker.MIN_KILLS
    if kills < need then
        return ("|c%s%d/%d|r"):format(GOLD, kills, need)
    end
    local text = ("|c%s%d|r"):format(WHITE, kills)
    if self:WorthEnabled() then
        local ok, entry = pcall(Tooltip.Read, Tooltip, name, kills)
        if ok and type(entry) == "table" and entry.text and not entry.estimate then
            text = text .. "  " .. entry.text
        end
    end
    -- The crown you earned on this mob, next to its name.
    local crown = Tooltip.Crown(kills)
    if crown then text = text .. " " .. crown end
    return text
end

--- The mob over `unit` and its text, or nil: a creature you could farm or
--- have killed, not hidden.
function KillPlates:Read(unit)
    if type(UnitGUID) ~= "function" then return nil end
    local ok, value = pcall(UnitGUID, unit)
    local guid = ok and ns.Harvest.Readable(value) or nil
    if type(guid) ~= "string" or not ns.Harvest.NpcID(guid) then return nil end
    if not (guid:find("^Creature%-") or guid:find("^Vehicle%-")) then return nil end

    local Tooltip = ns.KillTooltip
    local name = Tooltip:MobName(unit, guid)
    if not name then return nil end
    if ns.DB and ns.DB:IsHiddenSource(name) then return nil end
    local key = Tooltip.KeyHere(name)
    if Tooltip.Kills(key) == 0 and Tooltip:Attackable(unit) ~= true then return nil end
    return name, self:TextFor(key)
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
local function NameText(plate)
    local name = Field(Field(plate, "UnitFrame"), "name")
    if type(name) ~= "table" then return nil end
    local ok, kind = pcall(function() return name:GetObjectType() end)
    if ok and kind == "FontString" then return name end
    return nil
end

local function Label(plate)
    local entry = labels[plate]
    if entry then return entry end
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(80, 16)
    pcall(frame.EnableMouse, frame, false)
    local text = ns.Theme.CreateLabel(frame, "normal", "text")
    pcall(text.SetFont, text, ns.Theme.FONT, (ns.Theme.sizes.normal or 12) + KillPlates.SIZE_UP, "OUTLINE")
    pcall(text.SetShadowOffset, text, 1, -1)
    frame:Hide()
    entry = { frame = frame, text = text }
    labels[plate] = entry
    return entry
end

KillPlates.SIZE_UP = 2         -- points over the usual label size
KillPlates.POP = 1.35          -- how big the count grows on a kill
KillPlates.RISE = 30           -- how far the "+1" floats up
KillPlates.HOLD = 0.9          -- seconds the "+1" stays whole
KillPlates.FADE = 0.9          -- seconds it takes to fade after

--- Sets a scale step, by the older call where the client has it.
local function Grow(piece, by)
    if piece.SetScale then piece:SetScale(by, by)
    else piece:SetScaleFrom(1, 1); piece:SetScaleTo(by, by) end
end

--- The pop, the glow and the "+1", made the first time a kill moves this
--- count. Each piece is left out when the client will not make it.
local function Cheers(entry)
    if entry.cheers ~= nil then return entry.cheers end
    local frame, cheers = entry.frame, {}
    local origin = { left = "RIGHT", right = "LEFT", above = "BOTTOM", below = "TOP" }
    pcall(function()
        local glow = frame:CreateTexture(nil, "ARTWORK")
        glow:SetTexture(([[Interface\AddOns\%s\Media\Frame\Glow]]):format(ADDON))
        glow:SetBlendMode("ADD")
        glow:SetVertexColor(1, 0.82, 0.3)
        glow:SetPoint("TOPLEFT", entry.text, "TOPLEFT", -10, 8)
        glow:SetPoint("BOTTOMRIGHT", entry.text, "BOTTOMRIGHT", 10, -8)
        glow:SetAlpha(0)
        local group = glow:CreateAnimationGroup()
        local up = group:CreateAnimation("Alpha")
        up:SetFromAlpha(0); up:SetToAlpha(1); up:SetDuration(0.12); up:SetOrder(1)
        local down = group:CreateAnimation("Alpha")
        down:SetFromAlpha(1); down:SetToAlpha(0); down:SetDuration(0.4); down:SetOrder(2)
        if group.Play then cheers.glow = group end
    end)
    pcall(function()
        local group = frame:CreateAnimationGroup()
        local grow = group:CreateAnimation("Scale")
        Grow(grow, KillPlates.POP)
        grow:SetDuration(0.12); grow:SetSmoothing("OUT"); grow:SetOrder(1)
        local settle = group:CreateAnimation("Scale")
        Grow(settle, 1 / KillPlates.POP)
        settle:SetDuration(0.3); settle:SetSmoothing("IN_OUT"); settle:SetOrder(2)
        cheers.grow, cheers.settle = grow, settle
        if group.Play then cheers.pop = group end
    end)
    cheers.origin = origin
    pcall(function()
        local plus = frame:CreateFontString(nil, "OVERLAY")
        plus:SetFont(ns.Theme.FONT, (ns.Theme.sizes.normal or 12) + KillPlates.SIZE_UP + 2, "OUTLINE")
        plus:SetTextColor(0.55, 1, 0.55)
        plus:SetText("+1")
        plus:SetPoint("BOTTOM", entry.text, "TOP", 0, 2)
        plus:Hide()
        -- Shown whole while it holds, rising all along, then fading out.
        local group = plus:CreateAnimationGroup()
        local rise = group:CreateAnimation("Translation")
        rise:SetOffset(0, KillPlates.RISE); rise:SetDuration(KillPlates.HOLD + KillPlates.FADE)
        rise:SetSmoothing("OUT"); rise:SetOrder(1)
        local fade = group:CreateAnimation("Alpha")
        fade:SetFromAlpha(1); fade:SetToAlpha(0); fade:SetDuration(KillPlates.FADE)
        fade:SetStartDelay(KillPlates.HOLD); fade:SetOrder(1)
        pcall(group.SetScript, group, "OnFinished", function() plus:Hide() end)
        if group.Play then cheers.plus, cheers.plusText = group, plus end
    end)
    entry.cheers = cheers
    return cheers
end

local function Replay(group)
    if not group then return end
    pcall(group.Stop, group)
    pcall(group.Play, group)
end

--- A kill moved this count: pop it and float a "+1" off it.
-- @return what played ("full", "subtle"), or nil
function KillPlates:Cheer(entry)
    if not entry or not entry.frame:IsShown() then return nil end
    local level = ns.Motion and ns.Motion.Level and ns.Motion.Level() or "full"
    if level == "off" then return nil end
    local cheers = Cheers(entry)
    if level == "full" then
        local point = cheers.origin[entry.placed or self:Side()] or "CENTER"
        for _, piece in ipairs({ cheers.grow, cheers.settle }) do
            pcall(piece.SetOrigin, piece, point, 0, 0)
        end
        Replay(cheers.pop)
        Replay(cheers.glow)
    end
    if cheers.plusText then
        pcall(cheers.plusText.SetAlpha, cheers.plusText, 1)
        pcall(cheers.plusText.Show, cheers.plusText)
    end
    Replay(cheers.plus)
    return level
end

local JUSTIFY = { left = "RIGHT", right = "LEFT", above = "CENTER", below = "CENTER" }

--- The lowest bar under the name the game lets us read: the cast bar
--- (so a cast never runs over the count), else the health bar.
local function LowestBar(plate)
    local unitFrame = Field(plate, "UnitFrame")
    for _, key in ipairs({ "castBar", "CastBar", "healthBar", "HealthBar" }) do
        local bar = Field(unitFrame, key)
        if type(bar) == "table" then
            local ok, kind = pcall(function() return bar:GetObjectType() end)
            if ok and type(kind) == "string" then return bar end
        end
    end
    return nil
end

--- Lays the count out on the side picked. Right goes past the quest
--- count when one shows, so the two never sit on each other.
function KillPlates:Place(plate, entry)
    local side = self:Side()
    local frame, text = entry.frame, entry.text
    frame:ClearAllPoints()
    text:ClearAllPoints()
    local justify = JUSTIFY[side]
    text:SetPoint(justify)
    pcall(text.SetJustifyH, text, justify)
    local name = NameText(plate)
    if side == "left" then
        if name then frame:SetPoint("RIGHT", name, "LEFT", -4, 0)
        else frame:SetPoint("RIGHT", plate, "LEFT", -2, 0) end
    elseif side == "right" then
        local quest = ns.QuestMobs and ns.QuestMobs.LabelFor and ns.QuestMobs:LabelFor(plate)
        if quest then frame:SetPoint("LEFT", quest.text, "RIGHT", 4, 0)
        elseif name then frame:SetPoint("LEFT", name, "RIGHT", 4, 0)
        else frame:SetPoint("LEFT", plate, "RIGHT", 2, 0) end
    elseif side == "above" then
        if name then frame:SetPoint("BOTTOM", name, "TOP", 0, 2)
        else frame:SetPoint("BOTTOM", plate, "TOP", 0, 2) end
    else
        local bar = LowestBar(plate)
        if bar then frame:SetPoint("TOP", bar, "BOTTOM", 0, -2)
        else frame:SetPoint("TOP", plate, "BOTTOM", 0, -2) end
    end
    entry.placed = side
end

function KillPlates:Show(plate, text)
    local entry = Label(plate)
    if entry.shown ~= text then
        entry.text:SetText(text)
        entry.shown = text
    end
    if not entry.placed then self:Place(plate, entry) end
    entry.frame:Show()
end

--- The quest count over this plate came or went: on the right, the
--- count moves to stay clear of it.
function KillPlates:QuestMoved(plate)
    local entry = plate and labels[plate]
    if not entry or not entry.placed or self:Side() ~= "right" then return end
    self:Place(plate, entry)
end

--- The count's frame and text over a plate, for the tests.
function KillPlates:LabelOf(plate)
    return labels[plate]
end

--- The nameplate units being read now, in order, for the loot check.
function KillPlates:Units()
    local units = {}
    for unit in pairs(plateOf) do units[#units + 1] = unit end
    table.sort(units)
    return units
end

--- The text showing over a plate, or nil.
function KillPlates:Shown(plate)
    local entry = plate and labels[plate]
    return entry and entry.frame:IsShown() and entry.shown or nil
end

function KillPlates:Hide(plate)
    local entry = plate and labels[plate]
    if not entry then return end
    entry.frame:Hide()
    entry.frame:ClearAllPoints()
    entry.placed, entry.shown = nil, nil
end

--- Read one plate's mob again.
-- @return the text shown, or nil
function KillPlates:Update(unit)
    local plate = PlateFor(unit)
    local old = plateOf[unit]
    if old and old ~= plate then self:Hide(old) end
    plateOf[unit], nameOf[unit] = plate, nil
    if not plate then return nil end
    local name, text
    if self:IsEnabled() then name, text = self:Read(unit) end
    nameOf[unit] = name
    if text then self:Show(plate, text) else self:Hide(plate) end
    return text
end

function KillPlates:Removed(unit)
    local plate = plateOf[unit]
    plateOf[unit], nameOf[unit] = nil, nil
    self:Hide(plate)
end

--- Every plate showing, read again.
function KillPlates:UpdateAll()
    for unit in pairs(plateOf) do self:Update(unit) end
end

--- A kill moved this mob's count: only plates of that name are read again.
function KillPlates:Killed(name)
    if not self:IsEnabled() or type(name) ~= "string" then return end
    for unit, shown in pairs(nameOf) do
        if shown == name then
            local before = KillPlates:Shown(plateOf[unit])
            local text = self:Update(unit)
            if before and text and text ~= before then
                self:Cheer(labels[plateOf[unit]])
            end
        end
    end
end

function KillPlates:SetEnabled(on)
    ns.db.killPlates = on and true or false
    self:UpdateAll()
end

--- Moves every count to the side picked.
function KillPlates:SetSide(side)
    if not IS_SIDE[side] then return end
    ns.db.killPlatesSide = side
    for plate, entry in pairs(labels) do
        if entry.placed then self:Place(plate, entry) end
    end
end

function KillPlates:SetWorthEnabled(on)
    ns.db.killPlatesWorth = on and true or false
    self:UpdateAll()
end

local function Safe(fn)
    return function(...)
        local ok = pcall(fn, ...)
        return ok
    end
end

function KillPlates:OnEnable()
    ns.RegisterEvent(self, "NAME_PLATE_UNIT_ADDED", Safe(function(_, _, unit)
        if type(unit) == "string" then KillPlates:Update(unit) end
    end))
    ns.RegisterEvent(self, "NAME_PLATE_UNIT_REMOVED", Safe(function(_, _, unit)
        if type(unit) == "string" then KillPlates:Removed(unit) end
    end))
end

ns.DB.hideWatchers.killPlates = function() KillPlates:UpdateAll() end

ns.RegisterCommand("plates", L["your kill count beside mobs' nameplates on or off"], function(rest)
    local argument = ns.Util.Trim(rest or ""):lower()
    local worth, value = argument:match("^(worth)%s*(%a*)$")
    if worth then
        local on
        if value == "on" then on = true
        elseif value == "off" then on = false
        else on = not (ns.db.killPlatesWorth == true) end
        KillPlates:SetWorthEnabled(on)
        ns.Print(on and L["worth on nameplates on."] or L["worth on nameplates off."])
    else
        local on
        if argument == "on" then on = true
        elseif argument == "off" then on = false
        else on = not KillPlates:IsEnabled() end
        KillPlates:SetEnabled(on)
        ns.Print(on and L["kill count on nameplates on."] or L["kill count on nameplates off."])
    end
    if ns.SettingsUI then ns.SettingsUI:Refresh() end
end)
