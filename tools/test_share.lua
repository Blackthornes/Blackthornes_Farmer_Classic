-- Sharing kills, drop rates and gathering with another account.
--
-- What matters: counts from the two accounts add up, nothing is ever counted
-- twice (not on a repeat, not coming back round, not through a third
-- account), a partner's counts going down never lowers anything, nothing
-- strange is taken from the wire, and a side that is off says and hears
-- nothing. The second half plays two whole accounts against each other over
-- a pretend chat.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("share")

local ns = env.Load()
local Share, Comm = ns.Share, ns.Comm

suite.check("the module and the wire are loaded", Share ~= nil and Comm ~= nil and ns.Serialize ~= nil)
-- PLAYER_LOGIN, as the client runs it.
Share:OnEnable()

suite.check("sharing is off by default", ns.db.shareData == false and ns.db.shareNames == "")
suite.check("so nothing is listening", not Comm.listening)
suite.check("and nothing is enabled", not Share:Enabled())

--------------------------------------------------------------------------------
-- Adding up
--------------------------------------------------------------------------------

local SPEC = Share.SECTIONS[4].spec  -- kills

local function Tally(kills, copper, items)
    return { kills = kills, copper = copper, coinKills = kills, items = items or {}, qty = {}, stacks = {}, places = {} }
end

local function Clean(record) return Share.CleanRecord(SPEC, record) end

do
    -- A has 10 Wolf kills; B has 6.
    local a = Tally(10, 1000, { Pelt = 4 })
    local b = Tally(6, 300, { Pelt = 1 })
    local credit = {}

    local sent = Share.Export(SPEC, a, {})
    Share.Merge(SPEC, b, Clean(sent), credit)
    suite.check("B has both accounts' kills", b.kills == 16, b.kills)
    suite.check("and their coin", b.copper == 1300, b.copper)
    suite.check("and what dropped", b.items.Pelt == 5, b.items.Pelt)
    suite.check("A's own record is untouched", a.kills == 10)

    Share.Merge(SPEC, b, Clean(sent), credit)
    suite.check("hearing the same again adds nothing", b.kills == 16 and b.items.Pelt == 5, b.kills)

    a.kills, a.coinKills = 12, 12
    Share.Merge(SPEC, b, Clean(Share.Export(SPEC, a, {})), credit)
    suite.check("only what is new is added", b.kills == 18, b.kills)

    -- B tells A back: only B's own six, not A's ten coming round again.
    local back = Share.Export(SPEC, b, { credit })
    suite.check("B sends back only what B counted itself", back.kills == 6, back.kills)
    suite.check("and only its own drops", back.items.Pelt == 1, back.items.Pelt)

    -- A reset on the other side lowers nothing, and adds nothing until it
    -- passes what was already taken.
    a.kills = 3
    Share.Merge(SPEC, b, Clean(Share.Export(SPEC, a, {})), credit)
    suite.check("a partner's count going down changes nothing", b.kills == 18, b.kills)
    a.kills = 13
    Share.Merge(SPEC, b, Clean(Share.Export(SPEC, a, {})), credit)
    suite.check("and growing again adds only the part past what was taken", b.kills == 19, b.kills)
end

do
    -- Three accounts: C hears from B, and B holds A's counts. C gets B's own
    -- only; A's are not passed on.
    local a = Tally(10, 0)
    local b = Tally(6, 0)
    local fromA = {}
    Share.Merge(SPEC, b, Clean(Share.Export(SPEC, a, {})), fromA)
    local toC = Share.Export(SPEC, b, { fromA })
    suite.check("a third account is sent only B's own counts", toC.kills == 6, toC.kills)
end

do
    -- A record with nothing of the sender's own is not sent.
    local b = Tally(10, 0)
    local _, any = Share.Export(SPEC, b, { { kills = 10, coinKills = 10 } })
    suite.check("all taken, nothing of its own, nothing to send", not any)
end

--------------------------------------------------------------------------------
-- What is taken from the wire
--------------------------------------------------------------------------------

