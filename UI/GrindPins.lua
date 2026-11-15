-- Blackthornes Farmer -- UI/GrindPins.lua
-- The Grind tab's camps on the world map: a gold ring with crossed swords
-- on each camp the tab lists, on the map of its zone. Hover one for its
-- mobs; click it to point the arrow there.
--
-- Only camps with a spot are drawn, at the spot of one of their own mobs
-- (Logic/Grinding.lua), never at a place made up. They show only while the
-- Grind tab is open, and the camp the arrow follows stays after it closes
-- (a player found the swords always there, 2026-11-10). "Grinding Camps:"
-- in Settings (/farm grind pins) and the world map's gem
-- (UI/MapToggle.lua) turn them off.
--
-- Drawn the way UI/MapMarkers.lua draws its markers: plain frames on the
-- map's canvas, every client call guarded.

local _, ns = ...
local L = ns.L

local GrindPins = ns.NewModule("GrindPins")

local Theme = ns.Theme
local Util = ns.Util

local SIZE = 20
local STEP = 0.2

local ICON = [[Interface\Icons\INV_Sword_04]]
local ROUND = [[Interface\CharacterFrame\TempPortraitAlphaMask]]

GrindPins.camps = {}
GrindPins.version = 0

function GrindPins.IsOn()
    return ns.db ~= nil and ns.db.grindPins ~= false
end

function GrindPins:SetOn(on)
    ns.db.grindPins = on and true or false
    self.drawnKey = nil
    if ns.SettingsUI then pcall(ns.SettingsUI.Refresh, ns.SettingsUI) end
end

--- The camps to draw: what the Grind tab lists now.
function GrindPins:Show(camps)
    self.camps = type(camps) == "table" and camps or {}
    self.version = self.version + 1
end

--- Is the Grind tab on screen now?
function GrindPins.TabOpen()
    local view = ns.GrindingUI and ns.GrindingUI.view
    if not (view and ns.UI and ns.UI.tab == "grind") then return false end
    local frame = ns.UI.frame
    if frame and not frame:IsShown() then return false end
    local ok, shown = pcall(view.IsShown, view)
    return ok and shown and true or false
end

--- The camp the arrow follows, or nil.
function GrindPins.Followed()
    local camp = ns.Arrow and ns.Arrow.grind
    return type(camp) == "table" and camp or nil
end

--- The camps to draw now: all the tab lists while it is open, else only
--- the one the arrow follows.
function GrindPins:Shown()
    if GrindPins.TabOpen() then return self.camps end
    local camp = GrindPins.Followed()
    return camp and { camp } or {}
end

