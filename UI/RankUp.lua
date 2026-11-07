-- Blackthornes Farmer -- UI/RankUp.lua
-- The rank-up pop-up: your top 15 by worth per kill, shown for a few
-- seconds when a mob climbs it or joins it (Logic/RankUp.lua decides when).
--
-- It opens on the order as it was, the mob's row lights up, lifts out and
-- slides to its new place while the mobs it passes slide down one, its
-- worth counting up on the way. It lands with a green climb (or NEW) and a
-- glow, a short chime plays, and after about four seconds it fades away by
-- itself. The mouse over it keeps it up; a click on a row opens that mob's
-- loot table, as Rankings does; a right-click puts it away.
--
-- Dark glass, as every list is: the stripes stay by place under the rows,
-- so only the rows' words move. Window effects: Subtle lands the move at
-- once, Off shows the new order with nothing moving.

local _, ns = ...
local L = ns.L

local RankUpUI = ns.NewModule("RankUpUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local PADDING = 10
local ROW = 22
local HEAD = 46
local FOOT = 24
local MEDAL_W = 18
local BAR_W = 46
local GAP = 10
local CHIP_ROOM = 44

-- Seconds for each beat.
RankUpUI.FOCUS = 0.5
RankUpUI.SWAP = 1.1
RankUpUI.POP = 0.35
RankUpUI.GLOW = 2.2
RankUpUI.HOLD = 4
RankUpUI.FADE = 0.7

-- Gold, silver and bronze, as Rankings' medals.
local MEDALS = {
    { 1.00, 0.82, 0.30 },
    { 0.78, 0.80, 0.84 },
    { 0.80, 0.52, 0.30 },
}

local function EaseInOut(p)
    if p < 0.5 then return 4 * p * p * p end
    return 1 - (-2 * p + 2) ^ 3 / 2
end

local function Level()
    return ns.Motion and ns.Motion.Level() or "full"
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

function RankUpUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesFarmerRankUp", UIParent)
    frame:SetSize(360, HEAD + ROW * ns.RankUp.TOP + FOOT)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)

    -- Drag it anywhere; its top left is kept in `rankUpX`/`rankUpY`
    -- (account wide, nil for its usual place beside the kills panel).
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        RankUpUI:SavePlace()
    end)

    local back = Theme.Fill(frame, "window", 0.94)
    Theme.Border(frame, "borderLit")
    Theme.Halo(frame, 8, 0.12)

    -- The header: the house trim, a gold stripe down its left.
    local header = Theme.CreatePanel(frame, "header", false)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEAD - 18)
    if Theme.HouseHeader then Theme.HouseHeader(header) end

    local title = Theme.CreateLabel(header, "normal", "accent")
    title:SetPoint("LEFT", header, "LEFT", PADDING + 4, 0)
    title:SetText(L["YOUR TOP 15"])
    frame.title = title

    local note = Theme.CreateLabel(header, "small", "muted")
    note:SetPoint("LEFT", title, "RIGHT", 8, 0)
    note:SetText(L["measured, coin included"])
    frame.note = note

    -- Column names under the header.
    local columns = {}
    for _, key in ipairs({ "mob", "worth", "kills" }) do
        local label = Theme.CreateLabel(frame, "tiny", "dim", key == "kills" and "RIGHT" or "LEFT")
        columns[key] = label
    end
    columns.mob:SetText(L["MOB"])
    columns.worth:SetText(L["PER KILL"])
    columns.kills:SetText(L["KILLS"])
    self.columnLabels = columns

    -- The list: stripes by place, and the rows that move over them. It
    -- clips, so a mob sliding in from the side or off the bottom never
    -- draws outside the card.
    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -HEAD)
    list:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -HEAD)
    list:SetHeight(ROW * ns.RankUp.TOP)
    pcall(list.SetClipsChildren, list, true)
    self.list = list

    self.stripes = {}
    for slot = 1, ns.RankUp.TOP do
        local stripe = list:CreateTexture(nil, "BACKGROUND")
        stripe:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(slot - 1) * ROW)
        stripe:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -(slot - 1) * ROW)
        stripe:SetHeight(ROW)
        stripe:SetColorTexture(Theme.Unpack(slot % 2 == 1 and "glass" or "glassAlt"))

        local line = list:CreateTexture(nil, "BORDER")
        line:SetPoint("BOTTOMLEFT", stripe, "BOTTOMLEFT")
        line:SetPoint("BOTTOMRIGHT", stripe, "BOTTOMRIGHT")
        line:SetHeight(1)
        line:SetColorTexture(Theme.Unpack("border", 0.6))

        stripe.line = line
        self.stripes[slot] = stripe
        ns.SeeThrough:AddGlass("rankup", stripe)
        ns.SeeThrough:AddGlass("rankup", line)
    end

    self.rows = {}

    local foot = Theme.CreateLabel(frame, "small", "muted")
    foot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PADDING + 4, 8)
    foot:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING, 8)
    foot:SetWordWrap(true)
    self.foot = foot

    -- A thin gold line along the bottom that runs down while it holds.
    local timer = frame:CreateTexture(nil, "ARTWORK")
    timer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 3)
    timer:SetHeight(1)
    timer:SetColorTexture(Theme.Unpack("accent", 0.7))
    timer:Hide()
    self.timer = timer

    frame:SetScript("OnUpdate", function(_, elapsed) RankUpUI:Tick(elapsed) end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then RankUpUI:Hide() end
    end)

    -- The house size grip, as every window has; the size is its own.
    Widgets.ApplySize(frame, ns.db and ns.db.rankUpScale)
    self.sizeGrip = Widgets.CreateSizeGrip(frame, {
        get = function() return ns.db and ns.db.rankUpScale end,
        save = function(percent) if ns.db then ns.db.rankUpScale = percent end end,
        done = function()
            if RankUpUI:HasPlace() then RankUpUI:SavePlace() else RankUpUI:Place() end
        end,
    })

    -- See-through (UI/SeeThrough.lua, `rankUpSeeThrough`).
    ns.SeeThrough:AddGlass("rankup", back)
    ns.SeeThrough:AddGlass("rankup", header.background)
    ns.SeeThrough:Attach("rankup", frame)

    frame:Hide()
    self.frame = frame
    return frame
