-- Blackthornes Farmer -- Logic/Goals.lua
-- Gathering goals (2026-09-27): pick a material and a number, and the
-- Goals panel counts you toward it.
--
-- A goal is "have this many", counted from your bags (and your bank, if you
-- tick it), not "loot this many from now": 6 Copper Ore already in the bags
-- count toward 40. So the count is read from the client whenever the bags
-- change, and never kept by hand.
--
-- Only a rise out in the world counts as gathering. With the bank, a mailbox,
-- a vendor, the auction house or a trade open the count still follows the
-- bags, but that change is not loot: it floats nothing and does not feed the
-- pace.
--
-- The pace is worked out from the gathering itself: how many came in, over
-- the time between one loot and the next, with any gap over five minutes
-- counted as five (a break, not slow farming).
--
-- Goals live in BlackthornesFarmerDB.goals. They are your plan, not recorded
-- loot, so removing one removes nothing the addon measured.
--
-- That table is the account's, but a count is one character's bags, so a goal
-- belongs to the character that set it (goal.owner) and shows only there. A
-- goal saved before goals had owners shows on every character, and none of
-- them finishes it until one gathers toward it or changes it, which makes it
-- that character's.

local _, ns = ...
local L = ns.L

local Goals = ns.NewModule("Goals")

local Util = ns.Util

-- The most goals at once. The panel is a column down the side of the screen,
-- and more than this stops being a goal and becomes a shopping list.
Goals.MAX = 6

-- Where the milestones sit, and what each one says.
Goals.MILESTONES = {
    { at = 0.25, tag = "25%" },
    { at = 0.50, tag = L["HALFWAY"] },
    { at = 0.75, tag = "75%" },
}

-- The last stretch: this share of the goal or less left, and the bar turns
-- green and counts down "3 more!".
Goals.FINAL = 0.1

-- A gap between two loots longer than this is a break; it counts as this.
local BREAK = 300

-- Enough to call it a pace: this many gathered over at least this long.
local PACE_ITEMS = 3
local PACE_SECONDS = 20

-- Windows that move items without looting them: the event that opens each,
-- and the one that closes it.
local AWAY = {
    { open = "BANKFRAME_OPENED", close = "BANKFRAME_CLOSED", kind = "bank" },
    { open = "MAIL_SHOW", close = "MAIL_CLOSED", kind = "mail" },
    { open = "MERCHANT_SHOW", close = "MERCHANT_CLOSED", kind = "vendor" },
    { open = "AUCTION_HOUSE_SHOW", close = "AUCTION_HOUSE_CLOSED", kind = "auction" },
    { open = "TRADE_SHOW", close = "TRADE_CLOSED", kind = "trade" },
    -- What you craft is not loot either.
    { open = "TRADE_SKILL_SHOW", close = "TRADE_SKILL_CLOSE", kind = "craft" },
}

Goals.away = {}

-- Goes up whenever a goal is set, changed or taken off, so a reader that
-- keeps its own lookup of the goals (Logic/Butler.lua) knows to build it
-- again. Counts are not in it: they are read fresh.
Goals.version = 0

-- What one of those windows moved can reach the bags just after it closes
-- (the last of a trade, the last craft): for this long after, a rise is
-- still not loot.
local AWAY_GRACE = 2
Goals.awayUntil = 0

-- For a few seconds after login, a /reload or a loading screen the bags are
-- still being filled in, and a count going from 0 to 23 is not loot.
local SETTLE = 5
Goals.quietUntil = 0

--------------------------------------------------------------------------------
-- Saved state
--------------------------------------------------------------------------------

function Goals:Store()
    local db = ns.db
    if type(db.goals) ~= "table" then db.goals = {} end

    local store = db.goals
    if type(store.list) ~= "table" then store.list = {} end
    if type(store.today) ~= "table" then store.today = {} end
    return store
end