--- The camps on the map called `mapName` (map `mapID`), with a spot, out of
--- `camps` (all the tab lists when nil).
--
-- The camps' zones are the data's English names; a client in another
-- language names its maps in its own, so there the map's ID is matched too
-- (Spots.ZONE_MAPS).
function GrindPins:CampsOn(mapName, mapID, camps)
    local on = {}
    if type(mapName) ~= "string" then return on end
    local byID = mapID and not ns.Util.EnglishClient()
    for _, camp in ipairs(camps or self.camps) do
        local here = camp.zone == mapName
            or (byID and ns.Spots.ZONE_MAPS[ns.Spots.English(camp.zone)] == mapID)
        if here and type(camp.coords) == "table" then on[#on + 1] = camp end
    end
    return on
end

--------------------------------------------------------------------------------
-- A pin
--------------------------------------------------------------------------------

local function ShowTooltip(pin)
    local camp = pin.camp
    if not (camp and GameTooltip) then return end
    pcall(GameTooltip.SetOwner, GameTooltip, pin, "ANCHOR_RIGHT")
    GameTooltip:AddLine(("%s, %s"):format(ns.Spots.Show(camp.zone), camp.label or ""), Theme.Unpack("accent"))
    GameTooltip:AddLine(L.Format("Level %s, %s", ns.Search:LevelText(camp), Util.Plural(camp.count or 0, L["mob"], L["mobs"])),
        1, 1, 1)
    for _, mob in ipairs(camp.mobs or {}) do
        GameTooltip:AddDoubleLine(mob.name, mob.type and ns.Grinding.TypeLabel(mob.type) or "", 0.9, 0.9, 0.9, Theme.Unpack("muted"))
    end
    GameTooltip:AddLine(L["Click to point the arrow here."], Theme.Unpack("good"))
    GameTooltip:Show()
end

local function CreatePin(parent)
    local pin = CreateFrame("Button", nil, parent)
    pin:SetSize(SIZE, SIZE)

    local ring = pin:CreateTexture(nil, "BACKGROUND")
    ring:SetAllPoints(pin)
    ring:SetTexture(ROUND)
    ring:SetVertexColor(Theme.Unpack("accent"))

    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexture(ICON)
    pcall(icon.SetMask, icon, ROUND)

    pin:SetScript("OnEnter", ShowTooltip)
    pin:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    pin:SetScript("OnClick", function(self)
        if self.camp then
            ns.Arrow:Grind(self.camp)
            ns.Print(ns.Grinding:Line(self.camp))
        end
    end)
    return pin
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

--- The name of the map `mapID`, or nil.
local function MapName(mapID)
    if not (type(C_Map) == "table" and type(C_Map.GetMapInfo) == "function") then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, mapID)
    if not ok or type(info) ~= "table" then return nil end
    local okName, name = pcall(function() return info.name end)
    return okName and ns.Harvest.Readable(name) or nil
end

function GrindPins:Draw()
    local view = ns.MapMarkers and ns.MapMarkers:WorldView()
    local pins = self.pins or {}
    self.pins = pins

    if not view or not GrindPins.IsOn() then
        -- Hidden once; the driver asks again five times a second while the
        -- map is closed, and there is nothing to redo.
        if self.drawnKey ~= nil or not self.hiddenAll then
            for _, pin in ipairs(pins) do pin:Hide() end
            self.drawnKey = nil
            self.hiddenAll = true
        end
        return 0
    end
    self.hiddenAll = nil

    local open = GrindPins.TabOpen()
    local followed = not open and GrindPins.Followed() or nil
    local key = ("%d:%s:%s:%s:%d:%s:%s"):format(view.mapID, view.scale, view.width, view.height, self.version,
        open and "tab" or "", followed and tostring(followed) or "")
    if key == self.drawnKey then return nil end
    self.drawnKey = key

    if self.parent ~= view.canvas then
        for _, pin in ipairs(pins) do pin:Hide() end
        pins = {}
        self.pins = pins
        self.parent = view.canvas
    end

    -- Over the gathered-node markers and the kill heat glow.
    local level = ns.MapMarkers.BaseLevel(view.canvas) + 4
    local scale = 1 / view.scale

    local used = 0
    for _, camp in ipairs(self:CampsOn(MapName(view.mapID), view.mapID, self:Shown())) do
        used = used + 1
        local pin = pins[used]
        if not pin then
            pin = CreatePin(view.canvas)
            pins[used] = pin
        end
        pin.camp = camp
        pin:SetScale(scale)
        pin:SetFrameLevel(level)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", view.canvas, "TOPLEFT",
            camp.coords[1] / 100 * view.width / scale, -camp.coords[2] / 100 * view.height / scale)
        pin:Show()
    end
    for index = used + 1, #pins do pins[index]:Hide() end

    return used
end

function GrindPins:OnEnable()
    local driver = CreateFrame("Frame", nil, UIParent)
    driver.since = 0
    driver:SetScript("OnUpdate", function(selfDriver, elapsed)
        selfDriver.since = selfDriver.since + (elapsed or 0)
        if selfDriver.since < STEP then return end
        selfDriver.since = 0
        local ok, err = pcall(GrindPins.Draw, GrindPins)
        if not ok then ns.Debug("grinding pins:", tostring(err)) end
    end)
    driver:Show()
    self.driver = driver
end