end

--- One row of the list, made the first time it is needed.
function RankUpUI:Row(index)
    local row = self.rows[index]
    if row then return row end

    row = CreateFrame("Button", nil, self.list)
    row:SetHeight(ROW)
    row:EnableMouse(true)
    pcall(row.RegisterForClicks, row, "LeftButtonUp", "RightButtonUp")

    -- The row picked (the mob that moved): gold in the dark, a bright gold
    -- edge down its left, and a glow that settles after it lands.
    row.glow = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.glow:SetPoint("TOPLEFT", -4, 4)
    row.glow:SetPoint("BOTTOMRIGHT", 4, -4)
    pcall(row.glow.SetBlendMode, row.glow, "ADD")
    row.glow:Hide()

    row.active = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.active:SetAllPoints(row)
    row.active:SetColorTexture(Theme.Unpack("glassActive"))
    row.active:Hide()
    -- The picked row keeps some of its gold while see-through.
    ns.SeeThrough:AddGlass("rankup", row.active, 0.6)

    -- Under the mouse: lifted glass and a gold edge, on that row only.
    row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 3)
    row.hover:SetAllPoints(row)
    row.hover:SetColorTexture(Theme.Unpack("glassHover"))
    row.hover:Hide()

    row.edge = row:CreateTexture(nil, "ARTWORK")
    row.edge:SetPoint("TOPLEFT")
    row.edge:SetPoint("BOTTOMLEFT")
    row.edge:SetWidth(2)
    row.edge:SetColorTexture(Theme.Unpack("accentHi"))
    row.edge:Hide()

    row.medal = row:CreateTexture(nil, "ARTWORK")
    row.medal:SetSize(MEDAL_W, ROW - 8)
    row.medal:SetPoint("LEFT", row, "LEFT", PADDING - 4, 0)

    row.rank = Theme.CreateLabel(row, "normal", "dim", "CENTER")
    row.rank:SetPoint("CENTER", row.medal, "CENTER", 0, 0)

    row.name = Theme.CreateLabel(row, "normal", "text")
    row.name:SetPoint("LEFT", row, "LEFT", PADDING + MEDAL_W + 6, 0)

    row.chip = CreateFrame("Frame", nil, row)
    row.chip:SetHeight(ROW - 8)
    row.chip:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.chip.fill = Theme.Fill(row.chip, "good", 0.2)
    Theme.Border(row.chip, "good")
    row.chip.label = Theme.CreateLabel(row.chip, "tiny", "good", "CENTER")
    row.chip.label:SetPoint("CENTER", 0, 0)
    row.chip:Hide()

    row.track = row:CreateTexture(nil, "ARTWORK")
    row.track:SetHeight(6)
    row.track:SetWidth(BAR_W)
    row.track:SetColorTexture(Theme.Unpack("well", 0.9))

    row.bar = row:CreateTexture(nil, "OVERLAY")
    row.bar:SetHeight(6)
    row.bar:SetPoint("LEFT", row.track, "LEFT", 0, 0)
    row.bar:SetColorTexture(Theme.Unpack("good"))

    row.worth = Theme.CreateLabel(row, "normal", "text")
    row.kills = Theme.CreateLabel(row, "small", "muted", "RIGHT")

    row:SetScript("OnEnter", function(self)
        if not self.moving then
            self.hover:Show()
            if not self.picked then self.edge:Show() end
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
        if not self.picked then self.edge:Hide() end
    end)
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            RankUpUI:Hide()
        elseif self.mob and ns.LootTableUI then
            ns.LootTableUI:Show(self.mob)
        end
    end)

    ns.SeeThrough:Grew("rankup", row)
    self.rows[index] = row
    return row
