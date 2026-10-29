-- Blackthornes Farmer -- UI/LootTable.lua
-- One mob's whole loot table, in its own window.
--
-- The kills and loot panel has room for each mob's three most common drops.
-- Click a mob there (or its "Show all" line, or type /farm loot <mob>) and this
-- lists everything it has ever dropped for you: how many corpses held each
-- item, how many you took in all, the drop rate once there are enough kills
-- for one, and what each item adds to a kill when it can be priced.
--
-- It follows the tally as you farm: loot the mob with this open and the table
-- updates.

local _, ns = ...
local L = ns.L

local LootTableUI = ns.NewModule("LootTableUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

-- At least this wide; wider when an item's name needs it, up to MAX_WIDTH.
local WIDTH = 460
local MAX_WIDTH = 760
-- It is as tall as its rows, between these, and scrolls past the tallest.
local MIN_HEIGHT = 240
local MAX_HEIGHT = 460
local PADDING = 14
local HEADER = 32
-- The gold rim round the window reaches this far in (UI/Titanforged.lua);
-- the column titles' band stops short of it.
local EDGE = 6
local ROW = 20
local ICON = 16

-- Header, the numbers, the status line, where it was killed and the column
-- titles above the list; the price note under it.
-- The status line has room for two lines of text, so it wraps rather than
-- being cut off. The places get a second line only when the widest window
-- cannot fit them on one, and the titles and the list move down for it.
local STATUS_TOP = HEADER + 50
local STATUS_HEIGHT = 30
local PLACES_TOP = STATUS_TOP + STATUS_HEIGHT + 2
local PLACES_HEIGHT = 14
local COLUMNS_TOP = PLACES_TOP + PLACES_HEIGHT + 6

-- How many places the "Killed at" line names before "+N more".
local PLACES_SHOWN = 3
local TOP = COLUMNS_TOP + ROW + 4
local BOTTOM = 34

-- The number columns, right to left, in pixels.
local COLUMNS = {
    { key = "perKill", title = L["PER KILL"], width = 70 },
    { key = "rate",    title = L["RATE"],     width = 50 },
    { key = "total",   title = L["TOTAL"],    width = 44 },
    -- "123 of 1204" once a mob passes a hundred kills.
    { key = "dropped", title = L["DROPPED"],  width = 84 },
}
local GAP = 6

local FALLBACK_ICON = [[Interface\Icons\INV_Misc_QuestionMark]]

-- The Map button at the top right, beside the three numbers.
local MAP_WIDTH = 56
local MAP_LEFT = PADDING + 400

local function RateColor(chance)
    if chance >= 40 then return "good" end
    if chance >= 15 then return "accent" end
    return "muted"
end

local function HexColor(hex)
    if type(hex) ~= "string" or #hex ~= 8 then return nil end

    local r = tonumber(hex:sub(3, 4), 16)
    local g = tonumber(hex:sub(5, 6), 16)
    local b = tonumber(hex:sub(7, 8), 16)
    if not (r and g and b) then return nil end

    return r / 255, g / 255, b / 255, 1
end

--------------------------------------------------------------------------------
-- What goes in it
--
-- Worked out apart from the frame, so a test can read it without one.
--------------------------------------------------------------------------------

--- The table for `mobName`: { mob, kills, session, rated, needed, coinPerKill,
--- worth, basis, where, rows }, or nil for a mob never killed.
--
-- `where` is the "Killed at" line: its places, most kills first.
--
-- Each row: { name, id, dropped ("12 of 40"), total ("x57"), rate (text or
-- nil), chance (0-100 or nil), perKill (copper or nil) }. Rates and values
-- wait for MIN_KILLS, the same rule as everywhere else: before that a rate is
-- a guess, and a guess is never shown as a number.
function LootTableUI:Table(mobName)
    local Tracker = ns.Tracker
    local loot = Tracker and Tracker:LootTable(mobName)
    if not loot then return nil end

    local Value = ns.Value
    local out = {
        mob = loot.mob,
        kills = loot.kills,
        session = loot.session,
        rated = loot.rated,
        needed = loot.needed,
        rows = {},
    }

    -- Coin is measured, not a rate: it shows from the first kill that
    -- recorded any.
    out.coinPerKill = loot.coinPerKill
    out.coinKills = loot.coinKills

    -- Kills from before places were kept have none, and say so rather than
    -- being shared out among the places that are known.
    local places = Tracker.PlacesText(loot.places, PLACES_SHOWN)
    if places then
        out.where = L.Format("Killed at: %s.", places)
        if loot.unplaced > 0 then
            out.where = out.where .. L.Format(" %s with no place.",
                Util.Plural(loot.unplaced, L["kill"], L["kills"]))
        end
    else
        out.where = L["Killed at: shows from your next kill."]
    end

    if Value then
        local worth, details = Value:ForMob(mobName)
        out.worth = worth
        out.basis = details and details.basis
    end

    for _, item in ipairs(loot.items) do
        local id = Value and Value:ItemID(item.name)
        local row = {
            name = item.name,
            id = id,
            dropped = L.Format("%d of %d", item.corpses, loot.kills),
            total = ("x%d"):format(item.amount),
            corpses = item.corpses,
            amount = item.amount,
        }

        if loot.rated then
            row.chance = item.chance
            row.rate = Tracker.FormatChance(item.chance)

            local unit = Value and Value:WorthOf(item.name, id)
            if unit then row.perKill = item.corpses / loot.kills * item.perCorpse * unit end
        end
        -- A quest item says so where its worth would be (2026-10-18).
        if not row.perKill and Value and Value:IsQuest(item.name, id) then row.quest = true end
        -- Until then no rate shows, not even the guild's or the shipped
        -- data's: finding them is the player's own (the owner, 2026-10-15).

        out.rows[#out.rows + 1] = row
    end

    return out
end

--------------------------------------------------------------------------------
-- Sorting by the column titles
--------------------------------------------------------------------------------

-- What each title sorts by, and the ones that start lowest first (names
-- A to Z); the numbers start with the biggest.
LootTableUI.SORT_KEYS = { name = true, dropped = true, total = true, rate = true, perKill = true }
LootTableUI.SORT_STARTS_LOW = { name = true }

local SORT_VALUE = {
    name = function(row) return row.name end,
    dropped = function(row) return row.corpses end,
    total = function(row) return row.amount end,
    rate = function(row) return row.chance end,
    perKill = function(row) return row.perKill end,
}

--- The sort the loot table's titles were left on: key (nil for the usual
--- order, most common first) and ascending. Kept in `lootTableSort`.
function LootTableUI:SortChoice()
    local saved = ns.db and type(ns.db.lootTableSort) == "table" and ns.db.lootTableSort or {}
    if not LootTableUI.SORT_KEYS[saved.key or ""] then return nil, false end
    return saved.key, saved.ascending and true or false
end

--- `rows` in the order the titles ask for, as a new list; the rows
--- themselves are not touched, so nothing is worked out again.
function LootTableUI:SortRows(rows)
    local key, ascending = self:SortChoice()
    if not key then return rows end
    return Util.SortBy(rows, ascending, SORT_VALUE[key])
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function Stat(parent, x, caption)
    local label = Theme.CreateLabel(parent, "tiny", "muted")
    label:SetPoint("TOPLEFT", x, -(HEADER + 10))
    label:SetText(caption)

    local value = Theme.CreateLabel(parent, "large", "text")
    value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)

    return value
