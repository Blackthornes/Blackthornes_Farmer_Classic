-- Blackthornes Farmer -- UI/FishingBar.lua
-- The fishing bar (the owner said build it, 2026-10-25, from a mockup whose
-- words he approved): a small window that shows while a fishing pole is in
-- the main hand, with Cast (casts Fishing) and Add Lure (a list of every
-- lure in the bags, best first; a click puts one on the pole). Under them,
-- how long the lure on the pole lasts and the Fishing skill.
--
-- Casting a spell and using an item need the player's own click on a secure
-- button, so Cast and each lure row are secure action buttons whose
-- attributes are set only out of combat. The bar hides as a fight starts
-- (PLAYER_REGEN_DISABLED, before the game locks secure frames) and comes
-- back when it ends, so nothing on it has to change in a fight. It hides
-- at a vendor, the bank, a mailbox, the auction house or a trade too, where
-- using an item from the bags does something else.
--
-- A lure goes on with the game's own two steps as one macro: use the lure,
-- then use the main hand (slot 16). The game's own box asks first when it
-- would replace a lure already on.
--
-- Smooth play: bag, gear and skill events only mark it stale; one read
-- follows `SETTLE` later and only while the bar can show. The lure's time
-- left is read every `TICK` seconds only while the bar is up, and the text
-- is set only when it changed.
--
-- "Fishing Buttons:" under FISHING on the Loot page (`fishingBar`, off
-- unless ticked) and /farm fishingbar [on|off]. Its place and size are
-- `fishingBarX`, `fishingBarY` and `fishingBarScale`. All account wide;
-- never rename them.

local _, ns = ...
local L = ns.L

local FishingBar = ns.NewModule("FishingBar")

FishingBar.WIDTH = 300
FishingBar.PAD = 16
FishingBar.BUTTON_HEIGHT = 56
FishingBar.ROW = 40
FishingBar.PICKER_WIDTH = 300
FishingBar.SETTLE = 0.2
FishingBar.TICK = 5
-- Where it first shows: its top left corner from the middle of the screen.
FishingBar.FIRST_X = -150
FishingBar.FIRST_Y = -120

-- Fishing (Apprentice); the game casts the highest rank known by its name.
FishingBar.FISHING_SPELL = 7620
FishingBar.FISHING_ICON = 136245
-- Weapon (2), fishing pole (20).
FishingBar.POLE_CLASS, FishingBar.POLE_SUBCLASS = 2, 20
FishingBar.MAIN_HAND = 16

-- Every lure Classic Era has: item ID, the skill it adds, and its English
-- name for a client that has not loaded the item yet.
FishingBar.LURES = {
    { id = 6533, bonus = 100, name = "Aquadynamic Fish Attractor" },
    { id = 6532, bonus = 75, name = "Bright Baubles" },
    { id = 7307, bonus = 75, name = "Flesh Eating Worm" },
    { id = 6530, bonus = 50, name = "Nightcrawlers" },
    { id = 6811, bonus = 50, name = "Aquadynamic Fish Lens" },
    { id = 6529, bonus = 25, name = "Shiny Bauble" },
}

-- Places where using an item from the bags sells, banks, attaches or
-- trades it: [open event] = close event. Which are open now is `at`.
local PLACES = {
    MERCHANT_SHOW = "MERCHANT_CLOSED",
    BANKFRAME_OPENED = "BANKFRAME_CLOSED",
    MAIL_SHOW = "MAIL_CLOSED",
    AUCTION_HOUSE_SHOW = "AUCTION_HOUSE_CLOSED",
    TRADE_SHOW = "TRADE_CLOSED",
}
FishingBar.at = {}

-- What the last read found.
FishingBar.lures = {}
FishingBar.pole = false

--------------------------------------------------------------------------------
-- Client calls
--------------------------------------------------------------------------------

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2)
end

local function Number(value)
    local ok, n = pcall(function()
        local n = tonumber(value)
        if n then return n + 0 end
    end)
    if ok and type(n) == "number" then return n end
    return nil
end

local function Text(value)
    local ok, text = pcall(function()
        if type(value) == "string" and value ~= "" then return value .. "" end
    end)
    return ok and text or nil
end

local function InCombat()
    local fighting = Call(rawget(_G, "InCombatLockdown"))
    return fighting and true or false
end