end

--------------------------------------------------------------------------------
-- Laying out
--------------------------------------------------------------------------------

--- The card's width for the mobs it will show: wide enough for every name
--- with its chip, measured, never cut short.
function RankUpUI:Fit(items)
    local name, worth = Theme.TextWidth("normal", L["MOB"]), Theme.TextWidth("normal", "99s 99c")
    local kills = Theme.TextWidth("small", Util.Plural(999, L["kill"], L["kills"]))

    for _, item in ipairs(items) do
        name = math.max(name, Theme.TextWidth("normal", ns.Tracker.ShowKey(item.mob)))
        worth = math.max(worth, Theme.TextWidth("normal", ns.Value.Coins(item.value)),
            Theme.TextWidth("normal", ns.Value.Coins(item.fromValue or item.value)))
        kills = math.max(kills, Theme.TextWidth("small", Util.Plural(item.kills, L["kill"], L["kills"])))
    end

    local x = PADDING + MEDAL_W + 6
    local layout = { name = x }
    x = x + name + CHIP_ROOM + GAP
    layout.bar = x
    x = x + BAR_W + GAP
    layout.worth = x
    x = x + worth + GAP
    layout.kills = x + kills
    layout.width = layout.kills + PADDING + 8
    return layout
end

function RankUpUI:ApplyLayout(layout, shown)
    local frame = self.frame
    frame:SetWidth(layout.width)
    frame:SetHeight(HEAD + ROW * shown + FOOT)
    self.list:SetHeight(ROW * shown)

    local c = self.columnLabels
    c.mob:ClearAllPoints()
    c.mob:SetPoint("BOTTOMLEFT", self.list, "TOPLEFT", layout.name, 3)
    c.worth:ClearAllPoints()
    c.worth:SetPoint("BOTTOMLEFT", self.list, "TOPLEFT", layout.worth, 3)
    c.kills:ClearAllPoints()
    c.kills:SetPoint("BOTTOMRIGHT", self.list, "TOPLEFT", layout.kills, 3)

    for slot, stripe in ipairs(self.stripes) do
        stripe:SetShown(slot <= shown)
        stripe.line:SetShown(slot <= shown)
    end

    self.layout = layout