end

local function CreateRow(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- The icon's edge in the item's quality colour, as the bags draw it,
    -- and a faint wash across the row for green and better.
    row.iconFrame = CreateFrame("Frame", nil, row)
    row.iconFrame:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -1, 1)
    row.iconFrame:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, -1)
    Theme.Border(row.iconFrame, "borderLit")

    row.wash = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.wash:SetAllPoints(row)
    row.wash:SetColorTexture(1, 1, 1, 1)
    row.wash:Hide()

    row.cells = {}
    local right = 0

    for _, column in ipairs(COLUMNS) do
        local cell = Theme.CreateLabel(row, "small", "text", "RIGHT")
        cell:SetPoint("RIGHT", -right, 0)
        cell:SetWidth(column.width)
        row.cells[column.key] = cell
        right = right + column.width + GAP
    end

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", -right, 0)

    -- A thin bar under the rate, as on the panel.
    local rate = row.cells.rate
    row.track = row:CreateTexture(nil, "BORDER")
    row.track:SetPoint("BOTTOMRIGHT", rate, "BOTTOMRIGHT", 0, -3)
    row.track:SetSize(COLUMNS[2].width - 10, 2)
    row.track:SetColorTexture(Theme.Unpack("rowAlt"))

    row.fill = row:CreateTexture(nil, "ARTWORK")
    row.fill:SetPoint("BOTTOMLEFT", row.track, "BOTTOMLEFT")
    row.fill:SetHeight(2)
