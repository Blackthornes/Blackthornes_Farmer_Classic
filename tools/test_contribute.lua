-- Drop records players send to Blackthornes (Logic/Contribute.lua).
--
-- What matters: it is off until ticked, and nothing goes anywhere while the
-- list of names is empty; a player who ticks it sends only their own drop
-- records, only to the named characters, and never gets anything back; the
-- named character keeps them apart from its own counts, counts nothing
-- twice, says once in chat what came in, and ignores anyone it was not
-- whispered by; a whisper from someone not named gets no answer; nothing
-- goes from a client in another language; and the What's New card is due
-- only while it would do something. Played as accounts over a pretend chat.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("contribute")

local ns = env.Load({ ui = true })
local Share, Contribute, Comm = ns.Share, ns.Contribute, ns.Comm

suite.check("the module is loaded", Contribute ~= nil)
Share:OnEnable()
ns.GuildShare:OnEnable()
Contribute:OnEnable()

suite.check("off by default", ns.db.shareDrops == false and not Contribute:On())
-- The Era copy names the owner's Era characters, used only on their realm.
do
    local realmName = nil
    local oldNormal, oldRealm = _G.GetNormalizedRealmName, _G.GetRealmName
    _G.GetNormalizedRealmName, _G.GetRealmName = function() return realmName end, nil
    suite.check("the Classic Era copy names two characters", #Contribute.RECIPIENTS == 2)
    suite.check("with the realm not read, nobody is sent to", #Contribute:Recipients() == 0)
    realmName = "Ashkandi"
    suite.check("on their realm both are sent to", #Contribute:Recipients() == 2)
    realmName = "Mankrik"
    suite.check("on another realm nobody is", #Contribute:Recipients() == 0 and not Contribute:Sending())
    suite.check("realms compare without spaces or case",
        Contribute.RealmKey("Ana-Some Realm") == Contribute.RealmKey("Bob-somerealm")
        and Contribute.RealmKey("Ana") == nil)
    realmName = "Ashkandi"
    suite.check("no Forever character is named", (function()
        for _, name in ipairs(Contribute.RECIPIENTS) do
            if name:find(" ", 1, true) or not name:find("-Ashkandi$") then return false end
        end
        return true
    end)())
    _G.GetNormalizedRealmName, _G.GetRealmName = oldNormal, oldRealm
end

-- Only North America sends.
_G.GetCurrentRegion, _G.GetCurrentRegionName = nil, nil
suite.check("a client that will not say its region sends nothing", not Contribute:InRegion())
_G.GetCurrentRegion = function() return 3 end
suite.check("Europe sends nothing", not Contribute:InRegion())
_G.GetCurrentRegion = function() error("no") end
_G.GetCurrentRegionName = function() return "US" end
suite.check("the region's name is read when its number is not", Contribute:InRegion())
_G.GetCurrentRegionName = nil
_G.GetCurrentRegion = function() return 110 end
suite.check("the Forever test client's 110 is not this copy's", not Contribute:InRegion())
_G.GetCurrentRegion = function() return 1 end
suite.check("North America sends", Contribute:InRegion())

local shipped = Contribute.RECIPIENTS
Contribute.RECIPIENTS = {}
local tip
for _, card in ipairs(ns.WHATS_NEW_TIPS or {}) do
    if card.key == "shareDrops" then tip = card end
end
suite.check("no What's New card offers it", tip == nil)

--------------------------------------------------------------------------------
-- Pretend accounts
--------------------------------------------------------------------------------

local KEPT = {
    { Share, "partners" }, { Contribute, "byId" }, { Contribute, "bySender" }, { Contribute, "toState" },
    { Contribute, "queue" }, { Contribute, "current" }, { Contribute, "building" }, { Contribute, "ticker" },
    { Contribute, "me" },
}

local function Account(name)
    local db = {}
    for key, value in pairs(ns.DEFAULTS) do db[key] = value end
    db.tracker = { mobs = {} }
    db.gathering = { nodes = {}, spots = {} }
    db.fishing = { spots = {} }
    local kept = {
        partners = {}, byId = {}, bySender = {}, toState = {}, queue = {},
        me = { key = "contribute-hello", name = "", sections = { h = true } },
    }
    return { name = name, db = db, records = {}, online = true, kept = kept, said = {} }
end

local ana, bob, tia = Account("Ana Smith"), Account("Bob Smith"), Account("Tia Smith")
local accounts = { ana, bob, tia }
local byName = {}
for _, account in ipairs(accounts) do byName[account.name] = account end
local current

local function Switch(account)
    if current then
        for _, pair in ipairs(KEPT) do current.kept[pair[2]] = pair[1][pair[2]] end
    end
    current = account
    for _, pair in ipairs(KEPT) do pair[1][pair[2]] = account.kept[pair[2]] end
    ns.db = account.db
    ns.Harvest.records = account.records
    account.db.harvest = account.records
end

local outbox, timers = {}, {}
local clock = 0
local locale = "enUS"
_G.GetLocale = function() return locale end
_G.UnitName = function(unit)
    if unit == "player" then return (current.name:match("^(%S+)")) end
    return nil
end
_G.UnitSurname = function() return "Smith" end
-- The whole name, as the game gives it once the last name is read.
Comm.PlayerName = function() return current.name end
_G.IsInGuild = function() return false end
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
ns.Print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    current.said[#current.said + 1] = table.concat(parts, " ")
end

local whispers = 0
-- The alert: counted per account, never drawn.
ns.OpenNote.Notice = function() current.alerts = (current.alerts or 0) + 1 end
ns.Tracker.PlayFile = function() return true end

local function Settle()
    for _ = 1, 6000 do
        clock = clock + 5
        local moved = false

        local due = timers
        timers = {}
        for _, timer in ipairs(due) do
            Switch(timer.account)
            if timer.account.online then timer.fn() end
            moved = true
        end

        for _, account in ipairs(accounts) do
            Switch(account)
            if account.online and Comm:Pending() > 0 then Comm:Pump() moved = true end
        end

        local mail = outbox
        outbox = {}
        for _, message in ipairs(mail) do
            whispers = whispers + 1
            local to = byName[message.target]
            if to and to.online then
                Switch(to)
                Comm:CHAT_MSG_ADDON(nil, message.prefix, message.text, message.channel, message.from.name)
            end
            moved = true
        end

        if not moved and #timers == 0 and #outbox == 0 then return end
    end
    error("never settled")
end

local function HalfHour()
    clock = clock + Contribute.SYNC_GAP + 1
    for _, account in ipairs(accounts) do
        if account.online then Switch(account) Contribute:Hello() end
    end
    Settle()
end

local function Wolf(corpses, pelts)
    return {
        mob = "Wolf", zone = "Elwynn Forest", location = "Northshire", minLevel = 1, maxLevel = 3,
        corpses = corpses, coords = { 40, 50 },
        items = { ["Wolf Pelt"] = { name = "Wolf Pelt", count = pelts, corpses = pelts, id = 1 } },
    }
end
local WOLF = "Wolf|Elwynn Forest|Northshire"

ana.records[WOLF] = Wolf(30, 12)
bob.records[WOLF] = Wolf(20, 5)
tia.records[WOLF] = Wolf(50, 25)
ana.db.tracker.mobs.Wolf = { kills = 40, copper = 0, coinKills = 0, items = {}, qty = {}, stacks = {}, places = {} }
ana.db.gathering.nodes["Elwynn Forest|Northshire|Peacebloom"] = {
    zone = "Elwynn Forest", location = "Northshire", node = "Peacebloom", kind = "herb",
    gathers = 7, items = { Peacebloom = { gathers = 7, count = 9, id = 2447 } },
}

local function Check(label, ok, detail) suite.check(label, ok, detail) end
local function Shared(account) return account.db.sharedDrops and account.db.sharedDrops[WOLF] end

-- With no names, ticking it sends nothing.
Switch(ana) Contribute:SetOn(true)
HalfHour()
Check("with no names listed, nothing is whispered", whispers == 0, whispers)

Contribute.RECIPIENTS = { "Tia Smith" }
Switch(ana) ns.db.shareDrops = false
for _, account in ipairs(accounts) do Switch(account) Share:Apply() end
Settle()
Switch(ana)
Check("a named character is receiving", (function() Switch(tia) return Contribute:Receiving() end)())
Switch(ana)
Check("a player who is not named is not", not Contribute:Receiving())
HalfHour()
Check("still off, nothing is whispered", whispers == 0, whispers)

-- Ana ticks it on the About page; Bob does not.
Switch(ana) Contribute:SetOn(true)
Check("ticking it turns it on", ns.db.shareDrops == true and Contribute:Sending())
HalfHour()

Switch(tia)
Check("Tia has Ana's corpses, kept apart", Shared(tia) and Shared(tia).corpses == 30, Shared(tia) and Shared(tia).corpses)
Check("and her drops", Shared(tia).items["Wolf Pelt"].count == 12)
Check("Tia's own records are her own", tia.records[WOLF].corpses == 50, tia.records[WOLF].corpses)
Check("no kill tally came", tia.db.tracker.mobs.Wolf == nil)
Check("no gathering came", next(tia.db.gathering.nodes) == nil)
Check("the ledger is kept apart too", tia.db.sharedIn ~= nil and next(tia.db.shareIn or {}) == nil)
Check("one chat line says what came in", #tia.said == 1 and tia.said[1] == "Got drops for 1 mob from Ana Smith.",
    tia.said[1])
Check("a sound and a note on screen go with it", tia.alerts == 1, tia.alerts)
Check("the share is kept in the log", type(tia.db.sharedLog) == "table" and #tia.db.sharedLog == 1
    and tia.db.sharedLog[1].name == "Ana Smith" and tia.db.sharedLog[1].mobs == 1)
do
    local lines = Contribute:LogLines()
    Check("the log reads back newest first", #lines == 1 and lines[1]:find("drops for 1 mob from Ana Smith.", 1, true) ~= nil,
        lines[1])
    for i = 1, Contribute.LOG_KEEP + 5 do Contribute:Note("Bob Stone", i + 1) end
    Check("only the newest are kept", #tia.db.sharedLog == Contribute.LOG_KEEP
        and tia.db.sharedLog[#tia.db.sharedLog].mobs == Contribute.LOG_KEEP + 6)
    lines = Contribute:LogLines()
    Check("and a few are shown", #lines == Contribute.LOG_SHOW
        and lines[1]:find(("drops for %d mobs"):format(Contribute.LOG_KEEP + 6), 1, true) ~= nil, lines[1])
    tia.db.sharedLog = { tia.db.sharedLog[1] }
    tia.db.sharedLog[1] = { at = 0, name = "Ana Smith", mobs = 1 }
end

Switch(ana)
Contribute:PrintLog()
Check("a sender's log is empty", ana.said[1] == "Nobody has shared drops with you yet.", ana.said[1])
ana.said = {}
Check("Ana got nothing back", ana.db.sharedDrops == nil and ana.records[WOLF].corpses == 30
    and next(ana.db.shareIn or {}) == nil)
Check("and Ana is never told anything", #ana.said == 0 and (ana.alerts or 0) == 0, ana.said[1])
Switch(tia)
Check("Bob, who did not tick it, sent nothing", Shared(tia).corpses == 30 and Contribute.bySender["bob smith"] == nil)

-- Again adds nothing, and says nothing.
HalfHour()
HalfHour()
Switch(tia)
Check("syncing again counts nothing twice", Shared(tia).corpses == 30, Shared(tia).corpses)
Check("and says nothing more", #tia.said == 1, #tia.said)

-- New kills reach Tia once.
ana.records[WOLF].corpses = ana.records[WOLF].corpses + 5
HalfHour()
Switch(tia)
Check("a new kill reaches Tia", Shared(tia).corpses == 35, Shared(tia).corpses)
Check("with a line for it", #tia.said == 2)

-- Bob ticks it too.
Switch(bob) Contribute:SetOn(true)
HalfHour()
Switch(tia)
Check("Bob's are added to Ana's", Shared(tia).corpses == 55, Shared(tia).corpses)
Check("and two ledgers are kept", (function()
    local n = 0
    for _ in pairs(tia.db.sharedIn) do n = n + 1 end
    return n == 2
end)())

-- Only Tia may ask, and only what she was told about is taken.
Switch(ana)
local before = #outbox
Share:OnHello("Eve Smith", "", "WHISPER", false)
Check("a hello from someone not named gets no answer", #outbox == before)
Share:OnWant("Eve Smith", { h = { "x" } }, "WHISPER")
Check("and a want from them sends nothing", #outbox == before)
Switch(tia)
local corpses = Shared(tia).corpses
Share:OnRecords("Eve Smith", { { s = "h", k = WOLF, h = "x", d = Wolf(999, 1) } }, "WHISPER")
Check("records from someone who never said hello are not taken", Shared(tia).corpses == corpses)
Contribute:OnHello("Eve Smith", "abcdef123456:zz", "GUILD")
Check("a hello that is not a whisper is ignored", Contribute.byId["abcdef123456"] == nil)

-- Counts that are not play are refused.
do
    local state = Contribute.bySender["ana smith"]
    local ok, why = Share:Accept(state, { s = "h", k = WOLF, h = "q", d = Wolf(1, 5000) })
    Check("a drop record with far more items than corpses is refused", not ok and why == "not plausible", why)
    ok, why = Share:Accept(state, { s = "k", k = "Wolf", h = "q", d = { kills = 5 } })
    Check("and a kill tally is not taken", not ok and why == "not shared", why)
end

-- Tia never sends her own.
Switch(ana)
Check("Ana holds no records of Tia's", ana.records[WOLF].corpses == 35 and ana.db.sharedDrops == nil)

-- Away from North America nothing goes, ticked or not.
Switch(ana)
_G.GetCurrentRegion = function() return 2 end
Check("a player in another region does not send", Contribute:On() and not Contribute:Sending())
_G.GetCurrentRegion = function() return 1 end

-- A client in another language sends nothing.
locale = "deDE"
Switch(bob)
Check("a German client does not send", not Contribute:Sending())
locale = "enUS"

-- Turned off, nothing more goes.
Switch(ana) Contribute:SetOn(false)
Switch(bob) Contribute:SetOn(false)
ana.records[WOLF].corpses = ana.records[WOLF].corpses + 5
whispers = 0
HalfHour()
Check("off, nothing is whispered", whispers == 0, whispers)
Switch(tia)
Check("and nothing more comes", Shared(tia).corpses == 55)

-- Settings and the command.
ns.HandleSlash("share drops on")
Check("/farm share drops on turns it on", ns.db.shareDrops == true)
ns.HandleSlash("share drops off")
Check("and off", ns.db.shareDrops == false)

-- An old save loads with it off.
do
    local old = { windowScale = 120 }
    _G.BlackthornesFarmerDB = old
    ns.LoadSavedVariables()
    Check("an old save loads with sharing drops off", old.shareDrops == false)
    Check("and nothing is made", old.sharedDrops == nil and old.sharedIn == nil)
end

Contribute.RECIPIENTS = shipped

-- Both of the shipped characters take drops, and nobody else does.
do
    local before = Comm.PlayerName
    local oldNormal = _G.GetNormalizedRealmName
    _G.GetNormalizedRealmName = function() return "Ashkandi" end
    for _, name in ipairs(shipped) do
        Comm.PlayerName = function() return name end
        suite.check("a shipped character takes drops: " .. name, Contribute:Receiving())
    end
    Comm.PlayerName = function() return "Tia Smith" end
    suite.check("anyone else does not", not Contribute:Receiving())
    Comm.PlayerName = function() return "Blacklock" end
    suite.check("the first name alone is how Era says it", Contribute:Receiving())
    _G.GetNormalizedRealmName = function() return "Mankrik" end
    suite.check("the same name on another realm does not", not Contribute:Receiving())
    _G.GetNormalizedRealmName = oldNormal
    Comm.PlayerName = before
end
suite.done()