end

--- Whether the player dragged it somewhere of their own.
function RankUpUI:HasPlace()
    local db = ns.db
    return db and tonumber(db.rankUpX) ~= nil and tonumber(db.rankUpY) ~= nil or false
end

--- Keep where its top left corner is now.
function RankUpUI:SavePlace()
    local frame = self.frame
    if not (frame and ns.db) then return end
    local ok, left, top = pcall(function() return frame:GetLeft(), frame:GetTop() end)
    if ok and type(left) == "number" and type(top) == "number" then
        ns.db.rankUpX, ns.db.rankUpY = left, top
    end
    self:Place()
end

--- Back to its usual place beside the kills panel.
function RankUpUI:ResetPlace()
    if ns.db then ns.db.rankUpX, ns.db.rankUpY = nil, nil end
    self:Place()
end

--- Where the player left it, else beside the kills panel (its right, else
--- its left when the screen ends), or high in the middle when the panel is
--- away.
function RankUpUI:Place()
    local frame = self.frame
    if not frame then return end
    frame:ClearAllPoints()

    if self:HasPlace() then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", tonumber(ns.db.rankUpX), tonumber(ns.db.rankUpY))
        return
    end

    local panel = ns.TrackerUI and ns.TrackerUI.frame
    if panel and panel:IsShown() then
        local ok, right, screen = pcall(function() return panel:GetRight(), UIParent:GetWidth() end)
        local width = (frame:GetWidth() or 0) * ((frame.GetScale and frame:GetScale()) or 1)
        if ok and type(right) == "number" and type(screen) == "number" and right + width + 12 > screen then
            frame:SetPoint("TOPRIGHT", panel, "TOPLEFT", -10, 0)
        else
            frame:SetPoint("TOPLEFT", panel, "TOPRIGHT", 10, 0)
        end
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

--- Draw `row` for `item` at `slot` (0 at the top; may be fractional while
--- it moves), `dx` pixels to the right, its worth `value`.
function RankUpUI:DrawRow(row, item, slot, dx, value, alpha)
    local layout = self.layout

    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.list, "TOPLEFT", dx or 0, -slot * ROW)
    row:SetWidth(layout.width - 8)
    row:SetAlpha(alpha or 1)

    local place = math.floor(slot + 0.5) + 1
    if place ~= row.place then
        row.place = place
        local medal = MEDALS[place]
        if medal then
            row.medal:SetColorTexture(medal[1], medal[2], medal[3], 0.95)
            row.medal:Show()
            row.rank:SetTextColor(0.06, 0.06, 0.07)
        else
            row.medal:Hide()
            if item.picked then row.rank:SetTextColor(Theme.Unpack("accentHi"))
            else row.rank:SetTextColor(Theme.Unpack("dim")) end
        end
        row.rank:SetText(place <= ns.RankUp.TOP and tostring(place) or "")
    end

    value = math.floor((tonumber(value) or 0) + 0.5)
    if row.value ~= value then
        row.value = value
        row.worth:SetText(ns.Value.Coins(value))
        local share = (self.best or 0) > 0 and value / self.best or 0
        row.bar:SetWidth(math.max(1, BAR_W * math.min(1, share)))
    end
end

