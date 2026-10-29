-- Blackthornes Farmer -- UI/Import.lua
-- The window where another player's data string is pasted (Logic/Transfer.lua).
--
-- Paste, read what it would add, press Apply. Nothing changes before Apply,
-- and an import can be taken back out from the list underneath.

local _, ns = ...
local L = ns.L

local UI = ns.UI

local Theme = ns.Theme
local Widgets = ns.Widgets

local WIDTH = 560
local HEIGHT = 480
local PADDING = 14
local ROWS = 4

function UI:BuildImport()
    if self.importFrame then return self.importFrame end

    local frame = CreateFrame("Frame", "BlackthornesFarmerImportFrame", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER", 0, 20)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    Theme.Fill(frame, "window")
    local trim
    if ns.Titanforged then
        trim = ns.Titanforged:Dress(frame, {
            title = L["Take data"],
            close = function() UI:HideImport() end,
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
        table.insert(UISpecialFrames, "BlackthornesFarmerImportFrame")
    end
    self.importFrame = frame

    Widgets.ApplySize(frame, ns.db and ns.db.importScale)
    self.importGrip = Widgets.CreateSizeGrip(frame, {
        below = trim and select(4, ns.Titanforged.Reach(trim)) or 0,
        get = function() return ns.db and ns.db.importScale end,
        save = function(percent) if ns.db then ns.db.importScale = percent end end,
    })

    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", 8, -32)
    rule:SetPoint("TOPRIGHT", -8, -32)
    rule:SetHeight(1)
    Theme.SetGradientAlpha(rule, "HORIZONTAL", "accent", 0.6, 0.05)

    local hint = Theme.CreateLabel(frame, "small", "muted")
    hint:SetPoint("TOPLEFT", PADDING, -42)
    hint:SetPoint("TOPRIGHT", -PADDING, -42)
    hint:SetWordWrap(true)
    hint:SetText(L["Click the box and press Ctrl+V to paste what another player sent you (the whole line, starting BFR1). Nothing is added until you press Apply."])

    -- The paste box.
    local panel = Theme.CreatePanel(frame, "panel", "border")
    panel:SetPoint("TOPLEFT", PADDING, -76)
    panel:SetPoint("TOPRIGHT", -PADDING, -76)
    panel:SetHeight(96)

    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -8, 8)
    scroll:EnableMouseWheel(true)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFont(Theme.FONT, Theme.sizes.small, "")
    edit:SetTextColor(Theme.Unpack("text"))
    edit:SetWidth(WIDTH - PADDING * 2 - 20)
    edit:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    edit:SetScript("OnTextChanged", function(_, userInput)
        if userInput then UI:ImportChanged() end
    end)
    scroll:SetScrollChild(edit)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - delta * 30)))
    end)
    -- A click anywhere in the panel is a click in the box.
    panel:EnableMouse(true)
    panel:SetScript("OnMouseDown", function() edit:SetFocus() end)
    self.importEdit = edit

    -- What it would do.
    local preview = Theme.CreateLabel(frame, "small", "text")
    preview:SetPoint("TOPLEFT", PADDING, -182)
    preview:SetPoint("TOPRIGHT", -PADDING, -182)
    preview:SetHeight(100)
    preview:SetJustifyV("TOP")
    preview:SetWordWrap(true)
    self.importPreview = preview

    -- Taken in before.
    local heading = Theme.CreateLabel(frame, "small", "accent")
    heading:SetPoint("TOPLEFT", PADDING, -296)
    heading:SetText(L["TAKEN IN BEFORE"])
    self.importRows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Frame", nil, frame)
        row:SetPoint("TOPLEFT", PADDING, -316 - (i - 1) * 26)
        row:SetPoint("TOPRIGHT", -PADDING, -316 - (i - 1) * 26)
        row:SetHeight(24)
        row.label = Theme.CreateLabel(row, "small", "text")
        row.label:SetPoint("LEFT", 0, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -100, 0)
        row.remove = Widgets.CreateButton(row, L["Remove"], function() UI:ImportRemove(row) end,
            { width = 90, height = 22 })
        row.remove:SetPoint("RIGHT", 0, 0)
        row.confirming = false
        row:Hide()
        self.importRows[i] = row
    end
    local none = Theme.CreateLabel(frame, "small", "dim")
    none:SetPoint("TOPLEFT", PADDING, -316)
    none:SetText(L["Nothing yet."])
    self.importNone = none

    local more = Theme.CreateLabel(frame, "tiny", "dim")
    more:SetPoint("TOPLEFT", PADDING, -316 - ROWS * 26)
    more:SetPoint("TOPRIGHT", -PADDING, -316 - ROWS * 26)
    more:SetWordWrap(true)
    more:SetText(L["Remove takes back exactly what that text added. Your own counts are never touched."])

    -- Footer.
    local apply = Widgets.CreateButton(frame, L["Apply"], function() UI:ImportApply() end,
        { width = 90, height = 22, primary = true })
    apply:SetPoint("BOTTOMLEFT", PADDING, 12)
    apply:Hide()
    self.importApply = apply

    local clear = Widgets.CreateButton(frame, L["Clear"], function() UI:ImportClear() end,
        { width = 70, height = 22 })
    clear:SetPoint("LEFT", apply, "RIGHT", 8, 0)

    local done = Widgets.CreateButton(frame, L["Close"], function() UI:HideImport() end,
        { width = 70, height = 22 })
    done:SetPoint("BOTTOMRIGHT", -PADDING, 12)

    frame:Hide()
    return frame
