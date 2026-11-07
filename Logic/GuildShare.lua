-- Blackthornes Farmer -- Logic/GuildShare.lua
-- Drop rates shared with guildmates who use Farmer.
--
-- Asked 2026-10-13 by the owner, off by default. It is the account sharing
-- of Logic/Share.lua with a different way of finding partners: instead of
-- names typed in Settings, a guildmate is anyone heard on the guild's addon
-- channel, which only members of the guild can send on.
--
--   * Now and then (and soon after login) each side says hello to the guild:
--     one short message with its Farmer id (`Transfer:SourceId`) and a hash
--     of what it would share. Someone new to a side gets a hello back, at
--     most one a minute, so the two always know each other.
--   * A hello whose hash differs from the last one fully taken starts the
--     same whispered conversation as account sharing (manifest, want,
--     records), one guildmate at a time, each at most every half hour.
--   * Only drop records go ("h"), and only the sender's own: what came from
--     the guild is never sent on.
--
-- What is different from account sharing, because a guild is not you:
--   * A guildmate's counts never join the player's own. Kills, loot, the
--     session, Rankings, the tooltip's kill count and everything earned by
--     killing stay the player's alone. They are kept apart, in `guildDrops`
--     (shaped as Harvest's records) with their ledgers in `guildIn`, and only
--     the drop rates they make show: as rows in the database marked "guild"
--     (only where nothing measured on Forever stands, and only from
--     MIN_SAMPLE corpses). A mob's loot table no longer shows them before
--     the player's own rates (the owner, 2026-10-15); GuildShare:RateFor
--     is kept for whatever reads it.
--   * Records also have to look like play (`GuildShare.Plausible`).
--   * At most MAX_GUILDMATES guildmates are kept.
--   * Turned off, the guild's rows leave the database (the data is kept);
--     `/farm share guild forget confirm` deletes it and turns sharing off.
--
-- Saved, account wide, never renamed: `shareGuild` (on or off),
-- `guildDrops` and `guildIn` (`top` there is the hash last taken in full).

local _, ns = ...
local L = ns.L

local GuildShare = ns.NewModule("GuildShare")

local Comm = ns.Comm
local Share = ns.Share

GuildShare.HELLO_SECONDS = 900    -- a hello to the guild every quarter hour
GuildShare.FIRST_HELLO = 30       -- and this long after login
GuildShare.ANSWER_GAP = 60        -- at most one hello back a minute; answers held past it are not dropped
GuildShare.QUIET_ANSWER = 300     -- a guildmate not heard this long has likely reloaded: answer them
GuildShare.HEARD_US = 60          -- a hello this soon after ours arrived while they were up: they heard ours
GuildShare.SYNC_GAP = 600         -- one guildmate synced at most this often
GuildShare.SYNC_TIMEOUT = 600     -- a sync left this long is given up
GuildShare.STILL_COMING = 60      -- unless records came in this recently
GuildShare.CONFIRM_AFTER = 30     -- quiet this long after records: compare again
GuildShare.MAX_GUILDMATES = 20

GuildShare.byId = {}       -- Farmer id -> state
GuildShare.bySender = {}   -- name key of the character playing -> state
GuildShare.queue = {}
GuildShare.me = { key = "guild-hello", name = "", sections = { h = true } }
GuildShare.shown = {}       -- record key -> { corpses, rows } put in the database

function GuildShare:On()
    return ns.db ~= nil and ns.db.shareGuild == true
end

local function InGuild()
    local ok, inGuild = pcall(IsInGuild)
    return ok and inGuild == true
end

local function ValidId(id)
    return type(id) == "string" and #id >= 6 and #id <= 16 and id:match("^%x+$") ~= nil
end

-- A guildmate's rate is shown from this many corpses, as the player's own.
GuildShare.MIN_SAMPLE = 20
GuildShare.PUBLISH_SLICE = 100   -- records put in the database a frame

--- The guild's drop records, as Harvest's: [mob|zone|location] = record.
local function Drops(create)
    if type(ns.db) ~= "table" then return nil end
    if type(ns.db.guildDrops) ~= "table" then
        if not create then return nil end
        ns.db.guildDrops = {}
    end
    return ns.db.guildDrops
end

--- What was heard from and taken from each guildmate.
local function Ledgers()
    if type(ns.db) ~= "table" then return {} end
    if type(ns.db.guildIn) ~= "table" then ns.db.guildIn = {} end
    return ns.db.guildIn
end

--- The other account's ledgers, from account sharing.
local function AccountLedgers()
    return type(ns.db) == "table" and type(ns.db.shareIn) == "table" and ns.db.shareIn or {}
end

function GuildShare.LedgerKey(id)
    return "guild:" .. id
end

--- How many guildmates are kept: their ledgers, and the ones heard this
--- session whose ledger is not made yet.
local function Guildmates()
    local count = 0
    for _, held in pairs(Ledgers()) do
        if type(held) == "table" then count = count + 1 end
    end
    for _, state in pairs(GuildShare.byId) do
        if type(Ledgers()[state.key]) ~= "table" then count = count + 1 end
    end
    return count
end

--- True when `id` is the other account named in Settings: its counts come
--- by whisper already.
local function LinkedAccount(id)
    for _, held in pairs(AccountLedgers()) do
        if type(held) == "table" and held.kind == nil and held.account == id then return true end
    end
    return false
end

--- A guildmate's record has to look like play.
function GuildShare.Plausible(section, record)
    local Transfer = ns.Transfer
    local _, biggest = Transfer.Scan(section.spec, record, nil)
    if biggest > Transfer.MAX_COUNT then return false end
    return Transfer.Plausible(section, record)
end

--------------------------------------------------------------------------------
-- Hellos
--------------------------------------------------------------------------------

--- Say to the guild who this Farmer is and what it has. `fresh` is a copy
--- that just loaded (login, a reload, the check) and knows nobody yet: it
--- says so too ("N"), and every guildmate answers, heard lately or not.
function GuildShare:Hello(fresh)
    self.helloTried = (self.helloTried or 0) + 1
    if not self:On() then self.helloSkipped = "sharing off" return end
    if not InGuild() then self.helloSkipped = "not in a guild yet" return end
    if self.building then self.helloSkipped = "still building the last one" return end
    self.building = true
    self.helloAt = time()
    Share:Build(self.me, function(manifest)
        self.building = nil
        if not self:On() or not InGuild() then self.helloSkipped = "off or out of the guild while building" return end
        local ok, err = pcall(function()
            local top = Comm.Hash(ns.Serialize.EncodeCanonical(manifest))
            local body = ns.Transfer:SourceId() .. ":" .. top
            Comm:Send("G", body, "GUILD")
            if fresh then Comm:Send("N", body, "GUILD") end
        end)
        if not ok then self.helloSkipped = "error: " .. tostring(err) return end
        self.helloSent = (self.helloSent or 0) + 1
        self.sentAt = time()
        self.helloSkipped = nil
    end)
end

--- Someone was heard who may not know this side: say hello back soon. At
--- most one goes out an ANSWER_GAP; one asked for sooner waits for the gap
--- to pass rather than being dropped, and one answer covers everyone heard
--- while it waited (a reload used to go unanswered when two guildmates said
--- hello within a minute of each other).
function GuildShare:AnswerSoon()
    if self.answerPending then return end
    local now = time()
    local wait = 3 + math.random() * 10
    if self.answerAt and now - self.answerAt < self.ANSWER_GAP then
        wait = wait + (self.ANSWER_GAP - (now - self.answerAt))
    end
    self.answerPending = true
    C_Timer.After(wait, function()
        GuildShare.answerPending = nil
        GuildShare.answerAt = time()
        GuildShare:Hello()
    end)
end

GuildShare.passed = {}   -- [sender] = why a hello was not taken, for the check

--- A hello on the guild channel: "G" every quarter hour and as an answer,
--- "N" (`fresh`) from a copy that just loaded and knows nobody.
function GuildShare:OnHello(sender, body, channel, fresh)
    local function Pass(why)
        if type(sender) == "string" then self.passed[sender] = why end
    end
    if channel ~= "GUILD" then return Pass("not on the guild channel") end
    if not self:On() then return Pass("guild sharing is off here") end
    if Comm.IsMe(sender) then return Pass("read as this character") end
    local id, top = (body or ""):match("^(%x+):(%w+)$")
    if not ValidId(id) or #top > 12 then return Pass("hello not read") end
    if id == ns.Transfer:SourceId() then return Pass("same Farmer as this one") end
    if LinkedAccount(id) then return Pass("your other account, shared by name") end
    local senderKey = Comm.NameKey(sender)
    if not senderKey then return Pass("no name") end
    self.passed[sender] = nil

    local state = self.byId[id]
    local new = state == nil
    if new then
        local key = GuildShare.LedgerKey(id)
        if type(Ledgers()[key]) ~= "table" and Guildmates() >= self.MAX_GUILDMATES then return end
        state = {
            key = key, id = id, guild = true, apart = true, owner = self, check = GuildShare.Plausible,
            sections = { h = true },
            store = function(section, create) return section == "h" and Drops(create) or nil end,
            book = Ledgers,
        }
        self.byId[id] = state
    end

    -- The character playing on that account now.
    if state.senderKey and state.senderKey ~= senderKey then self.bySender[state.senderKey] = nil end
    local other = self.bySender[senderKey]
    if other and other ~= state then other.senderKey = nil end
    state.name, state.senderKey = sender, senderKey
    self.bySender[senderKey] = state
    -- A copy that just loaded knows nobody: it is always answered. Someone
    -- already known who was quiet a while, or went offline, has likely
    -- reloaded too and is answered as well, unless our own hello went out
    -- a moment ago, which they were up to hear (their hello is an answer
    -- to it, not a question); or they wait up to a quarter hour.
    local now = time()
    local back = not state.online or not state.heardAt or now - state.heardAt > self.QUIET_ANSWER
    local heardUs = self.sentAt and now - self.sentAt < self.HEARD_US
    state.online, state.heardAt, state.top = true, now, top

    if fresh or ((new or back) and not heardUs) then self:AnswerSoon() end
    local held = Ledgers()[state.key]
    if not (type(held) == "table" and held.top == top) then self:Want(state) end
end

--------------------------------------------------------------------------------
-- Syncing, one guildmate at a time
--------------------------------------------------------------------------------

function GuildShare:Want(state)
    if state.queued or self.current == state then return end
    if state.syncedAt and time() - state.syncedAt < self.SYNC_GAP then return end
    state.queued = true
    self.queue[#self.queue + 1] = state
    -- A moment's wait, so their own answer to a hello comes in first.
    C_Timer.After(5 + math.random() * 10, function() GuildShare:Next() end)
end

function GuildShare:Finish(state)
    if self.current == state then self.current = nil end
end

function GuildShare:Next()
    if not self:On() then return end
    local current = self.current
    if current then
        -- A big harvest takes longer than the timeout to send: while its
        -- records keep coming, it is waited on, not given up halfway.
        local now = time()
        local busy = now - (current.syncStart or 0) < self.SYNC_TIMEOUT
            or now - (current.lastRecordAt or 0) < self.STILL_COMING
        if current.online and busy then
            if not self.lookAgain then
                self.lookAgain = true
                C_Timer.After(self.STILL_COMING, function()
                    GuildShare.lookAgain = nil
                    GuildShare:Next()
                end)
            end
            return
        end
        self:Finish(current)
    end

    local state
    repeat
        state = table.remove(self.queue, 1)
        if state then state.queued = nil end
    until not state or state.online
    if not state then return end

    self.current, state.syncStart, state.syncedAt = state, time(), time()
    Share:SendManifest(state)
    C_Timer.After(self.STILL_COMING, function() GuildShare:Next() end)
end

--- Their manifest was compared with what is held (Share:OnManifest). Nothing
--- wanted: everything they announced is in, and the next one may go.
function GuildShare:Compared(state, wanted)
    if wanted > 0 then return end
    local held = Ledgers()[state.key]
    if type(held) == "table" and state.top then held.top = state.top end
    if self.current == state then
        self:Finish(state)
        self:Next()
    end
end

--- Records came in. Once they stop, ask for their manifest again (a hello
--- is always answered with one), which also says whether everything arrived.
function GuildShare:Received(state)
    state.lastRecordAt = time()
    self:DropsChanged()
    self:PublishSoon()
    if ns.SettingsUI and ns.SettingsUI.ShareStatusChanged then pcall(ns.SettingsUI.ShareStatusChanged, ns.SettingsUI) end
    if state.confirming then return end
    state.confirming = true
    local function Confirm()
        if time() - (state.lastRecordAt or 0) < self.CONFIRM_AFTER - 1 then
            C_Timer.After(self.CONFIRM_AFTER, Confirm)
            return
        end
        state.confirming = nil
        if self:On() and state.online and self.current == state then Share:Hello(state.name) end
    end
    C_Timer.After(self.CONFIRM_AFTER, Confirm)
end

--- A whisper from a guildmate: their state, or nil.
function GuildShare:PartnerFor(sender)
    if not self:On() then return nil end
    local key = Comm.NameKey(sender)
    if not key then return nil end
    if self.bySender[key] then return self.bySender[key] end
    -- A whisper can name its sender by the first name alone, or the guild
    -- channel can: then the one guildmate heard with that first name, and
    -- only when no other shares it.
    local first = key:match("^(%S+)")
    local found
    for heard, state in pairs(self.bySender) do
        if heard:match("^(%S+)") == first then
            if found then return nil end
            found = state
        end
    end
    return found
end

function GuildShare:OnOffline(key)
    local state = self.bySender[key]
    if not state then return end
    state.online = false
    if self.current == state then
        self:Finish(state)
        self:Next()
    end
end

--------------------------------------------------------------------------------
-- What the guild's records show: rows in the database, and loot table rates
--------------------------------------------------------------------------------

--- A record that can give a rate: a named mob with enough corpses.
local function Usable(record)
    return type(record) == "table" and type(record.mob) == "string"
        and not record.mob:match("^Creature #%d+$")
        and type(record.zone) == "string" and record.zone ~= ""
        and type(record.corpses) == "number" and record.corpses >= GuildShare.MIN_SAMPLE
        and type(record.items) == "table"
end

local function Coords(record)
    local coords = record.coords
    if type(coords) ~= "table" then return nil end
    local x, y = tonumber(coords[1]), tonumber(coords[2])
    if not (x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100) then return nil end
    return { x, y }
end

--- Take one record's rows back out of the database.
local function Hide(entry)
    local DB = ns.DB
    for index = #entry.rows, 1, -1 do
        local row = entry.rows[index]
        DB:RemoveSource(row.item, row.source)
        if row.item.guildOnly and #row.item.sources == 0 then DB:RemoveItem(row.item) end
    end
end

--- Put one record's rates in the database: a row per item it dropped, where
--- no row measured on Forever stands for the same spot.
local function Show(record, byID)
    local DB = ns.DB
    local rows = {}
    for name, entry in pairs(record.items) do
        local corpses = type(entry) == "table" and tonumber(entry.corpses) or 0
        local chance = corpses / record.corpses * 100
        local nodeOnly = ns.Gathering ~= nil and ns.Gathering.IsNodeOnly(name)
        if type(name) == "string" and name ~= "" and chance > 0 and chance <= 100 and not nodeOnly then
            local item = DB.items[name:lower()] or (tonumber(entry.id) and byID[tonumber(entry.id)])
            if not item then
                item = DB:RegisterItem({ name = name, id = tonumber(entry.id) })
                if item then item.guildOnly = true end
            end
            local source = item and DB:AddSource(item, {
                name = record.mob,
                zone = record.zone,
                location = type(record.location) == "string" and record.location ~= "" and record.location or nil,
                coords = Coords(record),
                minLevel = tonumber(record.minLevel),
                maxLevel = tonumber(record.maxLevel),
                chance = chance,
                provenance = "guild",
            })
            if source then
                rows[#rows + 1] = { item = item, source = source }
            elseif item and item.guildOnly and #item.sources == 0 then
                DB:RemoveItem(item)
            end
        end
    end
    return rows
end

--- Bring the database's guild rows up to date, a few records a frame: only
--- the records that changed since last time are touched.
function GuildShare:Publish()
    if not ns.DB then return end
    if self.publishing then
        self.publishAgain = true
        return
    end
    local drops = self:On() and Drops() or {}
    local todo = {}
    for key, entry in pairs(self.shown) do
        local record = drops[key]
        if not (Usable(record) and record.corpses == entry.corpses) then todo[#todo + 1] = key end
    end
    for key, record in pairs(drops) do
        if not self.shown[key] and Usable(record) then todo[#todo + 1] = key end
    end
    if #todo == 0 then return end

    self.publishing = true
    local index = 1
    local function Step()
        local byID = ns.DB:ByID()
        local stop = math.min(#todo, index + self.PUBLISH_SLICE - 1)
        while index <= stop do
            local key = todo[index]
            index = index + 1
            local entry = self.shown[key]
            if entry then
                pcall(Hide, entry)
                self.shown[key] = nil
            end
            local record = self:On() and Drops() and Drops()[key]
            if Usable(record) then
                local ok, rows = pcall(Show, record, byID)
                self.shown[key] = { corpses = record.corpses, rows = ok and rows or {} }
            end
        end
        if index <= #todo then
            C_Timer.After(0, Step)
            return
        end
        self.publishing = nil
        if ns.UI and ns.UI.RefreshActive then pcall(ns.UI.RefreshActive, ns.UI) end
        if ns.LootTableUI and ns.LootTableUI.Refresh then pcall(ns.LootTableUI.Refresh, ns.LootTableUI) end
        if self.publishAgain then
            self.publishAgain = nil
            self:Publish()
        end
    end
    Step()
end

--- Once records stop arriving for a moment.
function GuildShare:PublishSoon()
    if self.publishQueued then return end
    self.publishQueued = true
    C_Timer.After(2, function()
        GuildShare.publishQueued = nil
        GuildShare:Publish()
    end)
end

--- The guild's drop rate for `itemName` off `mob`, all its places together:
--- the percentage and how many corpses it is from, or nil below MIN_SAMPLE.
function GuildShare:RateFor(mob, itemName)
    if not self:On() then return nil end
    local drops = Drops()
    if not drops or type(mob) ~= "string" or type(itemName) ~= "string" then return nil end
    local corpses, dropped = 0, 0
    for _, record in pairs(drops) do
        if type(record) == "table" and record.mob == mob and type(record.corpses) == "number" then
            corpses = corpses + record.corpses
            local entry = type(record.items) == "table" and record.items[itemName]
            if type(entry) == "table" then dropped = dropped + (tonumber(entry.corpses) or 0) end
        end
    end
    if corpses < self.MIN_SAMPLE then return nil end
    return math.min(100, dropped / corpses * 100), corpses
end

--------------------------------------------------------------------------------
-- The guild's drops blended into a mob's loot table
--------------------------------------------------------------------------------
-- The owner, 2026-11-04: once a mob has the player's own MIN_KILLS, its loot
-- table's Drop Rate and Per Kill take the guild's corpses in beside the
-- player's, counted the same, for the items already on the player's table.
-- Nothing is saved and nothing of the player's is changed: LootTableUI reads
-- this and works the two columns out again.

GuildShare.dropsVersion = 0

--- The guild's records moved: the lookup by mob is laid out again when next asked.
function GuildShare:DropsChanged()
    self.dropsVersion = (self.dropsVersion or 0) + 1
end

--- The guild's records by mob name, laid out once a version.
function GuildShare:RecordsByMob()
    local drops = Drops()
    local kept = self.byMob
    if kept and kept.version == self.dropsVersion and kept.drops == drops then return kept.mobs end
    local mobs = {}
    for _, record in pairs(drops or {}) do
        if type(record) == "table" and type(record.mob) == "string"
            and type(record.corpses) == "number" and record.corpses > 0
            and type(record.items) == "table" then
            local list = mobs[record.mob]
            if not list then
                list = {}
                mobs[record.mob] = list
            end
            list[#list + 1] = record
        end
    end
    self.byMob = { version = self.dropsVersion, drops = drops, mobs = mobs }
    return mobs
end

--- The guild's loot off a loot table's mob: { kills, items = { [name] =
--- { corpses, count, counted } } }, or nil with sharing off or nothing
--- from the guild. `key` is the tally's: a name, or one zone's line of it
--- (Tracker.ZoneKey), which takes the guild's corpses in that zone only.
--- Items are put together by their random suffixes as the player's are
--- (Harvest:GroupedItems). `counted` is how many of the corpses said how
--- many they gave (`count`).
function GuildShare:LootFor(key)
    if not self:On() or type(key) ~= "string" then return nil end
    local Tracker, Harvest = ns.Tracker, ns.Harvest
    local name, zone = key, nil
    if Tracker and Tracker.SplitKey then name, zone = Tracker.SplitKey(key) end
    local list = self:RecordsByMob()[name]
    if not list then return nil end

    local kills, items = 0, {}
    for _, record in ipairs(list) do
        if not zone or record.zone == zone then
            kills = kills + record.corpses
            local grouped = Harvest and Harvest.GroupedItems and Harvest:GroupedItems(record) or record.items
            for itemName, entry in pairs(grouped) do
                local corpses = type(entry) == "table" and tonumber(entry.corpses) or 0
                corpses = math.min(corpses, record.corpses)
                if type(itemName) == "string" and corpses > 0 then
                    local into = items[itemName]
                    if not into then
                        into = { corpses = 0, count = 0, counted = 0 }
                        items[itemName] = into
                    end
                    into.corpses = into.corpses + corpses
                    local count = tonumber(entry.count)
                    if count and count > 0 then
                        into.count = into.count + count
                        into.counted = into.counted + corpses
                    end
                end
            end
        end
    end
    if kills <= 0 then return nil end
    return { kills = kills, items = items }
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

--- Start or stop to match the setting; Share:Apply calls it.
function GuildShare:Apply()
    if self:On() then
        if not self.ticker and type(C_Timer) == "table" then
            self.ticker = C_Timer.NewTicker(self.HELLO_SECONDS, function() GuildShare:Hello() end)
            C_Timer.After(self.FIRST_HELLO, function() GuildShare:Hello(true) end)
        end
    else
        if self.ticker then
            pcall(self.ticker.Cancel, self.ticker)
            self.ticker = nil
        end
        for _, state in pairs(self.byId) do
            state.online, state.queued = false, nil
        end
        self.queue, self.current = {}, nil
    end
    -- On, the guild's rows go in; off, they come out (the data is kept).
    self:Publish()
end

function GuildShare:SetOn(on)
    ns.db.shareGuild = on == true
    Share:Apply()
end

--- Delete everything taken from the guild, and turn it off. The player's
--- own counts were never touched, so nothing of theirs changes.
-- @return how many records were deleted
function GuildShare:Forget()
    local drops = Drops()
    local count = 0
    for _ in pairs(drops or {}) do count = count + 1 end
    self:SetOn(false)
    ns.db.guildDrops, ns.db.guildIn = {}, {}
    self.byId, self.bySender = {}, {}
    self:DropsChanged()
    self:Publish()
    return count
end

--- How many guildmates were heard this session, and drop records taken
--- from the guild in all.
function GuildShare:Counts()
    local heard = 0
    for _, state in pairs(self.byId) do
        if state.heardAt then heard = heard + 1 end
    end
    local records = 0
    for _ in pairs(Drops() or {}) do records = records + 1 end
    return heard, records
end

--- One line for Settings: how much came in from the guild, from how many
--- guildmates, and when the last did. From the save, so it reads the same
--- after a /reload.
function GuildShare:Status(now)
    if not self:On() then return L["Guild sharing is off."] end
    if not InGuild() then return L["You're not in a guild on this character."] end
    local mates, last = 0, nil
    for key, held in pairs(Ledgers()) do
        if type(key) == "string" and key:sub(1, 6) == "guild:" and type(held) == "table" and tonumber(held.at) then
            mates = mates + 1
            if not last or held.at > last then last = held.at end
        end
    end
    local mobs = Share.MobsIn(Drops())
    if mobs == 0 or mates == 0 then return L["Nothing from your guild yet. A guildmate needs this turned on too."] end
    return L.Format("Got drops for %s from %s.", ns.Util.Plural(mobs, L["mob"], L["mobs"]),
        ns.Util.Plural(mates, L["guildmate"], L["guildmates"]))
        .. " " .. L.Format("The last came in %s.", Share.Ago(last, now))
end

function GuildShare:Describe()
    if not self:On() then return L["Guild sharing is off."] end
    if not InGuild() then return L["Guild sharing is on, but this character is not in a guild."] end
    local heard, records = self:Counts()
    return L.Format("Guild sharing is on. Guildmates with Farmer heard this session: %d. Mobs with drops from your guild: %d.",
        heard, records)
end

function GuildShare:Command(text)
    local word, rest = (text or ""):match("^(%S*)%s*(.-)%s*$")
    word = (word or ""):lower()
    if word == "on" or word == "off" then
        self:SetOn(word == "on")
        ns.Print(word == "on" and L["sharing with your guild is on"] or L["sharing with your guild is off"])
    elseif word == "check" then
        ns.KeepCheck("guild check", GuildShare.Check, self)
    elseif word == "forget" then
        if (rest or ""):lower() ~= "confirm" then
            ns.Print(L["This deletes the drop rates your guild gave and turns guild sharing off. Your own kills and loot stay as they are. Type /farm share guild forget confirm to do it."])
            return
        end
        local count = self:Forget()
        ns.Print(L.Format("Deleted your guild's drops for %d mobs. Guild sharing is off.", count))
    else
        ns.Print(self:Describe())
    end
end

--- `/farm share guild check`: what guild sharing sees, for a report. Typed
--- only, kept as lastProbe. Says hello now too, so guildmates answer.
function GuildShare:Check()
    local function Line(...) ns.Print(string.format(...)) end
    Line("guild check: sharing %s, in a guild %s, listening %s, prefix %s",
        tostring(self:On()), tostring(InGuild()), tostring(Comm.listening == true), tostring(Comm.registered))
    local okCount, total, online = pcall(GetNumGuildMembers)
    if okCount then Line("guild members: %s, online %s", tostring(total), tostring(online)) end
    Line("my name reads %q, farmer id %s", tostring(Comm.PlayerName()), tostring(ns.Transfer:SourceId()))
    local ago = self.helloAt and (time() - self.helloAt) or nil
    Line("this session started %s s ago", tostring(self.enabledAt and (time() - self.enabledAt)))
    Line("hellos tried %d, sent %d, last %s s ago, building %s, timer set %s, last skip %s",
        self.helloTried or 0, self.helloSent or 0, tostring(ago), tostring(self.building == true),
        tostring(self.ticker ~= nil), tostring(self.helloSkipped))
    Line("addon messages sent %d, refused %d, retried %d, waiting %d, last refusal %s",
        Comm.sent or 0, Comm.refused or 0, Comm.retried or 0, #Comm.queue, tostring(Comm.lastRefusal))
    Line("Farmer messages heard in all: %d", Comm.received or 0)
    local any = false
    for _, entry in pairs(Comm.guildHeard) do
        any = true
        Line("heard on guild: %q, kinds %s, %d message(s), %d s ago",
            tostring(entry.name), entry.kinds, entry.count, time() - (entry.at or time()))
    end
    if not any then Line("heard on guild: nobody") end
    for sender, why in pairs(self.passed) do Line("hello not taken from %q: %s", sender, why) end
    for _, line in ipairs(self:WhisperLines()) do Line("%s", line) end
    for _, line in ipairs(self:MateLines()) do Line("%s", line) end
    if self:On() and InGuild() then
        self.helloAt = nil
        self:Hello(true)
        Line("a hello was just sent to your guild")
        -- And a whispered hello to each guildmate heard: their "A" back,
        -- in the 30 s lines, says whispers go both ways.
        local whispered = 0
        for _, state in pairs(self.byId) do
            if state.online and state.name then Share:Hello(state.name) whispered = whispered + 1 end
        end
        Line("a whispered hello went to %d guildmate(s)", whispered)
        self:FollowUp()
    end
end

GuildShare.FOLLOW_UP = 30   -- seconds the check waits before adding what came back

--- After the check's hello, add what happened next to the same saved
--- probe, so one check and a /reload a minute later tell the whole story.
function GuildShare:FollowUp()
    if type(C_Timer) ~= "table" then return end
    local sentBefore, heardBefore = Comm.sent or 0, Comm.received or 0
    C_Timer.After(self.FOLLOW_UP, function()
        -- The check is saved once it returns, so the probe is read now.
        local probe = type(ns.db) == "table" and ns.db.lastProbe
        if type(probe) ~= "table" or probe.check ~= "guild check" or type(probe.lines) ~= "table" then return end
        local function Add(...) probe.lines[#probe.lines + 1] = string.format(...) end
        Add("%d s later: hellos tried %d, sent %d, last skip %s", GuildShare.FOLLOW_UP,
            GuildShare.helloTried or 0, GuildShare.helloSent or 0, tostring(GuildShare.helloSkipped))
        Add("%d s later: addon messages sent %d more (refused %d, last refusal %s), heard %d more",
            GuildShare.FOLLOW_UP, (Comm.sent or 0) - sentBefore, Comm.refused or 0,
            tostring(Comm.lastRefusal), (Comm.received or 0) - heardBefore)
        local any = false
        for _, entry in pairs(Comm.guildHeard) do
            any = true
            Add("%d s later: heard on guild %q, kinds %s, %d message(s)", GuildShare.FOLLOW_UP,
                tostring(entry.name), entry.kinds, entry.count)
        end
        if not any then Add("%d s later: heard on guild: nobody", GuildShare.FOLLOW_UP) end
        for sender, why in pairs(GuildShare.passed) do
            Add("%d s later: hello not taken from %q: %s", GuildShare.FOLLOW_UP, sender, why)
        end
        for _, line in ipairs(GuildShare:WhisperLines()) do Add("%d s later: %s", GuildShare.FOLLOW_UP, line) end
        for _, line in ipairs(GuildShare:MateLines()) do Add("%d s later: %s", GuildShare.FOLLOW_UP, line) end
    end)
end

--- The check's lines on whispers: who was heard off the guild channel (the
--- name as the game gave it), and whose whispers no sharing knew.
function GuildShare:WhisperLines()
    local lines = {}
    for _, entry in pairs(Comm.otherHeard or {}) do
        lines[#lines + 1] = string.format("heard by %s: %q, kinds %s, %d message(s), %d s ago",
            tostring(entry.channel), tostring(entry.name), entry.kinds, entry.count, time() - (entry.at or time()))
    end
    if #lines == 0 then lines[1] = "heard by whisper: nobody" end
    for sender, count in pairs(Share.unmatched or {}) do
        lines[#lines + 1] = string.format("whispers not matched to anyone: %q, %d", sender, count)
    end
    return lines
end

--- The check's lines on each guildmate heard: where their sync stands.
function GuildShare:MateLines()
    local lines = {}
    for _, state in pairs(self.byId) do
        local held = Ledgers()[state.key]
        lines[#lines + 1] = string.format(
            "guildmate %q id %s, heard %s s ago, online %s, queued %s, syncing %s, last sync %s s ago, their manifest %s, records in %s, taken %s",
            tostring(state.name), tostring(state.id), tostring(state.heardAt and time() - state.heardAt),
            tostring(state.online == true), tostring(state.queued == true), tostring(self.current == state),
            tostring(state.syncedAt and time() - state.syncedAt),
            state.manifestIn and (state.manifestRefused or "in") or "none",
            tostring(state.lastRecordAt ~= nil), tostring(type(held) == "table"))
    end
    return lines
end

function GuildShare:OnEnable()
    self.enabledAt = time()
    Comm:On("G", function(...) GuildShare:OnHello(...) end)
    Comm:On("N", function(sender, body, channel) GuildShare:OnHello(sender, body, channel, true) end)
    -- Share:OnEnable ran first (the TOC's order) and called Apply before this
    -- module had its handler; this starts the hellos and shows the guild's
    -- rows if it is on.
    self:Apply()
end