do
    local HARVEST = Share.SECTIONS[1].spec
    local clean = Share.CleanRecord(HARVEST, {
        mob = "Wolf|cFFFF0000", zone = "Elwynn", corpses = 5, minLevel = -3, maxLevel = 8,
        junk = "x", coords = { 0.5, 0.25 },
        items = { Pelt = { name = "Pelt", count = 3, corpses = 2, extra = 9 }, [""] = { count = 1 }, Bad = "nope" },
    })
    suite.check("a pipe is taken out of strings", clean.mob == "WolfcFFFF0000", clean.mob)
    suite.check("an unknown field is dropped", clean.junk == nil)
    suite.check("a negative number is dropped", clean.minLevel == nil and clean.maxLevel == 8)
    suite.check("numbers and coordinates are kept", clean.corpses == 5 and clean.coords[2] == 0.25)
    suite.check("an item keeps only its known fields", clean.items.Pelt.count == 3 and clean.items.Pelt.extra == nil)
    suite.check("an unnamed item or a non-table is dropped", clean.items[""] == nil and clean.items.Bad == nil)
    suite.check("a table that is not one gives nothing", Share.CleanRecord(HARVEST, "x") == nil)
    suite.check("nor does NaN", Share.CleanRecord(HARVEST, { corpses = 0 / 0 }).corpses == nil)
    suite.check("nor a number past the limit", Share.CleanRecord(HARVEST, { corpses = 1e12 }).corpses == nil)

    local big = {}
    for i = 1, 1000 do big["Item " .. i] = { count = 1 } end
    local capped = 0
    for _ in pairs(Share.CleanRecord(HARVEST, { mob = "X", items = big }).items) do capped = capped + 1 end
    suite.check("a huge list is cut short", capped <= 400, capped)
end

--------------------------------------------------------------------------------
-- Two accounts over a pretend chat
--------------------------------------------------------------------------------

local function Account(name)
    local db = {}
    for key, value in pairs(ns.DEFAULTS) do db[key] = value end
    db.tracker = { mobs = {} }
    db.gathering = { nodes = {}, spots = {} }
    db.fishing = { spots = {} }
    return { name = name, db = db, records = {} }
end

local ana, bob = Account("Ana Smith"), Account("Bob Smith")
local accounts = { ["Ana Smith"] = ana, ["Bob Smith"] = bob }
local current

local function Switch(account)
    current = account
    ns.db = account.db
    ns.Harvest.records = account.records
    account.db.harvest = account.records
end

-- The client: the character playing, a last name the game will give, and a
-- chat that takes messages and hands them to the other account.
local outbox, timers = {}, {}
local clock = 0
_G.UnitName = function(unit)
    if unit == "player" then return (current.name:match("^(%S+)")) end
    return nil
