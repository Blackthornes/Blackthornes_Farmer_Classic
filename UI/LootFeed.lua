-- Blackthornes Farmer -- UI/LootFeed.lua
-- A small feed of what you loot, as it comes in (a player asked, the owner
-- said build it 2026-10-19, from a mockup): a dark glass row a thing, its
-- icon, its name in its rarity colour and how many, the newest on top with
-- a gold edge. Looting the same thing again adds to its count, moves it to
-- the top and holds it again. Rows fade after `lootFeedHold` seconds, and a
-- gold line at the foot adds up the coin and what the loot is worth while
-- any row shows.
--
-- What it reads: each loot window's slots, read once when the window is
-- read (ns.OnLootWindow, ahead of fast-loot addons), and a slot goes in the
-- feed when LOOT_SLOT_CLEARED says it was taken. A client without that
-- event shows the whole window as read. Locked slots (a roll, the master
-- looter) never go in. Every client value is read in a pcall.
--
-- Its own frame on UIParent that never takes the mouse while you play, so
-- nothing under it is blocked; Move lets it be dragged and sized (the house
-- size grip), and Move again puts it back to taking no mouse. Its OnUpdate
-- runs only while it shows, and rows are laid out again only when one is
-- added, moves or goes; each frame only their alpha moves. While the mouse
-- is over it (asked without the feed taking the mouse), nothing fades, so
-- there is time to reach Move.
--
-- Saved account wide, never rename them: `lootFeed` (off unless ticked),
-- `lootFeedHold` (seconds, nil for the usual 5), `lootFeedHoldPicked`
-- (true once Show For was picked), `lootFeedWorth` (on unless unticked),
-- `lootFeedSeeThrough` (Transparent, UI/SeeThrough.lua), `lootFeedScale`,
-- `lootFeedX` and `lootFeedY` (its top left, nil for the first place).
-- Settings > Loot > LOOT FEED, and /farm lootfeed on, off, move or reset.

local _, ns = ...
local L = ns.L

local LootFeed = ns.NewModule("LootFeed")

--- At most this many rows; a new thing past it takes the oldest's place.
LootFeed.MAX_ROWS = 6
--- How long a row takes to fade, after it held, in seconds.
LootFeed.FADE = 0.5
--- Show For's steps, in seconds.
LootFeed.HOLD_MIN, LootFeed.HOLD_MAX = 2, 10
--- Show For until one is picked (the owner, 2026-10-19: 3 went too fast).
LootFeed.HOLD = 5

local ROW = 26
local ICON = 20
local PAD = 8
local EDGE = 2
local MIN_WIDTH = 240
local MAX_WIDTH = 420
-- The first place: a little right of the middle of the screen.
local FIRST_X, FIRST_Y = 300, 120
-- The bag icon, for the row Move shows.
local SAMPLE_ICON = 133639

-- Newest first: { key, name, id, icon, count, unit, at }.
LootFeed.rows = {}
LootFeed.coin = 0
-- What the open window holds, by slot, until the slot is taken.
LootFeed.pending = {}

local function Now()
    return type(GetTime) == "function" and (tonumber(GetTime()) or 0) or 0
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

function LootFeed:Enabled()
    return ns.db ~= nil and ns.db.lootFeed == true
end

function LootFeed:SetEnabled(on)
    ns.db.lootFeed = on and true or false
    if not on then self:Clear() end
end

--- Show For, in whole seconds.
function LootFeed:Hold()
    local db = ns.db
    -- The first build wrote 3 into the save before anyone picked; a 3 nobody
    -- picked goes back to the usual.
    if db and db.lootFeedHold == 3 and not db.lootFeedHoldPicked then
        db.lootFeedHold = nil
    end
    local hold = math.floor(tonumber(db and db.lootFeedHold) or LootFeed.HOLD)
    return math.max(LootFeed.HOLD_MIN, math.min(LootFeed.HOLD_MAX, hold))
end

