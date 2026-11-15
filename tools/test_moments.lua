-- Small cheers while farming (the owner, 2026-10-14; kept quiet).
--
-- What must hold:
--   1. A rare drop long before its rate says it should comes with a
--      "Lucky!" line; one that kept you waiting well past its rate with a
--      "Finally!" line. Kills count since it last dropped, your own only.
--   2. A drop from before this was kept says nothing the first time.
--   3. The open mob's card counts kills since its best drop.
--   4. A corpse worth more than any of that mob before it, from the tenth
--      on, says "Best loot yet".
--   5. Ahead of your usual pace: "(up N%)" on the panel's per hour, and
--      one line in chat a session.
--   6. After a run and a quiet spell, the recap card; a run a logout ended
--      shows at the next login, once.
--   7. Celebrate off says nothing.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("moments")

local ns = env.Load({ ui = true })
local Tracker = ns.Tracker
local Moments = ns.Moments
local TUI = ns.TrackerUI

_G.PlaySoundFile = function() return true end
_G.PlaySound = function() return true end

local clock = 1000
_G.GetTime = function() return clock end

-- Timers wait until the test runs them.
local timers = {}
_G.C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = { at = clock + delay, fn = fn } end,
    NewTicker = function() return {} end,
}
local function RunTimers()
    local due = {}
    for index = #timers, 1, -1 do
        if timers[index].at <= clock then
            due[#due + 1] = timers[index]
            table.remove(timers, index)
        end
    end
    for _, timer in ipairs(due) do timer.fn() end
end

TUI:OnEnable()
TUI.frame:Show()

-- Drop rates from "the data", and prices.
local RATES = {
    ["Lucky Mob"] = { { "Shiny Gem", 9001, 1 }, { "Worn Tooth", 9002, 10 } },
}
local realByName = ns.DB.ByName
ns.DB.ByName = function(self)
    local byName = realByName(self)
    for mob, list in pairs(RATES) do
        local entries = {}
        for _, row in ipairs(list) do
            local source = { name = mob, chance = row[3] }
            self.sourceItem[source] = { name = row[1], id = row[2] }
            entries[#entries + 1] = source
        end
        byName[mob] = entries
    end
    return byName
end
local PRICES = { [9001] = 5000, [9002] = 20, [9003] = 300 }
ns.Value.UnitPrice = function(_, id) return id and PRICES[id] end
ns.Value.IsPoor = function() return false, true end

local serial = 0
local function Kill(mob, loot, step)
    serial = serial + 1
    clock = clock + (step or 20)
    env.world.target = { name = mob, level = 10, dead = true, guid = "MO-" .. serial }
    env.world.loot = loot or {}
    Tracker:OnLoot()
end

local function Said(text)
    for _, line in ipairs(env.chat) do
        -- Item names come in their rarity colour; the words are what count.
        if ns.Util.StripColor(tostring(line)):find(text, 1, true) then return true end
    end
    return false
end

local GEM = { name = "Shiny Gem", id = 9001 }
local TOOTH = { name = "Worn Tooth", id = 9002 }

--------------------------------------------------------------------------------
-- 1. Lucky and finally
--------------------------------------------------------------------------------

for _ = 1, 5 do Kill("Lucky Mob") end
env.chat = {}
Kill("Lucky Mob", { GEM })
suite.check("a 1 in 100 drop on the 6th kill is lucky",
    Said("Lucky! Shiny Gem drops 1 in 100. You got it in 6 kills."), env.chat[1])

env.chat = {}
for _ = 1, 2 do Kill("Lucky Mob") end
Kill("Lucky Mob", { GEM })
suite.check("counted again from the last drop", Said("You got it in 3 kills."), env.chat[1])

env.chat = {}
for _ = 1, 30 do Kill("Lucky Mob") end
suite.check("nothing said while nothing drops", not Said("Finally"))
Kill("Lucky Mob", { TOOTH })
suite.check("a 1 in 10 drop never seen in 40 kills is long awaited",
    Said("Finally! Worn Tooth after 40 kills. It drops 1 in 10."), env.chat[#env.chat])

env.chat = {}
Kill("Lucky Mob", { TOOTH })
suite.check("the next one straight after says nothing", not Said("Finally") and not Said("Lucky"))

--------------------------------------------------------------------------------
-- 2. A drop from before this was kept
--------------------------------------------------------------------------------

local old = Tracker:GetMob("Old Mob")
old.kills, old.items["Shiny Gem"] = 300, 2
RATES["Old Mob"] = { { "Shiny Gem", 9001, 1 } }
env.chat = {}
Kill("Old Mob", { GEM })
suite.check("no start, nothing said", not Said("Lucky") and not Said("Finally"))
for _ = 1, 3 do Kill("Old Mob") end
Kill("Old Mob", { GEM })
suite.check("the next one counts from it", Said("You got it in 4 kills."))

--------------------------------------------------------------------------------
-- 3. The card's count
--------------------------------------------------------------------------------

for _ = 1, 4 do Kill("Lucky Mob") end
local since = Moments:SinceLine("Lucky Mob")
suite.check("the card counts kills since its best drop", since
    and ns.Util.StripColor(since.label) == "Since your last Shiny Gem" and since.kills == 36,
    since and (since.label .. " " .. since.kills))

RATES["Dry Mob"] = { { "Shiny Gem", 9001, 1 } }
for _ = 1, 7 do Kill("Dry Mob") end
since = Moments:SinceLine("Dry Mob")
suite.check("never dropped: waiting on it, every kill", since
    and ns.Util.StripColor(since.label) == "Waiting on Shiny Gem" and since.kills == 7)

TUI:Refresh()
local found = false
for _, line in ipairs(TUI.shown or {}) do
    if ns.Util.StripColor(line.left) == "Waiting on Shiny Gem" then found = true end
end
suite.check("and the open card shows it", found)

ns.db.trackerCelebrate = false
suite.check("Celebrate off hides it", Moments:SinceLine("Dry Mob") == nil)
ns.db.trackerCelebrate = nil

--------------------------------------------------------------------------------
-- 4. Best loot yet
--------------------------------------------------------------------------------

local COIN = { name = "10 Copper", money = true }
env.chat = {}
for _ = 1, 10 do Kill("Coin Mob", { COIN }) end
suite.check("not before the tenth corpse, and not for the same worth", not Said("Best loot yet"))
Kill("Coin Mob", { COIN, { name = "Big Pearl", id = 9003 } })
suite.check("a corpse worth more than any before it", Said("Best loot yet from Coin Mob"), env.chat[#env.chat])
env.chat = {}
Kill("Coin Mob", { COIN })
suite.check("a plain one after says nothing", not Said("Best loot yet"))

ns.db.trackerCelebrate = false
env.chat = {}
Kill("Coin Mob", { COIN, { name = "Big Pearl", id = 9003, quantity = 3 } })
suite.check("Celebrate off says nothing", not Said("Best loot yet"))
ns.db.trackerCelebrate = nil

--------------------------------------------------------------------------------
-- 5. Your pace
--------------------------------------------------------------------------------

local store = ns.Stats:Store()
local current = ns.Stats.current
local before = {}
for _ = 1, 3 do before[#before + 1] = { seconds = 3600, copper = 1000, kills = 10 } end
for _, session in ipairs(before) do table.insert(store.sessions, 1, session) end
current.seconds, current.copper = 900, 500   -- 2000c an hour against 1000c
ns.Stats.version = ns.Stats.version + 1
env.chat = {}
local percent = Moments:Pace()
suite.check("ahead of your usual pace by 100%", percent == 100, percent)
suite.check("said once in chat", Said("Ahead of your usual pace"))
env.chat = {}
Moments:Pace()
suite.check("and only once a session", not Said("Ahead of your usual pace"))

TUI.startedAt = clock - 1000
TUI:DrawToolbar()
local text = TUI.toolbar.left:GetText() or ""
suite.check("the panel's per hour shows it", text:find("(up 100%)", 1, true) ~= nil, text)

current.copper = 100
ns.Stats.version = ns.Stats.version + 1
suite.check("behind your usual, nothing", Moments:Pace() == nil)

--------------------------------------------------------------------------------
-- 6. The recap
--------------------------------------------------------------------------------

Moments.run = nil
Moments.waiting = false
timers = {}
for _ = 1, 30 do Kill("Coin Mob", { COIN }, 25) end
suite.check("a run long enough waits on a timer", #timers > 0 and Moments.waiting)
suite.check("the card waits for a quiet spell", not ns.RecapUI:IsShown())
clock = clock + Moments.RECAP_IDLE + 1
RunTimers()
suite.check("then the recap shows", ns.RecapUI:IsShown())
suite.check("titled your run", ns.RecapUI.frame.title:GetText() == "YOUR RUN")
suite.check("with the kills", ns.RecapUI.lines[1].right:GetText() == "30", ns.RecapUI.lines[1].right:GetText())
suite.check("and the best drop", ns.RecapUI.lines[5].right:GetText() ~= nil)
suite.check("and a new run begins", Moments.run == nil)
ns.RecapUI:Hide()

-- Kills keep coming: it waits again.
for _ = 1, 30 do Kill("Coin Mob", { COIN }, 25) end
clock = clock + 100
RunTimers()
suite.check("not while still farming", not ns.RecapUI:IsShown())

Moments:Logout()
suite.check("a logout keeps the run", type(ns.db.lastRecap) == "table" and ns.db.lastRecap.kills == 30)
Moments:ShowLast()
suite.check("shown at the next login", ns.RecapUI:IsShown()
    and ns.RecapUI.frame.title:GetText() == "LAST TIME")
suite.check("once", ns.db.lastRecap == nil)

suite.check("the recap has its own size grip", ns.RecapUI.sizeGrip ~= nil)

suite.done()
