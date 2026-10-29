-- Blackthornes Farmer -- UI/Goals.lua
-- The Goals panel, and the picker that sets a goal from a search result
-- (2026-09-27: "an onscreen UI element that shows how many you have
-- and how many left to gather with dopamine built in").
--
-- The panel hangs under the Kills & Loot panel until you drag it somewhere
-- else. Each goal is a card: icon, name, "23 / 40", a bar with marks at a
-- quarter, half and three quarters, how many are left, and how long that
-- should take at your pace (or the best place to get it, until there is a
-- pace).
--
-- When the count goes up:
--   * the number counts up and pops, the bar slides and a shine runs along it
--   * "+3 Copper Ore" floats off the card's right edge
--   * the card washes green; passing 25%, half or 75% pulses it gold and
--     puts a tag beside the name
--   * the last stretch turns the bar green and says "3 more!"
--   * the last one drops a GOAL COMPLETE banner over the panel with
--     sparkles and the drop-rates-unlocked sound, and the card turns into a
--     short recap
--
-- The effects follow /farm effects, like the kills panel: Subtle keeps the
-- washes, count-up and slide; Off keeps none. They compare the addon's own
-- counts and never read the client, and anything that goes wrong is
-- dropped rather than raised.

local _, ns = ...
local L = ns.L

local GoalsUI = ns.NewModule("GoalsUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local WIDTH = 236
-- As tall as the kills panel's title line, which it docks under.
local HEADER = 28
local PADDING = 8
local CARD = 62
-- As wide as the widest line needs, up to this, so nothing is cut off.
local MAX_WIDTH = 380
local FOOTER = 22
local ICON = 22
local BAR_HEIGHT = 7
local GAP = 6

GoalsUI.CARD = CARD
GoalsUI.HEADER = HEADER

local FALLBACK_ICON = [[Interface\Icons\INV_Misc_QuestionMark]]

-- Timings, in seconds.
local COUNT_TIME = 0.7
local SLIDE_TIME = 0.5
local SHINE_TIME = 0.8
local GLOW_TIME = 1.3
local PULSE_TIME = 2.2
local POP_TIME = 0.4
local FLOAT_TIME = 1.8
local FLOAT_RISE = 30
local BANNER_TIME = 4
local BANNER_HEIGHT = 44

local COUNT_SIZE = 14
local POP_SIZE = 20
local SHINE_WIDTH = 26

local BRIGHT_GOLD = { 1, 0.906, 0.639 }

-- How bright the glow round the panel sits: low, since the panel is up all
-- the time. It flares as the panel opens, and more on the big moments.
local HALO_REST = 0.08
-- A flare peaks at this many times the resting glow and settles back over
-- this long: a goal done outshines a milestone passed.
local FLARE_DONE, FLARE_DONE_TIME = 5, 1.4
local FLARE_MILESTONE, FLARE_MILESTONE_TIME = 3.2, 0.9

GoalsUI.cards = {}
GoalsUI.effects = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function Color(key)
    local r, g, b = Theme.Unpack(key)
    return { r, g, b }
end

local function EaseOut(p)
    return 1 - (1 - p) ^ 3
end

local function Level()
    if ns.TrackerFX then return ns.TrackerFX.Level() end
    return "full"
end

--- "23 / 40", the first part bright.
function GoalsUI.CountText(have, target)
    return ("%s|c%s / %d|r"):format(tostring(math.floor(have + 0.5)), ns.COLORS.muted, target)
end

-- The kill goal's icon (Logic/KillGoal.lua): a sword.
local KILL_ICON = "Interface\\Icons\\INV_Sword_04"

local function IsKill(goal)
    return ns.KillGoal ~= nil and ns.KillGoal:Is(goal)
end

--- What a card is called: the item, or the kill goal's "Kill 1000 Mobs".
local function NameOf(goal)
    if IsKill(goal) then return ns.KillGoal.Title(goal) end
    return goal.item
end

--- Every card on this character's panel: the kill goal first, then the
--- item goals in the order they were set.
function GoalsUI:List()
    local list = {}
    local kill = ns.KillGoal and ns.KillGoal:Current()
    if kill then list[1] = kill end
    for _, goal in ipairs(ns.Goals:List()) do list[#list + 1] = goal end
    return list
end

local function IconOf(name)
    local look = ns.Tracker and ns.Tracker:LookOf(name) or {}
    if look.icon then return look.icon end

    local id = ns.Value and ns.Value:ItemID(name)
    if id and type(C_Item) == "table" and type(C_Item.GetItemIconByID) == "function" then
        local ok, icon = pcall(C_Item.GetItemIconByID, id)
        if ok and icon then
            local readable = ns.Harvest.ReadableNumber(icon) or ns.Harvest.Readable(icon)
            if readable then return readable end
        end
    end

    return FALLBACK_ICON
end

--------------------------------------------------------------------------------
-- The clock
--
-- Its own, on a frame of UIParent's: the kills panel's clock stops when that
-- panel is hidden, and the goals panel may well be showing without it.
--------------------------------------------------------------------------------

function GoalsUI:Driver()
    if self.driver then return self.driver end

    local driver = CreateFrame("Frame", nil, UIParent)
    driver:SetScript("OnUpdate", function(_, elapsed) GoalsUI:Step(elapsed) end)
    driver:Hide()

    self.driver = driver
    return driver
end

--- Start `effect`: { slot, duration, delay, apply(p), stop() }. A new effect
--- in the same slot replaces the one there.
function GoalsUI:Animate(effect)
    for index = #self.effects, 1, -1 do
        local other = self.effects[index]
        if effect.slot and other.slot == effect.slot then
            if other.stop then pcall(other.stop) end
            table.remove(self.effects, index)
        end
    end

    effect.age = -(effect.delay or 0)
    self.effects[#self.effects + 1] = effect
    -- Drawn at its start straight away, so the finished state never shows
    -- for a frame first.
    if not effect.delay then pcall(effect.apply, 0) end
    self:Driver():Show()
end

function GoalsUI:Step(elapsed)
    elapsed = tonumber(elapsed) or 0
    local live = {}

    for _, effect in ipairs(self.effects) do
        effect.age = effect.age + elapsed

        if effect.age >= 0 then
            local p = math.min(1, effect.age / effect.duration)
            local ok, err = pcall(effect.apply, p)

            if not ok then
                if effect.stop then pcall(effect.stop) end
                ns.Debug("goal effect dropped:", tostring(err))
            elseif p < 1 then
                live[#live + 1] = effect
            end
        else
            live[#live + 1] = effect
        end
    end

    self.effects = live
    if #live == 0 and self.driver then self.driver:Hide() end
end

--- Stop the effects running on `card`, put back as they were. For a card
--- about to show a different goal: a glow or count still running there
--- belonged to the goal that was on it.
function GoalsUI:StopCard(card)
    local slots = { [card.flash] = true, [card.count] = true, [card.fill] = true,
        [card.fresh] = true, [card.shine] = true }
    local live = {}
    for _, effect in ipairs(self.effects) do
        if effect.slot and slots[effect.slot] then
            if effect.stop then pcall(effect.stop) end
        else
            live[#live + 1] = effect
        end
    end
    self.effects = live
end

--- Everything stopped and put back.
function GoalsUI:Forget()
    for _, effect in ipairs(self.effects) do
        if effect.stop then pcall(effect.stop) end
    end
    self.effects = {}
    if self.driver then self.driver:Hide() end
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

function GoalsUI:Width()
    -- Docked under the kills panel, as wide as it is on screen (it widens
    -- past its saved width to fit its lines), so the two line up. Its size
    -- setting scales it, so its width is taken into this panel's units.
    local tracker = ns.TrackerUI and ns.TrackerUI.frame
    if not ns.db.goalsX and tracker and tracker:IsShown() then
        local ok, width = pcall(function()
            local own = (self.frame or UIParent):GetEffectiveScale()
            return tracker:GetWidth() * tracker:GetEffectiveScale() / own
        end)
        if ok and type(width) == "number" and width > 0 then
            return math.min(MAX_WIDTH, math.floor(width + 0.5))
        end
    end
    if ns.TrackerUI and ns.TrackerUI.Width then return ns.TrackerUI:Width() end
    return WIDTH
end

function GoalsUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesFarmerGoals", UIParent)
    frame:SetSize(self:Width(), HEADER + CARD)
    frame:SetFrameStrata("LOW")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    -- Solid enough that name plates and chat behind it do not show through
    -- the text (a screenshot, 2026-09-27).
    local back = Theme.Fill(frame, "window", 0.96)
    Theme.Border(frame, "border")
    -- The house's neon edge, as the other windows have.
    Theme.Halo(frame, 8, HALO_REST)

    frame:SetScript("OnDragStart", function(self)
        GoalsUI.dragging = true
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        GoalsUI.dragging = nil
        self:StopMovingOrSizing()
        GoalsUI:SavePosition()
    end)

    local header = Theme.CreatePanel(frame, "header", false)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER)

    Theme.HouseHeader(header)

    local title = Theme.CreateLabel(header, "normal", "accent")
    title:SetPoint("LEFT", PADDING + 4, 0)
    title:SetText(L["Goals"])

    local close = Widgets.HeaderCloseGem(header, function()
        ns.db.goalsHidden = true
        GoalsUI:Refresh()
        ns.Print(L["goals panel hidden. /farm goals brings it back."])
    end)
    close:SetPoint("RIGHT", -6, 0)

    local rule = Theme.CreateDivider(frame, "borderLit")
    rule:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    rule:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")

    -- Goals done today, and a way to the next one.
    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", 1, 1)
    footer:SetPoint("BOTTOMRIGHT", -1, 1)
    footer:SetHeight(FOOTER)
    local footerBack = Theme.Fill(footer, "header", 0.9)

    footer.left = Theme.CreateLabel(footer, "small", "muted")
    footer.left:SetPoint("LEFT", PADDING, 0)

    footer.next = Widgets.CreateButton(footer, L["Set another"], function()
        -- The New Goal box: Item opens the search, as this did before;
        -- Kills sets a kill goal (UI/KillGoal.lua).
        if ns.KillGoalUI then
            ns.KillGoalUI:ShowNew()
        elseif ns.UI then
            ns.UI:Show()
            -- The search box is on the Search tab: focused while the window
            -- shows Rankings, it would take your keys out of sight.
            if ns.UI.tab ~= "search" then ns.UI:ShowTab("search") end
            if ns.UI.searchBox then ns.UI.searchBox:SetFocus() end
        end
    end, { width = 70, height = 16 })
    footer.next:SetPoint("RIGHT", -PADDING + 2, 0)

    self.frame = frame
    self.header = header
    self.title = title
    self.closeButton = close
    self.footer = footer

    -- The house size grip beside the bottom right corner, as the kills
    -- panel wears it (Widgets.CreateSizeGrip), saved as `goalsScale`.
    -- Docked, it grows from the kills panel's corner and docks again on
    -- release; its width still matches the kills panel's on screen.
    Widgets.ApplySize(frame, ns.db and ns.db.goalsScale)
    self.sizeGrip = Widgets.CreateSizeGrip(frame, {
        beside = true,
        name = "panel",
        get = function() return ns.db and ns.db.goalsScale end,
        save = function(percent) if ns.db then ns.db.goalsScale = percent end end,
        -- Held where the drag has it: a goal changing mid-drag docks it
        -- only once the drag is done.
        onStart = function() GoalsUI.dragging = true end,
        done = function()
            GoalsUI.dragging = nil
            if ns.db.goalsX then GoalsUI:SavePosition() end
            GoalsUI:Refresh()
        end,
    })

    -- See-through (UI/SeeThrough.lua, `goalsSeeThrough`).
    local SeeThrough = ns.SeeThrough
    SeeThrough:AddGlass("goals", back)
    SeeThrough:AddGlass("goals", header.background)
    SeeThrough:AddGlass("goals", footerBack)
    SeeThrough:Attach("goals", frame)

    self:RestorePosition()
    frame:Hide()
    return frame
end

--- One goal's card, made the first time it is needed.
function GoalsUI:Card(index)
    local card = self.cards[index]
    if card then return card end

    local frame = self.frame
    card = CreateFrame("Button", nil, frame)
    card:SetHeight(CARD)
    card:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Dark glass, a shade apart card by card, with a fine line under each
    -- (the house list rows, 2026-10-12).
    card.band = Theme.Fill(card, index % 2 == 0 and "glassAlt" or "glass")
    card.rule = card:CreateTexture(nil, "BACKGROUND", nil, 1)
    card.rule:SetPoint("BOTTOMLEFT")
    card.rule:SetPoint("BOTTOMRIGHT")
    card.rule:SetHeight(1)
    card.rule:SetColorTexture(Theme.Unpack("border", 0.6))
    ns.SeeThrough:AddGlass("goals", card.band)
    ns.SeeThrough:AddGlass("goals", card.rule)

    -- Under the mouse the card lifts, a lighter wash and a lit edge easing
    -- in, so it reads as something to click. Both start clear.
    card.hover = card:CreateTexture(nil, "BACKGROUND", nil, 1)
    card.hover:SetAllPoints(card)
    card.hover:SetColorTexture(Theme.Unpack("glassHover"))
    card.hover:SetAlpha(0)
    Theme.Border(card, "borderLit")
    for _, line in ipairs(card.borderTextures) do line:SetAlpha(0) end

    -- The wash and the left edge the effects light up.
    card.flash = card:CreateTexture(nil, "BORDER")
    card.flash:SetAllPoints(card)
    pcall(card.flash.SetBlendMode, card.flash, "ADD")
    card.flash:SetAlpha(0)

    card.edge = card:CreateTexture(nil, "ARTWORK")
    card.edge:SetPoint("TOPLEFT")
    card.edge:SetPoint("BOTTOMLEFT")
    card.edge:SetWidth(2)
    card.edge:SetAlpha(0)

    card.outline = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local line = card:CreateTexture(nil, "ARTWORK")
        if side == "TOP" or side == "BOTTOM" then
            line:SetPoint(side .. "LEFT")
            line:SetPoint(side .. "RIGHT")
            line:SetHeight(1)
        else
            line:SetPoint("TOP" .. side)
            line:SetPoint("BOTTOM" .. side)
            line:SetWidth(1)
        end
        line:SetAlpha(0)
        card.outline[#card.outline + 1] = line
    end

    card.iconBorder = card:CreateTexture(nil, "ARTWORK")
    card.iconBorder:SetSize(ICON + 2, ICON + 2)
    card.iconBorder:SetPoint("TOPLEFT", PADDING - 1, -5)
    card.iconBorder:SetColorTexture(Theme.Unpack("borderLit"))

    card.icon = card:CreateTexture(nil, "OVERLAY")
    card.icon:SetSize(ICON, ICON)
    card.icon:SetPoint("TOPLEFT", PADDING, -6)
    card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    card.name = Theme.CreateLabel(card, "normal", "text")
    card.name:SetPoint("TOPLEFT", PADDING + ICON + 8, -6)

    card.sub = Theme.CreateLabel(card, "tiny", "muted")
    card.sub:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -2)

    -- The best places near you to farm it (2026-09-27).
    card.where = Widgets.CreateButton(card, L["Places"], function()
        if card.goal then GoalsUI:OpenSpots(card.goal.item, GoalsUI.frame) end
    end, { width = 52, height = 15, labelKey = "accent" })
    card.where:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    card.where:HookScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["Best places near you to farm this"])
            GameTooltip:Show()
        end
    end)

    -- The milestone tag: dark text on a gold chip.
    card.tagBack = card:CreateTexture(nil, "ARTWORK")
    card.tagBack:SetColorTexture(Theme.Unpack("accent"))
    card.tagBack:SetHeight(12)

    card.tag = Theme.CreateLabel(card, "tiny", "window", "CENTER")
    card.tag:SetPoint("LEFT", card.name, "RIGHT", 8, 0)
    card.tagBack:SetPoint("TOPLEFT", card.tag, "TOPLEFT", -4, 1)
    card.tagBack:SetPoint("BOTTOMRIGHT", card.tag, "BOTTOMRIGHT", 4, -1)

    card.count = Theme.CreateLabel(card, "large", "text", "RIGHT")
    pcall(card.count.SetFont, card.count, Theme.FONT, COUNT_SIZE, "OUTLINE")
    card.count:SetPoint("TOPRIGHT", -PADDING, -8)

    -- The bar: a dark track, the fill, a brighter tip, the part just
    -- gathered, and a shine that runs along it.
    card.track = card:CreateTexture(nil, "BORDER")
    card.track:SetPoint("TOPLEFT", PADDING, -36)
    card.track:SetPoint("TOPRIGHT", -PADDING, -36)
    card.track:SetHeight(BAR_HEIGHT)
    card.track:SetColorTexture(Theme.Unpack("window"))

    card.fill = card:CreateTexture(nil, "ARTWORK")
    card.fill:SetPoint("TOPLEFT", card.track, "TOPLEFT")
    card.fill:SetHeight(BAR_HEIGHT)

    card.tip = card:CreateTexture(nil, "OVERLAY")
    card.tip:SetPoint("TOPRIGHT", card.fill, "TOPRIGHT")
    card.tip:SetSize(4, BAR_HEIGHT)
    card.tip:SetColorTexture(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 0.9)

    -- And a soft spark round the tip, spilling past the bar, so the bar
    -- reads as on its way. Coloured by SetBar, with the bar.
    card.spark = card:CreateTexture(nil, "OVERLAY", nil, 1)
    card.spark:SetPoint("RIGHT", card.fill, "RIGHT", 4, 0)
    card.spark:SetSize(14, 10)
    pcall(card.spark.SetBlendMode, card.spark, "ADD")
    card.spark:Hide()

    card.fresh = card:CreateTexture(nil, "OVERLAY")
    card.fresh:SetHeight(BAR_HEIGHT)
    card.fresh:SetColorTexture(1, 0.95, 0.8, 1)
    pcall(card.fresh.SetBlendMode, card.fresh, "ADD")
    card.fresh:SetAlpha(0)

    card.shine = card:CreateTexture(nil, "OVERLAY")
    card.shine:SetSize(SHINE_WIDTH, BAR_HEIGHT)
    card.shine:SetColorTexture(1, 1, 1, 1)
    pcall(card.shine.SetBlendMode, card.shine, "ADD")
    card.shine:SetAlpha(0)

    card.ticks = {}
    for index = 1, 3 do
        local tick = card:CreateTexture(nil, "OVERLAY")
        tick:SetSize(1, BAR_HEIGHT)
        tick:SetColorTexture(1, 1, 1, 0.22)
        card.ticks[index] = tick
    end

    card.left = Theme.CreateLabel(card, "small", "muted")
    card.left:SetPoint("TOPLEFT", card.track, "BOTTOMLEFT", 0, -3)

    card.right = Theme.CreateLabel(card, "tiny", "muted", "RIGHT")

    -- The Where? button sits on the line under the bar, at its right end,
    -- with the time left just before it.
    card.where:SetPoint("TOPRIGHT", card.track, "BOTTOMRIGHT", 0, -3)

    local function Lit(value)
        card.hover:SetAlpha(0.6 * value)
        for _, line in ipairs(card.borderTextures) do line:SetAlpha(value) end
    end

    card:SetScript("OnEnter", function(self)
        ns.Motion:Blend(self, "hover", 1, 0.12, Lit)
        GoalsUI:ShowCardTooltip(self)
    end)
    card:SetScript("OnLeave", function(self)
        ns.Motion:Blend(self, "hover", 0, 0.18, Lit)
        if GameTooltip then GameTooltip:Hide() end
    end)
    -- Hidden under the mouse (its goal cleared, the panel closed), no leave
    -- may come: let go, or the next goal it shows starts lit.
    card:SetScript("OnHide", function(self)
        ns.Motion:Stop(self, "hover")
        ns.Motion:SetValue(self, "hover", 0)
        Lit(0)
    end)
    card:SetScript("OnClick", function(self, button) GoalsUI:OnCardClick(self, button) end)

    ns.SeeThrough:Grew("goals", card)
    self.cards[index] = card
    return card
end

function GoalsUI:BarWidth()
    local width = (self.frame and self.frame:GetWidth()) or self:Width()
    return math.max(20, width - 2 - PADDING * 2)
end

--- The bar filled to `fraction`, green in the last stretch or when done.
function GoalsUI:SetBar(card, fraction, green)
    local width = self:BarWidth()
    fraction = math.max(0, math.min(1, fraction or 0))

    local r, g, b = Theme.Unpack(green and "good" or "accent")
    card.fill:SetColorTexture(r, g, b, 1)
    card.fill:SetWidth(math.max(1, width * fraction))
    card.fill:SetShown(fraction > 0)

    if green then
        card.tip:SetColorTexture(0.66, 1, 0.77, 0.9)
    else
        card.tip:SetColorTexture(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 0.9)
    end
    card.tip:SetShown(fraction > 0.02 and fraction < 1)

    -- The spark turns green with the bar. Drawn again only when it changes
    -- colour: this runs every frame while the bar slides.
    local sparkKey = green and "good" or "accent"
    if card.sparkKey ~= sparkKey then
        Theme.SetGradientAlpha(card.spark, "HORIZONTAL", sparkKey, 0, 0.55)
        card.sparkKey = sparkKey
    end
    card.spark:SetShown(fraction > 0.02 and fraction < 1)
end

--- The small grey line under the name: the best place near you, from the
--- same ranking the Where button opens. Ranking walks every loot record
--- and saved spot, so the line is kept per goal until what it is made
--- from changes (the same key the goal arrow keeps its places on): every
--- loot redraws the cards, and the ranking cannot have changed between.
local spotTexts = {}

local function SpotText(goal)
    local item = goal.item
    local Gathering, Harvest = ns.Gathering, ns.Harvest
    local player = ns.Spots:Player()
    local key = table.concat({ tostring(player.zone), tostring(player.level),
        tostring(Gathering and Gathering.spotsVersion or 0), tostring(Harvest and Harvest.changes or 0) }, "|")
    local kept = spotTexts[item]
    if kept and kept.key == key then return kept.text end

    local text = ""
    local ok, spots = pcall(ns.Spots.For, ns.Spots, item)
    local spot = ok and spots and spots[1]
    if spot then
        local distance = ns.Spots.DistanceText(spot.hops, spot.zone, spot.travel)
        if distance == L["you are here"] then
            text = ("%s, %s"):format(spot.name or "?", Util.Colored("good", L["here"]))
        else
            text = ("%s, %s"):format(spot.name or "?", ns.Spots.Show(spot.zone) or "?")
        end
    end
    spotTexts[item] = { key = key, text = text }
    return text
end

--- The largest label size a goal's name fits in `room` at: "normal",
--- "small" or "tiny" (where a name still too long wraps).
function GoalsUI.NameSize(name, room)
    for _, size in ipairs({ "normal", "small" }) do
        if Theme.TextWidth(size, name) <= room then return size end
    end
    return "tiny"
end

function GoalsUI:DrawCard(card, goal)
    local Goals = ns.Goals
    card.goal = goal

    local kill = IsKill(goal)
    card.icon:SetTexture(kill and KILL_ICON or IconOf(goal.item))

    -- The name in its quality colour where the tracker has seen it.
    local look = (not kill and ns.Tracker and ns.Tracker:LookOf(goal.item)) or {}
    -- The name stops short of the count and the milestone tag, both
    -- measured: a width picked by eye let a long name run into "23 / 40".
    local countText = GoalsUI.CountText(goal.have or 0, goal.target or 0)
    local maxName = self:BarWidth() - ICON - 8 - Theme.TextWidth("large", Util.StripColor(countText)) - 10
    local tagText = goal.done and L["DONE"]
        or ((goal.milestone or 0) > 0 and Goals.MILESTONES[goal.milestone].tag) or nil
    if tagText then maxName = maxName - Theme.TextWidth("tiny", tagText) - 16 end
    -- Past the panel's widest, a long name steps down a size or two, and
    -- at the smallest wraps onto a second line: never cut to "...".
    local name = NameOf(goal)
    local size = GoalsUI.NameSize(name, maxName)
    pcall(card.name.SetFont, card.name, Theme.FONT, Theme.sizes[size], "")
    local wraps = Theme.TextWidth(size, name) > maxName
    card.name:SetWidth(wraps and math.max(1, maxName) or 0)
    card.name:SetWordWrap(wraps)
    if card.name.SetMaxLines then pcall(card.name.SetMaxLines, card.name, wraps and 2 or 0) end
    card.name:SetText(name)
    if kill then
        card.name:SetText(Util.Colored("text", name))
    elseif type(look.color) == "string" and #look.color == 8 then
        card.name:SetText(("|c%s%s|r"):format(look.color, name))
    else
        -- No loot link kept its colour: the item's rarity from the client.
        card.name:SetText(Util.ColorItem(name))
    end

    local fraction = Goals.Fraction(goal)
    local final = Goals.Final(goal)

    card.count:SetText(GoalsUI.CountText(goal.have or 0, goal.target or 0))
    pcall(card.count.SetFont, card.count, Theme.FONT, COUNT_SIZE, "OUTLINE")

    -- The tag: the last milestone passed, or DONE.
    local tag
    if goal.done then
        tag = L["DONE"]
    elseif (goal.milestone or 0) > 0 then
        tag = Goals.MILESTONES[goal.milestone].tag
    end
    card.tag:SetText(tag or "")
    card.tag:SetShown(tag ~= nil)
    card.tagBack:SetShown(tag ~= nil)
    card.tagBack:SetColorTexture(Theme.Unpack(goal.done and "good" or "accent"))

    local width = self:BarWidth()
    for index, milestone in ipairs(Goals.MILESTONES) do
        local tick = card.ticks[index]
        tick:ClearAllPoints()
        tick:SetPoint("TOPLEFT", card.track, "TOPLEFT", math.floor(width * milestone.at), 0)
        tick:SetShown(not goal.done)
    end

    self:SetBar(card, fraction, final or goal.done)
    card.where:SetShown(not goal.done and not kill)

    card.right:ClearAllPoints()
    if goal.done or kill then
        card.right:SetPoint("TOPRIGHT", card.track, "BOTTOMRIGHT", 0, -5)
    else
        card.right:SetPoint("RIGHT", card.where, "LEFT", -6, 0)
    end
    card.sub:SetWidth(self:BarWidth() - ICON - 8)

    if kill then
        self:DrawKillLines(card, goal, final)
    elseif goal.done then
        local recap = Goals:Recap(goal)
        card.sub:SetText(Util.Colored("good", L["Goal done"]) .. (goal.doneIn and goal.doneIn >= 1
            and Util.Colored("muted", L.Format("  in %s", Goals.Duration(goal.doneIn))) or ""))

        local parts = {}
        if recap.loots > 0 then
            parts[#parts + 1] = Util.Plural(recap.loots, L["loot"], L["loots"])
            if recap.perLoot then
                parts[#parts + 1] = L.Format("%.1f each", recap.perLoot)
            end
        end
        card.left:SetText(table.concat(parts, "  |  "))
        card.left:SetTextColor(Theme.Unpack("muted"))
        card.right:SetText(recap.worth and ns.Value.Coins(recap.worth) or "")
    else
        card.sub:SetText(SpotText(goal))

        local left = Goals.Left(goal)
        if final then
            card.left:SetText(left == 1 and L["1 more!"] or L.Format("%d more!", left))
            card.left:SetTextColor(Theme.Unpack("good"))
        else
            card.left:SetText(L.Format("|c%s%d|r left", ns.COLORS.text, left))
            card.left:SetTextColor(Theme.Unpack("muted"))
        end

        local eta = Goals.Eta(goal)
        card.right:SetText(eta and L.Format("%s at your pace", Goals.Duration(eta, true)) or "")
    end

    card:Show()
end

--- The kill goal's lines under its bar (Logic/KillGoal.lua): how far
--- along, how many to go and the time left at your pace; once done, the
--- time it took, its gold and a click for the summary.
function GoalsUI:DrawKillLines(card, goal, final)
    local KillGoal = ns.KillGoal
    if goal.done then
        local last = KillGoal:Last()
        local seconds = last and last.seconds or goal.seconds
        card.sub:SetText(Util.Colored("good", L["Goal done"]) .. ((tonumber(seconds) or 0) >= 1
            and Util.Colored("muted", L.Format("  in %s", ns.Goals.Duration(seconds))) or ""))
        card.left:SetText(L["Click to see the summary."])
        card.left:SetTextColor(Theme.Unpack("muted"))
        card.right:SetText(last and last.gold and last.gold > 0 and ns.Value.Coins(last.gold) or "")
        return
    end

    card.sub:SetText(Util.Colored("muted", L.Format("%d%%", math.floor(ns.Goals.Fraction(goal) * 100))))
    local left = ns.Goals.Left(goal)
    if final then
        card.left:SetText(left == 1 and L["1 more!"] or L.Format("%d more!", left))
        card.left:SetTextColor(Theme.Unpack("good"))
    else
        card.left:SetText(L.Format("%d to go", left))
        card.left:SetTextColor(Theme.Unpack("muted"))
    end
    card.right:SetText(KillGoal.EtaText(goal) or "")
end

--- How wide a card has to be for none of its text to be cut off or run
--- into something else. Measured, since the game's font runs wider than
--- any width picked by eye.
function GoalsUI:CardNeeds(card, goal)
    local text = Util.StripColor
    -- The same gap DrawCard keeps between the name and the count: with any
    -- less, the panel widened for a name and DrawCard still cut it.
    local count = Theme.TextWidth("large", text(card.count:GetText())) + 10

    local top = PADDING + ICON + 8 + Theme.TextWidth("normal", NameOf(goal)) + count + PADDING
    if card.tag:IsShown() then top = top + Theme.TextWidth("tiny", card.tag:GetText()) + 16 end

    local sub = PADDING + ICON + 8 + Theme.TextWidth("tiny", text(card.sub:GetText())) + PADDING

    local bottom = PADDING * 2 + Theme.TextWidth("small", text(card.left:GetText()))
        + Theme.TextWidth("tiny", text(card.right:GetText())) + 16
    if card.where:IsShown() then bottom = bottom + card.where:GetWidth() + 6 end

    return math.max(top, sub, bottom) + 2
end

function GoalsUI:Render()
    self:Build()

    local list = self:List()
    local width = self:Width()
    -- The width it started from, so the kills panel can tell when it has
    -- changed and a redraw is due.
    self.lastBase = width
    self.frame:SetWidth(width)

    local done = ns.Goals:DoneToday()
    local anyDone = false
    for _, goal in ipairs(list) do
        if goal.done then anyDone = true end
    end

    local footer = done > 0 or anyDone
    if footer then
        self.footer.left:SetText(L.Format("Goals done today: |c%s%d|r", ns.COLORS.accent, done))
    end
    self.footer:SetShown(footer)

    -- Draw once at the usual width, measure, and widen and draw again when
    -- a line needs more room. The footer's count and its Set another button
    -- sit side by side, so they are measured too.
    local needs = 0
    if footer then
        needs = PADDING + Theme.TextWidth("small", Util.StripColor(self.footer.left:GetText()))
            + 8 + self.footer.next:GetWidth() + PADDING
    end
    for index, goal in ipairs(list) do
        local card = self:Card(index)
        if card.goal ~= nil and card.goal ~= goal then self:StopCard(card) end
        self:DrawCard(card, goal)
        needs = math.max(needs, self:CardNeeds(card, goal))
    end
    local fit = math.min(MAX_WIDTH, math.max(width, math.ceil(needs)))
    local widened = fit ~= width
    if widened then self.frame:SetWidth(fit) end

    for index, goal in ipairs(list) do
        local card = self:Card(index)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 1, -(HEADER + GAP / 2 + (index - 1) * (CARD + 2)))
        card:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -1, -(HEADER + GAP / 2 + (index - 1) * (CARD + 2)))
        -- Drawn again only when the width moved under it.
        if widened then self:DrawCard(card, goal) end
    end

    for index = #list + 1, #self.cards do
        self:StopCard(self.cards[index])
        self.cards[index]:Hide()
        self.cards[index].goal = nil
    end

    self.frame:SetHeight(HEADER + GAP + #list * (CARD + 2) + (footer and FOOTER or 0))
end

--- An item's rarity came in late (Util.OnRarity): the cards and the
--- titles naming it take its colour. Only what is up is drawn.
function GoalsUI:RarityArrived()
    if self.frame and self.frame:IsShown() then self:Render() end
    local spots = self.spots
    if spots and spots:IsShown() and self.spotsItem then
        spots.title:SetText(L.Format("Where to farm |c%s%s|r", Util.ItemHexOr("text", self.spotsItem),
            self.spotsItem))
    end
    local picker = self.picker
    local item = GoalsUI.pickItem
    if picker and picker:IsShown() and item then
        picker.title:SetText(L.Format("GATHERING GOAL  |c%s%s|r", Util.ItemHexOr("text", item),
            (item:upper():gsub("ä", "Ä"):gsub("ö", "Ö"):gsub("ü", "Ü"))))
    end
end

Util.OnRarity("goals", function() GoalsUI:RarityArrived() end)

--- Redraw, and show or hide: shown while there are goals, unless you
--- closed it.
function GoalsUI:Refresh()
    self:Build()

    if #self:List() == 0 or ns.db.goalsHidden then
        self.frame:Hide()
        self:Forget()
        return
    end

    self:Render()
    self:Place()

    -- It fades up, its glow flaring, only as it appears: this also runs
    -- each time a goal is set or removed, and a panel already up must not
    -- blink. It never rises, since players drag it into place.
    local opening = not self.frame:IsShown()
    self.frame:Show()
    if opening then ns.Motion:Open(self.frame, 0) end
end

function GoalsUI:Show()
    ns.db.goalsHidden = false
    self:Refresh()
end

function GoalsUI:Toggle()
    if self.frame and self.frame:IsShown() then
        ns.db.goalsHidden = true
        self:Refresh()
    else
        self:Show()
    end
end

-- `/farm goals` and a middle-click on the minimap button: with no goals
-- there is no panel to show, so say how to make one.
function GoalsUI:ToggleOrHint()
    if #self:List() == 0 then
        ns.Print(L["no goals yet. /farm goal Copper Ore 40, or the Goal button on a search result."])
        return
    end
    self:Toggle()
end

function GoalsUI:OnEnable()
    self:Refresh()
end

--------------------------------------------------------------------------------
-- The card under the mouse
--------------------------------------------------------------------------------

function GoalsUI:ShowCardTooltip(card)
    local goal = card.goal
    if not (goal and GameTooltip) then return end

    GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
    if IsKill(goal) then
        GameTooltip:AddLine(NameOf(goal))
        GameTooltip:AddLine(L.Format("%d of %d", goal.have or 0, goal.target or 0), 1, 1, 1)
        if goal.done then
            GameTooltip:AddLine(L["Click to see the summary."], 0.6, 0.6, 0.6)
        else
            GameTooltip:AddLine(L["Right-click to remove the goal."], 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
        return
    end
    GameTooltip:AddLine(Util.ColorItem(goal.item))
    GameTooltip:AddLine(L.Format("%d of %d", goal.have or 0, goal.target or 0), 1, 1, 1)
    if goal.done then
        GameTooltip:AddLine(L["Click to clear it."], 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine(L["Click to find where to farm it."], 0.6, 0.6, 0.6)
        GameTooltip:AddLine(L["Shift-click to point the goal arrow at it."], 0.6, 0.6, 0.6)
        GameTooltip:AddLine(L["Right-click to remove the goal."], 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

function GoalsUI:OnCardClick(card, button)
    local goal = card.goal
    if not goal then return end

    if IsKill(goal) then
        if goal.done then
            if ns.KillGoalUI then ns.KillGoalUI:ShowSummary() end
        elseif button == "RightButton" then
            ns.KillGoal:Stop()
            ns.Print(L.Format("goal for %s removed.", Util.Colored("accent", NameOf(goal))))
        end
        return
    end

    if goal.done then
        ns.Goals:Remove(goal.item)
        return
    end

    if button ~= "RightButton" and type(IsShiftKeyDown) == "function" and IsShiftKeyDown() and ns.Arrow then
        ns.Arrow:Aim(goal.item)
        return
    end

    if button == "RightButton" then
        ns.Goals:Remove(goal.item)
        ns.Print(L.Format("goal for %s removed.", Util.ColorItemOr("accent", goal.item)))
        return
    end

    if ns.RunSearch then ns.RunSearch(goal.item) end
end

--------------------------------------------------------------------------------
-- Effects
--------------------------------------------------------------------------------

local function CardFor(goal)
    for _, card in ipairs(GoalsUI.cards) do
        if card.goal == goal and card:IsShown() then return card end
    end
    return nil
end

function GoalsUI:Glow(card, rgb, peak, duration, beats)
    card.flash:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
    card.edge:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
    for _, line in ipairs(card.outline) do line:SetColorTexture(rgb[1], rgb[2], rgb[3], 1) end

    local function Alpha(alpha, outline)
        card.flash:SetAlpha(alpha)
        card.edge:SetAlpha(math.min(1, alpha * 2.5))
        for _, line in ipairs(card.outline) do line:SetAlpha(outline and math.min(1, alpha * 1.8) or 0) end
    end

    self:Animate({ slot = card.flash, duration = duration or GLOW_TIME,
        apply = function(p)
            if beats then
                local beat = 0.55 + 0.45 * math.cos(p * beats * 2 * math.pi)
                Alpha(peak * (1 - p) ^ 1.5 * beat, true)
            else
                Alpha(peak * (1 - p) ^ 2, false)
            end
        end,
        stop = function() Alpha(0, false) end })
end

function GoalsUI:CountUp(card, goal, from, to, pop)
    local target = goal.target or 0

    self:Animate({ slot = card.count, duration = COUNT_TIME,
        apply = function(p)
            local e = EaseOut(p)
            card.count:SetText(GoalsUI.CountText(from + (to - from) * e, target))
            if pop then
                pcall(card.count.SetFont, card.count, Theme.FONT,
                    COUNT_SIZE + (POP_SIZE - COUNT_SIZE) * (1 - EaseOut(math.min(1, p * 1.75))), "OUTLINE")
            end
        end,
        stop = function()
            card.count:SetText(GoalsUI.CountText(card.goal and card.goal.have or to, target))
            pcall(card.count.SetFont, card.count, Theme.FONT, COUNT_SIZE, "OUTLINE")
        end })
end

--- The bar sliding from where it was, the part just gathered lit, and (at
--- Full) a shine running along it once it lands.
function GoalsUI:Slide(card, goal, fromFraction, toFraction, shine)
    local width = self:BarWidth()
    local green = goal.done or ns.Goals.Final(goal)

    self:Animate({ slot = card.fill, duration = SLIDE_TIME,
        apply = function(p)
            self:SetBar(card, fromFraction + (toFraction - fromFraction) * EaseOut(p), green)
        end,
        stop = function() self:SetBar(card, ns.Goals.Fraction(goal), green) end })

    if toFraction > fromFraction then
        card.fresh:ClearAllPoints()
        card.fresh:SetPoint("TOPLEFT", card.track, "TOPLEFT", width * fromFraction, 0)
        card.fresh:SetWidth(math.max(1, width * (toFraction - fromFraction)))

        self:Animate({ slot = card.fresh, duration = GLOW_TIME, delay = SLIDE_TIME * 0.6,
            apply = function(p) card.fresh:SetAlpha(0.6 * (1 - p) ^ 2) end,
            stop = function() card.fresh:SetAlpha(0) end })
    end

    if shine then
        local reach = math.max(SHINE_WIDTH, width * toFraction)
        self:Animate({ slot = card.shine, duration = SHINE_TIME, delay = SLIDE_TIME * 0.5,
            apply = function(p)
                card.shine:ClearAllPoints()
                card.shine:SetPoint("TOPLEFT", card.track, "TOPLEFT",
                    math.max(0, (reach - SHINE_WIDTH) * p), 0)
                card.shine:SetAlpha(0.55 * math.sin(p * math.pi))
            end,
            stop = function() card.shine:SetAlpha(0) end })
    end
end

function GoalsUI:FloatLabel()
    self.floats = self.floats or {}

    for _, label in ipairs(self.floats) do
        if not label.flying then return label end
    end

    if not self.holder then
        self.holder = CreateFrame("Frame", nil, self.frame)
        self.holder:SetAllPoints(self.frame)
        self.holder:SetFrameLevel(self.frame:GetFrameLevel() + 10)
    end

    local label = Theme.CreateLabel(self.holder, "normal", "good")
    label:Hide()
    self.floats[#self.floats + 1] = label
    return label
end

--- "+3 Copper Ore" rising off the card's right edge.
function GoalsUI:Float(card, text, size, delay)
    local label = self:FloatLabel()
    pcall(label.SetFont, label, Theme.FONT, size or 13, "OUTLINE")
    label:SetText(text)
    label:SetAlpha(0)
    label.flying = true

    local function Place(rise)
        label:ClearAllPoints()
        label:SetPoint("LEFT", card, "RIGHT", 8, 6 + rise)
    end

    Place(0)
    label:Show()

    self:Animate({ slot = label, duration = FLOAT_TIME, delay = delay,
        apply = function(p)
            Place(FLOAT_RISE * EaseOut(p))
            label:SetAlpha(p < 0.15 and p / 0.15 or (1 - (p - 0.15) / 0.85))
            if p >= 1 then
                label:Hide()
                label.flying = false
            end
        end,
        stop = function()
            label:Hide()
            label.flying = false
        end })
end

-- Where the sparkles sit on the banner, as fractions across and down.
local SPARKS = {
    { 0.04, 0.2 }, { 0.12, 0.85 }, { 0.3, 0.1 }, { 0.62, 0.9 },
    { 0.8, 0.12 }, { 0.95, 0.75 }, { 0.5, 0.06 }, { 0.2, 0.5 },
    { 0.72, 0.55 }, { 0.88, 0.35 },
}

function GoalsUI:Banner()
    if self.banner then return self.banner end

    local frame = self.frame
    local banner = CreateFrame("Frame", nil, frame)
    banner:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -(HEADER + 3))
    banner:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -(HEADER + 3))
    banner:SetHeight(BANNER_HEIGHT)
    banner:SetFrameLevel(frame:GetFrameLevel() + 12)

    Theme.Fill(banner, "window", 0.96)
    Theme.Border(banner, "accent")

    local wash = banner:CreateTexture(nil, "BORDER")
    wash:SetAllPoints(banner)
    wash:SetColorTexture(Theme.Unpack("accent"))
    pcall(wash.SetBlendMode, wash, "ADD")
    banner.wash = wash

    local title = Theme.CreateLabel(banner, "large", "accent", "CENTER")
    pcall(title.SetFont, title, Theme.FONT, 15, "OUTLINE")
    title:SetTextColor(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1)
    title:SetPoint("TOPLEFT", 6, -6)
    title:SetPoint("TOPRIGHT", -6, -6)
    banner.title = title

    local subject = Theme.CreateLabel(banner, "small", "text", "CENTER")
    subject:SetPoint("BOTTOMLEFT", 6, 7)
    subject:SetPoint("BOTTOMRIGHT", -6, 7)
    banner.subject = subject

    banner.sparks = {}
    for index = 1, #SPARKS do
        local spark = banner:CreateTexture(nil, "OVERLAY")
        spark:SetSize(3, 3)
        spark:SetColorTexture(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1)
        pcall(spark.SetBlendMode, spark, "ADD")
        banner.sparks[index] = spark
    end

    local shine = banner:CreateTexture(nil, "OVERLAY")
    shine:SetHeight(BANNER_HEIGHT)
    shine:SetWidth(40)
    shine:SetColorTexture(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1)
    pcall(shine.SetBlendMode, shine, "ADD")
    shine:SetAlpha(0)
    banner.shine = shine

    banner:Hide()
    self.banner = banner
    return banner
end

--- GOAL COMPLETE across the top of the panel.
function GoalsUI:Complete(goal)
    local banner = self:Banner()
    banner.title:SetText(L["GOAL COMPLETE"])
    banner:SetAlpha(0)
    banner:Show()

    local ok, width = pcall(banner.GetWidth, banner)
    width = ok and tonumber(width) or WIDTH

    -- How long it took, where the banner has room for it (the chat line
    -- says it too): measured, as it ran off a panel at its usual width.
    local kill = IsKill(goal)
    local subject = kill and ("%d / %d"):format(goal.have or 0, goal.target or 0)
        or ("%d / %d %s"):format(goal.have or 0, goal.target or 0, Util.ColorItem(goal.item))
    local spent = kill and goal.seconds or goal.doneIn
    if (tonumber(spent) or 0) >= 1 then
        local took = subject .. "  |  " .. ns.Goals.Duration(spent)
        if Theme.TextWidth("small", took) <= width - 12 then subject = took end
    end
    banner.subject:SetText(subject)

    for index, spark in ipairs(banner.sparks) do
        spark:ClearAllPoints()
        spark:SetPoint("CENTER", banner, "TOPLEFT", SPARKS[index][1] * width,
            -SPARKS[index][2] * BANNER_HEIGHT)
    end

    self:Animate({ slot = "banner", duration = BANNER_TIME,
        apply = function(p)
            local alpha = p < 0.06 and p / 0.06 or (p > 0.8 and (1 - p) / 0.2 or 1)
            banner:SetAlpha(alpha)
            banner.wash:SetAlpha(0.14 + 0.1 * math.sin(p * 8 * math.pi))

            for index, spark in ipairs(banner.sparks) do
                local twinkle = 0.5 + 0.5 * math.sin(p * 14 * math.pi + index * 1.7)
                spark:SetAlpha(twinkle * alpha)
            end

            local sweep = p * BANNER_TIME / SHINE_TIME
            if sweep < 1 then
                banner.shine:ClearAllPoints()
                banner.shine:SetPoint("TOPLEFT", banner, "TOPLEFT", (width - 40) * sweep, 0)
                banner.shine:SetAlpha(0.4 * math.sin(sweep * math.pi))
            else
                banner.shine:SetAlpha(0)
            end

            if p >= 1 then banner:Hide() end
        end,
        stop = function()
            banner:Hide()
            banner.shine:SetAlpha(0)
        end })
end

--- The search list's Goal buttons read "23/40"; keep them current while
--- the Search tab shows. Behind Rankings or Grind, or with the window shut,
--- it is only marked stale and redrawn when the tab shows again: each
--- gather of a goal item ran the whole search for a list nobody saw.
function GoalsUI:RedrawSearch()
    local UI = ns.UI
    if not (UI and UI.list and UI.frame) then return end
    if UI.frame:IsShown() and UI.tab == "search" then
        UI.searchStale = nil
        pcall(UI.Render, UI)
    else
        UI.searchStale = true
    end
end

--- The goals' counts moved (Goals:Update). Redraw, then animate each card
--- from where it was.
function GoalsUI:Changed(changes)
    -- The search list's buttons follow the count with this panel closed too.
    self:RedrawSearch()

    if not (self.frame and self.frame:IsShown()) then
        -- Closed: a finished goal still opens it, for the moment.
        local finished = false
        for _, change in ipairs(changes) do
            if change.done then finished = true end
        end
        if not finished then return end
        ns.db.goalsHidden = false
        self:Refresh()
    else
        self:Render()
        -- Taller with the footer, it may no longer fit under the kills panel.
        if not self.dragging then self:Place() end
    end

    local level = Level()
    if level == "off" then return end

    local floats = 0
    local done, milestone = false, false
    for _, change in ipairs(changes) do
        local ok, err = pcall(self.Play, self, change, level, floats)
        if not ok then ns.Debug("goal effects:", tostring(err)) end
        if change.gathered then floats = floats + 1 end
        if change.done then done = true elseif change.milestone then milestone = true end
    end

    -- The glow round the panel flares once, for the biggest moment in
    -- this count.
    if done then
        self:Flare(FLARE_DONE, FLARE_DONE_TIME)
    elseif milestone then
        self:Flare(FLARE_MILESTONE, FLARE_MILESTONE_TIME)
    end
end

--- The glow round the panel flares to `strength` times its rest and eases
--- back over `duration` seconds. Through Motion, so with effects off it
--- simply stays at rest.
function GoalsUI:Flare(strength, duration)
    local frame = self.frame
    local rest = frame and frame.haloRest
    if not rest then return end

    local peak = rest * strength
    ns.Motion:Run(frame, "halo", duration, function(p)
        Theme.SetHalo(frame, peak + (rest - peak) * p)
    end)
end

function GoalsUI:Play(change, level, floats)
    local goal = change.goal
    local card = CardFor(goal)
    if not card then return end

    local target = tonumber(goal.target) or 0
    if target <= 0 then return end

    local full = level == "full"
    local up = change.to > change.from

    self:CountUp(card, goal, change.from, change.to, full and up)
    self:Slide(card, goal, math.min(1, change.from / target), math.min(1, change.to / target), full and up)

    if change.done then
        self:Glow(card, BRIGHT_GOLD, 0.6, PULSE_TIME, 3)
        -- The banner, its sparkles and shine are Full's; Subtle keeps the glow.
        if full then self:Complete(goal) end
    elseif change.milestone then
        self:Glow(card, BRIGHT_GOLD, 0.55, PULSE_TIME, 3)
    elseif up then
        self:Glow(card, Color("good"), 0.3)
    end

    if full and change.gathered then
        self:Float(card, ("+%d %s"):format(change.gathered, change.name or NameOf(goal)), 13, floats * 0.18)
        if change.milestone then
            self:Float(card, Util.Colored("accent", change.milestone.at == 0.50
                and L["Halfway there!"] or (change.milestone.tag .. "!")), 16, floats * 0.18 + 0.35)
        elseif ns.Goals.Final(goal) then
            local left = ns.Goals.Left(goal)
            self:Float(card, Util.Colored("good", left == 1 and L["1 more!"] or L.Format("%d more!", left)),
                15, floats * 0.18 + 0.35)
        end
    end
end

--------------------------------------------------------------------------------
-- Position
--
-- Under the kills panel until you drag it; after that, where you put it.
--------------------------------------------------------------------------------

--- Which side of the kills panel this one docks on: "below" while there is
--- room under it, else "above", else "right" or "left", whichever has more
--- room. Below when the client will not say.
local function DockSide(frame, tracker)
    local ok, side = pcall(function()
        local own = frame:GetEffectiveScale()
        local scale = tracker:GetEffectiveScale() / own
        local screen = UIParent:GetEffectiveScale() / own
        local need = frame:GetHeight() + GAP
        -- Compared here, inside the pcall: a secret value raises on it.
        if tracker:GetBottom() * scale >= need then return "below" end
        if UIParent:GetTop() * screen - tracker:GetTop() * scale >= need then return "above" end
        local left = tracker:GetLeft() * scale
        local right = UIParent:GetRight() * screen - tracker:GetRight() * scale
        return right >= left and "right" or "left"
    end)
    return ok and side or "below"
end

function GoalsUI:Place()
    local frame = self.frame
    if not frame or ns.db.goalsX then return end

    local tracker = ns.TrackerUI and ns.TrackerUI.frame
    frame:ClearAllPoints()
    if tracker and tracker:IsShown() then
        -- Under it, unless a tall kills panel leaves too little room there:
        -- kept on screen, this one was pushed up over it.
        local side = DockSide(frame, tracker)
        if side == "above" then
            frame:SetPoint("BOTTOMLEFT", tracker, "TOPLEFT", 0, GAP)
        elseif side == "right" then
            frame:SetPoint("TOPLEFT", tracker, "TOPRIGHT", GAP, 0)
        elseif side == "left" then
            frame:SetPoint("TOPRIGHT", tracker, "TOPLEFT", -GAP, 0)
        else
            frame:SetPoint("TOPLEFT", tracker, "BOTTOMLEFT", 0, -GAP)
        end
    else
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 8, -190)
    end
end

function GoalsUI:SavePosition()
    local frame = self.frame
    if not frame then return end

    local ok, left, top = pcall(function() return frame:GetLeft(), frame:GetTop() end)
    if not (ok and type(left) == "number" and type(top) == "number") then return end

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    ns.db.goalsX = left
    ns.db.goalsY = top
end

function GoalsUI:RestorePosition()
    local frame = self.frame
    if not frame then return end

    if ns.db.goalsX and ns.db.goalsY then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", ns.db.goalsX, ns.db.goalsY)
    else
        self:Place()
    end
end

--- Back under the kills panel.
function GoalsUI:Dock()
    ns.db.goalsX = nil
    ns.db.goalsY = nil
    self:Place()
end

--------------------------------------------------------------------------------
-- Where to farm it: the best places near you (Logic/Spots.lua)
--------------------------------------------------------------------------------

local SPOTS_WIDTH = 300
local SPOT_ROW = 36
local SPOTS_TOP = 44
-- The gold rim round the panel reaches this far in; its rows stop short.
local SPOTS_EDGE = 6

--- What a spot's distance looks like: here in green, next door in gold.
local function DistanceColor(hops)
    if hops == 0 then return "good" end
    if hops == 1 then return "accent" end
    return "muted"
end

--- The note under a spot: what you measured there, else the rate known.
--- Rates read as the kills panel writes them, so a rare drop is "<1%",
--- not "0%".
function GoalsUI.SpotNote(spot)
    -- A node your gathering skill cannot take yet says so first.
    local short = ns.Spots.SkillShortText and ns.Spots.SkillShortText(spot)
    if short then return Util.Colored("warn", short) end
    local yours = spot.yours
    if yours and yours.opens then
        return Util.Colored("good", L.Format("in %d of the %d you opened", yours.got or 0, yours.opens))
    end
    if yours and yours.gathers then
        if spot.kind == "container" then
            return Util.Colored("good", L.Format("%d from the %d you opened here", yours.got or 0, yours.gathers))
        end
        return Util.Colored("good", L.Format("you gathered %d here", yours.got or 0))
    end
    if yours and yours.kills then
        if spot.measured then
            return Util.Colored("good", L.Format("%s in your %d kills",
                ns.Tracker.FormatChance(spot.measured), yours.kills))
        end
        return Util.Colored("good", L.Format("%d from your %d kills", yours.got or 0, yours.kills))
    end
    if spot.chance then return L.Format("%s drop", ns.Tracker.FormatChance(spot.chance)) end
    if spot.requires then return spot.requires end
    return ""
end

function GoalsUI:BuildSpots()
    if self.spots then return self.spots end

    local panel = CreateFrame("Frame", "BlackthornesFarmerGoalSpots", UIParent)
    panel:SetSize(SPOTS_WIDTH, SPOTS_TOP + SPOT_ROW)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)

    local back = Theme.Fill(panel, "window", 0.96)
    -- The house frame's rim and corner gems, and its red close gem
    -- (UI/Titanforged.lua). Its own title stays inside: it names the item
    -- in two colours and the panel is sized to it.
    local spotsTrim
    if ns.Titanforged then
        spotsTrim = ns.Titanforged:Dress(panel, { close = function() panel:Hide() end })
    else
        Theme.Border(panel, "accent")
        local close = Widgets.CreateButton(panel, "X", function() panel:Hide() end,
            { width = 16, height = 14, danger = true })
        close:SetPoint("TOPRIGHT", -6, -6)
    end
    -- The house glow round it, flaring as it opens.
    Theme.Halo(panel, 8, 0.10)

    -- The house size grip under the bottom right corner
    -- (Widgets.CreateSizeGrip), saved as `goalSpotsScale`.
    Widgets.ApplySize(panel, ns.db and ns.db.goalSpotsScale)
    panel.sizeGrip = Widgets.CreateSizeGrip(panel, {
        name = "panel",
        below = spotsTrim and select(4, ns.Titanforged.Reach(spotsTrim)) or 0,
        get = function() return ns.db and ns.db.goalSpotsScale end,
        save = function(percent) if ns.db then ns.db.goalSpotsScale = percent end end,
    })

    local title = Theme.CreateLabel(panel, "normal", "accent")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetPoint("TOPRIGHT", -30, -10)
    panel.title = title

    local from = Theme.CreateLabel(panel, "tiny", "muted")
    from:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    -- TOPRIGHT, not RIGHT: a RIGHT point pins the label's middle to the
    -- panel's, which stretched it down and drew the line mid-panel.
    from:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 20, -4)
    panel.from = from

    local rule = Theme.CreateDivider(panel, "borderLit")
    rule:SetPoint("TOPLEFT", SPOTS_EDGE, -(SPOTS_TOP - 4))
    rule:SetPoint("TOPRIGHT", -SPOTS_EDGE, -(SPOTS_TOP - 4))

    panel.empty = Theme.CreateLabel(panel, "small", "muted")
    panel.empty:SetPoint("TOPLEFT", 12, -(SPOTS_TOP + 8))
    panel.empty:SetText(L["No places known for this yet."])

    panel.rows = {}

    local hint = Theme.CreateLabel(panel, "tiny", "dim")
    hint:SetPoint("BOTTOMLEFT", 12, 6)
    hint:SetPoint("BOTTOMRIGHT", -10, 6)
    hint:SetText(L["Click a place to put it in chat. If it's in this zone, it gets a pin on your map too. Shift-click points the goal arrow there."])
    hint:SetWordWrap(true)
    panel.hint = hint

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesFarmerGoalSpots")
    end

    -- See-through (UI/SeeThrough.lua, `goalSpotsSeeThrough`).
    ns.SeeThrough:AddGlass("places", back)
    ns.SeeThrough:Attach("places", panel)

    panel:Hide()
    self.spots = panel
    return panel
end

function GoalsUI:SpotRow(index)
    local panel = self.spots
    local row = panel.rows[index]
    if row then return row end

    row = CreateFrame("Button", nil, panel)
    row:SetHeight(SPOT_ROW)
    row:SetPoint("TOPLEFT", SPOTS_EDGE, -(SPOTS_TOP + (index - 1) * SPOT_ROW))
    row:SetPoint("TOPRIGHT", -SPOTS_EDGE, -(SPOTS_TOP + (index - 1) * SPOT_ROW))

    -- Dark glass, a shade apart row by row, with a fine line under each.
    row.band = Theme.Fill(row, index % 2 == 0 and "glassAlt" or "glass")
    row.rule = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.rule:SetPoint("BOTTOMLEFT")
    row.rule:SetPoint("BOTTOMRIGHT")
    row.rule:SetHeight(1)
    row.rule:SetColorTexture(Theme.Unpack("border", 0.6))
    ns.SeeThrough:AddGlass("places", row.band)
    ns.SeeThrough:AddGlass("places", row.rule)
    -- The light the lists' rows wear under the mouse. The wash here was
    -- filled clear, so no alpha could ever show it.
    Widgets.RowLight(row)

    row.flash = row:CreateTexture(nil, "BORDER")
    row.flash:SetAllPoints(row)
    pcall(row.flash.SetBlendMode, row.flash, "ADD")
    row.flash:SetColorTexture(Theme.Unpack("good"))
    row.flash:SetAlpha(0)

    row.rank = Theme.CreateLabel(row, "large", "accent", "CENTER")
    pcall(row.rank.SetFont, row.rank, Theme.FONT, 15, "OUTLINE")
    row.rank:SetPoint("LEFT", 6, 0)
    row.rank:SetWidth(18)

    row.name = Theme.CreateLabel(row, "normal", "text")
    row.name:SetPoint("TOPLEFT", 30, -4)
    row.name:SetPoint("TOPRIGHT", -60, -4)

    row.level = Theme.CreateLabel(row, "small", "text", "RIGHT")
    row.level:SetPoint("TOPRIGHT", -10, -5)
    row.level:SetWidth(50)

    -- The note sizes to its own text; the zone line stops short of it.
    row.note = Theme.CreateLabel(row, "tiny", "muted", "RIGHT")
    row.note:SetPoint("BOTTOMRIGHT", -10, 5)

    row.zone = Theme.CreateLabel(row, "tiny", "muted")
    row.zone:SetPoint("BOTTOMLEFT", 30, 5)
    row.zone:SetPoint("RIGHT", row.note, "LEFT", -8, 0)

    local function Lit(value) Widgets.SetRowLight(row, value) end
    row:SetScript("OnEnter", function(self) ns.Motion:Blend(self, "hover", 1, 0.12, Lit) end)
    row:SetScript("OnLeave", function(self) ns.Motion:Blend(self, "hover", 0, 0.18, Lit) end)
    -- Closed with Escape under the mouse, no leave may come: let go, or the
    -- row is lit when the panel opens again.
    row:SetScript("OnHide", function(self)
        ns.Motion:Stop(self, "hover")
        ns.Motion:SetValue(self, "hover", 0)
        Lit(0)
    end)
    row:SetScript("OnClick", function(self)
        if not self.spot then return end
        if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() and ns.Arrow then
            ns.Arrow:Aim(GoalsUI.spotsItem, self.spot)
        else
            ns.Spots:Share(GoalsUI.spotsItem, self.spot)
        end
        GoalsUI:Animate({ slot = self.flash, duration = GLOW_TIME,
            apply = function(p) self.flash:SetAlpha(0.35 * (1 - p) ^ 2) end,
            stop = function() self.flash:SetAlpha(0) end })
    end)

    ns.SeeThrough:Grew("places", row)
    panel.rows[index] = row
    return row
end

--- Rank the places for `item` from where you are and show them beside
--- `anchor` (the goals panel), or on their own.
function GoalsUI:OpenSpots(item, anchor)
    local panel = self:BuildSpots()

    if panel:IsShown() and self.spotsItem == item then
        panel:Hide()
        return
    end
    self.spotsItem = item

    local spots, player = ns.Spots:For(item)

    panel.title:SetText(L.Format("Where to farm |c%s%s|r", Util.ItemHexOr("text", item), item))
    if player.zone and player.level then
        panel.from:SetText(L.Format("Nearest first, from %s at level %d", ns.Spots.Show(player.zone), player.level))
    elseif player.zone then
        panel.from:SetText(L.Format("Nearest first, from %s", ns.Spots.Show(player.zone)))
    else
        panel.from:SetText(L["The game won't say which zone you're in, so these are sorted by level and rate"])
    end

    for index, spot in ipairs(spots) do
        local row = self:SpotRow(index)
        row.spot = spot

        row.rank:SetText(tostring(index))
        -- A clam or sack you opened is an item, in its rarity colour.
        if spot.kind == "container" and spot.yours and spot.yours.container and spot.name then
            row.name:SetText(Util.ColorItem(spot.name))
        else
            row.name:SetText(spot.name or "?")
        end

        -- Coloured the way the search window colours a level: red well above
        -- you, yellow around you, green and then grey below.
        row.level:SetText(spot.minLevel and ns.Search:LevelText(spot) or "")
        if ns.UI and ns.UI.DifficultyColor then
            row.level:SetTextColor(ns.UI.DifficultyColor(spot.maxLevel or spot.minLevel))
        else
            row.level:SetTextColor(Theme.Unpack("text"))
        end

        local distance = ns.Spots.DistanceText(spot.hops, spot.zone, spot.travel)
        local where = ns.Spots.Show(spot.zone) or "?"
        if spot.location then where = where .. ", " .. spot.location end
        if distance ~= "" then
            where = where .. ("  |c%s%s|r"):format(ns.COLORS[DistanceColor(spot.hops)], distance)
        end
        row.zone:SetText(where)
        row.note:SetText(GoalsUI.SpotNote(spot))
        row:Show()
    end

    for index = #spots + 1, #panel.rows do
        panel.rows[index]:Hide()
        panel.rows[index].spot = nil
    end

    -- Wide enough for every row's text, measured.
    local needs = Theme.TextWidth("normal", Util.StripColor(panel.title:GetText())) + 42
    needs = math.max(needs, Theme.TextWidth("tiny", panel.from:GetText()) + 22)
    -- The rows stop short of the rim either side.
    for index = 1, #spots do
        local row = panel.rows[index]
        needs = math.max(needs,
            2 * SPOTS_EDGE + 30 + Theme.TextWidth("normal", row.name:GetText()) + 70,
            2 * SPOTS_EDGE + 30 + Theme.TextWidth("tiny", Util.StripColor(row.zone:GetText())) + 8
                + Theme.TextWidth("tiny", Util.StripColor(row.note:GetText())) + 12)
    end
    panel:SetWidth(math.min(480, math.max(SPOTS_WIDTH, math.ceil(needs))))

    panel.empty:SetShown(#spots == 0)
    panel:SetHeight(SPOTS_TOP + math.max(1, #spots) * SPOT_ROW + 44)

    panel:ClearAllPoints()
    if anchor and anchor.IsShown and anchor:IsShown() then
        panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 0)
    else
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    end
    local opening = not panel:IsShown()
    panel:Show()
    if opening then ns.Motion:Open(panel, 4) end

    -- The rows slide in one after another.
    if Level() == "full" then
        for index = 1, #spots do
            local row = panel.rows[index]
            row:SetAlpha(0)
            self:Animate({ slot = row, duration = 0.35, delay = (index - 1) * 0.06,
                apply = function(p) row:SetAlpha(EaseOut(p)) end,
                stop = function() row:SetAlpha(1) end })
        end
    end
end

--------------------------------------------------------------------------------
-- The picker: set a goal from a search result
--------------------------------------------------------------------------------

local PICK_WIDTH = 250
local PRESETS = { 20, 40, 60, 100 }

--- Four amounts to offer, all above what you have: 20, 40, 60, 100 while
--- they are, then the next steps of 20 above it.
function GoalsUI.Presets(have)
    have = tonumber(have) or 0
    local amounts = {}
    for _, amount in ipairs(PRESETS) do
        if amount > have then amounts[#amounts + 1] = amount end
    end

    local step = (math.floor(have / 20) + 1) * 20
    while #amounts < #PRESETS do
        local taken = false
        for _, amount in ipairs(amounts) do
            if amount == step then taken = true end
        end
        if not taken then amounts[#amounts + 1] = step end
        step = step + 20
    end

    table.sort(amounts)
    return amounts
end

function GoalsUI:BuildPicker()
    if self.picker then return self.picker end

    local picker = CreateFrame("Frame", "BlackthornesFarmerGoalPicker", UIParent)
    picker:SetSize(PICK_WIDTH, 144)
    picker:SetFrameStrata("DIALOG")
    picker:SetClampedToScreen(true)
    picker:EnableMouse(true)

    Theme.Fill(picker, "panel", 0.98)
    -- The house frame's rim and corner gems, and its red close gem
    -- (UI/Titanforged.lua). Its own title stays inside: it names the item
    -- in two colours and the picker is sized to it.
    local pickerTrim
    if ns.Titanforged then
        pickerTrim = ns.Titanforged:Dress(picker, { close = function() picker:Hide() end })
    else
        Theme.Border(picker, "accent")
        local close = Widgets.CreateButton(picker, "X", function() picker:Hide() end,
            { width = 16, height = 14, danger = true })
        close:SetPoint("TOPRIGHT", -6, -6)
    end
    -- The house glow round it, flaring as it opens.
    Theme.Halo(picker, 8, 0.10)

    -- The house size grip under the bottom right corner
    -- (Widgets.CreateSizeGrip), saved as `goalPickerScale`. Let go, it
    -- goes back beside the button it opened from, at its new size.
    Widgets.ApplySize(picker, ns.db and ns.db.goalPickerScale)
    picker.sizeGrip = Widgets.CreateSizeGrip(picker, {
        name = "picker",
        below = pickerTrim and select(4, ns.Titanforged.Reach(pickerTrim)) or 0,
        get = function() return ns.db and ns.db.goalPickerScale end,
        save = function(percent) if ns.db then ns.db.goalPickerScale = percent end end,
        done = function() if picker:IsShown() then GoalsUI:PlacePicker() end end,
    })

    local title = Theme.CreateLabel(picker, "small", "accent")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetPoint("TOPRIGHT", -30, -10)
    picker.title = title

    picker.chips = {}
    for index = 1, #PRESETS do
        local chip = Widgets.CreateChip(picker, "", function(self)
            picker.amount:SetText(tostring(self.amount))
            GoalsUI:PickerSelect(self.amount)
        end)
        chip:SetWidth(40)
        chip:SetPoint("TOPLEFT", 10 + (index - 1) * 44, -28)
        picker.chips[index] = chip
    end

    -- Plain: the search box's magnifier and clear button took all but 2px
    -- of a box this narrow, and the number typed could not be seen.
    local amount = Widgets.CreateSearchBox(picker, "other", function(text)
        GoalsUI:PickerSelect(tonumber(text))
    end, function() GoalsUI:PickerSet() end, { plain = true })
    amount:SetPoint("TOPLEFT", 10 + #PRESETS * 44, -27)
    amount:SetPoint("TOPRIGHT", -10, -27)
    amount:SetHeight(20)
    if amount.editBox then
        pcall(amount.editBox.SetNumeric, amount.editBox, true)
        pcall(amount.editBox.SetMaxLetters, amount.editBox, 5)
    end
    picker.amount = amount

    local have = Theme.CreateLabel(picker, "small", "muted")
    have:SetPoint("TOPLEFT", 10, -56)
    picker.have = have

    local bank = Widgets.CreateCheckbox(picker, L["Include bank"], function(on)
        ns.Goals:SetCountsBank(on)
        GoalsUI:FillPicker()
    end, ns.Goals:CountsBank())
    bank:SetPoint("TOPLEFT", 10, -74)
    picker.bank = bank

    local set = Widgets.CreateButton(picker, L["Set goal"], function() GoalsUI:PickerSet() end,
        { width = 80, height = 22, primary = true })
    set:SetPoint("BOTTOMLEFT", 10, 10)
    picker.set = set

    local remove = Widgets.CreateButton(picker, L["Remove goal"], function()
        ns.Goals:Remove(GoalsUI.pickItem)
        ns.Print(L.Format("goal for %s removed.", Util.ColorItemOr("accent", GoalsUI.pickItem)))
        picker:Hide()
        GoalsUI:RedrawSearch()
    end, { width = 80, height = 22 })
    remove:SetPoint("BOTTOMRIGHT", -10, 10)
    picker.remove = remove

    -- Why a goal was refused, on a line of its own under Include bank: kept
    -- just above the buttons, it was drawn over the tick box's label.
    local note = Theme.CreateLabel(picker, "tiny", "warn")
    note:SetPoint("TOPLEFT", 10, -96)
    note:SetPoint("TOPRIGHT", -10, -96)
    picker.note = note

    -- Escape closes it, like the game's own windows.
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesFarmerGoalPicker")
    end

    picker:Hide()
    self.picker = picker
    return picker
end

function GoalsUI:PickerSelect(amount)
    local picker = self.picker
    GoalsUI.choice = tonumber(amount)
    for _, chip in ipairs(picker.chips) do
        chip:SetSelected(chip.amount == GoalsUI.choice)
    end
    picker.note:SetText("")
end

function GoalsUI:FillPicker()
    local picker = self.picker
    local item = GoalsUI.pickItem
    local goal = ns.Goals:Find(item)
    local have = ns.Goals:Have(item) or 0

    picker.title:SetText(L.Format("GATHERING GOAL  |c%s%s|r", Util.ItemHexOr("text", item),
        (item:upper():gsub("ä", "Ä"):gsub("ö", "Ö"):gsub("ü", "Ü"))))
    picker.have:SetText(L.Format("You have |c%s%d|r %s.", ns.COLORS.text, have,
        ns.Goals:CountsBank() and L["in your bags and bank"] or L["in your bags"]))
    picker.bank:SetChecked(ns.Goals:CountsBank())

    -- As wide as its title needs, measured: a long name in capitals ran
    -- past a fixed width and ended in "...".
    picker:SetWidth(math.min(460, math.max(PICK_WIDTH,
        Theme.TextWidth("small", Util.StripColor(picker.title:GetText())) + 42,
        Theme.TextWidth("small", Util.StripColor(picker.have:GetText())) + 22)))

    for index, amount in ipairs(GoalsUI.Presets(have)) do
        local chip = picker.chips[index]
        chip.amount = amount
        chip.label:SetText(tostring(amount))
    end

    picker.set:SetText(goal and L["Change goal"] or L["Set goal"])
    picker.remove:SetShown(goal ~= nil)

    if not GoalsUI.choice or GoalsUI.choice <= have then
        GoalsUI.choice = goal and goal.target or GoalsUI.Presets(have)[2]
    end
    picker.amount:SetText(tostring(GoalsUI.choice))
    self:PickerSelect(GoalsUI.choice)
end

-- Room between the picker and the window it opens beside: both rims, the
-- corner gems and the window's close gem reach a few pixels past their
-- frames' edges.
local PICK_GAP = 12

--- Where the picker goes: level with the button that opened it, but outside
--- the window holding that button (`GoalsUI.pickBeside`), to its right, or to its
--- left when the right has too little screen left. Opened against the
--- button itself, it covered the window's right edge and close gem.
--- Called again when that window changes size or its list redraws, so it
--- follows a resize and flips side if the right runs out of room.
function GoalsUI:PlacePicker()
    local picker = self.picker
    if not picker then return end
    local anchor, beside = GoalsUI.pickAnchor, GoalsUI.pickBeside

    -- An opening still sliding in puts its own point back when it lands, so
    -- land it first, or it would carry the picker back to where it was.
    if ns.Motion then ns.Motion:Stop(picker, "open", true) end
    picker:ClearAllPoints()
    if not anchor then
        picker:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
        return
    end

    -- Edges in screen pixels, read in a pcall: a frame not yet laid out
    -- answers nil.
    local function Edges(frame)
        if not frame then return end
        local ok, left, right, top, scale = pcall(function()
            return frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetEffectiveScale()
        end)
        left, right, top, scale = tonumber(left), tonumber(right), tonumber(top), tonumber(scale)
        if not (ok and left and right and top and scale and scale > 0) then return end
        return left * scale, right * scale, top * scale
    end

    local winLeft, winRight, winTop = Edges(beside)
    local _, _, buttonTop = Edges(anchor)
    if not (winLeft and buttonTop) then
        picker:SetPoint("TOPLEFT", anchor, "TOPRIGHT", PICK_GAP, 0)
        return
    end

    local scale = tonumber(picker:GetEffectiveScale()) or 1
    if scale <= 0 then scale = 1 end
    local _, screenRight = Edges(UIParent)
    if not screenRight then
        local ok, width = pcall(GetScreenWidth)
        screenRight = ok and tonumber(width) or nil
    end

    local width = (tonumber(picker:GetWidth()) or PICK_WIDTH) * scale
    local needs = PICK_GAP * scale + width
    local right = true
    if screenRight and winRight + needs > screenRight then
        -- No room on the right: the left if it fits there, else whichever
        -- side has more room (the screen clamp keeps it on screen).
        right = winLeft < needs and (screenRight - winRight) >= winLeft
    end

    -- Its top a little above the button's, as when it hung off the button.
    local y = (buttonTop - winTop) / scale + 8
    if right then
        picker:SetPoint("TOPLEFT", beside, "TOPRIGHT", PICK_GAP, y)
    else
        picker:SetPoint("TOPRIGHT", beside, "TOPLEFT", -PICK_GAP, y)
    end
    picker.side = right and "right" or "left"
end

--- Open the picker for `item`, beside `anchor` (the Goal button pressed),
--- outside `beside`, the window that button sits in, when given.
--- `stillThere`, when given, says whether that button still stands for the
--- item: list rows are reused as the list scrolls, so the picker closes
--- (CheckPicker) rather than sit beside a row showing something else.
function GoalsUI:OpenPicker(item, anchor, stillThere, beside)
    local picker = self:BuildPicker()
    picker.stillThere = stillThere

    if picker:IsShown() and GoalsUI.pickItem == item then
        picker:Hide()
        return
    end

    GoalsUI.pickItem = item
    GoalsUI.choice = nil
    self:FillPicker()

    GoalsUI.pickAnchor, GoalsUI.pickBeside = anchor, beside
    self:PlacePicker()
    picker:Show()
    ns.Motion:Open(picker, 4)
end

--- Close the picker once the button it opened beside shows another item
--- or has gone (the results scrolled, a new search, the window closed).
function GoalsUI:CheckPicker()
    local picker = self.picker
    if not (picker and picker:IsShown() and picker.stillThere) then return end

    local ok, here = pcall(picker.stillThere)
    if not (ok and here) then
        picker:Hide()
    elseif GoalsUI.pickBeside then
        self:PlacePicker()
    end
end

function GoalsUI:PickerSet()
    local picker = self.picker
    if not (picker and GoalsUI.pickItem) then return end

    local amount = tonumber(picker.amount:GetText()) or GoalsUI.choice
    local goal, why = ns.Goals:Set(GoalsUI.pickItem, amount)

    if not goal then
        picker.note:SetText(why and (why:sub(1, 1):upper() .. why:sub(2) .. ".") or "")
        -- Wide enough for the note too, measured.
        local wants = Theme.TextWidth("tiny", picker.note:GetText()) + 22
        if wants > (tonumber(picker:GetWidth()) or 0) then picker:SetWidth(math.min(460, wants)) end
        return
    end

    picker:Hide()
    ns.Print(L.Format("goal set: %s %s. You have %d, %d to go.",
        Util.Colored("good", tostring(goal.target)), Util.ColorItemOr("accent", goal.item),
        goal.have, ns.Goals.Left(goal)))
    self:Show()
    GoalsUI:RedrawSearch()
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

ns.RegisterCommand("goals", L["show or hide the goals panel (dock puts it back under the kills panel)"], function(rest)
    local word = Util.Trim(rest):lower()

    if word == "dock" then
        GoalsUI:Dock()
        ns.Print(L["goals panel back under the kills panel."])
        return
    end

    GoalsUI:ToggleOrHint()
end)
