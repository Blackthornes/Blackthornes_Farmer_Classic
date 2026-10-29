local _, ns = ...

--------------------------------------------------------------------------------
-- What a camp on the Grind tab earns in an hour, from your own play there
--
-- A player farms an area, not one mob: a good mob shares its spawns with a
-- weak one, and herbs grow between them (the owner, 2026-10-29). So a camp's
-- hour is worked out from what you did there:
--
--   * the kills you made in the camp's subzone (each mob's `places` in the
--     kill tally), each mob worth what your own kills of it gave
--     (Value:FromTally, never the database's or the guild's rates), at your
--     own kill pace for it (Stats:SecondsPerKill);
--   * the coin those kills dropped;
--   * the herbs and ore you gathered in the same subzone (gathering.nodes),
--     worth what yours gave, at your own pace for that node in the zone
--     (gathering.pace, once GrindGather.MIN_SECONDS are behind it).
--
-- Everything is summed over the time it took, so a camp where you kill two
-- dogs for every cat earns what that mix earns. Under Tracker.MIN_KILLS of
-- your kills in a camp it says nothing yet.
--
-- Nothing is saved. A camp's answer is kept until kills, gathers or the
-- hide list move, or KEEP seconds pass (prices drift); camps with enough
-- kills are worked out BUDGET a frame, only when the Grind tab asks.
--------------------------------------------------------------------------------

local L = ns.L

local CampWorth = ns.NewModule("CampWorth")

-- Camps worked out a frame.
CampWorth.BUDGET = 3
-- Seconds an answer is kept before prices are read again.
CampWorth.KEEP = 120

CampWorth.results = {}
CampWorth.queue = {}
CampWorth.queued = {}

local function Clock()
    if type(GetTime) == "function" then
        local ok, now = pcall(GetTime)
        if ok and type(now) == "number" then return now end
    end
    return type(time) == "function" and time() or 0
end

local function English(zone)
    local Spots = ns.Spots
    if Spots and Spots.English then
        local ok, name = pcall(Spots.English, zone)
        if ok and type(name) == "string" then return name end
    end
    return zone
end

--- The key a camp, a kill's place and a gathered node share: the zone in
--- English and the subzone in lower case. Nil without a subzone.
function CampWorth.Key(zone, location)
    if type(zone) ~= "string" or type(location) ~= "string" or location == "" then return nil end
    return ("%s|%s"):format(English(zone), location:lower())
end

--- A kill's place ("The Sepulcher, Silverpine Forest") as its subzone and
--- zone; nil for a place that is a zone alone.
function CampWorth.SplitPlace(place)
    if type(place) ~= "string" then return nil end
    return place:match("^(.+), ([^,]+)$")
end

--- What moves the answers: a kill, a gather, the hide list, or the clock.
local function Stamp()
    local Stats, Harvest, GrindGather, DB = ns.Stats, ns.Harvest, ns.GrindGather, ns.DB
    return ("%s:%s:%s:%s:%d"):format(Stats and Stats.version or 0, Harvest and Harvest.changes or 0,
        GrindGather and GrindGather.paceVersion or 0, DB and DB.hiddenVersion or 0,
        math.floor(Clock() / CampWorth.KEEP))
end

local function Hidden(name)
    local DB = ns.DB
    if not (DB and DB.IsHiddenSource) then return false end
    local ok, hidden = pcall(DB.IsHiddenSource, DB, name)
    return ok and hidden == true
end

