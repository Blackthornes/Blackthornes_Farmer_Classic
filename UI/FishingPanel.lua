-- Fishing panel (the owner said build it, 2026-11-02, from a mockup whose
-- words he approved): a slim strip under Cast and Add Lure in the Fishing
-- window, and a panel it opens with This Session, This Spot and Fish Log.
--
-- Only what Farmer already keeps is read: the spots in `fishing.spots`
-- (Logic/Fishing.lua), their pace, and the prices Value gives. The session
-- is kept in memory only. Saved, account wide, never rename them:
-- `fishingPanel` (off unless ticked), `fishingPanelBest[spot key]` (the best
-- gold an hour seen at a spot, in copper) and `fishingPanelScale`.
--
-- Small rewards: New Catch for a fish never caught before, Best Hour Yet
-- when a spot pays better than ever, a Next Rate Unlock bar, coins that
-- count up and a gold edge on new fish. Sounds follow the rank-up sound
-- setting; motion follows Window effects.

local _, ns = ...
local L = ns.L

local FishingPanel = ns.NewModule("FishingPanel")
local Theme = ns.Theme
local Widgets = ns.Widgets

FishingPanel.WIDTH = 340
FishingPanel.HEIGHT = 400
FishingPanel.STRIP = 32
FishingPanel.ROW = 20
FishingPanel.ROWS = 12
-- A spot's gold an hour counts once this long has been fished there.
FishingPanel.BEST_AFTER = 600
-- Seconds the coins take to count up.
FishingPanel.COUNT_FOR = 0.6

local function MotionLevel()
    return ns.Motion and ns.Motion.Level and ns.Motion.Level() or "full"
end

local function Now()
    return type(GetTime) == "function" and GetTime() or 0
end

local function Coins(copper)
    if ns.Value and ns.Value.Coins then return ns.Value.Coins(copper or 0) end
    return tostring(copper or 0)
end

local function PriceOf(name)
    local Value = ns.Value
    if not (Value and name) then return 0 end
    local ok, price = pcall(function()
        local id = Value:ItemID(name)
        return id and Value:UnitPrice(id) or 0
    end)
    return ok and tonumber(price) or 0
end

