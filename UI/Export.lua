-- Blackthornes Farmer -- UI/Export.lua
-- A window that hands text back to you so it can leave the game.
--
-- Why a window and not a file: an addon cannot write files. The harvest is
-- kept in SavedVariables, and tools/harvest_import.py reads it from outside;
-- this window is the way out that needs nothing but the game itself.
--
-- The text is selected the moment the window opens, so the whole interaction
-- is: run the command, press Ctrl+C, paste into your editor.

local _, ns = ...
local L = ns.L

local UI = ns.UI

local Theme = ns.Theme
local Widgets = ns.Widgets

local WIDTH = 560
local HEIGHT = 420
local PADDING = 14

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function UI:BuildExport()
    if self.exportFrame then return self.exportFrame end

    local frame = CreateFrame("Frame", "BlackthornesFarmerExportFrame", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER", 0, 20)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    Theme.Fill(frame, "window")
    -- The house frame (UI/Titanforged.lua): the gold rim and corner gems,
    -- what is being handed over on a plate across the top, and a red close
    -- gem.
    local trim
    if ns.Titanforged then
        trim = ns.Titanforged:Dress(frame, {
            title = L["Export"],
            close = function() UI:HideExport() end,
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
        -- Land an opening still running, or it would pull the window back.
        ns.Motion:Stop(self, "open", true)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    -- Escape closes it even once the box has let go of the keyboard.
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesFarmerExportFrame")
    end

    self.exportFrame = frame

    -- The house size grip under the bottom right corner
    -- (Widgets.CreateSizeGrip), saved as `exportScale`.
    Widgets.ApplySize(frame, ns.db and ns.db.exportScale)
    self.exportGrip = Widgets.CreateSizeGrip(frame, {
        below = trim and select(4, ns.Titanforged.Reach(trim)) or 0,
        get = function() return ns.db and ns.db.exportScale end,
        save = function(percent) if ns.db then ns.db.exportScale = percent end end,
    })

    -- The title is on the plate and the close gem on the corner, so the
    -- header is a gold rule fading from the left, inside the rim.
    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", 8, -32)
    rule:SetPoint("TOPRIGHT", -8, -32)
    rule:SetHeight(1)
    Theme.SetGradientAlpha(rule, "HORIZONTAL", "accent", 0.6, 0.05)

    if trim and trim.plate then
        self.exportPlate = trim.plate
        self.exportTitle = trim.plate.label
    else
        local title = Theme.CreateLabel(frame, "large", "accent")
        title:SetPoint("TOPLEFT", PADDING, -10)
        title:SetText(L["Export"])
        self.exportTitle = title
    end

    local hint = Theme.CreateLabel(frame, "small", "muted")
    hint:SetPoint("TOPLEFT", PADDING, -42)
    hint:SetPoint("TOPRIGHT", -PADDING, -42)
    hint:SetText(L["Already selected. Press Ctrl+C, then paste it into your editor."])
    self.exportHint = hint

    -- The box itself.
    local panel = Theme.CreatePanel(frame, "panel", "border")
    panel:SetPoint("TOPLEFT", PADDING, -62)
    panel:SetPoint("BOTTOMRIGHT", -PADDING, 42)
    self.exportPanel = panel

    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -24, 8)
    scroll:EnableMouseWheel(true)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFont(Theme.FONT, Theme.sizes.small, "")
    edit:SetTextColor(Theme.Unpack("text"))
    edit:SetWidth(WIDTH - PADDING * 2 - 34)
    edit:SetScript("OnEscapePressed", function() UI:HideExport() end)

    -- The text is a handout, not a form. Anything typed into it would be lost
    -- on the next export and would break a copy half-made, so put it back.
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput and UI.exportText then
            self:SetText(UI.exportText)
            self:HighlightText()
        end
    end)

    scroll:SetScrollChild(edit)
    self.exportEdit = edit
    self.exportScroll = scroll

    local slider = CreateFrame("Slider", nil, panel)
    slider:SetPoint("TOPRIGHT", -8, -8)
    slider:SetPoint("BOTTOMRIGHT", -8, 8)
    slider:SetWidth(8)
    slider:SetOrientation("VERTICAL")
    slider:SetMinMaxValues(0, 0)
    slider:SetValue(0)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    Theme.Fill(slider, "panel")

    -- The same bar as the lists': it lights gold under the mouse.
    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetColorTexture(Theme.Unpack("borderLit"))
    thumb:SetSize(8, 40)
    slider:SetThumbTexture(thumb)

    -- The Blizzard window style draws it as the game's knob, lit by tint
    -- (UI/BlizzardLook.lua).
    local Look = ns.BlizzardLook
    if Look then Look.Thumb(thumb) end

    local function Light(p)
        if Look and Look.LightThumb(thumb, p >= 0.5) then return end
        thumb:SetColorTexture(ns.Motion.Mix("borderLit", "accent", p, 1, 0.9))
    end
    slider:SetScript("OnEnter", function(self) ns.Motion:Blend(self, "hover", 1, 0.12, Light) end)
    slider:SetScript("OnLeave", function(self) ns.Motion:Blend(self, "hover", 0, 0.2, Light) end)

    slider:SetScript("OnValueChanged", function(self, value)
        scroll:SetVerticalScroll(value)
    end)

    scroll:SetScript("OnScrollRangeChanged", function(self, _, vertical)
        vertical = vertical or self:GetVerticalScrollRange() or 0
        slider:SetMinMaxValues(0, math.max(vertical, 0))
        if slider:GetValue() > vertical then slider:SetValue(vertical) end
    end)

    -- Arrow keys and selecting past the edge bring the cursor into view.
    edit:SetScript("OnCursorChanged", function(_, _, y, _, height)
        pcall(function()
            local top = slider:GetValue()
            local visible = scroll:GetHeight()
            local line = -y
            if line < top then
                slider:SetValue(line)
            elseif line + height > top + visible then
                slider:SetValue(line + height - visible)
            end
        end)
    end)

    scroll:SetScript("OnMouseWheel", function(self, delta)
        slider:SetValue(slider:GetValue() - delta * 40)
    end)

    self.exportSlider = slider

    -- Footer buttons.
    local selectAll = Widgets.CreateButton(frame, L["Select all"], function()
        UI:FocusExport()
    end, { width = 90, height = 22 })
    selectAll:SetPoint("BOTTOMLEFT", PADDING, 12)

    local done = Widgets.CreateButton(frame, L["Close"], function() UI:HideExport() end,
        { width = 70, height = 22 })
    done:SetPoint("BOTTOMRIGHT", -PADDING, 12)

    local count = Theme.CreateLabel(frame, "tiny", "dim", "RIGHT")
    count:SetPoint("BOTTOMRIGHT", done, "BOTTOMLEFT", -10, 4)
    count:SetWidth(240)
    self.exportCount = count

    -- Previous and Next, only for a handout in parts (Logic/Transfer.lua).
    local prev = Widgets.CreateButton(frame, L["Previous"], function()
        if UI.exportNav then UI.exportNav.step(-1) end
    end, { width = 80, height = 22 })
    prev:SetPoint("LEFT", selectAll, "RIGHT", 8, 0)
    prev:Hide()
    local nextPart = Widgets.CreateButton(frame, L["Next part"], function()
        if UI.exportNav then UI.exportNav.step(1) end
    end, { width = 90, height = 22 })
    nextPart:SetPoint("LEFT", prev, "RIGHT", 8, 0)
    nextPart:Hide()
    self.exportPrev, self.exportNext = prev, nextPart

    frame:Hide()
    if ns.SharedWindow and ns.SharedWindow.KeepSpot then ns.SharedWindow.KeepSpot(frame, "farmer.export") end
    return frame
end

--------------------------------------------------------------------------------
-- Showing
--------------------------------------------------------------------------------

--- Put the edit box's whole contents under the cursor, ready for Ctrl+C.
function UI:FocusExport()
    local edit = self.exportEdit
    if not edit then return end

    edit:SetFocus()
    edit:HighlightText()
end

--- The spreadsheet's sheets as tabs along the top of the window
--- (Logic/CSV.lua), shown only while a spreadsheet is; the box moves down
--- under them and the hint says what to do with a CSV.
function UI:LayExportSheets(sheets)
    local frame = self.exportFrame
    local hint, panel = self.exportHint, self.exportPanel

    if sheets and not self.exportSheets then
        local tabs = {}
        for index, key in ipairs(sheets.sheets) do
            tabs[index] = { key = key, text = sheets.labels[key] or key }
        end
        local strip = Widgets.CreateTabStrip(frame, tabs, function(key)
            if UI.exportPick then UI.exportPick(key) end
        end, { width = WIDTH - PADDING * 2 })
        strip:SetPoint("TOPLEFT", PADDING, -36)
        self.exportSheets = strip
    end

    hint:ClearAllPoints()
    panel:ClearAllPoints()
    panel:SetPoint("BOTTOMRIGHT", -PADDING, 42)

    if sheets then
        self.exportPick = sheets.pick
        self.exportSheets:Show()
        self.exportSheets:Select(sheets.current)
        hint:SetPoint("TOPLEFT", PADDING, -70)
        hint:SetPoint("TOPRIGHT", -PADDING, -70)
        hint:SetText(sheets.hint or "")
        panel:SetPoint("TOPLEFT", PADDING, -100)
    else
        self.exportPick = nil
        if self.exportSheets then self.exportSheets:Hide() end
        hint:SetPoint("TOPLEFT", PADDING, -42)
        hint:SetPoint("TOPRIGHT", -PADDING, -42)
        hint:SetText(L["Already selected. Press Ctrl+C, then paste it into your editor."])
        panel:SetPoint("TOPLEFT", PADDING, -62)
    end
end

--- Show `text` in the export window.
--
-- `title` is optional and names what is being handed over, so a single-item
-- export and a whole-session export do not look identical.
-- `nav` is optional, { index, count, step(delta) }, for a handout in parts.
-- `sheets` is optional, { sheets, labels, current, pick(key), hint }, for
-- the spreadsheet (Logic/CSV.lua).
function UI:ShowExport(text, title, nav, sheets)
    text = tostring(text or "")

    self:BuildExport()
    self:LayExportSheets(sheets)

    self.exportText = text
    self.exportNav = nav
    self.exportPrev:SetShown(nav ~= nil and nav.index > 1)
    self.exportNext:SetShown(nav ~= nil and nav.index < nav.count)
    if self.exportPlate then
        self.exportPlate:SetTitle(title or L["Export"])
    else
        self.exportTitle:SetText(title or L["Export"])
    end

    self.exportEdit:SetText(text)
    self.exportEdit:SetCursorPosition(0)
    self.exportScroll:SetVerticalScroll(0)
    self.exportSlider:SetValue(0)

    local lines = 1
    for _ in text:gmatch("\n") do lines = lines + 1 end
    self.exportCount:SetText(L.Format("%d lines, %d characters", lines, #text))

    if not self.exportFrame:IsShown() then
        self.exportFrame:Show()
        ns.Motion:Open(self.exportFrame)
    end

    -- One frame later: the edit box has to have laid out its text before
    -- highlighting it covers the whole thing.
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() UI:FocusExport() end)
    else
        self:FocusExport()
    end

    return self.exportFrame
end

function UI:HideExport()
    if not self.exportFrame then return end

    if self.exportEdit then
        self.exportEdit:ClearFocus()
    end

    self.exportFrame:Hide()
end

function UI:ToggleExport(text, title)
    if self.exportFrame and self.exportFrame:IsShown() then
        self:HideExport()
    else
        self:ShowExport(text, title)
    end
end
