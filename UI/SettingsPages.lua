-- Blackthornes Farmer -- UI/SettingsPages.lua
-- The settings window's pages: what Tradeskills' Settings tab got
-- (2026-10-08), brought to Pets, Equipment and Farmer (asked 2026-10-09).
--
--   * Category pages picked along the top, like Tradeskills' Recipes /
--     Recipes to learn switch: gold and underlined when picked, grey until
--     hovered. The page you were on is remembered (settingsPage).
--   * What a setting does is the row's tooltip: the row lights gold under
--     the mouse and says it in white. "Show descriptions" (off by default,
--     settingsDescriptions) puts the words back under every row.
--   * "Find a setting": rows from every page glow where the words match,
--     pages with none dim, and the first page with a match is shown.
--   * Two columns a page, and the window fits its fullest page, so no
--     page scrolls.
--
-- The file is the same in Pets, Equipment and Farmer apart from this
-- header; a fix to it in one belongs in all three.

local _, ns = ...

local SettingsPages = {}
ns.SettingsPages = SettingsPages

-- The words through the addon's translation table where it has one (ns.L,
-- Locale/Locale.lua), else in English, so this file stays the same in all.
local L = ns.L or setmetatable({}, { __index = function(_, key) return key end })

local Theme = ns.Theme
local Widgets = ns.Widgets

local ROW_GAP = -8
local SECTION_GAP = -20
-- The switch along the top, and the room it takes.
local BAR_HEIGHT = 32
-- Between the switch and the search box, and the search box and the tick.
local BAR_GAP = 16
-- Between two names on the switch.
local SWITCH_GAP = 20

local Page = {}
Page.__index = Page

--- The number a client value is, or nil.
local function Number(value)
    return type(value) == "number" and value or nil
end

--- How tall a wrapped label is, or `fallback` when the client cannot say.
local function TextHeight(label, fallback)
    local ok, height = pcall(function() return label:GetStringHeight() end)
    return ok and Number(height) and height > 0 and height or fallback
end

--------------------------------------------------------------------------------
-- Building a window's pages
--------------------------------------------------------------------------------

--- Lay out pages inside `frame`.
--
-- opts:
--   pages        { { key, text, tip }, ... } in switch order; the first is
--                shown until another is picked
--   top          from the window's top to where the switch starts
--   bottom       the room kept under the pages (a footer line)
--   padding      the space at each side of the window
--   columnWidth  how wide each of the two columns is
--   columnGap    between the two columns
--   controlX     where a row's control starts, inside the row
--   db           function() returning the saved table that holds
--                settingsPage and settingsDescriptions
function SettingsPages.New(frame, opts)
    local self = setmetatable({
        frame = frame,
        opts = opts,
        defs = opts.pages,
        pages = {},
        searchables = {},
        switch = {},
    }, Page)

    self.columnX = { opts.padding, opts.padding + opts.columnWidth + opts.columnGap }

    self:BuildBar()

    for _, def in ipairs(opts.pages) do
        local content = CreateFrame("Frame", nil, frame)
        content:SetPoint("TOPLEFT", 0, -(opts.top + BAR_HEIGHT + 14))
        content:SetPoint("TOPRIGHT", 0, -(opts.top + BAR_HEIGHT + 14))
        content:SetHeight(10)
        content:Hide()

        self.pages[def.key] = {
            key = def.key, content = content,
            last = {}, items = { {}, {} }, rows = {},
        }
    end

    return self
end

function Page:DB()
    return self.opts.db() or {}
end

--------------------------------------------------------------------------------
-- Placing things on a page
--------------------------------------------------------------------------------

