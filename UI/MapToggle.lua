-- Blackthornes Farmer -- UI/MapToggle.lua
-- A small gold gem in the top right of the world map (a player asked for a
-- quick way to hide the map marks, the owner said build it from a mockup,
-- 2026-11-10). A click hides every Farmer mark on the world map at once:
-- the Grind tab's camps, the gathered node markers and the kill heat glow.
-- Another click brings back the ones that were on. A right-click opens a
-- menu with a tick for each, the same switches as the Map & Goals page.
--
-- It only flips the settings that were already there (grindPins,
-- markersWorld, heatWorld), so Settings and the gem always agree. What a
-- click hid is kept in `mapMarksKept` ({ [key] = true }) so the next click
-- puts back only those. "Map Button:" on the Map & Goals page
-- (`mapButton`, on unless unticked) and `/farm markers button on|off`.
-- Never rename either key.
--
-- The gem is our own frame, a child of the world map so it shows and goes
-- with it. Nothing on the game's map is moved, hidden or written to.

local _, ns = ...
local L = ns.L

local MapToggle = ns.NewModule("MapToggle")

local MEDIA = [[Interface\AddOns\Blackthornes_Farmer\Media\Frame\]]
local GEM = 20
local LOOK = 0.5

--- Each mark the gem switches: its saved key, its name, whether it is on,
--- and how to turn it on or off (the same calls Settings makes).
function MapToggle.Kinds()
    return {
        { key = "grindPins", text = L["Grinding Camps"],
            on = function() return ns.GrindPins and ns.GrindPins.IsOn() end,
            set = function(on) ns.GrindPins:SetOn(on) end },
        { key = "markersWorld", text = L["Gathered Nodes"],
            on = function() return ns.MapMarkers and ns.MapMarkers.WorldOn() end,
            set = function(on) ns.MapMarkers:SetWorld(on) end },
        { key = "heatWorld", text = L["Kill Heat"],
            on = function() return ns.Heat and ns.Heat.WorldOn() end,
            set = function(on) ns.Heat:SetWorld(on) end },
    }
end

local function Refresh()
    if ns.SettingsUI then pcall(ns.SettingsUI.Refresh, ns.SettingsUI) end
    MapToggle:Paint()
end

--- Is any Farmer mark on the world map turned on?
function MapToggle.AnyOn()
    for _, kind in ipairs(MapToggle.Kinds()) do
        if kind.on() then return true end
    end
    return false
end

--- One click: hide them all and keep which were on, or bring those back.
--- With nothing kept, the camps and gathered nodes come back (their usual
--- setting; the kill heat is off unless picked).
function MapToggle:Toggle()
    if not ns.db then return end
    local kinds = MapToggle.Kinds()
    if MapToggle.AnyOn() then
        local kept = {}
        for _, kind in ipairs(kinds) do
            if kind.on() then
                kept[kind.key] = true
                kind.set(false)
            end
        end
        ns.db.mapMarksKept = kept
    else
        local kept = type(ns.db.mapMarksKept) == "table" and ns.db.mapMarksKept or nil
        if not (kept and next(kept)) then kept = { grindPins = true, markersWorld = true } end
        for _, kind in ipairs(kinds) do
            if kept[kind.key] then kind.set(true) end
        end
    end
    Refresh()
end

--- The right-click menu: a tick for each mark.
function MapToggle:Menu()
    if not ns.RowMenu then return nil end
    local lines = {}
    for _, kind in ipairs(MapToggle.Kinds()) do
        local on = kind.on() and true or false
        lines[#lines + 1] = { text = kind.text, checked = on, run = function()
            kind.set(not on)
            Refresh()
        end }
    end
    return ns.RowMenu:Open(lines, { title = L["FARMER MAP MARKS"] })
end

function MapToggle.ButtonOn()
    return ns.db ~= nil and ns.db.mapButton ~= false
end

function MapToggle:SetButton(on)
    ns.db.mapButton = on and true or false
    Refresh()
end