end

--------------------------------------------------------------------------------
-- Reading what is pasted
--------------------------------------------------------------------------------

--- The text changed: read it once typing or pasting has settled.
function UI:ImportChanged()
    self.importStamp = (self.importStamp or 0) + 1
    local stamp = self.importStamp
    self.importPlan = nil
    self.importApply:Hide()
    self.importPreview:SetText(L["Reading..."])
    C_Timer.After(0.3, function()
        if stamp ~= UI.importStamp then return end
        ns.Transfer:Parse(UI.importEdit:GetText(), function(plan, why)
            if stamp ~= UI.importStamp then return end
            if not plan then
                UI.importPreview:SetText(why or "")
                return
            end
            local text = ns.Transfer.Describe(plan)
            UI.importPlan = plan
            UI.importPreview:SetText(text)
            -- Not while the last part is still going in: ImportApply reads
            -- this one again once it is.
            UI.importApply:SetShown(#plan.list > 0 and not ns.Transfer.applying)
        end)
    end)
end

function UI:ImportApply()
    local plan = self.importPlan
    if not plan or #plan.list == 0 then return end
    self.importPlan = nil
    self.importApply:Hide()
    self.importPreview:SetText(L["Adding..."])
    -- Something pasted while this is added is the next part: it is kept,
    -- and read again once this is in (it said "Done. 0" and was lost).
    local stamp = self.importStamp
    ns.Transfer:Apply(plan, function(taken, why)
        if why == "busy" then
            if stamp == UI.importStamp then
                UI.importPlan = plan
                UI.importApply:Show()
            end
            UI.importPreview:SetText(L["Still working on the last one. Try again in a moment."])
            return
        end
        if stamp ~= UI.importStamp then
            UI:ImportChanged()
        else
            UI.importPreview:SetText(taken == 1
                and L.Format("Done. %d entry added to your own. If there's another part, paste it next.", taken)
                or L.Format("Done. %d entries added to your own. If there's another part, paste it next.", taken))
            UI.importEdit:SetText("")
        end
        UI:ImportList()
    end)
end

function UI:ImportClear()
    self.importStamp = (self.importStamp or 0) + 1
    self.importPlan = nil
    self.importApply:Hide()
    self.importEdit:SetText("")
    self.importPreview:SetText("")
end

--- A first click asks; a second, within a few seconds, takes it back out.
function UI:ImportRemove(row)
    if not row.importId or rawget(row, "busy") then return end
    if row.confirming then
        local id = row.importId
        row.confirming = false
        row.busy = true
        row.remove:SetText(L["Removing..."])
        ns.Transfer:Remove(id, function(count, why)
            row.busy = nil
            if why == "busy" then
                row.remove:SetText(L["Remove"])
                UI.importPreview:SetText(L["Still working on the last one. Try again in a moment."])
                return
            end
            UI.importPreview:SetText(count == 1
                and L.Format("Took back what that text added (%d entry).", count)
                or L.Format("Took back what that text added (%d entries).", count))
            UI:ImportList()
        end)
        return
    end
    row.confirming = true
    row.remove:SetText(L["Click Again"])
    C_Timer.After(4, function()
        if row.confirming then
            row.confirming = false
            row.remove:SetText(L["Remove"])
        end
    end)
end

function UI:ImportList()
    if not self.importFrame then return end
    local list = ns.Transfer:List()
    for i, row in ipairs(self.importRows) do
        local item = list[i]
        row.confirming = false
        if item then
            row.importId = item.id
            row.remove:SetText(L["Remove"])
            local when = item.at > 0 and date("%d %b", item.at) or L["earlier"]
            row.label:SetText(item.records == 1
                and L.Format("From %s, taken in %s, %d entry", item.id:sub(1, 6), when, item.records)
                or L.Format("From %s, taken in %s, %d entries", item.id:sub(1, 6), when, item.records))
            row:Show()
        else
            row.importId = nil
            row:Hide()
        end
    end
    self.importNone:SetShown(#list == 0)
end

--------------------------------------------------------------------------------
-- Showing
--------------------------------------------------------------------------------

function UI:ShowImport()
    self:BuildImport()
    self:ImportList()
    if not self.importFrame:IsShown() then
        self.importFrame:Show()
        ns.Motion:Open(self.importFrame)
    end
    self.importEdit:SetFocus()
    return self.importFrame
end

function UI:HideImport()
    if not self.importFrame then return end
    self.importEdit:ClearFocus()
    self.importFrame:Hide()
end