function LootFeed:SetHold(seconds)
    seconds = math.floor(tonumber(seconds) or LootFeed.HOLD)
    ns.db.lootFeedHoldPicked = true
    ns.db.lootFeedHold = math.max(LootFeed.HOLD_MIN, math.min(LootFeed.HOLD_MAX, seconds))
end

function LootFeed:ShowsWorth()
    return ns.db ~= nil and ns.db.lootFeedWorth ~= false
end

function LootFeed:SetShowsWorth(on)
    ns.db.lootFeedWorth = on and true or false
    self:Layout()
end

--------------------------------------------------------------------------------
-- What came in
--------------------------------------------------------------------------------

local function Readable(value)
    return ns.Harvest and ns.Harvest.Readable and ns.Harvest.Readable(value) or nil
end

local function ReadableNumber(value)
    return ns.Harvest and ns.Harvest.ReadableNumber and ns.Harvest.ReadableNumber(value) or nil
end

local function IsTrue(value)
    local ok, yes = pcall(function() return value == true or value == 1 end)
    return ok and yes
end

--- The item ID in a loot slot, from its link, else by its name.
local function SlotID(slot, name)
    if type(GetLootSlotLink) == "function" then
        local ok, link = pcall(GetLootSlotLink, slot)
        local text = ok and Readable(link) or nil
        local id = text and tonumber(text:match("item:(%d+)"))
        if id then return id end
    end
    local ok, id = pcall(ns.Value.ItemID, ns.Value, name)
    return ok and tonumber(id) or nil
end

--- One slot of the open loot window: { coin } or { name, id, icon, count },
--- or nil for an empty, locked or unreadable one.
function LootFeed.ReadSlot(slot)
    local ok, icon, name, quantity, _, _, locked = pcall(GetLootSlotInfo, slot)
    local text = ok and Readable(name) or nil
    if not text then return nil end

    local okMoney, money = pcall(ns.Harvest.IsMoney, ns.Harvest, slot, text)
    if okMoney and money then
        local copper = ns.Tracker and ns.Tracker.CoinCopper and ns.Tracker.CoinCopper(text)
        return copper and copper > 0 and { coin = copper } or nil
    end
    if IsTrue(locked) then return nil end
    -- The hide list: things the player never wants to see.
    local okHidden, hidden = pcall(ns.DB.IsHiddenItem, ns.DB, text)
    if okHidden and hidden then return nil end

    local id = SlotID(slot, text)
    local shown = ns.Theme.ItemIcon(id)
    if not shown then
        local okIcon, value = pcall(function() return icon + 0 end)
        shown = okIcon and value or (type(icon) == "string" and icon) or nil
    end
    return { name = text, id = id, icon = shown, count = ReadableNumber(quantity) or 1 }
end

--- Read the window's slots, to show each as it is taken.
function LootFeed:ReadWindow()
    self.pending = {}
    if not self:Enabled() or type(GetNumLootItems) ~= "function" then return end
    local ok, count = pcall(GetNumLootItems)
    count = ok and ReadableNumber(count) or nil
    if not count then return end

    for slot = 1, count do
        local entry = LootFeed.ReadSlot(slot)
        if entry then
            if self.slotEvent then
                self.pending[slot] = entry
            else
                self:Add(entry)
            end
        end
    end
end

--- A slot was taken: it goes in the feed.
function LootFeed:SlotTaken(slot)
    slot = tonumber(slot)
    local entry = slot and self.pending[slot]
    if not entry then return end
    self.pending[slot] = nil
    if self:Enabled() then self:Add(entry) end
end

--- What one of `name` is worth, in copper (greys at vendor, as Value has it).
local function UnitWorth(name, id)
    local ok, worth = pcall(ns.Value.WorthOf, ns.Value, name, id)
    return ok and tonumber(worth) or 0
end

