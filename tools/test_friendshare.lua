-- Sharing drop rates with friends typed in Settings (Logic/GuildShare.lua).
--
-- What matters: a friend is shared with like a guildmate, by whisper, with
-- no guild and guild sharing off; what they send is kept apart and never
-- raises the player's own counts; only names both sides typed share; a
-- friend is never treated as the other account, even one typed there
-- before; and a friend taken off the list is let go, their data kept.
-- Played as three accounts over a pretend chat.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("friendshare")

local ns = env.Load({ ui = true })
local Share, GuildShare, Comm = ns.Share, ns.GuildShare, ns.Comm

Share:OnEnable()
GuildShare:OnEnable()
suite.check("no friends by default", ns.db.friendNames == "" and #GuildShare:Friends() == 0)
suite.check("so nothing is listening", not Comm.listening)

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
    error("friend sharing never settled")
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
_G.IsInGuild = function() return false end

local function Check(label, ok, detail) suite.check(label, ok, detail) end
local function Kept(account) return account.db.guildDrops and account.db.guildDrops[WOLF] end

for _, account in ipairs(accounts) do Switch(account) Share:Apply() end
Settle()

-- Before this, Ana had typed Bob as her other account and taken his counts.
Switch(bob)
local bobId = ns.Transfer:SourceId()
Switch(ana)
ana.db.shareData, ana.db.shareNames = true, "Bob Smith"
ana.db.shareIn = { bob = { account = bobId, name = "Bob Smith" } }
Check("typed there, Bob is her other account", #Share:GetPartners() == 1)

-- Ana and Bob name each other as friends; Cid names Ana, who doesn't name him.
GuildShare:SetFriends("  Bob Smith, Ana Smith ")
Check("the box is saved trimmed", ana.db.friendNames == "Bob Smith, Ana Smith", ana.db.friendNames)
Check("her own name is never a friend", #GuildShare:Friends() == 1 and GuildShare:IsFriend("Bob Smith"))
Check("a friend is never her other account", #Share:GetPartners() == 0)
Check("friends alone keep it listening", Comm.listening == true and Share:Active())
Check("guild sharing stays off", not GuildShare:On())
Switch(bob) GuildShare:SetFriends("Ana Smith")
Switch(cid) GuildShare:SetFriends("Ana Smith")
Settle()

Switch(ana)
Check("Ana has Bob's corpses, kept apart", Kept(ana) and Kept(ana).corpses == 20, Kept(ana) and Kept(ana).corpses)
Check("her own corpses are her own", ana.records[WOLF].corpses == 30, ana.records[WOLF].corpses)
Check("his kills do not add to hers", ana.db.tracker.mobs.Wolf.kills == 40, ana.db.tracker.mobs.Wolf.kills)
Check("nothing went to the old account ledger", next(ana.db.shareIn.bob, nil) ~= nil
    and ana.db.shareIn.bob.h == nil and ana.db.shareIn.bob.credit == nil)
Switch(bob)
Check("Bob has Ana's corpses, kept apart", Kept(bob) and Kept(bob).corpses == 30, Kept(bob) and Kept(bob).corpses)
Check("his own are his own", bob.records[WOLF].corpses == 20 and bob.db.tracker.mobs.Wolf.kills == 25)
Switch(cid)
Check("Cid, whom Ana didn't name, got nothing", cid.db.guildDrops == nil or cid.db.guildDrops[WOLF] == nil)
Switch(ana)
Check("and gave Ana nothing", Kept(ana).corpses == 20 and GuildShare:PartnerFor("Cid Smith") == nil)

-- Hearing it all again adds nothing.
HalfHour()
HalfHour()
Check("syncing again counts nothing twice", Kept(ana).corpses == 20 and Kept(bob).corpses == 30
    and ana.records[WOLF].corpses == 30)

-- Ana takes Bob off the list: he is let go, what he gave is kept.
Switch(ana)
ana.db.shareData, ana.db.shareNames = false, ""
GuildShare:SetFriends("")
Check("taken off, Bob is no partner", GuildShare:PartnerFor("Bob Smith") == nil)
Check("and nothing listens", not Share:Active())
Check("his drops are kept", Kept(ana) and Kept(ana).corpses == 20)
bob.records[WOLF].corpses = 25
HalfHour()
Switch(ana)
Check("and nothing new comes from him", Kept(ana).corpses == 20, Kept(ana).corpses)

suite.done()
