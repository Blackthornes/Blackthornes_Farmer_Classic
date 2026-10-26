-- Sharing drop rates with guildmates.
--
-- What matters: it is off until ticked, guildmates who ticked it get each
-- other's drop records and one who did not is left alone, a guildmate's
-- counts never touch the player's own (kills, loot, drop records), nothing
-- is counted twice (not on a repeat, not through a third guildmate, not for
-- a second character of one account, not for the other account already
-- named), nothing that does not look like play is taken, a whisper from
-- anyone not heard on the guild channel is ignored, the guild's rates show
-- in the database only where nothing measured on Forever stands and leave
-- it again when turned off, and forgetting deletes only the guild's.
-- Played as three accounts over a pretend chat.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("guildshare")

local ns = env.Load({ ui = true })
-- The test player is "Blackthornes", one of the characters drops are sent
-- to; that sharing is tested in test_contribute.lua, so nobody is named here.
ns.Contribute.RECIPIENTS = {}
local Share, GuildShare, Comm = ns.Share, ns.GuildShare, ns.Comm

suite.check("the module is loaded", GuildShare ~= nil)
Share:OnEnable()
GuildShare:OnEnable()

suite.check("guild sharing is off by default", ns.db.shareGuild == false and not GuildShare:On())
suite.check("so nothing is listening", not Comm.listening)
suite.check("and it says so", GuildShare:Describe() == "Guild sharing is off.", GuildShare:Describe())
suite.check("and Settings says so", GuildShare:Status() == "Guild sharing is off.", GuildShare:Status())

--------------------------------------------------------------------------------
-- A pretend guild
--------------------------------------------------------------------------------

local function Tally(kills, copper, items)
    return { kills = kills, copper = copper, coinKills = kills, items = items or {}, qty = {}, stacks = {}, places = {} }
end

-- Module state each account keeps for itself while the test swaps them.
local KEPT = {
    { Share, "partners" }, { GuildShare, "byId" }, { GuildShare, "bySender" }, { GuildShare, "queue" },
    { GuildShare, "current" }, { GuildShare, "helloAt" }, { GuildShare, "answerAt" },
    { GuildShare, "building" }, { GuildShare, "ticker" }, { GuildShare, "me" },
    { GuildShare, "shown" }, { GuildShare, "publishing" }, { GuildShare, "publishAgain" },
    { GuildShare, "publishQueued" },
}

local function Account(name, db, records)
    if not db then
        db = {}
        for key, value in pairs(ns.DEFAULTS) do db[key] = value end
        db.tracker = { mobs = {} }
        db.gathering = { nodes = {}, spots = {} }
        db.fishing = { spots = {} }
    end
    local kept = {
        partners = {}, byId = {}, bySender = {}, queue = {},
        me = { key = "guild-hello", name = "", sections = { h = true } },
        shown = {},
    }
    return { name = name, db = db, records = records or {}, online = true, kept = kept }
end

local ana, bob, cid = Account("Ana Smith"), Account("Bob Smith"), Account("Cid Smith")
-- A second character of Ana's account: the same saved data.
local ann = Account("Ann Smith", ana.db, ana.records)
ann.online = false
local accounts = { ana, bob, cid, ann }
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
_G.UnitName = function(unit)
    if unit == "player" then return (current.name:match("^(%S+)")) end
    return nil
end
_G.UnitSurname = function() return "Smith" end
_G.IsInGuild = function() return true end
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

local guildSent = 0

--- Let time pass until everything is quiet. A guild message reaches every
--- other account online; a whisper only its target, if online.
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
            if message.channel == "GUILD" then
                guildSent = guildSent + 1
                for _, to in ipairs(accounts) do
                    if to.online and to ~= message.from then
                        Switch(to)
                        Comm:CHAT_MSG_ADDON(nil, message.prefix, message.text, message.channel, message.from.name)
                    end
                end
            else
                local to = byName[message.target]
                if to and to.online then
                    Switch(to)
                    Comm:CHAT_MSG_ADDON(nil, message.prefix, message.text, message.channel, message.from.name)
                end
            end
            moved = true
        end

        if not moved and #timers == 0 and #outbox == 0 then return end
    end
    error("guild sharing never settled")
