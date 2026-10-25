-- Text is never cut off (2026-09-25).
--
-- His screenshots: "Loot a corpse and it shows up he...", "Forest Mushroom
-- C...", "Coin is from your l...". The game's font runs wider than widths
-- picked by eye, so windows measure their text and make room for it. The stub
-- client measures 6 pixels a character.
--
-- What matters: each window is at least as wide as its widest text needs, up
-- to its cap, and never narrower than the size it starts at or was given.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("textfit")

local ns = env.Load({ ui = true })
local Theme = ns.Theme
local Tracker = ns.Tracker
local TUI = ns.TrackerUI
local LTU = ns.LootTableUI
local UI = ns.UI

suite.check("text is measured", Theme.TextWidth("small", "abcd") == 24,
    Theme.TextWidth("small", "abcd"))
suite.check("nothing measures nothing", Theme.TextWidth("small", nil) == 0)

TUI:OnEnable()

--- Every drawn line fits the panel.
local function AllFit()
    local width = TUI.frame:GetWidth()
    for index = 1, #TUI.shown do
        local row = TUI.lines[index]
        if row.needs > width then return false, TUI.shown[index].left end
    end
    return true
end

--------------------------------------------------------------------------------
-- The kills and loot panel
--------------------------------------------------------------------------------

suite.check("the empty panel fits its text", AllFit())
suite.check("and is not narrower than it starts", TUI.frame:GetWidth() >= 236)

local serial = 0
local function Loot(mob, items)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, guid = "C-" .. serial }
    env.world.loot = items
    Tracker:OnLoot()
end

local LONG = "Refreshing Spring Water of the Long Name"
Loot("Rot Hide Mongrel", { { name = LONG, id = 159 }, { name = "Forest Mushroom Cap", id = 4604 } })

local fits, cut = AllFit()
suite.check("a long item name widens the panel", fits, cut)
suite.check("to wider than it was", TUI.frame:GetWidth() > 236, TUI.frame:GetWidth())

-- A width you dragged it to is kept when the text fits in it.
ns.db.trackerWidth = 500
TUI:Refresh()
suite.check("a wide saved width is kept", TUI.frame:GetWidth() == 500, TUI.frame:GetWidth())

-- Narrower than the text needs, it widens anyway.
ns.db.trackerWidth = 180
TUI:Refresh()
fits, cut = AllFit()
suite.check("a narrow saved width still fits the text", fits, cut)

-- But not past the largest the grip allows.
suite.check("widening stops at the maximum", TUI:FitWidth(5000) == 600, TUI:FitWidth(5000))
ns.db.trackerWidth = nil

-- A long value gets the room it needs rather than being cut.
local row = TUI.lines[1]
TUI:DrawLine(row, { style = "item", item = "x", left = "x", right = "123456789012" })
suite.check("a long value widens its column", row.leftStop > 8 + 54 + 4, row.leftStop)

--------------------------------------------------------------------------------
-- The loot table
--------------------------------------------------------------------------------

LTU:Show("Rot Hide Mongrel")
local fixed = LTU:WidthFor({}, "")
suite.check("the loot table starts at its usual width", fixed == 460, fixed)

local width = LTU.frame:GetWidth()
suite.check("a long item name widens the loot table",
    width > 460 and width >= LTU:WidthFor({ { name = LONG } }, ""), width)
suite.check("to its cap at most",
    LTU:WidthFor({ { name = string.rep("W", 400) } }, "") == 760)

local status = string.rep("word ", 40)
suite.check("a long status widens it to fit in two lines",
    LTU:WidthFor({}, status) >= Theme.TextWidth("small", status) / 2)
LTU:Hide()

--------------------------------------------------------------------------------
-- The search window
--------------------------------------------------------------------------------

UI:Build()
local baseWidth = 724  -- the window's usual width (660 before the worth column)
UI:Search("wool cloth")