--- Put a slot's loot in the feed: coin to the foot, a thing to its row.
function LootFeed:Add(entry)
    if entry.coin then
        self.coin = self.coin + entry.coin
        self.coinAt = Now()
        self:Layout()
        return
    end

    local key = entry.id and ("i" .. entry.id) or ("n" .. entry.name)
    local row
    for index, each in ipairs(self.rows) do
        if each.key == key then
            row = table.remove(self.rows, index)
            break
        end
    end
    if row then
        row.count = row.count + (entry.count or 1)
    else
        row = { key = key, name = entry.name, id = entry.id, icon = entry.icon,
            count = entry.count or 1, unit = UnitWorth(entry.name, entry.id) }
    end
    row.at = Now()
    table.insert(self.rows, 1, row)
    while #self.rows > LootFeed.MAX_ROWS do table.remove(self.rows) end
    self:Layout()
end

--- The loot's worth on screen, in copper.
function LootFeed:Worth()
    local total = 0
    for _, row in ipairs(self.rows) do total = total + (row.unit or 0) * row.count end
    return total
end

--- The foot's words: coin, then worth when Show Worth is on; nil for none.
function LootFeed:FootText()
    local left, right
    if self.coin > 0 then left = L.Format("Coin: %s", ns.Value.Coins(self.coin)) end
    local worth = self:ShowsWorth() and self:Worth() or 0
    if worth > 0 then right = L.Format("Loot worth: %s", ns.Value.Coins(worth)) end
    return left, right
end

--- Empty the feed.
function LootFeed:Clear()
    self.rows = {}
    self.coin = 0
    self.coinAt = nil
    self.pending = {}
    self:Layout()
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function MakeLine(frame, index)
    local Theme = ns.Theme
    local line = CreateFrame("Frame", nil, frame)
    line:SetHeight(ROW)

    local stripe = line:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints(line)
    stripe:SetColorTexture(Theme.Unpack(index % 2 == 1 and "glass" or "glassAlt"))
    line.stripe = stripe

    local rule = line:CreateTexture(nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    rule:SetColorTexture(Theme.Unpack("border", 0.6))

    local edge = line:CreateTexture(nil, "ARTWORK")
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("BOTTOMLEFT")
    edge:SetWidth(EDGE)
    edge:SetColorTexture(Theme.Unpack("accentHi"))
    edge:Hide()
    line.edge = edge

    local icon = line:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON, ICON)
    icon:SetPoint("LEFT", line, "LEFT", PAD, 0)
    line.icon = icon

    line.count = Theme.CreateLabel(line, "normal", "text", "RIGHT")
    line.count:SetPoint("RIGHT", line, "RIGHT", -PAD, 0)
    line.name = Theme.CreateLabel(line, "normal", "text", "LEFT")
    line.name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    line.name:SetPoint("RIGHT", line.count, "LEFT", -6, 0)
    line.name:SetWordWrap(true)

    ns.SeeThrough:AddGlass("lootfeed", stripe)
    ns.SeeThrough:AddGlass("lootfeed", rule)
    line:Hide()
    return line
end

function LootFeed:Build()
    if self.frame then return self.frame end

    local Theme, Widgets = ns.Theme, ns.Widgets
    local frame = CreateFrame("Frame", "BlackthornesFarmerLootFeed", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(MIN_WIDTH, ROW)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(false)

    self.lines = {}
    for index = 1, LootFeed.MAX_ROWS do
        self.lines[index] = MakeLine(frame, index)
    end

    -- The foot: a warm glass line under a gold rule.
    local foot = CreateFrame("Frame", nil, frame)
    foot:SetHeight(ROW)
    local back = foot:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(foot)
    back:SetColorTexture(Theme.Unpack("glassActive"))
    local top = foot:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(1)
    top:SetColorTexture(Theme.Unpack("accent", 0.7))
    foot.left = Theme.CreateLabel(foot, "normal", "accent", "LEFT")
    foot.left:SetPoint("LEFT", foot, "LEFT", PAD, 0)
    foot.right = Theme.CreateLabel(foot, "normal", "accent", "RIGHT")
    foot.right:SetPoint("RIGHT", foot, "RIGHT", -PAD, 0)
    foot:Hide()
    self.foot = foot
    ns.SeeThrough:AddGlass("lootfeed", back)

    -- A gold edge round it, only while it is being moved.
    local border = CreateFrame("Frame", nil, frame)
    border:SetAllPoints(frame)
    border:EnableMouse(false)
    Theme.Border(border, "accent")
    border:Hide()
    self.moveBorder = border

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) if LootFeed.moving then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        LootFeed:SavePlace()
    end)
    frame:SetScript("OnUpdate", function(_, elapsed) LootFeed:Tick(elapsed) end)

    Widgets.ApplySize(frame, ns.db and ns.db.lootFeedScale)
    self.sizeGrip = Widgets.CreateSizeGrip(frame, {
        get = function() return ns.db and ns.db.lootFeedScale end,
        save = function(percent) if ns.db then ns.db.lootFeedScale = percent end end,
        done = function() LootFeed:SavePlace() end,
    })
    self.sizeGrip:Hide()

    self.frame = frame
    self:Place()
    ns.SeeThrough:Attach("lootfeed", frame)
    frame:Hide()
    return frame