end

--- Half an hour on, and everyone online says hello, as the ticker would.
local function HalfHour()
    clock = clock + GuildShare.SYNC_GAP + 1
    for _, account in ipairs(accounts) do
        if account.online then Switch(account) GuildShare:Hello() end
    end
    Settle()
end

local function Wolf(corpses, pelts)
    return {
        mob = "Wolf", zone = "Elwynn Forest", location = "Northshire", minLevel = 1, maxLevel = 3,
        corpses = corpses, coords = { 0.4, 0.5 },
        items = { ["Wolf Pelt"] = { name = "Wolf Pelt", count = pelts, corpses = pelts, id = 1 } },
    }
end
local WOLF = "Wolf|Elwynn Forest|Northshire"

ana.records[WOLF] = Wolf(30, 12)
bob.records[WOLF] = Wolf(20, 5)
cid.records[WOLF] = Wolf(10, 2)
ana.db.tracker.mobs.Wolf = Tally(40, 4000)
bob.db.tracker.mobs.Wolf = Tally(25, 2500)
cid.db.tracker.mobs.Rat = Tally(9, 90)
bob.db.gathering.nodes["Elwynn Forest|Northshire|Peacebloom"] = {
    zone = "Elwynn Forest", location = "Northshire", node = "Peacebloom", kind = "herb",
    gathers = 7, items = { Peacebloom = { gathers = 7, count = 9, id = 2447 } },
}

for _, account in ipairs(accounts) do Switch(account) Share:Apply() end
Settle()
suite.check("off everywhere, nothing goes to the guild", guildSent == 0, guildSent)

local function Check(label, ok, detail) suite.check(label, ok, detail) end

local function Guild(account) return account.db.guildDrops and account.db.guildDrops[WOLF] end
local function Ledgers(account)
    local count = 0
    for key, held in pairs(account.db.guildIn or {}) do
        if key:find("^guild:") and type(held) == "table" then count = count + 1 end
    end
    return count
end

-- Ana and Bob tick it; Cid does not.
Switch(ana) GuildShare:SetOn(true)
Check("on, it listens", Comm.listening == true)
Switch(bob) GuildShare:SetOn(true)
Settle()

Switch(ana)
Check("Ana has Bob's corpses, kept apart", Guild(ana) and Guild(ana).corpses == 20, Guild(ana) and Guild(ana).corpses)
Check("and his drops", Guild(ana).items["Wolf Pelt"].count == 5, Guild(ana).items["Wolf Pelt"].count)
Check("her own corpses are her own", ana.records[WOLF].corpses == 30, ana.records[WOLF].corpses)
Check("and her own drops", ana.records[WOLF].items["Wolf Pelt"].count == 12)
Check("his kills do not add to hers", ana.db.tracker.mobs.Wolf.kills == 40, ana.db.tracker.mobs.Wolf.kills)
Check("and his gathering does not come", ana.db.gathering.nodes["Elwynn Forest|Northshire|Peacebloom"] == nil)
Check("and says who was heard", GuildShare:Describe():find("heard this session: 1", 1, true) ~= nil,
    GuildShare:Describe())
do
    local status = GuildShare:Status()
    Check("Settings says what came in", status:find("Got drops for 1 mob from 1 guildmate.", 1, true) == 1, status)
    Check("and when", status:find("The last came in just now.", 1, true) ~= nil, status)
    Check("two hours on, it says so", GuildShare:Status(time() + 7300):find("2 hours ago", 1, true) ~= nil,
        GuildShare:Status(time() + 7300))
    local inGuild = _G.IsInGuild
    _G.IsInGuild = function() return false end
    Check("out of a guild, it says so", GuildShare:Status() == "You're not in a guild on this character.")
    _G.IsInGuild = inGuild
    local held = ns.db.guildDrops
    ns.db.guildDrops = {}
    Check("before anything comes in, it says what's needed",
        GuildShare:Status() == "Nothing from your guild yet. A guildmate needs this turned on too.", GuildShare:Status())
    ns.db.guildDrops = held