--- Set a row's words and look for `item` once, before it moves.
function RankUpUI:Dress(row, item)
    row.mob = item.mob
    row.picked = item.picked
    row.place, row.value = nil, nil

    row.name:SetText(ns.Tracker.ShowKey(item.mob))
    row.name:SetTextColor(Theme.Unpack(item.picked and "accentHi" or "text"))
    row.kills:SetText(Util.Plural(item.kills, L["kill"], L["kills"]))

    local layout = self.layout
    row.track:ClearAllPoints()
    row.track:SetPoint("LEFT", row, "LEFT", layout.bar, 0)
    row.worth:ClearAllPoints()
    row.worth:SetPoint("LEFT", row, "LEFT", layout.worth, 0)
    row.kills:ClearAllPoints()
    row.kills:SetPoint("RIGHT", row, "LEFT", layout.kills, 0)

    row.active:SetShown(item.picked and true or false)
    row.edge:SetShown(item.picked and true or false)
    row.hover:Hide()
    row.glow:Hide()
    row.chip:Hide()
    row.chip:SetScale(1)
    row.moving = false
    row:Show()
end

--- Light the picked row's glow at `p` of its strength.
local function Glow(row, p)
    p = math.max(0, math.min(1, p or 0))
    row.glow:SetShown(p > 0)
    if p > 0 then row.glow:SetColorTexture(Theme.Unpack("accent", 0.28 * p)) end
end

--- The chip after the picked mob's name: "+5" in green, NEW in gold, or
--- TOP in gold for a new top farm. `climb` alone: "+N" on another row an
--- auction scan moved up.
local function SetChip(row, move, climb)
    local chip = row.chip
    local text, key
    if climb then
        text, key = "+" .. tostring(climb), "good"
    elseif move.newTop then
        text, key = L["TOP"], "accentHi"
    elseif move.new then
        text, key = L["NEW"], "accentHi"
    else
        text, key = "+" .. tostring(move.from - move.to), "good"
    end
    chip.label:SetText(text)
    chip.label:SetTextColor(Theme.Unpack(key))
    chip.fill:SetColorTexture(Theme.Unpack(key, 0.18))
    Theme.SetBorderColor(chip, key)
    chip:SetWidth(Theme.TextWidth("tiny", text) + 10)
end

--------------------------------------------------------------------------------
-- Showing a move
--------------------------------------------------------------------------------

