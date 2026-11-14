-- Blackthornes Farmer -- Logic/Moments.lua
-- Small cheers while you farm (the owner, 2026-10-14), worked out from the
-- numbers Farmer already keeps:
--
--   * Lucky: a drop that came long before its rate says it should
--     ("Lucky! Silk Cloth drops 1 in 120. You got it in 14 kills.").
--   * Finally: one that kept you waiting well past its rate.
--   * The open mob's card counts your kills since its best drop last fell.
--   * Best loot yet: a corpse worth more than any of that mob before it.
--   * Your pace: gold an hour against your usual, beside the panel's
--     per hour, and a cheer the first time a session passes it.
--   * The recap: a short card when you stop for a while after a good run,
--     or at the next login when the run ended with a logout.
--
-- These are kept quiet, like the 100th kill: no Settings text or help line
-- names them. They follow "Celebrate" (`trackerCelebrate`) and Window
-- effects, so a player who turned the fanfare off hears nothing new.
--
-- Saved, account wide, never renamed:
--   dropWaits[mob] = { n = your own kills of it since this was kept,
--                      items = { [item] = n when it last dropped } }
--   bestCorpses[mob] = { worth = copper, n = corpses priced }
--   lastRecap = the run a logout ended, shown once at the next login
--
-- Only your own kills count: a partner's or guild's counts never reach
-- `dropWaits`, so a merge never makes a drop look lucky or late. Nothing
-- here runs per frame; a kill does a few table reads, and the recap waits
-- on one timer at a time.

local _, ns = ...
local L = ns.L

local Moments = ns.NewModule("Moments")

local Util = ns.Util

-- Lucky: a drop of 1 in LUCKY_RARE or rarer, in at most LUCKY_SHARE of
-- the kills it takes on average.
Moments.LUCKY_RARE = 20
Moments.LUCKY_SHARE = 0.25
-- Finally: at least LATE_TIMES the kills it takes on average, and at least
-- LATE_KILLS kills.
Moments.LATE_TIMES = 3
Moments.LATE_KILLS = 30
-- A drop rate of your own is used only once a mob has this many kills;
-- the data's rate comes first.
Moments.OWN_RATE_KILLS = 50
-- The card's "since" line: only for a drop of 1 in 200 or more often,
-- once the mob has a few kills.
Moments.SINCE_RARE = 200
Moments.SINCE_FROM = 5
-- Best loot yet: from the BEST_AFTER-th corpse priced, and at least
-- BEST_TIMES what a kill is usually worth.
Moments.BEST_AFTER = 10
Moments.BEST_TIMES = 2
-- Your pace: from PACE_AFTER farming seconds this session, against your
-- usual over at least PACE_SESSIONS sessions, ahead by PACE_SHOW percent.
Moments.PACE_AFTER = 600
Moments.PACE_SESSIONS = 3
Moments.PACE_SHOW = 5
-- The recap: a run of RECAP_KILLS kills and RECAP_SECONDS farming
-- seconds, shown after RECAP_IDLE seconds with no kill, out of a fight.
Moments.RECAP_KILLS = 30
Moments.RECAP_SECONDS = 600
Moments.RECAP_IDLE = 300
-- A run saved at logout is shown at a login within this many seconds.
Moments.RECAP_KEEP = 3 * 86400
Moments.LOGIN_DELAY = 12
-- Seconds after a kill before its cheer floats off the panel, so it lands
-- after the loot's own floats.
Moments.FLOAT_DELAY = 0.6

local GOLD = { 1, 0.906, 0.639 }