--- Put `item` under the last thing in a page's column, or at its top, and
--- make it the new last thing there. Its height is read whenever the window
--- is fitted, so a row that grows with its description is measured again.
function Page:Place(pageKey, column, item, gap)
    local page = self.pages[pageKey]
    local last = page.last[column]
    gap = last and (gap or ROW_GAP) or 0

    if last then
        item:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, gap)
    else
        item:SetPoint("TOPLEFT", page.content, "TOPLEFT", self.columnX[column], 0)
    end

    page.last[column] = item
    local list = page.items[column]
    list[#list + 1] = { frame = item, gap = gap }
    return item
end

--- A soft gold frame behind something the search found.
local function AddFoundGlow(page, item)
    local glow = page.content:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("TOPLEFT", item, "TOPLEFT", -6, 3)
    glow:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", 6, -3)
    glow:SetColorTexture(Theme.Unpack("accent"))
    glow:SetAlpha(0.16)
    glow:Hide()
    return glow
end

--- Let the search find `item` by its words.
function Page:Searchable(pageKey, item, words)
    local page = self.pages[pageKey]
    self.searchables[#self.searchables + 1] = {
        page = pageKey,
        frame = item,
        words = (words or ""):lower(),
        glow = AddFoundGlow(page, item),
    }
end

--- A section heading with a rule underneath, next in a page's column.
function Page:Section(pageKey, column, text)
    local page = self.pages[pageKey]
    local section = CreateFrame("Frame", nil, page.content)
    section:SetSize(self.opts.columnWidth, 20)
    section.fixedHeight = 20
    self:Place(pageKey, column, section, SECTION_GAP)

    local heading = Theme.CreateLabel(section, "tiny", "accent")
    heading:SetPoint("TOPLEFT", 0, 0)
    heading:SetText(text)

    local divider = Theme.CreateDivider(section, "border")
    divider:SetPoint("TOPLEFT", 0, -14)
    divider:SetWidth(self.opts.columnWidth)

    return section
end

--- The tooltip a row shows under the mouse: its name in gold, then what it
--- does in white so it reads easily.
local function ShowRowTip(row)
    if not (row.description and row.description ~= "" and GameTooltip) then return end
    if row.pages:DB().settingsDescriptions == true then return end

    GameTooltip:SetOwner(row, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -2)
    GameTooltip:SetText(row.labelText, Theme.Unpack("accent"))
    GameTooltip:AddLine(row.description, 1, 1, 1, true)
    GameTooltip:Show()
end

--- Light a row while the mouse is over it or any control on it. Its
--- controls take the mouse from it, so it checks each frame until the mouse
--- has left the whole row rather than trusting OnLeave.
local function LightRow(row)
    row.hover:Show()
    ShowRowTip(row)
    row:SetScript("OnUpdate", function(self)
        local ok, over = pcall(self.IsMouseOver, self)
        if ok and over then return end
        self:SetScript("OnUpdate", nil)
        self.hover:Hide()
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
end

--- How tall a row is with its description shown, or without.
local function FitRow(row, show)
    if row.hint then row.hint:SetShown(show) end
    row.shownHeight = (show and row.hint) and row.fullHeight or row.compactHeight
    row:SetHeight(row.shownHeight)
end

--- One setting: its name and control on a line. What it does is the row's
--- tooltip, or the lines under it with Show descriptions ticked. Returns
--- the row; anchor the control at controlX inside it.
--
-- `description` may be a function, for words that change (the spec a gear
-- judge picked, say); the row asks again each time it shows them.
function Page:Row(pageKey, column, labelText, description)
    local page = self.pages[pageKey]
    local opts = self.opts

    local row = CreateFrame("Frame", nil, page.content)
    row:SetSize(opts.columnWidth, 24)
    row.pages = self
    self:Place(pageKey, column, row)

    -- Wrapped rather than cut off should a name outgrow its room at the
    -- player's font; the description then starts under its last line.
    local label = Theme.CreateLabel(row, "small", "text")
    label:SetPoint("TOPLEFT", 0, -4)
    label:SetWidth(opts.controlX - 8)
    label:SetText(labelText)

    local top = 24
    if Theme.TextWidth("small", labelText) > opts.controlX - 8 then
        label:SetWordWrap(true)
        top = math.ceil(4 + TextHeight(label, 26) + 6)
    end
    row.compactHeight = top
    row.fullHeight = top
    row.label = label

    -- Lit under the mouse, so it is plain the row has more to say.
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetPoint("TOPLEFT", -6, 2)
    row.hover:SetPoint("BOTTOMRIGHT", 6, -2)
    row.hover:SetColorTexture(Theme.Unpack("accent"))
    row.hover:SetAlpha(0.1)
    row.hover:Hide()

    row.labelText = labelText
    row:EnableMouse(true)
    row:SetScript("OnEnter", LightRow)

    -- "muted" rather than "dim": the small print says what each setting
    -- does, and "dim" was hard to read on the panel (Tradeskills found).
    local hint = Theme.CreateLabel(row, "tiny", "muted")
    hint:SetPoint("TOPLEFT", 0, -top)
    hint:SetWidth(opts.columnWidth)
    hint:SetWordWrap(true)
    row.hint = hint

    --- Change what the row says it does.
    function row:SetDescription(text)
        self.description = text or ""
        hint:SetText(self.description)
        local lines = TextHeight(hint, 13 * math.max(1, math.ceil(
            Theme.TextWidth("tiny", self.description) / opts.columnWidth)))
        self.fullHeight = self.description == "" and top or math.ceil(top + lines + 6)
        local shown = self.pages:DB().settingsDescriptions == true
        FitRow(self, shown)
        -- Words that change once the window is up (the spec a gear judge
        -- picked, say) may need more room under the row.
        if shown and self.pages.fitted then self.pages:Fit() end
    end

    --- Make room for a second line of controls under the first (a Reload
    --- button), the description moving down with it.
    function row:Grow(by)
        top = top + by
        self.compactHeight = top
        hint:ClearAllPoints()
        hint:SetPoint("TOPLEFT", 0, -top)
        self:SetDescription(self.description)
    end

    row:SetDescription(type(description) == "function" and description() or description)
    page.rows[#page.rows + 1] = row
    self:Searchable(pageKey, row, labelText .. " " .. (row.description or ""))

    return row
end

--------------------------------------------------------------------------------
-- The switch, the search and Show descriptions
--------------------------------------------------------------------------------

function Page:BuildBar()
    local frame, opts = self.frame, self.opts

    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", 0, -opts.top)
    bar:SetPoint("TOPRIGHT", 0, -opts.top)
    bar:SetHeight(BAR_HEIGHT)
    self.bar = bar

    local rule = Theme.CreateDivider(bar, "border")
    rule:SetPoint("BOTTOMLEFT", opts.padding, 0)
    rule:SetPoint("BOTTOMRIGHT", -opts.padding, 0)

    for _, def in ipairs(opts.pages) do
        local button = CreateFrame("Button", nil, bar)
        button:SetHeight(22)

        local part = { key = def.key, button = button }
        part.label = Theme.CreateLabel(button, "small", "muted")
        part.label:SetPoint("LEFT", 0, 0)
        part.label:SetText(def.text)

        -- The game's own window tabs glow under the one picked; this does
        -- too, as a gold line with a soft light over it.
        part.underline = button:CreateTexture(nil, "ARTWORK")
        part.underline:SetColorTexture(Theme.Unpack("accent"))
        part.underline:SetHeight(2)
        part.underline:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, 1)
        part.underline:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, 1)
        part.underline:Hide()

        part.glow = button:CreateTexture(nil, "BACKGROUND")
        part.glow:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -4, -1)
        part.glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 4, -1)
        part.glow:SetHeight(12)
        if Theme.SetGradientAlpha then
            Theme.SetGradientAlpha(part.glow, "VERTICAL", "accent", 0.22, 0)
        else
            part.glow:SetColorTexture(Theme.Unpack("accent"))
            part.glow:SetAlpha(0.12)
        end
        part.glow:Hide()

        button:SetScript("OnClick", function() self:Show(def.key) end)
        button:SetScript("OnEnter", function(widget)
            part.hovered = true
            self:Paint()
            if def.tip and GameTooltip then
                GameTooltip:SetOwner(widget, "ANCHOR_BOTTOM")
                GameTooltip:SetText(def.tip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave", function()
            part.hovered = false
            self:Paint()
            if GameTooltip then GameTooltip:Hide() end
        end)

        self.switch[#self.switch + 1] = part
    end

    -- The house order for an option bar: search, then tick boxes.
    self.describe = Widgets.CreateCheckbox(bar, L["Show Descriptions"], function(checked)
        self:DB().settingsDescriptions = checked
        self:ShowDescriptions(checked)
    end, false)
    self.describe:SetPoint("RIGHT", bar, "RIGHT", -opts.padding, 0)

    self.find = Widgets.CreateSearchBox(bar, L["Find a setting"], function(text) self:Search(text) end)
    self.find:SetWidth(170)
    self.find:SetPoint("RIGHT", self.describe, "LEFT", -BAR_GAP, 0)

    self:LayoutSwitch()
end

--- Lay the switch out left to right, each name as wide as it is drawn.
function Page:LayoutSwitch()
    local previous
    for _, part in ipairs(self.switch) do
        part.button:SetWidth(Theme.TextWidth("small", part.label:GetText()) + 4)
        part.button:ClearAllPoints()
        if previous then
            part.button:SetPoint("LEFT", previous, "RIGHT", SWITCH_GAP, 0)
        else
            part.button:SetPoint("LEFT", self.bar, "LEFT", self.opts.padding, 0)
        end
        previous = part.button
    end
end

--- How wide the bar needs the window to be: the switch, the search box and
--- the tick box side by side at the player's font.
function Page:BarWidth()
    local width = self.opts.padding * 2
    for index, part in ipairs(self.switch) do
        width = width + Theme.TextWidth("small", part.label:GetText()) + 4
        if index > 1 then width = width + SWITCH_GAP end
    end
    -- The tick box is its square, a gap and its words.
    local tick = 24 + Theme.TextWidth("small", L["Show Descriptions"])
    return width + BAR_GAP + 170 + BAR_GAP + tick
end

--- The page showing now: the one saved, or the first.
function Page:Current()
    local saved = self:DB().settingsPage
    return self.pages[saved] and saved or self.defs[1].key
end

--- Light the switch: the page showing gold and underlined, a page the
--- search found nothing on dimmed, the rest grey until hovered.
function Page:Paint()
    local current = self:Current()
    for _, part in ipairs(self.switch) do
        local active = part.key == current
        local color = active and "accent"
            or (self.query and not part.found) and "dim"
            or part.hovered and "text"
            or "muted"
        part.label:SetTextColor(Theme.Unpack(color))
        part.underline:SetShown(active)
        part.glow:SetShown(active)
    end
end

--- Show one page and remember it.
function Page:Show(key)
    if not self.pages[key] then key = self.defs[1].key end
    local db = self:DB()
    if db.settingsPage ~= key then db.settingsPage = key end
    for pageKey, page in pairs(self.pages) do
        page.content:SetShown(pageKey == key)
    end
    self.shown = key
    self:Paint()
end

--- Find settings by their words. Each one found glows, each page with none
--- dims on the switch, and when the page showing has none, the first page
--- that does is shown.
function Page:Search(text)
    local query = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    self.query = query ~= "" and query or nil

    local counts = {}
    for _, entry in ipairs(self.searchables) do
        local found = self.query and entry.words:find(self.query, 1, true) ~= nil
        entry.glow:SetShown(found and true or false)
        if found then counts[entry.page] = (counts[entry.page] or 0) + 1 end
    end

    for _, part in ipairs(self.switch) do
        part.found = (counts[part.key] or 0) > 0
    end

    local show = self:Current()
    if self.query and not counts[show] then
        for _, def in ipairs(self.defs) do
            if counts[def.key] then show = def.key break end
        end
    end
    if show ~= self:Current() then self:Show(show) else self:Paint() end
    return counts
end

--- Show or hide the lines under every setting, and fit the window to them.
function Page:ShowDescriptions(show)
    for _, page in pairs(self.pages) do
        for _, row in ipairs(page.rows) do FitRow(row, show) end
    end
    self:Fit()
end

--------------------------------------------------------------------------------
-- Fitting the window
--------------------------------------------------------------------------------

--- How tall something placed on a page is now.
-- Read with rawget: a frame answers a field it lacks with nothing on the
-- client, but a test's stand-in frame answers with a function.
local function HeightOf(item)
    return Number(rawget(item, "shownHeight")) or Number(rawget(item, "fixedHeight"))
        or Number(item:GetHeight()) or 24
end

--- How tall the fullest column on any page is.
function Page:TallestColumn()
    local tallest = 0
    for _, page in pairs(self.pages) do
        for _, list in ipairs(page.items) do
            local height = 0
            for _, entry in ipairs(list) do
                height = height - entry.gap + HeightOf(entry.frame)
            end
            tallest = math.max(tallest, height)
        end
    end
    return tallest
end

--- Size the window to its fullest page and its bar, so every page fits
--- without scrolling and the bar never runs off the edge. The same size on
--- every page, so the window does not jump as the switch is clicked.
function Page:Fit()
    local opts = self.opts
    local height = opts.top + BAR_HEIGHT + 14 + self:TallestColumn() + opts.bottom
    local width = math.max(opts.padding * 2 + opts.columnWidth * 2 + opts.columnGap, self:BarWidth())
    self.fitted = true
    self.frame:SetWidth(math.ceil(width))
    self.frame:SetHeight(math.ceil(height))
    for _, page in pairs(self.pages) do
        page.content:SetHeight(math.ceil(self:TallestColumn()))
    end
end

--- Put the bar back in step with what is saved: the page, the tick box.
function Page:Refresh()
    local db = self:DB()
    self.describe:SetChecked(db.settingsDescriptions == true)
    self:Show(self:Current())
end

--------------------------------------------------------------------------------
-- Text size
--------------------------------------------------------------------------------

-- Stored as words, so a save reads plainly; picked from a drop-down.
SettingsPages.TEXT_SIZES = { "normal", "large", "larger" }
SettingsPages.TEXT_LABELS = { normal = L["Normal"], large = L["Large"], larger = L["Larger"] }

--- Widen `stepper` to its longest word at the player's text size, so a
--- word like "Titanforged" stays inside its box: two 22 px buttons, the
--- gaps beside them and a little room, never under 100.
function SettingsPages.FitStepper(stepper, words)
    local widest = 0
    for _, word in pairs(words) do
        local ok, width = pcall(Theme.TextWidth, "small", word)
        width = ok and Number(width) or 0
        if width > widest then widest = width end
    end
    stepper:SetWidth(math.max(100, math.ceil(widest) + 22 * 2 + 4 * 2 + 12))
end

--- Put a row's Reload button under its control, lined up with the
--- control's right edge, the row a line taller for it. Every Reload in
--- Settings sits the same way, and none runs into a setting's name or the
--- other column.
function SettingsPages.ReloadUnder(row, control, reload)
    reload:ClearAllPoints()
    reload:SetPoint("TOPRIGHT", control, "BOTTOMRIGHT", 0, -4)
    if row.Grow then row:Grow(24) end
end

--- A "Window Size:" stepper on `row`, at `x`: 50% to 150% in steps of 10,
--- the size the window's grip saves (the owner, 2026-10-29: the same row in
--- every addon's WINDOWS section). `get()` reads the saved percent (nil for
--- 100); `set(percent)` keeps it and draws the window at it.
function SettingsPages.WindowSizeControl(row, x, get, set)
    local stepper = Widgets.CreateStepper(row, {
        min = Widgets.SIZE_MIN or 50, max = Widgets.SIZE_MAX or 150, step = 10, value = 100,
        format = function(value) return ("%d%%"):format(value) end,
        onChange = function(value) set(value) end,
    })
    stepper:SetPoint("TOPLEFT", x, 0)
    function stepper:Sync() self:SetValue(tonumber(get()) or 100, true) end
    return stepper
end

--- A "Text size" stepper and its "Reload" button on `row`, at `x`.
-- Returns the stepper; stepper:Sync() puts it back in step with the save.
function SettingsPages.TextSizeControl(row, x, db)
    local sizes = SettingsPages.TEXT_SIZES

    local reload
    local stepper = Widgets.CreateChoice(row, {
        min = 1, max = #sizes, step = 1,
        format = function(value) return SettingsPages.TEXT_LABELS[sizes[value]] end,
        onChange = function(value)
            db().textSize = sizes[value]
            if ns.SharedChoices then ns.SharedChoices:Changed("textSize", sizes[value]) end
            reload:SetShown((Theme.TEXT_STEPS[sizes[value]] or 0) ~= Theme.TextStep())
        end,
    })
    SettingsPages.FitStepper(stepper, SettingsPages.TEXT_LABELS)
    stepper:SetPoint("TOPLEFT", x, -2)

    -- ReloadUI is allowed from a click, and saves everything first.
    reload = Widgets.CreateButton(row, L["Reload"], function()
        if ReloadUI then ReloadUI() end
    end, { width = 60, height = 20 })
    SettingsPages.ReloadUnder(row, stepper, reload)
    reload:Hide()
    stepper.reload = reload

    function stepper:Sync()
        local saved = db().textSize
        local index = 1
        for i, key in ipairs(sizes) do
            if key == saved then index = i end
        end
        self:SetValue(index, true)
        reload:SetShown((Theme.TEXT_STEPS[sizes[index]] or 0) ~= Theme.TextStep())
    end

    return stepper
end