end
_G.UnitSurname = function() return "Smith" end
_G.GetTime = function() return clock end
_G.time = function() return 1000000 + math.floor(clock) end
_G.InCombatLockdown = function() return false end
_G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, text, channel, target)
        outbox[#outbox + 1] = { from = current, prefix = prefix, text = text, channel = channel, target = target }
        return 0
    end,
}
_G.C_Timer = {
    After = function(_, fn) timers[#timers + 1] = { fn = fn, account = current } end,
    NewTicker = function() return { Cancel = function() end } end,
}

--- Let time pass: timers run as the account that set them, and each account's
--- queue goes out and is heard by the other, until everything is quiet.
local function Settle()
    for _ = 1, 4000 do
        clock = clock + 5
        local moved = false

        local due = timers
        timers = {}
        for _, timer in ipairs(due) do
            Switch(timer.account)
            timer.fn()
            moved = true
        end

        for _, account in pairs(accounts) do
            Switch(account)
            if Comm:Pending() > 0 then Comm:Pump() moved = true end
        end

        local mail = outbox
        outbox = {}
        for _, message in ipairs(mail) do
            local to = accounts[message.target]
            if to then
                Switch(to)
                Comm:CHAT_MSG_ADDON(nil, message.prefix, message.text, message.channel, message.from.name)
                moved = true
            end
        end

        if not moved and #timers == 0 and #outbox == 0 then return end
    end
    error("sharing never settled")
end

local function Wolf(corpses, pelts, pelCorpses)
    return {
        mob = "Wolf", zone = "Elwynn Forest", location = "Northshire", minLevel = 1, maxLevel = 3,
        corpses = corpses, coords = { 0.4, 0.5 },
        items = { ["Wolf Pelt"] = { name = "Wolf Pelt", count = pelts, corpses = pelCorpses, id = 1 } },
    }
end

local WOLF_KEY = "Wolf|Elwynn Forest|Northshire"

ana.records[WOLF_KEY] = Wolf(30, 12, 10)
bob.records[WOLF_KEY] = Wolf(20, 5, 4)
ana.db.tracker.mobs.Wolf = Tally(40, 4000)
bob.db.tracker.mobs.Wolf = Tally(25, 2500)
bob.db.tracker.mobs.Boar = Tally(5, 100)
ana.db.gathering.nodes["Elwynn Forest|Northshire|Peacebloom"] = {
    zone = "Elwynn Forest", location = "Northshire", node = "Peacebloom", kind = "herb",
    gathers = 7, items = { Peacebloom = { gathers = 7, count = 9, id = 2447 } },
}
bob.db.fishing.spots["Westfall||"] = {
    zone = "Westfall", location = "", school = "", casts = 11,
    items = { ["Raw Brilliant Smallfish"] = { casts = 11, count = 13, id = 6291 } },
}

-- Each side still has nothing to do until it is turned on.
Switch(ana) Share:Apply()
Switch(bob) Share:Apply()
suite.check("off, nothing is listening", not Comm.listening)

-- A names Bob; Bob has not named A yet.
Switch(ana) Share:SetEnabled(true) Share:SetNames("Bob Smith")
suite.check("on with a name, it listens", Comm.listening == true)
suite.check("and says so", Share:Describe():find("Bob Smith", 1, true) ~= nil, Share:Describe())
Settle()
suite.check("Settings says nothing came in yet", Share:Status() == "", Share:Status())
suite.check("Bob's side is off, so nothing was taken", ana.records[WOLF_KEY].corpses == 30
    and bob.records[WOLF_KEY].corpses == 20)

-- Bob turns it on and names A: now both are paired.
Switch(bob) Share:SetEnabled(true) Share:SetNames("Ana Smith")
Settle()

local function Check(label, ok, detail) suite.check(label, ok, detail) end

Switch(ana)
Check("Ana has both accounts' corpses", ana.records[WOLF_KEY].corpses == 50, ana.records[WOLF_KEY].corpses)
Check("and both accounts' drops", ana.records[WOLF_KEY].items["Wolf Pelt"].count == 17
    and ana.records[WOLF_KEY].items["Wolf Pelt"].corpses == 14)
Check("and both accounts' kills", ana.db.tracker.mobs.Wolf.kills == 65, ana.db.tracker.mobs.Wolf.kills)
Check("and their coin", ana.db.tracker.mobs.Wolf.copper == 6500)
Check("and a mob only Bob killed", ana.db.tracker.mobs.Boar and ana.db.tracker.mobs.Boar.kills == 5)
Check("and Bob's fishing", ana.db.fishing.spots["Westfall||"] and ana.db.fishing.spots["Westfall||"].casts == 11)
do
    local status = Share:Status()
    Check("Settings says what came in and from whom", status:match("^Got drops for %d+ mobs? from Bob Smith%.") ~= nil, status)
    Check("and when", status:find("The last came in just now.", 1, true) ~= nil, status)
end

Switch(bob)
Check("Bob has both accounts' corpses", bob.records[WOLF_KEY].corpses == 50, bob.records[WOLF_KEY].corpses)
Check("and the same kills", bob.db.tracker.mobs.Wolf.kills == 65, bob.db.tracker.mobs.Wolf.kills)
Check("and Ana's gathering", bob.db.gathering.nodes["Elwynn Forest|Northshire|Peacebloom"]
    and bob.db.gathering.nodes["Elwynn Forest|Northshire|Peacebloom"].gathers == 7)
Check("with what it gave", bob.db.gathering.nodes["Elwynn Forest|Northshire|Peacebloom"].items.Peacebloom.count == 9)
Check("and the levels widened", bob.records[WOLF_KEY].minLevel == 1 and bob.records[WOLF_KEY].maxLevel == 3)

-- Syncing again, and again, adds nothing.
for _ = 1, 3 do
    Switch(ana) Share:Check()
    Switch(bob) Share:Check()
    Settle()
end
Check("syncing again does not count anything twice", ana.records[WOLF_KEY].corpses == 50
    and bob.records[WOLF_KEY].corpses == 50 and ana.db.tracker.mobs.Wolf.kills == 65
    and bob.db.tracker.mobs.Wolf.kills == 65)

-- New kills on one side reach the other, once.
Switch(ana)
ana.db.tracker.mobs.Wolf.kills = ana.db.tracker.mobs.Wolf.kills + 5
ana.db.tracker.mobs.Wolf.coinKills = ana.db.tracker.mobs.Wolf.coinKills + 5
ana.records[WOLF_KEY].corpses = ana.records[WOLF_KEY].corpses + 5
Switch(bob) Share:Check()
Switch(ana) Share:Check()
Settle()
Switch(bob)
Check("a new kill on one account reaches the other", bob.db.tracker.mobs.Wolf.kills == 70
    and bob.records[WOLF_KEY].corpses == 55, bob.db.tracker.mobs.Wolf.kills)
Switch(ana)
Check("without coming back round", ana.db.tracker.mobs.Wolf.kills == 70 and ana.records[WOLF_KEY].corpses == 55,
    ana.db.tracker.mobs.Wolf.kills)

-- Two characters of one account named: the account is counted once.
do
    local anaTwo = { name = "Ana Jones", db = ana.db, records = ana.records }
    accounts["Ana Jones"] = anaTwo
    Switch(bob) Share:SetEnabled(true) Share:SetNames("Ana Smith, Ana Jones")
    Switch(ana)
    ana.db.tracker.mobs.Wolf.kills = ana.db.tracker.mobs.Wolf.kills + 5
    ana.db.tracker.mobs.Wolf.coinKills = ana.db.tracker.mobs.Wolf.coinKills + 5
    for _ = 1, 3 do
        Switch(bob) Share:Check()
        Switch(anaTwo) Share:Check()
        Switch(ana) Share:Check()
        Settle()
    end
    Switch(bob)
    Check("a second character of the same account adds nothing", bob.db.tracker.mobs.Wolf.kills == 75,
        bob.db.tracker.mobs.Wolf.kills)
    Check("and is said to be the same account", Share:Describe():find("same account", 1, true) ~= nil, Share:Describe())
    local one, two = Share.partners["ana smith"], Share.partners["ana jones"]
    Check("exactly one of the two is the duplicate", (one.duplicate and not two.duplicate) or (two.duplicate and not one.duplicate))
    Check("naming a character of your own account takes nothing",
        (function()
            local state = { key = "me", name = "Me" }
            return Share:Identify(state, ns.Transfer:SourceId()) == false and state.duplicate == true
        end)())
    accounts["Ana Jones"] = nil
    Switch(bob) Share:SetNames("Ana Smith")
end

-- Only a named partner is heard.
Switch(bob)
local before = bob.records[WOLF_KEY].corpses
Share:OnRecords("Eve Smith", { { s = "h", k = WOLF_KEY, h = "x", d = Wolf(999, 1, 1) } }, "WHISPER")
Check("a stranger's records are not taken", bob.records[WOLF_KEY].corpses == before)
Check("nor are records that are not whispered", (Share:OnRecords("Ana Smith",
    { { s = "h", k = WOLF_KEY, h = "y", d = Wolf(999, 1, 1) } }, "GUILD")) == nil
    and bob.records[WOLF_KEY].corpses == before)

-- A record sent under the wrong key lands nowhere.
local state = Share:PartnerFor("Ana Smith")
local ok, why = Share:Accept(state, { s = "h", k = "Somewhere else", h = "z", d = Wolf(5, 1, 1) })
Check("a record under the wrong key is refused", not ok and why == "wrong key", why)
Check("an unknown kind is refused", not (Share:Accept(state, { s = "x", k = "a", h = "z", d = {} })))

-- Turning it off stops the listening; what was taken stays.
Share:SetEnabled(false)
Check("off, it stops listening", not Comm.listening)
Check("and what was taken stays", bob.records[WOLF_KEY].corpses == 55)
Check("and is not described as shared", Share:Describe() == "Sharing is off.", Share:Describe())
Check("and Settings says it's off", Share:Status() == "Sharing is off.", Share:Status())

-- A save from before this existed loads with it off and nothing changed.
do
    local old = { windowScale = 120, tracker = { mobs = { Wolf = Tally(3, 0) } } }
    _G.BlackthornesFarmerDB = old
    ns.LoadSavedVariables()
    Check("an old save loads with sharing off", old.shareData == false and old.shareNames == "")
    Check("and its numbers are kept", old.windowScale == 120 and old.tracker.mobs.Wolf.kills == 3)
end

-- A whisper goes to "Name-Realm" (Classic Era, 2026-10-25: a bare name
-- never arrived for one player).
do
    local oldNormal, oldRealm = _G.GetNormalizedRealmName, _G.GetRealmName
    local oldChat = _G.C_ChatInfo
    local sentTo
    _G.C_ChatInfo = { SendAddonMessage = function(_, _, _, target) sentTo = target return 0 end }
    _G.GetNormalizedRealmName, _G.GetRealmName = function() return "Ashkandi" end, nil
    Check("a bare name gets this realm", Comm.WithRealm("Ana") == "Ana-Ashkandi", Comm.WithRealm("Ana"))
    Check("a name with a realm is left alone", Comm.WithRealm("Ana-Other") == "Ana-Other")
    Comm.RawSend("x", "WHISPER", "Bob")
    Check("a whisper is sent with the realm", sentTo == "Bob-Ashkandi", sentTo)
    _G.GetNormalizedRealmName, _G.GetRealmName = nil, function() return "Old Blanchy" end
    Check("else the realm's name without spaces", Comm.WithRealm("Ana") == "Ana-OldBlanchy", Comm.WithRealm("Ana"))
    _G.GetRealmName = nil
    Check("no realm known: the name as it was", Comm.WithRealm("Ana") == "Ana")
    _G.C_ChatInfo, _G.GetNormalizedRealmName, _G.GetRealmName = oldChat, oldNormal, oldRealm
end

suite.done()