local function Number(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function Now()
    if type(GetTime) ~= "function" then return nil end
    local ok, now = pcall(GetTime)
    return ok and type(now) == "number" and now or nil
end

local function Clock()
    local fn = _G.time or (os and os.time)
    if type(fn) ~= "function" then return nil end
    local ok, now = pcall(fn)
    return ok and type(now) == "number" and now or nil
end

local function InCombat()
    if type(InCombatLockdown) ~= "function" then return false end
    local ok, fighting = pcall(InCombatLockdown)
    return ok and fighting == true
end

function Moments.On()
    return not (ns.db and ns.db.trackerCelebrate == false)
end

--------------------------------------------------------------------------------
-- The save
--------------------------------------------------------------------------------

function Moments:Waits(mobName)
    if not ns.db then return nil end
    if type(ns.db.dropWaits) ~= "table" then ns.db.dropWaits = {} end
    local entry = ns.db.dropWaits[mobName]
    if type(entry) ~= "table" then
        entry = { n = 0, items = {} }
        ns.db.dropWaits[mobName] = entry
    end
    entry.n = Number(entry.n) or 0
    if type(entry.items) ~= "table" then entry.items = {} end
    return entry
end

function Moments:Best(mobName)
    if not ns.db then return nil end
    if type(ns.db.bestCorpses) ~= "table" then ns.db.bestCorpses = {} end
    local entry = ns.db.bestCorpses[mobName]
    if type(entry) ~= "table" then
        entry = { worth = 0, n = 0 }
        ns.db.bestCorpses[mobName] = entry
    end
    entry.worth = Number(entry.worth) or 0
    entry.n = Number(entry.n) or 0
    return entry
end

--------------------------------------------------------------------------------
-- Drop rates
--------------------------------------------------------------------------------

--- How often `item` drops from `mobName`, as a fraction of kills: the
--- data's rate, else your own once the mob has OWN_RATE_KILLS kills. `mob`
--- is its tally; `before` is how many corpses had dropped it before this
--- kill (the kill itself would tilt your own rate).
function Moments.ChanceOf(mobName, item, mob, before)
    local DB = ns.DB
    if DB and DB.ByName then
        for _, source in ipairs(DB:ByName()[mobName] or {}) do
            local found = DB:ItemOf(source)
            if found and found.name == item and Number(source.chance)
                and DB.KindOf(source) == "mob" then
                local chance = Number(source.chance) / 100
                if chance > 0 then return chance end
            end
        end
    end

    local kills = mob and (Number(mob.kills) or 0) - 1 or 0
    before = Number(before) or 0
    if kills >= Moments.OWN_RATE_KILLS and before > 0 then
        return before / kills
    end
    return nil
end

local function OneIn(chance)
    return math.max(2, math.floor(1 / chance + 0.5))
end
Moments.OneIn = OneIn

local function Hidden(name)
    return ns.DB and ns.DB.HidesItem and ns.DB:HidesItem(name) or false
end

local function Grey(name)
    local Value = ns.Value
    local id = Value and Value:ItemID(name)
    if not id then return false end
    local poor = Value:IsPoor(id)
    return poor == true
end

--------------------------------------------------------------------------------
-- A kill
--------------------------------------------------------------------------------

--- A new kill of `mobName` you looted yourself, with its own `items` (not
--- an area loot's others, not a skin). Called by Tracker:Record after the
--- kill is counted and before its items are. Returns the moment picked, if
--- any: { kind = "lucky" | "late" | "best", line, float }.
function Moments:Kill(mobName, mob, items, quantities, copper)
    if type(mobName) ~= "string" or type(mob) ~= "table" then return nil end
    local waits = self:Waits(mobName)
    if not waits then return nil end
    waits.n = waits.n + 1

    local run = self:Run()
    run.kills = run.kills + 1

    local lucky, late
    local seen = {}
    for _, name in ipairs(type(items) == "table" and items or {}) do
        if type(name) == "string" and not seen[name] then
            seen[name] = true
            local before = Number(mob.items and mob.items[name]) or 0
            local mark = Number(waits.items[name])

            -- Kills it took: since it last dropped while kept here, or every
            -- kill counted when it never dropped at all. A drop from before
            -- this was kept has no start, so it says nothing this time.
            local took
            if mark then
                took = waits.n - mark
            elseif before == 0 then
                took = Number(mob.kills) or waits.n
            end
            waits.items[name] = waits.n

            local chance = took and took > 0 and not Hidden(name) and not Grey(name)
                and Moments.ChanceOf(mobName, name, mob, before)
            if chance then
                local expected = 1 / chance
                if chance <= 1 / Moments.LUCKY_RARE and took <= expected * Moments.LUCKY_SHARE then
                    local score = took * chance
                    if not lucky or score < lucky.score then
                        lucky = { name = name, took = took, chance = chance, score = score }
                    end
                elseif took >= expected * Moments.LATE_TIMES and took >= Moments.LATE_KILLS then
                    local score = took * chance
                    if not late or score > late.score then
                        late = { name = name, took = took, chance = chance, score = score }
                    end
                end
            end
        end
    end

    local best = self:Corpse(mobName, items, quantities, copper, run)

    -- A mob on the hide list keeps its counts and says nothing.
    if ns.DB and ns.DB.IsHiddenSource and ns.DB:IsHiddenSource(mobName) then
        lucky, late, best = nil, nil, nil
    end

    local moment
    if late then
        moment = { kind = "late", item = late.name,
            line = L.Format("Finally! %s after %d kills. It drops 1 in %d.",
                ns.Util.ColorItem(late.name), late.took, OneIn(late.chance)),
            float = L.Format("Finally! %d kills", late.took) }
    elseif lucky then
        moment = { kind = "lucky", item = lucky.name,
            line = L.Format("Lucky! %s drops 1 in %d. You got it in %d kills.",
                ns.Util.ColorItem(lucky.name), OneIn(lucky.chance), lucky.took),
            float = L.Format("Lucky! 1 in %d", OneIn(lucky.chance)) }
    elseif best then
        moment = { kind = "best",
            line = L.Format("Best loot yet from %s: %s.", mobName, ns.Value.Coins(best)),
            float = L.Format("Best loot yet: %s", ns.Value.Coins(best)) }
    end

    if moment then
        moment.mob = mobName
        -- The recap keeps the luckiest moment of the run.
        if moment.kind == "lucky" and (not run.lucky or lucky.score < run.lucky.score) then
            run.lucky = { line = moment.line, score = lucky.score }
        end
        self:Cheer(moment)
    end

    self:WaitForRecap()
    return moment
end

--- What this corpse's own drops and coin are worth, against the best from
--- this mob so far. Returns the new best when it is one worth cheering.
--- Also notes the run's best drop for the recap.
function Moments:Corpse(mobName, items, quantities, copper, run)
    local Value = ns.Value
    if not Value then return nil end

    local worth = Number(copper) or 0
    local priced = worth > 0
    for _, name in ipairs(type(items) == "table" and items or {}) do
        if type(name) == "string" and not Hidden(name) then
            local unit = Value:UnitPrice(Value:ItemID(name))
            if unit then
                local count = Number(quantities and quantities[name]) or 1
                worth = worth + unit * count
                priced = true
                if run and (not run.bestDrop or unit > run.bestDrop.unit) and not Grey(name) then
                    run.bestDrop = { name = name, unit = unit }
                end
            end
        end
    end
    if not priced then return nil end

    local best = self:Best(mobName)
    if not best then return nil end
    best.n = best.n + 1
    local was = best.worth
    if worth <= was then return nil end
    best.worth = worth

    if best.n < Moments.BEST_AFTER or was <= 0 then return nil end
    local usual = Value:ForMob(mobName)
    if usual and usual > 0 and worth < usual * Moments.BEST_TIMES then return nil end
    return worth
end

--- Say the moment: a line in your own chat, and a cheer floating off the
--- mob's band with a gold pulse, once the panel has drawn the kill. A drop
--- green or better already chimes, so only a plainer one gets a sound.
function Moments:Cheer(moment)
    if not Moments.On() then return end

    ns.PrintRaw(("|c%sBlackthornes Farmer:|r %s"):format(ns.COLORS.accent, moment.line))

    local FX = ns.TrackerFX
    local quality = moment.item and FX and FX.QualityOf and FX.QualityOf(moment.item) or 0
    if moment.kind ~= "best" and (quality or 0) < 2 and ns.Tracker and ns.Tracker.PlayFile then
        ns.Tracker.PlayFile(ns.Tracker.SOUNDS.rankup)
    end

    local function Show()
        local ok, err = pcall(Moments.Float, Moments, moment)
        if not ok then ns.Debug("moment:", tostring(err)) end
    end
    if C_Timer and type(C_Timer.After) == "function" then
        pcall(C_Timer.After, Moments.FLOAT_DELAY, Show)
    else
        Show()
    end
end

--- The float and the pulse on the mob's band, while the panel shows it.
function Moments:Float(moment)
    local FX, UI = ns.TrackerFX, ns.TrackerUI
    if not (FX and UI and UI.frame and UI.frame:IsShown()) then return end
    local level = FX.Level()
    if level == "off" then return end

    local key = "mob:" .. moment.mob
    for index, line in ipairs(UI.shown or {}) do
        local row = UI.lines and UI.lines[index]
        if line.key == key and line.style == "mob" and row then
            FX:Pulse(row, key, GOLD, 0.5)
            if level == "full" then
                FX:FloatText(("|c%s%s|r"):format(ns.COLORS.accent, moment.float), row, 0, 15)
            end
            self.floated = moment
            return
        end
    end
end

--------------------------------------------------------------------------------
-- The card's count since its best drop
--------------------------------------------------------------------------------

--- For the open mob's card: { label, kills } for your kills since its best
--- drop last fell (the one worth most a piece, of those dropping 1 in
--- SINCE_RARE or more often), or nil when that is not known.
function Moments:SinceLine(mobName)
    if not Moments.On() or type(mobName) ~= "string" then return nil end
    local Tracker, Value = ns.Tracker, ns.Value
    local mob = Tracker and Tracker:Store()[mobName]
    if type(mob) ~= "table" or not Value then return nil end
    local kills = Number(mob.kills) or 0
    if kills < Moments.SINCE_FROM then return nil end

    -- The best drop is worked out again only when the mob's kills move.
    self.bestDrop = self.bestDrop or {}
    local kept = self.bestDrop[mobName]
    if not kept or kept.kills ~= kills then
        local _, details = Value:ForMob(mobName)
        local pick
        for _, entry in ipairs(details and details.priced or {}) do
            local chance = (Number(entry.chance) or 0) / 100
            if chance >= 1 / Moments.SINCE_RARE and not Hidden(entry.name) and not Grey(entry.name)
                and (not pick or entry.unit > pick.unit) then
                pick = entry
            end
        end
        kept = { kills = kills, name = pick and pick.name }
        self.bestDrop[mobName] = kept
    end
    if not kept.name then return nil end

    local waits = ns.db and type(ns.db.dropWaits) == "table" and ns.db.dropWaits[mobName]
    local mark = type(waits) == "table" and type(waits.items) == "table" and Number(waits.items[kept.name])
    local dropped = Number(mob.items and mob.items[kept.name]) or 0
    if mark then
        return { label = L.Format("Since your last %s", ns.Util.ColorItem(kept.name)),
            kills = math.max(0, (Number(waits.n) or 0) - mark) }
    elseif dropped == 0 then
        return { label = L.Format("Waiting on %s", ns.Util.ColorItem(kept.name)), kills = kills }
    end
    return nil
end

--------------------------------------------------------------------------------
-- Your pace
--------------------------------------------------------------------------------

--- How far this session's gold an hour is above your usual, in whole
--- percent, once there is enough of both to say; nil otherwise. The first
--- time a session passes your usual, a cheer.
function Moments:Pace()
    if not Moments.On() then return nil end
    local Stats = ns.Stats
    local session = Stats and Stats.current
    if not session then return nil end

    local version = Stats.version
    local kept = self.pace
    if not kept or kept.version ~= version or kept.session ~= session then
        kept = { version = version, session = session }
        local rate = Stats.Rate(session, Moments.PACE_AFTER)
        local usual = rate and Stats:Usual()
        local _, _, counted = Stats:Best(true)
        if rate and usual and usual > 0 and (counted or 0) >= Moments.PACE_SESSIONS then
            kept.percent = (rate / usual - 1) * 100
            kept.rate, kept.usual = rate, usual
        end
        self.pace = kept
    end

    local percent = kept.percent
    if not percent or percent < Moments.PACE_SHOW then return nil end

    if not session.paceCheered then
        session.paceCheered = true
        ns.PrintRaw(("|c%sBlackthornes Farmer:|r %s"):format(ns.COLORS.accent,
            L.Format("Ahead of your usual pace: %s an hour, when you usually make %s.",
                ns.Value.Coins(kept.rate), ns.Value.Coins(kept.usual))))
        self.paceFloat = true
    end
    return math.floor(percent + 0.5)
end

--------------------------------------------------------------------------------
-- The recap
--------------------------------------------------------------------------------

--- The run since login or the last recap, kept in memory.
function Moments:Run()
    local run = self.run
    if run then return run end
    local Stats = ns.Stats
    local session = Stats and Stats.current
    run = { kills = 0, startedAt = Now(),
        copper = session and Number(session.copper) or 0,
        seconds = session and Number(session.seconds) or 0,
        session = session }
    self.run = run
    return run
end

--- What the run comes to: { kills, copper, seconds, rate, usual, change,
--- best, lucky }, or nil while it is too short to sum up.
function Moments:Summary(run)
    run = run or self.run
    if not run or run.kills < Moments.RECAP_KILLS then return nil end
    local Stats = ns.Stats
    local session = Stats and Stats.current
    local copper, seconds = 0, 0
    if session and session == run.session then
        copper = (Number(session.copper) or 0) - run.copper
        seconds = (Number(session.seconds) or 0) - run.seconds
    elseif session then
        -- The session began after the run's first kill: all of it is the run.
        copper = Number(session.copper) or 0
        seconds = Number(session.seconds) or 0
    end
    if seconds < Moments.RECAP_SECONDS then return nil end

    local summary = { kills = run.kills, copper = copper, seconds = seconds,
        best = run.bestDrop and run.bestDrop.name, lucky = run.lucky and run.lucky.line }
    summary.rate = copper / seconds * 3600
    local usual = Stats:Usual()
    if usual and usual > 0 then
        summary.usual = usual
        summary.change = math.floor((summary.rate / usual - 1) * 100 + 0.5)
    end
    return summary
end

--- One timer at a time waits for the run to go quiet.
function Moments:WaitForRecap(delay)
    if self.waiting or self.checking or not (C_Timer and type(C_Timer.After) == "function") then return end
    if not self:Summary() and not delay then return end
    self.waiting = true
    -- A timer that runs at once (no real clock) would only loop.
    local now = true
    pcall(C_Timer.After, delay or Moments.RECAP_IDLE, function()
        Moments.waiting = false
        if not now then Moments:CheckRecap() end
    end)
    now = false
end

--- Show the recap once the run has been quiet RECAP_IDLE seconds and you
--- are out of a fight; otherwise wait the rest.
function Moments:CheckRecap()
    self.checking = true
    local ok, err = pcall(self.CheckRecapNow, self)
    self.checking = false
    if not ok then ns.Debug("recap:", tostring(err)) end
    -- A wait asked for while checking starts now.
    if self.again then
        local delay = self.again
        self.again = nil
        self:WaitForRecap(delay)
    end
end

function Moments:CheckRecapNow()
    local summary = self:Summary()
    if not summary then return end
    local now = Now()
    local last = ns.Stats and ns.Stats.lastAt
    if now and last and now - last < Moments.RECAP_IDLE then
        self.again = Moments.RECAP_IDLE - (now - last) + 1
        return
    end
    if InCombat() then
        self.again = 10
        return
    end

    self.run = nil
    if Moments.On() and ns.RecapUI then
        local ok, err = pcall(ns.RecapUI.Show, ns.RecapUI, summary, L["YOUR RUN"])
        if not ok then ns.Debug("recap:", tostring(err)) end
    end
end

--- At logout, a run long enough to sum up is kept for the next login.
function Moments:Logout()
    local summary = self:Summary()
    if summary and ns.db then
        summary.at = Clock()
        ns.db.lastRecap = summary
    end
end

--- At login, the run the last logout ended, once.
function Moments:ShowLast()
    local saved = ns.db and ns.db.lastRecap
    if type(saved) ~= "table" then return end
    if InCombat() then
        self.lastTries = (self.lastTries or 0) + 1
        if self.lastTries <= 30 and C_Timer and type(C_Timer.After) == "function" then
            pcall(C_Timer.After, 10, function() Moments:ShowLast() end)
        end
        return
    end
    ns.db.lastRecap = nil
    local now, at = Clock(), Number(saved.at)
    if now and at and now - at > Moments.RECAP_KEEP then return end
    if not (Moments.On() and ns.RecapUI) then return end
    local ok, err = pcall(ns.RecapUI.Show, ns.RecapUI, saved, L["LAST TIME"])
    if not ok then ns.Debug("recap:", tostring(err)) end
end

function Moments:OnEnable()
    ns.RegisterEvent(self, "PLAYER_LOGOUT", function() Moments:Logout() end)
    if ns.db and type(ns.db.lastRecap) == "table"
        and C_Timer and type(C_Timer.After) == "function" then
        pcall(C_Timer.After, Moments.LOGIN_DELAY, function() Moments:ShowLast() end)
    end
end