local function Clock(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local h = math.floor(seconds / 3600)
    local m = math.floor(seconds % 3600 / 60)
    local s = seconds % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

-- Fish are food and trade goods; anything else (a crate, a lockbox, junk)
-- goes under Other Catches.
function FishingPanel.IsFish(id)
    if not (id and type(GetItemInfoInstant) == "function") then return true end
    local ok, _, _, _, _, _, classID = pcall(GetItemInfoInstant, id)
    if not ok or classID == nil then return true end
    return classID == 0 or classID == 7
end

-- ---------------------------------------------------------------------------
-- The session, kept in memory only
-- ---------------------------------------------------------------------------

function FishingPanel:StartOver()
    self.session = {
        started = Now(),
        banked = 0,
        paused = false,
        casts = 0,
        caught = 0,
        copper = 0,
        fish = {},
        new = {},
        spots = {},
    }
    self.cheered = {}
    self:Redraw()
end

function FishingPanel:Session()
    if not self.session then self:StartOver() end
    return self.session
end

function FishingPanel:Seconds()
    local s = self:Session()
    if s.paused then return s.banked end
    return s.banked + math.max(0, Now() - s.started)
end

function FishingPanel:TogglePause()
    local s = self:Session()
    if s.paused then
        s.started = Now()
        s.paused = false
    else
        s.banked = self:Seconds()
        s.paused = true
    end
    self:Redraw()
end

function FishingPanel:PerHour()
    local seconds = self:Seconds()
    if seconds < 60 then return nil end
    return math.floor(self:Session().copper / seconds * 3600 + 0.5)
end

function FishingPanel:Enabled()
    return ns.db and ns.db.fishingPanel == true or false
end

function FishingPanel:SetEnabled(on)
    if not ns.db then return end
    ns.db.fishingPanel = on and true or false
    if not on and self.frame then self.frame:Hide() end
    if ns.FishingBar and ns.FishingBar.FitButtons then ns.FishingBar:FitButtons() end
end

--- Asked by Fishing:Record before the catch is counted: the names in
--- `items` never caught at any spot before.
function FishingPanel:Fresh(items)
    if not self:Enabled() or type(items) ~= "table" or #items == 0 then return nil end
    local spots = ns.Fishing and ns.Fishing:Store() or {}
    local fresh
    for _, name in ipairs(items) do
        local seen = false
        for _, spot in pairs(spots) do
            if type(spot) == "table" and type(spot.items) == "table" and spot.items[name] then
                seen = true
                break
            end
        end
        if not seen then
            fresh = fresh or {}
            fresh[name] = true
        end
    end
    return fresh
end

function FishingPanel:Cheer(text, sound)
    if ns.Notice and ns.Notice.Show then
        ns.Notice:Show(text, { key = "fishingPanel", hold = 5 })
    else
        ns.Print(text)
    end
    local RankUp, Tracker = ns.RankUp, ns.Tracker
    if sound and RankUp and RankUp.SoundOn and RankUp.SoundOn() and Tracker and Tracker.PlayFile then
        Tracker.PlayFile(sound)
    end
end

--- Asked by Fishing:Record after a cast that landed something.
function FishingPanel:Caught(key, items, quantities, fresh)
    if not self:Enabled() then return end
    local s = self:Session()
    local sounds = ns.Tracker and ns.Tracker.SOUNDS or {}

    for name in pairs(fresh or {}) do
        s.new[name] = true
        self:Cheer(L["New Catch"] .. "\n" .. name .. "\n" .. L["First one you've ever caught."], sounds.unlock)
    end

    s.lastKey = key
    if s.paused then
        self:Redraw()
        return
    end

    local copper = 0
    for _, name in ipairs(items or {}) do
        local count = quantities and quantities[name] or 1
        s.caught = s.caught + count
        s.fish[name] = (s.fish[name] or 0) + count
        copper = copper + PriceOf(name) * count
    end
    s.casts = s.casts + 1
    s.copper = s.copper + copper

    self:NoteSpot(key, copper)
    self:Redraw()
end

--- Time at a spot counts only between casts close together, as
--- Fishing:NotePace does, so a walk away is never part of an hour.
function FishingPanel:NoteSpot(key, copper)
    if not key then return end
    local s = self:Session()
    local now = Now()
    local here = s.spots[key]
    if not here then
        here = { seconds = 0, copper = 0 }
        s.spots[key] = here
    end
    local gap = here.last and (now - here.last) or nil
    local limit = ns.Fishing and ns.Fishing.BREAK or 300
    if gap and gap > 0 and gap < limit then here.seconds = here.seconds + gap end
    here.last = now
    here.copper = here.copper + (copper or 0)

    if here.seconds < self.BEST_AFTER or not ns.db then return end
    local rate = math.floor(here.copper / here.seconds * 3600 + 0.5)
    ns.db.fishingPanelBest = ns.db.fishingPanelBest or {}
    local old = tonumber(ns.db.fishingPanelBest[key])
    if old and rate > old then
        if not self.cheered[key] then
            self.cheered[key] = true
            local sounds = ns.Tracker and ns.Tracker.SOUNDS or {}
            self:Cheer(L["Best Hour Yet"] .. "\n" .. L.Format("Your best here was %s.", Coins(old)), sounds.rankup)
        end
        ns.db.fishingPanelBest[key] = rate
    elseif not old then
        ns.db.fishingPanelBest[key] = rate
    end
end

function FishingPanel:BestAt(key)
    local best = ns.db and type(ns.db.fishingPanelBest) == "table" and ns.db.fishingPanelBest[key]
    return tonumber(best)
end

function FishingPanel:SpotKey()
    local s = self:Session()
    if s.lastKey then return s.lastKey end
    local list = ns.Fishing and ns.Fishing.SessionSpots and ns.Fishing:SessionSpots()
    return list and list[1] and list[1].key or nil
end

--- Every fish caught at any spot, most first.
function FishingPanel:LogRows()
    local totals = {}
    for _, spot in pairs(ns.Fishing and ns.Fishing:Store() or {}) do
        if type(spot) == "table" and type(spot.items) == "table" then
            for name, entry in pairs(spot.items) do
                local count = type(entry) == "table" and tonumber(entry.count) or 0
                local row = totals[name]
                if not row then
                    row = { name = name, count = 0, id = type(entry) == "table" and tonumber(entry.id) or nil }
                    totals[name] = row
                end
                row.count = row.count + count
                row.id = row.id or (type(entry) == "table" and tonumber(entry.id)) or nil
            end
        end
    end
    local rows = {}
    for _, row in pairs(totals) do rows[#rows + 1] = row end
    table.sort(rows, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    return rows
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

local function Glass(frame, index)
    local back = frame:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(frame)
    back:SetColorTexture(Theme.Unpack(index % 2 == 1 and "glass" or "glassAlt"))
    local line = frame:CreateTexture(nil, "BORDER")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(Theme.Unpack("border", 0.6))
    return back
end

--- A thin gold bar: `part` of `whole` filled.
local function Bar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(6)
    local back = bar:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(bar)
    back:SetColorTexture(Theme.Unpack("glassAlt"))
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT")
    fill:SetPoint("BOTTOMLEFT")
    fill:SetColorTexture(Theme.Unpack("gold"))
    bar.fill = fill
    function bar:SetPart(part, whole)
        local width = tonumber(self:GetWidth()) or 0
        local share = whole and whole > 0 and math.min(1, math.max(0, part / whole)) or 0
        self.fill:SetWidth(math.max(1, width * share))
    end
    return bar
end

--- Coins that count up to `copper` (Window effects Full), else land at once.
local function CountTo(label, copper, prefix)
    prefix = prefix or ""
    copper = math.floor(tonumber(copper) or 0)
    local from = label.countValue or copper
    label.countValue = copper
    if MotionLevel() ~= "full" or from == copper or not label.SetScript then
        label:SetText(prefix .. Coins(copper))
        return
    end
    local start = Now()
    label:SetScript("OnUpdate", function(self)
        local t = math.min(1, (Now() - start) / FishingPanel.COUNT_FOR)
        self:SetText(prefix .. Coins(math.floor(from + (copper - from) * t)))
        if t >= 1 then self:SetScript("OnUpdate", nil) end
    end)
end

-- The strip under Cast and Add Lure ------------------------------------------

function FishingPanel:StripHeight()
    if not self:Enabled() then return 0 end
    return self.STRIP + 6
end

function FishingPanel:BuildStrip(parent)
    if self.strip then return self.strip end
    local strip = CreateFrame("Button", nil, parent)
    strip:SetHeight(self.STRIP)
    local back = strip:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(strip)
    back:SetColorTexture(Theme.Unpack("glass"))
    local edge = strip:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("BOTTOMLEFT")
    edge:SetWidth(2)
    edge:SetColorTexture(Theme.Unpack("gold"))
    local hover = strip:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(strip)
    hover:SetColorTexture(Theme.Unpack("glassHover"))

    strip.top = Theme.CreateLabel(strip, "small", "text", "LEFT")
    strip.top:SetPoint("TOPLEFT", 8, -4)
    strip.top:SetPoint("TOPRIGHT", -8, -4)
    strip.label = Theme.CreateLabel(strip, "small", "muted", "LEFT")
    strip.label:SetPoint("BOTTOMLEFT", 8, 4)
    strip.value = Theme.CreateLabel(strip, "small", "gold", "RIGHT")
    strip.value:SetPoint("BOTTOMRIGHT", -8, 4)
    strip.bar = Bar(strip)
    strip.bar:SetPoint("BOTTOMLEFT", 8, 7)
    strip.bar:SetPoint("BOTTOMRIGHT", -48, 7)

    strip:SetScript("OnClick", function() FishingPanel:Toggle() end)
    self.strip = strip
    return strip
end

--- Placed by FishingBar:FitButtons: under `below` (Classic's bar hands
--- its lure line), or at `below` from the window's top when it is a number.
function FishingPanel:PlaceStrip(frame, below)
    if not self:Enabled() then
        if self.strip then self.strip:Hide() end
        return
    end
    local strip = self:BuildStrip(frame)
    local pad = ns.FishingBar and (ns.FishingBar.PAD or ns.FishingBar.PADDING) or 12
    strip:ClearAllPoints()
    if type(below) == "table" then
        strip:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -10)
        strip:SetPoint("RIGHT", frame, "RIGHT", -pad, 0)
    else
        strip:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, below or -114)
        strip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, below or -114)
    end
    strip:Show()
    self:DrawStrip()
