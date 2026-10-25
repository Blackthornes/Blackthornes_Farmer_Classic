-- Blackthornes Farmer -- Logic/Share.lua
-- Kills, drop rates, gathering and fishing shared with your other account.
--
-- Asked 2026-10-11 (a viewer's question on stream, the owner agreeing): WoW
-- keeps each account's saved data apart, so Farmer on one account could not
-- see what Farmer on the other had measured. This is the same pairing as
-- Tradeskills' account link (Logic/AccountLink.lua): each side names a
-- character on the other account in Settings > Sharing, and while both are
-- logged in they whisper each other. Off until ticked and a name is typed.
--
-- What is shared is counts only: the loot harvest (corpses and what they
-- held), the lifetime kill tally, nodes gathered and spots fished. Not
-- goals, settings or positions.
--
-- How two accounts' counts add up without ever counting one twice:
--   * Each side sends only what it counted ITSELF: its totals less what it
--     has already taken from partners. So a count goes round no loop, and
--     with three accounts nothing is passed on.
--   * The other side adds only what is new since it last heard: for every
--     number it keeps the largest value seen from that partner
--     (`shareIn[partner].credit`), and adds the difference. A message heard
--     twice adds nothing the second time; a partner whose counts went down
--     (a reset) adds nothing until they pass what was already taken.
--   * Taken counts are merged into the ordinary tables, so Rankings, the
--     tooltip and the drop rates just work. They cannot be taken back out.
--
-- What keeps it safe, as in Tradeskills:
--   * Only whispers, only from a name this side typed, and only after that
--     side typed this one (a hello from anyone else gets no answer).
--   * Every field is whitelisted and checked for its type and size; strings
--     lose their "|" (no colour, link or texture codes from someone else).
--   * Nothing is run, and nothing is relayed.
--
-- Saved, account wide, never renamed: `shareData` (on or off), `shareNames`
-- (the other account's characters, full names, comma apart) and `shareIn`
-- (`[partner] = { name, hashes, credit }`: what was heard and taken).
--
-- Smooth play: the lists are cut into frame-sized slices, nothing runs in
-- combat, and what is sent goes out a batch at a time as the pacing allows.
--
-- Guildmates use the same conversation (Logic/GuildShare.lua): a state with
-- `guild` set comes from GuildShare:PartnerFor instead of the typed names,
-- and carries where its counts go instead of the player's own tables:
-- `sections` (the ones shared), `store(key, create)` and `book()` (ledgers).
-- Such a state also sets `apart` (its records keep the key they came with),
-- `id` (the Farmer its manifest must name) and `owner` (told Compared and
-- Received). Logic/Contribute.lua adds two more: `giveOnly` (this side
-- serves and never asks) and `takeOnly` (this side asks and never says
-- what it has).

local _, ns = ...
local L = ns.L

local Share = ns.NewModule("Share")

local Comm = ns.Comm
local Serialize = ns.Serialize
local Util = ns.Util

Share.CHECK_SECONDS = 600
-- Records worked per frame when lists are built, and sent per message.
Share.SLICE = 30
Share.BATCH = 5
-- The most one section's manifest lists, and the most records a partner may
-- have us holding for one section.
Share.MAX_MANIFEST = 2500
Share.MAX_HELD = 6000
Share.MAX_WANT = 3000

local MAX_STRING = 120
local MAX_MAP = 400
local MAX_NUMBER = 2 ^ 31

--------------------------------------------------------------------------------
-- What is shared
--------------------------------------------------------------------------------

local function Set(list)
    local set = {}
    for _, name in ipairs(list) do set[name] = true end
    return set
end

-- Each record's fields: strings and fill numbers are taken only when the
-- field is empty, `add` numbers are added, `min` and `max` widen. A map's
-- value is "count" (a number to add) or the spec of its entries.
local ITEM_DROP = { strings = Set { "name" }, add = Set { "count", "corpses" }, fill = Set { "id" } }
local ITEM_NODE = { add = Set { "gathers", "count" }, fill = Set { "id" } }
local ITEM_CAST = { add = Set { "casts", "count" }, fill = Set { "id" } }

local SECTIONS = {
    { key = "h", what = "drop rates", label = L["drop rates"],
      spec = { strings = Set { "mob", "zone", "location" }, add = Set { "corpses" },
               min = Set { "minLevel" }, max = Set { "maxLevel" }, fill = Set { "npc" },
               coords = true, maps = { items = ITEM_DROP } } },
    { key = "g", what = "gathering", label = L["gathering"],
      spec = { strings = Set { "zone", "location", "node", "kind" }, add = Set { "gathers" },
               coords = true, maps = { items = ITEM_NODE } } },
    { key = "f", what = "fishing", label = L["fishing"],
      spec = { strings = Set { "zone", "location", "school" }, add = Set { "casts" },
               min = Set { "minSkill" }, max = Set { "maxSkill" },
               coords = true, maps = { items = ITEM_CAST } } },
    { key = "k", what = "kills", label = L["kills"],
      spec = { add = Set { "kills", "copper", "coinKills" },
               maps = { items = "count", qty = "count", stacks = "count", places = "count" } } },
}
Share.SECTIONS = SECTIONS

local BY_KEY = {}
for _, section in ipairs(SECTIONS) do BY_KEY[section.key] = section end

--- The saved table a section lives in; made if `create`.
function Share.Store(key, create)
    local db = ns.db
    if type(db) ~= "table" then return nil end

    if key == "h" then
        local records = ns.Harvest and ns.Harvest.records
        if type(records) ~= "table" and create then records = {} end
        return records
    elseif key == "g" then
        if create and ns.Gathering then return ns.Gathering:Store() end
        return type(db.gathering) == "table" and db.gathering.nodes or nil
    elseif key == "f" then
        if create and ns.Fishing then return ns.Fishing:Store() end
        return type(db.fishing) == "table" and db.fishing.spots or nil
    elseif key == "k" then
        if create and ns.Tracker then return ns.Tracker:Store() end
        return type(db.tracker) == "table" and db.tracker.mobs or nil
    end
end

--- What a record's key must be, from its own fields: a record sent under any
--- other key is not taken, so nothing lands where the addon never looks.
local KEYS = {
    h = function(record) return record.mob and ("%s|%s|%s"):format(record.mob, record.zone or "?", record.location or "") end,
    g = function(record) return ("%s|%s|%s"):format(record.zone or "?", record.location or "", record.node or "?") end,
    f = function(record) return ("%s|%s|%s"):format(record.zone or "?", record.location or "", record.school or "") end,
    k = function(_, key) return key end,
}

--------------------------------------------------------------------------------
-- Checking what arrives
--------------------------------------------------------------------------------

local function CleanString(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("|", "")
    if value == "" or #value > MAX_STRING then return nil end
    return value
end

local function CleanNumber(value)
    if type(value) ~= "number" or value ~= value then return nil end
    if value < 0 or value > MAX_NUMBER then return nil end
    return value
end

local function CleanCoords(value)
    if type(value) ~= "table" then return nil end
    local x, y = value[1], value[2]
    if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then return nil end
    if math.abs(x) > 1e6 or math.abs(y) > 1e6 then return nil end
    return { x, y }
end

local function CleanRecord(spec, value)
    if type(value) ~= "table" then return nil end
    local out = {}

    for field in pairs(spec.strings or {}) do
        local text = CleanString(value[field])
        if text then out[field] = text end
    end
    for _, group in ipairs { spec.add or {}, spec.min or {}, spec.max or {}, spec.fill or {} } do
        for field in pairs(group) do
            local number = CleanNumber(value[field])
            if number then out[field] = number end
        end
    end
    if spec.coords then out.coords = CleanCoords(value.coords) end

    for field, sub in pairs(spec.maps or {}) do
        local map = value[field]
        if type(map) == "table" then
            local clean, count = {}, 0
            for name, entry in pairs(map) do
                local key = count < MAX_MAP and CleanString(name)
                if key then
                    local cleaned
                    if sub == "count" then cleaned = CleanNumber(entry) else cleaned = CleanRecord(sub, entry) end
                    if cleaned ~= nil then
                        clean[key] = cleaned
                        count = count + 1
                    end
                end
            end
            out[field] = clean
        end
    end
    return out
end
Share.CleanRecord = CleanRecord

--------------------------------------------------------------------------------
-- Taking a partner's counts
--------------------------------------------------------------------------------

--- Add what is new in `inn` (a checked record) to `own`, keeping in `credit`
--- the most of each number ever taken.
-- @return true when a count went up
local function Merge(spec, own, inn, credit)
    local added = false

    for field in pairs(spec.add or {}) do
        local value = inn[field]
        if value then
            local seen = credit[field] or 0
            if value > seen then
                own[field] = (tonumber(own[field]) or 0) + (value - seen)
                credit[field] = value
                added = true
            end
        end
    end
    for field in pairs(spec.min or {}) do
        if inn[field] then own[field] = math.min(tonumber(own[field]) or inn[field], inn[field]) end
    end
    for field in pairs(spec.max or {}) do
        if inn[field] then own[field] = math.max(tonumber(own[field]) or inn[field], inn[field]) end
    end
    for field in pairs(spec.fill or {}) do
        if own[field] == nil and inn[field] then own[field] = inn[field] end
    end
    for field in pairs(spec.strings or {}) do
        if own[field] == nil and inn[field] then own[field] = inn[field] end
    end
    if spec.coords and own.coords == nil and inn.coords then own.coords = inn.coords end

    for field, sub in pairs(spec.maps or {}) do
        local map = inn[field]
        if map then
            if type(own[field]) ~= "table" then own[field] = {} end
            if type(credit[field]) ~= "table" then credit[field] = {} end
            for name, entry in pairs(map) do
                if sub == "count" then
                    local seen = credit[field][name] or 0
                    if entry > seen then
                        own[field][name] = (tonumber(own[field][name]) or 0) + (entry - seen)
                        credit[field][name] = entry
                        added = true
                    end
                else
                    if type(own[field][name]) ~= "table" then
                        -- Every count starts at 0, as OwnRecord's do: a
                        -- 0 or missing count left it nil, and the next
                        -- loot's `entry.corpses + 1` raised.
                        local fresh = {}
                        for add in pairs(sub.add or {}) do fresh[add] = 0 end
                        own[field][name] = fresh
                    end
                    if type(credit[field][name]) ~= "table" then credit[field][name] = {} end
                    if Merge(sub, own[field][name], entry, credit[field][name]) then added = true end
                end
            end
        end
    end
    return added
end
Share.Merge = Merge

--- The record to take counts into, made if it is new. A kill tally goes
--- through the tracker, which sets a tally from before coin was counted
--- over kills aside first, so merged kills never skew an old average.
--- Two ledgers one partner holds for the same record (a mob kept as
--- "Creature #ID" and under its name, before and after a name was learned):
--- both are that partner's counts at two times, so the larger holds the
--- smaller. `hi` is the ledger to keep, `lo` what own counts took twice.
local function Combine(spec, a, b)
    local hi, lo = {}, {}
    for field in pairs(spec.add or {}) do
        local x, y = tonumber(a[field]), tonumber(b[field])
        if x and y then hi[field], lo[field] = math.max(x, y), math.min(x, y)
        else hi[field] = x or y end
    end
    for field, sub in pairs(spec.maps or {}) do
        local ma = type(a[field]) == "table" and a[field] or {}
        local mb = type(b[field]) == "table" and b[field] or {}
        if type(a[field]) == "table" or type(b[field]) == "table" then
            hi[field], lo[field] = {}, {}
            local names = {}
            for name in pairs(ma) do names[name] = true end
            for name in pairs(mb) do names[name] = true end
            for name in pairs(names) do
                local x, y = ma[name], mb[name]
                if sub == "count" then
                    x, y = tonumber(x), tonumber(y)
                    if x and y then hi[field][name], lo[field][name] = math.max(x, y), math.min(x, y)
                    else hi[field][name] = x or y end
                elseif type(x) == "table" and type(y) == "table" then
                    hi[field][name], lo[field][name] = Combine(sub, x, y)
                else
                    hi[field][name] = type(x) == "table" and x or y
                end
            end
        end
    end
    return hi, lo
end
Share.Combine = Combine

--- Takes `lo` (from Combine) back off a record's counts, never below 0.
local function Subtract(spec, own, lo)
    if type(own) ~= "table" or type(lo) ~= "table" then return end
    for field in pairs(spec.add or {}) do
        local value = tonumber(lo[field])
        if value and tonumber(own[field]) then own[field] = math.max(0, own[field] - value) end
    end
    for field, sub in pairs(spec.maps or {}) do
        local map, taken = own[field], lo[field]
        if type(map) == "table" and type(taken) == "table" then
            for name, value in pairs(taken) do
                if sub == "count" then
                    if tonumber(value) and tonumber(map[name]) then map[name] = math.max(0, map[name] - value) end
                else
                    Subtract(sub, map[name], value)
                end
            end
        end
    end
end
Share.Subtract = Subtract

--- A partner's or an import's record for a mob kept as "Creature #ID" goes
--- under the name this side knows for it, so it meets this side's own
--- record and ledger (Harvest:NameUnnamed moved those to the name). Left
--- under the old key, the same counts were taken a second time.
-- @return the key to keep it under, and the record
function Share.Canonical(sectionKey, key, record)
    local harvest = ns.Harvest
    if not (harvest and harvest.KnownNpcName) then return key, record end
    if sectionKey == "h" and harvest.Unnamed and harvest.Unnamed(record) then
        local npcID = tonumber(record.npc) or tonumber(record.mob:match("%d+"))
        local name = npcID and harvest.KnownNpcName(npcID)
        if type(name) == "string" and name ~= "" then
            record.mob = name
            record.npc = record.npc or npcID
            return KEYS.h(record), record
        end
    elseif sectionKey == "k" then
        local npcID = tonumber(key:match("^Creature #(%d+)$"))
        local name = npcID and harvest.KnownNpcName(npcID)
        if type(name) == "string" and name ~= "" then return name, record end
    end
    return key, record
end

local function OwnRecord(section, store, key, record)
    local own = store[key]
    if section.key == "k" and ns.Tracker then
        return ns.Tracker:GetMob(key)
    end
    if type(own) ~= "table" then
        own = {}
        for field in pairs(section.spec.strings or {}) do own[field] = record[field] end
        for field in pairs(section.spec.add or {}) do own[field] = 0 end
        for field in pairs(section.spec.maps or {}) do own[field] = {} end
        store[key] = own
    end
    return own
end

--------------------------------------------------------------------------------
-- What this side sends
--------------------------------------------------------------------------------

--- This side's own counts for one record: the totals less everything taken
--- from partners (`credits`, one per partner, any may be nil).
-- @return the record to send, and whether any count of it is this side's own
local function Export(spec, data, credits)
    local out, any = {}, false

    for _, group in ipairs { spec.strings or {}, spec.min or {}, spec.max or {}, spec.fill or {} } do
        for field in pairs(group) do
            if data[field] ~= nil then out[field] = data[field] end
        end
    end
    if spec.coords and type(data.coords) == "table" then
        out.coords = { data.coords[1], data.coords[2] }
    end

    for field in pairs(spec.add or {}) do
        local value = tonumber(data[field])
        if value then
            for _, credit in ipairs(credits) do value = value - (tonumber(credit[field]) or 0) end
            if value > 0 then out[field] = value any = true else out[field] = 0 end
        end
    end

    for field, sub in pairs(spec.maps or {}) do
        local map = data[field]
        if type(map) == "table" then
            local sent = {}
            for name, entry in pairs(map) do
                if type(name) == "string" then
                    if sub == "count" then
                        local value = tonumber(entry)
                        if value then
                            for _, credit in ipairs(credits) do
                                local taken = type(credit[field]) == "table" and tonumber(credit[field][name])
                                value = value - (taken or 0)
                            end
                            if value > 0 then sent[name] = value any = true end
                        end
                    elseif type(entry) == "table" then
                        local subs = {}
                        for _, credit in ipairs(credits) do
                            local held = type(credit[field]) == "table" and credit[field][name]
                            if type(held) == "table" then subs[#subs + 1] = held end
                        end
                        local record, subAny = Export(sub, entry, subs)
                        if subAny then sent[name] = record any = true end
                    end
                end
            end
            out[field] = sent
        end
    end
    return out, any
end
Share.Export = Export

--------------------------------------------------------------------------------
-- Partners
--------------------------------------------------------------------------------

Share.partners = {}   -- name key -> { name, online, heardAt, manifestAt, ... }

function Share:Enabled()
    return ns.db ~= nil and ns.db.shareData == true and #self:GetPartners() > 0
end

--- Sharing with the other account or with the guild, either.
function Share:Active()
    return self:Enabled() or (ns.GuildShare ~= nil and ns.GuildShare:Active())
        or (ns.Contribute ~= nil and ns.Contribute:Active())
end

--- The names typed in Settings, as { key = "ana smith", name = "Ana Smith" }.
--- A name also typed under Friends is a friend, never another account
--- (Logic/GuildShare.lua): their counts must not join the player's own.
function Share:GetPartners()
    local list, seen = {}, {}
    local text = ns.db and ns.db.shareNames
    if type(text) ~= "string" then return list end

    for part in text:gmatch("[^,;]+") do
        local name = part:gsub("^%s+", ""):gsub("%s+$", "")
        local key = Comm.NameKey(name)
        if key and not seen[key] and #name <= 48
            and not (ns.GuildShare and ns.GuildShare:IsFriend(name)) then
            seen[key] = true
            list[#list + 1] = { key = key, name = name }
        end
    end
    return list
end

--- The partner a sender is, or nil for anyone else.
function Share:PartnerFor(sender)
    local key = Comm.NameKey(sender)
    if not key or Comm.IsMe(sender) then return nil end
    if self:Enabled() then
        for _, partner in ipairs(self:GetPartners()) do
            if partner.key == key then
                local state = self.partners[key]
                if not state then
                    state = { name = partner.name, key = key }
                    self.partners[key] = state
                end
                state.name = partner.name
                return state
            end
        end
    end
    -- A guildmate heard on the guild channel (Logic/GuildShare.lua).
    local guildmate = ns.GuildShare and ns.GuildShare:PartnerFor(sender)
    if guildmate then return guildmate end
    -- Drops given to, or taken from, a player who opted in (Logic/Contribute.lua).
    return ns.Contribute and ns.Contribute:PartnerFor(sender) or nil
end

--- What was heard from and taken from a partner, made if new.
function Share:Held(state)
    -- A guildmate's ledger is kept apart (GuildShare.Book), as their counts are.
    local book = state.book and state.book()
    if not book then
        if type(ns.db.shareIn) ~= "table" then ns.db.shareIn = {} end
        book = ns.db.shareIn
    end
    local held = book[state.key]
    if type(held) ~= "table" then
        held = {}
        book[state.key] = held
    end
    held.name = state.name
    if type(held.hashes) ~= "table" then held.hashes = {} end
    if type(held.credit) ~= "table" then held.credit = {} end
    for _, section in ipairs(SECTIONS) do
        if type(held.hashes[section.key]) ~= "table" then held.hashes[section.key] = {} end
        if type(held.credit[section.key]) ~= "table" then held.credit[section.key] = {} end
    end
    return held
end

--- Every partner's taken counts for one record, to be left out of what is
--- sent. Includes partners no longer named: taken is taken.
local function CreditsFor(section, key)
    local list = {}
    for _, held in pairs(ns.db.shareIn or {}) do
        local taken = type(held) == "table" and type(held.credit) == "table"
            and type(held.credit[section.key]) == "table" and held.credit[section.key][key]
        if type(taken) == "table" then list[#list + 1] = taken end
    end
    -- What was gathered, skinned or caught with a Legacy perk stays here: it
    -- is noted in the record's own shape (Logic/Legacy.lua), so it comes off
    -- like anything taken.
    local store = Share.Store(section.key)
    local boosted = type(store) == "table" and type(store[key]) == "table" and store[key].boosted
    if type(boosted) == "table" then list[#list + 1] = boosted end
    return list
end

local function InCombat()
    local ok, inCombat = pcall(InCombatLockdown)
    return ok and inCombat == true
end

--- Work through `list` a few at a time, a frame apart, then call `done`.
-- Waits out combat.
local function Slices(list, each, done)
    local index = 1
    local function Step()
        if InCombat() then C_Timer.After(2, Step) return end
        local stop = math.min(#list, index + Share.SLICE - 1)
        while index <= stop do
            pcall(each, list[index])
            index = index + 1
        end
        if index <= #list then C_Timer.After(0, Step) else done() end
    end
    Step()
end

--- What is this side's own, as { [section] = { [short key] = short hash } },
--- with the full keys kept in `state.keys` to look records up again.
function Share:Build(state, done)
    if state.building then
        state.building[#state.building + 1] = done
        return
    end
    state.building = { done }

    local manifest, keys, jobs = {}, {}, {}
    for _, section in ipairs(SECTIONS) do
        manifest[section.key], keys[section.key] = {}, {}
        local store = (not state.sections or state.sections[section.key]) and Share.Store(section.key)
        if type(store) == "table" then
            for key in pairs(store) do
                if type(key) == "string" then jobs[#jobs + 1] = { section = section, key = key } end
            end
        end
    end

    local counts = {}
    Slices(jobs, function(job)
        local section, key = job.section, job.key
        local store = Share.Store(section.key)
        local data = store and store[key]
        if type(data) ~= "table" then return end
        if (counts[section.key] or 0) >= Share.MAX_MANIFEST then return end

        local out, any = Export(section.spec, data, CreditsFor(section, key))
        if not any then return end
        local short = Comm.Hash(key)
        manifest[section.key][short] = Comm.Hash(Serialize.EncodeCanonical(out))
        keys[section.key][short] = key
        counts[section.key] = (counts[section.key] or 0) + 1
    end, function()
        state.keys = keys
        local waiting = state.building
        state.building = nil
        for _, fn in ipairs(waiting) do pcall(fn, manifest) end
    end)
end

--------------------------------------------------------------------------------
-- The conversation
--------------------------------------------------------------------------------
-- H hello, A hello back: the other side is there and paired.
-- M (table) manifest: [section] = { [short key] = hash of its own counts }.
-- W (table) want: [section] = { short key, ... } whose hash differs from the
--   copy held.
-- C (table) records: { { s = section, k = key, h = hash, d = record }, ... }.

local function Whisper(kind, text, target)
    return Comm:Send(kind, text, "WHISPER", target)
end

function Share:Hello(name)
    Whisper("H", ns.VERSION or "", name)
end

function Share:SendManifest(state)
    -- A side that only takes never says what it has.
    if state.takeOnly then return end
    state.manifestAt = time()
    self:Build(state, function(manifest)
        -- Which Farmer this is, so a partner naming two characters of this
        -- account counts it once (Share:Identify).
        if ns.Transfer then manifest.i = ns.Transfer:SourceId() end
        if self:Active() then Comm:SendTable("M", manifest, "WHISPER", state.name) end
    end)
end

--- Say hello to every partner not yet heard from, and tell the ones who are
--- what this side has. Called now and then, and by Sync now.
function Share:Check()
    if not self:Enabled() then return end
    for _, partner in ipairs(self:GetPartners()) do
        local state = self.partners[partner.key] or { name = partner.name, key = partner.key }
        self.partners[partner.key] = state
        state.name = partner.name
        if state.online then
            -- Not on top of a transfer still going out: the partner asks
            -- again for whatever has not come.
            if Comm:Pending() == 0 and not (state.todo and #state.todo > 0) then
                self:SendManifest(state)
            end
        else
            self:Hello(partner.name)
        end
    end
end

--- Two characters of one account send the same saved data, so a partner is
--- the account, not the name: the first character heard from holds the
--- ledger, and a second one with the same Farmer id adds nothing. Naming a
--- character of this very account takes nothing either.
-- @return true when this partner's counts are to be taken
function Share:Identify(state, id)
    if type(id) ~= "string" or #id < 6 or #id > 16 or not id:match("^%x+$") then
        state.duplicate = nil
        return true
    end
    state.duplicate, state.sameAs = nil, nil
    if ns.Transfer and id == ns.Transfer:SourceId() then
        state.duplicate, state.sameAs = true, L["this account"]
        return false
    end
    -- A friend (Logic/GuildShare.lua) once typed as the other account still
    -- has that ledger; what they send now is kept apart, so it counts.
    for key, held in pairs(not state.friend and ns.db.shareIn or {}) do
        if key ~= state.key and type(held) == "table" and held.kind ~= "import" and held.account == id then
            state.duplicate, state.sameAs = true, held.name or key
            return false
        end
    end
    local held = self:Held(state)
    held.account = id
    return true
end

function Share:OnHello(sender, _, channel, isReply)
    if channel ~= "WHISPER" then return end
    local state = self:PartnerFor(sender)
    if not state then return end

    state.online, state.heardAt = true, time()
    if not isReply then Whisper("A", ns.VERSION or "", state.name) end
    self:SendManifest(state)
end

function Share:OnManifest(sender, manifest, channel)
    if channel ~= "WHISPER" then return end
    local state = self:PartnerFor(sender)
    if not state then return end
    state.online, state.heardAt = true, time()

    -- Either side's check syncs both ways: answered with this side's own,
    -- unless one went out a moment ago (which is what stops the two
    -- answering each other for ever).
    if not state.manifestAt or time() - state.manifestAt > 60 then self:SendManifest(state) end
    -- A side that only gives never asks for anything.
    if state.giveOnly then return end

    -- A guildmate's manifest must come from the Farmer its hello named.
    if state.id and manifest.i ~= state.id then return end
    if not self:Identify(state, manifest.i) then return end
    local held = self:Held(state)
    local want, total = {}, 0
    for _, section in ipairs(SECTIONS) do
        local listed = (not state.sections or state.sections[section.key])
            and type(manifest[section.key]) == "table" and manifest[section.key] or {}
        local mine = held.hashes[section.key]
        local asked = {}
        for short, hash in pairs(listed) do
            if type(short) == "string" and #short <= 12 and type(hash) == "string" and #hash <= 12
                and mine[short] ~= hash and total < Share.MAX_WANT then
                asked[#asked + 1] = short
                total = total + 1
            end
        end
        if #asked > 0 then want[section.key] = asked end
    end
    if total > 0 then Comm:SendTable("W", want, "WHISPER", state.name) end
    if state.owner then state.owner:Compared(state, total) end
end

function Share:OnWant(sender, want, channel)
    if channel ~= "WHISPER" then return end
    local state = self:PartnerFor(sender)
    if not state or state.takeOnly then return end

    local function Serve()
        local todo = {}
        for _, section in ipairs(SECTIONS) do
            local asked = (not state.sections or state.sections[section.key]) and want[section.key]
            local known = state.keys and state.keys[section.key]
            if type(asked) == "table" and known then
                for _, short in ipairs(asked) do
                    local key = type(short) == "string" and known[short]
                    if key and #todo < Share.MAX_WANT then todo[#todo + 1] = { section = section, key = key } end
                end
            end
        end
        state.todo = todo
        self:Serve(state)
    end

    if state.keys then Serve() else self:Build(state, Serve) end
end

--- Send what was asked for, a batch at a time as the pacing frees up.
function Share:Serve(state)
    if state.serving then return end
    state.serving = true

    local function Step()
        local todo = state.todo
        if not todo or #todo == 0 or not self:Active() then
            state.serving = false
            return
        end
        if Comm:Pending() > 12 or InCombat() then C_Timer.After(2, Step) return end

        local batch = {}
        while #todo > 0 and #batch < Share.BATCH do
            local job = table.remove(todo, 1)
            local store = Share.Store(job.section.key)
            local data = store and store[job.key]
            if type(data) == "table" then
                local out, any = Export(job.section.spec, data, CreditsFor(job.section, job.key))
                if any then
                    local hash = Comm.Hash(Serialize.EncodeCanonical(out))
                    batch[#batch + 1] = { s = job.section.key, k = job.key, h = hash, d = out }
                end
            end
        end
        if #batch > 0 then
            Comm:SendTable("C", batch, "WHISPER", state.name)
            state.sentAt = time()
        end
        C_Timer.After(0.5, Step)
    end
    Step()
end

--- Take one record a partner sent.
-- @return true, or nil and why it was refused
function Share:Accept(state, entry)
    if type(entry) ~= "table" then return nil, "not a record" end
    local section = type(entry.s) == "string" and BY_KEY[entry.s]
    if not section then return nil, "unknown kind" end
    if state.sections and not state.sections[section.key] then return nil, "not shared" end

    -- A record's key joins its fields with "|", so it keeps them; it must
    -- then be exactly what the record's own fields make (below).
    local key = type(entry.k) == "string" and #entry.k >= 1 and #entry.k <= 3 * MAX_STRING + 2 and entry.k or nil
    if key and section.key == "k" and key:find("|", 1, true) then key = nil end
    local hash = type(entry.h) == "string" and #entry.h <= 12 and entry.h or nil
    local record = CleanRecord(section.spec, entry.d)
    if not (key and hash and record) then return nil, "unreadable" end
    if KEYS[section.key](record, key) ~= key then return nil, "wrong key" end
    -- A guildmate's counts are checked for being play (GuildShare.Plausible).
    if state.check and not state.check(section, record) then return nil, "not plausible" end

    local store
    if state.store then store = state.store(section.key, true) else store = Share.Store(section.key, true) end
    if type(store) ~= "table" then return nil, "no saved data" end

    -- The hash stays under the key the partner sent, which their manifest
    -- names; the counts go under this side's name for the mob. A guildmate's
    -- records live apart (guildDrops) and keep the key they came with.
    local sentKey = key
    if not state.apart then key, record = Share.Canonical(section.key, key, record) end

    local held = self:Held(state)
    local credit = held.credit[section.key]
    if credit[key] == nil then
        local count = 0
        for _ in pairs(credit) do count = count + 1 end
        if count >= Share.MAX_HELD then return nil, "too many" end
    end
    if type(credit[key]) ~= "table" then credit[key] = {} end

    local own = OwnRecord(section, store, key, record)
    Merge(section.spec, own, record, credit[key])
    held.hashes[section.key][Comm.Hash(sentKey)] = hash
    held.at = time()
    return true
end

function Share:OnRecords(sender, batch, channel)
    if channel ~= "WHISPER" then return end
    local state = self:PartnerFor(sender)
    if not state or state.duplicate or state.giveOnly then return end

    local taken = 0
    for index, entry in ipairs(batch) do
        if index > Share.BATCH * 4 then break end
        local ok, why = self:Accept(state, entry)
        if ok then taken = taken + 1 else ns.Debug("share: a record from", tostring(sender), "was not taken:", tostring(why)) end
    end
    if taken > 0 then
        state.receivedAt = time()
        self.taken = (self.taken or 0) + taken
        -- A guildmate's counts are not the player's: only the guild's rates
        -- in the database move (GuildShare:Received).
        if state.owner then state.owner:Received(state, taken) else self:Changed() end
    end
end

--- Windows showing counts catch up, once after a burst of records.
function Share:Changed()
    if self.refreshing then return end
    self.refreshing = true
    C_Timer.After(1, function()
        self.refreshing = nil
        -- What the arrow's places were made from moved too (Arrow:Sources).
        if ns.Harvest then ns.Harvest.changes = (ns.Harvest.changes or 0) + 1 end
        if ns.TrackerUI and ns.TrackerUI.Refresh then pcall(ns.TrackerUI.Refresh, ns.TrackerUI) end
        if ns.UI and ns.UI.RefreshActive then pcall(ns.UI.RefreshActive, ns.UI) end
        if ns.SettingsUI and ns.SettingsUI.ShareStatusChanged then pcall(ns.SettingsUI.ShareStatusChanged, ns.SettingsUI) end
    end)
end

--- The pieces Logic/Transfer.lua (a string handed to someone else) shares
--- with this file, so a record is checked and merged the same way both ways.
Share.Parts = {
    SECTIONS = SECTIONS, BY_KEY = BY_KEY, KEYS = KEYS, MAX_STRING = MAX_STRING,
    CreditsFor = CreditsFor, OwnRecord = OwnRecord, InCombat = InCombat,
    CleanRecord = CleanRecord,
}

--- A section's records were reset (a typed reset confirm): what was taken
--- into them from another account or an import is gone with them, so their
--- ledgers for it are emptied too. Kept, a later Remove of an import took the
--- old amount off the player's own new counts, and export left those new
--- counts out until they passed the old credit. The guild's ledgers
--- (guildIn) keep their own records apart and are not touched.
function Share:ForgetSection(sectionKey)
    local book = ns.db and ns.db.shareIn
    if type(book) ~= "table" or not BY_KEY[sectionKey] then return end
    for _, held in pairs(book) do
        if type(held) == "table" then
            if type(held.credit) == "table" then held.credit[sectionKey] = {} end
            if type(held.hashes) == "table" then held.hashes[sectionKey] = {} end
        end
    end
end

function Share:OnOffline(key)
    local state = self.partners[key]
    if state then state.online = false end
    if ns.GuildShare then ns.GuildShare:OnOffline(key) end
    if ns.Contribute then ns.Contribute:OnOffline(key) end
end

--------------------------------------------------------------------------------
-- Status, for Settings and /farm share
--------------------------------------------------------------------------------

--- How many records each partner's counts are held in: { [section] = n }.
function Share:CountTaken(key)
    local held = ns.db and ns.db.shareIn and ns.db.shareIn[key]
    local counts, total = {}, 0
    if type(held) == "table" and type(held.credit) == "table" then
        for _, section in ipairs(SECTIONS) do
            local n = 0
            for _ in pairs(type(held.credit[section.key]) == "table" and held.credit[section.key] or {}) do n = n + 1 end
            counts[section.key] = n
            total = total + n
        end
    end
    return total, counts
end

--- "just now", "12 min ago", "2 hours ago", "yesterday", "3 days ago".
function Share.Ago(when, now)
    when, now = tonumber(when), tonumber(now or time())
    if not (when and now) then return nil end
    local seconds = math.max(0, now - when)
    if seconds < 60 then return L["just now"] end
    if seconds < 3600 then return L.Format("%d min ago", math.floor(seconds / 60)) end
    if seconds < 7200 then return L["an hour ago"] end
    if seconds < 86400 then return L.Format("%d hours ago", math.floor(seconds / 3600)) end
    local days = math.floor(seconds / 86400)
    return days == 1 and L["yesterday"] or L.Format("%d days ago", days)
end

--- How many mobs drop records are held for, from the keys of a credit or
--- record table (mob|zone|location).
function Share.MobsIn(records)
    local mobs, count = {}, 0
    for key in pairs(type(records) == "table" and records or {}) do
        local mob = type(key) == "string" and key:match("^(.-)|") or key
        if mob and not mobs[mob] then mobs[mob] = true; count = count + 1 end
    end
    return count
end

--- One line for Settings, under the names typed: what came in, from whom
--- and when. Empty while nothing has.
function Share:Status(now)
    if not ns.db then return "" end
    if ns.db.shareData ~= true then return L["Sharing is off."] end
    local partners = self:GetPartners()
    if #partners == 0 then return L["Sharing is on, but you haven't named a character on your other account yet."] end
    local best
    for _, partner in ipairs(partners) do
        local held = type(ns.db.shareIn) == "table" and ns.db.shareIn[partner.key]
        if type(held) == "table" and tonumber(held.at) and (not best or held.at > best.at) then
            best = { at = held.at, name = held.name or partner.name,
                mobs = Share.MobsIn(type(held.credit) == "table" and held.credit.h) }
        end
    end
    if not best or best.mobs == 0 then return "" end
    return L.Format("Got drops for %s from %s.", Util.Plural(best.mobs, L["mob"], L["mobs"]), best.name)
        .. " " .. L.Format("The last came in %s.", Share.Ago(best.at, now))
end

function Share:Describe()
    if not ns.db then return "" end
    local partners = self:GetPartners()
    if ns.db.shareData ~= true then return L["Sharing is off."] end
    if #partners == 0 then return L["Sharing is on, but you haven't named a character on your other account yet."] end

    local parts = {}
    for _, partner in ipairs(partners) do
        local state = self.partners[partner.key] or {}
        local total = self:CountTaken(partner.key)
        if state.duplicate then
            parts[#parts + 1] = L.Format("%s: the same account as %s, so nothing is counted twice",
                partner.name, tostring(state.sameAs))
        else
            local heard = state.online and L["online"] or L["not heard from this session"]
            if total == 1 then
                parts[#parts + 1] = L.Format("%s: %s, %d entry taken in", partner.name, heard, total)
            else
                parts[#parts + 1] = L.Format("%s: %s, %d entries taken in", partner.name, heard, total)
            end
        end
    end
    local pending = Comm:Pending()
    if pending > 0 then
        if pending == 1 then
            parts[#parts + 1] = L.Format("%d message waiting to go", pending)
        else
            parts[#parts + 1] = L.Format("%d messages waiting to go", pending)
        end
    end
    return table.concat(parts, ".  ") .. "."
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

--- Start or stop listening to match the settings.
function Share:Apply()
    if self:Active() then Comm:Start() else Comm:Stop() end
    if self:Enabled() then
        if not self.started then
            self.started = true
            C_Timer.After(20, function() Share:Check() end)
        end
    else
        for _, state in pairs(self.partners) do state.online = false end
    end
    if ns.GuildShare then ns.GuildShare:Apply() end
    if ns.Contribute then ns.Contribute:Apply() end
end

function Share:SetEnabled(on)
    ns.db.shareData = on == true
    self:Apply()
    if on then self:Check() end
end

function Share:SetNames(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    ns.db.shareNames = text
    self:Apply()
    self:Check()
end

function Share:OnEnable()
    Comm:On("H", function(sender, body, channel) Share:OnHello(sender, body, channel, false) end)
    Comm:On("A", function(sender, body, channel) Share:OnHello(sender, body, channel, true) end)
    Comm:OnTable("M", function(...) Share:OnManifest(...) end)
    Comm:OnTable("W", function(...) Share:OnWant(...) end)
    Comm:OnTable("C", function(...) Share:OnRecords(...) end)
    Comm.onOffline = function(key) Share:OnOffline(key) end

    self:Apply()
    -- Now and then; nothing happens while sharing is off.
    self.ticker = C_Timer.NewTicker(self.CHECK_SECONDS, function() Share:Check() end)
end

ns.RegisterCommand("share", L["share kills, drop rates and gathering with your other account or guild: on, off, with <names>, sync, guild on|off, drops on|off"],
    function(args)
        local word, rest = (args or ""):match("^(%S*)%s*(.-)%s*$")
        word = (word or ""):lower()

        if word == "on" or word == "off" then
            Share:SetEnabled(word == "on")
            ns.Print(word == "on" and L["sharing with your other account is on"] or L["sharing with your other account is off"])
        elseif word == "with" then
            Share:SetNames(rest)
            ns.Print(rest ~= "" and L.Format("sharing with: %s", rest) or L["you haven't named anyone to share with"])
        elseif word == "sync" then
            Share:Check()
            ns.Print(Share:Enabled() and L["asked your other account for anything new"] or L["sharing is off, or you haven't named a character yet"])
        elseif word == "guild" then
            ns.GuildShare:Command(rest)
        elseif word == "drops" then
            local choice = (rest or ""):lower()
            if choice == "log" then return ns.Contribute:PrintLog() end
            if choice == "on" or choice == "off" then ns.Contribute:SetOn(choice == "on") end
            ns.Print(ns.Contribute:Describe())
        else
            ns.Print(Share:Describe())
            ns.Print(ns.GuildShare:Describe())
        end
    end)
