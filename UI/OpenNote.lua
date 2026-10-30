-- Blackthornes Farmer -- UI/OpenNote.lua
-- A small note on screen each time a clam, sack or lockbox from the bags is
-- opened and counted (the owner asked 2026-10-15: opening one "did not
-- update anything on screen").
--
-- Before Value.MIN_OPENS it says how far along the count is ("Small
-- Barnacled Clam: 3 of 10 opened"); from then on, what one opening is worth
-- on average (Value:Contents). Nothing about guild data or anyone else:
-- only the player's own openings (Containers).
--
-- Its own frame on UIParent, near the top of the screen. It fades in, holds
-- HOLD seconds and fades out; Window effects Off shows it and takes it away
-- with no fade. Its OnUpdate runs only while it shows. A new opening
-- replaces the note on screen.
--
-- "Clams and sacks" on the Loot page (`openNote`, account wide, on unless
-- unticked, never rename it) and /farm opennote.

local _, ns = ...
local L = ns.L

local OpenNote = ns.NewModule("OpenNote")

-- How long it stays, and how long the fades take, in seconds.
OpenNote.HOLD = 3
OpenNote.FADE = 0.35

-- Where it sits: down from the top of the screen, under the bags full
-- notice (UI/BagsFull.lua, at -150), so the two never cover each other.
OpenNote.TOP = -210

local ICON = 22
local PAD = 8

function OpenNote:Enabled()
    return ns.db ~= nil and ns.db.openNote ~= false
end

function OpenNote:SetEnabled(on)
    ns.db.openNote = on and true or false
    if not on then self:Hide() end
end

--- The note's words for `name` after its `opens`th opening.
function OpenNote.Text(name, opens, id)
    local need = ns.Value.MIN_OPENS or 10
    -- The name in its rarity colour; worth is read by the plain name.
    local shown = ns.Util.ColorItem(name, id)
    if opens < need then
        return L.Format("%s: %d of %d opened", shown, opens, need)
    end

    local ok, worth = pcall(ns.Value.Contents, ns.Value, name)
    if ok and type(worth) == "number" and worth > 0 then
        return L.Format("%s: %d opened, about %s each", shown, opens, ns.Value.Coins(worth))
    end
    return L.Format("%s: %d opened", shown, opens)
end

function OpenNote:Build()
    if self.frame then return self.frame end

    local Theme = ns.Theme
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetPoint("TOP", UIParent, "TOP", 0, OpenNote.TOP)
    frame:SetHeight(ICON + PAD * 2)
    frame:EnableMouse(false)

    Theme.Fill(frame, "glass", 0.92)
    Theme.Border(frame, "accent")

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON, ICON)
    icon:SetPoint("LEFT", PAD, 0)
    frame.icon = icon

    local label = Theme.CreateLabel(frame, "normal", "text", "LEFT")
    label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    frame.label = label

    frame:SetScript("OnUpdate", function(_, elapsed) OpenNote:Tick(elapsed) end)
    frame:Hide()
    self.frame = frame
    return frame
end

--- Show the note for `name` (item `id`) opened `opens` times.
function OpenNote:Show(name, id, opens)
    if not self:Enabled() or type(name) ~= "string" then return end
    opens = tonumber(opens) or 0
    if opens < 1 then return end

    self:Put(OpenNote.Text(name, opens, id), ns.Theme.ItemIcon(id) or 134400, OpenNote.HOLD)
end

--- Any note in the same place and look, whatever the setting says: drops
--- shared with a receiving character (Logic/Contribute.lua) use it too.
function OpenNote:Notice(text, icon, hold)
    if type(text) ~= "string" then return end
    self:Put(text, icon or 134400, hold or OpenNote.HOLD)
end

function OpenNote:Put(text, icon, hold)
    -- The shared note slot (UI/Notice.lua), so it never lands on another
    -- addon's note; the old card only when the shared one is missing.
    if ns.Notice and ns.Notice.Show then
        local ok, card = pcall(ns.Notice.Show, ns.Notice, text,
            { icon = icon, hold = hold, key = "farmer:opennote" })
        if ok and card then
            self.card = card
            return
        end
    end
    local frame = self:Build()
    frame.label:SetText(text)
    frame.icon:SetTexture(icon)
    self.hold = hold

    local width = ns.Theme.TextWidth("normal", text)
    frame:SetWidth(PAD * 2 + ICON + 6 + (tonumber(width) or 200) + 4)

    local level = ns.Motion and ns.Motion.Level() or "full"
    self.fade = level ~= "off"
    self.elapsed = 0
    frame:SetAlpha(self.fade and 0 or 1)
    frame:Show()
end

function OpenNote:Tick(elapsed)
    local frame = self.frame
    self.elapsed = (self.elapsed or 0) + (tonumber(elapsed) or 0)
    local t, fade = self.elapsed, OpenNote.FADE
    local total = (self.hold or OpenNote.HOLD) + (self.fade and fade * 2 or 0)

    if t >= total then
        frame:Hide()
        return
    end
    if not self.fade then return end

    if t < fade then
        frame:SetAlpha(t / fade)
    elseif t > total - fade then
        frame:SetAlpha((total - t) / fade)
    else
        frame:SetAlpha(1)
    end
end

function OpenNote:Hide()
    if self.card and self.card.key == "farmer:opennote" and ns.Notice and ns.Notice.Remove then
        ns.Notice.Remove(self.card)
    end
    if self.frame then self.frame:Hide() end
end

ns.RegisterCommand("opennote", L["show or hide the note when you open a clam, sack or lockbox"], function()
    OpenNote:SetEnabled(not OpenNote:Enabled())
    ns.Print(OpenNote:Enabled() and L["a note shows each time you open a clam, sack or lockbox."]
        or L["no note shows when you open a clam, sack or lockbox."])
end)
