-- The kill heat map (a test feature, 2026-10-17).
--
-- What must hold:
--   1. Off by default, and nothing is recorded while both switches are off.
--   2. A kill adds one to its map cell for its mob; a spot the client will
--      not give adds nothing, and the kill still counts.
--   3. The save stays small: cell and mob caps.
--   4. Hidden mobs are left out, and one mob can be picked.
--   5. /farm heat turns it on and off and forgets only on "clear confirm".
--   6. The Settings controls exist.
--   7. Show on Map: a mob or an item from the search aims the glow, an
--      item's mobs weighted by your own drop rate; the map opens where the
--      glow is; the same row again, or the card's button, stops tracking.
--   8. The maps glow only while a mob or an item is tracked, and the glow's
--      outer edge has an outline that closes round it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("heat")

local ns = env.Load({ ui = true })
for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local Heat = ns.Heat

-- 1.
suite.check("world map is off by default", ns.db.heatWorld == false)
suite.check("minimap is off by default", ns.db.heatMinimap == false)
suite.check("nothing is asking for it", not Heat.Recording())

local where = { 1411, 0.5, 0.5 }
ns.Harvest.PlayerMapPosition = function()
    if where then return where[1], where[2], where[3] end
end

Heat:Kill("Plainstrider")
suite.check("nothing recorded while off", select(3, Heat:Summary()) == 0)

