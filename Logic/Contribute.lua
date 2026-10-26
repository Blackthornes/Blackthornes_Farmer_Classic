-- Blackthornes Farmer -- Logic/Contribute.lua
-- Drop rates a player chooses to send to the addon's maker.
--
-- Asked 2026-10-15 by the owner: players who opt in send their own drop
-- records to his characters, so they can be folded into the shipped data at
-- the next release (tools/harvest_import.py --shared). Off by default:
-- one tick box on the About page of Settings (2026-10-17).
--
-- It is guild sharing's conversation (Logic/Share.lua), one way:
--   * A player with it ticked whispers a short hello ("Q<farmer id>:<hash>")
--     to each name in RECIPIENTS, soon after login and every five minutes.
--     Nothing in chat or Settings says whether anyone was there: the game's
--     "No player named ..." line is hidden (Comm.FilterNotFound), and the
--     names are never shown.
--   * Only the characters named in RECIPIENTS answer. They ask for what is
--     new ("H"), the sender sends its manifest and the records asked for.
--     The receiver never says what it has (`takeOnly`) and the sender never
--     asks for anything (`giveOnly`), so nothing flows back to the player.
--   * Only drop records go ("h"), and only the sender's own: what came from
--     another account, the guild or anyone else is never sent on.
--   * On the receiving side, the records are kept apart in `sharedDrops`,
--     with a ledger per sender in `sharedIn`, as guild drops are. They never
--     join the receiver's own kills, loot or drop records, and nothing in
--     the windows shows them. They are checked for being play
--     (GuildShare.Plausible), one sender is synced at a time, the next taken
--     as soon as one is done, each at most every SYNC_GAP, and at most
--     MAX_SENDERS are kept.
--   * When a sender's records finish coming in, one chat line says so, with
--     a sound and a note on screen (Alert).
--   * Only North American players send (InRegion), and only English
--     clients: records keep the client's mob and item names, and the
--     shipped data is in English.
--
-- Saved, account wide, never renamed: `shareDrops` (the player's choice),
-- `sharedDrops`, `sharedIn` and `sharedLog` (only on a receiving character's
-- account; the log is each finished share, for `/farm share drops log`).

local _, ns = ...
local L = ns.L

local Contribute = ns.NewModule("Contribute")

local Comm = ns.Comm
local Share = ns.Share

-- The characters drops are sent to, as Name-Realm. Kept only here, never
-- shown to players. This is the Classic Era copy: the owner's Era
-- characters (2026-10-26), never Forever's, so Era drops only ever reach
-- Era's shipped data. A whisper on Era only reaches the same realm, so a
-- name is used only by players on its realm (Recipients); anyone else has
-- nobody to send to, and the tick box in Settings is left out for them.
Contribute.RECIPIENTS = {
    "Blackthornes-Ashkandi",
    "Blacklock-Ashkandi",
}

-- Only players on this region send (the owner, 2026-10-17: North America),
-- since a whisper never crosses regions. GetCurrentRegion's 1 is the
-- Americas; a client that will not say sends nothing.
Contribute.REGIONS = { [1] = true }
Contribute.REGION_NAME = "US"

Contribute.HELLO_SECONDS = 300    -- a hello every five minutes (the owner, 2026-10-26)
Contribute.FIRST_HELLO = 30       -- and this long after login
Contribute.SYNC_GAP = 300         -- one sender synced at most this often
Contribute.SYNC_TIMEOUT = 180     -- a sync left this long is given up
Contribute.CONFIRM_AFTER = 30     -- quiet this long after records: compare again
Contribute.MAX_SENDERS = 200

Contribute.byId = {}       -- receiving: Farmer id -> state
Contribute.bySender = {}   -- receiving: name key -> state
Contribute.toState = {}    -- sending: recipient name key -> state
Contribute.queue = {}
Contribute.me = { key = "contribute-hello", name = "", sections = { h = true } }

local function ValidId(id)
    return type(id) == "string" and #id >= 6 and #id <= 16 and id:match("^%x+$") ~= nil
end

--- "Ana-Some Realm" -> "somerealm": a name's realm as two realms are
--- compared, or nil when it names none.
local function RealmKey(name)
    local realm = type(name) == "string" and name:match("%-(.+)$") or nil
    if not realm then return nil end
    realm = realm:gsub("[%s%-']", ""):lower()
    return realm ~= "" and realm or nil
end
Contribute.RealmKey = RealmKey

--- The realm of the character playing, as RealmKey gives it, or nil.
local function MyRealm()
    local ok, realm = pcall(function()
        local name = type(GetNormalizedRealmName) == "function" and GetNormalizedRealmName() or nil
        if (not name or name == "") and type(GetRealmName) == "function" then name = GetRealmName() end
        return name .. ""
    end)
    if not ok then return nil end
    return RealmKey("x-" .. realm)
end
Contribute.MyRealm = MyRealm

--- The recipients as { key, name }: only those on the realm of the character
--- playing (a name with no realm counts on any), since a whisper reaches no
--- other; with the realm not read, none that name one.
function Contribute:Recipients()
    local list, seen = {}, {}
    local here
    for _, name in ipairs(self.RECIPIENTS) do
        local key = type(name) == "string" and Comm.NameKey(name)
        local realm = key and RealmKey(name)
        if realm then
            here = here or MyRealm() or false
            if realm ~= here then key = nil end
        end
        if key and not seen[key] then
            seen[key] = true
            list[#list + 1] = { key = key, name = name }
        end
    end
    return list
end

--- True when the player has something to send to: names are listed.
function Contribute:HasRecipients()
    return #self:Recipients() > 0
end

--- The player chose to send their drops.
function Contribute:On()
    return ns.db ~= nil and ns.db.shareDrops == true
end

--- True when the character playing is one of the recipients, by its name
--- on its own realm.
function Contribute:Receiving()
    local mine = Comm.PlayerName and Comm.PlayerName()
    if type(mine) ~= "string" or mine == "" then return false end
    local key = Comm.NameKey(mine)
    for _, recipient in ipairs(self:Recipients()) do
        if recipient.key == key then return true end
    end
    return false
end

--- True when the game is on the region the recipients play on.
function Contribute:InRegion()
    if type(GetCurrentRegion) == "function" then
        local ok, region = pcall(GetCurrentRegion)
        if ok and type(region) == "number" then return self.REGIONS[region] == true end
    end
    if type(GetCurrentRegionName) == "function" then
        local ok, name = pcall(GetCurrentRegionName)
        if ok and type(name) == "string" then return name == self.REGION_NAME end
    end
    return false
end

--- Mob and item names are kept as the client gives them, so only an
--- English client's records can join the shipped data.
local function EnglishClient()
    return not (ns.Util and ns.Util.EnglishClient) or ns.Util.EnglishClient()
end

function Contribute:Sending()
    return self:On() and self:HasRecipients() and EnglishClient() and self:InRegion()
        and not self:Receiving()
end

--- Listening is needed while sending or receiving.
function Contribute:Active()
    return self:Sending() or self:Receiving()
end

--- The drops taken from players, as Harvest's records.
local function Drops(create)
    if type(ns.db) ~= "table" then return nil end
    if type(ns.db.sharedDrops) ~= "table" then
        if not create then return nil end
        ns.db.sharedDrops = {}
    end
    return ns.db.sharedDrops
end

--- What was heard from and taken from each sender.
local function Ledgers()
    if type(ns.db) ~= "table" then return {} end
    if type(ns.db.sharedIn) ~= "table" then ns.db.sharedIn = {} end
    return ns.db.sharedIn
end

function Contribute.LedgerKey(id)
    return "player:" .. id
end

local function Senders()
    local count = 0
    for _, held in pairs(Ledgers()) do
        if type(held) == "table" then count = count + 1 end
    end
    for _, state in pairs(Contribute.byId) do
        if type(Ledgers()[state.key]) ~= "table" then count = count + 1 end
    end
    return count
end

--------------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------------

--- Tell each recipient this Farmer has drops for them.
function Contribute:Hello()
    if not self:Sending() or self.building then return end
    self.building = true
    Share:Build(self.me, function(manifest)
        self.building = nil
        if not self:Sending() then return end
        local count = 0
        for _ in pairs(manifest.h or {}) do count = count + 1 end
        if count == 0 then return end
        local top = Comm.Hash(ns.Serialize.EncodeCanonical(manifest))
        local body = ns.Transfer:SourceId() .. ":" .. top
        for _, recipient in ipairs(self:Recipients()) do
            Comm:Send("Q", body, "WHISPER", recipient.name)
        end
    end)
end

--- The state a recipient's whisper is answered with, while sending.
local function GiveState(key, name)
    local state = Contribute.toState[key]
    if not state then
        state = { key = "give:" .. key, name = name, giveOnly = true, sections = { h = true } }
        Contribute.toState[key] = state
    end
    return state
end

--------------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------------

function Contribute:OnHello(sender, body, channel)
    if channel ~= "WHISPER" or not self:Receiving() or Comm.IsMe(sender) then return end
    local id, top = (body or ""):match("^(%x+):(%w+)$")
    if not ValidId(id) or #top > 12 then return end
    -- This account's own characters: their drops are already the player's.
    if id == ns.Transfer:SourceId() then return end
    local senderKey = Comm.NameKey(sender)
    if not senderKey then return end

    local state = self.byId[id]
    if not state then
        local key = Contribute.LedgerKey(id)
        if type(Ledgers()[key]) ~= "table" and Senders() >= self.MAX_SENDERS then return end
        state = {
            key = key, id = id, apart = true, takeOnly = true, owner = self,
            check = ns.GuildShare and ns.GuildShare.Plausible or nil,
            sections = { h = true },
            store = function(section, create) return section == "h" and Drops(create) or nil end,
            book = Ledgers,
        }
        self.byId[id] = state
    end

    if state.senderKey and state.senderKey ~= senderKey then self.bySender[state.senderKey] = nil end
    local other = self.bySender[senderKey]
    if other and other ~= state then other.senderKey = nil end
    state.name, state.senderKey = sender, senderKey
    self.bySender[senderKey] = state
    state.online, state.heardAt, state.top = true, time(), top

    local held = Ledgers()[state.key]
    if not (type(held) == "table" and held.top == top) then self:Want(state) end
end

function Contribute:Want(state)
    if state.queued or self.current == state then return end
    if state.syncedAt and time() - state.syncedAt < self.SYNC_GAP then return end
    state.queued = true
    self.queue[#self.queue + 1] = state
    C_Timer.After(2 + math.random() * 5, function() Contribute:Next() end)
end

--- One sender's sync is over: say what came in, once.
function Contribute:Finish(state)
    if self.current == state then self.current = nil end
    local taken = state.taken or 0
    state.taken = 0
    if taken > 0 then
        self:Note(state.name, taken)
        local line
        if taken == 1 then
            line = L.Format("Got drops for %d mob from %s.", taken, tostring(state.name))
        else
            line = L.Format("Got drops for %d mobs from %s.", taken, tostring(state.name))
        end
        ns.Print(line)
        self:Alert(line)
    end
end

--- A sound and a note on screen as the chat line goes out (the owner,
--- 2026-10-17). Only the receiving character ever gets here. The sound is
--- the addon's own rank-up chime; the note is OpenNote's frame.
Contribute.ALERT_HOLD = 6
Contribute.ALERT_ICON = [[Interface\Icons\Trade_Mining]]   -- Farmer's own icon

function Contribute:Alert(line)
    if ns.Tracker and ns.Tracker.PlayFile and ns.Tracker.SOUNDS then
        pcall(ns.Tracker.PlayFile, ns.Tracker.SOUNDS.rankup)
    end
    if ns.OpenNote and ns.OpenNote.Notice then
        pcall(ns.OpenNote.Notice, ns.OpenNote, line, self.ALERT_ICON, self.ALERT_HOLD)
    end
end

--- Each finished share, kept on the receiving account so it can be read
--- back with `/farm share drops log`. The newest LOG_KEEP are kept.
Contribute.LOG_KEEP = 100
Contribute.LOG_SHOW = 20

function Contribute:Note(name, taken)
    if type(ns.db) ~= "table" then return end
    if type(ns.db.sharedLog) ~= "table" then ns.db.sharedLog = {} end
    local log = ns.db.sharedLog
    log[#log + 1] = { at = time(), name = tostring(name), mobs = taken }
    while #log > self.LOG_KEEP do table.remove(log, 1) end
end

--- The shares kept, newest first, as lines for chat.
function Contribute:LogLines()
    local log = type(ns.db) == "table" and ns.db.sharedLog
    local lines = {}
    if type(log) ~= "table" then return lines end
    for i = #log, math.max(1, #log - self.LOG_SHOW + 1), -1 do
        local entry = log[i]
        if type(entry) == "table" then
            local ok, when = pcall(date, "%b %d %H:%M", tonumber(entry.at) or 0)
            when = ok and when or "?"
            local mobs = tonumber(entry.mobs) or 0
            if mobs == 1 then
                lines[#lines + 1] = L.Format("%s: drops for %d mob from %s.", when, mobs, tostring(entry.name))
            else
                lines[#lines + 1] = L.Format("%s: drops for %d mobs from %s.", when, mobs, tostring(entry.name))
            end
        end
    end
    return lines
end

function Contribute:PrintLog()
    local lines = self:LogLines()
    if #lines == 0 then
        ns.Print(L["Nobody has shared drops with you yet."])
        return
    end
    for _, line in ipairs(lines) do ns.Print(line) end
end

function Contribute:Next()
    if not self:Receiving() then return end
    local current = self.current
    if current then
        if current.online and time() - (current.syncStart or 0) < self.SYNC_TIMEOUT then return end
        self:Finish(current)
    end

    local state
    repeat
        state = table.remove(self.queue, 1)
        if state then state.queued = nil end
    until not state or state.online
    if not state then return end

    self.current, state.syncStart, state.syncedAt = state, time(), time()
    -- Ask for what is new: the sender answers with its manifest.
    Share:Hello(state.name)
    C_Timer.After(self.SYNC_TIMEOUT + 1, function() Contribute:Next() end)
end

--- Their manifest was compared with what is held. Nothing wanted: all in.
function Contribute:Compared(state, wanted)
    if wanted > 0 then return end
    local held = Ledgers()[state.key]
    if type(held) == "table" and state.top then held.top = state.top end
    if self.current == state then
        self:Finish(state)
        self:Next()
    end
end

--- Records came in. Once they stop, ask again, which also says whether
--- everything arrived.
function Contribute:Received(state, taken)
    state.taken = (state.taken or 0) + (taken or 0)
    state.lastRecordAt = time()
    if state.confirming then return end
    state.confirming = true
    local function Confirm()
        if time() - (state.lastRecordAt or 0) < self.CONFIRM_AFTER - 1 then
            C_Timer.After(self.CONFIRM_AFTER, Confirm)
            return
        end
        state.confirming = nil
        if self:Receiving() and state.online and self.current == state then Share:Hello(state.name) end
    end
    C_Timer.After(self.CONFIRM_AFTER, Confirm)
end

--------------------------------------------------------------------------------
-- Both sides
--------------------------------------------------------------------------------

--- A whisper's partner: a sender while receiving, a recipient while sending.
function Contribute:PartnerFor(sender)
    local key = Comm.NameKey(sender)
    if not key then return nil end
    if self:Receiving() then return self.bySender[key] end
    if self:Sending() then
        for _, recipient in ipairs(self:Recipients()) do
            if recipient.key == key then return GiveState(key, recipient.name) end
        end
    end
    return nil
end

function Contribute:OnOffline(key)
    local state = self.bySender[key]
    if state then
        state.online = false
        if self.current == state then
            self:Finish(state)
            self:Next()
        end
    end
    local give = self.toState[key]
    if give then give.online = false end
end

--- Start or stop to match the setting; Share:Apply calls it.
function Contribute:Apply()
    if self:Sending() then
        if not self.ticker and type(C_Timer) == "table" then
            self.ticker = C_Timer.NewTicker(self.HELLO_SECONDS, function() Contribute:Hello() end)
            C_Timer.After(self.FIRST_HELLO, function() Contribute:Hello() end)
        end
    elseif self.ticker then
        pcall(self.ticker.Cancel, self.ticker)
        self.ticker = nil
    end
    if not self:Receiving() then
        self.queue, self.current = {}, nil
    end
end

function Contribute:SetOn(on)
    ns.db.shareDrops = on == true
    Share:Apply()
end

function Contribute:Describe()
    if self:On() then return L["Sharing your drops with Blackthornes is on. Thank you."] end
    return L["Sharing your drops with Blackthornes is off."]
end

function Contribute:OnEnable()
    Comm:On("Q", function(...) Contribute:OnHello(...) end)
    -- Share:OnEnable ran first (the TOC's order); this starts the hellos.
    Share:Apply()
end