--------------------------------------------------------------------------------
-- The gem
--------------------------------------------------------------------------------

local function ShowTooltip(gem)
    if not GameTooltip then return end
    pcall(GameTooltip.SetOwner, GameTooltip, gem, "ANCHOR_LEFT")
    GameTooltip:AddLine(L["Farmer Map Marks"], ns.Theme.Unpack("accent"))
    if MapToggle.AnyOn() then
        GameTooltip:AddLine(L["Click to hide them. Right-click to pick which."], 1, 1, 1, true)
    else
        GameTooltip:AddLine(L["Click to show them. Right-click to pick which."], 1, 1, 1, true)
    end
    GameTooltip:Show()
end

function MapToggle:Build(map)
    if self.gem then return self.gem end
    local corner = rawget(map, "ScrollContainer")
    if type(corner) ~= "table" then corner = map end

    local gem = CreateFrame("Button", nil, map)
    gem:SetSize(GEM, GEM)
    gem:SetPoint("TOPRIGHT", corner, "TOPRIGHT", -8, -40)
    pcall(gem.SetFrameStrata, gem, "HIGH")
    pcall(gem.RegisterForClicks, gem, "LeftButtonUp", "RightButtonUp")

    gem.glow = gem:CreateTexture(nil, "BACKGROUND")
    gem.glow:SetTexture(MEDIA .. "Glow")
    gem.glow:SetPoint("CENTER")
    gem.glow:SetSize(GEM * 2.2, GEM * 2.2)
    gem.glow:SetVertexColor(ns.Theme.Unpack("accent"))
    pcall(gem.glow.SetBlendMode, gem.glow, "ADD")

    gem.face = gem:CreateTexture(nil, "ARTWORK")
    gem.face:SetTexture(MEDIA .. "FoldGem")
    gem.face:SetAllPoints(gem)

    gem.lit = gem:CreateTexture(nil, "ARTWORK", nil, 1)
    gem.lit:SetTexture(MEDIA .. "FoldGem")
    gem.lit:SetAllPoints(gem)
    pcall(gem.lit.SetBlendMode, gem.lit, "ADD")
    gem.lit:SetAlpha(0)

    gem:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            MapToggle:Menu()
        else
            MapToggle:Toggle()
        end
        if GameTooltip and GameTooltip:IsShown() then ShowTooltip(gem) end
    end)
    gem:SetScript("OnEnter", function(self)
        self.lit:SetAlpha(0.45)
        ShowTooltip(self)
    end)
    gem:SetScript("OnLeave", function(self)
        self.lit:SetAlpha(0)
        if GameTooltip then GameTooltip:Hide() end
    end)

    self.gem = gem
    self:Paint()
    return gem
end

--- Gold while any mark shows, grey with no glow when all are off; hidden
--- when "Map Button:" is unticked.
function MapToggle:Paint()
    local gem = self.gem
    if not gem then return end
    if not MapToggle.ButtonOn() then
        gem:Hide()
        return
    end
    gem:Show()
    local on = MapToggle.AnyOn()
    pcall(gem.face.SetDesaturated, gem.face, not on)
    gem.face:SetAlpha(on and 1 or 0.7)
    gem.glow:SetAlpha(on and 0.35 or 0)
end

--- The world map may load late, so look for it until it is there.
function MapToggle:Look()
    local map = _G.WorldMapFrame
    if type(map) ~= "table" then return false end
    local ok, err = pcall(self.Build, self, map)
    if not ok and ns.Debug then ns.Debug("map toggle:", tostring(err)) end
    return true
end

function MapToggle:OnEnable()
    if self:Look() then return end
    local finder = CreateFrame("Frame", nil, UIParent)
    finder.since = 0
    finder:SetScript("OnUpdate", function(selfFinder, elapsed)
        selfFinder.since = selfFinder.since + (elapsed or 0)
        if selfFinder.since < LOOK then return end
        selfFinder.since = 0
        if MapToggle:Look() then selfFinder:SetScript("OnUpdate", nil) end
    end)
    self.finder = finder
end