end

-- How many of a clam's contents the tooltip lists.
local CONTENTS_SHOWN = 6

--- The lines a clam, sack or lockbox you opened adds to its row's tooltip:
--- { left, right, color }. None for anything you never opened.
function LootTableUI:ContentsLines(name)
    local lines = {}
    local Value, Containers = ns.Value, ns.Containers
    if not (Value and Containers and name) then return lines end

    local ok, entry = pcall(Containers.Entry, Containers, name)
    entry = ok and entry
    local opens = type(entry) == "table" and tonumber(entry.opens) or 0
    if opens <= 0 then return lines end

    lines[#lines + 1] = { " " }

    local worth, details = Value:Contents(name)
    if not worth then
        if opens < Value.MIN_OPENS then
            lines[#lines + 1] = { L.Format("You've opened %d of %d.", opens, Value.MIN_OPENS), nil, "muted" }
            lines[#lines + 1] = { L["What's inside counts toward its worth from then on."], nil, "muted" }
        else
            lines[#lines + 1] = { L.Format("You've opened %d. Nothing inside has a price yet.", opens),
                nil, "muted" }
        end
        return lines
    end

    lines[#lines + 1] = { L.Format("Opens to (%d opened)", opens), Value.Coins(worth), "accentHi" }
    for index = 1, math.min(#details.priced, CONTENTS_SHOWN) do
        local item = details.priced[index]
        local rate = ns.Tracker.FormatChance(item.chance)
        if item.each >= 1.05 then
            rate = L.Format("%s, %s each", rate, ("%.1f"):format(item.each))
        end
        lines[#lines + 1] = { ("  %s  %s"):format(ns.Util.ColorItem(item.name, item.id), rate),
            Value.Coins(item.perOpen) }
    end
    if #details.unpriced > 0 then
        lines[#lines + 1] = { L.Format("  %d more with no price", #details.unpriced), nil, "muted" }
    end

    return lines
end

local function ShowItemTooltip(row)
    local data = row.data
    if not (data and GameTooltip) then return end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")

    local shown = data.id and pcall(GameTooltip.SetItemByID, GameTooltip, data.id)
    if not shown then GameTooltip:AddLine(ns.Util.ColorItem(data.name, data.id)) end

    for _, line in ipairs(LootTableUI:ContentsLines(data.name)) do
        local r, g, b = Theme.Unpack(line[3] or "text")
        GameTooltip:AddDoubleLine(line[1], line[2] or "", r, g, b, 1, 1, 1)
    end

    GameTooltip:Show()
end

local function UpdateRow(row, data)
    -- An item looted before icons were kept has none recorded: the game's
    -- own icon for it, before the question mark.
    local look = ns.Tracker:LookOf(data.name)
    row.icon:SetTexture(look.icon or Theme.ItemIcon(data.id) or FALLBACK_ICON)

    local r, g, b, a = HexColor(look.color)
    -- No loot link kept its colour: the item's rarity from the client.
    if not r then
        r, g, b = ns.Util.ItemRGB(data.name, data.id)
        a = r and 1 or nil
    end
    if r then
        row.name:SetTextColor(r, g, b, a)
    else
        row.name:SetTextColor(Theme.Unpack("text"))
    end

    local quality = ns.TrackerFX and ns.TrackerFX.QualityOf(data.name) or nil
    if not quality then quality = ns.Util.ItemQuality(data.name, data.id) end
    if r and quality and quality >= 1 then
        for _, edge in ipairs(row.iconFrame.borderTextures) do
            edge:SetColorTexture(r, g, b, quality >= 2 and 1 or 0.5)
        end
    else
        Theme.SetBorderColor(row.iconFrame, "borderLit")
    end

    if r and quality and quality >= 2 then
        local ok = type(CreateColor) == "function" and pcall(row.wash.SetGradient, row.wash,
            "HORIZONTAL", CreateColor(r, g, b, 0.2), CreateColor(r, g, b, 0))
        if not ok then row.wash:SetColorTexture(r, g, b, 0.08) end
        row.wash:Show()
    else
        row.wash:Hide()
    end
    row.name:SetText(data.name)

    row.cells.dropped:SetText(data.dropped)
    row.cells.dropped:SetTextColor(Theme.Unpack("muted"))
    row.cells.total:SetText(data.total)

    if data.chance then
        local color = RateColor(data.chance)
        row.cells.rate:SetText(data.rate)
        row.cells.rate:SetTextColor(Theme.Unpack(color))
        row.fill:SetColorTexture(Theme.Unpack(color))
        row.track:Show()
        row.fill:Show()

        -- Opening on a mob grows each bar from nothing, one row after another.
        local width = math.max(1, (COLUMNS[2].width - 10) * math.min(1, data.chance / 100))
        local fill = row.fill
        if LootTableUI.arriving then
            ns.Motion:Run(row, "bar", 0.45, function(p) fill:SetWidth(math.max(1, width * p)) end,
                { delay = 0.1 + math.min((row.dataIndex or 1) - 1, 14) * 0.025 })
        else
            ns.Motion:Stop(row, "bar")
            fill:SetWidth(width)
        end
    else
        row.cells.rate:SetText("--")
        row.cells.rate:SetTextColor(Theme.Unpack("dim"))
        row.track:Hide()
        row.fill:Hide()
    end

    if data.perKill then
        row.cells.perKill:SetText(ns.Value.Coins(data.perKill))
        row.cells.perKill:SetTextColor(Theme.Unpack("good"))
    elseif data.quest then
        row.cells.perKill:SetText(L["Quest"])
        row.cells.perKill:SetTextColor(Theme.Unpack("accent"))
    else
        row.cells.perKill:SetText("--")
        row.cells.perKill:SetTextColor(Theme.Unpack("dim"))
    end
end

function LootTableUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesFarmerLootTable", UIParent)
    frame:SetSize(WIDTH, MAX_HEIGHT)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    Theme.Fill(frame, "window", 0.96)
    -- The house frame (UI/Titanforged.lua): the gold rim and corner gems,
    -- the mob's name on a plate across the top, and a red close gem.
    local trim
    if ns.Titanforged then
        trim = ns.Titanforged:Dress(frame, {
            title = " ",
            close = function() LootTableUI:Hide() end,
        })
        self.trim = trim
        local left, right, top, bottom = ns.Titanforged.Reach(trim)
        if frame.SetClampRectInsets then
            pcall(frame.SetClampRectInsets, frame, -left, right, top, -bottom)
        end
    else
        Theme.Border(frame, "borderLit")
    end
    Theme.Halo(frame, 8, 0.10)

    frame:SetScript("OnDragStart", function(self)
        -- Land an opening still running, or it would pull the window back.
        ns.Motion:Stop(self, "open", true)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        LootTableUI:AnchorTop()
    end)

    -- The house size grip under the bottom right corner
    -- (Widgets.CreateSizeGrip), saved as `lootTableScale`. Its height
    -- follows the rows, so the grip rides the bottom edge as it moves.
    Widgets.ApplySize(frame, ns.db and ns.db.lootTableScale)
    self.sizeGrip = Widgets.CreateSizeGrip(frame, {
        below = trim and select(4, ns.Titanforged.Reach(trim)) or 0,
        get = function() return ns.db and ns.db.lootTableScale end,
        save = function(percent) if ns.db then ns.db.lootTableScale = percent end end,
        done = function() LootTableUI:AnchorTop() end,
    })

    -- Escape closes it, like the game's own windows.
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesFarmerLootTable")
    end

    -- The mob's name is on the plate and the close gem on the corner, as
    -- the search window has them, so nothing shifts going from one window
    -- to the other. The header is a gold rule fading from the left, inside
    -- the rim.
    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", EDGE + 2, -HEADER)
    rule:SetPoint("TOPRIGHT", -(EDGE + 2), -HEADER)
    rule:SetHeight(1)
    Theme.SetGradientAlpha(rule, "HORIZONTAL", "accent", 0.6, 0.05)

    local title
    if trim and trim.plate then
        self.plate = trim.plate
        title = trim.plate.label
        self.closeButton = trim.closeButton
    else
        title = Theme.CreateLabel(frame, "large", "accent")
        title:SetPoint("TOPLEFT", PADDING, -8)
        title:SetPoint("TOPRIGHT", -40, -8)
        local close = Widgets.CreateButton(frame, "X", function() LootTableUI:Hide() end,
            { width = 22, height = 20, danger = true })
        close:SetPoint("TOPRIGHT", -PADDING + 2, -6)
        self.closeButton = close
    end

    -- Three numbers across the top.
    self.kills = Stat(frame, PADDING, L["KILLS"])
    self.worth = Stat(frame, PADDING + 130, L["WORTH PER KILL"])
    self.coin = Stat(frame, PADDING + 280, L["COIN PER KILL"])

    -- Show on Map, as the search's mob rows have it: the kill heat map's
    -- glow for this mob, only while the heat map is on the world map.
    local map = Widgets.CreateButton(frame, L["Map"], function()
        local name = LootTableUI:MapName()
        if not (name and ns.Heat and ns.UI.MapHasSpots("mob", name)) then return end
        ns.Heat:ShowOnMap("mob", name)
        LootTableUI:DressMap()
    end, { width = MAP_WIDTH, height = 22 })
    map:SetPoint("TOPRIGHT", -PADDING, -(HEADER + 12))
    map:HookScript("OnEnter", function(self)
        local name = LootTableUI:MapName()
        if not (name and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.UI.MapHasSpots("mob", name)
            and L["Show where you find this on your map."]
            or L["Kill a few first and it will show here."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    map:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    map:Hide()
    self.mapButton = map

    local status = Theme.CreateLabel(frame, "small", "muted")
    status:SetPoint("TOPLEFT", PADDING, -STATUS_TOP)
    status:SetPoint("TOPRIGHT", -PADDING, -STATUS_TOP)
    status:SetHeight(STATUS_HEIGHT)
    status:SetWordWrap(true)
    status:SetJustifyV("TOP")

    local where = Theme.CreateLabel(frame, "small", "muted")
    where:SetPoint("TOPLEFT", PADDING, -PLACES_TOP)
    where:SetPoint("TOPRIGHT", -PADDING, -PLACES_TOP)
    where:SetHeight(PLACES_HEIGHT)
    where:SetWordWrap(true)
    where:SetJustifyV("TOP")

    -- Column titles, on a band. Placed, with the list, by PlaceBody.
    local columns = Theme.CreatePanel(frame, "header", false)
    columns:SetHeight(ROW)

    local headings = {}
    local itemTitle = Theme.CreateLabel(columns, "tiny", "muted")
    itemTitle:SetPoint("LEFT", PADDING - EDGE + 4, 0)
    itemTitle:SetText(L["ITEM"])
    headings.name = itemTitle

    -- The list's rows stop 14 short of its right edge for the scrollbar.
    local right = PADDING - EDGE + 14
    for _, column in ipairs(COLUMNS) do
        local label = Theme.CreateLabel(columns, "tiny", "muted", "RIGHT")
        label:SetPoint("RIGHT", -right, 0)
        label:SetWidth(column.width)
        label:SetText(column.title)
        headings[column.key] = label
        right = right + column.width + GAP
    end

    -- Click a title to sort the items by it (a player's request,
    -- 2026-10-11), as the search's headings do. Kept in `lootTableSort`.
    local key, ascending = self:SortChoice()
    self.sorter = Widgets.SortableHeadings(headings, {
        name = L["Sort by item name, A to Z."],
        dropped = L["Sort by how many corpses held it, most first."],
        total = L["Sort by how many you took in all, most first."],
        rate = L["Sort by drop rate, best first."],
        perKill = L["Sort by what the item adds to a kill, most first."],
    }, function(newKey, newAscending)
        if ns.db then
            ns.db.lootTableSort = newKey and { key = newKey, ascending = newAscending } or nil
        end
        LootTableUI:Resort()
    end, { startsLow = LootTableUI.SORT_STARTS_LOW, key = key, ascending = ascending })

    local list = Widgets.CreateRowList(frame, {
        rowHeight = ROW,
        createRow = CreateRow,
        updateRow = UpdateRow,
        -- The item's own tooltip, through the list, which redoes it when a
        -- scroll or new loot puts another item under a still mouse.
        onEnter = ShowItemTooltip,
        onLeave = function() if GameTooltip then GameTooltip:Hide() end end,
        -- Right-click offers to hide the item (HideMenu).
        onClick = function(data, button)
            if button == "RightButton" and data and data.name then
                ns.HideMenu:Open({ { kind = "item", name = data.name } })
            end
        end,
        fadeKey = "window",
    })
    list:SetPoint("BOTTOMRIGHT", -PADDING, BOTTOM)

    -- The house empty block (Widgets.CreateEmpty, 2026-10-29).
    local empty = Widgets.CreateEmpty(frame, { width = 280 })
    empty:SetPoint("TOP", list, "TOP", 0, -24)
    empty:SetText(L["Nothing has dropped from it yet."])

    local footer = Theme.CreateLabel(frame, "tiny", "dim")
    footer:SetPoint("BOTTOMLEFT", PADDING, 12)
    footer:SetPoint("BOTTOMRIGHT", -PADDING, 12)

    self.frame = frame
    self.title = title
    self.status = status
    self.where = where
    self.titles = columns
    self.list = list
    self.empty = empty
    self.footer = footer
    self:PlaceBody(0)

    frame:Hide()
    return frame
end

--- The column titles and the list, `extra` pixels lower when the places
--- take a second line.
function LootTableUI:PlaceBody(extra)
    self.placesExtra = extra
    self.where:SetHeight(PLACES_HEIGHT + extra)
    self.titles:SetPoint("TOPLEFT", EDGE, -(COLUMNS_TOP + extra))
    self.titles:SetPoint("TOPRIGHT", -EDGE, -(COLUMNS_TOP + extra))
    self.list:SetPoint("TOPLEFT", PADDING, -(TOP + extra))
end

--------------------------------------------------------------------------------
-- Showing
--------------------------------------------------------------------------------

function LootTableUI:Render()
    local data = self.mob and self:Table(self.mob)

    if not data then
        self:Hide()
        return
    end

    -- The rows as the tally gives them, kept for a re-sort, then sorted.
    data.byTally = data.rows
    data.rows = self:SortRows(data.rows)
    self.data = data
    local title = ns.Tracker.ShowKey(data.mob)
    if self.plate then self.plate:SetTitle(title) else self.title:SetText(title) end

    -- Opening on a mob counts its kills up from nothing.
    local function Kills(count)
        return data.session > 0
            and ("%d  %s"):format(count, Util.Colored("good", ("+%d"):format(data.session)))
            or tostring(count)
    end

    local kills = self.kills
    local opening = self.shownMob ~= data.mob
    if opening and data.kills > 1 then
        ns.Motion:Run(kills, "count", 0.6, function(p)
            kills:SetText(Kills(math.floor(data.kills * p + 0.5)))
        end)
    else
        ns.Motion:Stop(kills, "count")
        kills:SetText(Kills(data.kills))
    end

    local Money = ns.Value and ns.Value.Coins

    -- The money counts up with the kills as the window opens.
    local function Count(label, copper, suffix)
        if opening and copper > 0 then
            ns.Motion:Run(label, "count", 0.6, function(p)
                label:SetText(Money(copper * p) .. suffix)
            end)
        else
            ns.Motion:Stop(label, "count")
            label:SetText(Money(copper) .. suffix)
        end
    end

    if data.worth and Money then
        Count(self.worth, data.worth, data.basis == "tally" and "" or L[" (est.)"])
        self.worth:SetTextColor(Theme.Unpack("good"))
    else
        ns.Motion:Stop(self.worth, "count")
        self.worth:SetText("--")
        self.worth:SetTextColor(Theme.Unpack("dim"))
    end

    if data.coinPerKill and Money then
        Count(self.coin, data.coinPerKill, "")
        self.coin:SetTextColor(Theme.Unpack("text"))
    else
        ns.Motion:Stop(self.coin, "count")
        self.coin:SetText("--")
        self.coin:SetTextColor(Theme.Unpack("dim"))
    end

    local status
    if data.rated then
        status = L.Format("%s. Drop rates from your kills.",
            Util.Plural(#data.rows, L["item"], L["items"]))
    else
        local items = Util.Plural(#data.rows, L["item"], L["items"])
        status = data.needed == 1
            and L.Format("%s so far. Rates after %s more kill.", items, data.needed)
            or L.Format("%s so far. Rates after %s more kills.", items, data.needed)
    end

    -- Coin started being counted after some of these kills; say how many
    -- it is from, so a short average is not mistaken for the whole tally.
    if data.coinKills < data.kills then
        status = status .. (data.coinKills > 0
            and L.Format(" Coin from your last %s.", Util.Plural(data.coinKills, L["kill"], L["kills"]))
            or L[" Coin counts from your next kill."])
    end
    self.status:SetText(status)
    self.where:SetText(data.where)
    local source = ns.Value and ns.Value:PriceSource()
    if source == "tradeskills" then
        self.footer:SetText(L["Prices: Blackthornes Tradeskills market value, or the vendor price if higher."])
    elseif source then
        self.footer:SetText(L["Prices: TSM or Auctionator market value, or the vendor price if higher."])
    else
        self.footer:SetText(L["Prices: vendor price. Load Blackthornes Tradeskills for market prices."])
    end

    self:DressMap()
    local width = self:WidthFor(data.rows, status, data.where)
    self.frame:SetWidth(width)

    -- The window widens for the places up to its widest; past that they
    -- wrap onto a second line, which the window grows a line for.
    local fits = PADDING * 2 + Theme.TextWidth("small", data.where) + 4 <= width
    self:PlaceBody(fits and 0 or PLACES_HEIGHT)

    self.empty:SetShown(#data.rows == 0)
    self.frame:SetHeight(self:HeightFor(#data.rows) + self.placesExtra)

    local fresh = self.shownMob ~= data.mob
    self.arriving = fresh
    -- A redraw after new loot keeps your place in a long list.
    self.list:SetData(data.rows, not fresh)
    self.arriving = false

    if fresh then
        self.list:Arrive()
    end
    self.shownMob = data.mob
end

--- A click on a column title: the same rows in the new order, from the
--- top. Nothing is read from the tally again.
function LootTableUI:Resort()
    local data = self.data
    if not (data and self.frame and self.frame:IsShown()) then return end
    data.rows = self:SortRows(data.byTally or data.rows)
    self.list:SetData(data.rows)
end

--- Wide enough for the longest item name on one line, the status in two and
--- the places on one, between WIDTH and MAX_WIDTH.
--
-- Everything but the name column is a fixed width: the padding, the list's
-- scrollbar, the icon, and the number columns.
function LootTableUI:WidthFor(rows, status, where)
    local fixed = PADDING * 2 + 14 + 4 + ICON + 6 + 4
    for _, column in ipairs(COLUMNS) do fixed = fixed + column.width + GAP end

    local needs = 0
    for _, row in ipairs(rows or {}) do
        needs = math.max(needs, fixed + Theme.TextWidth("small", row.name))
    end

    -- Two lines of wrapped text, with some slack for where the words break.
    needs = math.max(needs, PADDING * 2 + Theme.TextWidth("small", status) / 2 + 40)

    -- The places on one line, and the price note under the list.
    needs = math.max(needs, PADDING * 2 + Theme.TextWidth("small", where) + 4)
    needs = math.max(needs, PADDING * 2 + Theme.TextWidth("tiny", self.footer and self.footer:GetText()) + 4)

    -- Room for the Map button after the numbers while it shows.
    if self:MapName() then needs = math.max(needs, MAP_LEFT + MAP_WIDTH + PADDING) end

    return math.min(MAX_WIDTH, math.max(WIDTH, math.ceil(needs)))
end

--- The mob the Map button shows, by its name alone (the heat map keeps
--- kills by name), or nil while the heat map is off the world map.
function LootTableUI:MapName()
    if not (ns.Heat and ns.Heat.WorldOn() and ns.UI and ns.UI.MapHasSpots) then return nil end
    local mob = self.mob
    if type(mob) ~= "string" then return nil end
    local name = ns.Tracker and ns.Tracker.NameOf and ns.Tracker.NameOf(mob) or mob
    return type(name) == "string" and name ~= "" and name or nil
end

--- The Map button: gold while the map shows this mob, dim before any kill
--- with a spot, hidden while the heat map is off the world map.
function LootTableUI:DressMap()
    local button = self.mapButton
    if not button then return end
    local name = self:MapName()
    if not name then
        button:Hide()
        return
    end
    if ns.Heat:Mob() == name then
        button:SetLabelColor("accent")
    elseif not ns.UI.MapHasSpots("mob", name) then
        button:SetLabelColor("dim")
    else
        button:SetLabelColor(nil)
    end
    button:Show()
end

--- Tall enough for `count` rows, within MIN_HEIGHT and MAX_HEIGHT.
function LootTableUI:HeightFor(count)
    return math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, TOP + count * ROW + 6 + BOTTOM))
end

-- The height follows the rows, so the window hangs from its top edge: a new
-- item lengthens it downward instead of moving it. After a drag the client
-- re-anchors to the nearest point, so pin it by its top-left again.
function LootTableUI:AnchorTop()
    local frame = self.frame
    if not frame then return end

    local ok, left, top = pcall(function() return frame:GetLeft(), frame:GetTop() end)
    if not (ok and type(left) == "number" and type(top) == "number") then return end

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

--- Open the window on `mobName`. Returns false for a mob never killed.
function LootTableUI:Show(mobName)
    if not (mobName and ns.Tracker:Summary(mobName)) then return false end

    self:Build()
    self.mob = mobName

    -- Closed and opened again on the same mob is a fresh look, so its rows
    -- come in again.
    local opening = not self.frame:IsShown()
    if opening then self.shownMob = nil end

    self:Render()
    self.frame:Show()
    -- A click on the main window lifts it over this one, so a second mob
    -- picked there would open behind it; bring this window to the front.
    self.frame:Raise()
    if opening then ns.Motion:Open(self.frame) end

    return true
end

function LootTableUI:Hide()
    if self.frame then self.frame:Hide() end
end

function LootTableUI:IsShown()
    return self.frame ~= nil and self.frame:IsShown()
end

--- Clicking the mob that is already open closes it again.
function LootTableUI:Toggle(mobName)
    if self:IsShown() and self.mob == mobName then
        self:Hide()
        return false
    end

    return self:Show(mobName)
end

--- Redraw if open, after new loot or a reset.
function LootTableUI:Refresh()
    if self:IsShown() then self:Render() end
end

-- An item's rarity came in late: the rows on screen take its colour.
ns.Util.OnRarity("lootTable", function()
    if LootTableUI:IsShown() and LootTableUI.list then LootTableUI.list:Refresh() end
end)

ns.RegisterCommand("loot", L["open a mob's full loot table"], function(rest)
    local Tracker = ns.Tracker
    local mobName = Tracker:ResolveMob(rest or "")
    -- A name killed in more than one zone opens on this zone's line, or
    -- the one last looted.
    if mobName then
        mobName = (Util.Trim(rest or "") == "" and Tracker.currentKey) or Tracker:KeyHere(mobName)
    end

    if not (mobName and LootTableUI:Show(mobName)) then
        local wanted = Util.Trim(rest or "")
        if wanted == "" then
            ns.Print(L["nothing killed yet. Loot something and try again."])
        else
            ns.Print(L.Format("no kills of %s yet.", wanted))
        end
    end
end)
