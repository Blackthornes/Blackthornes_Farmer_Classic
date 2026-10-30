-- Blackthornes Farmer -- UI/HideMenu.lua
-- The small menu a right-click on a row opens: "Hide Mangy Wolf", "Hide
-- Light Leather". The hide list itself is Data/Database.lua's (DB:Hide);
-- this only asks which, at the mouse, and says in chat how to undo it.
--
-- It waits for a click and never hides anything by itself. It goes when one
-- of its lines is clicked, when the mouse leaves it, or after a few seconds
-- if the mouse never comes onto it.

local _, ns = ...
local L = ns.L

local HideMenu = ns.NewModule("HideMenu")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local ROW = 26
-- A row's own action first (2026-10-29: right-click opens the row's menu,
-- what a click does at the top), then up to three hide lines.
local MOST = 4
-- How far in from the rim the rows sit, and the words from a row's left.
local INSET = 4
local PAD = 10
-- Seconds it waits for the mouse to come onto it.
HideMenu.WAIT = 6

--- One line: dark glass, a shade apart from the one above, a fine line
--- under it, and the gold edge and wash under the mouse.
local function CreateLine(menu, index)
    local line = CreateFrame("Button", nil, menu)
    line:SetHeight(ROW)
    line:SetPoint("TOPLEFT", INSET, -INSET - (index - 1) * ROW)
    line:SetPoint("TOPRIGHT", -INSET, -INSET - (index - 1) * ROW)
    pcall(line.RegisterForClicks, line, "LeftButtonUp", "RightButtonUp")

    line.stripe = Theme.Fill(line, index % 2 == 1 and "glass" or "glassAlt")
    line.rule = line:CreateTexture(nil, "BACKGROUND", nil, 1)
    line.rule:SetPoint("BOTTOMLEFT")
    line.rule:SetPoint("BOTTOMRIGHT")
    line.rule:SetHeight(1)
    line.rule:SetColorTexture(Theme.Unpack("border", 0.6))
    Widgets.RowLight(line)

    line.label = Theme.CreateLabel(line, "small", "text", "LEFT")
    line.label:SetPoint("LEFT", PAD, 0)
    line.label:SetPoint("RIGHT", -PAD, 0)

    line:SetScript("OnClick", function(self) HideMenu:Pick(self.choice) end)
    line:SetScript("OnEnter", function(self)
        HideMenu.entered = true
        Widgets.SetRowLight(self, 1)
    end)
    line:SetScript("OnLeave", function(self)
        Widgets.SetRowLight(self, 0)
        if C_Timer and C_Timer.After then
            C_Timer.After(0.3, function() HideMenu:CloseIfLeft() end)
        end
    end)
    line:Hide()
    return line
end

function HideMenu:Build()
    if self.frame then return self.frame end

    -- The house menu: a thin gold rim round the dark, the lines in glass.
    local menu = Theme.CreatePanel(UIParent, "window", "accent")
    menu.inner = CreateFrame("Frame", nil, menu)
    menu.inner:SetPoint("TOPLEFT", 1, -1)
    menu.inner:SetPoint("BOTTOMRIGHT", -1, 1)
    Theme.Border(menu.inner, "metal")
    pcall(menu.SetFrameStrata, menu, "FULLSCREEN_DIALOG")
    pcall(menu.SetToplevel, menu, true)
    pcall(menu.SetClampedToScreen, menu, true)
    menu:EnableMouse(true)
    menu:Hide()

    menu.lines = {}
    for index = 1, MOST do
        menu.lines[index] = CreateLine(menu, index)
    end

    -- Leaving it closes it, once the mouse has been on it. A line takes the
    -- mouse from the menu, so the check waits a moment for it to come back.
    menu:SetScript("OnEnter", function() HideMenu.entered = true end)
    menu:SetScript("OnLeave", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(0.3, function() HideMenu:CloseIfLeft() end)
        end
    end)

    self.frame = menu
    return menu
end

--- Is the mouse over the menu or one of its lines?
local function Over(frame)
    local ok, over = pcall(frame.IsMouseOver, frame)
    return ok and over == true