end
Switch(bob)
Check("Bob has Ana's corpses, kept apart", Guild(bob) and Guild(bob).corpses == 30)
Check("his own are his own", bob.records[WOLF].corpses == 20 and bob.db.tracker.mobs.Wolf.kills == 25)
Check("the ledger is the guild's, not the account sharing's", Ledgers(bob) == 1 and next(bob.db.shareIn or {}) == nil,
    Ledgers(bob))

Switch(cid)
Check("Cid, who did not tick it, got nothing", cid.records[WOLF].corpses == 10 and cid.db.guildDrops == nil)
Check("and gave nothing", ana.db.guildDrops["Rat"] == nil and bob.db.tracker.mobs.Rat == nil)

-- Hearing it all again adds nothing.
HalfHour()
HalfHour()
Check("syncing again counts nothing twice", Guild(ana).corpses == 20 and Guild(bob).corpses == 30
    and ana.records[WOLF].corpses == 30 and bob.records[WOLF].corpses == 20)

-- New kills reach the other side once.
ana.db.tracker.mobs.Wolf.kills = ana.db.tracker.mobs.Wolf.kills + 5
ana.records[WOLF].corpses = ana.records[WOLF].corpses + 5
HalfHour()
Check("a new kill reaches a guildmate", Guild(bob).corpses == 35, Guild(bob).corpses)
Check("without coming back round", Guild(ana).corpses == 20 and ana.records[WOLF].corpses == 35, Guild(ana).corpses)

-- Cid ticks it: he gets each guildmate's own counts, once.
Switch(cid) GuildShare:SetOn(true)
Settle()
HalfHour()
Check("Cid has everyone's corpses", Guild(cid) and Guild(cid).corpses == 55, Guild(cid) and Guild(cid).corpses)
Check("Ana has Cid's too, and Bob's only once", Guild(ana).corpses == 30, Guild(ana).corpses)
Check("and Bob", Guild(bob).corpses == 45, Guild(bob).corpses)
Check("and nobody's own changed", ana.records[WOLF].corpses == 35 and bob.records[WOLF].corpses == 20
    and cid.records[WOLF].corpses == 10)
Check("no kill tally went anywhere", ana.db.tracker.mobs.Rat == nil and cid.db.tracker.mobs.Wolf == nil)

-- Ana logs onto her other character: the same account, so nothing new.
ana.online, ann.online = false, true
Switch(bob) GuildShare:OnOffline("ana smith")
HalfHour()
Check("another character of the same account adds nothing", Guild(bob).corpses == 45, Guild(bob).corpses)
Switch(bob)
Check("and keeps one ledger per account", Ledgers(bob) == 2, Ledgers(bob))
Check("whispers to the character now playing", GuildShare.bySender["ann smith"] ~= nil
    and GuildShare.bySender["ana smith"] == nil)
ana.online, ann.online = true, false

-- Only what came in on the guild channel is heard.
Switch(bob)
local before = Guild(bob).corpses
Share:OnRecords("Eve Smith", { { s = "h", k = WOLF, h = "x", d = Wolf(999, 1) } }, "WHISPER")
Check("a whisper from someone never heard in the guild is not taken", Guild(bob).corpses == before
    and bob.records[WOLF].corpses == 20)
GuildShare:OnHello("Eve Smith", "abcdef123456:zz", "WHISPER")
Check("a hello that was not on the guild channel is ignored", GuildShare.byId["abcdef123456"] == nil)
GuildShare:OnHello("Eve Smith", "not an id:zz", "GUILD")
Check("a hello that does not read is ignored", GuildShare.bySender["eve smith"] == nil)

-- The other account already named in Settings is not taken again.
bob.db.shareIn = bob.db.shareIn or {}
bob.db.shareIn["dee smith"] = { name = "Dee Smith", account = "0123456789ab", hashes = {}, credit = {} }
GuildShare:OnHello("Dee Smith", "0123456789ab:zz", "GUILD")
Check("a guildmate who is your other account is left to account sharing", GuildShare.byId["0123456789ab"] == nil)
bob.db.shareIn["dee smith"] = nil