local function ItemAPI(name)
    local api = rawget(_G, "C_Item")
    local fn = type(api) == "table" and api[name] or nil
    if type(fn) == "function" then return fn end
    return rawget(_G, name)
end

--- Is a fishing pole in the main hand?
function FishingBar.HasPole()
    local id = Number(Call(rawget(_G, "GetInventoryItemID"), "player", FishingBar.MAIN_HAND))
    if not id then return false end
    local _, _, _, _, _, class, subclass = Call(ItemAPI("GetItemInfoInstant"), id)
    return Number(class) == FishingBar.POLE_CLASS and Number(subclass) == FishingBar.POLE_SUBCLASS
end

--- Seconds left on the lure on the pole, or nil with none on.
function FishingBar.LureLeft()
    local has, expires = Call(rawget(_G, "GetWeaponEnchantInfo"))
    local ok, on = pcall(function() return has and true or false end)
    if not (ok and on) then return nil end
    local ms = Number(expires)
    if not ms or ms <= 0 then return nil end
    return ms / 1000
end

--- The lures in the bags, best first: { id, bonus, name, count, icon }.
function FishingBar.ReadLures()
    local list = {}
    local count = ItemAPI("GetItemCount")
    for order, lure in ipairs(FishingBar.LURES) do
        local have = Number(Call(count, lure.id)) or 0
        if have > 0 then
            local name = Text(Call(ItemAPI("GetItemNameByID"), lure.id))
                or Text((Call(rawget(_G, "GetItemInfo"), lure.id)))
            if not name then
                Call(ItemAPI("RequestLoadItemDataByID"), lure.id)
                name = lure.name
            end
            local _, _, _, _, icon = Call(ItemAPI("GetItemInfoInstant"), lure.id)
            list[#list + 1] = { id = lure.id, bonus = lure.bonus, name = name, count = have,
                icon = icon or 134400, order = order }
        end
    end
    table.sort(list, function(a, b)
        if a.bonus ~= b.bonus then return a.bonus > b.bonus end
        if a.count ~= b.count then return a.count > b.count end
        return a.order < b.order
    end)
    return list
end

--- The macro that puts lure `id` on the pole.
function FishingBar.LureMacro(id)
    return ("/use item:%d\n/use %d"):format(id, FishingBar.MAIN_HAND)
end

--- The name the game casts Fishing by.
function FishingBar.SpellName()
    local name = Text((Call(rawget(_G, "GetSpellInfo"), FishingBar.FISHING_SPELL)))
    if name then return name end
    local spell = rawget(_G, "C_Spell")
    local info = type(spell) == "table" and Call(spell.GetSpellInfo, FishingBar.FISHING_SPELL)
    if type(info) == "table" then
        local ok, value = pcall(function() return info.name end)
        name = ok and Text(value) or nil
    end
    return name or "Fishing"
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

function FishingBar:Enabled()
    return ns.db ~= nil and ns.db.fishingBar == true
end

function FishingBar:SetEnabled(on)
    ns.db.fishingBar = on and true or false
    self:Changed()
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

--- A secure button wearing a house button's look: the look takes no mouse,
--- and the secure button lights it as the mouse comes and goes.
local function SecureLook(parent, name, text, opts)
    local secure = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    secure:RegisterForClicks("AnyUp")
    secure:SetAttribute("useOnKeyDown", false)
    local look = ns.Widgets.CreateButton(secure, text, nil, opts)
    look:SetAllPoints(secure)
    look:EnableMouse(false)
    secure:HookScript("OnEnter", function()
        local fn = look:GetScript("OnEnter")
        if fn then fn(look) end
    end)
    secure:HookScript("OnLeave", function()
        local fn = look:GetScript("OnLeave")
        if fn then fn(look) end
    end)
    secure.look = look
    return secure
end

--- Put an icon at the left of a button's label, the two centred together.
local function WithIcon(button, size)
    local look = rawget(button, "look") or button
    local icon = look:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    look.label:ClearAllPoints()
    look.label:SetPoint("LEFT", look, "CENTER", -(look.label:GetStringWidth() / 2) + (size + 6) / 2, 0)
    icon:SetPoint("RIGHT", look.label, "LEFT", -6, 0)
    button.icon = icon
    return icon
end

