-- Blackthornes Farmer -- Logic/Respawn.lua
-- Roughly when a herb or vein you took grows back, learned from your own
-- gathering.
--
-- Forever's respawn timers are not published, and Classic's figures online
-- may not be Forever's, so nothing here is typed in or copied: every number
-- comes from the player's own returns. A return is gathering a node at a
-- marked spot again (Logic/Gathering.lua's AddSpot, same map, same node,
-- same place). The time since that spot was last taken is one gap: the node
-- had grown back by then, so its respawn is no longer than that.
--
-- Gaps under MIN_GAP are the same visit (a vein mined three times opens three
-- loot windows a few seconds apart), and gaps over MAX_GAP say only that you
-- were away, so neither is kept. Each node on each map keeps its MAX_GAPS
-- latest gaps. Below MIN_RETURNS the answer is "?". From there the estimate
-- is the middle of the three shortest gaps: the quick returns are the ones
-- that tell how soon a node comes back, and the middle of three keeps one
-- lucky return from setting it alone.
--
-- Kept in saved variables under gathering.respawn, a key of its own; the
-- gathering record and the map spots are only read. Nothing is sent anywhere.

local _, ns = ...
local L = ns.L

local Respawn = ns.NewModule("Respawn")

local MIN_GAP = 60
local MAX_GAP = 2 * 60 * 60
local MAX_GAPS = 20
local MIN_RETURNS = 3

Respawn.MIN_GAP = MIN_GAP
Respawn.MAX_GAP = MAX_GAP
Respawn.MAX_GAPS = MAX_GAPS
Respawn.MIN_RETURNS = MIN_RETURNS

--- Every node's gaps, by map and node name.
function Respawn:Store()
    local db = ns.db

    if type(db.gathering) ~= "table" then db.gathering = {} end
    if type(db.gathering.respawn) ~= "table" then db.gathering.respawn = {} end

    return db.gathering.respawn
end

function Respawn.Key(mapID, node)
    return ("%s|%s"):format(tostring(mapID or "?"), tostring(node or "?"))
end