-- Counts that are not play are refused.
do
    local state = GuildShare.bySender["cid smith"]
    local silly = Wolf(1, 5000)
    local ok, why = Share:Accept(state, { s = "h", k = WOLF, h = "q", d = silly })
    Check("a drop record with far more items than corpses is refused", not ok and why == "not plausible", why)
    local huge = Wolf(2e9 - 1, 1)
    ok, why = Share:Accept(state, { s = "h", k = WOLF, h = "q", d = huge })
    Check("so is a count no one could reach", not ok and why == "not plausible", why)
    ok, why = Share:Accept(state, { s = "k", k = "Wolf", h = "q", d = Tally(5, 0) })
    Check("and a kill tally is not taken at all", not ok and why == "not shared", why)
    Check("and nothing changed", Guild(bob).corpses == before and bob.db.tracker.mobs.Wolf.kills == 25)
end

-- A big guild cannot grow the save without end.
do
    local limit = GuildShare.MAX_GUILDMATES
    GuildShare.MAX_GUILDMATES = 2
    GuildShare:OnHello("Fay Smith", "fedcba987654:zz", "GUILD")
    Check("past the most guildmates kept, a new one is not taken on", GuildShare.byId["fedcba987654"] == nil)
    GuildShare.MAX_GUILDMATES = limit
end