function FishingBar:Build()
    if self.frame then return self.frame end
    local Theme, Widgets = ns.Theme, ns.Widgets
    local PAD = self.PAD

    local frame = CreateFrame("Frame", "BlackthornesFarmerFishingBar", UIParent)
    frame:SetSize(self.WIDTH, 140)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()
    Theme.Fill(frame, "window")
    local trim
    if ns.Titanforged then
        trim = ns.Titanforged:Dress(frame, {
            title = L["Fishing"],
            close = function() FishingBar:Close() end,
        })
        if ns.FoldWindow then
            ns.FoldWindow:Add(frame, { canFold = function() return not InCombat() end })
        end
    else
        Theme.Border(frame, "borderLit")
    end
    Theme.Halo(frame, 8, 0.10)
    frame:SetScript("OnDragStart", function(self) if not InCombat() then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        FishingBar:SavePlace()
    end)
    frame:SetScript("OnShow", function() FishingBar:StartTicker() end)
    frame:SetScript("OnHide", function()
        FishingBar:StopTicker()
        if FishingBar.picker then FishingBar.picker:Hide() end
    end)

    local half = (self.WIDTH - PAD * 3) / 2

    local cast = SecureLook(frame, "BlackthornesFarmerFishingCast", L["Cast"],
        { primary = true, width = half, height = self.BUTTON_HEIGHT })
    cast:SetSize(half, self.BUTTON_HEIGHT)
    cast:SetPoint("TOPLEFT", PAD, -26)
    WithIcon(cast, 30):SetTexture(self.FISHING_ICON)
    self.cast = cast

    local lure = Widgets.CreateButton(frame, L["Add Lure"], function() FishingBar:TogglePicker() end,
        { width = half, height = self.BUTTON_HEIGHT })
    lure:SetSize(half, self.BUTTON_HEIGHT)
    lure:SetPoint("TOPLEFT", cast, "TOPRIGHT", PAD, 0)
    WithIcon(lure, 30):SetTexture(134400)
    lure:HookScript("OnEnter", function(button)
        if #FishingBar.lures > 0 or not GameTooltip then return end
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:SetText(L["No lures in your bags."], 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    lure:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    self.lureButton = lure

    local status = Theme.CreateLabel(frame, "normal", "good", "LEFT")
    status:SetPoint("TOPLEFT", cast, "BOTTOMLEFT", 0, -12)
    status:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    status:SetWordWrap(true)
    self.status = status

    local skill = Theme.CreateLabel(frame, "small", "muted", "LEFT")
    skill:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -4)
    skill:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    self.skill = skill

    Widgets.ApplySize(frame, ns.db and ns.db.fishingBarScale)
    self.sizeGrip = Widgets.CreateSizeGrip(frame, {
        below = trim and ns.Titanforged.Reach and select(4, ns.Titanforged.Reach(trim)) or 0,
        get = function() return ns.db and ns.db.fishingBarScale end,
        save = function(percent) if ns.db then ns.db.fishingBarScale = percent end end,
        done = function() FishingBar:SavePlace() end,
    })

    self.frame = frame
    self:Place()
    return frame
end

function FishingBar:BuildPicker()
    if self.picker then return self.picker end
    local Theme = ns.Theme
    local PAD = self.PAD

    local picker = CreateFrame("Frame", "BlackthornesFarmerLurePicker", self:Build())
    picker:SetSize(self.PICKER_WIDTH, 120)
    picker:SetPoint("TOPLEFT", self.frame, "TOPRIGHT", 14, 0)
    picker:SetFrameStrata("MEDIUM")
    picker:EnableMouse(true)
    picker:Hide()
    Theme.Fill(picker, "window")
    if ns.Titanforged then
        ns.Titanforged:Dress(picker, { title = L["Add Lure"], close = function() picker:Hide() end })
    else
        Theme.Border(picker, "borderLit")
    end

    local heading = Theme.CreateLabel(picker, "small", "accent", "LEFT")
    heading:SetPoint("TOPLEFT", 10, -22)
    heading:SetText(L["LURES IN YOUR BAGS"])
    self.heading = heading

    local foot = Theme.CreateLabel(picker, "small", "muted", "LEFT")
    foot:SetPoint("RIGHT", picker, "RIGHT", -10, 0)
    foot:SetWordWrap(true)
    foot:SetText(L["Click one to put it on your pole."])
    self.foot = foot

    self.rows = {}
    for index = 1, #self.LURES do
        local row = CreateFrame("Button", "BlackthornesFarmerLure" .. index, picker, "SecureActionButtonTemplate")
        row:RegisterForClicks("AnyUp")
        row:SetAttribute("useOnKeyDown", false)
        row:SetHeight(self.ROW)
        row:SetPoint("TOPLEFT", picker, "TOPLEFT", 6, -40 - (index - 1) * self.ROW)
        row:SetPoint("RIGHT", picker, "RIGHT", -6, 0)

        row.back = row:CreateTexture(nil, "BACKGROUND")
        row.back:SetAllPoints(row)
        local rest = index % 2 == 1 and "glass" or "glassAlt"
        row.back:SetColorTexture(Theme.Unpack(rest))
        local line = row:CreateTexture(nil, "BORDER")
        line:SetPoint("BOTTOMLEFT")
        line:SetPoint("BOTTOMRIGHT")
        line:SetHeight(1)
        line:SetColorTexture(Theme.Unpack("border", 0.6))
        row.edge = row:CreateTexture(nil, "ARTWORK")
        row.edge:SetPoint("TOPLEFT")
        row.edge:SetPoint("BOTTOMLEFT")
        row.edge:SetWidth(2)
        row.edge:SetColorTexture(Theme.Unpack("accent"))
        row.edge:Hide()

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(30, 30)
        row.icon:SetPoint("LEFT", 8, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.bonus = Theme.CreateLabel(row, "normal", "good", "RIGHT")
        row.bonus:SetPoint("RIGHT", -10, 0)
        row.name = Theme.CreateLabel(row, "normal", "text", "LEFT")
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
        row.name:SetPoint("RIGHT", row.bonus, "LEFT", -8, 0)
        row.name:SetWordWrap(true)
        row.count = Theme.CreateLabel(row, "small", "muted", "LEFT")
        row.count:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)

        row:HookScript("OnEnter", function(self)
            self.back:SetColorTexture(Theme.Unpack("glassHover"))
            self.edge:Show()
        end)
        row:HookScript("OnLeave", function(self)
            self.back:SetColorTexture(Theme.Unpack(rest))
            self.edge:Hide()
        end)
        -- On the pole: the list has done its job.
        row:HookScript("PostClick", function()
            if not InCombat() then picker:Hide() end
        end)
        row:Hide()
        self.rows[index] = row
    end

    self.picker = picker
    return picker
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

function FishingBar:Place()
    local frame = self.frame
    if not frame then return end
    frame:ClearAllPoints()
    local x, y = Number(ns.db and ns.db.fishingBarX), Number(ns.db and ns.db.fishingBarY)
    if x and y then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    else
        frame:SetPoint("TOPLEFT", UIParent, "CENTER", self.FIRST_X, self.FIRST_Y)
    end
end

function FishingBar:SavePlace()
    local frame = self.frame
    if not frame then return end
    local ok, left, top = pcall(function() return frame:GetLeft(), frame:GetTop() end)
    if ok and type(left) == "number" and type(top) == "number" then
        ns.db.fishingBarX, ns.db.fishingBarY = left, top
    end
    self:Place()
end

--- The lure line: how long the one on the pole lasts, or that none is on.
function FishingBar.StatusText()
    local left = FishingBar.LureLeft()
    if left then
        return L.Format("Lure on: %d min left", math.max(1, math.ceil(left / 60))), "good"
    end
    return L["No lure on"], "loss"
end

--- The skill line, or nil while the skill can't be read.
function FishingBar.SkillText()
    local read = ns.GatherToCap and ns.GatherToCap.ReadSkill
    if type(read) ~= "function" then return nil end
    local ok, skill, most = pcall(read, "Fishing")
    if not ok or not skill then return nil end
    return L.Format("Fishing %d / %d", skill, most or skill)
end

function FishingBar:UpdateStatus()
    if not self.status then return end
    local text, color = self.StatusText()
    if text ~= self.statusShown then
        self.statusShown = text
        self.status:SetText(text)
        self.status:SetTextColor(ns.Theme.Unpack(color))
    end
end

function FishingBar:StartTicker()
    self:StopTicker()
    self:UpdateStatus()
    self.ticker = C_Timer.NewTicker(self.TICK, function() FishingBar:UpdateStatus() end)
end

function FishingBar:StopTicker()
    if self.ticker and self.ticker.Cancel then self.ticker:Cancel() end
    self.ticker = nil
end

--- Should the bar be up now?
function FishingBar:ShouldShow()
    if not self:Enabled() or not self.pole or self.closed or self.fighting then return false end
    for _, open in pairs(self.at) do
        if open then return false end
    end
    return true
end

--- Lay the lure rows out, aimed at their lures. Out of combat only.
function FishingBar:DrawPicker()
    local picker = self:BuildPicker()
    local shown = 0
    for index, row in ipairs(self.rows) do
        local lure = self.lures[index]
        if lure then
            shown = index
            row:SetAttribute("type", "macro")
            row:SetAttribute("macrotext", self.LureMacro(lure.id))
            row.icon:SetTexture(lure.icon)
            row.name:SetText(lure.name)
            row.count:SetText("x" .. lure.count)
            row.bonus:SetText("+" .. lure.bonus)
            row:Show()
        else
            row:SetAttribute("type", nil)
            row:SetAttribute("macrotext", nil)
            row:Hide()
        end
    end
    self.foot:ClearAllPoints()
    self.foot:SetPoint("TOPLEFT", picker, "TOPLEFT", 10, -40 - shown * self.ROW - 8)
    self.foot:SetPoint("RIGHT", picker, "RIGHT", -10, 0)
    picker:SetHeight(40 + shown * self.ROW + 40)
    if shown == 0 then picker:Hide() end
end

function FishingBar:TogglePicker()
    if InCombat() or #self.lures == 0 then return end
    local picker = self:BuildPicker()
    if picker:IsShown() then
        picker:Hide()
    else
        self:DrawPicker()
        picker:Show()
    end
end

function FishingBar:Draw()
    if InCombat() then return end
    if not self:ShouldShow() then
        if self.frame then self.frame:Hide() end
        return
    end

    local frame = self:Build()
    self.cast:SetAttribute("type", "spell")
    self.cast:SetAttribute("spell", self.SpellName())

    local first = self.lures[1]
    self.lureButton.icon:SetTexture(first and first.icon or 134400)
    self.lureButton:SetAlpha(first and 1 or 0.5)

    local skill = self.SkillText()
    self.skill:SetText(skill or "")
    self.statusShown = nil
    self:UpdateStatus()

    if self.picker and self.picker:IsShown() then self:DrawPicker() end
    frame:Show()
end

--- The close gem: put away until the pole comes off and goes on again.
function FishingBar:Close()
    if InCombat() then return end
    self.closed = true
    if self.frame then self.frame:Hide() end
end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

function FishingBar:Read()
    local pole = self.HasPole()
    if not pole then self.closed = false end
    self.pole = pole
    self.lures = (pole and self:Enabled()) and self.ReadLures() or {}
    self:Draw()
end

--- Something moved: read once, a moment after the burst.
function FishingBar:Changed()
    if self.pending then return end
    self.pending = true
    C_Timer.After(self.SETTLE, function()
        FishingBar.pending = false
        FishingBar:Read()
    end)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function FishingBar:OnEnable()
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED",
            "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED", "GET_ITEM_INFO_RECEIVED" }) do
        ns.RegisterEvent(self, event, function() FishingBar:Changed() end)
    end
    -- A lure going on or wearing off.
    ns.RegisterPlayerEvent(self, "UNIT_INVENTORY_CHANGED", function(_, _, unit)
        if unit == "player" then FishingBar:UpdateStatus() end
    end)
    -- Just before combat locks secure frames: put away.
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
        FishingBar.fighting = true
        if FishingBar.frame then FishingBar.frame:Hide() end
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        FishingBar.fighting = false
        FishingBar:Read()
    end)
    -- Vendors and the rest, where using an item from the bags does
    -- something else.
    for open, close in pairs(PLACES) do
        ns.RegisterEvent(self, open, function()
            FishingBar.at[open] = true
            FishingBar:Draw()
        end)
        ns.RegisterEvent(self, close, function()
            FishingBar.at[open] = nil
            FishingBar:Draw()
        end)
    end
end

ns.RegisterCommand("fishingbar", L["the fishing bar with Cast and Add Lure (on/off)"], function(rest)
    local word = ns.Util.Trim(rest):lower()
    local on
    if word == "on" then on = true elseif word == "off" then on = false else on = not FishingBar:Enabled() end
    FishingBar:SetEnabled(on)
    ns.Print(on and L["the fishing bar shows while a fishing pole is in your hand."]
        or L["the fishing bar is hidden."])
end)