end

--- Put the feed where it was left, else in its first place.
function LootFeed:Place()
    local frame = self.frame
    if not frame then return end
    frame:ClearAllPoints()
    local x, y = tonumber(ns.db and ns.db.lootFeedX), tonumber(ns.db and ns.db.lootFeedY)
    if x and y then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    else
        frame:SetPoint("TOPLEFT", UIParent, "CENTER", FIRST_X, FIRST_Y)
    end
end

--- Keep where its top left corner is now.
function LootFeed:SavePlace()
    local frame = self.frame
    if not frame then return end
    local ok, left, top = pcall(function() return frame:GetLeft(), frame:GetTop() end)
    if ok and type(left) == "number" and type(top) == "number" then
        ns.db.lootFeedX, ns.db.lootFeedY = left, top
    end
    self:Place()
end

--- Back to its first place and size.
function LootFeed:ResetPlace()
    ns.db.lootFeedX, ns.db.lootFeedY, ns.db.lootFeedScale = nil, nil, nil
    if self.frame then
        ns.Widgets.ApplySize(self.frame, 100)
        self:Place()
    end
end

--- Move mode: it takes the mouse, can be dragged and sized, and shows a
--- row to hold on to. Off again, it takes no mouse.
function LootFeed:SetMoving(on)
    self:Build()
    self.moving = on and true or false
    self.frame:EnableMouse(self.moving)
    self.sizeGrip:SetShown(self.moving)
    self.moveBorder:SetShown(self.moving)
    if not self.moving then self:SavePlace() end
    self:Layout()
    if ns.SettingsUI then ns.SettingsUI:Refresh() end
end

--- What the rows show: the feed's, or the one row Move holds on to.
function LootFeed:Shown()
    if #self.rows == 0 and self.moving then
        return { { name = L["Loot Feed"], icon = SAMPLE_ICON, sample = true } }
    end
    return self.rows
end

--- Lay the rows out again: only when one is added, moves or goes.
function LootFeed:Layout()
    local frame = self.frame
    local rows = self:Shown()
    local left, right = self:FootText()
    if #rows == 0 and not left and not right then
        if frame then frame:Hide() end
        return
    end
    frame = self:Build()
    local Theme, Util = ns.Theme, ns.Util

    local width = MIN_WIDTH
    for index, line in ipairs(self.lines) do
        local row = rows[index]
        if row then
            line.icon:SetTexture(row.icon or 134400)
            Theme.RingItem(line.icon, not row.sample and row.name or nil, not row.sample and row.id or nil)
            local name = row.sample and row.name or Util.ColorItem(row.name, row.id)
            line.name:SetText(name)
            -- How many sits on the icon's corner, as in the bags
            -- (UI/ItemLook.lua); without it, after the name as before.
            if ns.ItemLook then
                ns.ItemLook.SetCount(line.icon, not row.sample and row.count or nil)
                line.count:SetText("")
            else
                line.count:SetText(row.sample and "" or ("x" .. row.count))
            end
            line.edge:SetShown(index == 1 and not row.sample)
            local wide = PAD * 2 + ICON + 12 + (tonumber(Theme.TextWidth("normal", row.name)) or 120)
                + (tonumber(Theme.TextWidth("normal", line.count:GetText() or "")) or 20)
            width = math.max(width, wide)
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(index - 1) * ROW)
            line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -(index - 1) * ROW)
            line:SetAlpha(1)
            line:Show()
        else
            line:Hide()
        end
    end

    local height = #rows * ROW
    local foot = self.foot
    if left or right then
        foot.left:SetText(left or "")
        foot.right:SetText(right or "")
        local wide = PAD * 3 + (tonumber(Theme.TextWidth("normal", left or "")) or 0)
            + (tonumber(Theme.TextWidth("normal", right or "")) or 0)
        width = math.max(width, wide)
        foot:ClearAllPoints()
        foot:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -height)
        foot:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -height)
        foot:SetAlpha(1)
        foot:Show()
        height = height + ROW
    else
        foot:Hide()
    end

    frame:SetSize(math.min(MAX_WIDTH, width), math.max(ROW, height))
    frame:SetAlpha(1)
    frame:Show()
