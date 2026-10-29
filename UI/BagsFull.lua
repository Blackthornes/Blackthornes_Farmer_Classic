-- Blackthornes Farmer -- UI/BagsFull.lua
-- A short notice on screen when the bags fill up (the owner asked
-- 2026-10-15: "an onscreen notification in farmer when bags are full").
--
-- Once a fill: it shows when the bags that take anything (Trash.Space, so a
-- herb bag's room doesn't count) go from having room to none, holds a few
-- seconds and fades. It comes back only after a slot frees and the bags fill
-- again, never on every loot.
--
-- It waits while a fight is on and shows when it ends, if the bags are still
-- full. At a vendor, the bank, a mailbox, the auction house or a trade the
-- bags fill on purpose, so a fill there is noted and nothing shows. The bags
-- as they are at login are only noted too.
--
-- Its own frame on UIParent, taking no mouse; nothing is written on a game
-- frame. No sound. Bag events only mark it stale; one look follows SETTLE
-- seconds after the burst, a handful of client calls.
--
-- "Bags full notice" on the Loot page (`bagsFullNotice`, on unless
-- unticked, never rename it) and /farm bagsfull [on|off|test].

local _, ns = ...
local L = ns.L

local BagsFull = ns.NewModule("BagsFull")

local Theme = ns.Theme

BagsFull.SETTLE = 0.3
BagsFull.HOLD = 4
BagsFull.FADE_IN = 0.25
BagsFull.FADE_OUT = 0.8
BagsFull.ICON = [[Interface\Icons\INV_Misc_Bag_08]]

local ICON_SIZE = 22
local PAD = 10
local HEIGHT = 36

-- Places where the bags fill on purpose: [event that opens] = event that closes.
local PLACES = {
    MERCHANT_SHOW = "MERCHANT_CLOSED",
    BANKFRAME_OPENED = "BANKFRAME_CLOSED",
    MAIL_SHOW = "MAIL_CLOSED",
    AUCTION_HOUSE_SHOW = "AUCTION_HOUSE_CLOSED",
    TRADE_SHOW = "TRADE_CLOSED",
}

-- nil until the bags were read once, then whether they were full.
BagsFull.full = nil
BagsFull.pending = false
BagsFull.at = {}

local function InCombat()
    local fn = rawget(_G, "InCombatLockdown")
    if type(fn) ~= "function" then return false end
    local ok, fighting = pcall(fn)
    return ok and fighting and true or false
end

function BagsFull:Enabled()
    return ns.db ~= nil and ns.db.bagsFullNotice ~= false
end

function BagsFull:SetEnabled(on)
    ns.db.bagsFullNotice = on and true or false
    if not on then
        self.pending = false
        self:Hide()
    end
end

--- At a vendor, the bank, a mailbox, the auction house or a trade.
function BagsFull:AtAPlace()
    for _, open in pairs(self.at) do
        if open then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- The notice
--------------------------------------------------------------------------------

function BagsFull:Frame()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetHeight(HEIGHT)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -150)
    pcall(frame.EnableMouse, frame, false)

    Theme.Fill(frame, "glass", 0.94)
    Theme.Border(frame, "accent", 0.9)
    Theme.Halo(frame, 8, 0.18)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", PAD, 0)
    icon:SetTexture(self.ICON)
    pcall(icon.SetTexCoord, icon, 0.07, 0.93, 0.07, 0.93)
    frame.icon = icon

    local text = Theme.CreateLabel(frame, "normal", "gilt", "LEFT")
    text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    frame.text = text

    frame:Hide()
    self.frame = frame
    return frame
end

function BagsFull:Hide()
    if self.card then
        if self.card.key == "farmer:bagsfull" and ns.Notice and ns.Notice.Remove then
            ns.Notice.Remove(self.card)
        end
        self.card = nil
        self.shownAt = nil
    end
    if not self.frame then return end
    if ns.Motion then ns.Motion:Stop(self.frame, "fade") end
    self.shownAt = nil
    self.frame:Hide()
end

