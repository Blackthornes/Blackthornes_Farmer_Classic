-- Blackthornes Farmer -- Logic/RankUp.lua
-- A mob that climbs your measured board, or joins its top 15, gets a short
-- pop-up showing the move (the owner, 2026-10-13: more of a lift while
-- farming, and something useful at the same time).
--
-- The board is Rankings' measured one (your own kills, MIN_KILLS or more,
-- coin included), never the estimates. What this keeps is the order as it
-- last stood, so a kill can be compared with it: the "before" the pop-up
-- shows and slides from.
--
-- Smooth play: the order is laid out once, a few mobs a frame, after you
-- log in. After that a kill only marks its mob; a second after the loot
-- (and never in a fight) the tallies are looked over, and only the mobs
-- whose kill count moved are valued again. One pop-up at most per look,
-- for the mob that moved most.
--
-- Nothing here is saved: the order is worked out again each session.
--
-- The kills panel reads the same order for the rank on each card
-- (`RankUp:RankOf`), so the order is kept up even with the pop-up off.

local _, ns = ...
local L = ns.L

local RankUp = ns.NewModule("RankUp")

local Util = ns.Util

-- How many of the board the pop-up shows, and only moves into them count.
RankUp.TOP = 15
-- Seconds after the loot before looking, so a burst of loot windows (an
-- area loot, a skinned corpse) settles first.
RankUp.SETTLE = 1
-- Mobs valued a frame while the order is first laid out.
RankUp.SLICE = 4
-- Seconds after logging in before that starts.
RankUp.START = 3

function RankUp.On()
    return not (ns.db and ns.db.rankUpPopup == false)
end

function RankUp.SoundOn()
    return not (ns.db and ns.db.rankUpSound == false)
end

--- What decides who is on the board besides kills and prices: the hide list
--- and Rankings' "Outside dungeons only". An order laid out under another
--- stamp is laid out again.
local function Stamp()
    return ("%d:%d"):format(ns.DB.hiddenVersion or 0, ns.Rankings.outsideVersion or 0)
end
RankUp.Stamp = Stamp

--- Measured or nothing: Rankings' own entry for the mob, so the pop-up and
--- the Rankings tab never disagree on a number.
local function Measured(name)
    if ns.Rankings:LeftOut(name) then return nil end
    local ok, entry = pcall(ns.Rankings.Entry, ns.Rankings, name)
    if ok and entry and entry.group == "measured" then
        return { mob = name, value = entry.value, kills = entry.kills }
    end
    return nil
end

local function KillsOf(record)
    return type(record) == "table" and tonumber(record.kills) or 0
end

local function ByValue(a, b)
    if a.value ~= b.value then return a.value > b.value end
    return a.mob < b.mob
end