--- Your kills and gathers by camp key, laid out once a stamp:
--- { kills = { [key] = { total, mobs = { [name] = kills }, zones = { [name] = client zone } } },
---   gathers = { [key] = { { node, kind, picks, items, zone } } } }.
function CampWorth:Index()
    local stamp = Stamp()
    if self.index and self.indexStamp == stamp then return self.index end

    local kills, gathers = {}, {}
    local Tracker = ns.Tracker
    local store = Tracker and Tracker:Store() or {}
    for name, mob in pairs(store) do
        if type(name) == "string" and type(mob) == "table" and type(mob.places) == "table"
            and not Hidden(name) then
            for place, count in pairs(mob.places) do
                count = tonumber(count) or 0
                local location, zone = CampWorth.SplitPlace(place)
                local key = count > 0 and CampWorth.Key(zone, location)
                if key then
                    local entry = kills[key]
                    if not entry then
                        entry = { total = 0, mobs = {}, zones = {} }
                        kills[key] = entry
                    end
                    entry.total = entry.total + count
                    entry.mobs[name] = (entry.mobs[name] or 0) + count
                    entry.zones[name] = zone
                end
            end
        end
    end

    local db = ns.db
    local nodes = type(db) == "table" and type(db.gathering) == "table" and db.gathering.nodes
    for _, node in pairs(type(nodes) == "table" and nodes or {}) do
        if type(node) == "table" and (node.kind == "herb" or node.kind == "ore")
            and type(node.node) == "string" and not Hidden(node.node) then
            local key = CampWorth.Key(node.zone, node.location)
            local picks = tonumber(node.gathers) or 0
            if key and picks > 0 then
                local list = gathers[key] or {}
                gathers[key] = list
                local found
                for _, each in ipairs(list) do
                    if each.node == node.node then found = each end
                end
                if not found then
                    found = { node = node.node, kind = node.kind, picks = 0, items = {}, zone = English(node.zone) }
                    list[#list + 1] = found
                end
                found.picks = found.picks + picks
                for item, entry in pairs(type(node.items) == "table" and node.items or {}) do
                    local count = type(entry) == "table" and tonumber(entry.count) or tonumber(entry) or 0
                    local have = found.items[item] or { count = 0 }
                    have.count = have.count + count
                    if type(entry) == "table" and entry.id then have.id = entry.id end
                    found.items[item] = have
                end
            end
        end
    end
    for _, list in pairs(gathers) do
        table.sort(list, function(a, b)
            if a.picks ~= b.picks then return a.picks > b.picks end
            return a.node < b.node
        end)
    end

    self.index = { kills = kills, gathers = gathers }
    self.indexStamp = stamp
    return self.index
end

--- A camp's own kills and gathers, at once and cheaply: { total, mobs =
--- { [name] = kills } } and the gathered nodes list. An unnamed camp has
--- none: kills are kept by subzone.
function CampWorth:Kills(camp)
    local key = type(camp) == "table" and CampWorth.Key(camp.zone, camp.location)
    local index = self:Index()
    local entry = key and index.kills[key]
    return entry or { total = 0, mobs = {}, zones = {} }, key and index.gathers[key] or {}
end

local function MaybeNumber(value)
    return type(value) == "number" and value == value and value or nil
end

--- How long a gather of `node` in `zone` takes you, or nil before
--- MIN_SECONDS of gathering it are counted.
local function SecondsPerGather(zone, node)
    local GrindGather = ns.GrindGather
    if not GrindGather then return nil end
    local ok, store = pcall(GrindGather.PaceStore, GrindGather)
    local pace = ok and type(store) == "table" and store[GrindGather.Key(zone, node)]
    if type(pace) ~= "table" then return nil end
    local seconds, picks = tonumber(pace.seconds) or 0, tonumber(pace.gathers) or 0
    if seconds < GrindGather.MIN_SECONDS or picks <= 0 then return nil end
    return seconds / picks
end