--- Put the notice up, then let it fade after HOLD seconds.
function BagsFull:Show()
    local words = L["Your bags are full."]
    -- The shared note slot (UI/Notice.lua), so it never lands on another
    -- addon's note; the old card only when the shared one is missing.
    if ns.Notice and ns.Notice.Show then
        local ok, card = pcall(ns.Notice.Show, ns.Notice, words,
            { icon = self.ICON, hold = self.HOLD, key = "farmer:bagsfull" })
        if ok and card then
            local shownAt = (rawget(_G, "GetTime") or os.time)()
            self.shownAt = shownAt
            self.card = card
            C_Timer.After(self.HOLD + self.FADE_IN + self.FADE_OUT, function()
                if BagsFull.shownAt == shownAt then BagsFull:Hide() end
            end)
            return
        end
    end
    local frame = self:Frame()
    frame.text:SetText(words)
    -- Sized from the measured words, so they never end in "...".
    local width = Theme.TextWidth("normal", words)
    frame.text:SetWidth(width + 2)
    frame:SetWidth(PAD + ICON_SIZE + 8 + width + 2 + PAD + 4)

    local Motion = ns.Motion
    if Motion then Motion:Stop(frame, "fade") end
    frame:SetAlpha(1)
    frame:Show()

    local shownAt = (rawget(_G, "GetTime") or os.time)()
    self.shownAt = shownAt
    if Motion then
        Motion:Run(frame, "fade", self.FADE_IN, function(p) frame:SetAlpha(p) end)
    end

    C_Timer.After(self.HOLD, function()
        if BagsFull.shownAt ~= shownAt then return end
        if Motion then
            Motion:Run(frame, "fade", BagsFull.FADE_OUT, function(p) frame:SetAlpha(1 - p) end,
                { done = function()
                    if BagsFull.shownAt == shownAt then BagsFull:Hide() end
                end })
        else
            BagsFull:Hide()
        end
    end)
end

--------------------------------------------------------------------------------
-- Watching the bags
--------------------------------------------------------------------------------

--- Look at the bags once the burst is over.
function BagsFull:Changed()
    if self.settling then return end
    self.settling = true
    C_Timer.After(self.SETTLE, function()
        BagsFull.settling = false
        BagsFull:Check()
    end)
end

--- Whether the bags that take anything have no free slot; nil when the
--- client says nothing yet.
function BagsFull.IsFull()
    local space = ns.Trash and ns.Trash.Space and ns.Trash.Space()
    if not space then return nil end
    return space.free <= 0
end

function BagsFull:Check()
    local full = self.IsFull()
    if full == nil then return end

    if not full then
        self.full = false
        self.pending = false
        return
    end

    -- The first read (login, a /reload) only notes how they are.
    if self.full == nil then
        self.full = true
        return
    end
    if self.full then return end
    self.full = true

    if not self:Enabled() or self:AtAPlace() then return end
    if InCombat() then
        self.pending = true
        return
    end
    self:Show()
end

--- A fight ended: show a notice that waited for it, if still full.
function BagsFull:FightOver()
    if not self.pending then return end
    self.pending = false
    if self:Enabled() and not self:AtAPlace() and self.IsFull() then self:Show() end
end

function BagsFull:OnEnable()
    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", function() BagsFull:Changed() end)
    ns.RegisterEvent(self, "BAG_CONTAINER_UPDATE", function() BagsFull:Changed() end)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function() BagsFull:Changed() end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function() BagsFull:FightOver() end)
    for open, close in pairs(PLACES) do
        ns.RegisterEvent(self, open, function()
            BagsFull.at[open] = true
            BagsFull.pending = false
        end)
        ns.RegisterEvent(self, close, function()
            BagsFull.at[open] = nil
            -- What changed while there is noted now, so walking away from
            -- the bank with full bags shows nothing.
            local full = BagsFull.IsFull()
            if full ~= nil then BagsFull.full = full end
        end)
    end
end

ns.RegisterCommand("bagsfull", L["show a notice on screen when your bags fill up (on/off, test)"], function(rest)
    local word = ns.Util.Trim(rest):lower()
    if word == "test" then
        BagsFull:Show()
        return
    end
    local on
    if word == "on" then on = true
    elseif word == "off" then on = false
    else on = not BagsFull:Enabled() end
    BagsFull:SetEnabled(on)
    ns.Print(on and L["a notice shows on screen when your bags fill up."]
        or L["no notice shows when your bags fill up."])
end)