end

function FishingPanel:DrawStrip()
    local strip = self.strip
    if not (strip and strip:IsShown()) then return end
    local s = self:Session()
    strip.top:SetText(L["Casts"] .. " " .. s.casts .. "   " .. L["Caught"] .. " " .. s.caught
        .. "   " .. L["Total"] .. " " .. Coins(s.copper))

    local key = self:SpotKey()
    local summary = key and ns.Fishing and ns.Fishing:Summary(key)
    if summary and not summary.rated then
        local need = ns.Fishing.MIN_CASTS or 20
        strip.label:SetText(L["Next Rate Unlock"])
        strip.label:Hide()
        strip.bar:Show()
        strip.bar:SetPart(summary.casts, need)
        strip.value:SetText(summary.casts .. "/" .. need)
    else
        strip.bar:Hide()
        strip.label:Show()
        strip.label:SetText(L["Gold an Hour"])
        local rate = self:PerHour()
        strip.value:SetText(rate and Coins(rate) or "--")
    end
end

-- The panel ------------------------------------------------------------------

local function Dress(frame, title, onClose)
    Theme.Fill(frame, "window")
    local trim
    if ns.Titanforged then
        trim = ns.Titanforged:Dress(frame, { title = title, close = onClose })
        local left, right, top, bottom = ns.Titanforged.Reach(trim)
        if frame.SetClampRectInsets then pcall(frame.SetClampRectInsets, frame, -left, right, top, -bottom) end
    else
        Theme.Border(frame, "borderLit")
    end
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    Widgets.ApplySize(frame, ns.db and ns.db.fishingPanelScale)
    frame.sizeGrip = Widgets.CreateSizeGrip(frame, {
        below = trim and select(4, ns.Titanforged.Reach(trim)) or 0,
        get = function() return ns.db and ns.db.fishingPanelScale end,
        save = function(percent) if ns.db then ns.db.fishingPanelScale = percent end end,
    })
