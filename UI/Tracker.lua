-- Blackthornes Farmer -- UI/Tracker.lua
-- The kills and loot panel, down the left side of the screen.
--
-- A tall, narrow column under the player and party frames that fills in as
-- you farm, on two tabs (2026-09-28: showing only three items a mob
-- was "limiting"):
--
--   * Farm: a card for every mob killed this session (and every fishing spot
--     and node). The one you are on leads, open and glowing gold: its
--     all-time kills, where, a progress bar toward the 20 it takes for drop
--     rates, what a kill is worth, and everything it has dropped as bag
--     icons -- a count on each until 20 kills, its drop rate after. The rest
--     fold to one line with their loot as small icons; click a band to open
--     or fold it. The Sort button orders the rest.
--   * Loot: everything looted, fished and gathered this session in one list,
--     best earners first with medals on the top three, and where each came
--     from.
--
-- Items are drawn the way the bags draw them, icon and quality colour, both
-- remembered from the loot window by the tracker. Click an item icon for
-- that mob's whole loot table (UI/LootTable.lua). The wheel scrolls.
--
-- /farm tracker (or its X) turns it off and on, and it stays that way from one
-- session to the next. Drag it if the left edge is busy. In a party or raid it
-- steps aside from the group frames (see "In a group" at the bottom).

local ADDON, ns = ...
local L = ns.L

local TrackerUI = ns.NewModule("TrackerUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

-- The starting size. Drag the corner grip to change it; the size is saved.
local WIDTH = 260
local HEIGHT = 420

-- How small and how large the grip will let it go. The shortest is further
-- down, after the sizes it is made of.
local MIN_WIDTH, MAX_WIDTH = 180, 600
local MAX_HEIGHT = 1000
local PADDING = 8
-- The title bar: "Kills & Loot" and the X on top, the session's gathered
-- value on a second line under them.
local TITLE_LINE = 28
local TOTAL_LINE = 20
local HEADER = TITLE_LINE + TOTAL_LINE
TrackerUI.HEADER = HEADER
-- The Farm and Loot tabs under it, then the toolbar with the Sort button.
local TAB_HEIGHT = 22
local TOOLBAR = 22
-- The toolbar's Clear button, beside Sort.
local CLEAR_WIDTH = 44
local TOP = HEADER + TAB_HEIGHT + TOOLBAR
TrackerUI.TOP = TOP
local LINE = 18
local ICON = 14
local BAR = 40
TrackerUI.BAR = BAR

-- The progress bar toward rates (2026-09-27: "a progress bar like
-- the goals"): as tall as a goal's, never shorter than MIN_PROGRESS.
local PROGRESS_HEIGHT = 7
local MIN_PROGRESS = 60
local BRIGHT_GOLD = { 1, 0.906, 0.639 }
local GREEN_TIP = { 0.66, 1, 0.77 }

-- Marks on the bar, and the last stretch that turns it green: a goal's.
local MARKS = { 0.25, 0.5, 0.75 }
local FINAL = 0.1

-- How bright the glow round the panel rests: lower than a window's, as this
-- one is on screen the whole time you farm. It flares as the panel comes
-- into view and as rates unlock (UI/TrackerFX.lua).
local HALO_REST = 0.08

-- The glow round the card you are on.
local LIVE_HALO = 0.22
-- While see-through, the open card keeps at least this much of its gold glass.
local LIVE_GLASS_FLOOR = 0.6

-- Right-hand value and the green badge beside it, in pixels.
local RIGHT_WIDTH = 54
local BADGE_WIDTH = 28

-- A kill streak shows once it reaches this many.
local STREAK_SHOWN = 3

-- An open card's loot, as bag slots, and a folded card's as small icons.
local SLOT = 30
local SLOT_GAP = 4
local MINI = 12
local MINIS = 6
TrackerUI.SLOT = SLOT

-- The shortest the grip goes: the header, and room under it for one row of
-- an open card's loot icons (see LineHeight). A shorter panel could not hold
-- that row, and was drawn taller than the height you set to fit it.
local MIN_HEIGHT = TOP + PADDING * 2 + SLOT + SLOT_GAP + 6

-- A Loot tab row: two lines, its icon, and the rank's medal.
local LOOT_ROW = 32
local LOOT_ICON = 22
local MEDAL = 14
-- How many sources an item names before "+2 more".
local SOURCES_SHOWN = 2

-- The Rankings tab's medals: gold, silver, bronze.
local MEDALS = {
    { 1.00, 0.82, 0.30 },
    { 0.78, 0.80, 0.84 },
    { 0.80, 0.52, 0.30 },
}

-- Lines the wheel moves at a time.
local SCROLL_STEP = 2

-- The strip under the lines that says "12 more below" while some are out of
-- sight. It comes out of the same height as the lines.
local MORE_HEIGHT = 10

-- Per hour shows once the session has run this long, in seconds; before
-- that one lucky drop would say you earn a fortune.
local PER_HOUR_AFTER = 300

-- Bumped when the default position moves, so a panel saved at the old spot
-- comes to the new one once instead of staying where nobody asked for it.
local LAYOUT = 2

local FALLBACK_ICON = [[Interface\Icons\INV_Misc_QuestionMark]]
local PLACE_ICON = [[Interface\Icons\INV_Misc_Map_01]]
-- The crown after a mob's name once you have killed Tracker.CHAMPION_KILLS
-- of it (2026-10-13): the game's party leader crown, sized to the text.
local CROWN = [[|TInterface\GroupFrame\UI-Group-LeaderIcon:0|t]]
TrackerUI.CROWN = CROWN
-- From the 1000th kill the crown is tinted legendary orange and the name
-- is drawn in it.
local LEGENDARY_CROWN = [[|TInterface\GroupFrame\UI-Group-LeaderIcon:0:0:0:0:16:16:0:16:0:16:255:150:40|t]]
TrackerUI.LEGENDARY_CROWN = LEGENDARY_CROWN
local LEGENDARY = "ffff8000"
-- On the way (2026-10-15): from 250 kills a laurel branch each side of the
-- crown, silver, gold from 500; from 750 the crown warms toward orange; at
-- 1000 the laurel turns legendary with it. Our own art, tinted here.
local LAUREL_ART = ([[Interface\AddOns\%s\Media\Frame\Laurel]]):format(ADDON or "Blackthornes_Farmer")
local function LaurelSide(left, r, g, b)
    return ("|T%s:0:0:0:0:128:64:%d:%d:0:64:%d:%d:%d|t"):format(LAUREL_ART,
        left and 0 or 64, left and 64 or 128, r, g, b)
end
local SILVER = { 205, 215, 230 }
local GOLD = { 255, 205, 70 }
local ORANGE = { 255, 150, 40 }
local WARM_CROWN = [[|TInterface\GroupFrame\UI-Group-LeaderIcon:0:0:0:0:16:16:0:16:0:16:255:200:110|t]]
TrackerUI.WARM_CROWN = WARM_CROWN

--- The crown and laurel after a mob's name for `kills` of it, and whether
--- the name is drawn in legendary orange. Nil below the 100th.
function TrackerUI.MarkFor(kills)
    kills = tonumber(kills) or 0
    local T = ns.Tracker
    if kills < T.CHAMPION_KILLS then return nil end
    if kills < T.LAUREL_KILLS then return CROWN end

    local tint, crown, legendary = SILVER, CROWN, false
    if kills >= T.BANE_KILLS then
        tint, crown, legendary = ORANGE, LEGENDARY_CROWN, true
    elseif kills >= T.FEAR_KILLS then
        tint, crown = GOLD, WARM_CROWN
    elseif kills >= T.SLAYER_KILLS then
        tint = GOLD
    end
    return LaurelSide(true, tint[1], tint[2], tint[3]) .. crown
        .. LaurelSide(false, tint[1], tint[2], tint[3]), legendary
end

--- A rate worth staying for should look different from one that is not.
local function RateColor(chance)
    if chance >= 40 then return "good" end
    if chance >= 15 then return "accent" end
    return "muted"
end

--- A "ffrrggbb" colour as the four numbers SetTextColor takes.
local function HexColor(hex)
    if type(hex) ~= "string" or #hex ~= 8 then return nil end

    local r = tonumber(hex:sub(3, 4), 16)
    local g = tonumber(hex:sub(5, 6), 16)
    local b = tonumber(hex:sub(7, 8), 16)
    if not (r and g and b) then return nil end

    return r / 255, g / 255, b / 255, 1
end

--------------------------------------------------------------------------------
-- Size
--
-- The width is exactly what you drag it to. The height you drag to is the
-- tallest it grows: a short session still gets a short panel, and a long one
-- fills down to where you put the bottom edge and says what did not fit.
--------------------------------------------------------------------------------

local function Clamp(value, low, high)
    value = tonumber(value)
    if not value then return nil end
    return math.max(low, math.min(high, value))
end

function TrackerUI:Width()
    return Clamp(ns.db and ns.db.trackerWidth, MIN_WIDTH, MAX_WIDTH) or WIDTH
end

--- The panel's width for lines that need `needs` pixels: the saved width, or
--- wider up to MAX_WIDTH.
function TrackerUI:FitWidth(needs)
    return math.min(MAX_WIDTH, math.max(self:Width(), math.ceil(tonumber(needs) or 0)))
end

function TrackerUI:MaxHeight()
    return Clamp(ns.db and ns.db.trackerHeight, MIN_HEIGHT, MAX_HEIGHT) or HEIGHT
end

--- How many lines fit under the header at a given height.
function TrackerUI:LinesFor(height)
    return math.max(2, math.floor((height - HEADER - PADDING * 2) / LINE))
end

--- Row `index`, made the first time it is needed.
function TrackerUI:Line(index)
    local row = self.lines[index]
    if not row then
        row = self:CreateLine(self.frame, index)
        self.lines[index] = row
    end
    return row
end

--- The panel's size on screen, in whole pixels.
function TrackerUI:SizeNow()
    return { width = math.floor((tonumber(self.frame:GetWidth()) or 0) + 0.5),
        height = math.floor((tonumber(self.frame:GetHeight()) or 0) + 0.5) }
end

--- Save the size on screen. `from` is the size when the grip was pressed,
--- and a side the drag left alone keeps what was saved: the panel is drawn
--- shorter than its saved height while there is less to show, so saving
--- what was on screen made a click on the grip, or a drag only to widen it,
--- the panel's new height for good.
function TrackerUI:SaveSize(from)
    if not (ns.db and self.frame) then return end

    local now = self:SizeNow()
    if not (from and from.width == now.width) then ns.db.trackerWidth = now.width end
    if not (from and from.height == now.height) then ns.db.trackerHeight = now.height end
end

--- The corner grip. Drag it and the panel follows; let go and it keeps that.
function TrackerUI:BuildGrip(frame)
    frame:SetResizable(true)

    -- Retail spells the limits one way and older clients another; try both,
    -- and let neither's absence stop the panel from building.
    if not pcall(frame.SetResizeBounds, frame, MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT) then
        pcall(frame.SetMinResize, frame, MIN_WIDTH, MIN_HEIGHT)
        pcall(frame.SetMaxResize, frame, MAX_WIDTH, MAX_HEIGHT)
    end

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(frame:GetFrameLevel() + 5)
    grip:EnableMouse(true)

    pcall(grip.SetNormalTexture, grip, [[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up]])
    pcall(grip.SetHighlightTexture, grip, [[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Highlight]])
    pcall(grip.SetPushedTexture, grip, [[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Down]])

    grip:SetScript("OnMouseDown", function()
        grip.held = true
        TrackerUI.sizing = true
        -- Pin the top first, so the panel grows downward from where it is.
        TrackerUI:AnchorTop()
        -- Start from the size on screen, so the corner stays under the
        -- cursor. Changing the height here would move the corner away from
        -- the mouse, and the drag would keep that gap the whole way.
        TrackerUI.sizeFrom = TrackerUI:SizeNow()
        frame:StartSizing("BOTTOMRIGHT")
    end)

    -- Let go, or the panel hid mid-drag (Alt-Z, a macro): either way the
    -- drag ends, or `sizing` stuck on kept the panel from fitting itself
    -- or following the group frames again.
    local function StopSizing()
        if not rawget(grip, "held") then return end
        grip.held = nil
        frame:StopMovingOrSizing()
        TrackerUI.sizing = false
        TrackerUI.tabNeeds = nil
        TrackerUI:AnchorTop()
        TrackerUI:SaveSize(TrackerUI.sizeFrom)
        TrackerUI.sizeFrom = nil
        -- Resizing is not picking a spot; in a group it stays beside the
        -- group frames rather than being pinned where it happens to be.
        if not TrackerUI.grouped then TrackerUI:SavePosition() end
        TrackerUI:Render()
        -- A docked goals panel takes the new width now, not at the next loot.
        TrackerUI:FollowGoals()
    end
    grip:SetScript("OnMouseUp", StopSizing)
    grip:SetScript("OnHide", StopSizing)

    -- Redraw while dragging, so you see what fits as you go.
    frame:SetScript("OnSizeChanged", function()
        if TrackerUI.sizing then TrackerUI:Arrange() end
    end)

    self.grip = grip
end

--------------------------------------------------------------------------------
-- Size
--
-- How big the whole panel is drawn, text and all, apart from how much of it
-- shows (the corner grip above): the gold grip beside its bottom right
-- corner, the Kill tally size row in Settings, or /farm tracker size (the
-- owner asked 2026-10-07, after Tradeskills' window got the same). Saved in
-- percent as `trackerScale`, the key the Settings row has always used.
--------------------------------------------------------------------------------

local SCALE_MIN, SCALE_MAX = 50, 150
TrackerUI.SCALE_MIN, TrackerUI.SCALE_MAX = SCALE_MIN, SCALE_MAX
TrackerUI.SIZES = {
    { key = "small", text = L["Small"], percent = 80 },
    { key = "normal", text = L["Normal"], percent = 100 },
    { key = "large", text = L["Large"], percent = 120 },
}
local SIZE_GRIP = 20

--- A frame's own scale, or 1 when it cannot say.
local function ScaleOf(frame)
    local ok, scale = pcall(function() return frame:GetScale() end)
    if ok and type(scale) == "number" and scale > 0 then return scale end
    return 1
end

--- A size in percent, kept within bounds and whole.
function TrackerUI.ClampPercent(value)
    value = tonumber(value)
    if not value or value ~= value then return 100 end
    return math.floor(math.max(SCALE_MIN, math.min(SCALE_MAX, value)) + 0.5)
end

--- "small", "normal", "large", "80", "80%" or "0.8" as a percent, or nil.
function TrackerUI.ParseSize(text)
    text = (text or ""):lower():gsub("%s", ""):gsub("%%$", "")
    if text == "" then return nil end
    for _, size in ipairs(TrackerUI.SIZES) do
        if size.key == text then return size.percent end
    end
    local number = tonumber(text)
    if not number or number <= 0 then return nil end
    -- 0.8 means 80%, as 80 does.
    if number <= 5 then number = number * 100 end
    return number
end

--- The name of a size, "Small (80%)", or "87%" for one dragged to.
function TrackerUI.ScaleText(percent)
    percent = math.floor((tonumber(percent) or 100) + 0.5)
    for _, size in ipairs(TrackerUI.SIZES) do
        if size.percent == percent then return ("%s (%d%%)"):format(size.text, percent) end
    end
    return ("%d%%"):format(percent)
end

--- The largest size, in percent, at which the panel as it is now fits on
--- the screen. Never under 100: a panel taller than the screen at its normal
--- size was drawn that way before there were sizes, and still is.
function TrackerUI:FitPercent()
    local ok, width, height = pcall(function() return UIParent:GetWidth(), UIParent:GetHeight() end)
    if not (ok and type(width) == "number" and type(height) == "number"
        and width > 0 and height > 0) then
        return SCALE_MAX
    end

    local wide, tall = self:Width(), MIN_HEIGHT
    if self.frame then
        local okSize, w, h = pcall(function() return self.frame:GetWidth(), self.frame:GetHeight() end)
        if okSize and type(w) == "number" and w > 0 then wide = w end
        if okSize and type(h) == "number" and h > tall then tall = h end
    end

    -- Room for the glow round it and the grip beside it.
    local fit = math.min(width / (wide + SIZE_GRIP + 16), height / (tall + 16))
    return math.max(100, math.min(SCALE_MAX, math.floor(fit * 100)))
end

--- The size the panel is drawn at, in percent: the saved one, kept on the
--- screen.
function TrackerUI:DrawnPercent()
    return math.min(TrackerUI.ClampPercent(ns.db and ns.db.trackerScale or 100), self:FitPercent())
end

--- Save a size and draw the panel at it, staying where it is on screen.
--- Returns the percent it is drawn at.
function TrackerUI:SetScalePercent(value)
    if not ns.db then return 100 end
    local previous = self:DrawnPercent()
    ns.db.trackerScale = TrackerUI.ClampPercent(value)

    if ns.SettingsUI and ns.SettingsUI.ApplyTrackerScale then
        ns.SettingsUI:ApplyTrackerScale(previous)
        if ns.SettingsUI.Refresh then ns.SettingsUI:Refresh() end
    elseif self.frame then
        self.frame:SetScale(self:DrawnPercent() / 100)
    end
    return self:DrawnPercent()
end

--- The gold grip beside the bottom right corner: drag it and the whole panel
--- grows or shrinks from its top left corner; right-click it for Normal. It
--- hangs outside, to the right, as the goals panel docks underneath.
function TrackerUI:BuildSizeGrip(frame)
    local grip = Theme.CreatePanel(frame, "panel", "borderLit")
    grip:SetSize(SIZE_GRIP, SIZE_GRIP)
    grip:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 3, 0)
    grip:SetFrameLevel((frame:GetFrameLevel() or 0) + 20)
    grip:EnableMouse(true)
    Theme.TopSheen(grip)
    self.sizeGrip = grip

    -- Six gold dots in a stair down to the bottom right corner, the shape
    -- every resizable window in the game wears, drawn from plain colour.
    local dots = {}
    for row = 0, 2 do
        for column = 2 - row, 2 do
            local dot = grip:CreateTexture(nil, "ARTWORK")
            dot:SetSize(3, 3)
            dot:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -3 - (2 - column) * 5, 3 + (2 - row) * 5)
            dot:SetColorTexture(Theme.Unpack("accent"))
            dots[#dots + 1] = dot
        end
    end

    local function Light(on)
        Theme.SetBorderColor(grip, on and "accent" or "borderLit")
        for _, dot in ipairs(dots) do
            dot:SetColorTexture(Theme.Unpack(on and "accentHi" or "accent"))
        end
    end

    local function Track(self)
        local cx, cy = GetCursorPosition()
        local uiScale = UIParent:GetEffectiveScale()
        if not (cx and cy and type(uiScale) == "number" and uiScale > 0) then return end
        cx, cy = cx / uiScale, cy / uiScale

        -- Where the corner would be for the cursor to sit on the grip as it
        -- did when the drag began, then the size that puts it there: the
        -- width's and the height's answers averaged, so a drag off the
        -- diagonal still feels right.
        local width = cx - self.grabX - self.anchorLeft
        local height = self.anchorTop - (cy + self.grabY)
        local percent = TrackerUI.ClampPercent((width / self.wide + height / self.tall) / 2 * 100)
        percent = math.min(percent, self.fit)
        local scale = percent / 100
        if math.abs(scale - ScaleOf(frame)) < 0.005 then return end

        frame:SetScale(scale)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", self.anchorLeft / scale, self.anchorTop / scale)

        if GameTooltip:IsOwned(self) then
            GameTooltip:SetText(TrackerUI.ScaleText(percent), Theme.Unpack("accentHi"))
            GameTooltip:Show()
        end
    end

    local function StopSizing(self)
        if not self.sizing then return end
        self.sizing = false
        TrackerUI.sizing = false
        self:SetScript("OnUpdate", nil)

        -- The saved spots were taken at the size the drag began at; Settings'
        -- path converts them, so the panel lands where the drag left it.
        local now = math.floor(ScaleOf(frame) * 100 + 0.5)
        frame:SetScale(self.from / 100)
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", self.anchorLeft * 100 / self.from,
            self.anchorTop * 100 / self.from)
        TrackerUI:SetScalePercent(now)
        TrackerUI:Render()
    end

    grip:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            TrackerUI:SetScalePercent(100)
            return
        end
        if button ~= "LeftButton" then return end

        if ns.Motion and ns.Motion.Stop then pcall(ns.Motion.Stop, ns.Motion, frame, "open", true) end

        local scale = ScaleOf(frame)
        local ok, left, top, wide, tall = pcall(function()
            return frame:GetLeft(), frame:GetTop(), frame:GetWidth(), frame:GetHeight()
        end)
        local cx, cy = GetCursorPosition()
        local uiScale = UIParent:GetEffectiveScale()
        if not (ok and type(left) == "number" and type(top) == "number"
            and type(wide) == "number" and wide > 0 and type(tall) == "number" and tall > 0
            and cx and cy and type(uiScale) == "number" and uiScale > 0) then
            return
        end

        -- All in the screen's units, which do not change with the panel's.
        self.wide, self.tall = wide, tall
        self.anchorLeft, self.anchorTop = left * scale, top * scale
        self.grabX = cx / uiScale - (self.anchorLeft + wide * scale)
        self.grabY = (self.anchorTop - tall * scale) - cy / uiScale
        self.fit = TrackerUI:FitPercent()
        self.from = math.floor(scale * 100 + 0.5)

        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)

        -- Not pulled back beside the group frames mid-drag.
        TrackerUI.sizing = true
        self.sizing = true
        self:SetScript("OnUpdate", Track)
    end)
    grip:SetScript("OnMouseUp", StopSizing)
    grip:SetScript("OnHide", StopSizing)

    grip:SetScript("OnEnter", function(self)
        Light(true)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(TrackerUI.ScaleText(ScaleOf(frame) * 100), Theme.Unpack("accentHi"))
        GameTooltip:AddLine(L["Drag to make the panel bigger or smaller."], 1, 1, 1, true)
        GameTooltip:AddLine(L["Right-click to go back to the normal size."], 1, 1, 1, true)
        GameTooltip:AddLine(L["The grip inside the corner shows more or less of it."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function()
        Light(false)
        GameTooltip:Hide()
    end)

    return grip
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local TABS = {
    { key = "farm", label = L["Farm"] },
    { key = "loot", label = L["Loot"] },
}

-- What each tab's Sort button steps through, first the default.
local SORTS = {
    farm = { { key = "recent", label = L["Recent"] }, { key = "worth", label = L["Worth per kill"] },
        { key = "kills", label = L["Kills"] }, { key = "value", label = L["Loot value"] } },
    loot = { { key = "value", label = L["Value"] }, { key = "count", label = L["Count"] },
        { key = "name", label = L["Name"] } },
}
TrackerUI.SORTS = SORTS

--- The tab showing: "farm" or "loot".
function TrackerUI:Tab()
    local tab = ns.db and ns.db.trackerTab
    return tab == "loot" and "loot" or "farm"
end

--- The Sort button's choice on `tab`, one of SORTS[tab]'s keys.
function TrackerUI:Sort(tab)
    tab = tab or self:Tab()
    local saved = ns.db and ns.db[tab == "loot" and "trackerLootSort" or "trackerSort"]
    for _, sort in ipairs(SORTS[tab]) do
        if sort.key == saved then return sort.key, sort.label end
    end
    return SORTS[tab][1].key, SORTS[tab][1].label
end

function TrackerUI:SetTab(tab)
    if not ns.db or tab == self:Tab() then return end
    ns.db.trackerTab = tab
    self.scroll = 0
    -- What the new tab shows was not just gained: take note, play nothing.
    if ns.TrackerFX and ns.TrackerFX.Rebase then ns.TrackerFX:Rebase() end
    self:Refresh()
end

--- Sort the tab showing by `key`, one of SORTS[tab]'s keys.
function TrackerUI:SetSort(key)
    local tab = self:Tab()
    if not ns.db then return end
    ns.db[tab == "loot" and "trackerLootSort" or "trackerSort"] = key
    self.scroll = 0
    if ns.TrackerFX and ns.TrackerFX.Rebase then ns.TrackerFX:Rebase() end
    self:Refresh()
end

--- The Sort drop-down's lines (the owner's rule of 2026-10-23: word choices
--- are drop-downs): every order for the tab showing, the one in use ticked.
function TrackerUI:SortLines()
    local tab = self:Tab()
    local current = self:Sort(tab)
    local lines = {}
    for _, sort in ipairs(SORTS[tab]) do
        local key = sort.key
        lines[#lines + 1] = { text = sort.label, checked = key == current,
            run = function() TrackerUI:SetSort(key) end }
    end
    return lines
end

--- Open the Sort drop-down under its button (UI/RowMenu.lua).
function TrackerUI:OpenSort()
    if ns.RowMenu then ns.RowMenu:Open(self:SortLines(), { title = L["Sort"] }) end
end

--- The next way of sorting the tab showing.
function TrackerUI:NextSort()
    local tab = self:Tab()
    local current = self:Sort(tab)
    local list = SORTS[tab]
    local nextKey = list[1].key

    for index, sort in ipairs(list) do
        if sort.key == current then nextKey = list[index % #list + 1].key end
    end

    ns.db[tab == "loot" and "trackerLootSort" or "trackerSort"] = nextKey
    self.scroll = 0
    if ns.TrackerFX and ns.TrackerFX.Rebase then ns.TrackerFX:Rebase() end
    self:Refresh()
end

--- Whether a card is open. The one you are on is open unless you folded it;
--- the rest are folded unless you opened them (2026-09-28).
function TrackerUI:IsOpen(key, default)
    local chosen = self.open and self.open[key]
    if chosen ~= nil then return chosen end
    return default and true or false
end

function TrackerUI:Toggle(key, default)
    self.open = self.open or {}
    self.open[key] = not self:IsOpen(key, default)
    if ns.TrackerFX and ns.TrackerFX.Rebase then ns.TrackerFX:Rebase() end
    self:Refresh()
end

function TrackerUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesFarmerTracker", UIParent)
    frame:SetSize(self:Width(), self:MaxHeight())
    frame:SetFrameStrata("LOW")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    local back = Theme.Fill(frame, "window", 0.88)
    Theme.Border(frame, "border")
    -- The house glow round its edge, as the windows have.
    Theme.Halo(frame, 8, HALO_REST)

    frame:SetScript("OnDragStart", function(self)
        TrackerUI.dragging = true
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        TrackerUI.dragging = false
        TrackerUI:AnchorTop()
        TrackerUI:SavePosition()
        -- Dropped over a loose goals panel, it hangs under (UI/PanelSnap.lua).
        if ns.PanelSnap then ns.PanelSnap:TrackerDropped() end
    end)

    -- The wheel scrolls the column rather than cutting it off.
    pcall(frame.EnableMouseWheel, frame, true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        TrackerUI:ScrollBy(-(tonumber(delta) or 0) * SCROLL_STEP)
    end)

    -- Title bar: the house header, with an accent stripe down its left edge
    -- so the panel reads as part of the same set as the search window.
    local header = Theme.CreatePanel(frame, "header", false)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER)

    Theme.HouseHeader(header)

    local title = Theme.CreateLabel(header, "normal", "accent")
    title:SetPoint("LEFT", header, "TOPLEFT", PADDING + 4, -TITLE_LINE / 2)
    title:SetText(L["Kills & Loot"])

    -- The house panel header (2026-10-29): the fold gem left of the close
    -- gem. Folded, the panel keeps its title bar only (session only).
    local gems = Widgets.CreatePanelGems(header, {
        onFold = function(folded) TrackerUI:SetFolded(folded) end,
        onClose = function()
            ns.db.trackerHidden = true
            TrackerUI:Refresh()
            -- An open Settings page shows the panel's switch: keep it in step,
            -- as /farm tracker off does.
            if ns.SettingsUI and ns.SettingsUI.Refresh then ns.SettingsUI:Refresh() end
            ns.Print(L["kill and loot panel hidden. /farm tracker brings it back."])
        end,
    })
    local close = gems.close
    close:ClearAllPoints()
    close:SetPoint("RIGHT", header, "TOPRIGHT", -6, -TITLE_LINE / 2)
    self.gems = gems

    -- The session's gathered value on the title bar's second line
    -- (2026-09-27). Built like a line row so the count-up, glow and "+38s" in
    -- UI/TrackerFX.lua work on it unchanged.
    local total = CreateFrame("Frame", nil, header)
    total:SetPoint("TOPLEFT", header, "TOPLEFT", 3, -TITLE_LINE + 2)
    total:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 2)

    -- Its name is on the hover, not under the title (2026-10-29).
    total.left = Theme.CreateLabel(total, "small", "muted")
    total.left:SetPoint("LEFT", PADDING + 1, 0)
    total.left:SetText("")
    pcall(total.EnableMouse, total, true)
    total:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["Gathered value"])
        GameTooltip:Show()
    end)
    total:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    -- A drag on it still moves the panel.
    pcall(total.RegisterForDrag, total, "LeftButton")
    total:SetScript("OnDragStart", function() local f = frame:GetScript("OnDragStart"); if f then f(frame) end end)
    total:SetScript("OnDragStop", function() local f = frame:GetScript("OnDragStop"); if f then f(frame) end end)

    total.right = Theme.CreateLabel(total, "normal", "good", "RIGHT")
    total.right:SetPoint("RIGHT", -PADDING, 0)

    total.badge = Theme.CreateLabel(total, "tiny", "good", "RIGHT")
    total.badge:SetPoint("RIGHT", total.right, "LEFT", -4, 0)

    self.frame = frame
    self.glassParts = self.glassParts or {}
    self:AddGlass(back)
    self:AddGlass(header.background)
    self.title = title
    self.titleRow = total
    self.header = header
    self.closeButton = close
    -- The Open button (UI/OpenButton.lua) sits left of the fold gem.
    self.openAnchor = gems.fold
    self.lines = {}
    self.cards = {}
    self.scroll = self.scroll or 0

    self:BuildTabs(frame)
    self:BuildToolbar(frame)

    local rule = Theme.CreateDivider(frame, "borderLit")
    rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -TOP)
    rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -TOP)
    self.rule = rule

    -- "12 more below" at the bottom edge while the column scrolls.
    local more = Theme.CreateLabel(frame, "tiny", "muted", "RIGHT")
    more:SetPoint("BOTTOMRIGHT", -20, 4)
    more:Hide()
    self.moreLabel = more

    -- While the column scrolls, its cut edges fade into the panel rather
    -- than stopping hard, so it reads as more above or below.
    self.fadeTop = self:BuildFade(frame, "TOP")
    self.fadeBottom = self:BuildFade(frame, "BOTTOM")

    self:BuildGrip(frame)
    self:BuildSizeGrip(frame)
    self:BuildSeeThrough(frame)

    self:RestorePosition()
    frame:Hide()

    return frame