--- Work one camp out. Returns { ready, kills, perHour, lines, coin, herbs,
--- hours, mix }; `ready` false under MIN_KILLS of your kills, or when no
--- mob there has a worth and a pace of yours yet.
function CampWorth:Work(camp)
    local entry, gathered = self:Kills(camp)
    local result = { ready = false, kills = entry.total, herbs = {} }
    for _, gather in ipairs(gathered) do
        result.herbs[#result.herbs + 1] = { node = gather.node, kind = gather.kind, picks = gather.picks }
    end
    local Tracker, Value, Stats = ns.Tracker, ns.Value, ns.Stats
    if entry.total < Tracker.MIN_KILLS or not (Value and Stats) then return result end

    local seconds, timed = 0, 0
    local lines, coin = {}, 0
    for name, kills in pairs(entry.mobs) do
        local okPace, pace = pcall(Stats.SecondsPerKill, Stats, name)
        pace = okPace and MaybeNumber(pace) or nil
        if pace then timed = timed + kills * pace end
        local key = Tracker:KeyFor(name, entry.zones[name])
        local ok, total, details = pcall(Value.FromTally, Value, key)
        total = ok and MaybeNumber(total) or nil
        if total and pace then
            local perCoin = type(details) == "table" and MaybeNumber(details.coin) or 0
            lines[#lines + 1] = { name = name, kills = kills, copper = kills * (total - perCoin) }
            coin = coin + kills * perCoin
            seconds = seconds + kills * pace
        end
    end
    if #lines == 0 then return result end

    for index, gather in ipairs(gathered) do
        local each = SecondsPerGather(gather.zone, gather.node)
        local ok, copper, priced = pcall(ns.GrindGather.Worth, gather.items)
        if each and ok and priced and type(copper) == "number" then
            result.herbs[index].copper = copper
            seconds = seconds + gather.picks * each
        end
        if each then timed = timed + gather.picks * each end
    end
    if seconds <= 0 then return result end

    local scale = 3600 / seconds
    local perHour = 0
    for _, line in ipairs(lines) do
        line.perHour = line.copper * scale
        perHour = perHour + line.perHour
    end
    table.sort(lines, function(a, b)
        if a.perHour ~= b.perHour then return a.perHour > b.perHour end
        return a.name < b.name
    end)
    result.coin = coin * scale
    perHour = perHour + result.coin
    for _, herb in ipairs(result.herbs) do
        if herb.copper then
            herb.perHour = herb.copper * scale
            perHour = perHour + herb.perHour
        end
    end

    result.ready = true
    result.lines = lines
    result.perHour = math.floor(perHour + 0.5)
    result.hours = timed / 3600
    result.mix = CampWorth.MixText(entry.mobs)
    return result
end

--- The camp's answer, or nil while it is being worked out (it is then
--- queued). An older answer is given while a newer one is worked out, so a
--- band never blinks.
function CampWorth:For(camp)
    local key = type(camp) == "table" and CampWorth.Key(camp.zone, camp.location)
    if not key then return { ready = false, kills = 0, herbs = {} } end
    local stamp = Stamp()
    local kept = self.results[key]
    if kept and kept.stamp == stamp then return kept.result end

    local entry = self:Kills(camp)
    if entry.total < ns.Tracker.MIN_KILLS then
        -- Too few kills: nothing to price, so no need to wait a frame.
        local result = self:Work(camp)
        self.results[key] = { stamp = stamp, result = result }
        return result
    end

    if not self.queued[key] then
        self.queued[key] = true
        self.queue[#self.queue + 1] = camp
        if not self.worker and type(CreateFrame) == "function" then
            self.worker = CreateFrame("Frame")
            self.worker:SetScript("OnUpdate", function() CampWorth:Step(CampWorth.BUDGET) end)
        end
        if self.worker then self.worker:Show() end
    end
    return kept and kept.result or nil
end

--- A camp's gold an hour once known, else nil (and it is queued).
function CampWorth:Known(camp)
    local result = self:For(camp)
    return result and result.ready and result.perHour or nil
end

--- Work out up to `budget` queued camps; once none are left, tell the
--- Grind tab (onDone) when anything new came in.
function CampWorth:Step(budget)
    local stamp = Stamp()
    while #self.queue > 0 and budget > 0 do
        local camp = table.remove(self.queue, 1)
        local key = CampWorth.Key(camp.zone, camp.location)
        self.queued[key] = nil
        budget = budget - 1
        local ok, result = pcall(self.Work, self, camp)
        if ok and type(result) == "table" then
            self.results[key] = { stamp = stamp, result = result }
            self.fresh = true
        elseif ns.Debug then
            ns.Debug("camp worth: " .. tostring(result))
        end
    end
    if #self.queue == 0 then
        if self.worker then self.worker:Hide() end
        if self.fresh then
            self.fresh = nil
            if self.onDone then pcall(self.onDone) end
        end
    end
end

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

local IRREGULAR = { wolf = "wolves", thief = "thieves", elf = "elves", dwarf = "dwarves",
    mouse = "mice", sheep = "sheep", deer = "deer", fish = "fish" }

--- More than one of a mob, in words: "Mottled Boars" on an English client.
--- Other clients keep the name, since their plurals can't be guessed.
function CampWorth.Plural(name)
    if type(name) ~= "string" or name == "" then return name end
    local Util = ns.Util
    if Util and Util.EnglishClient and not Util.EnglishClient() then return name end
    local head, last = name:match("^(.-)(%S+)$")
    local lower = last:lower()
    local word
    if IRREGULAR[lower] then
        word = IRREGULAR[lower]
        if last:sub(1, 1):match("%u") then word = word:sub(1, 1):upper() .. word:sub(2) end
    elseif lower:match("man$") then
        word = last:sub(1, -3) .. "en"
    elseif lower:match("[^aeiou]y$") then
        word = last:sub(1, -2) .. "ies"
    elseif lower:match("[sxz]$") or lower:match("[cs]h$") then
        word = last .. "es"
    else
        word = last .. "s"
    end
    return head .. word
end

--- How you split your kills between the two mobs you kill most there:
--- "You kill about 2 Mottled Boars for every Swoop." Nil for one mob.
function CampWorth.MixText(mobs)
    local list = {}
    for name, kills in pairs(mobs or {}) do list[#list + 1] = { name = name, kills = kills } end
    if #list < 2 then return nil end
    table.sort(list, function(a, b)
        if a.kills ~= b.kills then return a.kills > b.kills end
        return a.name < b.name
    end)
    local first, second = list[1], list[2]
    if second.kills <= 0 then return nil end
    local ratio = math.floor(first.kills / second.kills + 0.5)
    if ratio >= 2 then
        return L.Format("You kill about %d %s for every %s.", ratio, CampWorth.Plural(first.name), second.name)
    end
    return L.Format("You kill about as many %s as %s.", CampWorth.Plural(first.name), CampWorth.Plural(second.name))
end

local COMMA = { deDE = true, frFR = true, esES = true, esMX = true, ruRU = true }

--- How long your play there took, in words.
function CampWorth.HoursText(hours)
    hours = tonumber(hours) or 0
    if hours < 1 then
        return L.Format("From your %d minutes here.", math.max(1, math.floor(hours * 60 + 0.5)))
    end
    local rounded = math.floor(hours * 10 + 0.5) / 10
    if rounded == 1 then return L["From your 1 hour here."] end
    local text = (rounded == math.floor(rounded)) and ("%d"):format(rounded) or ("%.1f"):format(rounded)
    local ok, locale = pcall(function() return type(GetLocale) == "function" and GetLocale() end)
    if ok and COMMA[locale or ""] then text = text:gsub("%.", ",") end
    return L.Format("From your %s hours here.", text)
end

--- The camp band's words: "This camp: 1g 20s an hour", "Farm here a
--- while to see", or "" while it is being worked out.
function CampWorth.BandText(result)
    if result == nil then return "", nil end
    if result.ready then
        return L.Format("This camp: %s an hour", ns.Value.Coins(result.perHour)), "muted"
    end
    return L["Farm here a while to see"], "muted"
end

--- A mob's YOUR KILLS: "88 (35%)", "7/20" (short of MIN_KILLS) or "" for
--- none. Second value: true when short.
function CampWorth.KillsText(kills, total)
    kills = tonumber(kills) or 0
    if kills <= 0 then return "", false end
    local need = ns.Tracker.MIN_KILLS
    if kills < need then return ("%d/%d"):format(kills, need), true end
    local share = total and total > 0 and math.floor(kills / total * 100 + 0.5) or 0
    return ("%d (%d%%)"):format(kills, share), false
end