end

function FishingPanel:Build()
    if self.frame then return self.frame end
    local name = "BlackthornesFarmerFishingPanel"
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(self.WIDTH, self.HEIGHT)
    frame:SetPoint("CENTER", 220, 40)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, name) end
    self.frame = frame

    Dress(frame, L["Fishing"], function() frame:Hide() end)
    if ns.FoldWindow and ns.FoldWindow.Add then ns.FoldWindow:Add(frame, {}) end

    local PAD = 14
    local view = Widgets.CreateViewTabs(frame, {
        { key = "session", text = L["This Session"] },
        { key = "spot", text = L["This Spot"] },
        { key = "log", text = L["Fish Log"] },
    }, function(key)
        FishingPanel.view = key
        FishingPanel:Draw()
    end, { selected = self.view or "session" })
    view:SetPoint("TOPLEFT", PAD, -38)
    self.viewTabs = view
    self.view = self.view or "session"

    -- Top line: the clock on This Session, the spot's name on This Spot.
    frame.head = Theme.CreateLabel(frame, "normal", "gold", "LEFT")
    frame.head:SetPoint("TOPLEFT", PAD, -72)
    frame.head:SetPoint("TOPRIGHT", -PAD, -72)

    -- Three tiles: Casts, Caught, Total.
    frame.tiles = {}
    local tileWidth = math.floor((self.WIDTH - PAD * 2 - 12) / 3)
    for i, word in ipairs({ L["Casts"], L["Caught"], L["Total"] }) do
        local tile = CreateFrame("Frame", nil, frame)
        tile:SetSize(tileWidth, 40)
        tile:SetPoint("TOPLEFT", PAD + (i - 1) * (tileWidth + 6), -94)
        Glass(tile, i)
        tile.word = Theme.CreateLabel(tile, "small", "muted", "CENTER")
        tile.word:SetPoint("TOP", 0, -5)
        tile.word:SetText(word)
        tile.value = Theme.CreateLabel(tile, "normal", "text", "CENTER")
        tile.value:SetPoint("BOTTOM", 0, 6)
        frame.tiles[i] = tile
    end

    frame.rateLabel = Theme.CreateLabel(frame, "small", "muted", "LEFT")
    frame.rateLabel:SetPoint("TOPLEFT", PAD, -142)
    frame.rateValue = Theme.CreateLabel(frame, "small", "gold", "RIGHT")
    frame.rateValue:SetPoint("TOPRIGHT", -PAD, -142)
    frame.bar = Bar(frame)
    frame.bar:SetPoint("TOPLEFT", PAD, -160)
    frame.bar:SetPoint("TOPRIGHT", -PAD, -160)

    frame.listHead = Theme.CreateLabel(frame, "small", "gold", "LEFT")
    frame.listHead:SetPoint("TOPLEFT", PAD, -174)

    -- The list: dark glass rows.
    frame.rows = {}
    for i = 1, self.ROWS do
        local row = CreateFrame("Frame", nil, frame)
        row:SetHeight(self.ROW)
        row:SetPoint("TOPLEFT", PAD, -190 - (i - 1) * self.ROW)
        row:SetPoint("TOPRIGHT", -PAD, -190 - (i - 1) * self.ROW)
        row.back = Glass(row, i)
        row.edge = row:CreateTexture(nil, "ARTWORK")
        row.edge:SetPoint("TOPLEFT")
        row.edge:SetPoint("BOTTOMLEFT")
        row.edge:SetWidth(2)
        row.edge:SetColorTexture(Theme.Unpack("gold"))
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 6, 0)
        row.name = Theme.CreateLabel(row, "small", "text", "LEFT")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.tag = Theme.CreateLabel(row, "small", "gold", "LEFT")
        row.tag:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
        row.value = Theme.CreateLabel(row, "small", "text", "RIGHT")
        row.value:SetPoint("RIGHT", -6, 0)
        if row.CreateAnimationGroup then
            local pulse = row:CreateAnimationGroup()
            pulse:SetLooping("BOUNCE")
            local fade = pulse:CreateAnimation("Alpha")
            if fade and fade.SetFromAlpha then
                fade:SetFromAlpha(1)
                fade:SetToAlpha(0.35)
                fade:SetDuration(0.9)
                fade:SetTarget(row.edge)
            end
            row.pulse = pulse
        end
        row:Hide()
        frame.rows[i] = row
    end
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        FishingPanel.offset = math.max(0, (FishingPanel.offset or 0) - delta)
        FishingPanel:Draw()
    end)

    frame.pause = Widgets.CreateButton(frame, L["Pause"], function() FishingPanel:TogglePause() end, { width = 100 })
    frame.pause:SetPoint("BOTTOMLEFT", PAD, 14)
    frame.startOver = Widgets.CreateButton(frame, L["Start Over"], function() FishingPanel:StartOver() end, { width = 110 })
    frame.startOver:SetPoint("BOTTOMRIGHT", -PAD, 14)

    frame:SetScript("OnShow", function()
        FishingPanel:Draw()
        if not FishingPanel.ticker and C_Timer and C_Timer.NewTicker then
            FishingPanel.ticker = C_Timer.NewTicker(1, function() FishingPanel:Tick() end)
        end
    end)
    frame:SetScript("OnHide", function()
        if FishingPanel.ticker then
            FishingPanel.ticker:Cancel()
            FishingPanel.ticker = nil
        end
    end)
    return frame
