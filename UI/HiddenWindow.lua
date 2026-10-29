-- Blackthornes Farmer -- UI/HiddenWindow.lua
-- The hide list as a window: everything a player hid (a right-click's
-- "Hide", or /farm hide), each with Show again. The list is
-- Data/Database.lua's (DB:Hide, DB:Unhide, DB:HiddenEntries).
--
-- Drawn only while open, and again only when the list moves
-- (DB.hiddenVersion).

local _, ns = ...
local L = ns.L

local HiddenUI = ns.NewModule("HiddenUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local WIDTH = 400
local HEIGHT = 380
local PADDING = 14
local ROW = 26

local KIND_TAG = { item = L["ITEM"], source = L["MOB / NODE"] }

function HiddenUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesFarmerHiddenFrame", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER", 0, 20)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()

    Theme.Fill(frame, "window")
    local trim
    if ns.Titanforged then
        trim = ns.Titanforged:Dress(frame, {
            title = L["Hidden"],
            close = function() HiddenUI:Hide() end,
        })
        local left, right, top, bottom = ns.Titanforged.Reach(trim)
        if frame.SetClampRectInsets then
            pcall(frame.SetClampRectInsets, frame, -left, right, top, -bottom)
        end
    else
        Theme.Border(frame, "borderLit")
    end
    Theme.Halo(frame, 8, 0.10)

    frame:SetScript("OnDragStart", function(self)
        ns.Motion:Stop(self, "open", true)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesFarmerHiddenFrame")
    end
    self.frame = frame

    Widgets.ApplySize(frame, ns.db and ns.db.hiddenScale)
    self.sizeGrip = Widgets.CreateSizeGrip(frame, {
        below = trim and select(4, ns.Titanforged.Reach(trim)) or 0,
        get = function() return ns.db and ns.db.hiddenScale end,
        save = function(percent) if ns.db then ns.db.hiddenScale = percent end end,
    })

    local hint = Theme.CreateLabel(frame, "small", "muted")
    hint:SetPoint("TOPLEFT", PADDING, -38)
    hint:SetPoint("TOPRIGHT", -PADDING, -38)
    hint:SetWordWrap(true)
    hint:SetText(L["Mobs, nodes and items you hid are left out of the search, Rankings, Grind and the kills panel. Nothing you recorded is lost."])

    local panel = Theme.CreatePanel(frame, "panel", "border")
    panel:SetPoint("TOPLEFT", PADDING, -84)
    panel:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
    if Theme.Recess then Theme.Recess(panel) end

    local list = Widgets.CreateRowList(panel, {
        rowHeight = ROW,
        createRow = function(row) HiddenUI:CreateRow(row) end,
        updateRow = function(row, data) HiddenUI:UpdateRow(row, data) end,
        fadeKey = "well",
    })
    list:SetPoint("TOPLEFT", 6, -6)
    list:SetPoint("BOTTOMRIGHT", -6, 6)
    self.list = list

    -- The house empty block (Widgets.CreateEmpty, 2026-10-29).
    local empty = Widgets.CreateEmpty(panel, { width = 260 })
    empty:SetPoint("TOP", 0, -24)
    empty:SetText(L["Nothing hidden. Right-click a mob or an item in the search, Rankings, Grind or the kills panel to hide it, or type /farm hide and its name."])
    self.empty = empty

    return frame
end

function HiddenUI:CreateRow(row)
    row.tag = Theme.CreateLabel(row, "tiny", "dim")
    row.tag:SetPoint("LEFT", 6, 0)
    row.tag:SetWidth(76)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", row.tag, "RIGHT", 4, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -104, 0)
    row.name:SetWordWrap(true)

    row.show = Widgets.CreateButton(row, L["Show again"], function()
        if row.data then HiddenUI:ShowAgain(row.data) end
    end, { width = 96, height = 20 })
    row.show:SetPoint("RIGHT", -4, 0)
end

function HiddenUI:UpdateRow(row, data)
    row.tag:SetText(KIND_TAG[data.kind] or "")
    row.name:SetText(data.kind == "item" and Util.ColorItem(data.name) or data.name)
end

--- Take one entry off the list and say so.
function HiddenUI:ShowAgain(data)
    local name = ns.DB:Unhide(data.kind, data.name)
    if name then
        local shown = data.kind == "item" and Util.ColorItemOr("accent", name) or Util.Colored("accent", name)
        ns.Print(L.Format("%s is shown again.", shown))
    end
end

--- Draw the list, only when it moved since the last draw.
function HiddenUI:Render()
    if not (self.frame and self.frame:IsShown()) then return end
    if self.drawn == ns.DB.hiddenVersion then return end
    self.drawn = ns.DB.hiddenVersion

    local entries = ns.DB:HiddenEntries()
    self.list:SetData(entries)
    self.empty:SetShown(#entries == 0)
end

-- An item's rarity came in late: the rows on screen take its colour.
Util.OnRarity("hidden", function()
    if HiddenUI.frame and HiddenUI.frame:IsShown() and HiddenUI.list then HiddenUI.list:Refresh() end
end)

function HiddenUI:Show()
    self:Build()
    local opening = not self.frame:IsShown()
    self.frame:Show()
    self.drawn = nil
    self:Render()
    if opening and ns.Motion and ns.Motion.Open then ns.Motion:Open(self.frame) end
end

function HiddenUI:Hide()
    if self.frame then self.frame:Hide() end
end

function HiddenUI:Toggle()
    if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end
end

ns.DB.hideWatchers.hiddenWindow = function() HiddenUI:Render() end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

--- "item Light Leather", "mob Mangy Wolf" or just a name: which list, and
--- the name. A bare name is an item when the data knows an item by it,
--- else a mob or node.
local function Parse(rest)
    local text = Util.Trim(rest or "")
    local word, after = text:match("^(%S+)%s+(.+)$")
    word = word and word:lower()
    if word == "item" then return "item", Util.Trim(after) end
    if word == "mob" or word == "node" then return "source", Util.Trim(after) end
    if text == "" then return nil, "" end
    return ns.DB:GetItem(text) and "item" or "source", text
end

ns.RegisterCommand("hide", L["hide a mob, node or item from the lists: /farm hide <name>, or on its own to see what's hidden"], function(rest)
    local kind, name = Parse(rest)
    if not kind then
        HiddenUI:Toggle()
        return
    end
    local kept = ns.DB:Hide(kind, name)
    if kept then
        local shown = kind == "item" and Util.ColorItemOr("accent", kept) or Util.Colored("accent", kept)
        ns.Print(L.Format("hid %s. /farm unhide %s shows it again.", shown, kept))
    end
end)

ns.RegisterCommand("unhide", L["show a hidden mob, node or item again: /farm unhide <name>"], function(rest)
    local kind, name = Parse(rest)
    if not kind then
        HiddenUI:Show()
        return
    end
    local had = ns.DB:Unhide(kind, name)
        or ns.DB:Unhide(kind == "item" and "source" or "item", name)
    if had then
        ns.Print(L.Format("%s is shown again.", Util.Colored("accent", had)))
    else
        ns.Print(L.Format("%s is not hidden. /farm hidden lists what is.", name))
    end
end)

ns.RegisterCommand("hidden", L["list what you hid, each with Show again"], function()
    HiddenUI:Toggle()
end)
