-- Blackthornes Farmer -- UI/Stats.lua
-- The Stats tab of the main window: your farming in charts (Logic/Stats.lua).
--
-- The owner asked (2026-10-13, "gold goblin farmers are data nerds") for a
-- tab that is only charts, in the house look, and picked the mockup with a
-- row of numbers across the top and six cards under it:
--
--   1. Gold an hour over your last sessions, against your usual pace
--   2. Where your gold came from this week
--   3. Your best mobs for gold, at your own kill speed (a click opens the
--      mob's loot table)
--   4. Luck since you logged in: what dropped against the drop rates
--   5. The days you farmed, ten weeks of them
--   6. How long each level took, from the XP bar's record
--
-- A switch beside Settings picks This session or Overall (the owner asked
-- 2026-10-13; `statsView`, Stats:View). This session: the numbers, how
-- this login's gold grew, its sources, the mobs killed in it and its luck.
-- Overall: every session, every day kept and the whole kill tally. Days
-- and levels are the same in both and say so while This session shows.
--
-- Drawn only while the tab is on screen: opening it draws it with the
-- charts growing in (Window effects Off lands them at once), and anything
-- that moves while it shows draws it again once, REDRAW seconds later.
-- Every texture is made once and reused.

local _, ns = ...
local L = ns.L

local StatsUI = ns.NewModule("StatsUI")

local Theme = ns.Theme
local Util = ns.Util

local PADDING = 14
local GAP = 10
-- The narrowest the charts are laid out at; the window is as wide as
-- every tab shares (UI:WindowWidth), at least this.
StatsUI.WIDTH = 920
StatsUI.HEIGHT = 620
StatsUI.REDRAW = 3

local KPI_HEIGHT = 54
local CARD_HEAD = 38
local FOOT = 30

local GLOW = [[Interface\AddOns\Blackthornes_Farmer\Media\Frame\Glow.tga]]

-- The sources' colours: gold for drops, silver for coin, green for
-- gathering, blue for fishing, grey for greys.
StatsUI.SOURCE_COLORS = {
    drops = { 0.945, 0.780, 0.290 },
    coin = { 0.780, 0.780, 0.812 },
    gather = { 0.310, 0.820, 0.420 },
    fish = { 0.240, 0.610, 1.000 },
    grey = { 0.500, 0.500, 0.500 },
}

StatsUI.SOURCE_LABELS = {
    drops = L["Loot from kills"],
    coin = L["Coin off corpses"],
    gather = L["Herbs, ore and gathering"],
    fish = L["Fishing"],
    grey = L["Greys for the vendor"],
}

--------------------------------------------------------------------------------
-- Small pieces
--------------------------------------------------------------------------------

local function Tip(owner, title, lines)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:AddLine(title, 1, 1, 1)
    for _, line in ipairs(lines or {}) do
        GameTooltip:AddLine(line, Theme.Unpack("muted"))
    end
    GameTooltip:Show()
end

local function HideTip()
    if GameTooltip then GameTooltip:Hide() end
end

local function Texture(parent, layer, sub)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
    texture:SetColorTexture(1, 1, 1, 1)
    return texture
end

--- A soft round light (the frame's Glow art), tinted.
local function Light(parent, size, r, g, b, a)
    local light = parent:CreateTexture(nil, "OVERLAY")
    light:SetTexture(GLOW)
    pcall(light.SetBlendMode, light, "ADD")
    light:SetSize(size, size)
    light:SetVertexColor(r, g, b, a or 1)
    return light
end

--- A label that wraps rather than ending in "...".
local function Wrapped(parent, size, color, width)
    local label = Theme.CreateLabel(parent, size, color)
    label:SetWordWrap(true)
    label:SetJustifyV("TOP")
    if width then label:SetWidth(width) end
    return label
end

--- Coins rounded for an axis: whole gold past a gold, tens of silver below.
function StatsUI.AxisCoins(copper)
    copper = tonumber(copper) or 0
    if copper >= 10000 then
        return ns.Value.Coins(math.floor(copper / 5000 + 0.5) * 5000)
    end
    return ns.Value.Coins(math.floor(copper / 100 + 0.5) * 100)
end

--- A number to a tenth when small, whole when not: "1.8", "41".
function StatsUI.Count(value)
    value = tonumber(value) or 0
    if value < 10 and math.floor(value) ~= value then return ("%.1f"):format(value) end
    return ns.XP.Comma(value)
end

--- A card: dark glass with the house header (gold stripe, glow and sheen),
--- its title and a line under it saying what it shows.
function StatsUI:Card(parent, x, y, width, height, title, subtitle)
    local card = Theme.CreatePanel(parent, "glassAlt", "border")
    card:SetPoint("TOPLEFT", x, -y)
    card:SetSize(width, height)
    card.width, card.height = width, height

    local head = CreateFrame("Frame", nil, card)
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", -1, -1)
    head:SetHeight(CARD_HEAD)
    Theme.Fill(head, "glassActive", 0.55)
    Theme.HouseHeader(head, 22)

    card.title = Theme.CreateLabel(head, "normal", "accentHi")
    card.title:SetPoint("TOPLEFT", 10, -5)
    card.title:SetText(title)

    card.subtitle = Theme.CreateLabel(head, "tiny", "muted")
    card.subtitle:SetPoint("TOPLEFT", 10, -22)
    card.subtitle:SetText(subtitle)

    local body = CreateFrame("Frame", nil, card)
    body:SetPoint("TOPLEFT", 1, -(CARD_HEAD + 1))
    body:SetPoint("BOTTOMRIGHT", -1, 1)
    card.body = body
    card.bodyWidth = width - 2
    card.bodyHeight = height - CARD_HEAD - 2

    card.empty = Wrapped(body, "small", "muted", width - 32)
    card.empty:SetPoint("TOPLEFT", 14, -14)
    card.empty:Hide()

    -- Lit for a moment when something on it is new (a best session).
    Theme.Halo(card, 8, 0, "accent")
    return card
end

--- Show the card's empty words, or hide them.
local function Empty(card, text)
    card.empty:SetText(text or "")
    card.empty:SetShown(text ~= nil)
end

--- A dark glass row: its band, the fine line under it, and the gold edge
--- and lift under the mouse.
local function GlassRow(parent, height)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(height)
    row.band = Theme.Fill(row, "glass")
    local line = row:CreateTexture(nil, "BORDER")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(Theme.Unpack("border", 0.6))
    row.edge = row:CreateTexture(nil, "OVERLAY")
    row.edge:SetPoint("TOPLEFT")
    row.edge:SetPoint("BOTTOMLEFT")
    row.edge:SetWidth(2)
    row.edge:SetColorTexture(Theme.Unpack("accentHi"))
    row.edge:Hide()
    row:SetScript("OnEnter", function(self)
        self.band:SetColorTexture(Theme.Unpack(self.active and "glassActive" or "glassHover"))
        self.edge:Show()
        if self.onEnter then self.onEnter(self) end
    end)
    row:SetScript("OnLeave", function(self)
        self.band:SetColorTexture(Theme.Unpack(self.glass or "glass"))
        self.edge:SetShown(self.active and true or false)
        HideTip()
    end)
    return row
end

--- A row's shade by its place, and whether it is the picked one.
local function Stripe(row, index, active)
    row.glass = active and "glassActive" or (index % 2 == 0 and "glassAlt" or "glass")
    row.active = active
    row.band:SetColorTexture(Theme.Unpack(row.glass))
    row.edge:SetShown(active and true or false)
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function StatsUI:Build(frame)
    if self.view then return self.view end

    local view = CreateFrame("Frame", nil, frame)
    view:SetAllPoints(frame)
    self.view = view

    local left, top = ns.UI.HEAD_LEFT or PADDING, ns.UI.HEAD_TOP or 26

    -- This Session or Overall (the owner, 2026-10-13) as the house's small
    -- view tabs on top of the charts (2026-10-29), where a line of words sat.
    local switch = ns.Widgets.CreateViewTabs(view, {
        { key = "session", text = L["This Session"] },
        { key = "overall", text = L["Overall"] },
    }, function(key)
        ns.Stats:SetView(key)
        StatsUI:ViewChanged()
    end)
    switch:SetPoint("TOPLEFT", left, -(top + 2))
    self.switch = switch

    -- The last kill goal's summary (UI/KillGoal.lua), left of the switch,
    -- once one is finished.
    local killGoal = ns.Widgets.CreateButton(view, L["Kill Goal"], function()
        if ns.KillGoalUI then ns.KillGoalUI:ShowSummary() end
    end, { height = 20 })
    killGoal:Hide()
    self.killGoalButton = killGoal
    self:PlaceSwitch()

    -- The window is as wide as the widest tab has needed, and every tab
    -- shares it: the charts are laid out at that width when they are made,
    -- on a canvas kept in the middle, so a window that grows later only
    -- adds a little room either side.
    local layoutWidth = math.max(StatsUI.WIDTH,
        ns.UI and ns.UI.WindowWidth and ns.UI:WindowWidth() or 0)
    local canvas = CreateFrame("Frame", nil, view)
    canvas:SetPoint("TOP", view, "TOP")
    canvas:SetPoint("BOTTOM", view, "BOTTOM")
    canvas:SetWidth(layoutWidth)
    self.canvas = canvas

    local width = layoutWidth - 2 * PADDING
    local kpiTop = top + 24 + 10

    -- The numbers across the top.
    self.tiles = {}
    local tileWidth = math.floor((width - 3 * GAP) / 4)
    for index = 1, 4 do
        local tile = Theme.CreatePanel(canvas, "glass", "border")
        tile:SetPoint("TOPLEFT", PADDING + (index - 1) * (tileWidth + GAP), -kpiTop)
        tile:SetSize(tileWidth, KPI_HEIGHT)
        tile.width = tileWidth
        tile.stripe = Theme.AccentStripe(tile, 3)
        Theme.TopSheen(tile)
        tile.label = Theme.CreateLabel(tile, "tiny", "muted")
        tile.label:SetPoint("TOPLEFT", 12, -6)
        tile.value = Theme.CreateLabel(tile, "large", "text")
        tile.value:SetPoint("TOPLEFT", 12, -19)
        tile.note = Theme.CreateLabel(tile, "tiny", "muted")
        tile.note:SetPoint("TOPLEFT", 12, -38)
        self.tiles[index] = tile
    end

    -- The cards, three across and two down.
    local cardsTop = kpiTop + KPI_HEIGHT + GAP
    local rowHeight = math.floor((StatsUI.HEIGHT - cardsTop - FOOT - GAP) / 2)
    local wide = math.floor((width - 2 * GAP) * 0.38)
    local narrow = math.floor((width - 2 * GAP - wide) / 2)
    local xs = { PADDING, PADDING + wide + GAP, PADDING + wide + narrow + 2 * GAP }
    local ws = { wide, narrow, narrow }
    local y2 = cardsTop + rowHeight + GAP

    self.sessionsCard = self:Card(canvas, xs[1], cardsTop, ws[1], rowHeight,
        L["Gold an hour"], L["One point for each session"])
    self.sourcesCard = self:Card(canvas, xs[2], cardsTop, ws[2], rowHeight,
        L["Where your gold came from"], L["This session"])
    self.mobsCard = self:Card(canvas, xs[3], cardsTop, ws[3], rowHeight,
        L["Best mobs for gold"], L["Gold an hour, at how fast you kill them"])
    self.luckCard = self:Card(canvas, xs[1], y2, ws[1], rowHeight,
        L["Your luck"], L["Your drops vs. the usual drop rates"])
    self.daysCard = self:Card(canvas, xs[2], y2, ws[2], rowHeight,
        L["Days you farmed"], L["Last 10 weeks, brighter is more gold"])
    self.levelsCard = self:Card(canvas, xs[3], y2, ws[3], rowHeight,
        L["How long each level took"], L["This character, in played time"])

    -- Days and levels are not kept by session, so these two show the same
    -- in both views and say so while This session is picked.
    self:SameInBoth(self.daysCard, L["Every day"],
        L["The same in both views."])
    self:SameInBoth(self.levelsCard, L["Every level"],
        L["The same in both views."])

    self:BuildSessions(self.sessionsCard)
    self:BuildSources(self.sourcesCard)
    self:BuildMobs(self.mobsCard)
    self:BuildLuck(self.luckCard)
    self:BuildDays(self.daysCard)
    self:BuildLevels(self.levelsCard)

    local footer = Theme.CreateLabel(view, "tiny", "dim")
    footer:SetPoint("BOTTOMLEFT", PADDING, 8)
    footer:SetPoint("BOTTOMRIGHT", -(PADDING + (ns.UI.VERSION_ROOM or 0)), 8)
    footer:SetWordWrap(true)
    footer:SetText(L["Five minutes with no loot counts as a break."])
    self.footer = footer

    view:Hide()
    return view
end

--- The view tabs sit top left over the charts; the last kill goal's
--- button on the same line, at the right.
function StatsUI:PlaceSwitch()
    local killGoal = self.killGoalButton
    if not killGoal then return end
    killGoal:ClearAllPoints()
    killGoal:SetPoint("TOPRIGHT", self.view, "TOPRIGHT", -PADDING, -(ns.UI.HEAD_TOP or 26))
    self.switchPlaced = true
end

--- A dim tag on a card's header, shown in the This session view, whose
--- tooltip says why the card does not change with it.
function StatsUI:SameInBoth(card, text, why)
    local tag = CreateFrame("Frame", nil, card)
    tag:SetPoint("TOPRIGHT", -10, -6)
    tag:SetSize(Theme.TextWidth("tiny", text) + 4, 14)
    local label = Theme.CreateLabel(tag, "tiny", "dim", "RIGHT")
    label:SetPoint("RIGHT")
    label:SetText(text)
    tag:EnableMouse(true)
    tag:SetScript("OnEnter", function(self) Tip(self, text, { why }) end)
    tag:SetScript("OnLeave", HideTip)
    tag:Hide()
    card.sameTag = tag
end

--------------------------------------------------------------------------------
-- 1. Gold an hour, your last sessions
--------------------------------------------------------------------------------

local SEGMENT_SLICES = 6
local MAX_POINTS = 20

function StatsUI:BuildSessions(card)
    local body = card.body
    local plot = CreateFrame("Frame", nil, body)
    plot:SetPoint("TOPLEFT", 48, -22)
    plot:SetPoint("BOTTOMRIGHT", -14, 22)
    card.plot = plot
    card.plotWidth = card.bodyWidth - 62
    card.plotHeight = card.bodyHeight - 44

    card.grid, card.axis = {}, {}
    for index = 1, 3 do
        local line = Texture(plot, "BACKGROUND", 2)
        line:SetColorTexture(Theme.Unpack("border", 0.7))
        line:SetHeight(1)
        card.grid[index] = line
        local label = Theme.CreateLabel(body, "tiny", "dim", "RIGHT")
        card.axis[index] = label
    end
    local floor = Texture(plot, "BACKGROUND", 2)
    floor:SetColorTexture(Theme.Unpack("border", 0.9))
    floor:SetHeight(1)
    floor:SetPoint("BOTTOMLEFT")
    floor:SetPoint("BOTTOMRIGHT")

    card.firstDay = Theme.CreateLabel(body, "tiny", "dim")
    card.firstDay:SetPoint("TOPLEFT", plot, "BOTTOMLEFT", 0, -4)
    card.lastDay = Theme.CreateLabel(body, "tiny", "dim", "RIGHT")
    card.lastDay:SetPoint("TOPRIGHT", plot, "BOTTOMRIGHT", 0, -4)

    card.slices, card.lines, card.glows, card.dashes = {}, {}, {}, {}
    for index = 1, (MAX_POINTS - 1) * SEGMENT_SLICES do
        local slice = Texture(plot, "BORDER")
        slice:Hide()
        card.slices[index] = slice
    end
    for index = 1, MAX_POINTS - 1 do
        local glow = plot.CreateLine and plot:CreateLine(nil, "ARTWORK", nil, 1)
        local line = plot.CreateLine and plot:CreateLine(nil, "ARTWORK", nil, 2)
        if glow and line then
            glow:SetColorTexture(Theme.Unpack("accent", 0.28))
            pcall(glow.SetThickness, glow, 6)
            line:SetColorTexture(Theme.Unpack("accentHi"))
            pcall(line.SetThickness, line, 2)
            glow:Hide()
            line:Hide()
            card.lines[index], card.glows[index] = line, glow
        end
    end
    -- Without lines (an older client), a dot at every session.
    card.dots = {}
    for index = 1, MAX_POINTS do
        local dot = Texture(plot, "ARTWORK", 3)
        dot:SetSize(4, 4)
        dot:SetColorTexture(Theme.Unpack("accentHi"))
        dot:Hide()
        card.dots[index] = dot
    end
    for index = 1, 60 do
        local dash = Texture(plot, "ARTWORK", 0)
        dash:SetSize(5, 1)
        dash:SetColorTexture(Theme.Unpack("muted", 0.8))
        dash:Hide()
        card.dashes[index] = dash
    end
    card.usualLabel = Theme.CreateLabel(plot, "tiny", "muted")

    card.bestLight = Light(plot, 24, 1, 0.82, 0.29, 0.9)
    card.bestDot = Texture(plot, "OVERLAY", 2)
    card.bestDot:SetSize(6, 6)
    card.bestDot:SetColorTexture(1, 0.86, 0.4, 1)
    card.bestLabel = Theme.CreateLabel(plot, "tiny", "accentHi")
    card.nowDot = Texture(plot, "OVERLAY", 3)
    card.nowDot:SetSize(6, 6)
    card.nowDot:SetColorTexture(1, 1, 1, 1)
end

--- Where a session sits in the plot.
local function Point(card, index, count, rate, top)
    local x = count > 1 and (index - 1) / (count - 1) * card.plotWidth or card.plotWidth / 2
    local y = top > 0 and rate / top * card.plotHeight or 0
    return x, y
end

function StatsUI:DrawSessions(card, arrive, view)
    local series, curve
    if view == "session" then
        -- How this session's gold grew, against your usual pace as a
        -- sloped line.
        curve = ns.Stats:Curve(MAX_POINTS)
        series = {}
        for index, point in ipairs(curve or {}) do
            series[index] = { rate = point.copper, seconds = point.seconds }
        end
    else
        series = ns.Stats:Series(MAX_POINTS)
    end
    local count = #series
    local usual = ns.Stats:Usual()

    local function HideAll()
        for _, t in ipairs(card.slices) do t:Hide() end
        for _, t in ipairs(card.lines) do t:Hide() end
        for _, t in ipairs(card.glows) do t:Hide() end
        for _, t in ipairs(card.dots) do t:Hide() end
        for _, t in ipairs(card.dashes) do t:Hide() end
        card.bestLight:Hide()
        card.bestDot:Hide()
        card.bestLabel:Hide()
        card.nowDot:Hide()
        card.usualLabel:Hide()
    end

    local shown = count >= 2
    card.plot:SetShown(shown)
    for _, label in ipairs(card.axis) do label:SetShown(shown) end
    card.firstDay:SetShown(shown)
    card.lastDay:SetShown(shown)
    if not shown then
        HideAll()
        Empty(card, curve == nil and view == "session"
            and L["Loot something and this chart starts."]
            or L["Farm for five minutes to start a session. The line shows once you have two."])
        return
    end
    Empty(card, nil)

    -- Your usual pace: across for sessions, rising with the time farmed for
    -- this session's gold.
    local lastSeconds = series[count].seconds or 0
    local function UsualAt(fraction)
        if not usual then return nil end
        if curve then return usual / 3600 * lastSeconds * fraction end
        return usual
    end

    local top, best, bestIndex = math.max(UsualAt(0) or 0, UsualAt(1) or 0), nil, nil
    for index, entry in ipairs(series) do
        if entry.rate > top then top = entry.rate end
        if not best or entry.rate > best then best, bestIndex = entry.rate, index end
    end
    if curve then best, bestIndex = series[count].rate, count end
    top = top * 1.18
    if top <= 0 then top = 1 end

    for index, line in ipairs(card.grid) do
        local y = index / 3 * card.plotHeight
        line:ClearAllPoints()
        line:SetPoint("BOTTOMLEFT", card.plot, "BOTTOMLEFT", 0, y)
        line:SetPoint("BOTTOMRIGHT", card.plot, "BOTTOMRIGHT", 0, y)
        local label = card.axis[index]
        label:ClearAllPoints()
        label:SetPoint("RIGHT", card.plot, "BOTTOMLEFT", -6, y)
        label:SetText(StatsUI.AxisCoins(top * index / 3))
    end
    if curve then
        card.firstDay:SetText(L["Start"])
        card.lastDay:SetText(L.Format("%s farming", ns.XP.Duration(lastSeconds)))
    else
        card.firstDay:SetText(series[1].day or "")
        card.lastDay:SetText(series[count].current and L["Now"] or (series[count].day or ""))
    end

    local points = {}
    for index, entry in ipairs(series) do
        local x, y = Point(card, index, count, entry.rate, top)
        points[index] = { x = x, y = y }
    end

    -- Your usual pace as a dashed line.
    local usualY = usual and UsualAt(0) / top * card.plotHeight
    for index, dash in ipairs(card.dashes) do
        local x = (index - 1) * 9
        if usual and x < card.plotWidth then
            local y = UsualAt(x / card.plotWidth) / top * card.plotHeight
            dash:ClearAllPoints()
            dash:SetPoint("BOTTOMLEFT", card.plot, "BOTTOMLEFT", x, y)
            dash:Show()
        else
            dash:Hide()
        end
    end
    if usualY then
        card.usualLabel:ClearAllPoints()
        if curve then
            -- Beside the line's far end, inside the plot.
            local endY = UsualAt(1) / top * card.plotHeight
            card.usualLabel:SetPoint("BOTTOMRIGHT", card.plot, "BOTTOMLEFT", card.plotWidth - 2,
                math.min(endY + 3, card.plotHeight - 8))
        else
            card.usualLabel:SetPoint("BOTTOMLEFT", card.plot, "BOTTOMLEFT", 2, usualY + 3)
        end
        card.usualLabel:SetText(L["Your usual"])
        card.usualLabel:Show()
    else
        card.usualLabel:Hide()
    end

    local function Draw(p)
        local reach = p * (count - 1)
        local slice = 0
        for index = 1, MAX_POINTS - 1 do
            local a, b = points[index], points[index + 1]
            local part = b and math.max(0, math.min(1, reach - (index - 1))) or 0
            local line, glow = card.lines[index], card.glows[index]
            if part > 0 then
                local ex, ey = a.x + (b.x - a.x) * part, a.y + (b.y - a.y) * part
                if line then
                    line:SetStartPoint("BOTTOMLEFT", card.plot, a.x, a.y)
                    line:SetEndPoint("BOTTOMLEFT", card.plot, ex, ey)
                    glow:SetStartPoint("BOTTOMLEFT", card.plot, a.x, a.y)
                    glow:SetEndPoint("BOTTOMLEFT", card.plot, ex, ey)
                    line:Show()
                    glow:Show()
                end
            else
                if line then line:Hide() glow:Hide() end
            end
            -- The gold wash under the line, a few slices a segment.
            for s = 1, SEGMENT_SLICES do
                slice = slice + 1
                local texture = card.slices[slice]
                local from, to = (s - 1) / SEGMENT_SLICES, s / SEGMENT_SLICES
                if b and part >= to then
                    local x = a.x + (b.x - a.x) * from
                    local w = (b.x - a.x) / SEGMENT_SLICES
                    local h = a.y + (b.y - a.y) * (from + to) / 2
                    texture:ClearAllPoints()
                    texture:SetPoint("BOTTOMLEFT", card.plot, "BOTTOMLEFT", x, 0)
                    texture:SetSize(math.max(1, w + 0.5), math.max(1, h))
                    Theme.SetGradientAlpha(texture, "VERTICAL", "accent", 0, 0.32)
                    texture:Show()
                else
                    texture:Hide()
                end
            end
        end
        for index, dot in ipairs(card.dots) do
            local point = points[index]
            if point and not card.lines[1] and index - 1 <= reach + 0.001 then
                dot:ClearAllPoints()
                dot:SetPoint("CENTER", card.plot, "BOTTOMLEFT", point.x, point.y)
                dot:Show()
            else
                dot:Hide()
            end
        end

        local landed = p >= 1
        local bp = points[bestIndex]
        card.bestLight:ClearAllPoints()
        card.bestLight:SetPoint("CENTER", card.plot, "BOTTOMLEFT", bp.x, bp.y)
        card.bestDot:ClearAllPoints()
        card.bestDot:SetPoint("CENTER", card.plot, "BOTTOMLEFT", bp.x, bp.y)
        card.bestLight:SetShown(landed)
        card.bestDot:SetShown(landed)
        card.bestLabel:ClearAllPoints()
        local anchor = bp.x > card.plotWidth * 0.6 and "BOTTOMRIGHT" or "BOTTOMLEFT"
        card.bestLabel:SetPoint(anchor, card.plot, "BOTTOMLEFT", bp.x + (anchor == "BOTTOMLEFT" and -4 or 4),
            math.min(bp.y + 8, card.plotHeight + 6))
        card.bestLabel:SetText(curve and L.Format("%s so far", ns.Value.Coins(best))
            or L.Format("Best %s", ns.Value.Coins(best)))
        card.bestLabel:SetShown(landed)

        local last = points[count]
        card.nowDot:ClearAllPoints()
        card.nowDot:SetPoint("CENTER", card.plot, "BOTTOMLEFT", last.x, last.y)
        card.nowDot:SetShown(landed and series[count].current and bestIndex ~= count or false)
    end

    if arrive then
        ns.Motion:Run(card, "draw", 0.9, Draw, { ease = false })
    else
        ns.Motion:Stop(card, "draw")
        Draw(1)
    end
end

--------------------------------------------------------------------------------
-- 2. Where your gold came from
--------------------------------------------------------------------------------

local SOURCE_ROW = 24

function StatsUI:BuildSources(card)
    local body = card.body
    local barWidth = card.bodyWidth - 24
    card.barWidth = barWidth

    local track = Theme.CreatePanel(body, "well", "border")
    track:SetPoint("TOPLEFT", 12, -12)
    track:SetSize(barWidth, 16)
    card.track = track

    card.segments = {}
    for index, key in ipairs(ns.Stats.SOURCES) do
        local segment = Texture(track, "ARTWORK")
        local c = StatsUI.SOURCE_COLORS[key]
        segment:SetColorTexture(c[1], c[2], c[3], 1)
        segment:SetHeight(14)
        segment:Hide()
        local shine = Texture(track, "ARTWORK", 1)
        shine:SetColorTexture(1, 1, 1, 0.18)
        shine:SetHeight(6)
        shine:Hide()
        card.segments[index] = { texture = segment, shine = shine }
    end

    card.rows = {}
    for index, key in ipairs(ns.Stats.SOURCES) do
        local row = GlassRow(body, SOURCE_ROW)
        row:SetPoint("TOPLEFT", 8, -(38 + (index - 1) * SOURCE_ROW))
        row:SetPoint("TOPRIGHT", -8, -(38 + (index - 1) * SOURCE_ROW))
        local c = StatsUI.SOURCE_COLORS[key]
        row.swatch = Texture(row, "ARTWORK")
        row.swatch:SetSize(8, 8)
        row.swatch:SetPoint("LEFT", 8, 0)
        row.swatch:SetColorTexture(c[1], c[2], c[3], 1)
        row.name = Theme.CreateLabel(row, "small", "text")
        row.name:SetPoint("LEFT", row.swatch, "RIGHT", 7, 0)
        row.name:SetText(StatsUI.SOURCE_LABELS[key])
        row.value = Theme.CreateLabel(row, "small", "text", "RIGHT")
        row.value:SetPoint("RIGHT", -8, 0)
        row.key = key
        row.onEnter = function(self)
            local share = card.total > 0 and math.floor(self.copper / card.total * 100 + 0.5) or 0
            Tip(self, StatsUI.SOURCE_LABELS[key], {
                card.view == "session"
                    and L.Format("%s, %d%% of your gold this session.", ns.Value.Coins(self.copper), share)
                    or L.Format("%s, %d%% of all your gold kept.", ns.Value.Coins(self.copper), share),
            })
        end
        Stripe(row, index, false)
        card.rows[index] = row
    end
end

function StatsUI:DrawSources(card, arrive, view)
    local list, total, first
    if view == "session" then
        list, total = ns.Stats:SessionSources()
    else
        list, total, first = ns.Stats:AllSources()
    end
    card.total, card.view, card.first = total, view, first
    card.subtitle:SetText(view == "session" and L["This session"]
        or (first and L.Format("Since %s", first) or L["Everything kept"]))

    local any = total > 0
    card.track:SetShown(any)
    for _, row in ipairs(card.rows) do row:SetShown(any) end
    if not any then
        Empty(card, L["Loot, gather or fish to see where your gold comes from."])
        return
    end
    Empty(card, nil)

    local widths = {}
    for index, entry in ipairs(list) do
        widths[index] = entry.copper / total * (card.barWidth - 2)
        local row = card.rows[index]
        row.copper = entry.copper
        row.value:SetText(entry.copper > 0 and ns.Value.Coins(entry.copper) or "|cff6b707b-|r")
    end

    local function Draw(p)
        local x = 1
        for index, segment in ipairs(card.segments) do
            -- One after another, left to right.
            local own = math.max(0, math.min(1, p * #card.segments - (index - 1)))
            local w = widths[index] * own
            if w >= 0.5 then
                segment.texture:ClearAllPoints()
                segment.texture:SetPoint("TOPLEFT", card.track, "TOPLEFT", x, -1)
                segment.texture:SetWidth(w)
                segment.texture:Show()
                segment.shine:ClearAllPoints()
                segment.shine:SetPoint("TOPLEFT", card.track, "TOPLEFT", x, -1)
                segment.shine:SetWidth(w)
                segment.shine:Show()
            else
                segment.texture:Hide()
                segment.shine:Hide()
            end
            x = x + w
        end
    end

    if arrive then
        ns.Motion:Run(card, "draw", 0.8, Draw, { ease = false })
    else
        ns.Motion:Stop(card, "draw")
        Draw(1)
    end
end

--------------------------------------------------------------------------------
-- 3. Your best mobs for gold
--------------------------------------------------------------------------------

local MOB_ROW = 34
local MOB_ROWS = 5

function StatsUI:BuildMobs(card)
    local body = card.body
    card.rows = {}
    card.trackWidth = card.bodyWidth - 16 - 20
    for index = 1, MOB_ROWS do
        local row = GlassRow(body, MOB_ROW)
        row:SetPoint("TOPLEFT", 8, -(6 + (index - 1) * MOB_ROW))
        row:SetPoint("TOPRIGHT", -8, -(6 + (index - 1) * MOB_ROW))
        row.name = Theme.CreateLabel(row, "small", "text")
        row.name:SetPoint("TOPLEFT", 10, -5)
        row.value = Theme.CreateLabel(row, "small", "text", "RIGHT")
        row.value:SetPoint("TOPRIGHT", -10, -5)
        row.track = Texture(row, "ARTWORK")
        row.track:SetColorTexture(Theme.Unpack("well"))
        row.track:SetPoint("BOTTOMLEFT", 10, 7)
        row.track:SetSize(card.trackWidth, 5)
        row.fill = Texture(row, "ARTWORK", 1)
        row.fill:SetPoint("BOTTOMLEFT", 10, 7)
        row.fill:SetHeight(5)
        Theme.SetGradientAlpha(row.fill, "HORIZONTAL", "accent", 0.55, 1)
        row.light = Light(row, 18, 1, 0.82, 0.29, 0.7)
        row.light:Hide()
        row:RegisterForClicks("LeftButtonUp")
        row:SetScript("OnClick", function(self)
            if self.mob and ns.LootTableUI then ns.LootTableUI:Show(self.mob) end
        end)
        row.onEnter = function(self)
            local entry = self.entry
            if not entry then return end
            local lines = {}
            if entry.sessionKills then
                lines[#lines + 1] = L.Format("Killed this session: %d", entry.sessionKills)
            end
            lines[#lines + 1] = L.Format("Worth per kill: %s", ns.Value.Coins(entry.perKill))
            if entry.seconds then
                lines[#lines + 1] = L.Format("About %d seconds a kill", math.floor(entry.seconds + 0.5))
                lines[#lines + 1] = entry.own and L["This is how fast you kill this one."]
                    or L.Format("Your average pace for now. This mob gets its own after %d kills in a row.", ns.Stats.PACE_MIN)
            else
                lines[#lines + 1] = L.Format("Gold an hour shows after %d kills in a row.",
                    ns.Stats.PACE_MIN)
            end
            lines[#lines + 1] = L["Click for its loot table."]
            Tip(self, entry.mob, lines)
        end
        card.rows[index] = row
    end
end

function StatsUI:DrawMobs(card, arrive, view)
    local list, byKill = ns.Stats:BestMobs(MOB_ROWS, view)
    card.byKill = byKill
    if byKill then
        card.subtitle:SetText(L["Worth per kill until your kill speed is known"])
    else
        card.subtitle:SetText(view == "session" and L["Mobs you killed this session"]
            or L["Gold an hour, at how fast you kill them"])
    end
    if #list == 0 then
        for _, row in ipairs(card.rows) do row:Hide() end
        Empty(card, view == "session"
            and L.Format("A mob shows here after you loot it %d times.",
                ns.Tracker.MIN_KILLS)
            or L.Format("Loot a mob %d times to rank it by gold an hour.",
                ns.Tracker.MIN_KILLS))
        return
    end
    Empty(card, nil)

    local top = list[1].rate or list[1].perKill
    for index, row in ipairs(card.rows) do
        local entry = list[index]
        row.entry = entry
        row.mob = entry and entry.mob
        row:SetShown(entry ~= nil)
        if entry then
            Stripe(row, index, index == 1)
            row.name:SetText(entry.mob)
            row.name:SetTextColor(Theme.Unpack(index == 1 and "accentHi" or "text"))
            local value = entry.rate or entry.perKill
            row.value:SetText(entry.rate and ns.Value.Coins(value)
                or L.Format("%s a kill", ns.Value.Coins(value)))
            row.share = top > 0 and value / top or 0
        end
    end

    local function Draw(p)
        for index, row in ipairs(card.rows) do
            if row.entry then
                local w = math.max(1, card.trackWidth * row.share * p)
                row.fill:SetWidth(w)
                row.light:ClearAllPoints()
                row.light:SetPoint("CENTER", row, "BOTTOMLEFT", 10 + w, 9)
                row.light:SetShown(index == 1 and p >= 1)
            end
        end
    end

    if arrive then
        ns.Motion:Run(card, "draw", 0.7, Draw)
    else
        ns.Motion:Stop(card, "draw")
        Draw(1)
    end
end

--------------------------------------------------------------------------------
-- 4. Luck since you logged in
--------------------------------------------------------------------------------

local LUCK_ROW = 22

function StatsUI:BuildLuck(card)
    local body = card.body
    local width = card.bodyWidth

    card.headline = Theme.CreateLabel(body, "title", "good")
    card.headline:SetPoint("TOPLEFT", 14, -10)
    card.sub = Wrapped(body, "small", "muted", width - 28)
    card.sub:SetPoint("TOPLEFT", 14, -32)

    local meterWidth = width - 28
    card.meterWidth = meterWidth
    local meter = CreateFrame("Frame", nil, body)
    meter:SetPoint("TOPLEFT", 14, -66)
    meter:SetSize(meterWidth, 10)
    card.meter = meter

    local back = Texture(meter, "BACKGROUND")
    back:SetAllPoints(meter)
    back:SetColorTexture(Theme.Unpack("well"))
    local unlucky = Texture(meter, "BORDER")
    unlucky:SetPoint("TOPLEFT")
    unlucky:SetPoint("BOTTOMLEFT")
    unlucky:SetWidth(meterWidth / 2)
    Theme.SetGradientAlpha(unlucky, "HORIZONTAL", "loss", 0.75, 0.1)
    local lucky = Texture(meter, "BORDER")
    lucky:SetPoint("TOPRIGHT")
    lucky:SetPoint("BOTTOMRIGHT")
    lucky:SetWidth(meterWidth / 2)
    Theme.SetGradientAlpha(lucky, "HORIZONTAL", "good", 0.1, 0.75)
    local middle = Texture(meter, "ARTWORK")
    middle:SetPoint("TOP", meter, "TOP", 0, 3)
    middle:SetSize(1, 16)
    middle:SetColorTexture(Theme.Unpack("muted"))

    card.needleLight = Light(meter, 30, 1, 0.82, 0.29, 0.85)
    card.needle = Texture(meter, "OVERLAY", 2)
    card.needle:SetSize(4, 20)
    card.needle:SetColorTexture(Theme.Unpack("accentHi"))

    card.lowLabel = Theme.CreateLabel(body, "tiny", "dim")
    card.lowLabel:SetPoint("TOPLEFT", meter, "BOTTOMLEFT", 0, -5)
    card.lowLabel:SetText(L["Less lucky"])
    card.highLabel = Theme.CreateLabel(body, "tiny", "dim", "RIGHT")
    card.highLabel:SetPoint("TOPRIGHT", meter, "BOTTOMRIGHT", 0, -5)
    card.highLabel:SetText(L["Luckier"])

    card.rows = {}
    for index = 1, 3 do
        local row = GlassRow(body, LUCK_ROW)
        row:SetPoint("TOPLEFT", 8, -(100 + (index - 1) * LUCK_ROW))
        row:SetPoint("TOPRIGHT", -8, -(100 + (index - 1) * LUCK_ROW))
        row.name = Theme.CreateLabel(row, "small", "text")
        row.name:SetPoint("LEFT", 10, 0)
        row.value = Theme.CreateLabel(row, "small", "muted", "RIGHT")
        row.value:SetPoint("RIGHT", -10, 0)
        Stripe(row, index, false)
        card.rows[index] = row
    end
end

--- The headline for a luck percent.
function StatsUI.LuckWords(percent)
    local whole = math.floor(math.abs(percent) + 0.5)
    if whole <= 3 then return L["Right on the odds"], "accentHi" end
    if percent > 0 then return L.Format("%d%% luckier", whole), "good" end
    return L.Format("%d%% less lucky", whole), "loss"
end

function StatsUI:DrawLuck(card, arrive, view)
    local luck = ns.Stats:Luck(view)
    card.title:SetText(view == "session" and L["Your luck this session"] or L["Your luck"])
    card.subtitle:SetText(L["Your drops vs. the usual drop rates"])
    local parts = { card.headline, card.sub, card.meter, card.lowLabel, card.highLabel }
    for _, part in ipairs(parts) do part:SetShown(luck ~= nil) end
    if not luck then
        for _, row in ipairs(card.rows) do row:Hide() end
        Empty(card, view == "session"
            and L.Format("Loot %d kills from mobs with known drop rates and you'll see if luck is on your side.",
                ns.Stats.LUCK_MIN_KILLS)
            or L.Format("Loot %d kills from mobs with known drop rates and you'll see if luck is on your side.",
                ns.Stats.LUCK_MIN_KILLS))
        return
    end
    Empty(card, nil)

    -- Only rare drops so far: no number and no needle until one is due.
    for _, part in ipairs({ card.meter, card.lowLabel, card.highLabel }) do
        part:SetShown(not luck.tooSoon)
    end
    local words, color
    if luck.tooSoon then
        words, color = L["Too soon to tell"], "muted"
    else
        words, color = StatsUI.LuckWords(luck.percent)
    end
    card.headline:SetText(words)
    card.headline:SetTextColor(Theme.Unpack(color))
    card.sub:SetText(L.Format("Over %d kills", luck.kills))

    for index, row in ipairs(card.rows) do
        local entry = luck.rows[index]
        row:SetShown(entry ~= nil)
        if entry then
            local hex = entry.color or ns.Util.ItemHex(entry.name, entry.id) or "ffffffff"
            row.name:SetText(("|c%s%s|r"):format(hex, entry.name))
            row.value:SetText(L.Format("%s, about %s expected", StatsUI.Count(entry.got),
                StatsUI.Count(entry.expected)))
        end
    end

    if luck.tooSoon then
        ns.Motion:Stop(card, "draw")
        return
    end

    local target = math.max(-1, math.min(1, luck.percent / 50))
    local function Draw(p)
        local x = card.meterWidth / 2 * (1 + target * p)
        card.needle:ClearAllPoints()
        card.needle:SetPoint("CENTER", card.meter, "LEFT", x, 0)
        card.needleLight:ClearAllPoints()
        card.needleLight:SetPoint("CENTER", card.meter, "LEFT", x, 0)
    end
    if arrive then
        ns.Motion:Run(card, "draw", 0.9, Draw, { ease = ns.Motion.EaseOutBack })
    else
        ns.Motion:Stop(card, "draw")
        Draw(1)
    end
end

--------------------------------------------------------------------------------
-- 5. Days you farmed
--------------------------------------------------------------------------------

local WEEKS = 10
local CELL = 12
local CELL_GAP = 3

-- Brighter is more gold: the well, then metal up to bright gold.
local CELL_COLORS = {
    [0] = { 0.090, 0.098, 0.118 },
    { 0.300, 0.235, 0.110 },
    { 0.470, 0.365, 0.150 },
    { 0.720, 0.570, 0.250 },
    { 1.000, 0.824, 0.290 },
}

function StatsUI:BuildDays(card)
    local body = card.body
    local grid = CreateFrame("Frame", nil, body)
    grid:SetPoint("TOP", 0, -10)
    grid:SetSize(WEEKS * (CELL + CELL_GAP), 7 * (CELL + CELL_GAP))
    card.grid = grid

    card.cells = {}
    for week = 1, WEEKS do
        for weekday = 1, 7 do
            local cell = CreateFrame("Frame", nil, grid)
            cell:SetSize(CELL, CELL)
            cell:SetPoint("TOPLEFT", (week - 1) * (CELL + CELL_GAP), -(weekday - 1) * (CELL + CELL_GAP))
            cell.fill = Theme.Fill(cell, "glassAlt")
            cell.light = Light(cell, 26, 1, 0.82, 0.29, 0.55)
            cell.light:SetPoint("CENTER")
            cell.light:Hide()
            cell:EnableMouse(true)
            cell:SetScript("OnEnter", function(self)
                local entry = self.entry
                if not entry then return end
                local lines = {}
                if entry.copper > 0 or entry.kills > 0 then
                    lines[#lines + 1] = L.Format("Gold: %s", ns.Value.Coins(entry.copper))
                    lines[#lines + 1] = L.Format("Kills: %d", entry.kills)
                    if entry.seconds >= 60 then
                        lines[#lines + 1] = L.Format("Farming: %s", ns.XP.Duration(entry.seconds))
                    end
                    if entry.top then
                        lines[#lines + 1] = L.Format("Most killed: %s (%d)", entry.top, entry.topKills)
                    end
                else
                    lines[#lines + 1] = L["Nothing farmed"]
                end
                Tip(self, entry.key or "", lines)
            end)
            cell:SetScript("OnLeave", HideTip)
            card.cells[#card.cells + 1] = cell
        end
    end
    card.today = CreateFrame("Frame", nil, grid)
    card.today:SetSize(CELL + 2, CELL + 2)
    Theme.Border(card.today, "text")

    -- The streak and the best day sit under the grid, across the card, so
    -- they keep to a line each.
    local textWidth = card.bodyWidth - 24
    local textTop = 10 + 7 * (CELL + CELL_GAP) + 26
    card.streak = Wrapped(body, "normal", "good", textWidth)
    card.streak:SetJustifyH("CENTER")
    card.streak:SetPoint("TOP", 0, -textTop)
    card.longest = Wrapped(body, "small", "muted", textWidth)
    card.longest:SetJustifyH("CENTER")
    card.longest:SetPoint("TOP", card.streak, "BOTTOM", 0, -3)
    card.bestDay = Wrapped(body, "small", "text", textWidth)
    card.bestDay:SetJustifyH("CENTER")
    card.bestDay:SetPoint("TOP", card.longest, "BOTTOM", 0, -3)

    -- Less to more, under the grid.
    card.legend = {}
    local less = Theme.CreateLabel(body, "tiny", "dim")
    less:SetPoint("TOPLEFT", grid, "BOTTOMLEFT", 0, -6)
    less:SetText(L["Less"])
    local x = Theme.TextWidth("tiny", L["Less"]) + 6
    for level = 0, 4 do
        local swatch = Texture(body, "ARTWORK")
        swatch:SetSize(10, 10)
        swatch:SetPoint("TOPLEFT", grid, "BOTTOMLEFT", x + level * 13, -7)
        local c = CELL_COLORS[level]
        swatch:SetColorTexture(c[1], c[2], c[3], 1)
    end
    local more = Theme.CreateLabel(body, "tiny", "dim")
    more:SetPoint("TOPLEFT", grid, "BOTTOMLEFT", x + 5 * 13 + 2, -6)
    more:SetText(L["More"])
end

--- How bright a day is: 0 for nothing, else 1 to 4 by its gold against the
--- best day shown.
function StatsUI.DayLevel(copper, most)
    if not copper or copper <= 0 or not most or most <= 0 then return 0 end
    local share = copper / most
    if share > 0.75 then return 4 elseif share > 0.5 then return 3 elseif share > 0.25 then return 2 end
    return 1
end

function StatsUI:DrawDays(card, arrive)
    local days = ns.Stats:Days(WEEKS * 7)
    local most, best = 0, nil
    for _, entry in ipairs(days) do
        if entry.copper > most then most, best = entry.copper, entry end
    end

    for index, cell in ipairs(card.cells) do
        local entry = days[index]
        cell.entry = entry
        local level = entry and StatsUI.DayLevel(entry.copper, most) or 0
        if level == 0 and entry and entry.kills > 0 then level = 1 end
        cell.level = level
        local c = CELL_COLORS[level]
        cell.fill:SetColorTexture(c[1], c[2], c[3], 1)
        cell.light:SetShown(level == 4)
    end

    local last = card.cells[#card.cells]
    card.today:ClearAllPoints()
    card.today:SetPoint("CENTER", last, "CENTER")

    local streak, longest = ns.Stats:Streak()
    if streak > 0 then
        card.streak:SetText(ns.Util.Plural(streak, L["day in a row"], L["days in a row"]))
        card.streak:SetTextColor(Theme.Unpack("good"))
    else
        card.streak:SetText(L["Farm today to start a streak"])
        card.streak:SetTextColor(Theme.Unpack("muted"))
    end
    card.longest:SetText(L.Format("Your longest: %d", longest))
    card.bestDay:SetText(best and L.Format("Best day: %s on %s", ns.Value.Coins(best.copper), best.key or "") or "")

    if arrive then
        -- Week by week, oldest first.
        ns.Motion:Run(card, "draw", 0.7, function(p)
            local reach = p * WEEKS
            for index, cell in ipairs(card.cells) do
                local week = math.floor((index - 1) / 7)
                cell:SetAlpha(math.max(0, math.min(1, reach - week)))
            end
        end, { ease = false })
    else
        ns.Motion:Stop(card, "draw")
        for _, cell in ipairs(card.cells) do cell:SetAlpha(1) end
    end
end

--------------------------------------------------------------------------------
-- 6. How long each level took
--------------------------------------------------------------------------------

local LEVEL_BARS = 15

function StatsUI:BuildLevels(card)
    local body = card.body
    card.headline = Wrapped(body, "small", "accentHi", card.bodyWidth - 24)
    card.headline:SetPoint("TOPLEFT", 12, -8)

    local chart = CreateFrame("Frame", nil, body)
    chart:SetPoint("TOPLEFT", 12, -36)
    chart:SetPoint("BOTTOMRIGHT", -12, 20)
    card.chart = chart
    card.chartWidth = card.bodyWidth - 24
    card.chartHeight = card.bodyHeight - 56

    card.bars = {}
    for index = 1, LEVEL_BARS do
        local bar = CreateFrame("Frame", nil, chart)
        bar.fill = Theme.Fill(bar, "metal")
        bar.light = Light(chart, 30, 1, 0.82, 0.29, 0.6)
        bar.light:Hide()
        bar.label = Theme.CreateLabel(body, "tiny", "dim", "CENTER")
        bar:EnableMouse(true)
        bar:SetScript("OnEnter", function(self)
            if not self.entry then return end
            Tip(self, L.Format("Level %d", self.entry.level), {
                L.Format("Took %s of played time", ns.XP.Duration(self.entry.seconds)),
            })
        end)
        bar:SetScript("OnLeave", HideTip)
        bar:Hide()
        card.bars[index] = bar
    end
end

function StatsUI:DrawLevels(card, arrive)
    local levels = ns.Stats:Levels(LEVEL_BARS)
    local count = #levels
    card.headline:SetShown(count > 0)
    if count == 0 then
        for _, bar in ipairs(card.bars) do
            bar:Hide()
            bar.label:Hide()
            bar.light:Hide()
        end
        Empty(card, L["Keep the XP bar on and each level's time shows up here after you level."])
        return
    end
    Empty(card, nil)

    local most, fastest = 0, nil
    for _, entry in ipairs(levels) do
        if entry.seconds > most then most = entry.seconds end
        if entry.fastest then fastest = entry end
    end
    if fastest then
        card.headline:SetText(L.Format("Fastest: level %d in %s", fastest.level, ns.XP.Duration(fastest.seconds)))
    else
        card.headline:SetText(L.Format("Level %d took %s", levels[1].level, ns.XP.Duration(levels[1].seconds)))
    end

    local slot = card.chartWidth / LEVEL_BARS
    local barWidth = math.max(4, math.floor(slot - 5))
    local offset = (card.chartWidth - slot * count) / 2

    for index, bar in ipairs(card.bars) do
        local entry = levels[index]
        bar.entry = entry
        bar:SetShown(entry ~= nil)
        bar.label:SetShown(entry ~= nil)
        if entry then
            local x = offset + (index - 1) * slot + (slot - barWidth) / 2
            bar.x = x
            bar.target = math.max(2, entry.seconds / most * card.chartHeight)
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMLEFT", card.chart, "BOTTOMLEFT", x, 0)
            bar:SetWidth(barWidth)
            bar.fill:SetColorTexture(Theme.Unpack(entry.fastest and "accentHi" or "metal"))
            bar.label:ClearAllPoints()
            bar.label:SetPoint("TOP", card.chart, "BOTTOMLEFT", x + barWidth / 2, -4)
            bar.label:SetText(tostring(entry.level))
            bar.light:ClearAllPoints()
            bar.light:SetPoint("CENTER", card.chart, "BOTTOMLEFT", x + barWidth / 2, bar.target)
        else
            bar.light:Hide()
        end
    end

    local function Draw(p)
        for _, bar in ipairs(card.bars) do
            if bar.entry then
                bar:SetHeight(math.max(1, bar.target * p))
                bar.light:SetShown(bar.entry.fastest and p >= 1)
            end
        end
    end
    if arrive then
        ns.Motion:Run(card, "draw", 0.7, Draw, { ease = ns.Motion.EaseOutBack })
    else
        ns.Motion:Stop(card, "draw")
        Draw(1)
    end
end

--------------------------------------------------------------------------------
-- The numbers across the top
--------------------------------------------------------------------------------

--- Set a tile, counting a coin value up from nothing as it arrives.
local function CountUp(tile, copper, arrive, suffix)
    local function Set(p)
        local text = ns.Value.Coins((copper or 0) * p)
        if suffix then text = text .. " |cff8b919b" .. suffix .. "|r" end
        tile.value:SetText(text)
    end
    if arrive and copper and copper > 0 then
        ns.Motion:Run(tile, "count", 0.7, Set)
    else
        ns.Motion:Stop(tile, "count")
        Set(1)
    end
end

--- A tile's big text: the large size when it fits, a step smaller when
--- not (a long mob name).
local function TileValue(tile, text)
    local fits = Theme.TextWidth("large", text) <= tile.width - 24
    tile.value:SetFont(Theme.FONT, Theme.sizes[fits and "large" or "normal"], "")
    tile.value:SetText(text)
end

local function NoValue(tile)
    ns.Motion:Stop(tile, "count")
    TileValue(tile, "|cff6b707b-|r")
end

local function Note(tile, text, color)
    tile.note:SetText(text or "")
    tile.note:SetTextColor(Theme.Unpack(color or "muted"))
end

function StatsUI:DrawTiles(arrive, view)
    local summary = ns.Stats:Summary()
    local tiles = self.tiles
    for _, tile in ipairs(tiles) do
        tile.value:SetFont(Theme.FONT, Theme.sizes.large, "")
        tile.stripe:SetColorTexture(Theme.Unpack("accent"))
    end

    local rate = tiles[1]
    rate.label:SetText(L["Gold an hour"])
    if view == "session" then
        if summary.rate then
            CountUp(rate, summary.rate, arrive)
            if summary.change then
                local whole = math.floor(math.abs(summary.change) + 0.5)
                if summary.change >= 0 then
                    Note(rate, L.Format("%d%% above your usual", whole), "good")
                else
                    Note(rate, L.Format("%d%% below your usual", whole))
                end
            else
                Note(rate, L["Your first session"])
            end
        else
            NoValue(rate)
            Note(rate, L["Farm five minutes to see it"])
        end
    elseif summary.overallRate then
        CountUp(rate, summary.overallRate, arrive)
        Note(rate, L.Format("Over %s", ns.Util.Plural(summary.sessions, L["session"], L["sessions"])))
    else
        NoValue(rate)
        Note(rate, L["Farm five minutes to see it"])
    end

    local gold = tiles[2]
    if view == "session" then
        gold.label:SetText(L["Gold this session"])
        CountUp(gold, summary.sessionCopper, arrive)
        Note(gold, summary.sessionSeconds >= 60
            and L.Format("In %s of farming", ns.XP.Duration(summary.sessionSeconds)) or L["Nothing farmed yet"])
    else
        gold.label:SetText(L["Gold farmed"])
        CountUp(gold, summary.allCopper, arrive)
        Note(gold, summary.firstDay and L.Format("Since %s", summary.firstDay) or L["Nothing farmed yet"])
    end

    local kills = tiles[3]
    if view == "session" then
        kills.label:SetText(L["Kills this session"])
        TileValue(kills, ns.XP.Comma(summary.sessionKills))
        Note(kills, summary.sessionKillsPerHour
            and L.Format("%d kills an hour", math.floor(summary.sessionKillsPerHour + 0.5)) or "")
    else
        kills.label:SetText(L["Kills"])
        TileValue(kills, ns.XP.Comma(summary.allKills))
        Note(kills, ns.Util.Plural(summary.mobKinds, L["mob"], L["different mobs"]))
    end

    local fourth = tiles[4]
    if view == "session" then
        fourth.label:SetText(L["Killed most"])
        if summary.topMob then
            TileValue(fourth, summary.topMob)
            Note(fourth, ns.Util.Plural(summary.topKills, L["kill"], L["kills"]))
        else
            NoValue(fourth)
            Note(fourth, L["Nothing killed yet"])
        end
    else
        fourth.label:SetText(L["Days in a row"])
        TileValue(fourth, tostring(summary.streak))
        Note(fourth, L.Format("Your longest is %d", summary.longest))
        fourth.stripe:SetColorTexture(Theme.Unpack(summary.streak > 0 and "good" or "accent"))
    end
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

--- Draw the whole tab. `arrive` grows the charts in, as when the tab opens.
function StatsUI:Render(arrive)
    if not self.view then return end
    self.rendering = true
    pcall(ns.Stats.Settle, ns.Stats)
    self.rendering = nil

    local view = ns.Stats:View()
    if not self.switchPlaced then self:PlaceSwitch() end
    if self.switch.selected ~= view then self.switch:Select(view) end
    if self.killGoalButton then
        self.killGoalButton:SetShown(ns.KillGoal ~= nil and ns.KillGoal:Last() ~= nil)
    end
    self.daysCard.sameTag:SetShown(view == "session")
    self.levelsCard.sameTag:SetShown(view == "session")
    local sessions = self.sessionsCard
    if view == "session" then
        sessions.title:SetText(L["Gold this session"])
        sessions.subtitle:SetText(L["Your gold so far vs. your usual pace"])
    else
        sessions.title:SetText(L["Gold an hour"])
        sessions.subtitle:SetText(L["One point for each session"])
    end

    local steps = {
        function() self:DrawTiles(arrive, view) end,
        function() self:DrawSessions(self.sessionsCard, arrive, view) end,
        function() self:DrawSources(self.sourcesCard, arrive, view) end,
        function() self:DrawMobs(self.mobsCard, arrive, view) end,
        function() self:DrawLuck(self.luckCard, arrive, view) end,
        function() self:DrawDays(self.daysCard, arrive) end,
        function() self:DrawLevels(self.levelsCard, arrive) end,
    }
    for _, step in ipairs(steps) do
        local ok, err = pcall(step)
        if not ok and ns.Debug then ns.Debug("stats: " .. tostring(err)) end
    end
    self.drawnVersion = ns.Stats.version

    if ns.UI and ns.UI.frame and ns.UI.tab == "stats" then ns.UI:ApplySize() end
end

--- The switch moved: the charts grow in again for the other view.
function StatsUI:ViewChanged()
    if self:Showing() then self:Render(true) end
end

--- Whether the tab is on screen.
function StatsUI:Showing()
    local frame = ns.UI and ns.UI.frame
    return self.view and self.view:IsShown() and frame and frame:IsShown() and true or false
end

--- Something moved: draw again once, a moment later, only if the tab is
--- on screen then and the log moved since it was drawn.
function StatsUI:Changed()
    if self.rendering or self.waiting or not self:Showing() then return end
    self.waiting = true
    local function Later()
        self.waiting = nil
        if self:Showing() and self.drawnVersion ~= ns.Stats.version then self:Render() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(StatsUI.REDRAW, Later) else Later() end
end

--- A new best session: its card lights up for a moment.
function StatsUI:Best()
    local card = self.sessionsCard
    if not (card and self:Showing()) then return end
    self:Render()
    ns.Motion:Run(card, "best", 1.6, function(p)
        Theme.SetHalo(card, 0.9 * (1 - p))
    end, { ease = false })
end

--- Hidden mobs or skinning moved: the mobs card follows on the next draw.
ns.DB.hideWatchers.stats = function()
    if StatsUI:Showing() then StatsUI:Render() end
end

-- An item's rarity came in late: the luck card's names take its colour.
ns.Util.OnRarity("stats", function()
    if StatsUI:Showing() then StatsUI:Render() end
end)