local columns = UI.columns
local widest = { name = 0, where = 0 }
for _, data in ipairs(UI.list.data) do
    if data.type == "source" then
        local source = data.source
        local where = ns.DB:WhereText(source)
        widest.name = math.max(widest.name, Theme.TextWidth("small",
            source.name or source.requires or ns.DB:KindLabel(source.kind)))
        widest.where = math.max(widest.where, Theme.TextWidth("small",
            where and (source.zone .. ns.Util.Colored("dim", " / ") .. where) or source.zone))
    end
end

suite.check("the source column fits every name", columns.name.w >= math.min(320, widest.name),
    columns.name.w .. " < " .. widest.name)
suite.check("the where column fits every place", columns.where.w >= math.min(520, widest.where),
    columns.where.w .. " < " .. widest.where)
suite.check("columns follow one another",
    columns.where.x == columns.name.x + columns.name.w + 6, columns.where.x)
suite.check("the window grows with its columns",
    UI.frame:GetWidth() == baseWidth + columns.extra, UI.frame:GetWidth())
suite.check("the headings move with them",
    UI.headings.where._point[2] == 8 + columns.where.x, UI.headings.where._point[2])

-- A row is the window less its padding, the list's inset and the scrollbar.
local function RowWidth() return UI.frame:GetWidth() - 58 end

-- The longest places in the data ran past 400 pixels in the game's font.
local far = { kind = "mob", name = "x", zone = "Tirisfal Glades", location = string.rep("x", 70) }
UI:FitColumns({ { type = "source", source = far } })
suite.check("the where column grows past 400 for a long place", UI.columns.where.w > 400,
    UI.columns.where.w)

-- The badge slot sits after the drop column; on Classic Era it holds no
-- Forever tag, so it stays narrow.
UI:FitColumns({ { type = "source", source = { kind = "node", name = "Copper Vein",
    zone = "Durotar", requires = "Mining 1", provenance = "forever" } } })
columns = UI.columns
suite.check("the badge's slot starts after the drop column",
    columns.badge.x >= columns.drop.x + columns.drop.w, columns.badge.x)
suite.check("and stays narrow, with no Forever tag", columns.badge.w < Theme.TextWidth("tiny", "Forever"),
    columns.badge.w)
suite.check("inside the row", columns.badge.x + columns.badge.w <= RowWidth(),
    columns.badge.x + columns.badge.w)

local badged = env.Stub()
UI:CreateRow(badged)
suite.check("a row puts its badge in that slot", badged.badge._point[2] == columns.badge.x,
    badged.badge._point[2])

-- A note is one line across its row; a long one widens the window.
local note = string.rep("a long note ", 12)
UI:FitColumns({ { type = "note", text = note } })
suite.check("a long note fits its row", Theme.TextWidth("small", "     " .. note) + 4 <= RowWidth(),
    RowWidth())
UI:UpdateRow(badged, { type = "note", text = note })
suite.check("which it spans, with no room kept for a Goal button",
    badged.heading._point[1] == "RIGHT" and badged.heading._point[2] == -2,
    badged.heading._point[2])

UI:FitColumns({ { type = "note", text = "short" } })
-- Every tab shares one width, the widest any has needed: a short note
-- after a long one leaves the window as it was, and spreads the columns.
local grown = UI.frame:GetWidth()
UI:FitColumns({ { type = "note", text = "short" } })
suite.check("a short note keeps the window at the width it grew to",
    UI.frame:GetWidth() == grown and grown == UI:WindowWidth(), UI.frame:GetWidth())
suite.check("and the columns fill it", baseWidth + UI.columns.extra == UI.frame:GetWidth(),
    baseWidth + UI.columns.extra)
suite.check("the width is kept for next time", ns.db.windowWidth == grown, ns.db.windowWidth)

--------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------

local button = ns.Widgets.CreateButton(UIParent, "A label much longer than eighty", nil,
    { width = 80 })
suite.check("a button is never narrower than its label",
    button:GetWidth() >= Theme.TextWidth("small", "A label much longer than eighty"),
    button:GetWidth())
button:SetText("OK")
suite.check("and keeps its set width for a short one", button:GetWidth() == 80, button:GetWidth())

suite.done()
