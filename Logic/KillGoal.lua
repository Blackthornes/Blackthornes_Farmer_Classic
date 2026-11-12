-- Blackthornes Farmer -- Logic/KillGoal.lua
-- A kill goal (a player asked, the owner said build it, 2026-10-20): "kill
-- 1000 mobs" or "kill 200 Defias Pillagers", counted only from the moment
-- Start is pressed, and a summary when it is done: how long it took, the
-- gold, gold an hour, the XP and what each mob dropped.
--
-- It is not an item goal, so it is kept apart from Logic/Goals.lua's list
-- (Butler, Tradeskills and the arrow read every goal there as an item).
-- One kill goal a character, by GUID, in BlackthornesFarmerDB.killGoals:
--
--   killGoals[guid] = { goal = { ... }, last = { ... } }
--
-- `goal` is the one under way (or just finished, until Got It), `last` the
-- summary of the newest finished one, kept so the Stats tab can show it
-- again. Never rename killGoals or its fields.
--
-- It only reads what Tracker:Record already counts: the corpse's own drops
-- (never skinning), the rest of an area loot window and the coin. Nothing
-- here changes the kill tally, the drop rates or any other count.

local _, ns = ...
local L = ns.L

local KillGoal = ns.NewModule("KillGoal")

local Util = ns.Util

-- The biggest goal that can be set.
KillGoal.MOST = 100000

-- A gap between two kills longer than this is a break and is left out of
-- the time, as the Stats tab does.
KillGoal.BREAK = 300

-- Enough to guess the time left: this many kills over at least this long.
KillGoal.PACE_KILLS = 3
KillGoal.PACE_SECONDS = 20

-- How much the summary keeps: mobs, and items a mob. A grind of a thousand
-- kills meets a few dozen mobs at most; past these the rest are dropped,
-- the kills still count.
KillGoal.MAX_MOBS = 60
KillGoal.MAX_ITEMS = 40

-- How many mobs the summary window lists, most kills first.
KillGoal.SHOWN_MOBS = 12

local function Now()
    return type(time) == "function" and time() or os.time()
end

--------------------------------------------------------------------------------
-- Saved state
--------------------------------------------------------------------------------

--- This character's record, or nil while the client will not give its GUID
--- (one key per character: nothing is kept under a guess).
function KillGoal:Record(make)
    local guid = ns.Goals and ns.Goals:Owner()
    if not guid then return nil end
    local db = ns.db
    if type(db.killGoals) ~= "table" then
        if not make then return nil end
        db.killGoals = {}
    end
    local record = db.killGoals[guid]
    if type(record) ~= "table" then
        if not make then return nil end
        record = {}
        db.killGoals[guid] = record
    end
    return record
end

--- The kill goal on this character, finished or not, or nil.
function KillGoal:Current()
    local record = self:Record()
    local goal = record and record.goal
    if type(goal) ~= "table" or not tonumber(goal.target) then return nil end
    return goal
end

--- The summary of the newest finished goal, or nil.
function KillGoal:Last()
    local record = self:Record()
    local last = record and record.last
    if type(last) ~= "table" then return nil end
    return last
end

--- Is `goal` the kill goal (for the Goals panel, which draws both kinds)?
function KillGoal:Is(goal)
    return type(goal) == "table" and goal.kills == true
end

--------------------------------------------------------------------------------
-- Setting and clearing
--------------------------------------------------------------------------------

--- Start a goal of `target` kills, of `mob` only or of any mob (nil). A goal
--- already under way is replaced. Returns the goal, or nil and why.
function KillGoal:Start(target, mob)
    target = math.floor(tonumber(target) or 0)
    if target < 1 then return nil, L["the amount has to be 1 or more"] end
    if target > KillGoal.MOST then
        return nil, L.Format("a kill goal can be up to %d", KillGoal.MOST)
    end
    if type(mob) == "string" then
        mob = Util.Trim(mob)
        if mob == "" then mob = nil end
    else
        mob = nil
    end

    local record = self:Record(true)
    if not record then return nil, L["try again in a moment"] end

    local now = Now()
    record.goal = {
        kills = true,
        target = target,
        mob = mob,
        have = 0,
        started = now,
        lastAt = now,
        seconds = 0,
        copper = 0,
        xp = 0,
        levels = 0,
        mobs = {},
        milestone = 0,
    }
    if ns.GoalsUI then ns.GoalsUI:Refresh() end
    return record.goal
end

--- Take the goal off, finished or not. The last summary stays.
function KillGoal:Stop()
    local record = self:Record()
    if not record or record.goal == nil then return false end
    record.goal = nil
    if ns.GoalsUI then ns.GoalsUI:Refresh() end
    return true
end

--- Take a finished goal off the panel (Got It).
function KillGoal:ClearDone()
    local goal = self:Current()
    if not goal or not goal.done then return false end
    return self:Stop()
end

--------------------------------------------------------------------------------
-- Counting
--------------------------------------------------------------------------------

local function Count(table_, key, amount)
    table_[key] = (tonumber(table_[key]) or 0) + amount
end

