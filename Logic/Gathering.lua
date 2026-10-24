-- Blackthornes Farmer -- Logic/Gathering.lua
-- Herbs and ore: what each node gave, where, and how often.
--
-- A herb or a vein is not a corpse, so the harvester and the kill tally never
-- saw it: they read the target to know whose loot a window is, and a node is
-- not a unit. Most of the time that meant the loot was dropped. Now and then,
-- with a looted corpse still targeted, it was worse: the herb went down as
-- that mob's drop. This is where node loot goes instead.
--
-- How a window is known to be a node's. Picking a herb or mining a vein is a
-- spell cast, Herb Gathering or Mining, and the client says so when the cast
-- is sent, naming what it was cast on: "Peacebloom", "Copper Vein". A loot
-- window that opens soon after one of those, which nothing interrupted, is
-- that node's. No such cast, no gathering: nothing is put down to a node on
-- a guess. Skinning is left alone -- skinned leather is the mob's drop
-- (the house rule, PR #16) and the kill tally keeps it. Its cast is only
-- noted (IsSkinning), so a corpse first opened by skinning is not taken for
-- a fresh kill with nothing in it.
--
-- Each loot window is one gather. A vein mined three times is three gathers,
-- which is what an ore rate should be over anyway.
--
-- Below MIN_GATHERS a node shows counts, never percentages, the same rule and
-- the same number as kills and casts.
--
-- Everything is kept in saved variables. Nothing is sent anywhere.

local _, ns = ...
local L = ns.L

local Gathering = ns.NewModule("Gathering")

local Util = ns.Util

-- Same threshold as kills and fishing casts, for the same reason.
local MIN_GATHERS = 20

-- How long after a gathering cast is sent its loot window may open. A herb
-- takes a few seconds to pick; this is long enough for a slow one and short
-- enough that a cast from a minute ago cannot claim a corpse's loot.
local GATHER_SECONDS = 10

-- How long a node's name under the mouse still names the cast, for a client
-- that sends the cast without saying what it was on.
local HOVER_SECONDS = 8

Gathering.MIN_GATHERS = MIN_GATHERS
Gathering.GATHER_SECONDS = GATHER_SECONDS

-- This session only: gathers per node, the order nodes were last gathered in,
-- and how many gathers in all. The panel's Gathering section shows only while
-- `sessionGathers` is above zero. `sessionItems` is how many of each item came
-- off a node, for the session's gathered value.
Gathering.session = {}
Gathering.sessionItems = {}
-- Which nodes each item came from this session: sessionFrom[item][node].
Gathering.sessionFrom = {}
Gathering.recent = {}
Gathering.clock = 0
Gathering.sessionGathers = 0

--------------------------------------------------------------------------------
-- Which casts are gathering
--------------------------------------------------------------------------------

-- By spell id: every rank of Herb Gathering and Mining the game has had.
local SPELL_KIND = {
    [2366] = "herb", [2368] = "herb", [3570] = "herb", [11993] = "herb",
    [2575] = "ore", [2576] = "ore", [3564] = "ore", [10248] = "ore",
}

-- By name, for a client whose ids differ.
local NAME_KIND = {
    ["Herb Gathering"] = "herb",
    ["Herbalism"] = "herb",
    ["Mining"] = "ore",
}

-- What a node is called when the client would not name it.
local UNNAMED = { herb = "Herb", ore = "Mineral vein" }

Gathering.SPELL_KIND = SPELL_KIND
Gathering.NAME_KIND = NAME_KIND

--- The client's clock in seconds, or nil if it will not say.
local function Now()
    if type(GetTime) ~= "function" then return nil end
    local ok, now = pcall(GetTime)
    return ok and ns.Harvest.ReadableNumber(now) or nil
end

--- A spell's name, or nil if the client will not say.
local function SpellName(spellID)
    if type(C_Spell) == "table" and type(C_Spell.GetSpellName) == "function" then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        local text = ok and ns.Harvest.Readable(name) or nil
        if text then return text end
    end

    if type(GetSpellInfo) == "function" then
        local ok, name = pcall(GetSpellInfo, spellID)
        return ok and ns.Harvest.Readable(name) or nil
    end

    return nil
end

--------------------------------------------------------------------------------
-- The client's own names for the gathering skills
--
-- The names above are English. A German client calls Mining "Bergbau", so a
-- name is also checked against what the client calls the same spell (by its
-- ID) and the same skill line (by its ID, through
-- C_TradeSkillUI.GetProfessionInfoBySkillLineID, which Forever has: see
-- Tradeskills' findings, both of Forever's skill line IDs). Fishing and
-- Spots read their skills by the same names.
--------------------------------------------------------------------------------

-- The skill lines, Forever's classic ID and its modern one.
Gathering.SKILL_LINES = {
    Mining = { 186, 2946 }, Herbalism = { 182, 2944 }, Skinning = { 393, 2947 }, Fishing = { 356 },
}
-- A spell of the same name.
Gathering.SKILL_SPELLS = {
    Mining = { 2575 }, ["Herb Gathering"] = { 2366 }, Skinning = { 8613 }, Fishing = { 7620 },
}

local clientNames = {}

--- Every name the client may give `english` (a skill, or Herb Gathering):
--- { [name] = true }, the English one always among them. Kept once the
--- client has named all of it.
function Gathering.ClientNames(english)
    local kept = clientNames[english]
    if kept and kept.complete then return kept.names end

    local names, complete = { [english] = true }, true
    for _, spellID in ipairs(Gathering.SKILL_SPELLS[english] or {}) do
        local name = SpellName(spellID)
        if name then names[name] = true else complete = false end
    end

    local trade = type(C_TradeSkillUI) == "table" and C_TradeSkillUI or nil
    local get = trade and trade.GetProfessionInfoBySkillLineID
    for _, line in ipairs(Gathering.SKILL_LINES[english] or {}) do
        local name
        if type(get) == "function" then
            local ok, info = pcall(get, line)
            if ok and type(info) == "table" then
                local got, value = pcall(function() return info.professionName end)
                name = got and ns.Harvest.Readable(value) or nil
            end
        end
        if name and name ~= "" then names[name] = true else complete = false end
    end

    clientNames[english] = { names = names, complete = complete }
    return names
end

--- The English skill `name` is, of `list` (English names), or nil.
function Gathering.SkillOf(name, list)
    if type(name) ~= "string" then return nil end
    for _, english in ipairs(list) do
        if name == english then return english end
    end
    if ns.Util.EnglishClient() then return nil end
    for _, english in ipairs(list) do
        if Gathering.ClientNames(english)[name] then return english end
    end
    return nil
end

--- "herb", "ore", or nil for any other spell.
function Gathering.KindOf(spellID)
    local id = ns.Harvest.ReadableNumber(spellID)
    if not id then return nil end

    if SPELL_KIND[id] then return SPELL_KIND[id] end

    local name = SpellName(id)
    if not name then return nil end
    if NAME_KIND[name] then return NAME_KIND[name] end

    -- The client's own word for the same skill.
    local skill = Gathering.SkillOf(name, { "Herb Gathering", "Herbalism", "Mining" })
    return skill and NAME_KIND[skill] or nil
end

-- Skinning, by every rank's id and by name for a client whose ids differ. It
-- is never a gather: it is only told apart, for IsSkinning.
local SKINNING_ID = { [8613] = true, [8617] = true, [8618] = true, [10768] = true }

--- Is `spellID` Skinning?
function Gathering.IsSkinningSpell(spellID)
    local id = ns.Harvest.ReadableNumber(spellID)
    if not id then return false end

    if SKINNING_ID[id] then return true end

    local name = SpellName(id)
    return name ~= nil and Gathering.SkillOf(name, { "Skinning" }) == "Skinning"
end

--------------------------------------------------------------------------------
-- The cast
--------------------------------------------------------------------------------

--- The game tooltip just showed: remember a world object's name, in case the
--- cast that follows does not say what it was on.
--
-- Units and items are never nodes, and one under the mouse means the node
-- before it is not what you are about to click.
function Gathering:OnTooltipShown(unitOrItem)
    local tooltip = GameTooltip
    if not tooltip then return end

    if unitOrItem == nil then unitOrItem = ns.Harvest.TooltipShowsUnitOrItem(tooltip) end
    if unitOrItem then
        self.hovered = nil
        return
    end

    local line = _G.GameTooltipTextLeft1
    if not line or type(line.GetText) ~= "function" then return end

    local ok, text = pcall(line.GetText, line)
    local name = ok and ns.Harvest.Readable(text) or nil

    if name then self.hovered = { name = name, at = Now() } end
end

--- A cast was sent. If it is you picking a herb or mining a vein, remember
--- what it was on and when.
--
-- UNIT_SPELLCAST_SENT: unit, target, castGUID, spellID.
function Gathering:OnCastSent(unit, target, castGUID, spellID)
    if ns.Harvest.Readable(unit) ~= "player" then return end

    -- A skin is only noted, for IsSkinning. It is no gather, so it still ends
    -- any gather in hand below.
    if Gathering.IsSkinningSpell(spellID) then
        self.skinning = { id = ns.Harvest.Readable(castGUID), at = Now() }
    end

    local kind = Gathering.KindOf(spellID)

    if not kind then
        -- Any other cast of yours means you are not gathering any more.
        if self.cast and not self.cast.looted then self.cast = nil end
        return
    end

    local now = Now()
    local node = ns.Harvest.Readable(target)

    if not node then
        local hovered = self.hovered
        if hovered and hovered.at and now and now - hovered.at <= HOVER_SECONDS then
            node = hovered.name
        end
    end

    -- A name names one cast.
    self.hovered = nil

    self.cast = {
        kind = kind,
        node = node or UNNAMED[kind],
        id = ns.Harvest.Readable(castGUID),
        at = now,
    }
end

--- A cast went through. A client that never sent UNIT_SPELLCAST_SENT still
--- says this, so a gather is not missed for want of the first.
function Gathering:OnCastSucceeded(unit, castGUID, spellID)
    if ns.Harvest.Readable(unit) ~= "player" then return end

    -- A skin gone through: its loot window opens next. The one noted when it
    -- was sent is held from now, as a gather is; one whose window is already
    -- open is left as it is.
    if Gathering.IsSkinningSpell(spellID) then
        local skinning, id = self.skinning, ns.Harvest.Readable(castGUID)
        if skinning and (not skinning.id or not id or skinning.id == id) then
            if not skinning.looted then skinning.at = Now() or skinning.at end
        else
            self.skinning = { id = id, at = Now() }
        end
        return
    end

    local kind = Gathering.KindOf(spellID)
    if not kind then return end

    local cast = self.cast
    local id = ns.Harvest.Readable(castGUID)

    if cast and not cast.looted and (not cast.id or not id or cast.id == id) then
        cast.at = Now() or cast.at
        return
    end

    self.cast = { kind = kind, node = UNNAMED[kind], id = id, at = Now() }
end

--- A cast failed or was interrupted: a gather that never finished opens no
--- loot, so it must not claim the next window that does.
function Gathering:OnCastStopped(unit, castGUID, spellID)
    if ns.Harvest.Readable(unit) ~= "player" then return end

    local id = ns.Harvest.Readable(castGUID)

    -- The same for a skin. By its cast guid when both can be read, else by
    -- the spell: another spell failing while you skin is not the skin.
    local skinning = self.skinning
    if skinning then
        local same
        if skinning.id and id then
            same = skinning.id == id
        else
            same = Gathering.IsSkinningSpell(spellID)
        end
        if same then self.skinning = nil end
    end

    local cast = self.cast
    if not cast or cast.looted then return end

    if (cast.id and id and cast.id == id) or (not id and Gathering.KindOf(spellID)) then
        self.cast = nil
    end
end

--- Is the open loot window a node's?
--
-- The harvester and the kill tally ask this before they read the target, so
-- a herb picked beside a looted corpse is never that corpse's drop.
function Gathering:IsGathering()
    local cast = self.cast
    if not cast then return false end

    local now = Now()
    if cast.at and now then return now - cast.at <= GATHER_SECONDS end

    -- No clock to hold it to: it lasts until its loot window closes.
    return true
end

--- Is the open loot window one you are skinning?
--
-- True from your own Skinning cast, sent or gone through, until its loot
-- window closes or GATHER_SECONDS pass; a skin that failed or was
-- interrupted ends it. The harvester and the kill tally ask this so a corpse
-- first opened by skinning (another player's kill, one an area loot already
-- emptied, one looted before a /reload) is not taken for a fresh kill.
function Gathering:IsSkinning()
    local skinning = self.skinning
    if not skinning then return false end

    local now = Now()
    if skinning.at and now then return now - skinning.at <= GATHER_SECONDS end

    -- No clock to hold it to: it lasts until its loot window closes.
    return true
end

--------------------------------------------------------------------------------
-- The record
--------------------------------------------------------------------------------

--- Every node gathered, kept in saved variables from one session to the next.
function Gathering:Store()
    local db = ns.db

    if type(db.gathering) ~= "table" then db.gathering = {} end
    if type(db.gathering.nodes) ~= "table" then db.gathering.nodes = {} end

    return db.gathering.nodes
end

function Gathering.NodeKey(zone, location, node)
    return ("%s|%s|%s"):format(zone or "?", location or "", node or "?")
end

function Gathering:GetNode(zone, location, node, kind)
    local key = Gathering.NodeKey(zone, location, node)
    local nodes = self:Store()
    local entry = nodes[key]

    if type(entry) ~= "table" then
        entry = { zone = zone, location = location, node = node, kind = kind }
        nodes[key] = entry
    end

    entry.gathers = tonumber(entry.gathers) or 0
    if type(entry.items) ~= "table" then entry.items = {} end

    return entry, key
end

--- Count one gather. Returns the node.
--
-- `items` are names, each once; `quantities` how many of each came up.
function Gathering:Record(zone, location, node, kind, items, quantities, coords)
    local entry, key = self:GetNode(zone, location, node, kind)

    entry.gathers = entry.gathers + 1

    for _, name in ipairs(items or {}) do
        local item = entry.items[name]

        if type(item) ~= "table" then
            item = { gathers = 0, count = 0 }
            entry.items[name] = item
        end

        local quantity = quantities and quantities[name] or 1

        item.gathers = (tonumber(item.gathers) or 0) + 1
        item.count = (tonumber(item.count) or 0) + quantity
        item.id = item.id or ns.Tracker:LookOf(name).id

        self.sessionItems[name] = (self.sessionItems[name] or 0) + quantity
        if ns.Stats then ns.Stats:Loot("gather", name, quantity) end
        if type(node) == "string" and node ~= "" then
            self.sessionFrom[name] = self.sessionFrom[name] or {}
            self.sessionFrom[name][node] = (self.sessionFrom[name][node] or 0) + quantity
        end
    end

    if coords and not entry.coords then
        entry.coords = { coords[1], coords[2] }
    end

    -- Made with Bountiful Harvest: noted beside the record, so it never
    -- reaches anyone's rates (Logic/Legacy.lua).
    local boost = ns.Legacy and ns.Legacy:GatherBoost(kind)
    if boost then ns.Legacy.Note(entry, "gathers", items, quantities, boost) end

    -- How long it took, for the Grind tab's worth an hour. Only herbs and
    -- veins: a chest opened between two herbs is not part of their pace.
    if ns.GrindGather and (kind == "herb" or kind == "ore") then ns.GrindGather:NoteGather(zone, node, items, quantities) end

    self.session[key] = (self.session[key] or 0) + 1
    self.sessionGathers = self.sessionGathers + 1
    self.clock = self.clock + 1
    self.recent[key] = self.clock

    -- Whichever you did last goes on top of the panel.
    ns.lastLoot = "gathering"

    if ns.TrackerUI then ns.TrackerUI:Refresh() end

    -- The gather that unlocks rates gets the same fanfare as a 20th kill.
    if entry.gathers == MIN_GATHERS then
        self:Celebrate(key)
    end

    return entry
end

function Gathering:Celebrate(key)
    if ns.db.trackerCelebrate == false then return end

    local summary = self:Summary(key)
    if not summary then return end

    local where = summary.place and L.Format(" in %s", summary.place) or ""
    local line = L.Format("Gather rates unlocked for %s%s after %d gathers.",
        Util.Colored("accent", summary.name), where, summary.gathers)

    ns.Tracker:Fanfare(line,
        { title = L["GATHER RATES UNLOCKED"], subject = L.Format("%s  |  %d gathers", summary.name, summary.gathers),
            key = "node:" .. tostring(key) })
end

--- One node's yield, most often found first.
function Gathering:Summary(key)
    local entry = self:Store()[key]
    if type(entry) ~= "table" then return nil end

    local gathers = tonumber(entry.gathers) or 0
    local items = {}

    for name, item in pairs(type(entry.items) == "table" and entry.items or {}) do
        local held = type(item) == "table" and tonumber(item.gathers) or 0
        items[#items + 1] = {
            name = name,
            gathers = held,
            count = type(item) == "table" and tonumber(item.count) or held,
            id = type(item) == "table" and tonumber(item.id) or nil,
            chance = gathers > 0 and math.min(100, held / gathers * 100) or 0,
        }
    end

    table.sort(items, function(a, b)
        if a.gathers ~= b.gathers then return a.gathers > b.gathers end
        return a.name < b.name
    end)

    return {
        key = key,
        node = entry,
        name = entry.node or "?",
        place = ns.Tracker.PlaceName(ns.Spots.Show(entry.zone), entry.location),
        gathers = gathers,
        session = self.session[key] or 0,
        rated = gathers >= MIN_GATHERS,
        needed = math.max(0, MIN_GATHERS - gathers),
        items = items,
    }
end

--- Every node gathered this session, most recent first, as summaries.
function Gathering:SessionNodes()
    local nodes = {}

    for key in pairs(self.session) do
        local summary = self:Summary(key)
        if summary then nodes[#nodes + 1] = summary end
    end

    table.sort(nodes, function(a, b)
        return (self.recent[a.key] or 0) > (self.recent[b.key] or 0)
    end)

    return nodes
end

--- Every node ever gathered, most gathers first; only those in `zone` if given.
function Gathering:Nodes(zone)
    local nodes = {}

    for key, entry in pairs(self:Store()) do
        if type(entry) == "table" and (not zone or entry.zone == zone) then
            local summary = self:Summary(key)
            if summary and summary.gathers > 0 then nodes[#nodes + 1] = summary end
        end
    end

    table.sort(nodes, function(a, b)
        if a.gathers ~= b.gathers then return a.gathers > b.gathers end
        return a.key < b.key
    end)

    return nodes
end

function Gathering:CountGathers()
    local total = 0
    for _, entry in pairs(self:Store()) do
        if type(entry) == "table" then total = total + (tonumber(entry.gathers) or 0) end
    end
    return total
end

--- What one gather of a node is worth, in copper, once it has MIN_GATHERS.
-- Nil below the threshold, or when nothing it gave has a price.
function Gathering:WorthPerGather(key)
    local summary = self:Summary(key)
    if not (summary and summary.rated and ns.Value) then return nil end

    local total, priced = 0, 0

    for _, item in ipairs(summary.items) do
        local unit = ns.Value:UnitPrice(ns.Value:ItemID(item.name))
        if unit then
            total = total + item.count / summary.gathers * unit
            priced = priced + 1
        end
    end

    if priced == 0 then return nil end

    return total
end

function Gathering:Reset()
    -- Shared and imported counts went with the records: their ledgers too.
    if ns.Share and ns.Share.ForgetSection then ns.Share:ForgetSection("g") end
    -- The record only. The map markers live in the same table and have their
    -- own clear (/farm markers clear), so they stay.
    if type(ns.db.gathering) == "table" then ns.db.gathering.nodes = nil end
    self.session = {}
    self.sessionItems = {}
    self.sessionFrom = {}
    self.recent = {}
    self.sessionGathers = 0
    self.cast = nil

    if ns.TrackerUI then ns.TrackerUI:Refresh() end
    self:SpotsChanged()
end

--------------------------------------------------------------------------------
-- Where on the map
--
-- The node record above is per zone and subzone, which says where to go but
-- not where to stand. For the map markers each gather also keeps the exact
-- spot: the map it was on and where on that map, as fractions of it, which is
-- how the world map and the minimap both place things.
--
-- Gathering the same node again lands on the spot already there rather than a
-- second marker on top of it: same map, same node name, within SAME_SPOT_YARDS
-- (or SAME_SPOT_SHARE of the map, on a client that will not size its maps).
--------------------------------------------------------------------------------

local SAME_SPOT_YARDS = 15
local SAME_SPOT_SHARE = 0.005

-- Enough for every node in every zone many times over. Past it the spot
-- gathered longest ago goes, so the saved file cannot grow for ever.
local MAX_SPOTS = 2000

Gathering.MAX_SPOTS = MAX_SPOTS

--- Wall-clock seconds, which, unlike GetTime, mean the same after a restart.
local function Clock()
    if type(time) ~= "function" then return nil end
    local ok, now = pcall(time)
    return ok and ns.Harvest.ReadableNumber(now) or nil
end

Gathering.Clock = Clock

local mapSizes = {}

--- How big a map is, in yards: width, height. Nil if the client will not say.
function Gathering.MapSize(mapID)
    local cached = mapSizes[mapID]
    if cached then return cached[1], cached[2] end
    if cached == false or type(C_Map) ~= "table" then return nil end

    local width, height

    if type(C_Map.GetMapWorldSize) == "function" then
        local ok, w, h = pcall(C_Map.GetMapWorldSize, mapID)
        if ok then
            width, height = ns.Harvest.ReadableNumber(w), ns.Harvest.ReadableNumber(h)
        end
    end

    -- The older way round: where the map's two corners are in the world.
    -- Across a map is along the world's y axis, down it along the x axis.
    if not (width and height) and type(C_Map.GetWorldPosFromMapPos) == "function"
        and type(CreateVector2D) == "function" then
        local function Corner(u, v)
            local ok, _, position = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(u, v))
            if not ok or type(position) ~= "table" then return nil end
            local read, wx, wy = pcall(position.GetXY, position)
            if not read then return nil end
            return ns.Harvest.ReadableNumber(wx), ns.Harvest.ReadableNumber(wy)
        end

        local ax, ay = Corner(0, 0)
        local bx, by = Corner(1, 1)
        if ax and ay and bx and by then
            width, height = math.abs(ay - by), math.abs(ax - bx)
        end
    end

    if not (width and height and width > 0 and height > 0) then
        mapSizes[mapID] = false
        return nil
    end

    mapSizes[mapID] = { width, height }
    return width, height
end

--- Every spot a node was gathered at, kept in saved variables.
function Gathering:Spots()
    local db = ns.db

    if type(db.gathering) ~= "table" then db.gathering = {} end
    if type(db.gathering.spots) ~= "table" then db.gathering.spots = {} end

    return db.gathering.spots
end

--- Are two points on one map close enough to be the same node?
local function SameSpot(mapID, ax, ay, bx, by)
    local width, height = Gathering.MapSize(mapID)

    if width then
        local dx, dy = (ax - bx) * width, (ay - by) * height
        return dx * dx + dy * dy <= SAME_SPOT_YARDS * SAME_SPOT_YARDS
    end

    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy <= SAME_SPOT_SHARE * SAME_SPOT_SHARE
end

Gathering.SameSpot = SameSpot

-- Era grows a different herb or vein on one spawn point from time to time,
-- so any herb or vein this close to a spot of its own kind is that spot,
-- whatever its name (the owner, 2026-10-24: "within about 3 meters"). About
-- 3 meters, in yards; NEAR_SHARE of the map on a client that will not size
-- its maps. A fishing spot never joins another.
local NEAR_YARDS = 3.3
local NEAR_SHARE = 0.001

Gathering.NEAR_YARDS = NEAR_YARDS

--- Are two points on one map within NEAR_YARDS?
local function NearSpot(mapID, ax, ay, bx, by)
    ax, ay, bx, by = tonumber(ax), tonumber(ay), tonumber(bx), tonumber(by)
    if not (ax and ay and bx and by) then return false end
    local width, height = Gathering.MapSize(mapID)
    local dx, dy = ax - bx, ay - by
    if width then
        dx, dy = dx * width, dy * height
        return dx * dx + dy * dy <= NEAR_YARDS * NEAR_YARDS
    end
    return dx * dx + dy * dy <= NEAR_SHARE * NEAR_SHARE
end

Gathering.NearSpot = NearSpot

--- Does a gather of `node` (`kind`) at x, y land on `spot`? The same node
--- within SAME_SPOT_YARDS, or any herb or vein within NEAR_YARDS of one of
--- its own kind. A fishing spot joins only its own school.
function Gathering.Joins(spot, mapID, x, y, node, kind)
    if type(spot) ~= "table" or spot.map ~= mapID then return false end
    local sx, sy = tonumber(spot.x), tonumber(spot.y)
    if not (sx and sy) then return false end
    if spot.node == node and SameSpot(mapID, sx, sy, x, y) then return true end
    return kind ~= nil and kind ~= "fish" and spot.kind == kind and NearSpot(mapID, sx, sy, x, y)
end

--- The spots to draw: one for each place, the one gathered last, where
--- older saves kept two herbs or two veins within NEAR_YARDS. In their saved
--- order, so a redraw keeps each marker on its spot. Nothing saved changes.
function Gathering.Joined(spots)
    local order = {}
    for index, spot in ipairs(spots) do order[index] = spot end
    table.sort(order, function(a, b) return (tonumber(a.last) or 0) > (tonumber(b.last) or 0) end)

    local kept = {}
    for _, spot in ipairs(order) do
        local taken = false
        if spot.kind ~= "fish" then
            for _, other in ipairs(kept) do
                if other.kind == spot.kind and NearSpot(spot.map, other.x, other.y, spot.x, spot.y) then
                    taken = true
                    break
                end
            end
        end
        if not taken then kept[#kept + 1] = spot end
    end
    if #kept == #spots then return spots end

    local keep, found = {}, {}
    for _, spot in ipairs(kept) do keep[spot] = true end
    for _, spot in ipairs(spots) do
        if keep[spot] then found[#found + 1] = spot end
    end
    return found
end

--- What a gather gave, added to its spot's own count (`spot.items[name]`,
--- never renamed), so the world map shows the item it gave most.
local function NoteItems(spot, items, quantities)
    if type(items) ~= "table" or #items == 0 then return end
    if type(spot.items) ~= "table" then spot.items = {} end
    for _, name in ipairs(items) do
        if type(name) == "string" and name ~= "" then
            local quantity = quantities and tonumber(quantities[name]) or 1
            spot.items[name] = (tonumber(spot.items[name]) or 0) + quantity
        end
    end
end

Gathering.NoteItems = NoteItems

--- Mark a gather on the map. `x` and `y` are fractions of map `mapID`.
-- `kind` is "herb", "ore" or "fish" (a cast into a school you moused over,
-- from Logic/Fishing.lua); `items` and `quantities` are what it gave. A
-- school never grows back, so it teaches Logic/Respawn.lua nothing.
-- Returns the spot.
function Gathering:AddSpot(mapID, x, y, node, kind, items, quantities)
    if not (mapID and x and y) then return nil end

    local spots = self:Spots()
    local now = Clock()

    for _, spot in ipairs(spots) do
        if Gathering.Joins(spot, mapID, x, y, node, kind) then
            -- Back at a spot already taken: how long it took is what
            -- Logic/Respawn.lua learns grow-back times from, only when it is
            -- the same node again: another name there says nothing about
            -- this one's time.
            local last = tonumber(spot.last)
            if now and last and ns.Respawn and kind ~= "fish" and spot.node == node then
                ns.Respawn:Learn(mapID, node, now - last)
            end

            spot.gathers = (tonumber(spot.gathers) or 1) + 1
            spot.last = now or spot.last
            NoteItems(spot, items, quantities)
            -- Another herb or vein grown on it: kept beside it (`spot.also`,
            -- never renamed), so that name counts as gathered here too.
            if type(node) == "string" and node ~= spot.node then
                if type(spot.also) ~= "table" then spot.also = {} end
                spot.also[node] = true
            end
            self:SpotsChanged()
            return spot
        end
    end

    local spot = {
        map = mapID, x = x, y = y, node = node, kind = kind,
        gathers = 1, first = now, last = now,
    }
    NoteItems(spot, items, quantities)
    spots[#spots + 1] = spot

    -- Over the cap: the one gathered longest ago goes.
    while #spots > MAX_SPOTS do
        local oldest, at = 1, math.huge
        for index, candidate in ipairs(spots) do
            local when = tonumber(candidate.last) or 0
            if when < at then oldest, at = index, when end
        end
        table.remove(spots, oldest)
    end

    self:SpotsChanged()
    return spot
end

--- Every spot on one map.
function Gathering:SpotsOn(mapID)
    local found = {}
    if not mapID then return found end

    for _, spot in ipairs(self:Spots()) do
        if type(spot) == "table" and spot.map == mapID
            and tonumber(spot.x) and tonumber(spot.y) then
            found[#found + 1] = spot
        end
    end

    return found
end

--- Forget every marked spot. The gathering record itself is left alone.
function Gathering:ClearSpots()
    local count = #self:Spots()
    ns.db.gathering.spots = {}
    self:SpotsChanged()
    return count
end

--- Tell the markers to redraw.
function Gathering:SpotsChanged()
    self.spotsVersion = (self.spotsVersion or 0) + 1
    if ns.MapMarkers then ns.MapMarkers:Refresh() end
end

--------------------------------------------------------------------------------
-- Reading the loot window
--------------------------------------------------------------------------------

function Gathering:OnLoot()
    -- A skin's window is open: the skin ends when it closes. Marked rather
    -- than ended on any close, so a window shut as the skin began does not
    -- end it early.
    if self.skinning then self.skinning.looted = true end

    if not self:IsGathering() then return end

    local cast = self.cast

    -- One window is one gather. A second LOOT_OPENED for it is the same one.
    if cast.looted then return end
    cast.looted = true

    -- A catch is fishing's, whatever else was going on.
    if ns.Fishing and ns.Fishing:IsCatch() then return end

    -- The same pause as the harvester: recording off means nothing recorded.
    if ns.db.harvestPaused then return end

    local zone, location = ns.Harvest:Where()
    local items, quantities = ns.Tracker:LootedItems(true)
    local mapID, x, y = ns.Harvest:PlayerMapPosition()

    if mapID then
        self:AddSpot(mapID, x, y, cast.node, cast.kind, items, quantities)
    end

    return self:Record(zone, location, cast.node, cast.kind, items, quantities,
        mapID and { x * 100, y * 100 } or nil)
end

--- The window closed: the gather or the skin it belonged to is over.
function Gathering:OnLootClosed()
    if self.cast and self.cast.looted then self.cast = nil end
    if self.skinning and self.skinning.looted then self.skinning = nil end
end

--------------------------------------------------------------------------------
-- Herbs and ore already credited to a mob
--
-- Before this module, a herb picked with a looted corpse still targeted went
-- down as that corpse's drop. This finds any such entry in the kill tally and
-- the harvest and lists it. It changes nothing: what to do with them is
-- the player's call.
--------------------------------------------------------------------------------

--- Is `name` a herb or an ore that no mob in the seed data drops?
function Gathering.IsNodeOnly(name)
    local item = ns.DB and ns.DB:GetItem(name)
    if not item then return false end
    if item.category ~= "Herbalism" and item.category ~= "Mining" then return false end

    -- "node" is a vein, "herb" a herb. A single source of any other kind --
    -- a mob, a container -- and a mob holding it could be right.
    --
    -- Only the seed data is asked. Rows marked "forever" were written by the
    -- harvest import from the very records this check reads, so a herb once
    -- credited to a mob would vouch for itself and never be listed; the
    -- guild's rows are records of the same kind.
    local any = false

    for _, source in ipairs(item.sources or {}) do
        if source.provenance ~= "forever" and source.provenance ~= "guild" then
            if source.kind ~= "node" and source.kind ~= "herb" then return false end
            any = true
        end
    end

    return any
end

--- Every mob tally or harvest record holding a node-only item:
--- { where = "tally" | "harvest", mob, item, times, of }.
function Gathering:Suspects()
    local found = {}

    local tally = type(ns.db.tracker) == "table" and ns.db.tracker.mobs
    for mobName, mob in pairs(type(tally) == "table" and tally or {}) do
        if type(mob) == "table" and type(mob.items) == "table" then
            for name, times in pairs(mob.items) do
                if Gathering.IsNodeOnly(name) then
                    found[#found + 1] = { where = "tally", mob = mobName, item = name,
                        times = tonumber(times) or 0, of = tonumber(mob.kills) or 0 }
                end
            end
        end
    end

    -- The live harvest; ns.db.harvest is the same table once it is restored.
    local harvest = ns.Harvest.records or ns.db.harvest

    for _, record in pairs(type(harvest) == "table" and harvest or {}) do
        if type(record) == "table" and type(record.items) == "table" then
            for name, entry in pairs(record.items) do
                if Gathering.IsNodeOnly(name) then
                    found[#found + 1] = { where = "harvest", mob = record.mob, item = name,
                        times = type(entry) == "table" and tonumber(entry.corpses) or 0,
                        of = tonumber(record.corpses) or 0 }
                end
            end
        end
    end

    table.sort(found, function(a, b)
        if a.where ~= b.where then return a.where > b.where end
        if a.mob ~= b.mob then return tostring(a.mob) < tostring(b.mob) end
        return a.item < b.item
    end)

    return found
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Gathering:OnEnable()
    if not ns.Harvest:Capabilities().usable then return end

    ns.OnLootWindow(self, function() Gathering:OnLoot() end)
    ns.RegisterEvent(self, "LOOT_CLOSED", function() Gathering:OnLootClosed() end)

    ns.RegisterPlayerEvent(self, "UNIT_SPELLCAST_SENT", function(_, _, ...)
        Gathering:OnCastSent(...)
    end)

    ns.RegisterPlayerEvent(self, "UNIT_SPELLCAST_SUCCEEDED", function(_, _, ...)
        Gathering:OnCastSucceeded(...)
    end)

    for _, event in ipairs({ "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
        ns.RegisterPlayerEvent(self, event, function(_, _, ...)
            Gathering:OnCastStopped(...)
        end)
    end

    ns.Harvest.WatchTooltip("Gathering", function(_, unitOrItem)
        Gathering:OnTooltipShown(unitOrItem)
    end)
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local function PrintNode(summary)
    ns.PrintRaw(("%s  %s"):format(
        Util.Colored("accent", summary.name),
        Util.Colored("muted", ("%s, %s"):format(summary.place or "?",
            Util.Plural(summary.gathers, L["gather"], L["gathers"])))))

    for _, item in ipairs(summary.items) do
        local right = summary.rated and ns.Tracker.FormatChance(item.chance)
            or L.Format("%d of %d", item.gathers, summary.gathers)
        ns.PrintRaw(("  %s %s"):format(Util.ColorItem(item.name, item.id), Util.Colored("muted", right)))
    end

    if not summary.rated then
        ns.PrintRaw(Util.Colored("muted", summary.needed == 1
            and L["  1 more gather for gather rates."]
            or L.Format("  %d more gathers for gather rates.", summary.needed)))
    end
end

local function PrintSuspects()
    local found = Gathering:Suspects()

    if #found == 0 then
        ns.Print("no herbs or ore are credited to any mob. Your kill data is clean.")
        return
    end

    ns.Print(("%s %s like a herb or ore picked with a corpse still targeted. "
        .. "Nothing has been changed:"):format(
            Util.Plural(#found, "entry", "entries"), #found == 1 and "looks" or "look"))

    for _, entry in ipairs(found) do
        local what = entry.where == "tally" and "kill tally" or "harvest"
        local unit = entry.where == "tally" and "kills" or "corpses"
        ns.PrintRaw(("  %s: %s %s"):format(
            Util.Colored("accent", entry.mob or "?"), entry.item,
            Util.Colored("muted", ("%d of %d %s, in the %s"):format(
                entry.times, entry.of, unit, what))))
    end
end

ns.RegisterCommand("gathering", L["herbs and ore you've gathered in this zone (all for everywhere, check for odd gathers)"], function(rest)
    local argument = Util.Trim(rest):lower()

    if argument == "check" then
        ns.KeepCheck("gathering check", function()
            PrintSuspects()
            if ns.Legacy then ns.Print(ns.Legacy:CheckLine()) end
        end)
        return
    end

    if argument == "reset" then
        ns.Print(L.Format("this deletes all %s you have recorded, for good. Your map markers stay. Type /farm gathering reset confirm to do it.",
            Util.Plural(Gathering:CountGathers(), L["gather"], L["gathers"])))
        return
    end

    if argument == "reset confirm" then
        Gathering:Reset()
        ns.Print(L["your gathering counts are cleared."])
        return
    end

    local zone = argument ~= "all" and ns.Harvest:Where() or nil
    local nodes = Gathering:Nodes(zone)

    if #nodes == 0 then
        if zone and Gathering:CountGathers() > 0 then
            ns.Print(L.Format("nothing gathered in %s yet. /farm gathering all shows everywhere.", zone))
        else
            ns.Print(L["nothing gathered yet. Pick a herb or mine a vein and try again."])
        end
        return
    end

    ns.Print(zone and L.Format("gathered in %s:", zone) or L["gathered everywhere:"])
    for _, summary in ipairs(nodes) do PrintNode(summary) end
end)