-- 2.
Heat:SetWorld(true)
Heat:Kill("Plainstrider")
Heat:Kill("Plainstrider")
local list, most = Heat:Cells(1411)
suite.check("two kills share a cell", #list == 1 and most == 2)
suite.check("the cell is the middle of the map", list[1].cell == Heat.CellOf(0.5, 0.5))

where = nil
Heat:Kill("Plainstrider")
suite.check("an unreadable spot adds nothing", select(3, Heat:Summary()) == 1)

suite.check("cell maths keeps to the edges", Heat.CellOf(-1, 2) == 99 * 100 and Heat.CellOf(1, 1) == 9999)
local cx, cy = Heat.CellCentre(Heat.CellOf(0.255, 0.755))
suite.check("a cell's middle is inside it", math.abs(cx - 0.255) < 0.01 and math.abs(cy - 0.755) < 0.01)

-- 3.
for i = 0, Heat.MAX_CELLS + 20 do
    Heat:Note(1, (i % 100) / 100 + 0.001, math.floor(i / 100) / 100 + 0.001, "Boar")
end
local _, _, cells = Heat:Summary()
suite.check("a mob keeps at most MAX_CELLS cells", cells <= 1 + Heat.MAX_CELLS)
local before = Heat.version
suite.check("a full mob still counts a cell it has", Heat:Note(1, 0.001, 0.001, "Boar"))
suite.check("but not a new one", not Heat:Note(1, 0.999, 0.999, "Boar"))
for i = 1, Heat.MAX_MOBS + 5 do Heat:Note(2, 0.5, 0.5, "Mob" .. i) end
local _, lines = Heat:Summary()
suite.check("a map keeps at most MAX_MOBS mobs", lines <= 2 + Heat.MAX_MOBS)
suite.check("bad input is refused", not Heat:Note("x", 0.5, 0.5, "A") and not Heat:Note(1, 0.5, 0.5, ""))

-- 4.
Heat:Clear()
Heat:Note(7, 0.1, 0.1, "Wolf")
Heat:Note(7, 0.9, 0.9, "Bear")
suite.check("all mobs shows both", #Heat:Cells(7) == 2)
Heat:SetMob("Wolf")
suite.check("one mob shows only its own", #Heat:Cells(7) == 1)
Heat:SetMob("")
suite.check("empty name means every mob", Heat:Mob() == nil)
ns.DB:Hide("source", "Bear")
suite.check("a hidden mob is left out", #Heat:Cells(7) == 1)

-- 5.
ns.HandleSlash("heat off")
suite.check("/farm heat off", not Heat.WorldOn() and not Heat.MinimapOn())
ns.HandleSlash("heat minimap on")
suite.check("/farm heat minimap on", Heat.MinimapOn() and not Heat.WorldOn())
ns.HandleSlash("heat strength most")
suite.check("/farm heat strength most", Heat:Level() == 3)
ns.HandleSlash("heat mob Wolf")
suite.check("/farm heat mob", Heat:Mob() == "Wolf")
ns.HandleSlash("heat mob all")
suite.check("/farm heat mob all", Heat:Mob() == nil)
ns.HandleSlash("heat clear")
suite.check("clear alone forgets nothing", select(3, Heat:Summary()) > 0)
ns.HandleSlash("heat clear confirm")
suite.check("clear confirm forgets", select(3, Heat:Summary()) == 0)

-- 7.
Heat:SetWorld(true)
ns.DB:Unhide("source", "Bear")
Heat:Note(7, 0.1, 0.1, "Wolf")
Heat:Note(7, 0.1, 0.1, "Wolf")
Heat:Note(7, 0.9, 0.9, "Bear")
Heat:Note(8, 0.5, 0.5, "Bear")
local keptRecords = ns.Harvest.records
ns.Harvest.records = {
    ["Wolf|Mulgore|"] = { mob = "Wolf", zone = "Mulgore", corpses = 10, items = {
        ["Wolf Fang"] = { name = "Wolf Fang", id = 900, count = 5, corpses = 5 },
    } },
    ["Bear|Mulgore|"] = { mob = "Bear", zone = "Mulgore", corpses = 10, items = {
        ["Wolf Fang"] = { name = "Wolf Fang", id = 900, count = 1, corpses = 1 },
    } },
    ["Boar|Mulgore|"] = { mob = "Boar", zone = "Mulgore", corpses = 10, items = {} },
}

local mobs = Heat:ItemMobs("Wolf Fang")
suite.check("an item's mobs, likeliest first", #mobs == 2 and mobs[1].mob == "Wolf"
    and math.abs(mobs[1].chance - 0.5) < 1e-9 and math.abs(mobs[2].chance - 0.1) < 1e-9)
suite.check("a mob with spots has them", Heat:HasSpots("Wolf") and not Heat:HasSpots("Boar"))
suite.check("an item with a spotted mob has spots", Heat:ItemHasSpots("Wolf Fang")
    and not Heat:ItemHasSpots("Nothing"))

local opened
_G.OpenWorldMap = function(mapID) opened = mapID end
suite.check("Map on an item aims the glow", Heat:ShowOnMap("item", "Wolf Fang")
    and Heat:Item() == "Wolf Fang" and Heat:Mob() == nil)
local itemCells = Heat:Cells(7)
local wolfCell, bearCell
for _, entry in ipairs(itemCells) do
    if entry.cell == Heat.CellOf(0.1, 0.1) then wolfCell = entry.count end
    if entry.cell == Heat.CellOf(0.9, 0.9) then bearCell = entry.count end
end
suite.check("an item's glow is weighted by drop rate", wolfCell == 2 and math.abs(bearCell - 0.2) < 1e-9)
suite.check("the map opens where the glow is most", opened == 7)
suite.check("nothing new is saved for an item", ns.db.heatMob == nil)

local shows = ns.HeatUI.CardText()
suite.check("the card says what it shows", shows.name == "Wolf Fang" and shows.item)
suite.check("the card lists the mobs with their rate", shows.rows[1].mob == "Wolf"
    and shows.rows[1].rate == "50% a kill" and shows.rows[2].mob == "Bear" and shows.rows[2].rate == "10% a kill")

suite.check("the same row again shows all", not Heat:ShowOnMap("item", "Wolf Fang") and Heat:Item() == nil)

opened = nil
suite.check("Map on a mob picks the mob", Heat:ShowOnMap("mob", "Bear") and Heat:Mob() == "Bear")
suite.check("a mob's map is where it was killed most", opened == 7 or opened == 8)
local mobShows = ns.HeatUI.CardText()
suite.check("a mob's card has no rate lines", #mobShows.rows == 0 and not mobShows.item)
Heat:ShowAll()
suite.check("Stop Tracking goes back to every mob", Heat:Mob() == nil and Heat:Item() == nil
    and Heat:TargetKey() == "all")

ns.DB:Hide("source", "Bear")
suite.check("a hidden mob is left out of an item", #Heat:ItemMobs("Wolf Fang") == 1)
ns.DB:Unhide("source", "Bear")

local inFight = _G.InCombatLockdown
_G.InCombatLockdown = function() return true end
opened = nil
Heat:ShowOnMap("mob", "Wolf")
suite.check("the map is not opened in a fight", opened == nil and Heat:Mob() == "Wolf")
_G.InCombatLockdown = inFight
Heat:ShowAll()

-- The search's Map button.
suite.check("a mob row gets a Map button", ns.UI.MapTarget({ type = "source",
    source = { name = "Wolf", kind = "mob" } }) == "mob")
suite.check("a node row does not", ns.UI.MapTarget({ type = "source",
    source = { name = "Copper Vein", kind = "mining" } }) == nil)
suite.check("an item row does", ns.UI.MapTarget({ type = "item", item = { name = "Wolf Fang" } }) == "item")
suite.check("world drops do not", ns.UI.MapTarget({ type = "item",
    item = { name = "World drops", worldDrops = true } }) == nil)
-- Drawn in a real search: the mob rows get the button in a slot of its own.
local mobName
for _, source in ipairs(ns.DB:GetItem("Wool Cloth").sources) do
    if (source.kind or "mob") == "mob" and source.name then mobName = source.name break end
end
Heat:Note(9, 0.3, 0.3, mobName)
local searched = pcall(function() ns.UI:Search("wool cloth") end)
suite.check("a search with the heat map on draws", searched)
suite.check("the Map slot opens up", ns.UI.columns.map.w > 0)
local shownMob, shownItem
for index = 1, #ns.UI.list.rows do
    local r = ns.UI.list.rows[index]
    if r:IsShown() and r.data and r.map:IsShown() then
        if r.data.type == "source" then shownMob = true end
        if r.data.type == "item" then shownItem = true end
    end
end
suite.check("mob rows and the item heading show Map", shownMob and shownItem)
Heat:SetWorld(false)
ns.UI:Search("wool cloth")
local anyMap = false
for index = 1, #ns.UI.list.rows do
    local r = ns.UI.list.rows[index]
    if r:IsShown() and r.map:IsShown() then anyMap = true end
end
suite.check("no Map buttons with the heat map off", not anyMap and ns.UI.columns.map.w == 0)
suite.check("no Map button while the heat map is off", ns.UI.MapTarget({ type = "source",
    source = { name = "Wolf", kind = "mob" } }) == nil)
ns.Harvest.records = keptRecords

-- Drawing never fails, in a fight or out.
local ok = pcall(function() ns.HeatUI:Refresh() end)
suite.check("drawing does not raise", ok)

-- 8.
local outline = ns.HeatUI.Outline({ { cell = Heat.CellOf(0.505, 0.505), count = 1 } })
-- One cell grown to three by three: a square with its corners cut: four corners and two pieces a side.
suite.check("one cell's outline has twelve pieces", #outline == 12)
local ends = {}
for _, piece in ipairs(outline) do
    for _, at in ipairs({ { piece[1], piece[2] }, { piece[3], piece[4] } }) do
        local k = ("%.4f,%.4f"):format(at[1], at[2])
        ends[k] = (ends[k] or 0) + 1
    end
end
local closed = true
for _, n in pairs(ends) do if n ~= 2 then closed = false end end
suite.check("the outline closes round the glow", closed)
local outside = true
for _, piece in ipairs(outline) do
    for _, at in ipairs({ { piece[1], piece[2] }, { piece[3], piece[4] } }) do
        local far = math.max(math.abs(at[1] - 0.505), math.abs(at[2] - 0.505))
        if far < 0.0099 then outside = false end
    end
end
suite.check("the outline sits outside the cell", outside)
suite.check("a corner cell's outline stays on the map", (function()
    for _, piece in ipairs(ns.HeatUI.Outline({ { cell = 0, count = 1 } })) do
        for _, v in ipairs(piece) do if v < 0 or v > 1 then return false end end
    end
    return true
end)())
suite.check("no cells, no outline", #ns.HeatUI.Outline({}) == 0)

local keptView = ns.MapMarkers.WorldView
local worldCanvas = CreateFrame("Frame")
worldCanvas:SetFrameLevel(5)
ns.MapMarkers.WorldView = function()
    return { mapID = 9, width = 1000, height = 700, canvas = worldCanvas }
end
Heat:SetWorld(true)
Heat:ShowAll()
ns.HeatUI:Refresh()
suite.check("nothing tracked, no glow on the map", ns.HeatUI.job == nil
    and (not ns.HeatUI.world or ns.HeatUI.world.used == 0))
Heat:SetMob(mobName)
ns.HeatUI:Refresh()
for _ = 1, 20 do ns.HeatUI:Slice() end
suite.check("tracking a mob, the map glows", ns.HeatUI.world and ns.HeatUI.world.used > 0)
suite.check("and its edge is outlined", (ns.HeatUI.world.edgesUsed or 0) > 0)
-- The map's art is a frame one level over the canvas: a glow at the
-- canvas's own level was drawn under it and never showed.
suite.check("the glow sits over the map's art",
    ns.HeatUI.world.frame:GetFrameLevel() >= worldCanvas:GetFrameLevel() + 2)
suite.check("and under the node markers",
    ns.MapMarkers.WORLD_ABOVE > ns.HeatUI.WORLD_ABOVE
    and ns.MapMarkers.MINIMAP_ABOVE > ns.HeatUI.MINIMAP_ABOVE)
-- On a zone map the explored parts are pins over the art (the glow showed
-- on Kalimdor, not Ashenvale, 2026-10-18): the glow goes over them too.
local keptMap = _G.WorldMapFrame
local explored = CreateFrame("Frame")
explored:SetFrameLevel(9)
_G.WorldMapFrame = {
    -- As the game's pin pools give them: pairs over the active pins.
    EnumeratePinsByTemplate = function(_, template)
        if template ~= "MapExplorationPinTemplate" then return pairs({}) end
        return pairs({ [explored] = true })
    end,
}
Heat.version = Heat.version + 1
ns.HeatUI:Refresh()
local glowLevel = ns.HeatUI.world.frame:GetFrameLevel()
suite.check("the glow sits over a zone's explored parts", glowLevel > explored:GetFrameLevel(), glowLevel)
suite.check("and the node markers over the glow",
    ns.MapMarkers.BaseLevel(worldCanvas) + ns.MapMarkers.WORLD_ABOVE > glowLevel)
_G.WorldMapFrame = {
    GetPinFrameLevelsManager = function()
        return { GetValidFrameLevel = function(_, kind)
            return kind == "PIN_FRAME_LEVEL_MAP_EXPLORATION" and 12 or nil
        end }
    end,
}
suite.check("with no explored pins out yet, the level the map keeps for them counts",
    ns.MapMarkers.BaseLevel(worldCanvas) == 11)
_G.WorldMapFrame = {}
suite.check("a map with neither counts from the canvas", ns.MapMarkers.BaseLevel(worldCanvas) == 5)
_G.WorldMapFrame = keptMap
Heat:ShowAll()
suite.check("stop tracking, the glow goes", ns.HeatUI.world.used == 0
    and ns.HeatUI.world.edgesUsed == 0)
ns.MapMarkers.WorldView = keptView

-- The card says when there is nothing to show yet, and stays inside the map.
Heat:SetMob(mobName)
suite.check("a mob with spots has glow", ns.HeatUI.HasGlow())
Heat:SetMob("Never Killed Here")
suite.check("a mob with no spots has none yet", not ns.HeatUI.HasGlow())
Heat:ShowAll()
ns.db.heatCardX, ns.db.heatCardY = 5000, -50
local okPlace = pcall(function()
    _G.WorldMapFrame = _G.WorldMapFrame or env.Stub()
    Heat:SetMob(mobName)
    ns.HeatUI:UpdateCard()
    ns.HeatUI:PlaceCard()
    ns.HeatUI:KeepCardPlace()
end)
suite.check("placing and dragging the card does not raise", okPlace)
local mapShown = _G.WorldMapFrame.IsShown
_G.WorldMapFrame.IsShown = function() return true end
local okItem = pcall(function()
    Heat.item = { name = "Wolf Fang", mobs = { { mob = "Wolf", chance = 0.5 } }, weights = { Wolf = 1 } }
    ns.HeatUI:UpdateCard()
end)
_G.WorldMapFrame.IsShown = mapShown
suite.check("an item's card draws its mob rows", okItem and ns.HeatUI.card ~= nil
    and #ns.HeatUI.card.rows >= 1)
-- The card is drawn small, so Era's small map still shows round it.
suite.check("the card is drawn at its smaller size", ns.HeatUI.CARD_SCALE and ns.HeatUI.CARD_SCALE < 1)
local scaleSeen
local okScale = pcall(function()
    local placed = ns.HeatUI.card
    local setPoint = placed.SetPoint
    placed.SetPoint = function(self, point, rel, relPoint, x, y) scaleSeen = { x, y } end
    ns.db.heatCardX, ns.db.heatCardY = 30, 30
    ns.HeatUI:PlaceCard()
    placed.SetPoint = setPoint
end)
suite.check("the card's place is kept in the map's units", okScale and scaleSeen
    and math.abs(scaleSeen[1] * ns.HeatUI.CARD_SCALE - 30) < 0.01)
-- The card sits a layer above the map, never under its art.
suite.check("the card is drawn above a HIGH map", ns.HeatUI.CardStrata({ GetFrameStrata = function() return "HIGH" end }) == "DIALOG")
suite.check("the card is drawn above a full screen map",
    ns.HeatUI.CardStrata({ GetFrameStrata = function() return "FULLSCREEN" end }) == "FULLSCREEN_DIALOG")
suite.check("the card follows the map's layer", ns.HeatUI.card:GetFrameStrata()
    == ns.HeatUI.CardStrata(_G.WorldMapFrame))
Heat:ShowAll()
ns.db.heatCardX, ns.db.heatCardY = nil, nil

-- The loot table's Map button, for the mob it shows.
local LTU = ns.LootTableUI
LTU:Build()
LTU.mob = mobName .. "\tSomewhere"
suite.check("the loot table maps a mob by its name", LTU:MapName() == mobName)
LTU:DressMap()
suite.check("the loot table's Map button shows with the heat map on", LTU.mapButton:IsShown())
LTU.mapButton:GetScript("OnClick")(LTU.mapButton, "LeftButton")
suite.check("and tracks that mob", Heat:Mob() == mobName)
LTU.mapButton:GetScript("OnClick")(LTU.mapButton, "LeftButton")
suite.check("a second click stops tracking", Heat:Mob() == nil)
Heat:SetWorld(false)
LTU:DressMap()
suite.check("it hides with the heat map off the world map", not LTU.mapButton:IsShown()
    and LTU:MapName() == nil)
LTU.mob = nil

-- 6.
ns.SettingsUI:Show()
local c = ns.SettingsUI.controls
suite.check("Settings has the controls", c.heatWorld ~= nil and c.heatMinimap ~= nil and c.heatLevel ~= nil)

-- 7. Kills kept under a map inside the one shown (the owner saw no glow on
-- Ashenvale, 2026-10-18): the game can name a smaller map where you stood.
ns.db.killHeat = {}
Heat.version = Heat.version + 1
local realRect = C_Map.GetMapRectOnMap
C_Map.GetMapRectOnMap = function(inner, outer)
    if inner == 9001 and outer == 1440 then return 0.2, 0.4, 0.5, 0.7 end
    return nil
end
Heat:Note(9001, 0.5, 0.5, "Clattering Crawler")
Heat:SetMob("Clattering Crawler")
local carried = Heat:Cells(1440)
suite.check("a kill on a map inside shows on the zone", #carried == 1
    and carried[1].cell == Heat.CellOf(0.3, 0.6))
local back = Heat:Cells(9001)
suite.check("and still on its own map", #back == 1 and back[1].cell == Heat.CellOf(0.5, 0.5))
Heat:Note(1440, 0.9, 0.9, "Clattering Crawler")
local out = Heat:Cells(9001)
suite.check("a zone kill off the smaller map is left off it", #out == 1)
suite.check("the map opens where it was killed, not the zone holding it",
    Heat:BestMap() == 9001 or Heat:BestMap() == 1440)
suite.check("maps that don't hold each other share nothing", #Heat:Cells(1411) == 0)
ns.KeepCheck("heat check", Heat.Check)
local probe = ns.db.lastProbe
local saysMap = false
for _, line in ipairs(probe and probe.lines or {}) do
    if line:find("kept on map 9001", 1, true) then saysMap = true end
end
suite.check("/farm heat check names the map kills are kept on", probe and probe.check == "heat check" and saysMap)
C_Map.GetMapRectOnMap = realRect
Heat:SetMob(nil)

-- 8. Kills kept under the continent, or a map beside the zone, show on the
-- zone too, placed by where each map's corners lie in the world (the owner
-- saw the glow on Kalimdor but not on Ashenvale, 2026-10-18).
ns.db.killHeat = {}
Heat.version = Heat.version + 1
local realWorld, realVector = C_Map.GetWorldPosFromMapPos, _G.CreateVector2D
-- Each map's corners in the world: { north, west } at (0, 0), then at (1, 1).
local corners = {
    [8414] = { 1000, 1000, 0, 0 },     -- the continent
    [8440] = { 600, 600, 400, 400 },   -- a zone on it
    [8441] = { 600, 650, 400, 550 },   -- a strip beside the zone, half on it
    [8999] = { 600, 600, 400, 400 },   -- another continent
}
_G.CreateVector2D = function(x, y) return { x = x, y = y } end
C_Map.GetWorldPosFromMapPos = function(mapID, at)
    local c = corners[mapID]
    if not c then return nil end
    local north = c[1] + (c[3] - c[1]) * at.y
    local west = c[2] + (c[4] - c[2]) * at.x
    return mapID == 8999 and 2 or 1, { GetXY = function() return north, west end }
end
Heat:Note(8414, 0.5, 0.5, "Clattering Crawler")
Heat:SetMob("Clattering Crawler")
local onZone = Heat:Cells(8440)
-- One continent cell is five zone cells wide, so its centre lands a little off.
suite.check("a kill kept on the continent shows on the zone", #onZone == 1
    and onZone[1].cell == Heat.CellOf(Heat.Carry(8414, 8440, Heat.CellCentre(Heat.CellOf(0.5, 0.5))))
    and math.abs(onZone[1].cell - Heat.CellOf(0.5, 0.5)) <= 202)
suite.check("but not on another continent's map", #Heat:Cells(8999) == 0)
ns.db.killHeat = {}
Heat.version = Heat.version + 1
Heat:Note(8441, 0.25, 0.5, "Clattering Crawler")
Heat:Note(8441, 0.75, 0.5, "Clattering Crawler")
local beside = Heat:Cells(8440)
suite.check("a kill on a map beside the zone shows where they meet", #beside == 1
    and beside[1].cell == Heat.CellOf(0.125, 0.5))
local wide = Heat:Cells(8414)
suite.check("and both show on the continent", #wide == 2)
C_Map.GetWorldPosFromMapPos, _G.CreateVector2D = realWorld, realVector
Heat:SetMob(nil)

suite.done()