-- The guild's rates in the database and the loot table.
do
    Switch(bob)
    local DB = ns.DB
    DB:RegisterItem({ name = "Guild Test Fang", category = "Misc", sources = {
        { name = "Test Gnoll", zone = "Redridge Mountains", location = "Camp", chance = 50 },
        { name = "Test Murloc", zone = "Westfall", location = "Coast", chance = 7, provenance = "forever" },
    } })
    local function Spot(mob, corpses, fangs, item)
        local key = mob .. "|" .. (mob == "Test Gnoll" and "Redridge Mountains|Camp" or mob == "Test Murloc" and "Westfall|Coast" or "Duskwood|")
        bob.db.guildDrops[key] = {
            mob = mob, zone = key:match("^[^|]+|([^|]+)"), location = key:match("|([^|]*)$") ~= "" and key:match("|([^|]*)$") or nil,
            corpses = corpses, coords = { 40, 50 },
            items = { [item or "Guild Test Fang"] = { name = item or "Guild Test Fang", count = fangs, corpses = fangs } },
        }
    end
    Spot("Test Gnoll", 40, 10)
    Spot("Test Murloc", 40, 20)
    Spot("Test Ghoul", 25, 5, "Guild Test Bone")
    Spot("Test Bat", 10, 5, "Guild Test Wing")
    GuildShare:Publish()
    Settle()
    Switch(bob)

    local fang = DB:GetItem("Guild Test Fang")
    local function Row(item, mob)
        for _, source in ipairs(item and item.sources or {}) do
            if source.name == mob then return source end
        end
    end
    local gnoll = Row(fang, "Test Gnoll")
    Check("the guild's rate stands in for a Classic one", gnoll and gnoll.provenance == "guild" and gnoll.chance == 25,
        gnoll and gnoll.chance)
    Check("one row for the spot, not two", #fang.sources == 2, #fang.sources)
    local murloc = Row(fang, "Test Murloc")
    Check("but never for one measured on Forever", murloc and murloc.provenance == "forever" and murloc.chance == 7)
    local bone = DB:GetItem("Guild Test Bone")
    Check("an item only the guild has seen is listed", bone and Row(bone, "Test Ghoul")
        and Row(bone, "Test Ghoul").chance == 20)
    Check("a mob killed too few times gives no rate", DB:GetItem("Guild Test Wing") == nil)

    -- Bob has killed three gnolls: his kills stay three, the rate is the guild's.
    bob.db.tracker.mobs["Test Gnoll"] = Tally(3, 0, { ["Guild Test Fang"] = 1 })
    local loot = ns.LootTableUI:Table("Test Gnoll")
    Check("the loot table keeps his own kills", loot.kills == 3 and loot.rows[1].dropped == "1 of 3", loot.kills)
    Check("and shows no rate until he has his own, not even the guild's", loot.rows[1].chance == nil
        and loot.rows[1].rate == nil, loot.rows[1].chance)
    Check("with no value off it", loot.rows[1].perKill == nil)
    bob.db.tracker.mobs["Test Gnoll"] = Tally(30, 0, { ["Guild Test Fang"] = 3 })
    loot = ns.LootTableUI:Table("Test Gnoll")
    Check("past twenty kills the rate is his own", loot.rows[1].chance == 10, loot.rows[1].chance)
    Check("his tally was never added to", bob.db.tracker.mobs["Test Gnoll"].kills == 30)

    -- Off, the rows leave; the data stays.
    GuildShare:SetOn(false)
    Settle()
    Switch(bob)
    gnoll = Row(fang, "Test Gnoll")
    Check("off, the Classic row is back", gnoll and gnoll.provenance == "classic" and gnoll.chance == 50)
    Check("the item only the guild saw is gone", DB:GetItem("Guild Test Bone") == nil)
    Check("the Forever row was never touched", Row(fang, "Test Murloc").chance == 7)
    Check("the guild's data is kept", bob.db.guildDrops["Test Gnoll|Redridge Mountains|Camp"] ~= nil)
    Check("and the loot table has no guild rate", GuildShare:RateFor("Test Gnoll", "Guild Test Fang") == nil)
    GuildShare:SetOn(true)
    Settle()
    Switch(bob)
    Check("on again, it is back", Row(fang, "Test Gnoll").provenance == "guild" and DB:GetItem("Guild Test Bone") ~= nil)
end

-- Forgetting deletes the guild's, and only theirs.
do
    Switch(bob)
    local count = GuildShare:Forget()
    Settle()
    Switch(bob)
    Check("forget says how much", count and count > 0, count)
    Check("and turns it off", ns.db.shareGuild == false and not GuildShare:On())
    Check("the guild's data is gone", next(bob.db.guildDrops) == nil and next(bob.db.guildIn) == nil)
    Check("Bob's own corpses are as they were", bob.records[WOLF].corpses == 20, bob.records[WOLF].corpses)
    Check("and his own drops", bob.records[WOLF].items["Wolf Pelt"].count == 5)
    Check("and his own kills", bob.db.tracker.mobs.Wolf.kills == 25)
    Check("and his own gathering", bob.db.gathering.nodes["Elwynn Forest|Northshire|Peacebloom"].gathers == 7)
    Check("the database is back to its own rows", ns.DB:GetItem("Guild Test Bone") == nil
        and ns.DB:GetItem("Guild Test Fang").sources[1].provenance == "classic")
end

-- The typed command.
do
    Switch(cid)
    local printed = {}
    local print = ns.Print
    ns.Print = function(text) printed[#printed + 1] = text end
    ns.HandleSlash("share guild off")
    Check("/farm share guild off turns it off", ns.db.shareGuild == false)
    ns.HandleSlash("share guild on")
    Check("and on", ns.db.shareGuild == true)
    local corpses = Guild(cid).corpses
    ns.HandleSlash("share guild forget")
    Check("forget without confirm only explains", ns.db.shareGuild == true and Guild(cid).corpses == corpses)
    ns.Print = print
end

-- A save from before this existed loads with it off.
do
    local old = { windowScale = 120, shareIn = { ["bob smith"] = { name = "Bob Smith", credit = {}, hashes = {} } } }
    _G.BlackthornesFarmerDB = old
    ns.LoadSavedVariables()
    Check("an old save loads with guild sharing off", old.shareGuild == false)
    Check("and its ledgers are kept", old.shareIn["bob smith"].name == "Bob Smith")
    Check("and nothing of the guild's is made", old.guildDrops == nil)
end

suite.done()
