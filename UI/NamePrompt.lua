-- Blackthornes Farmer -- UI/NamePrompt.lua
-- "Name this mob": a small box for naming a mob the game will not name.
-- Inside a dungeon Forever hides every mob's name from addons, and a mob
-- Forever added is in no list, so it shows as "Creature #250484". The
-- kills panel's right-click opens this; Harvest:NameByHand keeps the name.
--
-- Nothing is kept until Save or Enter. The panel shows the name at once,
-- and what was kept under the number moves to it at the next login.

local _, ns = ...
local L = ns.L

local NamePrompt = ns.NewModule("NamePrompt")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local WIDTH = 320
local HEIGHT = 150
local PADDING = 14

function NamePrompt:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesFarmerNamePrompt", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER", 0, 80)
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
            title = L["Name this mob"],
            close = function() NamePrompt:Hide() end,
        })
        local left, right, top, bottom = ns.Titanforged.Reach(trim)
        if frame.SetClampRectInsets then
            pcall(frame.SetClampRectInsets, frame, -left, right, top, -bottom)
        end
    else
        Theme.Border(frame, "borderLit")
    end

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesFarmerNamePrompt")
    end
    self.frame = frame

    Widgets.ApplySize(frame, ns.db and ns.db.namePromptScale)
    self.sizeGrip = Widgets.CreateSizeGrip(frame, {
        below = trim and select(4, ns.Titanforged.Reach(trim)) or 0,
        get = function() return ns.db and ns.db.namePromptScale end,
        save = function(percent) if ns.db then ns.db.namePromptScale = percent end end,
    })

    local ask = Theme.CreateLabel(frame, "small", "muted")
    ask:SetPoint("TOPLEFT", PADDING, -38)
    ask:SetPoint("TOPRIGHT", -PADDING, -38)
    ask:SetWordWrap(true)
    frame.ask = ask

    local box = Widgets.CreateSearchBox(frame, L["Its name, as your tooltip shows it"], nil,
        function(text) NamePrompt:Save(text) end, { plain = true })
    box:SetPoint("TOPLEFT", PADDING, -74)
    box:SetPoint("TOPRIGHT", -PADDING, -74)
    frame.box = box

    local save = Widgets.CreateButton(frame, L["Save"], function() NamePrompt:Save() end,
        { primary = true, width = 90 })
    save:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
    local cancel = Widgets.CreateButton(frame, L["Cancel"], function() NamePrompt:Hide() end,
        { width = 90 })
    cancel:SetPoint("RIGHT", save, "LEFT", -8, 0)

    if ns.SharedWindow and ns.SharedWindow.KeepSpot then ns.SharedWindow.KeepSpot(frame, "farmer.nameprompt") end
    return frame
end

function NamePrompt:Open(npcID)
    npcID = tonumber(npcID)
    if not npcID or ns.Harvest.KnownNpcName(npcID) then return false end
    local frame = self:Build()
    self.npcID = npcID
    frame.ask:SetText(L.Format("What is Creature #%d called? Hover or target it and type the name its tooltip shows. Your kills and loot move to the name the next time you log in.", npcID))
    frame.box:SetText("")
    local edit = frame.box.editBox
    if edit then pcall(edit.SetFocus, edit) end
    frame:Show()
    return true
end

function NamePrompt:Hide()
    if self.frame then self.frame:Hide() end
    self.npcID = nil
end

--- Keeps what was typed, if it makes a name, and says so in chat.
function NamePrompt:Save(text)
    local npcID = self.npcID
    if text == nil then
        local box = self.frame and self.frame.box
        if box then
            local ok, typed = pcall(box.GetText, box)
            text = ok and typed or nil
        end
    end
    local name = npcID and ns.Harvest:NameByHand(npcID, text)
    if not name then
        if npcID then ns.Print(L["That name can't be used. Type the name the tooltip shows."]) end
        return nil
    end
    self:Hide()
    ns.Print(L.Format("Creature #%d is now %s. Its kills and loot move to that name the next time you log in.",
        npcID, Util.Colored("accent", name)))
    if ns.TrackerUI and ns.TrackerUI.Refresh then pcall(ns.TrackerUI.Refresh, ns.TrackerUI) end
    return name
end