end

function HideMenu:CloseIfLeft()
    local menu = self.frame
    if not (menu and menu:IsShown()) then return end
    if Over(menu) then return end
    menu:Hide()
end

--- Open at the mouse with one line per `choices` entry: { kind = "item" or
--- "source", name }. Choices without a name, or already hidden, are left
--- out; with none left it does not open.
function HideMenu:Open(choices)
    local kept = {}
    for _, choice in ipairs(choices or {}) do
        local name = choice and choice.name
        if choice and choice.kind == "action" then
            if type(choice.run) == "function" and type(choice.text) == "string" and #kept < MOST then
                kept[#kept + 1] = choice
            end
        elseif type(name) == "string" and name ~= "" and #kept < MOST then
            local hidden = choice.kind == "item" and ns.DB:IsHiddenItem(name)
                or choice.kind == "source" and ns.DB:IsHiddenSource(name)
            if not hidden then kept[#kept + 1] = choice end
        end
    end
    if #kept == 0 then return false end

    local menu = self:Build()
    local width = 120
    for index, line in ipairs(menu.lines) do
        local choice = kept[index]
        if choice then
            line.choice = choice
            if choice.kind == "action" then
                line.label:SetText(choice.text)
            elseif choice.kind == "name" then
                line.label:SetText(L["Name this mob"])
            else
                -- An item's name in its rarity colour; a mob's as it is.
                local shown = choice.kind == "item" and Util.ColorItem(choice.name) or choice.name
                line.label:SetText(L.Format("Hide %s", shown))
            end
            local w = Theme.TextWidth("small", line.label:GetText())
            local ok, drawn = pcall(line.label.GetStringWidth, line.label)
            if ok and type(drawn) == "number" and drawn > w then w = drawn end
            width = math.max(width, math.ceil(w) + PAD * 2)
            Widgets.SetRowLight(line, 0)
            line:Show()
        else
            line.choice = nil
            line:Hide()
        end
    end
    menu:SetWidth(width + INSET * 2)
    menu:SetHeight(INSET * 2 + #kept * ROW)

    -- At the mouse, its top left corner just under it.
    menu:ClearAllPoints()
    -- Called on its own: "GetCursorPosition and GetCursorPosition()" keeps
    -- only x, which left y nil and the menu in the middle of the screen.
    local x, y
    if GetCursorPosition then
        local ok, cx, cy = pcall(GetCursorPosition)
        if ok then x, y = cx, cy end
    end
    local scale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    if type(x) == "number" and type(y) == "number" and type(scale) == "number" and scale > 0 then
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - 6, y / scale + 6)
    else
        menu:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    self.entered = false
    self.opened = (self.opened or 0) + 1
    local opened = self.opened
    menu:Show()

    -- Never come onto: it goes by itself.
    if C_Timer and C_Timer.After then
        C_Timer.After(HideMenu.WAIT, function()
            if HideMenu.opened == opened and not HideMenu.entered then menu:Hide() end
        end)
    end
    return true
end

--- A line was clicked: hide it, and say how to bring it back.
function HideMenu:Pick(choice)
    if self.frame then self.frame:Hide() end
    if not choice then return end
    if choice.kind == "action" then
        local ok, err = pcall(choice.run)
        if not ok and ns.Debug then ns.Debug("row menu:", tostring(err)) end
        return
    end
    if choice.kind == "name" then
        if ns.NamePrompt then ns.NamePrompt:Open(choice.npcID) end
        return
    end
    local name = ns.DB:Hide(choice.kind, choice.name)
    if not name then return end
    -- A mob or a node is a "source".
    local shown = Util.Colored("accent", name)
    if choice.kind == "item" then
        shown = Util.ColorItemOr("accent", name)
        ns.Print(L.Format("hid item %s. /farm hidden lists what you hid, with Show again.", shown))
    else
        ns.Print(L.Format("hid mob or node %s. /farm hidden lists what you hid, with Show again.", shown))
    end
end