--- A spot was gathered again, `gap` seconds after the last time. Returns true
--- when the gap was kept.
function Respawn:Learn(mapID, node, gap)
    gap = tonumber(gap)
    if not (mapID and node and gap) then return false end
    if gap < MIN_GAP or gap > MAX_GAP then return false end

    local store = self:Store()
    local key = Respawn.Key(mapID, node)
    local entry = store[key]

    if type(entry) ~= "table" then
        entry = {}
        store[key] = entry
    end
    if type(entry.gaps) ~= "table" then entry.gaps = {} end

    local gaps = entry.gaps
    gaps[#gaps + 1] = math.floor(gap + 0.5)
    while #gaps > MAX_GAPS do table.remove(gaps, 1) end

    return true
end

--- What is known for a node on a map: { seconds = estimate or nil,
--- returns = how many gaps, needed = how many more before an estimate }.
function Respawn:Estimate(mapID, node)
    local entry = self:Store()[Respawn.Key(mapID, node)]
    local sorted = {}

    if type(entry) == "table" and type(entry.gaps) == "table" then
        for _, gap in ipairs(entry.gaps) do
            gap = tonumber(gap)
            if gap then sorted[#sorted + 1] = gap end
        end
    end

    table.sort(sorted)

    local returns = #sorted
    local result = { returns = returns, needed = math.max(0, MIN_RETURNS - returns) }

    if returns >= MIN_RETURNS then result.seconds = sorted[2] end

    return result
end

--- "under a minute", "7 min", "1 h 20 min".
function Respawn.Duration(seconds)
    seconds = math.max(0, tonumber(seconds) or 0)
    if seconds < 60 then return L["under a minute"] end

    local minutes = math.floor(seconds / 60 + 0.5)
    if minutes < 60 then return L.Format("%d min", minutes) end

    local hours, rest = math.floor(minutes / 60), minutes % 60
    if rest == 0 then return L.Format("%d h", hours) end
    return L.Format("%d h %d min", hours, rest)
end

local function Learning(estimate)
    return L.Format("Grows back: ?  (learning, %d of %d returns)", estimate.returns, MIN_RETURNS)
end

local function From(estimate)
    if estimate.returns == 1 then return L["1 return"] end
    return L.Format("%d returns", estimate.returns)
end

--- When this spot's node should be back (a time() stamp), or nil while its
--- grow-back time is still being learned, or for a fishing school.
function Respawn:BackAt(spot)
    if type(spot) ~= "table" or spot.kind == "fish" then return nil end
    local last = tonumber(spot.last)
    if not last then return nil end
    local estimate = self:Estimate(spot.map, spot.node)
    return estimate.seconds and last + estimate.seconds or nil
end

--- The line for a map marker: how long until this spot's node is back.
function Respawn:SpotLine(spot, now)
    if type(spot) ~= "table" or spot.kind == "fish" then return nil end

    local estimate = self:Estimate(spot.map, spot.node)
    if not estimate.seconds then return Learning(estimate), false end

    local last, clock = tonumber(spot.last), tonumber(now)
    if not (last and clock) then
        return L.Format("Grows back in about %s  (from %s)",
            Respawn.Duration(estimate.seconds), From(estimate)), true
    end

    local left = last + estimate.seconds - clock
    if left <= 0 then
        return L.Format("Should be back by now  (from %s)", From(estimate)), true
    end

    return L.Format("Back in about %s  (from %s)", Respawn.Duration(left), From(estimate)), true
end

--- The line for a node under the mouse in the world: how long it takes to
--- grow back on this map. Nil for anything never gathered on this map.
function Respawn:NodeLine(mapID, node)
    if not (mapID and node) then return nil end

    local estimate = self:Estimate(mapID, node)

    if not estimate.seconds then
        if not self:Gathered(mapID, node) then return nil end
        return Learning(estimate), false
    end

    return L.Format("Grows back in about %s here  (from %s)",
        Respawn.Duration(estimate.seconds), From(estimate)), true
end

--- Has a node of this name been marked on this map?
function Respawn:Gathered(mapID, node)
    for _, spot in ipairs(ns.Gathering:SpotsOn(mapID)) do
        -- A fishing school never grows back: nothing to learn about it.
        if spot.kind ~= "fish" and (spot.node == node
            or (type(spot.also) == "table" and spot.also[node])) then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- The node's own tooltip
--
-- Hovering a herb or a vein shows the game's tooltip with its name. Once that
-- node has been gathered on this map, one line is added under it. Units and
-- items are never nodes and get nothing, and the line goes in once per
-- showing.
--------------------------------------------------------------------------------

function Respawn:OnTooltipShown(tooltip, unitOrItem)
    tooltip = tooltip or GameTooltip
    if type(tooltip) ~= "table" or self.adding or self.added == tooltip then return end

    if unitOrItem == nil then unitOrItem = ns.Harvest.TooltipShowsUnitOrItem(tooltip) end
    if unitOrItem then return end

    local first = _G.GameTooltipTextLeft1
    if not first or type(first.GetText) ~= "function" then return end

    local ok, text = pcall(first.GetText, first)
    local name = ok and ns.Harvest.Readable(text) or nil
    if not name then return end

    local mapID = ns.Harvest:PlayerMapPosition()
    local line, known = self:NodeLine(mapID, name)
    if not line then return end

    self.added = tooltip
    self.adding = true
    pcall(function()
        local r, g, b
        if ns.Theme then r, g, b = ns.Theme.Unpack(known and "accent" or "muted") end
        tooltip:AddLine(line, r, g, b)
        tooltip:Show()
    end)
    self.adding = false
end

function Respawn:OnTooltipGone(tooltip)
    if self.added == (tooltip or GameTooltip) then self.added = nil end
end

function Respawn:OnEnable()
    if not (GameTooltip and type(GameTooltip.HookScript) == "function") then return end

    ns.Harvest.WatchTooltip("Respawn", function(tooltip, unitOrItem)
        Respawn:OnTooltipShown(tooltip, unitOrItem)
    end)

    for _, script in ipairs({ "OnHide", "OnTooltipCleared" }) do
        pcall(GameTooltip.HookScript, GameTooltip, script, function(tooltip)
            Respawn:OnTooltipGone(tooltip)
        end)
    end
end