--- Everything the card draws for `move`: one item per mob, with the slot
--- it starts at and the slot it ends at (0 at the top).
function RankUpUI.Items(move)
    local top = ns.RankUp.TOP
    local items, byMob = {}, {}

    local function Item(entry)
        local item = byMob[entry.mob]
        if not item then
            item = { mob = entry.mob, value = entry.value, kills = entry.kills }
            byMob[entry.mob] = item
            items[#items + 1] = item
        end
        return item
    end

    for index, entry in ipairs(move.before or {}) do
        if index <= top then
            local item = Item(entry)
            item.from = index - 1
            item.fromValue = entry.value
        end
    end

    for index, entry in ipairs(move.after or {}) do
        if index <= top or byMob[entry.mob] then
            local item = Item(entry)
            item.to = index - 1
            item.value, item.kills = entry.value, entry.kills
        end
    end

    for _, item in ipairs(items) do
        item.picked = item.mob == move.mob
        -- Pushed off the bottom, or arriving from below it.
        item.to = item.to or top
        if not item.from then
            if item.picked and move.new then
                item.from, item.slideIn = item.to, true
            else
                item.from = top
            end
        end
        item.fromValue = item.fromValue or item.value
    end

    return items
end

--- Put the card up for a move worked out by RankUp:Compare.
function RankUpUI:Show(move)
    if type(move) ~= "table" then return end
    local frame = self:Build()

    self:Stop()

    local items = RankUpUI.Items(move)
    local shown = math.min(ns.RankUp.TOP, #(move.after or {}))
    if shown == 0 then return end

    self.best = 0
    for _, item in ipairs(items) do
        self.best = math.max(self.best, item.value or 0, item.fromValue or 0)
    end

    self:ApplyLayout(self:Fit(items), shown)

    local picked
    self.chipped = {}
    for index, item in ipairs(items) do
        local row = self:Row(index)
        item.row = row
        self:Dress(row, item)
        if item.picked then
            picked = item
            SetChip(row, move)
        elseif move.climbs and move.climbs[item.mob] and (item.to or 0) < ns.RankUp.TOP then
            -- After a scan every climber shows how far it went.
            SetChip(row, move, move.climbs[item.mob])
            self.chipped[#self.chipped + 1] = row
        end
    end
    for index = #items + 1, #self.rows do self.rows[index]:Hide() end
    self.items = items

    -- After an auction scan every worth moves, so every row counts.
    self.counting = move.scan and true or false

    local title, note = L["YOUR TOP 15"], L["measured, coin included"]
    if move.newTop then
        title, note = L["NEW TOP FARM"], L["after your auction scan"]
    elseif move.scan then
        note = L["after your auction scan"]
    end
    frame.title:SetText(title)
    frame.note:SetText(note)

    if move.newTop then
        if move.lead then
            self.foot:SetText(L.Format("%s is your best farm now: %s a kill, %d%% more than %s.", ns.Tracker.ShowKey(move.mob),
                ns.Value.Coins(picked and picked.value or 0), math.floor(move.lead * 100 + 0.5), move.passed and ns.Tracker.ShowKey(move.passed) or ""))
        else
            self.foot:SetText(L.Format("%s is your best farm now: %s a kill.", ns.Tracker.ShowKey(move.mob),
                ns.Value.Coins(picked and picked.value or 0)))
        end
    elseif move.scan then
        self.foot:SetText(L["New prices from your auction scan moved your best mobs."])
    elseif not move.mob then
        self.foot:SetText("")
    elseif move.new then
        self.foot:SetText(L.Format("%s is on your board now: %s a kill.", ns.Tracker.ShowKey(move.mob),
            ns.Value.Coins(picked and picked.value or 0)))
    else
        self.foot:SetText(L.Format("%s moved up: %s to %s a kill.", ns.Tracker.ShowKey(move.mob),
            ns.Value.Coins(picked and picked.fromValue or 0), ns.Value.Coins(picked and picked.value or 0)))
    end

    self:Place()
    frame:SetAlpha(1)
    frame:Show()
    if ns.Motion then ns.Motion:Open(frame, 10) end

    local level = Level()
    local moving = level == "full"
    local focus = moving and self.FOCUS or 0
    local swap = moving and self.SWAP or 0

    -- The old order first.
    self:Step(0)

    if picked and moving then
        picked.row.moving = true
        ns.Motion:Run(frame, "focus", focus, function(p) Glow(picked.row, 0.35 * p) end)
    end

    self.landing = { move = move, picked = picked }
    if swap > 0 then
        ns.Motion:Run(frame, "swap", swap, function(p) RankUpUI:Step(p) end,
            { delay = focus, ease = EaseInOut, done = function() RankUpUI:Land() end })
    else
        self:Step(1)
        self:Land()
    end
end

--- Every row `p` of the way from the old order to the new.
function RankUpUI:Step(p)
    local width = self.layout and self.layout.width or 0

    for _, item in ipairs(self.items or {}) do
        local slot = item.from + (item.to - item.from) * p
        local dx, alpha = 0, 1
        local value = item.value

        if item.slideIn then
            -- New to the board: in from the right.
            dx = (1 - p) * width
            alpha = math.min(1, p * 1.5)
        elseif item.to >= ns.RankUp.TOP and item.from < ns.RankUp.TOP then
            -- Pushed off the bottom: it fades as it goes.
            alpha = 1 - p
        elseif item.from >= ns.RankUp.TOP then
            alpha = p
        end

        if item.picked or self.counting then
            value = item.fromValue + (item.value - item.fromValue) * p
        end
        if item.picked then
            if item.slideIn then value = item.value end
            -- Lifted a little to the right while it climbs.
            if not item.slideIn and p > 0 and p < 1 then dx = 4 end
        end

        self:DrawRow(item.row, item, slot, dx, value, alpha)
    end
end

--- The move is done: the climb or NEW pops in, the glow flares and
--- settles, the chime plays, and the hold starts.
function RankUpUI:Land()
    local landing = self.landing
    self.landing = nil
    if not landing then return end

    local picked = landing.picked
    if picked then
        local row = picked.row
        row.moving = false
        row.chip:Show()
        if Level() == "full" then
            ns.Motion:Run(row.chip, "pop", self.POP, function(p) row.chip:SetScale(math.max(0.01, p)) end,
                { ease = ns.Motion.EaseOutBack })
            ns.Motion:Run(self.frame, "glow", self.GLOW, function(p)
                Glow(row, 1 - p)
            end)
            ns.Motion:Run(self.frame, "halo", 0.8, function(p)
                Theme.SetHalo(self.frame, 0.4 + (0.12 - 0.4) * p)
            end)
        else
            Glow(row, 0)
        end
    end

    -- The rows an auction scan moved up show how far, popping in a
    -- little after one another.
    for index, row in ipairs(self.chipped or {}) do
        row.chip:Show()
        if Level() == "full" then
            row.chip:SetScale(0.01)
            ns.Motion:Run(row.chip, "pop", self.POP, function(p) row.chip:SetScale(math.max(0.01, p)) end,
                { ease = ns.Motion.EaseOutBack, delay = 0.06 * index })
        end
    end

    local sounds = ns.Tracker and ns.Tracker.SOUNDS
    local sound = sounds and (landing.move.newTop and sounds.topfarm or sounds.rankup)
    if landing.move.sound and sound then
        ns.Tracker.PlayFile(sound)
    end

    self:Hold()
end

--- Hold the card up for HOLD seconds of the mouse being away from it.
function RankUpUI:Hold()
    self.holding = self.HOLD
    self.fading = false
    self.timer:Show()
    self:Tick(0)
end

function RankUpUI:Tick(elapsed)
    if not self.holding or self.fading then return end

    local ok, over = pcall(function() return self.frame:IsMouseOver() end)
    if not (ok and over) then
        self.holding = self.holding - (tonumber(elapsed) or 0)
    end

    local width = (self.layout and self.layout.width or 0) - 8
    local share = math.max(0, self.holding / self.HOLD)
    self.timer:SetWidth(math.max(1, width * share))

    if self.holding <= 0 then self:FadeOut() end
end

function RankUpUI:FadeOut()
    if self.fading or not self.frame then return end
    self.fading = true
    self.timer:Hide()

    local frame = self.frame
    ns.Motion:Run(frame, "fade", self.FADE, function(p) frame:SetAlpha(1 - p) end, {
        done = function()
            RankUpUI.holding = nil
            RankUpUI.fading = false
            frame:Hide()
            frame:SetAlpha(1)
        end,
    })
end

--- Stop whatever is running, at once.
function RankUpUI:Stop()
    if not ns.Motion or not self.frame then return end
    ns.Motion:Stop(self.frame)
    for _, row in ipairs(self.rows or {}) do ns.Motion:Stop(row.chip) end
    self.landing = nil
    self.holding = nil
    self.fading = false
end

function RankUpUI:Hide()
    self:Stop()
    if self.frame then
        self.frame:Hide()
        self.frame:SetAlpha(1)
    end
end

function RankUpUI:IsShown()
    return self.frame and self.frame:IsShown() or false
end

--- The board's top as it stands, held up the same way, with nothing
--- moving (`/farm rankup show`, Settings).
function RankUpUI:ShowCurrent()
    local top = ns.RankUp:Current()
    if #top == 0 then
        ns.Print(L.Format("nothing on your board yet. Kill a mob %d times to rank it from your own loot.",
            ns.Tracker.MIN_KILLS))
        return
    end

    self:Show({ before = top, after = top })
    self.foot:SetText(L["Your best mobs by worth per kill, from your own kills."])
end