end

--- A soft fade over one cut edge of the column, above the rows.
function TrackerUI:BuildFade(frame, side)
    local fade = Widgets.CreateFade(frame, side, "window", 16)
    if not fade then return nil end
    if side == "TOP" then
        fade:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -(TOP + 1))
        fade:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -(TOP + 1))
    else
        fade:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 14)
        fade:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 14)
    end
    return fade
end

--------------------------------------------------------------------------------
-- See-through
--------------------------------------------------------------------------------

-- The owner said build it (2026-10-16, from a mockup in
-- previews/kills-loot-transparent/): the panel's dark glass thins out so the
-- world shows through, every word gets a black shadow so it reads over a
-- busy scene, and the glass comes back while the mouse is on the panel.
-- "See-Through:" on the Kill tally page (`trackerSeeThrough`, account wide,
-- off unless ticked, never rename it) and how much glass stays
-- (`trackerSeeThroughLevel`, an index into SEE_THROUGH_LEVELS, never rename
-- it); `/farm tracker seethrough [on|off|some|more|most]`. Only the panel's own textures are
-- faded (texture SetAlpha, which multiplies the colour each redraw sets), so
-- no game frame is touched. Gold edges, icons, bars and glows stay as they are.

--- How much of each piece of glass stays, by level: Some, More, Most clear.
TrackerUI.SEE_THROUGH_LEVELS = { 0.5, 0.3, 0.15 }
-- What the glass blend belongs to, so it never stops another of the panel's.
local GLASS = {}
--- How often the mouse is looked for while see-through, in seconds.
TrackerUI.SEE_THROUGH_LOOK = 0.1
--- How long the glass takes to come back or go, in seconds.
TrackerUI.SEE_THROUGH_FADE = 0.2

function TrackerUI:SeeThroughOn()
    return ns.db ~= nil and ns.db.trackerSeeThrough == true
end

function TrackerUI:SeeThroughLevel()
    local level = ns.db and tonumber(ns.db.trackerSeeThroughLevel)
    if not level or not TrackerUI.SEE_THROUGH_LEVELS[level] then return 2 end
    return level
end