--- The order from `byMob`, best first, ranks set.
local function Order(byMob)
    local list = {}
    for _, entry in pairs(byMob) do list[#list + 1] = entry end
    table.sort(list, ByValue)
    for rank, entry in ipairs(list) do entry.rank = rank end
    return list
end

--- Copies of the first `count` entries of `list`, so what the pop-up holds
--- never changes under it.
local function Top(list, count)
    local out = {}
    for index = 1, math.min(count, #list) do
        local entry = list[index]
        out[index] = { mob = entry.mob, value = entry.value, kills = entry.kills, rank = index }
    end
    return out
end

-- Logic/TopFarm.lua lays the order out again after an auction scan.
RankUp.Order = Order
RankUp.Top = Top

--------------------------------------------------------------------------------
-- Laying out the order
--------------------------------------------------------------------------------

--- Start laying out the order over frames, from the tallies as they are.
--- With `keep` the old order stays readable until the new one is done (an
--- auction scan moved the prices); `done(old, new)` is called then.
function RankUp:Build(keep, done)
    local old = self.snapshot
    if not keep then self.snapshot = nil end
    -- By line: a name killed in two zones has a line for each.
    local tallies = ns.Tracker:Tallies()
    self.building = { byMob = {}, kills = {}, hidden = Stamp(), queue = {},
        old = old, done = done, store = tallies }

    for name, record in pairs(tallies) do
        if type(name) == "string" and KillsOf(record) >= ns.Tracker.MIN_KILLS then
            self.building.queue[#self.building.queue + 1] = name
        end
    end

    if not self.worker then
        self.worker = CreateFrame("Frame")
        self.worker:SetScript("OnUpdate", function() RankUp:Step(RankUp.SLICE) end)
    end
    self.worker:Show()
end

--- Value up to `budget` mobs of the order being laid out; done when none
--- are left.
function RankUp:Step(budget)
    local building = self.building
    if not building then
        if self.worker then self.worker:Hide() end
        return
    end

    local store = building.store or ns.Tracker:Tallies()
    local queue = building.queue
    while #queue > 0 and budget > 0 do
        local name = table.remove(queue)
        budget = budget - 1
        local entry = Measured(name)
        building.kills[name] = KillsOf(store[name])
        if entry then building.byMob[name] = entry end
    end

    if #queue == 0 then
        self.snapshot = { byMob = building.byMob, kills = building.kills,
            hidden = building.hidden, list = Order(building.byMob) }
        self.building = nil
        if self.worker then self.worker:Hide() end
        self:Changed()
        if building.done then
            local ok, err = pcall(building.done, building.old, self.snapshot)
            if not ok then ns.Debug("rank order laid out:", tostring(err)) end
        end
    end
end

--- The order moved: the kills panel shows the ranks again.
function RankUp:Changed()
    local ui = ns.TrackerUI
    if ui and ui.frame and ui.frame:IsShown() then
        local ok, err = pcall(ui.Refresh, ui)
        if not ok then ns.Debug("rank on the cards:", tostring(err)) end
    end
end

--- Where `mobName` stands on your measured board, and how many are on it;
--- nil when it is not on it or the order is not laid out yet.
function RankUp:RankOf(mobName)
    local snapshot = self.snapshot
    if not snapshot then return nil end
    if snapshot.hidden ~= Stamp() then
        -- What is hidden (or the dungeon tick box) changed: the old places
        -- are wrong until it is laid out again.
        if not self.building then self:Build() end
        return nil
    end
    local entry = snapshot.byMob[mobName]
    if not entry then return nil end
    return entry.rank, #snapshot.list
end

--- The order laid out at once: a look that comes before the frames are done
--- finishes it now.
function RankUp:BuildNow()
    if not (self.building or self.snapshot) then self:Build() end
    if self.building then self:Step(math.huge) end
    return self.snapshot
end

--- Forget the order (the tallies were cleared); it is laid out again.
function RankUp:Forget()
    self.snapshot = nil
    self.building = nil
    self.killed = {}
end

--------------------------------------------------------------------------------
-- A kill
--------------------------------------------------------------------------------

--- Tracker:Record calls this on a new kill of `mobName`.
function RankUp:Killed(mobName)
    if type(mobName) ~= "string" then return end

    self.killed = self.killed or {}
    self.killed[mobName] = true

    if self.pending then return end
    self.pending = true
    C_Timer.After(self.SETTLE, function()
        RankUp.pending = false
        RankUp:Look()
    end)
end

local function InCombat()
    local ok, fighting = pcall(function()
        return (InCombatLockdown and InCombatLockdown())
            or (UnitAffectingCombat and UnitAffectingCombat("player"))
    end)
    return ok and fighting and true or false
end

--- What the kills since the last look did to the order. Returns the move
--- for the pop-up, or nil: { before, after (the top TOP each, then the one
--- pushed out), mob, from (nil when it is new to the board), to, new }.
function RankUp:Compare()
    local killed = self.killed or {}
    self.killed = {}

    local snapshot = self.snapshot
    if not snapshot or snapshot.hidden ~= Stamp() then
        -- No order to compare with yet, or what is hidden changed: lay it
        -- out again, and say nothing this time.
        if not self.building then self:Build() end
        return nil
    end

    local store = ns.Tracker:Tallies()
    local byMob, kills = {}, {}
    for name, entry in pairs(snapshot.byMob) do byMob[name] = entry end
    for name, count in pairs(snapshot.kills) do kills[name] = count end

    -- Only mobs whose kill count moved are valued again: yours, and any a
    -- share, an import or a reset changed.
    local changed = {}
    for name, record in pairs(store) do
        if type(name) == "string" then
            local count = KillsOf(record)
            if count ~= (kills[name] or 0) and (count >= ns.Tracker.MIN_KILLS or byMob[name]) then
                changed[name] = true
            end
        end
    end
    for name in pairs(byMob) do
        if store[name] == nil then changed[name] = true end
    end

    for name in pairs(changed) do
        kills[name] = KillsOf(store[name])
        byMob[name] = Measured(name)
    end

    -- Laying out the new order renumbers entries the old one shares, so the
    -- old places are read first.
    local before = Top(snapshot.list, self.TOP + 1)
    local wasRank = {}
    for _, entry in ipairs(snapshot.list) do wasRank[entry.mob] = entry.rank end

    local after = Order(byMob)
    self.snapshot = { byMob = byMob, kills = kills, hidden = snapshot.hidden, list = after }

    -- The cards show ranks: redraw them only when a place moved.
    local moved = #after ~= #snapshot.list
    for _, entry in ipairs(after) do
        if wasRank[entry.mob] ~= entry.rank then moved = true break end
    end
    if moved then self:Changed() end

    -- The kill that moved its mob furthest up into the top: one new to the
    -- board first, then the longest climb.
    local best
    for name in pairs(killed) do
        local now = byMob[name]
        local was = wasRank[name]
        if now and now.rank <= self.TOP and (not was or now.rank < was) then
            local climb = was and (was - now.rank) or math.huge
            if not best or climb > best.climb or (climb == best.climb and now.rank < best.to) then
                best = { mob = name, from = was, to = now.rank, new = not was, climb = climb }
            end
        end
    end

    if not best then return nil end

    best.before = before
    best.after = Top(after, self.TOP + 1)
    best.kills = byMob[best.mob].kills
    return best
end

--- Look at what the kills did, and show it. In a fight it waits for the
--- fight to end.
function RankUp:Look()
    if InCombat() then
        self.waiting = true
        return
    end
    self.waiting = false

    local move = self:Compare()
    if not move or not self.On() then return end

    -- The kill that unlocks drop rates, the 100th and the 1000th have their
    -- fanfare: one sound at a time.
    local fanfare = ((move.new and move.kills == ns.Tracker.MIN_KILLS)
            or (move.kills ~= ns.Tracker.MIN_KILLS and ns.Tracker.HasFanfare(move.kills, ns.Tracker.NameOf(move.mob))))
        and not (ns.db and ns.db.trackerCelebrate == false)
    move.sound = self.SoundOn() and not fanfare

    if ns.RankUpUI then
        local ok, err = pcall(ns.RankUpUI.Show, ns.RankUpUI, move)
        if not ok then ns.Debug("rank-up pop-up:", tostring(err)) end
    end
end

--- The board's top as it stands, for `/farm rankup show`.
function RankUp:Current()
    local snapshot = self:BuildNow()
    return snapshot and Top(snapshot.list, self.TOP) or {}
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function RankUp:OnEnable()
    self.killed = {}

    local started = false
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        if started then return end
        started = true
        C_Timer.After(RankUp.START, function()
            if not (RankUp.snapshot or RankUp.building) then RankUp:Build() end
        end)
    end)

    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        if RankUp.waiting then RankUp:Look() end
    end)
end

--------------------------------------------------------------------------------
-- Command
--------------------------------------------------------------------------------

ns.RegisterCommand("rankup", L["a pop-up when a mob climbs your top 15 (on/off, sound on/off, show)"], function(rest)
    local argument = Util.Trim(rest):lower()

    if argument == "show" then
        if ns.RankUpUI then ns.RankUpUI:ShowCurrent() end
        return
    end

    if argument == "reset" then
        if ns.RankUpUI then ns.RankUpUI:ResetPlace() end
        ns.Print(L["your top 15 is back beside the kills panel."])
        return
    end

    local sound = argument:match("^sound%s*(.-)$")
    if sound then
        if sound == "on" then
            ns.db.rankUpSound = true
        elseif sound == "off" then
            ns.db.rankUpSound = false
        else
            ns.db.rankUpSound = ns.db.rankUpSound == false
        end
        ns.Print(RankUp.SoundOn()
            and L["a short chime plays when a mob climbs your top 15. /farm rankup sound off to stop."]
            or L["no chime for a climb. /farm rankup sound on to bring it back."])
    else
        if argument == "on" then
            ns.db.rankUpPopup = true
        elseif argument == "off" then
            ns.db.rankUpPopup = false
        else
            ns.db.rankUpPopup = ns.db.rankUpPopup == false
        end
        if not RankUp.On() then
            RankUp.killed = {}
            if ns.RankUpUI then ns.RankUpUI:Hide() end
        end
        ns.Print(RankUp.On()
            and L["a mob that climbs your top 15 shows it for a few seconds. /farm rankup off to stop."]
            or L["no pop-up when a mob climbs your top 15. /farm rankup on to bring it back."])
    end

    if ns.SettingsUI and ns.SettingsUI.Refresh then ns.SettingsUI:Refresh() end
end)