--- Where a mob's kills and drops go in the goal, or nil once the summary
--- holds as many mobs as it keeps.
local function MobEntry(goal, name)
    if type(goal.mobs) ~= "table" then goal.mobs = {} end
    local entry = goal.mobs[name]
    if type(entry) == "table" then return entry end

    local count = 0
    for _ in pairs(goal.mobs) do count = count + 1 end
    if count >= KillGoal.MAX_MOBS then return nil end

    entry = { kills = 0, items = {}, itemCount = 0 }
    goal.mobs[name] = entry
    return entry
end

local function AddItems(entry, items)
    if not entry or type(items) ~= "table" then return end
    for name, amount in pairs(items) do
        amount = tonumber(amount) or 0
        if type(name) == "string" and amount > 0 then
            if entry.items[name] == nil then
                if (entry.itemCount or 0) < KillGoal.MAX_ITEMS then
                    entry.itemCount = (entry.itemCount or 0) + 1
                    entry.items[name] = amount
                end
            else
                Count(entry.items, name, amount)
            end
        end
    end
end

--- Does this goal count `mobName`?
function KillGoal.Counts(goal, mobName)
    if not goal.mob then return true end
    return type(mobName) == "string" and mobName:lower() == goal.mob:lower()
end

--- A corpse looted (from Tracker:Record). `corpse` is the tracker's own
--- table for it, `newKill` true on the first window, `given` the items it
--- gave that are yours, `copper` its coin and `haul` the rest of an area
--- loot window. Skinning windows are never passed.
function KillGoal:Corpse(mobName, corpse, newKill, given, copper, haul)
    local goal = self:Current()
    if not goal or goal.done or not KillGoal.Counts(goal, mobName) then return end
    local started = tonumber(goal.started) or 0

    if newKill then
        -- Kept at [3] of the tracker's corpse (its string keys are items):
        -- a later window on it adds its items only to the goal it counted for.
        if type(corpse) == "table" then corpse[3] = started end

        local now = Now()
        local gap = now - (tonumber(goal.lastAt) or now)
        if gap > 0 and gap < KillGoal.BREAK then
            goal.seconds = (tonumber(goal.seconds) or 0) + gap
        end
        goal.lastAt = now
        goal.have = (tonumber(goal.have) or 0) + 1
        goal.copper = (tonumber(goal.copper) or 0) + (tonumber(copper) or 0)
            + (type(haul) == "table" and tonumber(haul.copper) or 0)

        local entry = MobEntry(goal, mobName)
        if entry then entry.kills = (tonumber(entry.kills) or 0) + 1 end
        AddItems(entry, given)
        if type(haul) == "table" then AddItems(entry, haul.items) end
    elseif type(corpse) == "table" and corpse[3] == started then
        AddItems(MobEntry(goal, mobName), given)
        return
    else
        return
    end

    local change = { goal = goal, from = goal.have - 1, to = goal.have, gathered = 1, name = mobName }
    local reached = ns.Goals.MilestoneFor(ns.Goals.Fraction(goal))
    if reached > (tonumber(goal.milestone) or 0) then
        change.milestone = ns.Goals.MILESTONES[reached]
    end
    goal.milestone = reached

    if goal.have >= (tonumber(goal.target) or math.huge) then
        goal.done = true
        goal.doneAt = Now()
        change.done = true
        change.milestone = nil
        self:Keep(goal)
    end

    if ns.GoalsUI then pcall(ns.GoalsUI.Changed, ns.GoalsUI, { change }) end
    if change.done then self:Finished(goal) end
end

--- XP gained (from XP:Update), with how many levels it crossed.
function KillGoal:GainedXP(amount, levels)
    local goal = self:Current()
    if not goal or goal.done then return end
    goal.xp = (tonumber(goal.xp) or 0) + math.max(0, tonumber(amount) or 0)
    goal.levels = (tonumber(goal.levels) or 0) + math.max(0, tonumber(levels) or 0)
end

--------------------------------------------------------------------------------
-- Reading a goal
--------------------------------------------------------------------------------

--- Seconds to finish at the pace so far, or nil until there is a pace.
function KillGoal.Eta(goal)
    local kills = tonumber(goal.have) or 0
    local seconds = tonumber(goal.seconds) or 0
    if kills < KillGoal.PACE_KILLS or seconds < KillGoal.PACE_SECONDS then return nil end
    return ns.Goals.Left(goal) / (kills / seconds)
end

--- "About 2 hours left at your pace", or nil until there is a pace.
function KillGoal.EtaText(goal)
    local seconds = KillGoal.Eta(goal)
    if not seconds then return nil end
    local minutes = math.max(1, math.floor(seconds / 60 + 0.5))
    if minutes < 90 then
        if minutes == 1 then return L["About 1 minute left at your pace"] end
        return L.Format("About %d minutes left at your pace", minutes)
    end
    local hours = math.floor(minutes / 60 + 0.5)
    return L.Format("About %d hours left at your pace", hours)
end