--- Keep a piece of the panel's glass, to thin out while see-through.
--- `floor` is the least of it that ever stays (the open card's gold).
function TrackerUI:AddGlass(texture, floor)
    if not texture then return end
    self.glassParts = self.glassParts or {}
    self.glassParts[#self.glassParts + 1] = { texture = texture, floor = floor or 0 }
    -- A line made while the panel is see-through starts that way.
    if self.glassShown and self.glassShown < 1 then
        pcall(texture.SetAlpha, texture, math.max(self.glassShown, floor or 0))
    end
end

--- Every piece of glass at `shown` (1 is the usual dark glass).
function TrackerUI:SetGlass(shown)
    self.glassShown = shown
    for _, part in ipairs(self.glassParts or {}) do
        pcall(part.texture.SetAlpha, part.texture, math.max(shown, part.floor))
    end
end

--- A black shadow under every word on the panel while see-through, so it
--- reads over grass, snow or fire; none otherwise, as the labels are made.
local function ShadeText(region, on)
    if type(region) ~= "table" or type(region.GetObjectType) ~= "function" then return end
    local ok, kind = pcall(region.GetObjectType, region)
    if not ok or kind ~= "FontString" then return end
    if on then
        pcall(region.SetShadowColor, region, 0, 0, 0, 1)
        pcall(region.SetShadowOffset, region, 1, -1)
    else
        pcall(region.SetShadowOffset, region, 0, 0)
    end
end

local function ShadeAll(frame, on)
    if type(frame) ~= "table" then return end
    if type(frame.GetRegions) == "function" then
        local regions = { pcall(frame.GetRegions, frame) }
        for i = 2, #regions do ShadeText(regions[i], on) end
    end
    if type(frame.GetChildren) == "function" then
        local children = { pcall(frame.GetChildren, frame) }
        for i = 2, #children do ShadeAll(children[i], on) end
    end
end
TrackerUI.ShadeAll = ShadeAll

--- The watcher that brings the glass back under the mouse. It only runs
--- while the panel shows and is see-through.
function TrackerUI:BuildSeeThrough(frame)
    local watch = CreateFrame("Frame", nil, frame)
    watch.wait = 0
    self.seeThroughWatch = watch
    ns.Motion:SetValue(GLASS, "seeThrough", 1)
    self:ApplySeeThrough()
end

function TrackerUI:MouseOnPanel()
    local frame = self.frame
    if not frame or type(frame.IsMouseOver) ~= "function" then return false end
    local ok, over = pcall(frame.IsMouseOver, frame)
    return ok and over == true
end

--- Blend the glass toward solid (mouse on the panel) or see-through.
function TrackerUI:FadeGlass(solid)
    local keep = TrackerUI.SEE_THROUGH_LEVELS[self:SeeThroughLevel()]
    local target = solid and 1 or keep
    self.glassSolid = solid
    ns.Motion:Blend(GLASS, "seeThrough", target, TrackerUI.SEE_THROUGH_FADE,
        function(value) TrackerUI:SetGlass(value) end)
end

--- Put the panel in step with the setting: the glass, the shadows under
--- the words, the fades at the cut edges and the mouse watcher.
function TrackerUI:ApplySeeThrough()
    local frame, watch = self.frame, self.seeThroughWatch
    if not frame or not watch then return end
    local on = self:SeeThroughOn()

    ShadeAll(frame, on)
    if on then
        self:FadeGlass(self:MouseOnPanel())
        watch:SetScript("OnUpdate", function(w, elapsed)
            w.wait = w.wait - (tonumber(elapsed) or 0)
            if w.wait > 0 then return end
            w.wait = TrackerUI.SEE_THROUGH_LOOK
            local over = TrackerUI:MouseOnPanel()
            if over ~= TrackerUI.glassSolid then TrackerUI:FadeGlass(over) end
        end)
        if self.fadeTop then self.fadeTop:Hide() end
        if self.fadeBottom then self.fadeBottom:Hide() end
    else
        watch:SetScript("OnUpdate", nil)
        self.glassSolid = nil
        ns.Motion:Stop(GLASS, "seeThrough")
        ns.Motion:SetValue(GLASS, "seeThrough", 1)
        self:SetGlass(1)
    end
end

--- Turn see-through on or off, and redraw so the cut-edge fades follow.
function TrackerUI:SetSeeThrough(on)
    ns.db.trackerSeeThrough = on == true
    self:ApplySeeThrough()
    if self.frame and self.frame:IsShown() then self:Refresh() end
end

--- Pick how much glass stays, 1 to #SEE_THROUGH_LEVELS.
function TrackerUI:SetSeeThroughLevel(level)
    level = tonumber(level)
    if not level or not TrackerUI.SEE_THROUGH_LEVELS[level] then return end
    ns.db.trackerSeeThroughLevel = level
    if self:SeeThroughOn() then self:FadeGlass(self:MouseOnPanel()) end
end

--- How lit a tab is under the mouse, 0 to 1: its wash, and its name from
--- muted toward white. The tab showing keeps its gold name.
local function TabHover(tab, p)
    tab.hover:SetAlpha(p)
    if tab.key ~= TrackerUI:Tab() then
        tab.label:SetTextColor(ns.Motion.Mix("accent", "accentHi", p))
    end
end

--- The Farm and Loot tabs under the title bar: a gold line under the one
--- showing that slides to the other when you pick it, and a green dot on
--- the other when something new lands there.
function TrackerUI:BuildTabs(frame)
    local strip = CreateFrame("Frame", nil, frame)
    strip:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -HEADER)
    strip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -HEADER)
    strip:SetHeight(TAB_HEIGHT)
    self:AddGlass(Theme.Fill(strip, "header", 0.7))

    self.tabs = {}

    for index, spec in ipairs(TABS) do
        local tab = CreateFrame("Button", nil, strip)
        tab:SetHeight(TAB_HEIGHT)
        tab.key = spec.key
        tab.index = index

        -- The house's small view tabs (UI/HouseKit.lua, 2026-10-29): dark
        -- gold metal, the one showing dark glass with a bright gold top edge.
        tab.metal = Theme.Fill(tab, "metal", 0.55, "BACKGROUND")
        self:AddGlass(tab.metal)
        pcall(Theme.Border, tab, "metal", 0.8)
        tab.edge = tab:CreateTexture(nil, "ARTWORK")
        tab.edge:SetPoint("TOPLEFT")
        tab.edge:SetPoint("TOPRIGHT")
        tab.edge:SetHeight(2)
        tab.edge:SetColorTexture(Theme.Unpack("accentHi"))
        tab.edge:Hide()

        -- Under the mouse a tab lifts, easing in and out (TabHover). Hidden
        -- with SetAlpha rather than Hide, so the blend can set it.
        tab.hover = Theme.Fill(tab, "rowHover", 0.5, "BORDER")
        tab.hover:SetAlpha(0)

        -- The tab showing sits in a soft gold light rising from its line.
        tab.lit = tab:CreateTexture(nil, "BORDER", nil, 1)
        tab.lit:SetAllPoints(tab)
        Theme.SetGradientAlpha(tab.lit, "VERTICAL", "accent", 0.14, 0)
        tab.lit:Hide()

        tab.label = Theme.CreateLabel(tab, "small", "accent", "CENTER")
        tab.label:SetPoint("CENTER", -6, 0)
        tab.label:SetText(spec.label)

        -- How many there are, beside the name.
        tab.count = Theme.CreateLabel(tab, "tiny", "muted", "LEFT")
        tab.count:SetPoint("LEFT", tab.label, "RIGHT", 4, 0)

        tab.dot = tab:CreateTexture(nil, "OVERLAY")
        tab.dot:SetSize(6, 6)
        tab.dot:SetPoint("LEFT", tab.count, "RIGHT", 4, 3)
        tab.dot:SetColorTexture(Theme.Unpack("good"))
        tab.dot:Hide()

        tab:SetScript("OnEnter", function(self)
            -- The tab showing is lit already.
            if self.key == TrackerUI:Tab() then return end
            ns.Motion:Blend(self, "hover", 1, 0.12, function(p) TabHover(self, p) end)
        end)
        tab:SetScript("OnLeave", function(self)
            ns.Motion:Blend(self, "hover", 0, 0.18, function(p) TabHover(self, p) end)
        end)
        tab:SetScript("OnClick", function(self) TrackerUI:SetTab(self.key) end)

        self.tabs[index] = tab
    end

    -- The gold line under the tab showing, and the soft glow rising off it.
    local line = strip:CreateTexture(nil, "OVERLAY")
    line:SetHeight(2)
    line:SetColorTexture(Theme.Unpack("accent"))
    local glow = strip:CreateTexture(nil, "ARTWORK")
    glow:SetHeight(7)
    Theme.SetGradientAlpha(glow, "VERTICAL", "accent", 0.32, 0)
    pcall(glow.SetBlendMode, glow, "ADD")

    self.tabStrip = strip
    self.tabLine = line
    self.tabGlow = glow
end

--- Lay the tabs out across the panel's width and put the gold line under
--- the one showing, sliding it there when it moved.
function TrackerUI:DrawTabs(counts)
    local width = tonumber(self.frame:GetWidth()) or self:Width()
    local each = (width - 2) / #self.tabs
    local showing = self:Tab()

    for _, tab in ipairs(self.tabs) do
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", self.tabStrip, "TOPLEFT", (tab.index - 1) * each, 0)
        tab:SetWidth(each - (tab.index < #self.tabs and 3 or 0))

        local on = tab.key == showing
        tab.lit:SetShown(on)
        tab.edge:SetShown(on)
        if on then
            tab.metal:SetColorTexture(Theme.Unpack("glassActive"))
        else
            tab.metal:SetColorTexture(Theme.Unpack("metal", 0.55))
        end
        if on then
            -- The tab showing does not light under the mouse, and its name
            -- is gold.
            ns.Motion:Stop(tab, "hover")
            ns.Motion:SetValue(tab, "hover", 0)
            tab.hover:SetAlpha(0)
            tab.label:SetTextColor(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1)
        else
            -- As lit as its hover has got to, so a redraw under the mouse
            -- leaves it lit.
            TabHover(tab, ns.Motion:Value(tab, "hover"))
        end

        local count = counts and counts[tab.key]
        tab.count:SetText(count and count > 0 and tostring(count) or "")
        tab.dot:SetShown(not on and self.dots and self.dots[tab.key] == true)
    end

    local index = showing == "loot" and 2 or 1
    local inset = math.floor(each * 0.18)
    local target = (index - 1) * each + inset
    local lineWidth = math.max(10, each - inset * 2)

    local function Place(x, span)
        -- Kept, so the next slide starts from where the line is.
        self.tabLineX, self.tabLineWidth = x, span
        self.tabLine:ClearAllPoints()
        self.tabLine:SetPoint("BOTTOMLEFT", self.tabStrip, "BOTTOMLEFT", x, 0)
        self.tabLine:SetWidth(span)
        self.tabGlow:ClearAllPoints()
        self.tabGlow:SetPoint("BOTTOMLEFT", self.tabStrip, "BOTTOMLEFT", x - 2, 0)
        self.tabGlow:SetWidth(span + 4)
    end

    -- Already sliding there: a redraw on the way leaves it going.
    local Motion = ns.Motion
    if Motion and Motion:Running(self, "tabline")
        and self.tabLineTo == target and self.tabLineSpan == lineWidth then
        return
    end
    self.tabLineTo, self.tabLineSpan = target, lineWidth

    -- From wherever the line is now, not from where it was last sent: a tab
    -- picked while the line is still sliding turns it round, where it used
    -- to jump to the far end first.
    local fromX, fromWidth = self.tabLineX, self.tabLineWidth
    if Motion and fromX and fromX ~= target and not self.sizing then
        Motion:Run(self, "tabline", 0.25, function(p)
            Place(fromX + (target - fromX) * p, fromWidth + (lineWidth - fromWidth) * p)
        end)
    else
        if Motion then Motion:Stop(self, "tabline") end
        Place(target, lineWidth)
    end
end

--- Under the tabs: what the session is earning on the left, and the Sort
--- button on the right.
function TrackerUI:BuildToolbar(frame)
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -(HEADER + TAB_HEIGHT))
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -(HEADER + TAB_HEIGHT))
    bar:SetHeight(TOOLBAR)
    self:AddGlass(Theme.Fill(bar, "rowAlt", 0.8))

    bar.left = Theme.CreateLabel(bar, "small", "muted")
    bar.left:SetPoint("LEFT", PADDING, 0)

    bar.sort = Widgets.CreateButton(bar, L.Format("Sort: %s", L["Recent"]), function() TrackerUI:OpenSort() end,
        { width = 60, height = 16 })
    bar.sort:SetPoint("RIGHT", -PADDING + 2, 0)
    bar.sort:SetScript("OnEnter", function(self)
        if self.Light then ns.Motion:Blend(self, "hover", 1, 0.12, self.Light) end
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["Sort"])
            GameTooltip:Show()
        end
    end)
    bar.sort:SetScript("OnLeave", function(self)
        if self.Light then ns.Motion:Blend(self, "hover", 0, 0.18, self.Light) end
        if GameTooltip then GameTooltip:Hide() end
    end)

    -- Clear panel (2026-10-11): how a new run starts mid-session, or across
    -- sessions when the panel is kept (Logic/Session.lua, `keepPanel`).
    bar.clear = TrackerUI.ClearButton(bar, CLEAR_WIDTH, 16)
    bar.clear:SetPoint("RIGHT", bar.sort, "LEFT", -4, 0)

    self.toolbar = bar
end

--- How long a first click on Clear waits for the second, in seconds.
TrackerUI.CLEAR_ARMED = 4