end

function FishingPanel:Toggle()
    local frame = self:Build()
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

function FishingPanel:Show()
    self:Build():Show()
end

function FishingPanel:Tick()
    local frame = self.frame
    if not (frame and frame:IsShown()) then return end
    if self.view == "session" then
        local s = self:Session()
        frame.head:SetText(Clock(self:Seconds()))
        frame.head:SetAlpha(s.paused and 0.5 or 1)
    end
end

function FishingPanel:Redraw()
    self:DrawStrip()
    if self.frame and self.frame:IsShown() then self:Draw() end
end

local function FillRow(row, line)
    row.name:SetText(line.name or "")
    row.value:SetText(line.value or "")
    row.tag:SetText(line.new and L["New"] or "")
    local icon = line.id and type(GetItemIcon) == "function" and GetItemIcon(line.id)
    row.icon:SetTexture(icon or 134400)
    row.edge:SetShown(line.new and true or false)
    if row.pulse then
        if line.new and MotionLevel() == "full" then
            if not row.pulse:IsPlaying() then row.pulse:Play() end
        else
            row.pulse:Stop()
        end
    end
    row:Show()
end

function FishingPanel:SessionLines()
    local s = self:Session()
    local lines = {}
    for name, count in pairs(s.fish) do
        lines[#lines + 1] = {
            name = name,
            count = count,
            id = ns.Value and ns.Value:ItemID(name) or nil,
            value = tostring(count),
            new = s.new[name],
        }
    end
    table.sort(lines, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    return lines
end

--- This Spot's lines: Fish, then Other Catches, each a heading row.
function FishingPanel:SpotLines(summary)
    local fish, other = {}, {}
    for _, item in ipairs(summary and summary.items or {}) do
        local line = {
            name = item.name,
            id = item.id,
            new = self:Session().new[item.name],
            value = summary.rated and string.format("%.0f%%", item.chance) or tostring(item.count),
        }
        if FishingPanel.IsFish(item.id) then fish[#fish + 1] = line else other[#other + 1] = line end
    end
    local lines = {}
    if #fish > 0 then
        lines[#lines + 1] = { heading = L["Fish"] }
        for _, line in ipairs(fish) do lines[#lines + 1] = line end
    end
    if #other > 0 then
        lines[#lines + 1] = { heading = L["Other Catches"] }
        for _, line in ipairs(other) do lines[#lines + 1] = line end
    end
    return lines
end

function FishingPanel:Draw()
    local frame = self.frame
    if not (frame and frame:IsShown()) then return end
    local s = self:Session()
    local view = self.view or "session"
    local lines

    for _, tile in ipairs(frame.tiles) do tile:SetShown(view ~= "log") end
    frame.bar:Hide()
    frame.pause:SetShown(view == "session")
    frame.startOver:SetShown(view == "session")
    frame.pause:SetText(s.paused and L["Start"] or L["Pause"])

    if view == "session" then
        frame.head:SetText(Clock(self:Seconds()))
        frame.head:SetAlpha(s.paused and 0.5 or 1)
        frame.tiles[1].value:SetText(tostring(s.casts))
        frame.tiles[2].value:SetText(tostring(s.caught))
        CountTo(frame.tiles[3].value, s.copper)
        frame.rateLabel:SetText(L["Gold an Hour"])
        local rate = self:PerHour()
        frame.rateValue:SetText(rate and Coins(rate) or "--")
        frame.listHead:SetText(L["Your Catch"])
        lines = self:SessionLines()
    elseif view == "spot" then
        frame.head:SetAlpha(1)
        local key = self:SpotKey()
        local summary = key and ns.Fishing and ns.Fishing:Summary(key)
        frame.head:SetText(summary and (summary.name or summary.place) or "")
        frame.tiles[1].value:SetText(tostring(summary and summary.casts or 0))
        local caught = 0
        for _, item in ipairs(summary and summary.items or {}) do caught = caught + (item.count or 0) end
        frame.tiles[2].value:SetText(tostring(caught))
        local here = key and s.spots[key]
        CountTo(frame.tiles[3].value, here and here.copper or 0)
        if summary and not summary.rated then
            local need = ns.Fishing.MIN_CASTS or 20
            frame.rateLabel:SetText(L["Next Rate Unlock"])
            frame.rateValue:SetText(summary.casts .. "/" .. need)
            frame.bar:Show()
            frame.bar:SetPart(summary.casts, need)
        else
            frame.rateLabel:SetText(L["Best hour here:"])
            local best = key and self:BestAt(key)
            frame.rateValue:SetText(best and Coins(best) or "--")
        end
        frame.listHead:SetText("")
        lines = self:SpotLines(summary)
    else
        frame.head:SetAlpha(1)
        frame.head:SetText(L["Fish Log"])
        frame.rateLabel:SetText("")
        frame.rateValue:SetText("")
        frame.listHead:SetText("")
        lines = {}
        for _, row in ipairs(self:LogRows()) do
            lines[#lines + 1] = { name = row.name, id = row.id, value = tostring(row.count), new = s.new[row.name] }
        end
    end

    local most = math.max(0, #lines - self.ROWS)
    self.offset = math.min(self.offset or 0, most)
    for i, row in ipairs(frame.rows) do
        local line = lines[i + self.offset]
        if not line then
            row:Hide()
        elseif line.heading then
            FillRow(row, { name = line.heading })
            row.name:SetTextColor(Theme.Unpack("gold"))
            row.icon:SetTexture(nil)
        else
            FillRow(row, line)
            row.name:SetTextColor(Theme.Unpack("text"))
        end
    end
end

-- ---------------------------------------------------------------------------
-- Setting and command
-- ---------------------------------------------------------------------------

ns.RegisterCommand("fishpanel", L["Show what you catch while you fish."], function(rest)
    local word = ns.Util.Trim(rest or ""):lower()
    local on
    if word == "on" then on = true elseif word == "off" then on = false else on = not FishingPanel:Enabled() end
    FishingPanel:SetEnabled(on)
    ns.Print(L["Fishing Panel:"] .. " " .. (on and L["On"] or L["Off"]))
end)
