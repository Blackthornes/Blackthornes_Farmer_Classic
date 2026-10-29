-- Blackthornes Farmer -- UI/Rankings.lua
-- The Rankings tab of the main window: mobs by what a kill is worth.
--
-- Two boards, never one. Measured values come from your own kills, coin and
-- all; estimates come from the database's rates, one of each drop and no coin,
-- so they run low. Ranked together an estimate would sit under a mob worth
-- less, so each has its own heading, its own ranks and its own colour, and the
-- estimate's number carries a "~" so it cannot pass for a measured one.
--
-- Below the measured board are the mobs you have started on: not ranked yet,
-- with how many kills each still needs.

local _, ns = ...
local L = ns.L

local RankingsUI = ns.NewModule("RankingsUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local PADDING = 14
local ROW_HEIGHT = 20
local COLUMN_GAP = 6
local BAR_WIDTH = 46

-- What the window adds around the columns: padding, the list's insets and its
-- scrollbar. The same as the search tab's, so the two line up.
local CHROME = 74

local COLUMN_ORDER = { "rank", "mob", "worth", "basis", "best", "where", "level" }
local BASE_WIDTH = { rank = 24, mob = 160, worth = 130, basis = 64, best = 130, where = 170, level = 46 }
local MAX_WIDTH = { mob = 300, worth = 200, basis = 110, best = 240, where = 340 }

local FILTERS = {
    { label = L["ALL"], group = false },
    { label = L["MEASURED"], group = "measured" },
    { label = L["ESTIMATES"], group = "estimate" },
    { label = L["WORLD DROPS"], group = "worlddrops" },
}

local HEADINGS = {
    measured = { L["YOUR KILLS"], L["measured, coin included"] },
    estimate = { L["ESTIMATES"], L["from the usual drop rates without coin, so they run low"] },
    pending = { L["NOT RANKED YET"], L["keep killing"] },
    worlddrops = { L["WORLD DROPS"], L["green gear and better, by mob level"] },
}

-- The World Drops chip has a layout of its own (the owner, 2026-10-17, from
-- a mockup): four tiles on top, one for each colour, and a row per level
-- band with its kills, greens, a bar, the percent and "1 in X". The bar's
-- column takes whatever room the window has left, so the window keeps its
-- size when the chip changes.
local WORLD_ORDER = { "level", "kills", "greens", "chance", "pct", "onein" }
local WORLD_BASE = { level = 140, kills = 60, greens = 56, chance = 160, pct = 52, onein = 96 }
local WORLD_RIGHT = { kills = true, greens = true, pct = true, onein = true }
local WORLD_BAR_HEIGHT = 8
local TILE_GAP = 8
local TILE_QUALITIES = { 2, 3, 4, 5 }

--- Column left edges and widths for the given widths.
local function Columns(widths, order, base)
    local columns, x = {}, 0

    for _, key in ipairs(order or COLUMN_ORDER) do
        local w = widths and widths[key] or (base or BASE_WIDTH)[key]
        columns[key] = { x = x, w = w }
        x = x + w + COLUMN_GAP
    end

    columns.total = x - COLUMN_GAP
    return columns
end

local function WorldColumns(widths)
    return Columns(widths, WORLD_ORDER, WORLD_BASE)
end

--- How tall a colour tile is at this text size: its name, its count and a
--- line under them.
local function TileHeight()
    return 7 + Theme.sizes.tiny + 3 + Theme.sizes.title + 3 + Theme.sizes.small + 7
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

--- Build the tab's contents into `frame`, the main window. Hidden until the
--- tab is chosen.
function RankingsUI:Build(frame)
    if self.view then return self.view end

    self.group = nil

    local view = CreateFrame("Frame", nil, frame)
    view:SetAllPoints(frame)
    self.view = view

    -- Up in the window's top row, where the Search tab has its box: beside
    -- the portrait and level with the Settings button.
    local filters = CreateFrame("Frame", nil, view)
    local left, top = ns.UI.HEAD_LEFT or PADDING, (ns.UI.HEAD_TOP or 45) + 3
    filters:SetPoint("TOPLEFT", left, -top)
    if ns.UI.settingsButton then
        filters:SetPoint("TOPRIGHT", ns.UI.settingsButton, "TOPLEFT", -8, -3)
    else
        filters:SetPoint("TOPRIGHT", -PADDING, -top)
    end
    filters:SetHeight(18)
    self.filters = filters

    self.chips = {}
    local offset = 0

    for index, entry in ipairs(FILTERS) do
        local chip = Widgets.CreateChip(filters, entry.label, function(clicked)
            RankingsUI.group = clicked:GetFilterKind()
            RankingsUI:Render()
        end)
        chip.filterKind = entry.group
        chip:SetWidth(math.max(34, Theme.TextWidth("tiny", entry.label) + 16))
        chip:SetPoint("LEFT", filters, "LEFT", offset, 0)
        offset = offset + chip:GetWidth() + 4
        self.chips[index] = chip
    end

    -- Mobs found only in dungeons and raids left out (the owner, 2026-10-14),
    -- after the chips. Off unless ticked; Rankings:SetOutsideOnly redraws.
    local outside = Widgets.CreateCheckbox(filters, L["Outside dungeons only"], function(checked)
        ns.Rankings:SetOutsideOnly(checked)
        if ns.SettingsUI then ns.SettingsUI:Refresh() end
    end, ns.Rankings.OutsideOnly())
    outside:SetPoint("LEFT", filters, "LEFT", offset + 8, 0)
    outside:HookScript("OnEnter", function(box)
        if not GameTooltip then return end
        GameTooltip:SetOwner(box, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(L["Rankings leave out mobs you only found in dungeons and raids."], 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    outside:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    self.outside = outside
    offset = offset + 8 + outside:GetWidth()

    -- Uncommon and better drops left out of worth per kill (the owner,
    -- 2026-10-18). Off unless ticked; Rankings:SetSkipUncommon redraws.
    local uncommon = Widgets.CreateCheckbox(filters, L["Skip Uncommon and better"], function(checked)
        ns.Rankings:SetSkipUncommon(checked)
        if ns.SettingsUI then ns.SettingsUI:Refresh() end
    end, ns.Rankings.SkipUncommon())
    uncommon:SetPoint("LEFT", filters, "LEFT", offset + 12, 0)
    uncommon:HookScript("OnEnter", function(box)
        if not GameTooltip then return end
        GameTooltip:SetOwner(box, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(L["Worth per kill leaves out Uncommon, Rare and Epic drops."], 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    uncommon:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    self.uncommon = uncommon
    offset = offset + 12 + uncommon:GetWidth()

    -- Every drop at what a vendor pays (the owner, 2026-10-27). Off unless
    -- ticked. Ticked from here, the board comes in fresh and the mobs that
    -- climb show "+N" for a moment (RankingsUI:NoteClimbs). The top row is
    -- full, so it starts a second line under the chips.
    local vendor = Widgets.CreateCheckbox(filters, L["Vendor only"], function(checked)
        RankingsUI:NoteClimbs()
        ns.Rankings:SetVendorOnly(checked)
        RankingsUI:Render(true)
        if ns.SettingsUI then ns.SettingsUI:Refresh() end
    end, ns.Rankings.VendorOnly())
    vendor:SetPoint("TOPLEFT", filters, "BOTTOMLEFT", 0, -4)
    vendor:HookScript("OnEnter", function(box)
        if not GameTooltip then return end
        GameTooltip:SetOwner(box, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(L["Worth per kill uses what a vendor pays, not the auction house."], 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    vendor:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    self.vendor = vendor
    self.headOffset = offset

    -- Where the prices come from, on the right of the chips.
    local summary = Theme.CreateLabel(view, "small", "muted", "RIGHT")
    summary:SetPoint("LEFT", filters, "LEFT", offset + 8, 0)
    summary:SetPoint("RIGHT", filters, "RIGHT", -2, 0)
    self.summary = summary

    -- Below the portrait, as wide as the Search tab's results.
    self.panelTop = top + 18 + 4 + 18 + 8
    local panel = Theme.CreatePanel(view, "panel", "border")
    self.panel = panel
    self:PlacePanel(false)

    -- The World Drops tiles sit where the panel's top was; the panel moves
    -- down under them while they show.
    local tiles = CreateFrame("Frame", nil, view)
    tiles:SetPoint("TOPLEFT", view, "TOPLEFT", PADDING, -self.panelTop)
    tiles:SetPoint("TOPRIGHT", view, "TOPRIGHT", -PADDING, -self.panelTop)
    tiles:SetHeight(TileHeight())
    tiles:SetScript("OnSizeChanged", function() RankingsUI:PlaceTiles() end)
    tiles:Hide()
    self.tiles = tiles
    self.tileFrames = {}
    for index, quality in ipairs(TILE_QUALITIES) do
        self.tileFrames[index] = self:CreateTile(tiles, quality)
    end
    -- Sunk into the window, as the game's inset panels sit (Titanforged).
    if Theme.Recess then Theme.Recess(panel) end

    self.headings = {}
    for key, text in pairs({ rank = "#", mob = L["MOB"], worth = L["PER KILL"], basis = L["FROM"],
        best = L["BEST DROP"], where = L["WHERE"], level = L["LEVEL"] }) do
        -- "#" sits over the ranks' right edge; the sort arrow goes before it.
        local label = Theme.CreateLabel(panel, "tiny", "dim", key == "rank" and "RIGHT" or nil)
        label:SetText(text)
        self.headings[key] = label
    end

    self.columns = Columns()
    self:PlaceHeadings()

    -- Click a heading to sort each board by it (a player's request,
    -- 2026-10-11), as the search's headings do. The boards stay apart and
    -- each mob keeps its rank and medal. Kept in `rankingsSort`.
    local key, ascending = self:SortChoice()
    self.sorter = Widgets.SortableHeadings(self.headings, {
        rank = L["Sort by rank, best first: the usual order."],
        mob = L["Sort by mob name, A to Z."],
        worth = L["Sort by what a kill is worth, best first."],
        basis = L["Sort by how many you have killed, most first."],
        best = L["Sort by the best drop's name, A to Z."],
        where = L["Sort by where it is, A to Z."],
        level = L["Sort by level, lowest first."],
    }, function(newKey, newAscending)
        if ns.db then
            ns.db.rankingsSort = newKey and { key = newKey, ascending = newAscending } or nil
        end
        RankingsUI:Resort()
    end, { startsLow = RankingsUI.SORT_STARTS_LOW, key = key, ascending = ascending })

    -- The World Drops chip's own headings, sorted on their own and kept in
    -- `rankingsWorldSort`. The best chance comes first until one is clicked.
    self.worldHeadings = {}
    for wkey, text in pairs({ level = L["MOB LEVELS"], kills = L["KILLS"], greens = L["UNCOMMON"],
        chance = L["UNCOMMON CHANCE"], pct = "%", onein = L["1 IN"] }) do
        local label = Theme.CreateLabel(panel, "tiny", "dim", WORLD_RIGHT[wkey] and "RIGHT" or nil)
        label:SetText(text)
        label:Hide()
        self.worldHeadings[wkey] = label
    end
    self.worldColumns = WorldColumns()
    self:PlaceWorldHeadings()

    local worldKey, worldAscending = self:WorldSortChoice()
    local chanceTip = L["Sort by the chance of an uncommon, best first."]
    self.worldSorter = Widgets.SortableHeadings(self.worldHeadings, {
        level = L["Sort by mob level, lowest first."],
        kills = L["Sort by kills, most first."],
        greens = L["Sort by uncommon drops, most first."],
        chance = chanceTip,
        pct = chanceTip,
        onein = L["Sort by how many kills an uncommon takes, fewest first."],
    }, function(newKey, newAscending)
        if ns.db then
            ns.db.rankingsWorldSort = newKey and { key = newKey, ascending = newAscending } or nil
        end
        RankingsUI:Resort()
    end, { startsLow = RankingsUI.WORLD_STARTS_LOW, key = worldKey, ascending = worldAscending })
    self:ShowHeadings(false)

    local rule = Theme.CreateDivider(panel, "border")
    rule:SetPoint("TOPLEFT", 8, -20)
    rule:SetPoint("TOPRIGHT", -8, -20)

    local list = Widgets.CreateRowList(panel, {
        rowHeight = ROW_HEIGHT,
        createRow = function(row) RankingsUI:CreateRow(row) end,
        updateRow = function(row, data, index) RankingsUI:UpdateRow(row, data, index) end,
        onClick = function(data, button) RankingsUI:OnRowClick(data, button) end,
        onEnter = function(row, data)
            if data.entry then
                ns.UI:ShowMobTooltip(row, data.entry.mob, true, data.entry)
                if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(row) then
                    GameTooltip:AddLine(L["Click for its loot."], Theme.Unpack("dim"))
                    GameTooltip:Show()
                end
            end
        end,
        onLeave = function() if GameTooltip then GameTooltip:Hide() end end,
        -- The colour of the well the rows sit in.
        fadeKey = "well",
    })
    list:SetPoint("TOPLEFT", 8, -24)
    list:SetPoint("BOTTOMRIGHT", -8, 8)
    self.list = list

    -- Clear of the version in the window's corner (UI/Main.lua).
    local footer = Theme.CreateLabel(view, "tiny", "dim")
    footer:SetPoint("BOTTOMLEFT", PADDING, 6)
    footer:SetPoint("BOTTOMRIGHT", -(PADDING + (ns.UI.VERSION_ROOM or 0)), 6)
    footer:SetHeight(26)
    footer:SetWordWrap(true)
    footer:SetJustifyV("MIDDLE")
    -- The count only; what a click does is on each row's hover (2026-10-29).
    footer:SetText(L.Format("Ranked after %d kills.", ns.Tracker.MIN_KILLS))
    self.footer = footer

    view:Hide()
    return view
end

function RankingsUI:PlaceHeadings()
    for key, label in pairs(self.headings) do
        local column = self.columns[key]
        local x, w = column.x, column.w
        if key == "level" then
            -- Centred over its column by width, so the sort arrow, placed
            -- after the words, stays clear of them (as the Grind tab's).
            local text = math.ceil(Theme.TextWidth("tiny", label:GetText() or "")) + 2
            x, w = x + math.max(0, math.floor((w - text) / 2)), math.min(w, text)
        end
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", 8 + x, -8)
        label:SetWidth(w)
    end
end

function RankingsUI:PlaceWorldHeadings()
    for key, label in pairs(self.worldHeadings) do
        local column = self.worldColumns[key]
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", 8 + column.x, -8)
        label:SetWidth(column.w)
    end
end

--- The mob boards' headings, or the World Drops chip's, with their sort
--- buttons: a hidden heading's button must not take clicks either.
function RankingsUI:ShowHeadings(world)
    local function Show(labels, sorter, shown)
        for key, label in pairs(labels) do
            if shown then label:Show() else label:Hide() end
            local button = sorter and sorter.buttons[key]
            if button then
                if shown then button:Show() else button:Hide() end
            end
        end
    end
    Show(self.headings, self.sorter, not world)
    Show(self.worldHeadings, self.worldSorter, world)
end

--- The list's panel, under the World Drops tiles while they show.
function RankingsUI:PlacePanel(world)
    local panel = self.panel
    local top = self.panelTop + (world and (TileHeight() + TILE_GAP) or 0)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", self.view, "TOPLEFT", PADDING, -top)
    panel:SetPoint("BOTTOMRIGHT", self.view, "BOTTOMRIGHT", -PADDING, 36)
end

--------------------------------------------------------------------------------
-- World Drops tiles
--------------------------------------------------------------------------------

--- A gradient from `from` to `to` alpha in one colour, or a flat wash where
--- the client has no gradients.
local function Wash(texture, orientation, r, g, b, from, to)
    local ok = type(CreateColor) == "function" and pcall(texture.SetGradient, texture,
        orientation, CreateColor(r, g, b, from), CreateColor(r, g, b, to))
    if not ok then texture:SetColorTexture(r, g, b, math.max(from, to) * 0.4) end
end

--- One colour's tile: dark glass with an edge of its colour on top, which
--- lights up once you have had one.
function RankingsUI:CreateTile(parent, quality)
    local rgb = RankingsUI.QUALITY_RGB[quality]
    local tile = CreateFrame("Frame", nil, parent)
    tile:SetHeight(TileHeight())

    tile.background = tile:CreateTexture(nil, "BACKGROUND")
    tile.background:SetAllPoints(tile)
    tile.background:SetColorTexture(Theme.Unpack("glass"))

    -- A soft light of its colour falling from the top edge.
    tile.glow = tile:CreateTexture(nil, "BACKGROUND", nil, 1)
    tile.glow:SetAllPoints(tile)
    tile.glow:SetColorTexture(1, 1, 1, 1)
    Wash(tile.glow, "VERTICAL", rgb[1], rgb[2], rgb[3], 0, 0.22)
    tile.glow:Hide()

    tile.edge = tile:CreateTexture(nil, "ARTWORK")
    tile.edge:SetPoint("TOPLEFT")
    tile.edge:SetPoint("TOPRIGHT")
    tile.edge:SetHeight(2)
    tile.edge:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)

    tile.line = tile:CreateTexture(nil, "ARTWORK")
    tile.line:SetPoint("BOTTOMLEFT")
    tile.line:SetPoint("BOTTOMRIGHT")
    tile.line:SetHeight(1)
    tile.line:SetColorTexture(Theme.Unpack("border", 0.6))

    local names = { [2] = L["Uncommon"], [3] = L["Rare"], [4] = L["Epic"], [5] = L["Legendary"] }
    tile.name = Theme.CreateLabel(tile, "tiny", "text")
    tile.name:SetPoint("TOPLEFT", 10, -7)
    tile.name:SetText(names[quality])
    tile.name:SetTextColor(rgb[1], rgb[2], rgb[3])

    tile.count = Theme.CreateLabel(tile, "title", "text")
    tile.count:SetPoint("TOPLEFT", 10, -(7 + Theme.sizes.tiny + 3))
    tile.count:SetPoint("RIGHT", -8, 0)

    tile.note = Theme.CreateLabel(tile, "small", "muted")
    tile.note:SetPoint("TOPLEFT", 10, -(7 + Theme.sizes.tiny + 3 + Theme.sizes.title + 3))
    tile.note:SetPoint("RIGHT", -8, 0)

    tile.quality = quality
    return tile
end

--- The four tiles side by side, sharing the width.
function RankingsUI:PlaceTiles()
    local width = self.tiles:GetWidth()
    if type(width) ~= "number" or width <= 0 then return end
    local each = math.floor((width - TILE_GAP * (#self.tileFrames - 1)) / #self.tileFrames)
    for index, tile in ipairs(self.tileFrames) do
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", self.tiles, "TOPLEFT", (index - 1) * (each + TILE_GAP), 0)
        tile:SetWidth(each)
    end
end

--- What each tile says, from the bands: { [quality] = { count, note, lit } }.
function RankingsUI.TileTexts(data)
    local texts = {}
    for _, quality in ipairs(TILE_QUALITIES) do
        local count = data and data.drops[quality] or 0
        local note
        if not data or data.measured == 0 then
            note = L["Needs more kills"]
        elseif count == 0 then
            note = L.Format("None yet in %d kills", data.measured)
        else
            note = L.Format("%1$s, 1 in %2$d kills", RankingsUI.Percent(count, data.measured),
                ns.WorldDrops.OneIn(data.measured, count))
        end
        texts[quality] = { count = tostring(count), note = note, lit = count > 0 }
    end
    return texts
end

function RankingsUI:FillTiles(data)
    local texts = RankingsUI.TileTexts(data)
    for _, tile in ipairs(self.tileFrames) do
        local text = texts[tile.quality]
        tile.count:SetText(text.count)
        tile.count:SetTextColor(Theme.Unpack(text.lit and "text" or "dim"))
        tile.note:SetText(text.note)
        if text.lit then tile.glow:Show() else tile.glow:Hide() end
        tile.edge:SetAlpha(text.lit and 1 or 0.4)
    end
end

--------------------------------------------------------------------------------
-- Sorting by the headings
--------------------------------------------------------------------------------

-- What each heading sorts by, and the ones that start lowest first: rank,
-- names and level; worth and kills start with the biggest.
RankingsUI.SORT_KEYS = { rank = true, mob = true, worth = true, basis = true, best = true,
    where = true, level = true }
RankingsUI.SORT_STARTS_LOW = { rank = true, mob = true, best = true, where = true, level = true }

local SORT_VALUE = {
    rank = function(entry) return entry.rank end,
    mob = function(entry) return entry.mob end,
    worth = function(entry) return entry.value end,
    basis = function(entry) return entry.kills end,
    best = function(entry) return entry.best and entry.best.name end,
    where = function(entry) return entry.where end,
    level = function(entry) return entry.minLevel end,
}

--- The sort the headings were left on: key (nil for the usual order) and
--- ascending. Kept in `rankingsSort`.
function RankingsUI:SortChoice()
    local saved = ns.db and type(ns.db.rankingsSort) == "table" and ns.db.rankingsSort or {}
    if not RankingsUI.SORT_KEYS[saved.key or ""] then return nil, false end
    return saved.key, saved.ascending and true or false
end

-- The World Drops headings: level and "1 in" start lowest first, the rest
-- with the biggest. Chance and percent sort the same way.
RankingsUI.WORLD_SORT_KEYS = { level = true, kills = true, greens = true, chance = true, pct = true,
    onein = true }
RankingsUI.WORLD_STARTS_LOW = { level = true, onein = true }

local WORLD_SORT_VALUE = {
    level = function(row) return row.band.band end,
    kills = function(row) return row.kills end,
    greens = function(row) return row.greens end,
    chance = function(row) return row.rate end,
    pct = function(row) return row.rate end,
    onein = function(row) return row.oneIn end,
}

function RankingsUI:WorldSortChoice()
    local saved = ns.db and type(ns.db.rankingsWorldSort) == "table" and ns.db.rankingsWorldSort or {}
    if not RankingsUI.WORLD_SORT_KEYS[saved.key or ""] then return nil, false end
    return saved.key, saved.ascending and true or false
end

--- The band rows in the order the headings ask for. The usual order is the
--- best chance first; bands still short on kills go last, lowest first.
function RankingsUI:SortWorld(rows)
    local key, ascending = self:WorldSortChoice()
    if not key then return Util.SortBy(rows, false, WORLD_SORT_VALUE.chance) end
    return Util.SortBy(rows, ascending, WORLD_SORT_VALUE[key])
end

--- One board's entries in the order the headings ask for, as a new list.
function RankingsUI:SortEntries(entries)
    local key, ascending = self:SortChoice()
    if not key then return entries end
    return Util.SortBy(entries, ascending, SORT_VALUE[key])
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

-- The top three of each board: gold, silver and bronze.
local MEDALS = {
    { 1.00, 0.82, 0.30 },
    { 0.78, 0.80, 0.84 },
    { 0.80, 0.52, 0.30 },
}
RankingsUI.MEDALS = MEDALS

function RankingsUI:CreateRow(row)
    -- A board's heading sits on a band, as the search tab's items do.
    row.band = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.band:SetAllPoints(row)
    row.band:SetColorTexture(Theme.Unpack("header"))

    -- The house glow: gold fading across the band from its stripe.
    row.bandGlow = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.bandGlow:SetAllPoints(row)
    row.bandGlow:SetColorTexture(1, 1, 1, 1)
    do
        local r, g, b = Theme.Unpack("accent")
        local ok = type(CreateColor) == "function" and pcall(row.bandGlow.SetGradient, row.bandGlow,
            "HORIZONTAL", CreateColor(r, g, b, 0.16), CreateColor(r, g, b, 0))
        if not ok then row.bandGlow:SetColorTexture(r, g, b, 0.05) end
    end
    row.bandGlow:Hide()

    -- The top three glow faintly in their medal's colour.
    row.podium = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.podium:SetAllPoints(row)
    row.podium:SetColorTexture(1, 1, 1, 1)
    row.podium:Hide()

    row.bandStripe = row:CreateTexture(nil, "ARTWORK")
    row.bandStripe:SetPoint("TOPLEFT")
    row.bandStripe:SetPoint("BOTTOMLEFT")
    row.bandStripe:SetWidth(2)
    row.bandStripe:SetColorTexture(Theme.Unpack("accent", 0.8))

    -- A medal behind the top three ranks.
    row.medal = row:CreateTexture(nil, "ARTWORK")
    row.medal:SetSize(16, 14)

    row.heading = Theme.CreateLabel(row, "small", "accent")
    row.heading:SetPoint("LEFT", 8, 0)
    row.heading:SetPoint("RIGHT", -2, 0)

    row.rank = Theme.CreateLabel(row, "small", "dim", "RIGHT")
    row.mob = Theme.CreateLabel(row, "small", "text")

    row.barTrack = row:CreateTexture(nil, "ARTWORK")
    row.barTrack:SetSize(BAR_WIDTH, 6)
    row.barTrack:SetColorTexture(Theme.Unpack("row"))

    row.barFill = row:CreateTexture(nil, "OVERLAY")
    row.barFill:SetHeight(6)

    row.worth = Theme.CreateLabel(row, "small", "good")
    row.basis = Theme.CreateLabel(row, "small", "muted")
    row.best = Theme.CreateLabel(row, "small", "muted")
    row.where = Theme.CreateLabel(row, "small", "muted")
    row.level = Theme.CreateLabel(row, "small", "text", "CENTER")

    -- The World Drops chip's cells.
    row.wLevel = Theme.CreateLabel(row, "small", "text")
    row.wKills = Theme.CreateLabel(row, "small", "muted", "RIGHT")
    row.wGreens = Theme.CreateLabel(row, "small", "text", "RIGHT")
    row.wPct = Theme.CreateLabel(row, "small", "text", "RIGHT")
    row.wOneIn = Theme.CreateLabel(row, "small", "text", "RIGHT")

    row.wTrack = row:CreateTexture(nil, "ARTWORK")
    row.wTrack:SetHeight(WORLD_BAR_HEIGHT)
    row.wTrack:SetColorTexture(Theme.Unpack("well"))
    -- A soft glow under the bar, the house neon.
    row.wGlow = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.wGlow:SetHeight(WORLD_BAR_HEIGHT + 8)
    row.wGlow:SetColorTexture(1, 1, 1, 1)
    pcall(row.wGlow.SetBlendMode, row.wGlow, "ADD")
    row.wFill = row:CreateTexture(nil, "OVERLAY")
    row.wFill:SetHeight(WORLD_BAR_HEIGHT)

    -- BEST and YOUR LEVEL, after the band's name.
    row.wTags = {}
    for index = 1, 2 do
        local tag = { back = row:CreateTexture(nil, "ARTWORK"), text = Theme.CreateLabel(row, "tiny", "ink", "CENTER") }
        tag.back:SetHeight(Theme.sizes.tiny + 4)
        tag.text:SetPoint("CENTER", tag.back, "CENTER", 0, 0)
        row.wTags[index] = tag
    end

    self:PlaceRow(row)
end

-- The tags a band row can wear, by kind.
local WORLD_TAGS = {
    best = { text = L["BEST"], back = "accent", backAlpha = 1, color = "ink" },
    yours = { text = L["YOUR LEVEL"], back = "good", backAlpha = 0.2, color = "good" },
}

--- How wide a tag is for its words.
local function TagWidth(kind)
    return Theme.TextWidth("tiny", WORLD_TAGS[kind].text) + 10
end

--- Row `row`'s World Drops cells where the current layout puts them.
function RankingsUI:PlaceWorldRow(row)
    local columns = self.worldColumns
    if row.worldLayout == columns then return end
    row.worldLayout = columns

    local function Place(region, key, width)
        region:ClearAllPoints()
        region:SetPoint("LEFT", columns[key].x, 0)
        region:SetWidth(width or columns[key].w)
    end

    Place(row.wLevel, "level")
    Place(row.wKills, "kills")
    Place(row.wGreens, "greens")
    Place(row.wPct, "pct")
    Place(row.wOneIn, "onein")
    local bar = math.max(20, columns.chance.w - 8)
    Place(row.wTrack, "chance", bar)
    row.wFill:ClearAllPoints()
    row.wFill:SetPoint("LEFT", columns.chance.x, 0)
    row.wGlow:ClearAllPoints()
    row.wGlow:SetPoint("LEFT", columns.chance.x - 3, 0)
    row.barMost = bar
end

local WORLD_CELLS = { "wLevel", "wKills", "wGreens", "wPct", "wOneIn", "wTrack", "wGlow", "wFill" }

--- Row `row`'s columns where the current layout puts them.
function RankingsUI:PlaceRow(row)
    local columns = self.columns
    if row.layout == columns then return end
    row.layout = columns

    local function Place(region, key, offset, width)
        region:ClearAllPoints()
        region:SetPoint("LEFT", columns[key].x + (offset or 0), 0)
        region:SetWidth(width or columns[key].w)
    end

    Place(row.rank, "rank", 0, columns.rank.w - 4)
    row.medal:ClearAllPoints()
    row.medal:SetPoint("RIGHT", row, "LEFT", columns.rank.x + columns.rank.w + 1, 0)
    Place(row.mob, "mob")
    Place(row.barTrack, "worth", 0, BAR_WIDTH)
    row.barFill:ClearAllPoints()
    row.barFill:SetPoint("LEFT", columns.worth.x, 0)
    Place(row.worth, "worth", BAR_WIDTH + 6, columns.worth.w - BAR_WIDTH - 6)
    Place(row.basis, "basis")
    Place(row.best, "best")
    Place(row.where, "where")
    Place(row.level, "level")
end

local CELLS = { "rank", "mob", "barTrack", "barFill", "worth", "basis", "best", "where", "level" }

--- The texts a mob's row shows, by column; shared by drawing and fitting.
local function EntryTexts(data)
    local entry = data.entry
    local texts = { mob = ns.Tracker.ShowKey(entry.mob), where = entry.where or "", level = entry.level or "" }

    if entry.group == "pending" then
        texts.worth = entry.unpriced and L["no prices yet"]
            or L.Format("%d more to go", entry.needed)
        texts.basis = Util.Plural(entry.kills, L["kill"], L["kills"])
        texts.best = ""
        return texts
    end

    texts.rank = tostring(entry.rank)
    local climb = RankingsUI:ClimbOf(entry)
    if climb then texts.mob = texts.mob .. "  " .. Util.Colored("good", "+" .. climb) end
    texts.best = entry.best and entry.best.name or ""

    if entry.group == "measured" then
        texts.worth = ns.Value.Coins(entry.value)
        texts.basis = Util.Plural(entry.kills, L["kill"], L["kills"])
    else
        texts.worth = "~" .. ns.Value.Coins(entry.value)
        texts.basis = L["estimate"]
    end

    return texts
end

function RankingsUI:UpdateRow(row, data, index)
    self:PlaceRow(row)

    row.heading:Hide()
    row.band:Hide()
    row.bandGlow:Hide()
    row.podium:Hide()
    row.bandStripe:Hide()
    row.medal:Hide()
    for _, key in ipairs(CELLS) do row[key]:Hide() end
    for _, key in ipairs(WORLD_CELLS) do row[key]:Hide() end
    for _, tag in ipairs(row.wTags) do tag.back:Hide(); tag.text:Hide() end

    if data.type == "wband" then
        self:UpdateWorldBand(row, data, index)
        return
    end

    if data.type == "wnote" then
        -- What greens add to a kill, on a gold wash like the best band's.
        local medal = MEDALS[1]
        Wash(row.podium, "HORIZONTAL", medal[1], medal[2], medal[3], 0.16, 0)
        row.podium:Show()
        row.heading:SetTextColor(Theme.Unpack("text"))
        row.heading:SetText(data.text)
        row.heading:Show()
        return
    end

    if data.type == "heading" then
        row.band:Show()
        row.bandGlow:Show()
        row.bandStripe:Show()
        local heading = HEADINGS[data.group]
        row.heading:SetTextColor(Theme.Unpack("accent"))
        row.heading:SetText(("%s  %s"):format(heading[1],
            Util.Colored("muted", "(" .. (data.note or heading[2]) .. ")")))
        row.heading:Show()
        return
    end

    if data.type == "note" then
        row.heading:SetTextColor(Theme.Unpack("muted"))
        row.heading:SetText("     " .. data.text)
        row.heading:Show()
        return
    end

    if data.type == "band" or data.type == "rare" then
        self:UpdateWorldRow(row, data, index)
        return
    end

    local entry = data.entry
    local texts = EntryTexts(data)
    local measured = entry.group == "measured"

    for _, key in ipairs({ "mob", "basis", "best", "where", "level" }) do
        row[key]:SetText(texts[key])
        row[key]:Show()
    end

    row.mob:SetTextColor(Theme.Unpack(entry.group == "pending" and "muted" or "text"))
    row.best:SetTextColor(Theme.Unpack(entry.group == "pending" and "dim" or "muted"))
    -- The best drop in its rarity colour, once the game says what that is.
    if entry.best and entry.best.name then
        local r, g, b = ns.Util.ItemRGB(entry.best.name, entry.best.id)
        if r then row.best:SetTextColor(r, g, b) end
    end

    if entry.group == "pending" then
        -- No worth yet, so no bar: just how far there is to go.
        row.worth:SetText(texts.worth)
        row.worth:SetTextColor(Theme.Unpack("dim"))
        row.worth:Show()
        return
    end

    row.rank:SetText(texts.rank)
    -- The top three of a board wear gold, silver and bronze.
    local medal = MEDALS[entry.rank]
    row.rank:ClearAllPoints()
    if medal then
        row.rank:SetTextColor(0.06, 0.06, 0.07)
        row.medal:SetColorTexture(medal[1], medal[2], medal[3], measured and 0.95 or 0.6)
        row.medal:Show()
        -- The number sits in the middle of its medal.
        row.rank:SetPoint("CENTER", row.medal, "CENTER", 0, 0)
        row.rank:SetJustifyH("CENTER")

        local r, g, b = medal[1], medal[2], medal[3]
        local peak = measured and 0.14 or 0.07
        local ok = type(CreateColor) == "function" and pcall(row.podium.SetGradient, row.podium,
            "HORIZONTAL", CreateColor(r, g, b, peak), CreateColor(r, g, b, 0))
        if not ok then row.podium:SetColorTexture(r, g, b, peak * 0.4) end
        row.podium:Show()
    else
        row.rank:SetTextColor(Theme.Unpack("dim"))
        row.rank:SetPoint("LEFT", self.columns.rank.x, 0)
        row.rank:SetJustifyH("RIGHT")
    end
    row.rank:Show()

    local color = measured and "good" or "accent"
    local share = data.top > 0 and entry.value / data.top or 0
    local width = math.max(1, BAR_WIDTH * share)
    local fill = row.barFill

    row.barTrack:Show()
    fill:SetColorTexture(Theme.Unpack(color, measured and 1 or 0.6))
    fill:Show()

    -- A board shown fresh grows its bars from nothing, top down.
    if self.arriving and index then
        ns.Motion:Run(row, "bar", 0.5, function(p) fill:SetWidth(math.max(1, width * p)) end,
            { delay = 0.1 + math.min(index - 1, 14) * 0.025 })
    else
        ns.Motion:Stop(row, "bar")
        fill:SetWidth(width)
    end

    row.worth:SetText(texts.worth)
    row.worth:SetTextColor(Theme.Unpack(measured and "good" or "muted"))
    row.worth:Show()
end

-- The colours of green, blue, purple and orange gear.
local QUALITY_RGB = {
    [2] = { 0.12, 1.00, 0.00 },
    [3] = { 0.00, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 },
    [5] = { 1.00, 0.50, 0.00 },
}
RankingsUI.QUALITY_RGB = QUALITY_RGB

--- A world drops row: a level band's chance of green gear, its bar against
--- the best band, or one of the rarer colours over every measured kill.
function RankingsUI:UpdateWorldRow(row, data, index)
    row.mob:SetText(data.label)
    row.mob:SetTextColor(Theme.Unpack("text"))
    if data.quality then
        local rgb = QUALITY_RGB[data.quality]
        row.mob:SetTextColor(rgb[1], rgb[2], rgb[3])
    end
    row.mob:Show()

    row.worth:SetText(data.text)
    row.worth:SetTextColor(Theme.Unpack(data.share and "good" or "dim"))
    row.worth:Show()

    if data.share then
        local rgb = QUALITY_RGB[2]
        local width = math.max(1, BAR_WIDTH * data.share)
        local fill = row.barFill
        row.barTrack:Show()
        fill:SetColorTexture(rgb[1], rgb[2], rgb[3], 0.9)
        fill:Show()
        if self.arriving and index then
            ns.Motion:Run(row, "bar", 0.5, function(p) fill:SetWidth(math.max(1, width * p)) end,
                { delay = 0.1 + math.min(index - 1, 14) * 0.025 })
        else
            ns.Motion:Stop(row, "bar")
            fill:SetWidth(width)
        end
    end

    -- The best band for greens glows gold, as the top of a board does.
    if data.best then
        local medal = MEDALS[1]
        local ok = type(CreateColor) == "function" and pcall(row.podium.SetGradient, row.podium,
            "HORIZONTAL", CreateColor(medal[1], medal[2], medal[3], 0.14),
            CreateColor(medal[1], medal[2], medal[3], 0))
        if not ok then row.podium:SetColorTexture(medal[1], medal[2], medal[3], 0.06) end
        row.podium:Show()
    end
end

--- A World Drops band row: kills, greens, a bar against the best band,
--- the percent and "1 in X". A band short on kills shows how far it has to
--- go instead.
function RankingsUI:UpdateWorldBand(row, data, index)
    self:PlaceWorldRow(row)
    local measured = data.measured

    row.wLevel:SetText(data.label)
    row.wLevel:SetTextColor(Theme.Unpack(measured and "text" or "muted"))
    row.wKills:SetText(data.killsText)
    row.wGreens:SetText(data.greensText)
    row.wGreens:SetTextColor(Theme.Unpack(measured and (data.greens or 0) > 0 and "text" or "dim"))
    row.wPct:SetText(data.pct or "")
    local green = QUALITY_RGB[2]
    if data.rate and data.rate > 0 then
        row.wPct:SetTextColor(green[1], green[2], green[3])
    else
        row.wPct:SetTextColor(Theme.Unpack("dim"))
    end
    row.wOneIn:SetText(data.oneInText)
    row.wOneIn:SetTextColor(Theme.Unpack(data.oneIn and "text" or "dim"))
    for _, key in ipairs({ "wLevel", "wKills", "wGreens", "wPct", "wOneIn", "wTrack" }) do row[key]:Show() end

    -- BEST and YOUR LEVEL just after the band's name.
    local x = self.worldColumns.level.x + Theme.TextWidth("small", data.label) + 8
    local slot = 0
    for _, kind in ipairs({ "best", "yours" }) do
        if data[kind] then
            slot = slot + 1
            local tag, look = row.wTags[slot], WORLD_TAGS[kind]
            local width = TagWidth(kind)
            tag.back:ClearAllPoints()
            tag.back:SetPoint("LEFT", row, "LEFT", x, 0)
            tag.back:SetWidth(width)
            tag.back:SetColorTexture(Theme.Unpack(look.back, look.backAlpha))
            tag.text:SetText(look.text)
            tag.text:SetTextColor(Theme.Unpack(look.color))
            tag.back:Show()
            tag.text:Show()
            x = x + width + 4
        end
    end

    -- The share of the bar: the chance against the best band's, or how many
    -- kills a band short on them has of the ones it needs.
    local share = measured and (data.share or 0) or (data.progress or 0)
    local width = (row.barMost or 100) * share
    local fill, glow = row.wFill, row.wGlow
    if measured then
        fill:SetColorTexture(green[1], green[2], green[3], 0.95)
        glow:SetColorTexture(green[1], green[2], green[3], 0.22)
    else
        fill:SetColorTexture(Theme.Unpack("dim", 0.6))
    end
    local function Grow(w)
        fill:SetWidth(math.max(1, w))
        glow:SetWidth(math.max(1, w) + 6)
    end
    if width >= 1 then
        fill:Show()
        if measured then glow:Show() end
        if self.arriving and index then
            ns.Motion:Run(row, "bar", 0.5, function(p) Grow(width * p) end,
                { delay = 0.1 + math.min(index - 1, 14) * 0.025 })
        else
            ns.Motion:Stop(row, "bar")
            Grow(width)
        end
    end

    -- The best band wears gold, as the top of a board does.
    if data.best then
        local medal = MEDALS[1]
        Wash(row.podium, "HORIZONTAL", medal[1], medal[2], medal[3], 0.16, 0)
        row.podium:Show()
        row.bandStripe:Show()
    end
end

--- A chance as a percent: "4.3%", "12%", "0%"; nil with no kills.
function RankingsUI.Percent(drops, kills)
    if not kills or kills <= 0 then return nil end
    local percent = (drops or 0) / kills * 100
    if percent <= 0 then return "0%" end
    if percent >= 10 then return ("%d%%"):format(math.floor(percent + 0.5)) end
    if percent >= 0.1 then return ("%.1f%%"):format(percent) end
    return "<0.1%"
end

--- The bands and what they add up to, or nil while World Drops is off:
--- { bands, total, measured, drops = { [quality] = n }, best, bestRate }.
--- Only bands with enough kills count toward the drops.
function RankingsUI:WorldData()
    local WorldDrops = ns.WorldDrops
    if not (WorldDrops and WorldDrops:IsEnabled()) then return nil end

    local data = { bands = WorldDrops:Bands(), total = 0, measured = 0,
        drops = { [2] = 0, [3] = 0, [4] = 0, [5] = 0 } }
    for _, entry in ipairs(data.bands) do
        data.total = data.total + entry.kills
        if WorldDrops.Measured(entry) then
            data.measured = data.measured + entry.kills
            for quality in pairs(data.drops) do
                data.drops[quality] = data.drops[quality] + (entry.drops[quality] or 0)
            end
            local rate = entry.drops[2] / entry.kills
            if rate > 0 and (not data.bestRate or rate > data.bestRate) then
                data.best, data.bestRate = entry, rate
            end
        end
    end
    return data
end

--- What greens add to a kill where they drop most, as a line, or nil.
local function WorthLine(data)
    local worth = data.best and ns.WorldDrops.GreenWorth(data.best)
    if not (worth and worth > 0) then return nil end
    return L.Format("Uncommon drops add about %1$s a kill at %2$s.", ns.Value.Coins(worth),
        ns.WorldDrops.BandLabel(data.best.band))
end

--- The band of the character's own level, or nil.
local function PlayerBand()
    local ok, level = pcall(UnitLevel, "player")
    if not ok then return nil end
    return ns.WorldDrops.Band(level)
end

--- The World Drops chip's rows: a row per band in the headings' order and
--- the greens worth line. The tiles are filled from `data`.
function RankingsUI:WorldViewRows(data)
    local WorldDrops = ns.WorldDrops
    if #data.bands == 0 then
        return { { type = "note", text = L["No kills with a level yet."] } }
    end

    local yours = PlayerBand()
    local bands = {}
    for _, entry in ipairs(data.bands) do
        local row = { type = "wband", band = entry, label = WorldDrops.BandLabel(entry.band),
            kills = entry.kills, measured = WorldDrops.Measured(entry),
            best = entry == data.best or nil, yours = entry.band == yours or nil }
        if row.measured then
            local greens = entry.drops[2] or 0
            row.greens = greens
            row.rate = greens / entry.kills
            row.pct = RankingsUI.Percent(greens, entry.kills)
            row.oneIn = WorldDrops.OneIn(entry.kills, greens)
            row.share = data.bestRate and row.rate / data.bestRate or 0
            row.killsText = tostring(entry.kills)
            row.greensText = tostring(greens)
            row.oneInText = row.oneIn and L.Format("1 in %d", row.oneIn) or L["None yet"]
        else
            row.progress = math.min(1, entry.kills / WorldDrops.MIN_KILLS)
            row.killsText = L.Format("%1$d of %2$d", entry.kills, WorldDrops.MIN_KILLS)
            row.greensText = "-"
            row.oneInText = L["Needs more kills"]
        end
        bands[#bands + 1] = row
    end

    local rows = self:SortWorld(bands)
    local worth = WorthLine(data)
    if worth then rows[#rows + 1] = { type = "wnote", text = worth } end
    return rows
end

--- The world drops rows under ALL (Logic/WorldDrops.lua): a heading, a row
--- per level band, the rarer colours and what greens add to a kill where
--- they drop most. Nil while it is turned off.
function RankingsUI:WorldRows(onlyWithKills)
    local data = self:WorldData()
    if not data then return nil end
    local WorldDrops = ns.WorldDrops
    local bands = data.bands

    -- Under ALL it shows once there is something to show.
    if onlyWithKills and #bands == 0 then return nil end
    local rows = {}

    rows[1] = { type = "heading", group = "worlddrops",
        note = L.Format("green gear, from %d kills", data.total) }

    if #bands == 0 then
        rows[2] = { type = "note", text = L["No kills with a level yet."] }
        return rows
    end

    for _, entry in ipairs(bands) do
        local text, share
        if not WorldDrops.Measured(entry) then
            text = L.Format("needs more kills (%d)", entry.kills)
        elseif entry.drops[2] == 0 then
            text = L.Format("none in %d", entry.kills)
        else
            text = L.Format("1 in %1$d (%2$s)", WorldDrops.OneIn(entry.kills, entry.drops[2]),
                RankingsUI.Percent(entry.drops[2], entry.kills))
            share = (entry.drops[2] / entry.kills) / data.bestRate
        end
        rows[#rows + 1] = { type = "band", label = WorldDrops.BandLabel(entry.band),
            text = text, share = share, best = entry == data.best or nil, band = entry }
    end

    if data.measured > 0 then
        local names = { [3] = L["Rare"], [4] = L["Epic"], [5] = L["Legendary"] }
        for _, quality in ipairs({ 3, 4, 5 }) do
            local n = data.drops[quality]
            rows[#rows + 1] = { type = "rare", quality = quality, label = names[quality],
                text = n > 0 and L.Format("%1$d in %2$d kills", n, data.measured)
                    or L.Format("none yet in %d kills", data.measured) }
        end
    end

    local worth = WorthLine(data)
    if worth then rows[#rows + 1] = { type = "note", text = worth } end

    return rows
end

--- A mob you have killed opens its loot table; one you have not says so.
function RankingsUI:OnRowClick(data, button)
    if not data.entry then return end

    -- Right-click offers to hide the mob (HideMenu).
    if button == "RightButton" then
        -- What a click does comes first (2026-10-29).
        ns.HideMenu:Open({
            { kind = "action", text = L["Open Loot Table"],
                run = function() RankingsUI:OnRowClick(data, "LeftButton") end },
            { kind = "source", name = ns.Tracker.NameOf(data.entry.mob) } })
        return
    end

    local mob = data.entry.mob
    if ns.LootTableUI and ns.LootTableUI:Show(mob) then return end

    ns.Print(L.Format("%s: no kills yet, so no loot table. Its worth is an estimate from the usual drop rates.",
        Util.Colored("accent", ns.Tracker.ShowKey(mob))))
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

--- What the mobs not ranked yet are waiting on, when it is not only kills:
--- a mob with its kills but nothing priced waits on prices.
local function PendingNote(entries)
    local kills, prices = false, false
    for _, entry in ipairs(entries) do
        if entry.unpriced then prices = true else kills = true end
    end
    if not prices then return nil end
    return kills and L["waiting on kills or prices"] or L["waiting on prices"]
end

--- The board as list rows, for the chosen filter, or with `all` for
--- every chip but World Drops (what the columns are measured on).
function RankingsUI:Rows(board, all)
    local rows = {}
    local wanted = not all and self.group or nil

    -- The World Drops chip has its own layout: tiles and band rows.
    if self.world and not all then return self:WorldViewRows(self.world) end

    local function Add(group, emptyText)
        local entries = board[group]
        if #entries == 0 and not emptyText then return end

        rows[#rows + 1] = { type = "heading", group = group,
            note = group == "pending" and PendingNote(entries) or nil }

        if #entries == 0 then
            rows[#rows + 1] = { type = "note", text = emptyText }
            return
        end

        -- The bars are measured against the board's best, wherever the
        -- sort has put it.
        local top = 0
        for _, entry in ipairs(entries) do
            if (entry.value or 0) > top then top = entry.value end
        end
        for _, entry in ipairs(self:SortEntries(entries)) do
            rows[#rows + 1] = { type = "mob", entry = entry, top = top }
        end
    end

    if not wanted or wanted == "measured" then
        Add("measured", L.Format("Nothing yet. Kill a mob %d times to rank it.",
            ns.Tracker.MIN_KILLS))
    end

    if not wanted or wanted == "estimate" then
        Add("estimate", L["None of the usual drop rates has a price yet."])
    end

    if not wanted or wanted == "measured" then
        Add("pending")
    end

    if not wanted or wanted == "worlddrops" then
        for _, row in ipairs(self:WorldRows(not wanted) or {}) do rows[#rows + 1] = row end
    end

    return rows
end

--- Widen the columns to fit these rows, and return the window width they want.
--- All, Measured and Estimates are measured on the whole board, so a
--- column stays put when the chip changes (2026-10-22: From, Best drop and
--- Where moved with each).
function RankingsUI:FitColumns(rows)
    if self.world then return self:FitWorldColumns(rows) end
    if self.group and self.board then rows = self:Rows(self.board, true) end
    local widths = {}
    for key, w in pairs(BASE_WIDTH) do widths[key] = w end

    for _, row in ipairs(rows) do
        if row.type == "mob" then
            local texts = EntryTexts(row)
            for _, key in ipairs({ "mob", "basis", "best", "where" }) do
                widths[key] = math.max(widths[key], Theme.TextWidth("small", texts[key]) + 8)
            end
            if texts.worth then
                widths.worth = math.max(widths.worth,
                    Theme.TextWidth("small", texts.worth) + BAR_WIDTH + 12)
            end
            -- A long board's ranks run to three figures: "100" was cut off.
            if texts.rank then
                widths.rank = math.max(widths.rank, Theme.TextWidth("small", texts.rank) + 8)
            end
        elseif row.type == "band" or row.type == "rare" then
            widths.mob = math.max(widths.mob, Theme.TextWidth("small", row.label) + 8)
            widths.worth = math.max(widths.worth, Theme.TextWidth("small", row.text) + BAR_WIDTH + 12)
        end
    end

    for key, most in pairs(MAX_WIDTH) do
        widths[key] = math.min(most, math.ceil(widths[key]))
    end

    -- Never wider than the screen, as the search tab: on a small screen, or
    -- with the window scaled up, the widest columns give back room (their
    -- text ends in "...") before the close button goes off the edge.
    local room = ns.UI and ns.UI.ScreenRoom and ns.UI:ScreenRoom()
    if room then
        local over = Columns(widths).total + CHROME - room
        for _, key in ipairs({ "where", "best", "mob", "worth", "basis" }) do
            if over <= 0 then break end
            local give = math.min(over, widths[key] - BASE_WIDTH[key])
            if give > 0 then
                widths[key] = widths[key] - give
                over = over - give
            end
        end
    end

    -- Every tab shares one width: the room past what the board needs goes
    -- to the best drop and where columns.
    local natural = Columns(widths).total + CHROME
    local shared = RankingsUI.Claim(math.max(natural, self:HeadWidth()))
    local spare = shared - natural
    if spare > 0 then
        local half = math.floor(spare / 2)
        widths.best = widths.best + half
        widths.where = widths.where + (spare - half)
    end

    local current = self.columns
    local changed = false
    for _, key in ipairs(COLUMN_ORDER) do
        if current[key].w ~= widths[key] then changed = true end
    end

    if changed then
        self.columns = Columns(widths)
        self:PlaceHeadings()
    end

    return math.max(shared, self.columns.total + CHROME)
end

--- The window's shared width, grown to `width` when that is more (see
--- UI:Claim); just `width` before the window is built.
function RankingsUI.Claim(width)
    if ns.UI and ns.UI.Claim then return ns.UI:Claim(width) end
    return width
end

--- Widen the World Drops columns to fit these rows and the tiles, and
--- return the window width they want. The window never shrinks for it: the
--- bar's column takes whatever room is left.
function RankingsUI:FitWorldColumns(rows)
    local widths = {}
    for key, w in pairs(WORLD_BASE) do widths[key] = w end

    -- Room for each heading and its sort arrow.
    for key, label in pairs(self.worldHeadings) do
        widths[key] = math.max(widths[key], Theme.TextWidth("tiny", label:GetText()) + 14)
    end

    for _, row in ipairs(rows) do
        if row.type == "wband" then
            local level = Theme.TextWidth("small", row.label) + 8
            for _, kind in ipairs({ "best", "yours" }) do
                if row[kind] then level = level + TagWidth(kind) + 4 end
            end
            widths.level = math.max(widths.level, level)
            widths.kills = math.max(widths.kills, Theme.TextWidth("small", row.killsText) + 8)
            widths.greens = math.max(widths.greens, Theme.TextWidth("small", row.greensText) + 8)
            widths.pct = math.max(widths.pct, Theme.TextWidth("small", row.pct or "") + 8)
            widths.onein = math.max(widths.onein, Theme.TextWidth("small", row.oneInText) + 8)
        end
    end
    for key in pairs(widths) do widths[key] = math.ceil(widths[key]) end

    -- Each tile wide enough for its line, so none is cut.
    local tileText = 0
    for _, text in pairs(RankingsUI.TileTexts(self.world)) do
        tileText = math.max(tileText, Theme.TextWidth("small", text.note))
    end
    local tiles = (tileText + 20) * #TILE_QUALITIES + TILE_GAP * (#TILE_QUALITIES - 1) + PADDING * 2

    local want = math.max(WorldColumns(widths).total + CHROME, tiles, ns.UI and ns.UI.BASE_WIDTH or 0)
    -- Every tab shares one width; the chance column takes what is spare.
    want = RankingsUI.Claim(math.max(want, self:HeadWidth()))
    local room = ns.UI and ns.UI.ScreenRoom and ns.UI:ScreenRoom()
    if type(room) == "number" then want = math.max(math.min(want, room), WorldColumns(widths).total + CHROME) end

    widths.chance = widths.chance + math.max(0, want - CHROME - WorldColumns(widths).total)
    self.worldColumns = WorldColumns(widths)
    self:PlaceWorldHeadings()
    return want
end

--- How wide the window must be for the top row: the chips, the tick box
--- and the price note beside them, clear of the Settings button. German
--- runs longer, and the note would end in "..." otherwise.
function RankingsUI:HeadWidth()
    local button = ns.UI and ns.UI.settingsButton
    local right = (button and button:GetWidth() or 0) + 8 + PADDING
    return (ns.UI.HEAD_LEFT or PADDING) + (self.headOffset or 0) + 8
        + Theme.TextWidth("small", self:PriceText()) + 6 + right
end

function RankingsUI:PriceText()
    if ns.Rankings.VendorOnly() then return L["vendor prices"] end
    local source = ns.Value:PriceSource()
    if source == "tradeskills" then
        return L["Tradeskills auction prices"]
    elseif source then
        return L["TSM or Auctionator auction prices"]
    end
    return L["vendor prices, Tradeskills not loaded"]
end

-- How long a climb's "+N" stays after the Vendor only box is ticked.
RankingsUI.CLIMB_SHOWS = 4

--- Keep each mob's place on the board shown now, so the board drawn next
--- can say who climbed. Cleared CLIMB_SHOWS seconds later.
function RankingsUI:NoteClimbs()
    local places = {}
    for _, group in ipairs({ "measured", "estimate" }) do
        for _, entry in ipairs(self.board and self.board[group] or {}) do
            if entry.rank then places[group .. "\t" .. entry.mob] = entry.rank end
        end
    end
    self.climbs = places
    local stamp = {}
    self.climbStamp = stamp
    if C_Timer and type(C_Timer.After) == "function" then
        pcall(C_Timer.After, self.CLIMB_SHOWS, function()
            if RankingsUI.climbStamp ~= stamp then return end
            RankingsUI.climbs, RankingsUI.climbStamp = nil, nil
            if RankingsUI.list and RankingsUI.view and RankingsUI.view:IsShown() then RankingsUI.list:Refresh() end
        end)
    end
end

--- How many places a mob climbed since NoteClimbs, or nil.
function RankingsUI:ClimbOf(entry)
    local was = self.climbs and entry.rank and self.climbs[(entry.group or "") .. "\t" .. entry.mob]
    if was and was > entry.rank then return was - entry.rank end
    return nil
end

--- A click on a heading: the board already built, in the new order, from
--- the top. Nothing is priced or counted again.
function RankingsUI:Resort()
    if not (self.view and self.view:IsShown() and self.board) then return end
    self:ShowWorld()
    local rows = self:Rows(self.board)
    local width = math.max(self:FitColumns(rows), self:HeadWidth())
    self.list:SetData(rows)
    if ns.UI and ns.UI.frame and ns.UI.tab == "rankings" then ns.UI:ApplySize() end
end

--- The World Drops chip's tiles and headings, or the boards': read the
--- bands once into `self.world` (nil on the other chips, or while World
--- Drops is turned off).
function RankingsUI:ShowWorld()
    local world = self.group == "worlddrops" and self:WorldData() or nil
    self.world = world
    local on = world ~= nil
    if self.shownWorld ~= on then
        self.shownWorld = on
        self:PlacePanel(on)
        self:ShowHeadings(on)
        if on then
            self.tiles:Show()
            self:PlaceTiles()
        else
            self.tiles:Hide()
        end
    end
    if world then self:FillTiles(world) end
end

--- Rebuild the board and draw it. Returns the window width it wants.
function RankingsUI:Render(arrive)
    if not self.view then return end

    for _, chip in ipairs(self.chips) do
        chip:SetSelected(chip:GetFilterKind() == self.group)
    end
    if self.outside then self.outside:SetChecked(ns.Rankings.OutsideOnly()) end
    if self.uncommon then self.uncommon:SetChecked(ns.Rankings.SkipUncommon()) end
    if self.vendor then self.vendor:SetChecked(ns.Rankings.VendorOnly()) end

    self:ShowWorld()
    local board = ns.Rankings:Build()
    self.board = board
    local rows = self:Rows(board)

    local width = math.max(self:FitColumns(rows), self:HeadWidth())

    -- The board comes in row by row when the tab is opened or the filter
    -- changes; a kill that redraws it while you look just redraws.
    local fresh = arrive or self.shownGroup ~= self.group
    self.shownGroup = self.group
    self.arriving = fresh
    -- A redraw after a kill keeps your place on the board.
    self.list:SetData(rows, not fresh)
    self.arriving = false
    if fresh then self.list:Arrive() end
    self.summary:SetText(self:PriceText())

    -- The window grows to fit, never narrower than the search tab's base.
    if ns.UI and ns.UI.frame and ns.UI.tab == "rankings" then ns.UI:ApplySize() end

    return width
end

-- "Hide skinning" moved: leather counts toward a kill's worth or not.
ns.DB.hideWatchers.rankings = function() RankingsUI:Refresh() end

-- An item's rarity came in late: the rows on screen take its colour.
ns.Util.OnRarity("rankings", function()
    local self = RankingsUI
    if self.view and self.view:IsShown() and self.list and ns.UI.frame and ns.UI.frame:IsShown() then
        self.list:Refresh()
    end
end)

--- Redraw if the tab is on screen: a kill can change the board. The board
--- prices every rated mob, so a burst of loot gets one redraw, not one each.
function RankingsUI:Refresh()
    if not (self.view and self.view:IsShown() and ns.UI.frame:IsShown()) then return end
    if self.pending then return end
    if C_Timer and type(C_Timer.After) == "function" then
        self.pending = true
        local ok = pcall(C_Timer.After, 0.2, function()
            RankingsUI.pending = nil
            if RankingsUI.view and RankingsUI.view:IsShown() and ns.UI.frame:IsShown() then
                RankingsUI:Render()
            end
        end)
        if ok then return end
        self.pending = nil
    end
    self:Render()
end