--- A Clear panel button: the first click asks "Click Again", a second within
--- CLEAR_ARMED seconds empties what the panel shows (Session:Clear). Only
--- the view goes; every tally, rate and ranking stays. Used on the panel and
--- in Settings.
function TrackerUI.ClearButton(parent, width, height)
    local function Now()
        if type(GetTime) ~= "function" then return nil end
        local ok, now = pcall(GetTime)
        return ok and type(now) == "number" and now or nil
    end

    -- When the first click came, kept here rather than on the button.
    -- `button.armed` says whether a second click clears (its tooltip reads it).
    local button, armedAt
    local function Arm(on, at)
        button.armed, armedAt = on, at
        if button.SetText then
            button:SetText(on and L["Click Again"] or L["Clear"])
        elseif button.label then
            button.label:SetText(on and L["Click Again"] or L["Clear"])
        end
    end

    button = Widgets.CreateButton(parent, L["Clear"], function()
        local now = Now()
        if button.armed == true and (not armedAt or not now
            or now - armedAt <= TrackerUI.CLEAR_ARMED) then
            Arm(false, nil)
            if ns.Session then ns.Session:Clear() end
            return
        end

        Arm(true, now)
        -- Back to Clear if the second click never comes. Without a clock
        -- (the tests) it waits for the second click.
        if now and C_Timer and type(C_Timer.After) == "function" then
            pcall(C_Timer.After, TrackerUI.CLEAR_ARMED, function()
                local later = Now()
                if button.armed == true and armedAt and later
                    and later - armedAt >= TrackerUI.CLEAR_ARMED then
                    Arm(false, nil)
                end
            end)
        end
    end, { width = width, height = height })
    button.armed = false

    button:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Clear panel"])
        GameTooltip:AddLine(L["Starts fresh. Your kill counts and Rankings stay."], 1, 1, 1, true)
        GameTooltip:AddLine(self.armed == true and L["Click again to clear."] or L["Click twice to clear."],
            0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    return button
end

--- The toolbar's words. Returns how wide the panel must be for them.
function TrackerUI:DrawToolbar()
    local bar = self.toolbar
    local tab = self:Tab()
    local _, label = self:Sort(tab)
    bar.sort:SetText(L.Format("Sort: %s", label))

    local text
    if tab == "loot" then
        local _, looted = self:TabCounts()
        text = L.Format("%d looted", looted)
    else
        local hour = self:PerHour()
        text = hour and L.Format("Per hour  %s", ns.Value.Coins(hour)) or L["This session"]
        -- Ahead of your usual pace (Logic/Moments.lua), in green.
        local pace = hour and ns.Moments and ns.Moments:Pace()
        if pace then text = text .. "  " .. Util.Colored("good", L.Format("(up %d%%)", pace)) end
    end

    bar.left:SetText(text)

    -- The first time a session passes your usual, a cheer floats off it.
    local Moments = ns.Moments
    if Moments and Moments.paceFloat then
        Moments.paceFloat = false
        local FX = ns.TrackerFX
        if FX and FX.Level() == "full" and self.frame and self.frame:IsShown() then
            pcall(FX.FloatText, FX, Util.Colored("good", L["Ahead of your usual pace!"]), bar.left, 0.3, 14)
        end
    end

    local sortWidth = tonumber(bar.sort:GetWidth()) or 60
    local clearWidth = bar.clear and (tonumber(bar.clear:GetWidth()) or CLEAR_WIDTH) + 4 or 0
    return PADDING + Theme.TextWidth("small", Util.StripColor(text)) + 12 + clearWidth + sortWidth + PADDING
end

--- What the session is earning an hour, in copper, once it has run long
--- enough to mean something. Timed from the first thing gathered.
function TrackerUI:PerHour()
    local total = self:NoteStart()
    local now = type(GetTime) == "function" and GetTime() or nil
    if not (total and self.startedAt and type(now) == "number") then return nil end

    local elapsed = now - self.startedAt
    if elapsed < PER_HOUR_AFTER then return nil end

    return total / elapsed * 3600
end

--- Start the per-hour clock at the first thing gathered, and stop it when
--- the session is cleared. Called on every refresh, shown or not: timed
--- only from when the panel was first drawn, a panel opened an hour into a
--- session said you earned a fortune. Returns the session's value.
function TrackerUI:NoteStart()
    local total = ns.Value and ns.Value:Session()
    -- Only nothing gathered at all stops the clock. Worth 0 with items not
    -- priced yet (item info still loading after a /reload) kept nothing
    -- back either, and lost the play time the panel had brought back.
    if total == nil then
        self.startedAt = nil
        return nil
    end
    if not (total > 0) then return nil end

    if not self.startedAt and type(GetTime) == "function" then
        local ok, now = pcall(GetTime)
        if ok and type(now) == "number" then self.startedAt = now end
    end
    return total
end

--- How lit a card's band is under the mouse: 0 at rest, 1 under it.
local function Lit(row, value)
    row.hover:SetAlpha(value)
    row.hoverEdge:SetAlpha(value)
    -- A gradient faded with SetAlpha alone stays lit on Forever, so the
    -- bleed and the wash go through LightGradient, hidden outright at rest.
    -- Both sit above a loot line's quality light, so every line shows it.
    Theme.LightGradient(row.hoverBleed, "HORIZONTAL", "accent", 0.22, 0, value)
    Theme.LightGradient(row.hoverWash, "HORIZONTAL", "accent", 0.10, 0, value)
end

--- Whether a line lights and takes the mouse: one that opens or folds
--- something, a mob, and a Loot tab item (right-click hides it).
local function TakesMouse(line)
    return line ~= nil and (line.mob ~= nil or line.openKey ~= nil or line.style == "loot")
end
TrackerUI.TakesMouse = TakesMouse

--- Whether the mouse is on `row` and the row is on screen. Read in a pcall,
--- as every client value is; a client that cannot say answers no.
local function UnderMouse(row)
    local ok, over = pcall(function() return row:IsVisible() and row:IsMouseOver() end)
    return ok and over and true or false
end

--- Takes a gradient off a texture: white at every corner again.
local function PlainTexture(texture)
    if type(CreateColor) == "function"
        and pcall(texture.SetGradient, texture, "HORIZONTAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1)) then
        return
    end
    pcall(texture.SetVertexColor, texture, 1, 1, 1, 1)
end

--- One row of the column. Every row can be any kind of line; DrawLine
--- decides which parts to show and Render where it goes.
function TrackerUI:CreateLine(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(LINE)
    row:SetFrameLevel(parent:GetFrameLevel() + 3)

    -- Dark glass (the owner, 2026-10-12, "like the Tradeskills queue"): every
    -- line a shade apart, glass and glassAlt in turn (Stripe), with a fine
    -- line under each, so the column reads as separate lines.
    row.band = Theme.Fill(row, "glass")
    row.rule = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.rule:SetPoint("BOTTOMLEFT")
    row.rule:SetPoint("BOTTOMRIGHT")
    row.rule:SetHeight(1)
    row.rule:SetColorTexture(Theme.Unpack("border", 0.6))
    self:AddGlass(row.band)
    self:AddGlass(row.rule)

    -- The card you are on: dark gold (glassActive) and a bright edge.
    row.live = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.live:SetAllPoints(row)
    row.live:SetColorTexture(1, 1, 1, 1)
    row.live:Hide()
    -- The card you are on keeps more of its gold glass, so it still stands out.
    self:AddGlass(row.live, LIVE_GLASS_FLOOR)

    row.edge = row:CreateTexture(nil, "ARTWORK")
    row.edge:SetPoint("TOPLEFT")
    row.edge:SetPoint("BOTTOMLEFT")
    row.edge:SetWidth(2)
    row.edge:Hide()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", PADDING + 6, 0)
    -- Trim the icon's built-in border, as the bags do.
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Anchored at both ends rather than given a width, so it stretches with
    -- the panel; DrawLine sets where it stops.
    row.left = Theme.CreateLabel(row, "small", "text")
    row.left:SetPoint("LEFT", PADDING, 0)
    row.left:SetPoint("RIGHT", -PADDING, 0)

    -- A second, smaller line under the name, on the Loot tab.
    row.sub = Theme.CreateLabel(row, "tiny", "muted")
    row.sub:Hide()

    row.right = Theme.CreateLabel(row, "small", "muted", "RIGHT")
    row.right:SetPoint("RIGHT", -PADDING, 0)
    row.right:SetWidth(RIGHT_WIDTH)

    row.below = Theme.CreateLabel(row, "tiny", "good", "RIGHT")
    row.below:Hide()

    -- The column names over the cards' counts ("columns" lines).
    row.column = Theme.CreateLabel(row, "tiny", "muted", "RIGHT")
    row.column:SetPoint("RIGHT", -PADDING, 0)
    row.column:Hide()

    row.badge = Theme.CreateLabel(row, "tiny", "good", "RIGHT")
    row.badge:SetPoint("RIGHT", row.right, "LEFT", -2, 0)
    row.badge:SetWidth(BADGE_WIDTH)

    -- The Loot tab's rank, on a medal for the top three.
    row.medal = row:CreateTexture(nil, "ARTWORK")
    row.medal:SetSize(MEDAL, MEDAL)
    row.medal:Hide()
    row.rank = Theme.CreateLabel(row, "tiny", "muted", "CENTER")
    row.rank:Hide()

    -- A thin bar under the value: a drop rate, or kills toward MIN_KILLS.
    row.track = row:CreateTexture(nil, "BORDER")
    row.track:SetPoint("BOTTOMRIGHT", -PADDING, 1)
    row.track:SetSize(BAR, 2)
    row.track:SetColorTexture(Theme.Unpack("rowAlt"))

    row.fill = row:CreateTexture(nil, "ARTWORK")
    row.fill:SetPoint("BOTTOMLEFT", row.track, "BOTTOMLEFT")
    row.fill:SetHeight(2)

    -- A folded card's loot, as small icons before its kills.
    row.minis = {}

    -- An open card's loot, as bag slots (made as needed).
    row.slots = {}

    -- The progress bar, the Goals panel's: a dark track, the fill, a
    -- brighter tip with a spark round it, the part just gained, a shine,
    -- and the quarter marks. DrawLine sets where the track runs.
    local bar = {}
    row.progress = bar

    bar.track = row:CreateTexture(nil, "BORDER")
    bar.track:SetHeight(PROGRESS_HEIGHT)
    bar.track:SetColorTexture(Theme.Unpack("row"))

    bar.fill = row:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT", bar.track, "TOPLEFT")
    bar.fill:SetHeight(PROGRESS_HEIGHT)

    bar.tip = row:CreateTexture(nil, "OVERLAY")
    bar.tip:SetPoint("TOPRIGHT", bar.fill, "TOPRIGHT")
    bar.tip:SetSize(4, PROGRESS_HEIGHT)

    -- A soft spark round the tip, spilling past the bar's edges, so the bar
    -- reads as moving: gold, or green with the bar (SetProgress).
    bar.spark = row:CreateTexture(nil, "OVERLAY", nil, 1)
    bar.spark:SetPoint("RIGHT", bar.fill, "RIGHT", 4, 0)
    bar.spark:SetSize(14, 10)
    pcall(bar.spark.SetBlendMode, bar.spark, "ADD")

    bar.fresh = row:CreateTexture(nil, "OVERLAY")
    bar.fresh:SetHeight(PROGRESS_HEIGHT)
    bar.fresh:SetColorTexture(1, 0.95, 0.8, 1)
    pcall(bar.fresh.SetBlendMode, bar.fresh, "ADD")
    bar.fresh:SetAlpha(0)

    bar.shine = row:CreateTexture(nil, "OVERLAY")
    bar.shine:SetHeight(PROGRESS_HEIGHT)
    bar.shine:SetColorTexture(1, 1, 1, 1)
    pcall(bar.shine.SetBlendMode, bar.shine, "ADD")
    bar.shine:SetAlpha(0)

    bar.marks = {}
    for index = 1, #MARKS do
        local mark = row:CreateTexture(nil, "OVERLAY")
        mark:SetSize(1, PROGRESS_HEIGHT)
        mark:SetColorTexture(1, 1, 1, 0.22)
        bar.marks[index] = mark
    end

    bar.parts = { bar.track, bar.fill, bar.tip, bar.spark, bar.fresh, bar.shine }
    for _, mark in ipairs(bar.marks) do bar.parts[#bar.parts + 1] = mark end

    -- A card's band folds and opens it. Under the mouse it lifts, easing in
    -- and out, with the thin gold edge and soft light a list row has (Lit).
    -- The lift sits under the gold wash of the card you are on, so that
    -- one stays gold under the mouse. Each part is drawn at full strength
    -- and hidden with SetAlpha, so the blend can set it.
    row.dragged = false
    row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.hover:SetAllPoints(row)
    row.hover:SetColorTexture(Theme.Unpack("glassHover"))
    row.hover:SetAlpha(0)

    row.hoverEdge = row:CreateTexture(nil, "ARTWORK", nil, 7)
    row.hoverEdge:SetPoint("TOPLEFT")
    row.hoverEdge:SetPoint("BOTTOMLEFT")
    row.hoverEdge:SetWidth(2)
    row.hoverEdge:SetColorTexture(Theme.Unpack("accent"))
    row.hoverEdge:SetAlpha(0)

    row.hoverBleed = row:CreateTexture(nil, "BORDER", nil, 1)
    row.hoverBleed:SetPoint("TOPLEFT", 2, 0)
    row.hoverBleed:SetPoint("BOTTOMLEFT", 2, 0)
    row.hoverBleed:SetWidth(18)
    pcall(row.hoverBleed.SetBlendMode, row.hoverBleed, "ADD")
    row.hoverBleed:Hide()

    -- A soft gold wash across the line from its left, as list rows light.
    row.hoverWash = row:CreateTexture(nil, "BORDER", nil, 1)
    row.hoverWash:SetAllPoints(row)
    row.hoverWash:Hide()

    row:SetScript("OnEnter", function(self)
        local line = self.line
        if not TakesMouse(line) then return end
        TrackerUI.hovered = self
        ns.Motion:Blend(self, "hover", 1, 0.12, function(value) Lit(self, value) end)
        TrackerUI:CardTooltip(self)
    end)

    row:SetScript("OnLeave", function(self)
        if TrackerUI.hovered == self then TrackerUI.hovered = nil end
        ns.Motion:Blend(self, "hover", 0, 0.18, function(value) Lit(self, value) end)
        if GameTooltip then GameTooltip:Hide() end
    end)

    row:SetScript("OnMouseUp", function(self, button)
        -- Letting go at the end of a drag is not a click.
        if self.dragged then
            self.dragged = false
            return
        end

        local line = self.line
        -- Right-click offers to hide the mob, or the Loot tab's item.
        if button == "RightButton" and line and ns.HideMenu then
            if line.mob then
                -- A mob known only by its number can be named here first.
                -- A zone's card hides or names the mob itself.
                local mob = ns.Tracker.NameOf(line.mob)
                local choices = {}
                if ns.LootTableUI then
                    local key = line.mob
                    choices[1] = { kind = "action", text = L["Open Loot Table"],
                        run = function() ns.LootTableUI:Show(key) end }
                end
                local npcID = tonumber(mob:match("^Creature #(%d+)$"))
                if npcID and not ns.Harvest.KnownNpcName(npcID) then
                    choices[#choices + 1] = { kind = "name", name = mob, npcID = npcID }
                end
                choices[#choices + 1] = { kind = "source", name = mob }
                ns.HideMenu:Open(choices)
            elseif line.style == "loot" and line.item then
                ns.HideMenu:Open({ { kind = "item", name = line.item } })
            end
            return
        end
        if button ~= "LeftButton" or not line then return end

        if line.openKey then
            TrackerUI:Toggle(line.openKey, line.openDefault)
        elseif line.mob and ns.LootTableUI then
            ns.LootTableUI:Toggle(line.mob)
        end
    end)

    -- A row that takes the mouse would stop the panel dragging from it;
    -- hand the drag on to the panel.
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function(self)
        self.dragged = true
        local start = parent:GetScript("OnDragStart")
        if start then start(parent) end
    end)
    row:SetScript("OnDragStop", function()
        local stop = parent:GetScript("OnDragStop")
        if stop then stop(parent) end
    end)
    row:SetScript("OnMouseWheel", function(_, delta)
        TrackerUI:ScrollBy(-(tonumber(delta) or 0) * SCROLL_STEP)
    end)

    -- A line made while the panel is see-through gets the shadow under its words.
    if self:SeeThroughOn() then ShadeAll(row, true) end
    return row
end

--- Slot `index` of a row's loot icons, made the first time it is needed:
--- the item's icon on a quality-coloured edge, its count or rate in the
--- corner, and what the effects light up (a glow, "+2", a NEW tag).
function TrackerUI:Slot(row, index)
    local slot = row.slots[index]
    if slot then return slot end

    slot = CreateFrame("Button", nil, row)
    slot:SetSize(SLOT, SLOT)
    slot.dragged = false
    slot:SetFrameLevel(row:GetFrameLevel() + 2)

    Theme.Fill(slot, "window", 0.9)
    slot.glow = slot:CreateTexture(nil, "BACKGROUND", nil, 1)
    slot.glow:SetPoint("TOPLEFT", -3, 3)
    slot.glow:SetPoint("BOTTOMRIGHT", 3, -3)
    slot.glow:SetColorTexture(1, 1, 1, 1)
    pcall(slot.glow.SetBlendMode, slot.glow, "ADD")
    slot.glow:SetAlpha(0)

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 1, -1)
    slot.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    Theme.Border(slot, "borderLit")

    -- A light that washes over the icon when its count goes up.
    slot.flash = slot:CreateTexture(nil, "OVERLAY")
    slot.flash:SetPoint("TOPLEFT", 1, -1)
    slot.flash:SetPoint("BOTTOMRIGHT", -1, 1)
    slot.flash:SetColorTexture(1, 1, 1, 1)
    pcall(slot.flash.SetBlendMode, slot.flash, "ADD")
    slot.flash:SetAlpha(0)

    slot.count = Theme.CreateLabel(slot, "tiny", "text", "RIGHT")
    pcall(slot.count.SetFont, slot.count, Theme.FONT, Theme.sizes.tiny, "OUTLINE")
    slot.count:SetPoint("BOTTOMRIGHT", -1, 2)

    slot.gain = Theme.CreateLabel(slot, "tiny", "good", "RIGHT")
    pcall(slot.gain.SetFont, slot.gain, Theme.FONT, Theme.sizes.tiny, "OUTLINE")
    slot.gain:SetPoint("TOPRIGHT", 4, 5)
    slot.gain:SetAlpha(0)

    slot.tag = slot:CreateTexture(nil, "OVERLAY", nil, 2)
    slot.tag:SetSize(24, 9)
    slot.tag:SetPoint("TOP", 0, 5)
    slot.tag:SetColorTexture(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1)
    slot.tag:SetAlpha(0)
    slot.tagText = Theme.CreateLabel(slot, "tiny", "window", "CENTER")
    pcall(slot.tagText.SetFont, slot.tagText, Theme.FONT, 8, "")
    slot.tagText:SetPoint("CENTER", slot.tag, "CENTER", 0, 0)
    slot.tagText:SetText(L["NEW"])
    slot.tagText:SetTextColor(0.1, 0.08, 0.03, 1)
    slot.tagText:SetAlpha(0)

    slot.hover = slot:CreateTexture(nil, "HIGHLIGHT")
    slot.hover:SetAllPoints(slot.icon)
    slot.hover:SetColorTexture(1, 1, 1, 0.15)

    slot:SetScript("OnEnter", function(self) TrackerUI:SlotTooltip(self) end)
    slot:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    slot:SetScript("OnClick", function(self)
        if self.dragged then
            self.dragged = false
            return
        end
        local icon = self.line
        if icon and icon.mob and ns.LootTableUI then ns.LootTableUI:Toggle(icon.mob) end
    end)
    slot:RegisterForDrag("LeftButton")
    slot:SetScript("OnDragStart", function(self)
        self.dragged = true
        local panel = TrackerUI.frame
        local start = panel and panel:GetScript("OnDragStart")
        if start then start(panel) end
    end)
    slot:SetScript("OnDragStop", function()
        local panel = TrackerUI.frame
        local stop = panel and panel:GetScript("OnDragStop")
        if stop then stop(panel) end
    end)
    slot:SetScript("OnMouseWheel", function(_, delta)
        TrackerUI:ScrollBy(-(tonumber(delta) or 0) * SCROLL_STEP)
    end)

    row.slots[index] = slot
    return slot
end

--- A card band's tooltip: its name, and what a click does now.
function TrackerUI:CardTooltip(row)
    local line = row.line
    if not (line and GameTooltip) then return end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(line.left)
    if line.style == "loot" then
        GameTooltip:AddLine(L["Right-click to hide it."], 1, 1, 1)
    elseif line.openKey then
        GameTooltip:AddLine(line.folded and L["Click to show its loot."] or L["Click to fold it."], 1, 1, 1)
        if line.mob then
            GameTooltip:AddLine(L["Click an item for everything it has dropped."], 1, 1, 1)
        end
    else
        GameTooltip:AddLine(L["Click for everything it has dropped."], 1, 1, 1)
    end
    GameTooltip:Show()
end

--- A redraw hands a row its line while the mouse sits still, and no OnEnter
--- comes for that. A band still under the mouse stays lit, at once and at
--- full, its tooltip saying what a click does now; every other row is dark.
--- Before, each kill put out the band you were pointing at.
function TrackerUI:Relight(row, takesMouse)
    local over = takesMouse and self.hovered == row and UnderMouse(row)
    ns.Motion:Stop(row, "hover")
    ns.Motion:SetValue(row, "hover", over and 1 or 0)
    Lit(row, over and 1 or 0)
    if over then self:CardTooltip(row) end
end

--- An icon's name, what its number means, and what one is worth.
function TrackerUI:SlotTooltip(slot)
    local icon = slot.line
    if not (icon and GameTooltip) then return end

    GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
    local r, g, b = HexColor(ns.Tracker:LookOf(icon.item).color)
    if not r then r, g, b = ns.Util.ItemRGB(icon.item) end
    GameTooltip:AddLine(icon.item, r or 1, g or 1, b or 1)
    if icon.about then GameTooltip:AddLine(icon.about, 1, 1, 1) end

    local unit = ns.Value and ns.Value:WorthOf(icon.item)
    if unit then
        GameTooltip:AddLine(L.Format("Worth %s each", ns.Value.Coins(unit)), 1, 1, 1)
    elseif ns.Value and ns.Value:IsQuest(icon.item) then
        local r, g, b = Theme.Unpack("accent")
        GameTooltip:AddLine(L["Quest item"], r, g, b)
    end

    if icon.mob then
        GameTooltip:AddLine(L["Click for everything it has dropped."], 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- What goes in it
--
-- Built as a flat list of lines first, then drawn, so the layout rules live in
-- one place and a test can read the list without a frame.
--------------------------------------------------------------------------------

--- Every line the tab showing would hold, top to bottom.
--
-- Each is { style, left, right }, plus as it applies: `item` (a name whose
-- icon and colour to draw), `badge` (small green text beside the value),
-- `bar` (0-1) and `barColor`, `rightColor`, `mob` (a mob whose loot table a
-- click opens) and `openKey` (a card's band: a click folds or opens it).
-- A line whose number can go up also has a `key` that names it from one
-- redraw to the next and that `count`, so UI/TrackerFX.lua can tell what just
-- went up and make it move.
-- Styles: "heading", "mob" (a card's band; `folded` for one line with
-- `minis`, `live` for the card you are on), "place", "value", "item",
-- "note", "link", "progress" (the bar toward rates: `have`, `target`,
-- `progress` 0-1, `milestone` for the marks passed, `final` in the last
-- stretch), "icons" (an open card's loot as bag slots: `icons`, each
-- { item, text, key, count, about, mob }) and "loot" (a Loot tab item:
-- `sub` under the name, `below` under the count, `rank`).
-- A fishing spot or a node is drawn as a card with no `mob`.
function TrackerUI:Lines()
    local out = {}

    local function Add(line)
        line.right = line.right or ""
        out[#out + 1] = line
        return line
    end

    if self:Tab() == "loot" then
        self:LootLines(Add)
        return out
    end

    local mobs = ns.Tracker:SessionMobs()

    -- The Fishing and Gathering sections are there only once you have done
    -- that this session (2026-09-25), and whichever you did last goes
    -- on top.
    local fished = ns.Fishing and ns.Fishing.sessionCasts > 0
    local gathered = ns.Gathering and ns.Gathering.sessionGathers > 0

    if #mobs == 0 and not fished and not gathered then
        Add({ style = "note", left = L["Nothing killed yet this session."] })
        Add({ style = "note", left = L["Loot a corpse and it shows up here."] })
        return out
    end

    local sections = {}

    if #mobs > 0 then
        sections[#sections + 1] = { key = "kill", draw = function(withTotal, first)
            self:KillLines(Add, mobs, first)
        end }
    end

    if fished then
        sections[#sections + 1] = { key = "fishing", draw = function(withTotal, first)
            self:FishingLines(Add, withTotal, first)
        end }
    end

    if gathered then
        sections[#sections + 1] = { key = "gathering", draw = function(withTotal, first)
            self:GatheringLines(Add, withTotal, first)
        end }
    end

    for index, section in ipairs(sections) do
        if section.key == ns.lastLoot and index > 1 then
            table.remove(sections, index)
            table.insert(sections, 1, section)
            break
        end
    end

    -- The haul's total goes with the kills when there are any, as it always
    -- has; otherwise under whichever heading is on top.
    for index, section in ipairs(sections) do
        section.draw(#mobs == 0 and index == 1, index == 1)
    end

    return out
end

--- "12 / 20", the first part bright, as a goal's count reads.
function TrackerUI.CountText(have, target)
    return ("%d|c%s / %d|r"):format(have, ns.COLORS.muted, target)
end

--- In the last stretch toward `target`: a few left, and the bar goes green.
function TrackerUI.Final(have, target)
    local left = target - have
    return left > 0 and left <= math.max(1, math.floor(target * FINAL))
end

--- A bar toward `target`: the count it shows (held to 0..target), how full
--- it is, and how many of the MARKS it has passed.
function TrackerUI.ProgressOf(have, target)
    have = math.max(0, math.min(have, target))
    local fraction = target > 0 and have / target or 0

    local milestone = 0
    for index, at in ipairs(MARKS) do
        if fraction >= at then milestone = index end
    end

    return have, fraction, milestone
end

--- Under a band still short of rates (2026-09-27): a progress bar
--- like a goal's, then how many more. `key` is the band's; `more` is the
--- countdown's text, "%d" for the number.
function TrackerUI:ProgressLines(Add, key, have, target, more)
    local fraction, milestone
    have, fraction, milestone = TrackerUI.ProgressOf(have, target)

    local final = TrackerUI.Final(have, target)
    Add({ style = "progress", key = key .. ":progress", count = have,
        have = have, target = target, progress = fraction,
        milestone = milestone, final = final,
        right = TrackerUI.CountText(have, target), rightColor = "text" })

    -- The last few say so in green, as a goal's do.
    local left = target - have
    Add({ style = "note", left = more:format(left) .. (final and "!" or ""),
        leftColor = final and "good" or nil })
end

--- One card: a mob, a fishing spot or a node (2026-09-28: every
--- item it has given as bag icons, not just the top three).
--
-- Open, it is the band, where, the bar toward rates, what one is worth and
-- its loot as icons. Folded, it is the band alone with its loot as small
-- icons, so a long session still fits. `card` is:
-- { key, name, mob, total, session, rated, target, more, place, placeMore,
--   worth, worthLabel, rank, ranked, items = { { name, n, chance } }, noun,
--   open, default, live }
function TrackerUI:CardLines(Add, card)
    local open = self:IsOpen(card.key, card.default)

    -- A crown for a mob you are champion of, and for the one a preview
    -- crowned (held in memory only, never saved).
    -- A mob killed in more than one zone has a card a zone: "Ghoul (Duskwood)".
    local name = ns.Tracker.ShowKey(card.name, ns.Harvest.ShowName)
    local mobName = card.mob and ns.Tracker.NameOf(card.mob)
    local kills = card.mob and (tonumber(card.total) or 0) or 0
    -- A preview's kills, for its mark alone.
    if card.mob and self.banePreview == mobName then
        kills = math.max(kills, ns.Tracker.BANE_KILLS)
    elseif card.mob and self.markPreview and self.markPreview.mob == mobName then
        kills = math.max(kills, self.markPreview.kills)
    elseif card.mob and self.crownPreview == mobName then
        kills = math.max(kills, ns.Tracker.CHAMPION_KILLS)
    end
    local mark, legendary = nil, false
    if card.mob then mark, legendary = TrackerUI.MarkFor(kills) end
    local crowned = mark ~= nil
    local bane = legendary and true or false
    if mark then
        name = legendary and ("|c%s%s|r %s"):format(LEGENDARY, name, mark) or (name .. " " .. mark)
    end

    local band = Add({ style = "mob", left = name, mob = card.mob, crowned = crowned or nil,
        bane = bane or nil,
        openKey = card.key, openDefault = card.default, folded = not open,
        live = card.live and open or nil,
        right = tostring(card.total), badge = ("+%d"):format(card.session),
        key = card.key, count = card.total })

    if not open then
        -- Folded: kills toward rates as the thin bar under the count, and
        -- what it drops as small icons.
        if not card.rated then
            band.bar = card.target > 0 and card.total / card.target or 0
            band.barColor = TrackerUI.Final(card.total, card.target) and "good" or "accent"
        end
        band.minis = {}
        for index = 1, math.min(#card.items, MINIS) do
            band.minis[index] = card.items[index].name
        end

        -- What its progress bar and icons would count, open. A kill on this
        -- mob opens the card in the same redraw, and the effects need the
        -- counts from before it to slide the bar from where it was, cheer
        -- the marks it passes and flash the icon that went up.
        band.hidden = {}
        if not card.rated then
            local have, fraction, milestone = TrackerUI.ProgressOf(card.total, card.target)
            band.hidden[1] = { key = card.key .. ":progress", count = have,
                progress = fraction, milestone = milestone }
        end
        for _, item in ipairs(card.items) do
            band.hidden[#band.hidden + 1] = { key = ("%s:%s"):format(card.key, item.name),
                count = item.n }
        end
        return
    end

    if card.place then
        Add({ style = "place", left = card.place, right = card.placeMore })
    end

    if not card.rated then
        self:ProgressLines(Add, card.key, card.total, card.target, card.more)
    end

    if card.worth then
        Add({ style = "value", left = card.worthLabel,
            right = ns.Value.Coins(card.worth), rightColor = "good" })
    end

    -- Its place on your Rankings board (2026-10-13), once it is on it.
    if card.rank then
        Add({ style = "value", left = L["Rank"],
            right = L.Format("#%d of %d", card.rank, card.ranked), rightColor = "accent" })
    end

    -- Your kills since its best drop last fell (Logic/Moments.lua).
    local since = card.mob and ns.Moments and ns.Moments:SinceLine(mobName)
    if since then
        Add({ style = "value", left = since.label,
            right = Util.Plural(since.kills, L["kill"], L["kills"]), rightColor = "accent" })
    end

    -- The chance of green gear at its level, and what you have had from it
    -- (Logic/WorldDrops.lua). Only open cards get here, so only they ask.
    local world = card.mob and ns.WorldDrops and ns.WorldDrops:CardLines(mobName)
    if world then
        Add({ style = "value", left = world.label, right = world.chance, rightColor = "good" })
        Add({ style = "value", left = L["You've had here"], right = world.had })
    end

    if #card.items == 0 then
        if card.rated then Add({ style = "note", left = L["nothing dropped yet"] }) end
        return
    end

    local icons = {}
    for _, item in ipairs(card.items) do
        local icon = { item = item.name, mob = card.mob,
            key = ("%s:%s"):format(card.key, item.name), count = item.n }

        if card.rated then
            icon.text = ns.Tracker.FormatChance(item.chance)
            icon.textColor = RateColor(item.chance)
            icon.about = L.Format("In %s of %s", ns.Tracker.FormatChance(item.chance), card.noun)
        else
            icon.text = tostring(item.n)
            icon.about = L.Format("%d of %d %s", item.n, card.total, card.noun)
        end

        icons[#icons + 1] = icon
    end

    Add({ style = "icons", icons = icons, mob = card.mob, card = card.key, live = card.live })
end

--- The mobs in the order the Sort button says. The one you are on always
--- leads, open, whatever the order.
function TrackerUI:SortMobs(mobs)
    local sort = self:Sort("farm")
    if sort == "recent" then return mobs end

    local keyed = {}
    for _, summary in ipairs(mobs) do
        local value = 0
        if sort == "kills" then
            value = summary.session
        elseif sort == "worth" then
            value = ns.Value and ns.Value:ForMob(summary.mob) or 0
        elseif sort == "value" then
            value = self:MobLootValue(ns.Tracker.NameOf(summary.mob))
        end
        keyed[#keyed + 1] = { summary = summary, value = tonumber(value) or 0 }
    end

    table.sort(keyed, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.summary.mob < b.summary.mob
    end)

    local sorted = {}
    for index, entry in ipairs(keyed) do sorted[index] = entry.summary end
    return sorted
end

--- What a mob's loot this session is worth, in copper, from the items that
--- have a price.
function TrackerUI:MobLootValue(mob)
    local total = 0
    if not ns.Value then return total end

    for name, from in pairs(ns.Tracker.sessionFrom or {}) do
        local count = from[mob]
        if count and ns.Tracker.Counts(name) then
            local unit = ns.Value:WorthOf(name)
            if unit then total = total + count * unit end
        end
    end
    return total
end

--- The small line over the cards that says what their two numbers are
--- (2026-10-13): the green one is this session's, the white one all of them.
function TrackerUI:ColumnLine(Add)
    Add({ style = "columns", left = "", badge = L["This session"], column = L["All time"] })
end

--- This session's kills: the heading, then a card for each mob killed.
function TrackerUI:KillLines(Add, mobs, first)
    local Tracker = ns.Tracker

    Add({ style = "heading", left = L["THIS SESSION"],
        right = Util.Plural(Tracker:SessionKills(), L["kill"], L["kills"]) })

    self:TotalLines(Add)

    -- A streak shows from its third kill (2026-09-26), with the
    -- session's best beside it once there is a better one to beat.
    local streak = Tracker:Streak()
    if streak >= STREAK_SHOWN then
        local best = Tracker.bestStreak
        Add({ style = "value", key = "streak", count = streak,
            left = best > streak and L.Format("Kill streak  (best %d)", best) or L["Kill streak"],
            right = ("x%d"):format(streak), rightColor = "accent" })
    end

    -- The mob you are on leads; the rest follow in the order picked.
    local current = Tracker.currentKey or Tracker.current
    local ordered = {}
    for _, summary in ipairs(mobs) do
        if summary.mob == current then table.insert(ordered, 1, summary) end
    end
    local rest = {}
    for _, summary in ipairs(mobs) do
        if summary.mob ~= current then rest[#rest + 1] = summary end
    end
    for _, summary in ipairs(self:SortMobs(rest)) do ordered[#ordered + 1] = summary end

    if #ordered > 0 then self:ColumnLine(Add) end

    for _, summary in ipairs(ordered) do
        local worth, details
        if ns.Value then worth, details = ns.Value:ForMob(summary.mob) end

        local top = summary.places[1]
        local items = {}
        for _, item in ipairs(summary.items) do
            items[#items + 1] = { name = item.name, n = item.corpses, chance = item.chance }
        end

        -- Your board only: a mob is ranked from its own kills, never an
        -- estimate.
        local rank, ranked
        if ns.RankUp and summary.rated and details and details.basis == "tally" then
            rank, ranked = ns.RankUp:RankOf(summary.mob)
        end

        local isCurrent = summary.mob == current
        self:CardLines(Add, {
            key = "mob:" .. summary.mob, name = summary.mob, mob = summary.mob,
            total = summary.kills, session = summary.session,
            rated = summary.rated, target = Tracker.MIN_KILLS,
            more = summary.needed == 1 and L["%d more kill for drop rates"] or L["%d more kills for drop rates"],
            place = top and top.name,
            placeMore = top and #summary.places > 1 and L.Format("+%d more", #summary.places - 1) or nil,
            worth = worth,
            worthLabel = details and details.basis == "tally" and L["Worth per kill"] or L["Worth per kill (est.)"],
            rank = rank, ranked = ranked,
            items = items, noun = L["kills"],
            default = isCurrent, live = isCurrent and first,
        })
    end
end

--- What everything gathered this session is worth (2026-09-25): coin,
--- loot and fishing catches together, priced like worth per kill. Items with
--- no price are left out, so the total never guesses.
--
-- The total itself sits in the title bar (2026-09-27). Returns its
-- line, or nil when nothing gathered this session has a price.
function TrackerUI:TitleTotal()
    if not ns.Value then return nil end

    local total = ns.Value:Session()
    if not total then return nil end

    return { style = "value", left = L["Gathered value"],
        right = ns.Value.Coins(total), rightColor = "good",
        key = "total", count = total }
end

--- The note under the top heading when some items had no price to count.
function TrackerUI:TotalLines(Add)
    if not ns.Value then return end

    local total, details = ns.Value:Session()
    if not total then return end

    local missing = #details.unpriced
    if missing > 0 then
        Add({ style = "note", left = L.Format("%s with no price left out",
            Util.Plural(missing, L["item"], L["items"])) })
    end
end

--- This session's fishing: a card for each spot fished, latest first.
function TrackerUI:FishingLines(Add, withTotal, first)
    local Fishing = ns.Fishing

    Add({ style = "heading", left = L["FISHING"],
        right = Util.Plural(Fishing.sessionCasts, L["cast"], L["casts"]) })

    -- No kills this session and this on top: the haul's total goes here.
    if withTotal then self:TotalLines(Add) end

    local spots = Fishing:SessionSpots()
    if #spots > 0 then self:ColumnLine(Add) end

    for index, summary in ipairs(spots) do
        local items = {}
        for _, item in ipairs(summary.items) do
            items[#items + 1] = { name = item.name, n = item.casts, chance = item.chance }
        end

        self:CardLines(Add, {
            key = "spot:" .. tostring(summary.key),
            name = (summary.name:gsub("^%l", string.upper)),
            total = summary.casts, session = summary.session,
            rated = summary.rated, target = Fishing.MIN_CASTS,
            more = summary.needed == 1 and L["%d more cast for catch rates"] or L["%d more casts for catch rates"],
            place = summary.place,
            worth = Fishing:WorthPerCast(summary.key), worthLabel = L["Worth per cast"],
            items = items, noun = L["casts"],
            default = index == 1, live = index == 1 and first,
        })
    end
end

--- This session's gathering: a card for each herb or vein, latest first.
function TrackerUI:GatheringLines(Add, withTotal, first)
    local Gathering = ns.Gathering

    Add({ style = "heading", left = L["GATHERING"],
        right = Util.Plural(Gathering.sessionGathers, L["gather"], L["gathers"]) })

    if withTotal then self:TotalLines(Add) end

    local nodes = Gathering:SessionNodes()
    if #nodes > 0 then self:ColumnLine(Add) end

    for index, summary in ipairs(nodes) do
        local items = {}
        for _, item in ipairs(summary.items) do
            items[#items + 1] = { name = item.name, n = item.gathers, chance = item.chance }
        end

        self:CardLines(Add, {
            key = "node:" .. tostring(summary.key), name = summary.name,
            total = summary.gathers, session = summary.session,
            rated = summary.rated, target = Gathering.MIN_GATHERS,
            more = L["%d more for gather rates"],
            place = summary.place,
            worth = Gathering:WorthPerGather(summary.key), worthLabel = L["Worth per node"],
            items = items, noun = L["gathers"],
            default = index == 1, live = index == 1 and first,
        })
    end
end

--------------------------------------------------------------------------------
-- The Loot tab
--
-- Everything looted, fished and gathered this session in one list
-- (2026-09-28), best earners first, with where each came from under its name.
--------------------------------------------------------------------------------

--- "Rabid Gnoll 7, Mangy Wolf 3, +2 more" from { [source] = count }, and
--- the short form, "Rabid Gnoll 7, +2 more", for a narrow panel.
local function SourcesText(sources)
    local list = {}
    for name, count in pairs(sources) do list[#list + 1] = { name = name, count = count } end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)

    local function Text(shown)
        local parts = {}
        for index = 1, math.min(#list, shown) do
            parts[index] = ("%s %d"):format(list[index].name, list[index].count)
        end
        if #list > shown then parts[#parts + 1] = L.Format("+%d more", #list - shown) end
        return table.concat(parts, ", ")
    end

    return Text(SOURCES_SHOWN), Text(1)
end

--- This session's items: { name, count, value (copper or nil), sources }.
function TrackerUI:SessionItems()
    local byName = {}

    local function Take(counts, fromTable, label)
        for name, count in pairs(counts or {}) do
            local entry = byName[name]
            if not entry then
                entry = { name = name, count = 0, sources = {} }
                byName[name] = entry
            end
            entry.count = entry.count + count

            local from = fromTable and fromTable[name]
            if type(from) == "table" and next(from) then
                for source, n in pairs(from) do
                    entry.sources[source] = (entry.sources[source] or 0) + n
                end
            elseif label then
                entry.sources[label] = (entry.sources[label] or 0) + count
            end
        end
    end

    Take(ns.Tracker.sessionLoot, ns.Tracker.sessionFrom, nil)
    if ns.Fishing then Take(ns.Fishing.sessionCatch, nil, L["Fishing"]) end
    if ns.Gathering then Take(ns.Gathering.sessionItems, ns.Gathering.sessionFrom, L["Gathering"]) end

    -- Skinning while it is hidden, and items on the hide list, are not
    -- shown (DB:HidesItem).
    for name in pairs(byName) do
        if not ns.Tracker.Counts(name) then byName[name] = nil end
    end

    local items = {}
    for _, entry in pairs(byName) do
        local unit = ns.Value and ns.Value:WorthOf(entry.name)
        entry.value = unit and entry.count * unit or nil
        entry.quest = not unit and ns.Value and ns.Value:IsQuest(entry.name) or nil
        items[#items + 1] = entry
    end

    local sort = self:Sort("loot")
    table.sort(items, function(a, b)
        if sort == "count" and a.count ~= b.count then return a.count > b.count end
        if sort == "value" then
            local va, vb = a.value or -1, b.value or -1
            if va ~= vb then return va > vb end
        end
        return a.name < b.name
    end)

    return items
end

function TrackerUI:LootLines(Add)
    local items = self:SessionItems()

    if #items == 0 then
        Add({ style = "note", left = L["No loot yet this session."] })
        Add({ style = "note", left = L["Everything you loot, fish or gather shows up here."] })
        return
    end

    for rank, entry in ipairs(items) do
        local sub, short = SourcesText(entry.sources)
        Add({ style = "loot", item = entry.name, left = entry.name,
            sub = sub, subShort = short, rank = rank,
            right = ("x%d"):format(entry.count),
            below = entry.value and ns.Value.Coins(entry.value)
                or (entry.quest and L["Quest"] or L["no price"]),
            belowColor = entry.value and "good" or (entry.quest and "accent" or "muted"),
            key = "loot:" .. entry.name, count = entry.count })
    end

    local coin = tonumber(ns.Tracker.sessionCopper) or 0
    if coin > 0 then
        Add({ style = "value", left = L["Coin from kills"], right = ns.Value.Coins(coin),
            rightColor = "good" })
    end

    self:TotalLines(Add)
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

--- Each line's glass shade, worked out once a redraw over every line
--- (Render), so the shades follow the list rather than the rows on screen.
--- Headings keep the header band; lines inside an open card sit on the
--- card's own darker glass; the rest take glass and glassAlt in turn (the
--- Loot tab's by rank, so a line keeps its shade as the list scrolls).
function TrackerUI.Stripe(lines)
    local turn, inCard = 0, false
    for _, line in ipairs(lines) do
        local style = line.style
        if style == "heading" then
            line.glass, inCard, turn = "header", false, 0
        elseif style == "columns" then
            line.glass, inCard = "header", false
        elseif style == "mob" then
            inCard = not line.folded
            turn = turn + 1
            line.glass = turn % 2 == 0 and "glassAlt" or "glass"
        elseif inCard then
            line.glass = false
        elseif style == "loot" and line.rank then
            line.glass = line.rank % 2 == 0 and "glassAlt" or "glass"
        else
            turn = turn + 1
            line.glass = turn % 2 == 0 and "glassAlt" or "glass"
        end
    end
    return lines
end

--- How tall a line is drawn. Icons wrap to the panel's width.
function TrackerUI:LineHeight(line, width)
    if line.style == "loot" then return LOOT_ROW end
    if line.style == "icons" then
        local perRow = self:SlotsPerRow(width)
        local rows = math.max(1, math.ceil(#line.icons / perRow))
        return rows * (SLOT + SLOT_GAP) + 6
    end
    if line.style == "mob" and not line.folded then return LINE + 4 end
    return LINE
end

function TrackerUI:SlotsPerRow(width)
    width = tonumber(width) or self:Width()
    return math.max(1, math.floor((width - 2 - PADDING * 2 - 4 + SLOT_GAP) / (SLOT + SLOT_GAP)))
end

--- Hide everything a line style may have shown, before drawing another.
local function ClearExtras(row)
    for _, slot in ipairs(row.slots) do slot:Hide() end
    for _, mini in ipairs(row.minis) do mini:Hide() end
    row.sub:Hide()
    row.below:Hide()
    row.medal:Hide()
    row.rank:Hide()
    row.live:Hide()
    row.edge:Hide()
    if row.column then row.column:Hide() end
end

--- A quality-coloured item's colour as four numbers, text colour if none.
local function ItemColor(name)
    local r, g, b, a = HexColor(ns.Tracker:LookOf(name).color)
    if r then return r, g, b, a end
    -- No loot link kept its colour: the item's rarity from the client.
    r, g, b = ns.Util.ItemRGB(name)
    if r then return r, g, b, 1 end
    return Theme.Unpack("text")
end

function TrackerUI:DrawLine(row, line)
    ClearExtras(row)
    row.line = line

    -- A line measured before any Stripe (Needs) takes plain glass.
    local glass = line.glass
    if glass == nil then glass = line.style == "heading" and "header" or "glass" end
    if glass then
        row.band:SetColorTexture(Theme.Unpack(glass))
        row.band:Show()
    else
        row.band:Hide()
    end
    row.rule:SetShown(line.style ~= "heading")

    if line.style == "icons" then
        return self:DrawIcons(row, line)
    end

    -- Items get an icon and their quality colour; everything else is text.
    local indent = PADDING

    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", PADDING + 6, 0)
    row.icon:SetSize(ICON, ICON)

    if line.style == "item" then
        local look = ns.Tracker:LookOf(line.item)
        row.icon:SetTexture(look.icon or FALLBACK_ICON)
        row.icon:Show()
        indent = PADDING + 6 + ICON + 4
        row.left:SetTextColor(ItemColor(line.item))
    elseif line.style == "loot" then
        indent = self:DrawLootParts(row, line)
    elseif line.style == "place" then
        row.icon:SetTexture(PLACE_ICON)
        row.icon:Show()
        indent = PADDING + 6 + ICON + 4
        row.left:SetTextColor(Theme.Unpack("muted"))
    else
        row.icon:Hide()

        if line.style == "note" or line.style == "value" or line.style == "progress" then
            indent = PADDING + 6
            row.left:SetTextColor(Theme.Unpack(line.leftColor or "muted"))
        elseif line.style == "link" then
            indent = PADDING + 6
            row.left:SetTextColor(Theme.Unpack("accent"))
        elseif line.style == "heading" then
            row.left:SetTextColor(Theme.Unpack("muted"))
        elseif line.live then
            row.left:SetTextColor(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1)
        else
            row.left:SetTextColor(Theme.Unpack("accent"))
        end
    end

    -- The card you are on: dark gold glass and a bright edge down its left
    -- (2026-09-28: "i like that neon glow"; 2026-10-12, as the top row of
    -- Tradeskills' queue).
    if line.style == "mob" and line.live then
        -- The row may have lit a green drop on the Loot tab, and a colour
        -- does not undo a gradient: it stayed tinted and see-through.
        PlainTexture(row.live)
        row.live:SetColorTexture(Theme.Unpack("glassActive"))
        row.live:Show()
        row.edge:SetColorTexture(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1)
        row.edge:SetWidth(3)
        row.edge:Show()
    end

    -- The text runs to the value column, or all the way across when a line
    -- has no value. That second case is what cut "Nothing killed yet this
    -- session." short: it stopped where a value would have started.
    --
    -- The value and badge columns are as wide as their text needs, at least
    -- their usual width, so neither is cut short either.
    local rightWidth = math.max(RIGHT_WIDTH, Theme.TextWidth("small", Util.StripColor(line.right)) + 2)
    local badgeWidth = math.max(BADGE_WIDTH, Theme.TextWidth("tiny", line.badge) + 2)
    if line.style == "loot" then
        rightWidth = math.max(rightWidth, Theme.TextWidth("tiny", Util.StripColor(line.below)) + 2)
    end
    row.right:SetWidth(rightWidth)
    row.badge:SetWidth(badgeWidth)

    local stop = PADDING
    if line.right ~= "" then stop = stop + rightWidth + 4 end
    if line.badge then stop = stop + badgeWidth + 2 end

    -- A folded card's small icons sit just before its count.
    local minisWidth = 0
    if line.minis and #line.minis > 0 then
        minisWidth = self:DrawMinis(row, line.minis, stop)
        stop = stop + minisWidth
    end

    row.left:ClearAllPoints()
    if line.style == "loot" then
        row.left:SetPoint("TOPLEFT", indent, -3)
        row.left:SetPoint("TOPRIGHT", -stop, -3)
        row.sub:ClearAllPoints()
        row.sub:SetPoint("BOTTOMLEFT", indent, 4)
        row.sub:SetPoint("BOTTOMRIGHT", -stop, 4)
        -- Where it came from, shortened to the first source when the panel
        -- is too narrow for two: it never widens the panel on its own.
        local room = (tonumber(self.frame and self.frame:GetWidth()) or self:Width()) - 2 - indent - stop
        local sub = line.sub or ""
        if line.subShort and Theme.TextWidth("tiny", sub) > room then sub = line.subShort end
        row.sub:SetText(sub)
        row.sub:Show()
    else
        row.left:SetPoint("LEFT", indent, 0)
        row.left:SetPoint("RIGHT", -stop, 0)
    end
    row.leftStop = stop
    row.leftIndent = indent

    -- How wide the panel must be for this line to show in full.
    row.needs = indent + Theme.TextWidth("small", line.left) + stop + 4
    if line.style == "loot" then
        row.needs = math.max(row.needs, indent + Theme.TextWidth("tiny", line.subShort or line.sub) + stop + 4)
    end
    row.left:SetText(line.left or "")
    row.left:Show()

    -- The progress bar runs from the indent to just short of its count.
    local bar = row.progress
    if line.style == "progress" then
        row.barLeft = indent
        row.barRight = stop
        row.needs = indent + MIN_PROGRESS + stop + 4

        bar.track:ClearAllPoints()
        bar.track:SetPoint("LEFT", indent, 0)
        bar.track:SetPoint("RIGHT", -stop, 0)
        for _, part in ipairs(bar.parts) do part:Show() end
        -- Drawn at its real width once the panel's width is settled.
        self:SetProgress(row, line.progress, line.final)
    else
        for _, part in ipairs(bar.parts) do part:Hide() end
    end

    row.right:ClearAllPoints()
    if line.style == "loot" then
        row.right:SetPoint("TOPRIGHT", -PADDING, -3)
        row.below:ClearAllPoints()
        row.below:SetPoint("BOTTOMRIGHT", -PADDING, 4)
        row.below:SetWidth(rightWidth)
        row.below:SetText(line.below or "")
        row.below:SetTextColor(Theme.Unpack(line.belowColor or "good"))
        row.below:Show()
    else
        row.right:SetPoint("RIGHT", -PADDING, 0)
    end
    row.right:SetText(line.right)
    row.right:SetTextColor(Theme.Unpack(line.rightColor
        or ((line.style == "mob" or line.style == "loot") and "text" or "muted")))
    if line.live then row.right:SetTextColor(1, 1, 1, 1) end
    row.right:Show()

    -- Column names: small and muted, the right one as wide as the counts
    -- under it so both sit over their own column.
    if line.style == "columns" then
        local width = math.max(RIGHT_WIDTH, Theme.TextWidth("tiny", line.column) + 2)
        row.right:SetWidth(width)
        row.column:SetWidth(width)
        row.column:SetText(line.column or "")
        row.column:Show()
        row.needs = math.max(row.needs, PADDING + width + 2 + badgeWidth + PADDING + 4)
    end
    row.badge:SetTextColor(Theme.Unpack(line.style == "columns" and "muted" or "good"))

    if line.badge then
        row.badge:SetText(line.badge)
        row.badge:Show()
    else
        row.badge:SetText("")
        row.badge:Hide()
    end

    if line.bar then
        row.track:Show()
        row.fill:SetWidth(math.max(1, BAR * math.min(1, line.bar)))
        row.fill:SetColorTexture(Theme.Unpack(line.barColor or "accent"))
        row.fill:Show()
    else
        row.track:Hide()
        row.fill:Hide()
    end

    -- Only rows that open or fold something take the mouse, so the rest of
    -- the panel still drags from anywhere.
    local takesMouse = TakesMouse(line)
    row:EnableMouse(takesMouse)
    self:Relight(row, takesMouse)

    row:Show()
end

--- A Loot tab row's rank and medal, icon and quality wash. Returns where
--- its name starts.
function TrackerUI:DrawLootParts(row, line)
    -- A medal says best earner, so only the Value order hands them out:
    -- sorted by name, the top three are only first in the alphabet.
    local medal = self:Sort("loot") == "value" and MEDALS[line.rank] or nil
    row.medal:ClearAllPoints()
    row.medal:SetPoint("LEFT", PADDING - 2, 0)
    row.rank:ClearAllPoints()
    row.rank:SetPoint("CENTER", row.medal, "CENTER", 0, 0)
    row.rank:SetText(tostring(line.rank or ""))
    row.rank:Show()

    if medal then
        row.medal:SetColorTexture(medal[1], medal[2], medal[3], 0.95)
        row.medal:Show()
        row.rank:SetTextColor(0.1, 0.08, 0.03, 1)
    else
        row.rank:SetTextColor(Theme.Unpack("muted"))
    end

    local look = ns.Tracker:LookOf(line.item)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", PADDING - 2 + MEDAL + 5, 0)
    row.icon:SetSize(LOOT_ICON, LOOT_ICON)
    row.icon:SetTexture(look.icon or FALLBACK_ICON)
    row.icon:Show()

    row.left:SetTextColor(ItemColor(line.item))

    -- Green and better glow in their own colour.
    local quality = ns.TrackerFX and ns.TrackerFX.QualityOf(line.item) or nil
    if quality and quality >= 2 then
        local r, g, b = ItemColor(line.item)
        row.live:SetColorTexture(1, 1, 1, 1)
        local ok = type(CreateColor) == "function" and pcall(row.live.SetGradient, row.live, "HORIZONTAL",
            CreateColor(r, g, b, 0.26), CreateColor(r, g, b, 0.02))
        if not ok then
            PlainTexture(row.live)
            row.live:SetColorTexture(r, g, b, 0.14)
        end
        row.live:Show()
        row.edge:SetColorTexture(r, g, b, 1)
        row.edge:SetWidth(2)
        row.edge:Show()
    end

    return PADDING - 2 + MEDAL + 5 + LOOT_ICON + 6
end

--- A folded card's loot as small icons, right to left from `stop`.
--- Returns the width they take.
function TrackerUI:DrawMinis(row, names, stop)
    for index, name in ipairs(names) do
        local mini = row.minis[index]
        if not mini then
            mini = row:CreateTexture(nil, "ARTWORK")
            mini:SetSize(MINI, MINI)
            mini:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.minis[index] = mini
        end

        mini:ClearAllPoints()
        mini:SetPoint("RIGHT", row, "RIGHT", -(stop + 2 + (#names - index) * (MINI + 2)), 0)
        mini:SetTexture(ns.Tracker:LookOf(name).icon or FALLBACK_ICON)
        mini:Show()
    end

    return #names * (MINI + 2) + 4
end

--- An open card's loot as bag slots, wrapping to the panel's width.
function TrackerUI:DrawIcons(row, line)
    row.icon:Hide()
    row.left:SetText("")
    row.left:Hide()
    row.right:SetText("")
    row.right:Hide()
    row.badge:Hide()
    row.track:Hide()
    row.fill:Hide()
    for _, part in ipairs(row.progress.parts) do part:Hide() end

    row.needs = PADDING * 2 + SLOT + 8
    row:EnableMouse(false)
    self:Relight(row, false)

    for index, icon in ipairs(line.icons) do
        local slot = self:Slot(row, index)
        slot.line = icon
        slot.icon:SetTexture(ns.Tracker:LookOf(icon.item).icon or FALLBACK_ICON)

        local r, g, b = ItemColor(icon.item)
        local quality = ns.TrackerFX and ns.TrackerFX.QualityOf(icon.item) or nil
        for _, edge in ipairs(slot.borderTextures or {}) do
            if quality and quality >= 1 then
                edge:SetColorTexture(r, g, b, quality >= 2 and 1 or 0.55)
            else
                edge:SetColorTexture(Theme.Unpack("borderLit"))
            end
        end

        -- Green and better keep a soft glow in their colour.
        if quality and quality >= 2 then
            slot.glow:SetColorTexture(r, g, b, 1)
            slot.glow:SetAlpha(quality >= 3 and 0.35 or 0.2)
        else
            slot.glow:SetAlpha(0)
        end
        slot.rest = slot.glow:GetAlpha()

        slot.count:SetText(icon.text or "")
        slot.count:SetTextColor(Theme.Unpack(icon.textColor or "text"))
        if icon.textColor == "good" then slot.count:SetTextColor(0.62, 0.96, 0.75, 1) end
        slot:Show()
    end

    for index = #line.icons + 1, #row.slots do row.slots[index]:Hide() end

    row:Show()
end

--- Put an icons row's slots where they go for `width`.
function TrackerUI:PlaceSlots(row, line, width)
    local perRow = self:SlotsPerRow(width)
    for index = 1, #line.icons do
        local slot = row.slots[index]
        local column = (index - 1) % perRow
        local down = math.floor((index - 1) / perRow)
        slot.baseTo = row
        slot.baseX = PADDING + 5 + column * (SLOT + SLOT_GAP)
        slot.baseY = -(5 + down * (SLOT + SLOT_GAP))
        slot:ClearAllPoints()
        slot:SetPoint("TOPLEFT", row, "TOPLEFT", slot.baseX, slot.baseY)
    end
end

--- How long a row's progress bar is: the panel's width, less the indent
--- and the count.
function TrackerUI:ProgressWidth(row)
    local width = tonumber(self.frame and self.frame:GetWidth()) or self:Width()
    return math.max(20, width - 2 - (row.barLeft or PADDING) - (row.barRight or PADDING))
end

--- A row's progress bar filled to `fraction`, green in the last stretch, as
--- a goal's is (GoalsUI:SetBar).
function TrackerUI:SetProgress(row, fraction, green)
    local bar = row.progress
    local width = self:ProgressWidth(row)
    fraction = math.max(0, math.min(1, tonumber(fraction) or 0))

    bar.fill:SetColorTexture(Theme.Unpack(green and "good" or "accent"))
    bar.fill:SetWidth(math.max(1, width * fraction))
    bar.fill:SetShown(fraction > 0)

    local tip = green and GREEN_TIP or BRIGHT_GOLD
    bar.tip:SetColorTexture(tip[1], tip[2], tip[3], 0.9)
    local moving = fraction > 0.02 and fraction < 1
    bar.tip:SetShown(moving)

    -- The spark in the bar's own colour, shaded again only when that changes:
    -- this runs on every step of a slide.
    local sparkKey = green and "good" or "accent"
    if bar.sparkKey ~= sparkKey then
        Theme.SetGradientAlpha(bar.spark, "HORIZONTAL", sparkKey, 0, 0.55)
        bar.sparkKey = sparkKey
    end
    bar.spark:SetShown(moving)

    for index, at in ipairs(MARKS) do
        local mark = bar.marks[index]
        mark:ClearAllPoints()
        mark:SetPoint("TOPLEFT", bar.track, "TOPLEFT", math.floor(width * at), 0)
    end
end

--------------------------------------------------------------------------------
-- Cards
--
-- An open card sits on a panel of its own with an edge round it: gold with
-- a soft outer glow for the one you are on, plain for the rest.
--------------------------------------------------------------------------------

function TrackerUI:Card(index)
    local card = self.cards[index]
    if card then return card end

    card = CreateFrame("Frame", nil, self.frame)
    card:SetFrameLevel(self.frame:GetFrameLevel() + 1)
    card.fill = Theme.Fill(card, "glassAlt")
    self:AddGlass(card.fill)

    card.edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = card:CreateTexture(nil, "BORDER")

        if side == "TOP" or side == "BOTTOM" then
            edge:SetPoint(side .. "LEFT")
            edge:SetPoint(side .. "RIGHT")
            edge:SetHeight(1)
        else
            edge:SetPoint("TOP" .. side)
            edge:SetPoint("BOTTOM" .. side)
            edge:SetWidth(1)
        end

        card.edges[#card.edges + 1] = edge
    end

    -- The house glow, lit round the card you are on (DrawCard): bright at
    -- its edge and fading out, as round the windows. It was a flat band set
    -- off from the edge, which read as a second, blurry frame.
    Theme.Halo(card, 6, LIVE_HALO)

    self.cards[index] = card
    return card
end

--- Draw a card behind rows `first` to `last` of the ones showing.
function TrackerUI:DrawCard(index, first, last, live)
    local card = self:Card(index)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", first, "TOPLEFT", PADDING - 5, 1)
    card:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", -(PADDING - 5), -1)

    for _, edge in ipairs(card.edges) do
        if live then
            edge:SetColorTexture(Theme.Unpack("accent", 0.95))
        else
            edge:SetColorTexture(Theme.Unpack("border"))
        end
    end
    Theme.SetHalo(card, live and LIVE_HALO or 0)

    card:Show()
end

--------------------------------------------------------------------------------
-- Scrolling
--------------------------------------------------------------------------------

function TrackerUI:ScrollBy(lines)
    local was = self.scroll or 0
    self.scroll = math.max(0, math.min(self.maxScroll or 0, was + (tonumber(lines) or 0)))
    if self.scroll ~= was then self:Arrange() end
end

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------

--- How many there are on each tab, for the numbers beside their names.
function TrackerUI:TabCounts()
    local mobs = 0
    for _ in pairs(ns.Tracker.session or {}) do mobs = mobs + 1 end
    if ns.Fishing then for _ in pairs(ns.Fishing.session or {}) do mobs = mobs + 1 end end
    if ns.Gathering then for _ in pairs(ns.Gathering.session or {}) do mobs = mobs + 1 end end

    local items, looted = {}, 0
    local function Take(counts)
        for name, count in pairs(counts or {}) do
            if ns.Tracker.Counts(name) then
                items[name] = true
                looted = looted + count
            end
        end
    end
    Take(ns.Tracker.sessionLoot)
    if ns.Fishing then Take(ns.Fishing.sessionCatch) end
    if ns.Gathering then Take(ns.Gathering.sessionItems) end

    local distinct = 0
    for _ in pairs(items) do distinct = distinct + 1 end

    return { farm = mobs, loot = distinct }, looted, ns.Tracker:SessionKills()
end

--- A green dot on the tab not showing when something new lands there.
function TrackerUI:NoteDots(looted, kills)
    self.dots = self.dots or {}
    local tab = self:Tab()

    if self.seenLooted and looted > self.seenLooted and tab ~= "loot" then self.dots.loot = true end
    if self.seenKills and kills > self.seenKills and tab ~= "farm" then self.dots.farm = true end

    self.seenLooted, self.seenKills = looted, kills
    self.dots[tab] = nil
end

function TrackerUI:Render()
    self:Build()

    local counts, looted, kills = self:TabCounts()
    self:NoteDots(looted, kills)

    local all = TrackerUI.Stripe(self:Lines())

    -- The gathered value goes in the title bar. The effects see it as the
    -- first line, ahead of the column's.
    local titleLine = self:TitleTotal()
    self.titleLine = titleLine
    local titleNeeds = self:DrawTitle(titleLine)
    local toolbarNeeds = self:DrawToolbar()

    -- The width first: every line drawn once to see what it needs.
    local width = tonumber(self.frame:GetWidth()) or self:Width()
    if not self.sizing then
        local needs = math.max(titleNeeds, toolbarNeeds)
        for _, line in ipairs(all) do
            if line.style ~= "icons" then
                needs = math.max(needs, self:Needs(line))
            end
        end
        -- As wide as the wider tab has needed, so switching tabs never
        -- makes the panel jump.
        self.tabNeeds = self.tabNeeds or {}
        self.tabNeeds[self:Tab()] = needs
        for _, other in pairs(self.tabNeeds) do needs = math.max(needs, other) end
        width = self:FitWidth(needs)
        self.frame:SetWidth(width)
    end

    self.arranged = { all = all, width = width, counts = counts, titleLine = titleLine }
    self:Arrange(true)
end

--- Lays the lines Render worked out into the rows: which show at this
--- scroll, where each sits, and the panel's height. A wheel tick or a
--- drag of the corner grip comes here alone, so the mobs are not priced
--- and every line measured again for a list that only moved (smooth play).
--- `effects` is Render's: the counts changed, so the effects play.
function TrackerUI:Arrange(effects)
    local arranged = self.arranged
    if not arranged then return self:Render() end
    local all, titleLine, counts = arranged.all, arranged.titleLine, arranged.counts
    local width = arranged.width
    if not effects then width = tonumber(self.frame:GetWidth()) or width end
    -- While the grip is held, the panel is whatever size the drag says;
    -- otherwise it is the saved size. The column scrolls within it.
    local limit = self.sizing and self.frame:GetHeight() or self:MaxHeight()
    local room = math.max(LINE * 2, limit - TOP - PADDING * 2)

    -- Heights hang on the width (icon rows wrap), so they are kept for it.
    local heights = arranged.heights
    if not heights or arranged.heightsWidth ~= width then
        heights = {}
        for index, line in ipairs(all) do
            heights[index] = self:LineHeight(line, width)
        end
        arranged.heights, arranged.heightsWidth = heights, width
    end

    -- Scrolled no further than it takes to bring the last line to the
    -- bottom edge. A last line taller than the whole room (an open card's
    -- icons on a short panel) is shown on its own, never scrolled past:
    -- scrolled past, nothing at all was drawn.
    local maxScroll, tail = 0, 0
    for index = #all, 1, -1 do
        tail = tail + heights[index]
        if tail > room then
            maxScroll = math.min(index, #all - 1)
            break
        end
    end
    self.maxScroll = maxScroll
    self.scroll = math.max(0, math.min(self.scroll or 0, maxScroll))

    local shown, used = {}, 0
    for index = self.scroll + 1, #all do
        if used + heights[index] > room and #shown > 0 then break end
        shown[#shown + 1] = all[index]
        used = used + heights[index]
    end

    -- Lines left below take the "more below" strip from the same room, so the
    -- panel is never taller than the height you set.
    if self.scroll + #shown < #all then
        while #shown > 1 and used + MORE_HEIGHT > room do
            used = used - heights[self.scroll + #shown]
            shown[#shown] = nil
        end
    end
    local first = self.scroll + 1
    local below = #all - (self.scroll + #shown)

    self.shown = shown

    local fxAll = { }
    for _, line in ipairs(all) do fxAll[#fxAll + 1] = line end
    local fxShown = shown
    if titleLine then
        table.insert(fxAll, 1, titleLine)
        fxShown = { titleLine }
        for _, line in ipairs(shown) do fxShown[#fxShown + 1] = line end
    end

    local function RowFor(index)
        if titleLine then
            if index == 1 then return self.titleRow end
            index = index - 1
        end
        return self.lines[index]
    end

    -- What went up since the last redraw, worked out before drawing so the
    -- value line can carry its "+38s". Never allowed to stop the panel.
    local FX = ns.TrackerFX
    local plan
    if FX and effects then
        local ok, result = pcall(FX.Prepare, FX, fxAll, fxShown)
        plan = ok and result or nil
        if not ok then ns.Debug("panel effects:", tostring(result)) end

        -- Prepare is what gives the gathered value its "+38s": draw the
        -- title again so the badge is there to show.
        if titleLine and titleLine.badge then self:DrawTitle(titleLine) end
    end

    -- Drawn top down, each row under the last.
    local y = TOP + PADDING
    for index = 1, math.max(#shown, #self.lines) do
        local line = shown[index]

        if line then
            local row = self:Line(index)
            local height = heights[first + index - 1]
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 1, -y)
            row:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -1, -y)
            row:SetHeight(height)
            self:DrawLine(row, line)
            if line.style == "icons" then self:PlaceSlots(row, line, width) end
            y = y + height
        elseif self.lines[index] then
            self.lines[index]:Hide()
        end
    end

    self:DrawCards(shown)
    self:DrawTabs(counts)

    if below > 0 then
        self.moreLabel:SetText(L.Format("%d more below, scroll down", below))
        self.moreLabel:Show()
    else
        self.moreLabel:Hide()
    end
    if self.fadeTop then
        -- The fades are the panel's dark colour, so a see-through panel
        -- leaves them out.
        local clear = self:SeeThroughOn()
        self.fadeTop:SetShown(self.scroll > 0 and not clear)
        self.fadeBottom:SetShown(below > 0 and not clear)
    end

    if not self.sizing then
        self.frame:SetHeight(TOP + PADDING * 2 + used + (below > 0 and MORE_HEIGHT or 0))
    end

    self:FitTitleBadge()
    if self.folded then self:ApplyFold() return end

    -- The progress bars again, now that the panel has its width.
    for index, line in ipairs(shown) do
        if line.style == "progress" then
            self:SetProgress(self.lines[index], line.progress, line.final)
        end
    end

    if plan then
        local ok, err = pcall(FX.Play, FX, plan, RowFor)
        if not ok then ns.Debug("panel effects:", tostring(err)) end
    end

    if effects then self:NoteRanks(shown) end
end

--- How wide the panel must be for `line` to show in full, measured on a
--- spare row that is never shown.
function TrackerUI:Needs(line)
    if not self.measure then
        self.measure = self:CreateLine(self.frame, 0)
    end
    local row = self.measure
    self:DrawLine(row, line)
    row:Hide()
    for _, slot in ipairs(row.slots) do slot:Hide() end
    return row.needs or 0
end

--- Whether the line at `index`, a note or value line at the top of the
--- column, belongs to a card scrolled half out of sight: the card's icons
--- or bar come after it before any band or heading does.
function TrackerUI:InCard(shown, index)
    for next = index + 1, #shown do
        local style = shown[next].style
        if style == "icons" or style == "progress" then return true end
        if style == "mob" or style == "heading" or style == "loot" then return false end
    end
    return false
end

--- The cards behind every open card showing: from its band to its icons.
function TrackerUI:DrawCards(shown)
    local used = 0
    local open

    local function Close(last)
        if not open then return end
        used = used + 1
        self:DrawCard(used, self.lines[open.first], self.lines[last], open.live)
        open = nil
    end

    for index, line in ipairs(shown) do
        if line.style == "mob" or line.style == "heading" or line.style == "loot" then
            Close(index - 1)
            if line.style == "mob" and not line.folded then
                open = { first = index, live = line.live == true }
            end
        elseif not open and (line.style == "place" or line.style == "progress"
            or line.style == "icons"
            or ((line.style == "note" or line.style == "value") and index == 1
                and self:InCard(shown, index))) then
            -- A card scrolled half out of sight: its rest still sits on one.
            open = { first = index, live = false }
        end
        if open and line.style == "icons" then Close(index) end
    end
    Close(#shown)

    for index = used + 1, #self.cards do self.cards[index]:Hide() end
end

--- On the Loot tab, an item that climbs past another floats where it got
--- to (2026-09-28: dopamine hits wherever they fit).
function TrackerUI:NoteRanks(shown)
    if self:Tab() ~= "loot" or self:Sort("loot") ~= "value" then
        self.ranks = nil
        return
    end

    local ranks = {}
    for index, line in ipairs(shown) do
        if line.style == "loot" then
            ranks[line.item] = line.rank
            local was = self.ranks and self.ranks[line.item]
            local FX = ns.TrackerFX
            if was and line.rank < was and FX and FX.Level() == "full" and self.lines[index] then
                pcall(FX.FloatText, FX, Util.Colored("good", L.Format("Up to #%d!", line.rank)),
                    self.lines[index], 0.2, 14)
            end
        end
    end
    self.ranks = ranks
end

--- The gathered value on the title bar's second line; "0c" until something
--- gathered has a price. Returns how wide the panel must be for both title
--- lines to show in full.
function TrackerUI:DrawTitle(line)
    local row = self.titleRow
    -- False rather than nil, so an effect still running on it sees no line.
    row.line = line or false
    self.titleBadgeNeeds = nil

    -- Top line: the title, a gap, and the X with its margins.
    local top = PADDING + 4 + Theme.TextWidth("normal", self.title:GetText()) + 8 + 6 + 18 + 4 + 18 + 6

    local value = line and line.right or (ns.Value and ns.Value.Coins(0) or "0c")
    local valueWidth = Theme.TextWidth("normal", Util.StripColor(value)) + 2
    -- No fixed width: hung from its right edge, it sizes to its text, so
    -- the count-up passing through "99s 87c" on its way to "1g 2s" is
    -- never cut to "99s...".
    row.right:SetWidth(0)
    row.right:SetText(value)
    row.right:SetTextColor(Theme.Unpack(line and (line.rightColor or "good") or "muted"))

    -- Second line: the label, a gap, and the value.
    local labelEnd = 3 + PADDING + 1 + Theme.TextWidth("small", row.left:GetText())
    local second = labelEnd + 12 + valueWidth + PADDING

    local badge = line and line.badge
    local badgeWidth = badge and (Theme.TextWidth("tiny", badge) + 2) or 0
    row.badge:SetWidth(math.max(1, badgeWidth))
    row.badge:SetText(badge or "")
    if badge then self.titleBadgeNeeds = labelEnd + 8 + badgeWidth + 4 + valueWidth + PADDING end

    return math.max(top, second)
end

--- The "+38s" only lasts a few seconds, so the panel does not widen for it:
--- it shows when there is room between the label and the value.
function TrackerUI:FitTitleBadge()
    local row = self.titleRow
    local width = self.frame:GetWidth()
    local needs = self.titleBadgeNeeds

    if needs and type(width) == "number" and needs <= width then
        row.badge:Show()
    else
        row.badge:Hide()
    end
end

--------------------------------------------------------------------------------
-- On and off
--------------------------------------------------------------------------------

--- Fold the panel to its title bar, or open it again (the fold gem; for
--- the session only). A docked goals panel follows it up.
function TrackerUI:SetFolded(on)
    self.folded = on and true or false
    if self.gems then self.gems:SetFolded(self.folded) end
    if not self.folded then
        for _, part in ipairs({ self.tabStrip, self.toolbar, self.rule }) do
            if part then part:Show() end
        end
    end
    if self.frame and self.frame:IsShown() then self:Refresh() end
end

--- Folded: only the title bar shows.
function TrackerUI:ApplyFold()
    for _, part in ipairs({ self.tabStrip, self.toolbar, self.rule, self.moreLabel,
        self.fadeTop, self.fadeBottom }) do
        if part then part:Hide() end
    end
    for _, line in ipairs(self.lines or {}) do line:Hide() end
    for _, card in ipairs(self.cards or {}) do card:Hide() end
    self.frame:SetHeight(HEADER)
end

--- The goals panel hangs under this one until it is dragged, as wide as it
--- is: follow it when it comes back, changes width or goes, so it never
--- hangs under empty space.
local function FollowGoals()
    local goals = ns.GoalsUI
    if goals and goals.frame and goals.frame:IsShown() and not ns.db.goalsX
        and not goals.dragging then
        if goals.lastBase ~= goals:Width() then pcall(goals.Render, goals) end
        pcall(goals.Place, goals)
    end
end

--- For a change made elsewhere, such as the panel's size in Settings.
function TrackerUI:FollowGoals()
    FollowGoals()
end

-- "Hide skinning" moved: the panel's drops (Tracker:Summary) and an open
-- loot table follow it. Nothing is built for it.
ns.DB.hideWatchers.tally = function()
    if TrackerUI.frame then TrackerUI:Refresh() end
end

-- An item's rarity came in late: the lines on screen take its colour,
-- laid out as they are (nothing is priced or measured again).
ns.Util.OnRarity("tracker", function()
    local frame = TrackerUI.frame
    if frame and frame:IsShown() and TrackerUI.arranged then TrackerUI:Arrange(false) end
end)

--- Redraw, and show or hide to match the saved setting.
function TrackerUI:Refresh()
    self:Build()

    -- An open loot table follows the same tally.
    if ns.LootTableUI then ns.LootTableUI:Refresh() end
    if ns.RankingsUI then ns.RankingsUI:Refresh() end

    self:NoteStart()

    if ns.db.trackerHidden then
        self.frame:Hide()
        -- Hidden, nothing plays but the rare-drop chime; shown again, the
        -- counts start from there.
        if ns.TrackerFX then
            ns.TrackerFX:Forget()
            pcall(ns.TrackerFX.HiddenLoot, ns.TrackerFX)
        end
        FollowGoals()
        return
    end

    if ns.TrackerFX and ns.TrackerFX.Shown then ns.TrackerFX:Shown() end

    -- Refresh shows the panel on every redraw; only coming into view fades
    -- it up.
    local opening = not self.frame:IsShown()

    self:Render()
    self.frame:Show()

    -- Up where it is, its glow flaring and settling. It never rises: players
    -- drag it into place.
    if opening and ns.Motion then ns.Motion:Open(self.frame, 0) end

    FollowGoals()
end

--- Forget what the panel remembered about the last session's lines: its
--- widest width on each tab, which cards you opened or folded, the Loot
--- tab's ranks and the scroll. For a reset.
--
-- The per-hour clock is left to NoteStart: a reset clears the kills, but
-- what you fished and gathered is still in the session's value, and timed
-- from the reset, an hour of fishing read as earned in minutes. NoteStart
-- stops the clock itself once nothing is left.
function TrackerUI:ResetState()
    self.tabNeeds = nil
    self.open = nil
    self.ranks = nil
    self.scroll = 0
    self.dots = nil
end

function TrackerUI:Hide()
    if self.frame then self.frame:Hide() end
    if ns.TrackerFX then ns.TrackerFX:Forget() end
end

function TrackerUI:OnEnable()
    self:Refresh()
    self:Place()

    local function Settle() TrackerUI:PlaceSoon() end
    ns.RegisterEvent(self, "GROUP_ROSTER_UPDATE", Settle)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", Settle)
    -- The group frames moved in Edit Mode. Clients without it skip this.
    ns.RegisterEvent(self, "EDIT_MODE_LAYOUTS_UPDATED", Settle)
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

-- After a drag the client re-anchors the panel to whichever corner or edge is
-- nearest, often the bottom or the centre. The panel's height then changes
-- to fit its contents, and a bottom or centre anchor would move its top.
-- Anchor it by its top-left corner instead, where it is now on screen.
-- UIParent's bottom-left is 0,0 in every scale, so the panel's own left and
-- top are the offsets.
function TrackerUI:AnchorTop()
    local frame = self.frame
    if not frame then return end

    local ok, left, top = pcall(function() return frame:GetLeft(), frame:GetTop() end)
    if not (ok and type(left) == "number" and type(top) == "number") then return end

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

function TrackerUI:SavePosition()
    if not (ns.db and self.frame) then return end

    local point, _, relativePoint, x, y = self.frame:GetPoint()

    -- Moved while in a group: that is where it goes in a group from now on,
    -- and the spot it has when you play alone stays as it was.
    if self.grouped then
        ns.db.trackerGroupX = x
        ns.db.trackerGroupY = y
        return
    end

    ns.db.trackerPoint = point
    ns.db.trackerRelativePoint = relativePoint
    ns.db.trackerX = x
    ns.db.trackerY = y
end

function TrackerUI:RestorePosition()
    if not self.frame then return end

    local db = ns.db or {}

    -- The first version sat on the right; move a panel saved there once.
    if db.trackerLayout ~= LAYOUT then
        db.trackerPoint = "TOPLEFT"
        db.trackerRelativePoint = "TOPLEFT"
        db.trackerX = 8
        db.trackerY = -190
        db.trackerLayout = LAYOUT
    end

    local point = db.trackerPoint or "TOPLEFT"

    self.frame:ClearAllPoints()
    self.frame:SetPoint(point, UIParent, db.trackerRelativePoint or point,
        db.trackerX or 8, db.trackerY or -190)

    -- A panel saved by an earlier version may hang from its bottom or centre.
    -- Written straight to the solo spot: SavePosition would put it in the
    -- spot for groups while the panel last stood grouped.
    if point ~= "TOPLEFT" then
        self:AnchorTop()
        local newPoint, _, relativePoint, x, y = self.frame:GetPoint()
        db.trackerPoint = newPoint
        db.trackerRelativePoint = relativePoint
        db.trackerX = x
        db.trackerY = y
    end
end

--------------------------------------------------------------------------------
-- In a group
--------------------------------------------------------------------------------

-- The default spot is right where the party frames are. In a party or raid
-- the panel steps to the right of whichever group frames are showing, and
-- goes back when you are on your own again. Drag it while grouped and it
-- keeps that spot for groups instead (trackerGroupX/Y).
--
-- The panel is a plain frame anchored to UIParent, so moving it in combat is
-- allowed; the group frames are only read, never touched.

-- Blizzard's group frames, newest layout first. Whichever are showing count.
local GROUP_FRAMES = {
    "CompactRaidFrameContainer",
    "CompactPartyFrame",
    "PartyFrame",
    "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4",
}

-- Space left between the group frames and the panel.
local GROUP_GAP = 8

-- How long to let the group frames lay themselves out after a change.
local SETTLE = 0.5

function TrackerUI:InGroup()
    local ok, grouped = pcall(function()
        if IsInRaid and IsInRaid() then return true end
        if IsInGroup and IsInGroup() then return true end
        return (GetNumGroupMembers and GetNumGroupMembers() or 0) > 0
    end)
    return ok and grouped == true
end

function TrackerUI:DodgeGroupOn()
    return not (ns.db and ns.db.trackerDodgeGroup == false)
end

--- A frame's edges in the panel's own units, or nil if it is not on screen.
local function EdgesIn(frame, scale)
    local ok, left, right, top, bottom = pcall(function()
        if not (frame.IsVisible and frame:IsVisible()) then return end
        local own = frame:GetEffectiveScale() / scale
        local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
        -- Compared here, inside the pcall: a secret value raises on it.
        if not (type(l) == "number" and type(r) == "number" and r > l
            and type(t) == "number" and type(b) == "number" and t > b) then
            return
        end
        return l * own, r * own, t * own, b * own
    end)
    if ok and left then return left, right, top, bottom end
end

--- Where the showing group frames are, as one box in the panel's units.
function TrackerUI:GroupFrameBox()
    local ok, scale = pcall(self.frame.GetEffectiveScale, self.frame)
    if not (ok and type(scale) == "number" and scale > 0) then return end

    local box
    for _, name in ipairs(GROUP_FRAMES) do
        local frame = _G[name]
        if frame then
            local left, right, top, bottom = EdgesIn(frame, scale)
            if left then
                if box then
                    box.left = math.min(box.left, left)
                    box.right = math.max(box.right, right)
                    box.top = math.max(box.top, top)
                    box.bottom = math.min(box.bottom, bottom)
                else
                    box = { left = left, right = right, top = top, bottom = bottom }
                end
            end
        end
    end
    return box
end

--- Put the panel where it belongs for being solo or grouped.
function TrackerUI:Place()
    if not self.frame then return end
    -- Never pull it out from under a drag.
    if self.sizing or self.dragging then return end

    self:RestorePosition()

    local db = ns.db or {}
    self.grouped = self:DodgeGroupOn() and self:InGroup()
    if not self.grouped then return end

    if type(db.trackerGroupX) == "number" and type(db.trackerGroupY) == "number" then
        self.frame:ClearAllPoints()
        self.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.trackerGroupX, db.trackerGroupY)
        return
    end

    local box = self:GroupFrameBox()
    if not box then return end

    local ok, left, top = pcall(function() return self.frame:GetLeft(), self.frame:GetTop() end)
    if not (ok and type(left) == "number" and type(top) == "number") then return end

    -- The panel grows downward as it fills, so check the whole height it may
    -- take, not just what it has now.
    local okWidth, width = pcall(self.frame.GetWidth, self.frame)
    if not (okWidth and type(width) == "number") then width = self:Width() end
    local right = left + width
    local bottom = top - self:MaxHeight()
    local overlaps = left < box.right and right > box.left
        and top > box.bottom and bottom < box.top
    if not overlaps then return end

    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", box.right + GROUP_GAP, top)
end

--- Place it again once the group frames have settled. A raid forming
--- raises the roster event dozens of times in a row: one placing waits for
--- the burst, not one per event.
function TrackerUI:PlaceSoon()
    if self.placing then return end
    if C_Timer and type(C_Timer.After) == "function" then
        self.placing = true
        local ok = pcall(C_Timer.After, SETTLE, function()
            TrackerUI.placing = nil
            TrackerUI:Place()
        end)
        if ok then return end
        self.placing = nil
    end
    self:Place()
end

function TrackerUI:SetDodgeGroup(on)
    ns.db.trackerDodgeGroup = on and true or false
    self:Place()
end

--- Forget the spot picked for groups; it goes back beside the group frames.
function TrackerUI:ResetGroupSpot()
    if not ns.db then return end
    ns.db.trackerGroupX = nil
    ns.db.trackerGroupY = nil
end