--- The character playing, as goals are tagged with it: its GUID, or nil
--- while the client will not say (asked again later rather than tagged
--- without it, so one character is never two). The GUID is the one way a
--- character is named in saved data, in every Blackthornes addon (see "One
--- key per character" in CLAUDE.md): Forever lets characters share a first
--- name, and "Name-Realm" filed them all as one.
function Goals:Owner()
    if self.me then return self.me end
    if type(UnitGUID) ~= "function" then return nil end
    local ok, value = pcall(UnitGUID, "player")
    local guid = ok and ns.Harvest.Readable(value) or nil
    if not guid then return nil end
    self.me = guid
    return guid
end

--- How goals were tagged before 0.26.0: "Name-Realm", or nil while the
--- client will not say. A goal tagged so is read as this character's, and
--- tagged with the GUID the next time it gathers toward it or changes it.
function Goals:OldOwner()
    if self.oldMe then return self.oldMe end

    local name, realm
    if type(UnitName) == "function" then
        local ok, value = pcall(UnitName, "player")
        name = ok and ns.Harvest.Readable(value) or nil
    end
    if not name or name == _G.UNKNOWNOBJECT then return nil end

    if type(GetRealmName) == "function" then
        local ok, value = pcall(GetRealmName)
        realm = ok and ns.Harvest.Readable(value) or nil
        if not realm then return nil end
        name = name .. "-" .. realm
    end

    self.oldMe = name
    return name
end

--- Is `owner`, as a goal or the arrow saved it, the character playing?
function Goals:IsOwner(owner)
    if owner == nil then return false end
    local me = self:Owner()
    if me ~= nil and owner == me then return true end
    local old = self:OldOwner()
    return old ~= nil and owner == old
end

--- Whether `goal` shows on this character: one it set, or one saved before
--- goals had owners.
function Goals:IsMine(goal)
    if goal.owner == nil then return true end
    return self:IsOwner(goal.owner)
end

--- This character's goals, in the order they were set.
function Goals:List()
    local mine = {}
    for _, goal in ipairs(self:Store().list) do
        if type(goal) == "table" and self:IsMine(goal) then mine[#mine + 1] = goal end
    end
    return mine
end

--- This character's goal for `name`, and where it is in the saved list.
function Goals:Find(name)
    if type(name) ~= "string" then return nil end
    local wanted = Util.Trim(name):lower()

    for index, goal in ipairs(self:Store().list) do
        if type(goal) == "table" and type(goal.item) == "string"
            and goal.item:lower() == wanted and self:IsMine(goal) then
            return goal, index
        end
    end

    -- The same item by its other name: a goal saved as "Linen Cloth" asked
    -- for as the client's "Leinenstoff", or the other way round. Only on a
    -- client whose names differ from the data's.
    if ns.Util.EnglishClient() then return nil end
    local item = ns.DB:GetItem(name)
    if not item then return nil end
    for index, goal in ipairs(self:Store().list) do
        if type(goal) == "table" and type(goal.item) == "string"
            and self:IsMine(goal) and ns.DB:GetItem(goal.item) == item then
            return goal, index
        end
    end

    return nil
end

--- Whether the bank counts toward goals. Off unless asked for.
function Goals:CountsBank()
    return self:Store().bank == true
end

function Goals:SetCountsBank(on)
    self:Store().bank = on and true or false
    -- The bank's share is not loot, so it is read quietly; a quiet read
    -- finishes nothing, so a goal the bank took past its number finishes
    -- on the read after.
    self:Update(true)
    self:Update()
end

--------------------------------------------------------------------------------
-- The clock and the calendar
--------------------------------------------------------------------------------

local function Now()
    if type(GetTime) == "function" then
        local ok, value = pcall(GetTime)
        if ok and type(value) == "number" then return value end
    end
    return os.time()
end

Goals.Now = Now

--- Today, as the goal-a-day count keys it.
local function Today()
    local fn = type(date) == "function" and date or os.date
    local ok, value = pcall(fn, "%Y-%m-%d")
    return ok and value or "?"
end

--- Goals finished today.
function Goals:DoneToday()
    local today = self:Store().today
    if today.day ~= Today() then return 0 end
    return tonumber(today.count) or 0
end

local function NoteDoneToday(self)
    local today = self:Store().today
    if today.day ~= Today() then
        today.day = Today()
        today.count = 0
    end
    today.count = (tonumber(today.count) or 0) + 1
end

--------------------------------------------------------------------------------
-- Counting
--------------------------------------------------------------------------------

--- How many of `name` you have, or nil when the client will not say.
--- `itemID`, when the caller knows it, is asked by over the name.
--
-- Read inside a pcall and made into a plain number there: in an instance
-- the client can hand back a value that raises when it is compared.
function Goals:Have(name, itemID)
    local id = itemID or (ns.Value and ns.Value:ItemID(name))
    local bank = self:CountsBank()

    local fn
    if type(C_Item) == "table" and type(C_Item.GetItemCount) == "function" then
        fn = C_Item.GetItemCount
    elseif type(GetItemCount) == "function" then
        fn = GetItemCount
    end
    if not fn then return nil end

    local ok, count = pcall(function()
        local value = fn(id or name, bank)
        return ns.Harvest.ReadableNumber(value)
    end)

    if not ok or type(count) ~= "number" then return nil end
    return math.max(0, math.floor(count))
end

--------------------------------------------------------------------------------
-- Setting and removing
--------------------------------------------------------------------------------

-- Whether the client knows an item by exactly this name. A vendor item the
-- data never lists (Salt) is still a real item, and it must not be taken
-- for a longer name that starts the same way (Salty Scorpid Venom).
local function ClientKnowsName(text)
    local fn = (type(C_Item) == "table" and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
    if type(fn) ~= "function" then return false end
    local ok, id = pcall(fn, text)
    return ok and type(id) == "number" and id > 0
end

Goals.ClientKnowsName = ClientKnowsName

--- The item a typed name means: the database's own spelling when it knows
--- it, else what you typed, as long as it looks like a name.
--- An item ID gives that item's name.
function Goals:ResolveItem(text)
    -- An item ID: the data's name for it, else the client's.
    local id = type(text) == "number" and text or tonumber(type(text) == "string" and text:match("^%s*(%d+)%s*$"))
    if id then
        local item = ns.DB:ByID()[id]
        if item then return item.name end
        return ns.DB.ClientItemName(id)
    end

    text = Util.Trim(Util.StripColor(text or ""))

    -- An item link: [Copper Ore] out of it.
    local linked = text:match("%[(.-)%]")
    if linked then text = linked end

    if text == "" then return nil end

    local item, byClientName = ns.DB:GetItem(text)
    -- A name the client gives the item (a German client's "Leinenstoff")
    -- stays as typed: it is what the player reads, and what the bags and
    -- Tradeskills call it. The database still finds the item by it.
    if item then return byClientName and text or item.name end

    -- An alias wins, then an item the client knows by exactly this name.
    local wanted = text:lower()
    for entry in ns.DB:Iterate() do
        for _, alias in ipairs(entry.aliases or {}) do
            if alias:lower() == wanted then return entry.name end
        end
    end
    if ClientKnowsName(text) then return text end

    -- Close enough: the one item whose name starts with the whole words
    -- typed. "Copper" finds Copper Ore, but "Salt" never finds Salty
    -- Scorpid Venom.
    local matches = {}
    for entry in ns.DB:Iterate() do
        local lowered = entry.name:lower()
        if lowered:sub(1, #wanted) == wanted then
            local after = lowered:sub(#wanted + 1, #wanted + 1)
            if after == "" or after == " " then
                matches[#matches + 1] = entry.name
            end
        end
    end
    if #matches == 1 then return matches[1] end

    -- Something the database has never heard of can still be a goal: the
    -- bags know it by name.
    return text
end

--- Set (or change) a goal. Returns the goal, or nil and why not.
function Goals:Set(name, target)
    name = self:ResolveItem(name)
    target = math.floor(tonumber(target) or 0)

    if not name then return nil, L["no item named"] end
    if target < 1 then return nil, L["the amount has to be 1 or more"] end
    if target > 99999 then return nil, L["that is more than anyone could carry"] end

    local have = self:Have(name) or 0
    if have >= target then
        return nil, L.Format("you already have %d %s", have, name)
    end

    local goal = self:Find(name)
    local list = self:Store().list
    local isNew = false

    if not goal then
        -- A finished goal still on the panel makes room for a new one. Only
        -- this character's count: another's goals are not on its panel.
        if #self:List() >= Goals.MAX then
            for index = #list, 1, -1 do
                local other = list[index]
                if type(other) == "table" and other.done and self:IsMine(other) then
                    table.remove(list, index)
                    break
                end
            end
        end
        if #self:List() >= Goals.MAX then
            return nil, L.Format("you can have up to %d goals at once", Goals.MAX)
        end

        goal = { item = name }
        list[#list + 1] = goal
        isNew = true
    end

    -- Changing a goal saved before goals had owners makes it yours.
    goal.owner = self:Owner() or goal.owner
    goal.target = target
    goal.have = have
    goal.start = have
    goal.done = nil
    goal.doneIn = nil
    goal.gained = 0
    goal.paced = 0
    goal.loots = 0
    goal.active = 0
    goal.lastGain = nil
    goal.milestone = Goals.MilestoneFor(have / target)
    Goals.version = Goals.version + 1

    if ns.GoalsUI then ns.GoalsUI:Refresh() end
    if isNew and ns.Arrow and ns.Arrow.TurnOnForGoal then pcall(ns.Arrow.TurnOnForGoal, ns.Arrow) end
    return goal
end

function Goals:Remove(name)
    local goal, index = self:Find(name)
    if not goal then return false end

    table.remove(self:Store().list, index)
    Goals.version = Goals.version + 1
    if ns.GoalsUI then ns.GoalsUI:Refresh() end
    return true
end

--- Take this character's finished goals off the panel.
function Goals:ClearDone()
    local list = self:Store().list
    local removed = 0
    for index = #list, 1, -1 do
        local goal = list[index]
        if type(goal) == "table" and goal.done and self:IsMine(goal) then
            table.remove(list, index)
            removed = removed + 1
        end
    end
    if removed > 0 then Goals.version = Goals.version + 1 end
    if removed > 0 and ns.GoalsUI then ns.GoalsUI:Refresh() end
    return removed
end

--------------------------------------------------------------------------------
-- Reading a goal
--------------------------------------------------------------------------------

--- The last milestone at or below `fraction`: 0 for none yet, else its index.
function Goals.MilestoneFor(fraction)
    local reached = 0
    for index, milestone in ipairs(Goals.MILESTONES) do
        if fraction >= milestone.at then reached = index end
    end
    return reached
end

function Goals.Fraction(goal)
    local target = tonumber(goal.target) or 0
    if target <= 0 then return 0 end
    return math.max(0, math.min(1, (tonumber(goal.have) or 0) / target))
end

function Goals.Left(goal)
    return math.max(0, (tonumber(goal.target) or 0) - (tonumber(goal.have) or 0))
end

--- In the last stretch: a few left, and the bar goes green.
function Goals.Final(goal)
    if goal.done then return false end
    local left = Goals.Left(goal)
    return left > 0 and left <= math.max(1, math.floor((goal.target or 0) * Goals.FINAL))
end

--- Seconds to finish at the pace so far, or nil until there is a pace.
--
-- The first loot only starts the clock, so what it brought is left out of
-- the pace (goal.paced); counted, it made the first estimates about twice
-- too quick. A goal set before that count was kept goes on with all it
-- gained.
function Goals.Eta(goal)
    local gained = tonumber(goal.paced) or tonumber(goal.gained) or 0
    local active = tonumber(goal.active) or 0
    if gained < PACE_ITEMS or active < PACE_SECONDS then return nil end

    return Goals.Left(goal) / (gained / active)
end

--- "18 min 42s", "about 9 min", and so on.
function Goals.Duration(seconds, rough)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))

    if rough then
        if seconds < 60 then return L["under a minute"] end
        local minutes = math.floor(seconds / 60 + 0.5)
        if minutes < 60 then return L.Format("about %d min", minutes) end
        return L.Format("about %d hr %d min", math.floor(minutes / 60), minutes % 60)
    end

    if seconds < 60 then return L.Format("%ds", seconds) end
    local minutes = math.floor(seconds / 60)
    if minutes < 60 then return L.Format("%d min %ds", minutes, seconds % 60) end
    return L.Format("%d hr %d min", math.floor(minutes / 60), minutes % 60)
end

--- The best place the database knows for an item: the highest drop rate,
--- else the source nearest your level. Nil when it knows none.
function Goals:BestSpot(name)
    local item = ns.DB:GetItem(name)
    if not (item and item.sources and #item.sources > 0) then return nil end

    local best
    for _, source in ipairs(item.sources) do
        if source.chance and (not best or not best.chance or source.chance > best.chance) then
            best = source
        end
    end

    if not best then
        local level = 1
        if type(UnitLevel) == "function" then
            local ok, value = pcall(UnitLevel, "player")
            level = ok and ns.Harvest.ReadableNumber(value) or level
        end

        for _, source in ipairs(ns.Search:SortedSources(item)) do
            local low = source.minLevel or 0
            if not best or low <= level then best = source end
        end
    end

    return best
end

--------------------------------------------------------------------------------
-- Keeping up
--------------------------------------------------------------------------------

--- What each goal's count did since it was last read. `quiet` reads the
--- counts without calling anything gathered (login, the bank tick box), and
--- never finishes a goal.
--
-- Returns a list of { goal, from, to, gathered, milestone, done } for the
-- goals whose count moved or that finished, which is what the panel
-- animates.
function Goals:Update(quiet)
    local changes = {}
    local now = Now()
    local away = next(self.away) ~= nil or now < (self.awayUntil or 0)
    if now < (self.quietUntil or 0) then quiet = true end

    for _, goal in ipairs(self:List()) do
        if type(goal) == "table" and not goal.done then
            local have = self:Have(goal.item)
            local was = tonumber(goal.have) or 0
            local change

            if have and have ~= was then
                change = { goal = goal, from = was, to = have }
                goal.have = have

                if have > was and not quiet and not away then
                    change.gathered = have - was
                    goal.gained = (tonumber(goal.gained) or 0) + change.gathered
                    goal.loots = (tonumber(goal.loots) or 0) + 1
                    -- Gathering toward a goal saved before goals had owners
                    -- makes it yours; one tagged the old way gets the GUID.
                    goal.owner = self:Owner() or goal.owner

                    if goal.lastGain then
                        goal.active = (tonumber(goal.active) or 0)
                            + math.min(BREAK, math.max(0, now - goal.lastGain))
                        if goal.paced then
                            goal.paced = (tonumber(goal.paced) or 0) + change.gathered
                        end
                    end
                    goal.lastGain = now
                end

                -- A milestone once, on the way up; dropping back under one
                -- (crafting, selling) quietly lowers the mark.
                local reached = Goals.MilestoneFor(Goals.Fraction(goal))
                if reached > (goal.milestone or 0) and not quiet then
                    change.milestone = Goals.MILESTONES[reached]
                end
                goal.milestone = reached
            end

            -- Finished only on a read that is not quiet, by the character the
            -- goal belongs to: the bags filling in at login, or another
            -- character's bags, finish nothing. A count a quiet read took to
            -- the number finishes on the next read.
            if have and have >= (tonumber(goal.target) or math.huge)
                and not quiet and goal.owner ~= nil then
                change = change or { goal = goal, from = was, to = have }
                goal.done = true
                goal.doneIn = goal.active or 0
                change.done = true
                change.milestone = nil
                NoteDoneToday(self)
            end

            if change then changes[#changes + 1] = change end
        end
    end

    if #changes > 0 and ns.GoalsUI then ns.GoalsUI:Changed(changes) end

    for _, change in ipairs(changes) do
        if change.done then self:Finished(change.goal) end
    end

    return changes
end

--- The recap for a finished goal: { loots, perLoot, worth }. Worth is nil
--- without a price.
function Goals:Recap(goal)
    local loots = tonumber(goal.loots) or 0
    local gained = tonumber(goal.gained) or 0

    local recap = { loots = loots, gained = gained }
    if loots > 0 then recap.perLoot = gained / loots end

    local id = ns.Value:ItemID(goal.item)
    local unit = id and ns.Value:UnitPrice(id)
    if unit then recap.worth = unit * (tonumber(goal.target) or 0) end

    return recap
end

--- A goal just reached its number: a line in chat, and the fanfare.
function Goals:Finished(goal)
    local line = L.Format("Goal done: %s %s!",
        Util.Colored("good", tostring(goal.target)), Util.ColorItemOr("accent", goal.item))

    if (tonumber(goal.doneIn) or 0) >= 1 then
        line = line .. L.Format(" %s of gathering.", Goals.Duration(goal.doneIn))
    end

    ns.PrintRaw(("|c%sBlackthornes Farmer:|r %s"):format(ns.COLORS.accent, line))

    -- The peon's "Work complete!", or with voice lines off (or said a
    -- moment ago) the drop-rates-unlocked sound, the one for big moments.
    if ns.TrackerFX and ns.TrackerFX:Say("goal") then return end
    if ns.Tracker and not ns.Tracker.PlayFile(ns.Tracker.SOUNDS.unlock)
        and type(PlaySound) == "function" then
        pcall(PlaySound, 888, "Master")
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

--- After login, a /reload or a loading screen: quiet while the bags fill in,
--- then one read that can finish a goal they took to its number.
function Goals:Settle()
    self.quietUntil = Now() + SETTLE
    if C_Timer and type(C_Timer.After) == "function" then
        pcall(C_Timer.After, SETTLE + 1, function()
            Goals:Update()
            -- Shown again here too: at login the client can keep the
            -- character's name to itself for a moment, and with no owner
            -- the panel hid with nothing to show. A count change is not
            -- the only way back.
            if ns.GoalsUI then ns.GoalsUI:Refresh() end
        end)
    end
end

function Goals:OnEnable()
    self:Settle()
    self:Update(true)

    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function() Goals:Settle() end)

    local function Changed() Goals:Update() end
    -- Once per burst of bag changes where the client has it; each change
    -- on a client that does not.
    if not ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", Changed) then
        ns.RegisterEvent(self, "BAG_UPDATE", Changed)
    end

    for _, window in ipairs(AWAY) do
        ns.RegisterEvent(self, window.open, function() Goals.away[window.kind] = true end)
        ns.RegisterEvent(self, window.close, function() Goals:WindowClosed(window.kind) end)
    end

    -- Walking away ends the game's interaction too; heard as well, since a
    -- client that said that and not MAIL_CLOSED (Butler found one,
    -- 2026-10-11) left the goals counting nothing gathered until /reload.
    ns.RegisterEvent(self, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, _, kind)
        local away = Goals.InteractionKind(kind)
        if away and Goals.away[away] then Goals:WindowClosed(away) end
    end)
end

--- One of the AWAY windows closed.
function Goals:WindowClosed(kind)
    self.away[kind] = nil
    self.awayUntil = Now() + AWAY_GRACE
    -- Whatever moved while it was open is already counted; read the
    -- bags once more so the next loot is measured from here.
    self:Update(true)
end

-- The game's interaction types for the AWAY windows that have one, with
-- the numbers retail gives them for a client without the Enum.
local INTERACTIONS = {
    { name = "TradePartner", number = 1, kind = "trade" },
    { name = "Merchant", number = 5, kind = "vendor" },
    { name = "Banker", number = 8, kind = "bank" },
    { name = "MailInfo", number = 17, kind = "mail" },
    { name = "Auctioneer", number = 21, kind = "auction" },
}

--- The AWAY kind for one of the game's interaction types, else nil.
function Goals.InteractionKind(kind)
    if type(kind) ~= "number" then return nil end
    local enum = rawget(_G, "Enum")
    local types = type(enum) == "table" and rawget(enum, "PlayerInteractionType") or nil
    for _, entry in ipairs(INTERACTIONS) do
        local number = type(types) == "table" and rawget(types, entry.name) or entry.number
        if kind == number then return entry.kind end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local function PrintGoals()
    local list = Goals:List()
    if #list == 0 then
        ns.Print(L["no goals yet. /farm goal Copper Ore 40, or the Goal button on a search result."])
        return
    end

    ns.Print(L["your goals:"])
    for _, goal in ipairs(list) do
        local state = goal.done and Util.Colored("good", L["done"])
            or L.Format("%d left", Goals.Left(goal))
        ns.PrintRaw(("  %s  %d / %d  %s"):format(
            Util.ColorItemOr("accent", goal.item), goal.have or 0, goal.target or 0,
            Util.Colored("muted", state)))
    end
end

ns.RegisterCommand("goal", L["set a gathering goal: /farm goal Copper Ore 40 (remove, bank on/off)"], function(rest)
    rest = Util.Trim(rest)
    local word, after = rest:match("^(%S+)%s*(.*)$")
    word = word and word:lower()

    if rest == "" then
        PrintGoals()
        if ns.GoalsUI then ns.GoalsUI:Show() end
        return
    end

    if word == "remove" or word == "clear" then
        if word == "clear" and after == "" then
            ns.Print(L.Format("took %s off the panel.",
                Util.Plural(Goals:ClearDone(), L["finished goal"], L["finished goals"])))
            return
        end

        local name = Goals:ResolveItem(after)
        if name and Goals:Remove(name) then
            ns.Print(L.Format("goal for %s removed.", Util.ColorItemOr("accent", name)))
        else
            ns.Print(L.Format("no goal for %s.", after ~= "" and after or L["that"]))
        end
        return
    end

    if word == "bank" then
        local on = after:lower()
        if on == "on" then Goals:SetCountsBank(true)
        elseif on == "off" then Goals:SetCountsBank(false)
        else Goals:SetCountsBank(not Goals:CountsBank()) end

        ns.Print(Goals:CountsBank()
            and L["goals count your bank too."]
            or L["goals count your bags only."])
        return
    end

    -- "Copper Ore 40", or "40 Copper Ore".
    local name, amount = rest:match("^(.-)%s+(%d+)$")
    if not name then amount, name = rest:match("^(%d+)%s+(.+)$") end

    if not (name and amount) then
        ns.Print(L["give it a number: /farm goal Copper Ore 40"])
        return
    end

    local goal, why = Goals:Set(name, amount)
    if not goal then
        ns.Print(L.Format("couldn't set that goal: %s.", why))
        return
    end

    ns.Print(L.Format("goal set: %s %s. You have %d, %d to go.",

        Util.Colored("good", tostring(goal.target)), Util.ColorItemOr("accent", goal.item),
        goal.have, Goals.Left(goal)))
    if ns.GoalsUI then ns.GoalsUI:Show() end
end)