end

--- How far along its hold and fade a thing shown at `at` is: 1 while it
--- holds, down to 0 as it fades, nil once it is gone.
function LootFeed:Alpha(at, now)
    local age = now - (at or now)
    local hold = self:Hold()
    local fades = not ns.Motion or ns.Motion.Level() ~= "off"
    if age < hold then return 1 end
    if not fades or age >= hold + LootFeed.FADE then return nil end
    return 1 - (age - hold) / LootFeed.FADE
end

function LootFeed:Tick()
    if self.moving then return end
    local now = Now()
    local gone = false
    local newest = 0

    -- The mouse on it keeps every row up and holds them again from now.
    local over = false
    pcall(function() over = self.frame:IsMouseOver() == true end)
    if over then
        for _, row in ipairs(self.rows) do row.at = now end
        if self.coinAt then self.coinAt = now end
    end

    for index = #self.rows, 1, -1 do
        local row = self.rows[index]
        local alpha = self:Alpha(row.at, now)
        if alpha then
            local line = self.lines[index]
            if line then line:SetAlpha(alpha) end
            newest = math.max(newest, alpha)
        else
            table.remove(self.rows, index)
            gone = true
        end
    end

    -- The foot holds while any row does, or as long as its newest coin.
    if self.coin > 0 then
        local alpha = self.coinAt and self:Alpha(self.coinAt, now)
        newest = math.max(newest, alpha or 0)
    end
    if newest <= 0 then
        self.coin, self.coinAt = 0, nil
        if #self.rows == 0 then
            self.frame:Hide()
            return
        end
    end
    if gone then
        self:Layout()
    elseif self.foot:IsShown() then
        self.foot:SetAlpha(newest)
    end
end

--------------------------------------------------------------------------------
-- Events and the command
--------------------------------------------------------------------------------

ns.OnLootWindow(LootFeed, function(self) self:ReadWindow() end)
LootFeed.slotEvent = ns.RegisterEvent(LootFeed, "LOOT_SLOT_CLEARED", function(self, _, slot)
    self:SlotTaken(slot)
end)
ns.RegisterEvent(LootFeed, "LOOT_CLOSED", function(self) self.pending = {} end)

local function Command(rest)
    local word = (rest or ""):lower():match("^(%a*)")
    if word == "" then word = LootFeed:Enabled() and "off" or "on" end

    if word == "on" or word == "off" then
        LootFeed:SetEnabled(word == "on")
        ns.Print(LootFeed:Enabled() and L["The loot feed shows what you loot."]
            or L["The loot feed is off."])
    elseif word == "move" then
        LootFeed:SetMoving(not LootFeed.moving)
        ns.Print(LootFeed.moving and L["Drag the loot feed where you like. Type /farm lootfeed move again when it's set."]
            or L["The loot feed stays there."])
    elseif word == "reset" then
        LootFeed:ResetPlace()
        ns.Print(L["The loot feed is back in its first place."])
    else
        ns.Print(L["Type /farm lootfeed on, off, move or reset."])
    end
end

ns.RegisterCommand("lootfeed", L["shows what you loot as it comes in: on, off, move or reset"], Command)