--- The goal's name on its card: "Kill 1000 Mobs" or "Kill 200 Defias Pillager".
function KillGoal.Title(goal)
    if goal.mob then return L.Format("Kill %d %s", tonumber(goal.target) or 0, goal.mob) end
    return L.Format("Kill %d Mobs", tonumber(goal.target) or 0)
end

--- What the goal's items are worth now, in copper.
local function ItemWorth(mobs)
    local worth = 0
    local best, bestPrice
    for _, entry in pairs(type(mobs) == "table" and mobs or {}) do
        for name, amount in pairs(type(entry.items) == "table" and entry.items or {}) do
            local id = ns.Value:ItemID(name)
            local unit = id and ns.Value:UnitPrice(id)
            if unit then
                worth = worth + unit * (tonumber(amount) or 0)
                if not bestPrice or unit > bestPrice then best, bestPrice = name, unit end
            end
        end
    end
    return worth, best
end

--- The summary of a finished goal, kept as `last` so the Stats tab can show
--- it again: { target, mob, kills, seconds, gold, xp, levels, at, best,
--- mobs = { { name, kills, items = { { name, count } } } } }, mobs by most
--- kills and their items by most.
function KillGoal:Summary(goal)
    local worth, best = ItemWorth(goal.mobs)
    local summary = {
        target = tonumber(goal.target) or 0,
        mob = goal.mob,
        kills = tonumber(goal.have) or 0,
        seconds = tonumber(goal.seconds) or 0,
        gold = (tonumber(goal.copper) or 0) + worth,
        xp = tonumber(goal.xp) or 0,
        levels = tonumber(goal.levels) or 0,
        at = goal.doneAt or Now(),
        best = best,
        mobs = {},
    }

    for name, entry in pairs(type(goal.mobs) == "table" and goal.mobs or {}) do
        local row = { name = name, kills = tonumber(entry.kills) or 0, items = {} }
        for item, count in pairs(type(entry.items) == "table" and entry.items or {}) do
            row.items[#row.items + 1] = { name = item, count = tonumber(count) or 0 }
        end
        table.sort(row.items, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return a.name < b.name
        end)
        summary.mobs[#summary.mobs + 1] = row
    end
    table.sort(summary.mobs, function(a, b)
        if a.kills ~= b.kills then return a.kills > b.kills end
        return a.name < b.name
    end)
    return summary
end

--- Gold an hour of a summary, or nil while it took under a minute.
function KillGoal.PerHour(summary)
    local seconds = tonumber(summary.seconds) or 0
    if seconds < 60 then return nil end
    return math.floor((tonumber(summary.gold) or 0) / seconds * 3600)
end

function KillGoal:Keep(goal)
    local record = self:Record(true)
    if record then record.last = self:Summary(goal) end
end

--- A goal just reached its number: a line in chat, the goal sound and the
--- summary.
function KillGoal:Finished(goal)
    local line = L.Format("Goal done: %s kills!", Util.Colored("good", tostring(goal.target)))
    ns.PrintRaw(("|c%sBlackthornes Farmer:|r %s"):format(ns.COLORS.accent, line))

    local said = ns.TrackerFX and ns.TrackerFX:Say("goal")
    if not said and ns.Tracker and not ns.Tracker.PlayFile(ns.Tracker.SOUNDS.unlock)
        and type(PlaySound) == "function" and not (ns.Muted and ns.Muted()) then
        pcall(PlaySound, 888, "Master")
    end

    if ns.KillGoalUI then pcall(ns.KillGoalUI.ShowSummary, ns.KillGoalUI) end
end

--------------------------------------------------------------------------------
-- Command
--------------------------------------------------------------------------------

local function Say(text)
    ns.PrintRaw(("|c%sBlackthornes Farmer:|r %s"):format(ns.COLORS.accent, text))
end

function KillGoal:Command(args)
    args = Util.Trim(args or "")
    local word = (args:match("^(%S+)") or ""):lower()

    if args == "" then
        if ns.KillGoalUI then ns.KillGoalUI:ShowNew() end
        return
    end
    if word == "stop" then
        if self:Stop() then Say(L["Kill goal taken off."]) else Say(L["You have no kill goal."]) end
        return
    end
    if word == "summary" then
        if not self:Last() then Say(L["Finish a kill goal to see its summary."]) return end
        if ns.KillGoalUI then ns.KillGoalUI:ShowSummary() end
        return
    end

    local number, mob = args:match("^(%d+)%s*(.*)$")
    if not number then
        Say(L["Type /farm killgoal 1000, or /farm killgoal 200 and a mob's name."])
        return
    end
    local goal, why = self:Start(number, mob)
    if not goal then
        Say(L.Format("Couldn't start it: %s.", why or ""))
        return
    end
    Say(L.Format("Started: %s.", KillGoal.Title(goal)))
    if ns.GoalsUI and ns.GoalsUI.Show then pcall(ns.GoalsUI.Show, ns.GoalsUI) end
end

ns.RegisterCommand("killgoal", L["a kill goal: /farm killgoal 1000, or 200 and a mob's name (stop, summary)"],
    function(rest) KillGoal:Command(rest) end)
