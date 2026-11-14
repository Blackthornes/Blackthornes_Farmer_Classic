-- Blackthornes Farmer -- Logic/Harvest.lua
-- Record what actually drops, as you play.
--
-- Every fact this addon ships was copied from Classic and is a guess about
-- Forever. The client already knows the truth at the moment you loot a corpse:
-- which mob it was, its level, the zone, the subzone, where you are standing,
-- and what was inside. Count corpses looted and count the ones that held the
-- item, and that is a real drop rate, measured here rather than assumed.
--
-- Nothing is sent anywhere. It accumulates in SavedVariables from one session
-- to the next, and `/farm export` or tools/harvest_import.py hands it back as a
-- data file for the repository.
--
-- Nothing about this client's loot API is documented, so every call is behind
-- a capability check and the module degrades to doing less rather than
-- erroring. A missed sample is a missed sample; a Lua error mid-raid is not.

local _, ns = ...
local L = ns.L

local Harvest = ns.NewModule("Harvest")

local Util = ns.Util

-- Below this many corpses a percentage is noise, so the export omits the rate
-- and says how thin the sample was instead of inventing confidence.
local MIN_SAMPLE = 20

Harvest.records = {}
Harvest.enabled = true

-- Every corpse opened this session, by guid: which record it went into and
-- which items were already counted from it. See RecordCorpse.
Harvest.opened = {}

-- Every corpse whose loot showed in another corpse's window this session
-- (area loot), by guid. Its drops went with that window, so opening it
-- later, when full bags left something on it, is no new corpse.
Harvest.shown = {}

--------------------------------------------------------------------------------
-- Client capabilities
--------------------------------------------------------------------------------

local function Has(name)
    local path, object = name, _G
    local namespace, method = name:match("^([%w_]+)%.([%w_]+)$")

    if namespace then
        object = _G[namespace]
        if type(object) ~= "table" then return false end
        path = method
    end

    return type(object[path]) == "function"
end

function Harvest:Capabilities()
    if self.caps then return self.caps end

    self.caps = {
        lootSlotInfo = Has("GetLootSlotInfo"),
        lootSlotLink = Has("GetLootSlotLink"),
        lootSlotType = Has("GetLootSlotType"),
        numLootItems = Has("GetNumLootItems"),
        fishingLoot  = Has("IsFishingLoot"),
        bestMap      = Has("C_Map.GetBestMapForUnit"),
        playerPos    = Has("C_Map.GetPlayerMapPosition"),
        realZone     = Has("GetRealZoneText"),
        subZone      = Has("GetSubZoneText"),
    }

    self.caps.usable = self.caps.numLootItems and self.caps.lootSlotInfo
    return self.caps
end

--------------------------------------------------------------------------------
-- Values the client will not let us read
--
-- Forever inherited retail's secret values along with the instance rules that
-- go with them: inside a dungeon the client may hand an addon a name, a level
-- or a quantity that it is not willing to have inspected. The value looks
-- ordinary -- type() answers "string" -- but comparing, concatenating or
-- formatting it raises on the spot, and it raises in this addon's own stack
-- frame, because the execution reading it is tainted by this addon.
--
-- Seen in Ragefire Chasm on 2026-09-22. UnitName("target") came back
-- clean from its pcall and `name == ""` two lines later was the error. The
-- pcall around the call never had a chance: nothing was wrong with the call.
--
-- So nothing that came out of the client is touched outside a pcall. Every
-- such value goes through one of these two, where the reading itself is what
-- happens inside the pcall, and callers get back either an ordinary Lua value
-- or nil. An unreadable name costs a corpse, which is the trade this module
-- makes everywhere else already: a sample attributed to the wrong mob is worse
-- than no sample.
--------------------------------------------------------------------------------

-- The reads themselves, kept out here so each call passes them to pcall
-- rather than making a new function every time: these run on every event.
local function CopyText(value)
    -- The read is the test. Concatenating and comparing are both refused
    -- on a secret value, and refusing means raising, so doing them in here
    -- is how we find out. Whatever comes back out has survived both.
    local text = value .. ""
    if text == "" then return nil end
    return text
end

local function CopyNumber(value)
    -- Arithmetic and comparison, for the same reason as above. The
    -- comparison doubles as the not-a-number check.
    local number = value + 0
    if number ~= number then return nil end
    return number
end

--- A plain string copy of `value`, or nil if this client will not let us read it.
local function Readable(value)
    local kind = type(value)

    -- A number would concatenate cleanly below and is not a name, so it is
    -- ruled out first. Everything else -- nil, tables, secret values -- is
    -- ruled out by failing the read.
    if kind == "number" or kind == "boolean" then return nil end

    local ok, copy = pcall(CopyText, value)

    -- type() answers safely for a secret value and for nil alike, which is why
    -- the check out here is a type check and not a comparison.
    if not ok or type(copy) ~= "string" then return nil end

    return copy
end

--- `value` as a plain number, or nil if this client will not let us read it.
local function ReadableNumber(value)
    local kind = type(value)

    -- "12" would coerce to 12 in the arithmetic below, and a level that
    -- arrived as text is not one this module should be believing.
    if kind == "string" or kind == "boolean" then return nil end

    local ok, copy = pcall(CopyNumber, value)

    if not ok or type(copy) ~= "number" then return nil end

    return copy
end

-- The kill tracker reads the same loot window and the same target, so it reads
-- them through the same two doors.
Harvest.Readable = Readable
Harvest.ReadableNumber = ReadableNumber

--- Is the tooltip showing a unit or an item, rather than a world object such
--- as a school or a herb?
--
-- Older clients ask the tooltip itself (GetUnit, GetItem); the retail engine
-- moved both to TooltipUtil. Whichever this client has is asked, so a mob
-- called "... Swarm" cannot pass for a fishing school, and a mob under the
-- mouse is never remembered as the node about to be picked.
-- Is there a value at all? type() is the one thing a secret value answers,
-- so this never touches the value itself. `name ~= nil` looked harmless, but
-- on a mob in a dungeon the name is secret and the comparison raised, once
-- per hook, every time the tooltip showed a mob.
local function Present(value)
    return type(value) ~= "nil"
end

--- A drop rate as the export writes it, or nil to leave the field out. The
--- data refuses 0, so a rare drop is kept to a decimal place, and one too rare
--- to show at all is listed without a rate.
function Harvest.ExportChance(percent)
    if type(percent) ~= "number" or percent ~= percent then return nil end
    if percent >= 99.95 then return "chance = 100" end
    if percent >= 0.95 then return ("chance = %d"):format(math.floor(percent + 0.5)) end
    if percent >= 0.05 then return ("chance = %.1f"):format(percent) end
    return nil
end

function Harvest.TooltipShowsUnitOrItem(tooltip)
    if type(tooltip) ~= "table" then return false end

    for _, method in ipairs({ "GetUnit", "GetItem" }) do
        if type(tooltip[method]) == "function" then
            local ok, name = pcall(tooltip[method], tooltip)
            if ok and Present(name) then return true end
        end
    end

    local util = _G.TooltipUtil
    if type(util) == "table" then
        for _, method in ipairs({ "GetDisplayedUnit", "GetDisplayedItem" }) do
            if type(util[method]) == "function" then
                local ok, name = pcall(util[method], tooltip)
                if ok and Present(name) then return true end
            end
        end
    end

    return false
end

--- One OnShow hook on the game tooltip for everything that reads a world
--- object's name off it (gathering, fishing, respawn times), so the "is it
--- a unit or an item" check runs once per showing, not once per module.
--- `fn(tooltip, unitOrItem)`; one watcher per key.
local tooltipWatchers, tooltipOrder = {}, {}

function Harvest.WatchTooltip(key, fn)
    if not tooltipWatchers[key] then tooltipOrder[#tooltipOrder + 1] = key end
    tooltipWatchers[key] = fn
    if Harvest.tooltipHooked then return end

    local tooltip = _G.GameTooltip
    if not (tooltip and type(tooltip.HookScript) == "function") then return end
    Harvest.tooltipHooked = pcall(tooltip.HookScript, tooltip, "OnShow", function(shown)
        local unitOrItem = Harvest.TooltipShowsUnitOrItem(shown or _G.GameTooltip)
        for _, each in ipairs(tooltipOrder) do
            pcall(tooltipWatchers[each], shown, unitOrItem)
        end
    end)
end

--------------------------------------------------------------------------------
-- Where and what
--------------------------------------------------------------------------------

--- The player's position as map percentages, or nil if the client will not say.
--- Where the player stands on the map the client is showing them in:
--- mapID, x, y, with x and y as fractions of that map (0 to 1). Nil when the
--- client will not say, which inside an instance it usually will not.
function Harvest:PlayerMapPosition()
    local caps = self:Capabilities()
    if not (caps.bestMap and caps.playerPos) then return nil end

    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    mapID = ok and ReadableNumber(mapID) or nil
    if not mapID then return nil end

    local gotPosition, position = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not gotPosition or not position then return nil end

    -- A map position is a vector object on modern clients; older ones hand
    -- back two plain numbers.
    local x, y

    if type(position) == "table" and type(position.GetXY) == "function" then
        local readable, px, py = pcall(position.GetXY, position)
        if readable then x, y = px, py end
    elseif type(position) == "number" then
        local readable, _, py = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
        if readable then x, y = position, py end
    end

    -- Read rather than type-checked: a coordinate off a restricted client is
    -- as liable to be secret as a name, and this one is about to be compared.
    x, y = ReadableNumber(x), ReadableNumber(y)

    if not x or not y then return nil end
    if x == 0 and y == 0 then return nil end

    return mapID, x, y
end

--- The player's map coordinates in percent, as the game shows them: 45.2, 68.0.
function Harvest:PlayerPosition()
    local mapID, x, y = self:PlayerMapPosition()
    if not mapID then return nil end

    return x * 100, y * 100
end

--- The corpse being looted, as far as the client will admit.
--
-- The loot window does not name its owner. The target is the corpse in the
-- usual case, so that is asked first. But plenty of players loot without
-- targeting the corpse: the interact key, a right-click on a corpse with
-- another mob targeted, auto loot with the target already cleared. Waiting
-- for the target counted none of those (a player's report, 2026-10-05: the
-- kills panel stayed empty), so when the target is not the corpse, the
-- window's own sources are asked whose loot it is (GetLootSourceInfo), and
-- the corpse is the one of them the client names under the mouse or the
-- interact key, or one this addon saw alive by that same guid (NoteUnit).
--
-- Every way in matches by guid, so nothing is guessed: a window whose
-- sources cannot be read, or whose mob was never seen, is still dropped. A
-- sample attributed to the wrong mob is worse than no sample: it goes into
-- the data and sends somebody to the wrong place.
--
-- Returns the name, the level (nil when unknown), the guid (nil when the
-- client will not give one) and the unit token the corpse is ("target",
-- "mouseover", "softinteract"; nil when it was only known by its guid).
function Harvest:Corpse()
    -- Every reader asks this several times a window (once a slot, and
    -- again per check), and inside a dungeon each answer builds a tooltip
    -- for the mob's name, so one window's answer serves the rest of it.
    local reading = self.lootReading
    if reading and reading.corpse then
        local kept = reading.corpse
        return kept[1], kept[2], kept[3], kept[4]
    end

    local name, level, guid, unit = self:FindCorpse()
    if reading then reading.corpse = { name, level, guid, unit } end
    return name, level, guid, unit
end

function Harvest:FindCorpse()
    -- A rogue's Pick Pocket opens a loot window on a mob still alive. It is
    -- no kill, and taking it for one put pocket loot in the drop rates and
    -- left the real kill's coin uncounted (its corpse was "already opened").
    if self:PickingPockets() then return nil end

    local sources = self:LootSources()

    local name, level, guid = self:UnitCorpse("target")
    if name and self:LootIsFrom(guid) then
        -- A target whose guid will not be read is still the corpse, but
        -- without a guid every opening of it counted as a new kill. A window
        -- with one corpse in it names that guid itself.
        if not guid and #sources == 1 and Harvest.NpcID(sources[1]) then
            guid = sources[1]
        end
        return name, level, guid, "target"
    end

    if #sources == 0 then return nil end

    local listed = {}
    for _, source in ipairs(sources) do listed[source] = true end

    for _, unit in ipairs(Harvest.CORPSE_UNITS) do
        local unitName, unitLevel, unitGuid = self:UnitCorpse(unit)
        if unitName and unitGuid and listed[unitGuid] then
            return unitName, unitLevel, unitGuid, unit
        end
    end

    -- Past this point nothing says which corpse was clicked. A corpse never
    -- seen before is tried first: one already opened, or shown in another
    -- corpse's area loot, has been counted, and picking it could pass over
    -- the one that is new (2026-10-13, bags full).
    sources = self:NewSourcesFirst(sources)

    for _, source in ipairs(sources) do
        local known = self:KnownUnit(source)
        if known and not self:StillAlive(source) then return known.name, known.level, source end
    end

    -- Inside a dungeon the corpse's own name and guid are hidden, but the
    -- loot window still names its source by guid, and the guid carries the
    -- mob's ID (Ragefire Chasm, 2026-10-10). The ID is a fact, not a guess,
    -- so the corpse is the first mob the window names, under the name that
    -- ID has. Other corpses' slots in the same window are left out by
    -- SlotIsTargets, as with a target.
    for _, source in ipairs(sources) do
        local npcID = Harvest.NpcID(source)
        if npcID and not self:StillAlive(source) then return self:NpcName(npcID, source), nil, source end
    end

    return nil
end

--- Every other corpse the open window names is marked shown, unless it
--- was opened itself. Read before the corpse is judged, so the corpse
--- being opened is never marked by its own window.
---
--- Corpses opened or shown this session are let go after OPENED_KEEP
--- seconds: the body is long gone by then. Session only, nothing saved.
Harvest.OPENED_KEEP = 1800

function Harvest:Aging()
    if not self.aging then
        self.aging = ns.Util.NewAging(Harvest.OPENED_KEEP, function(guid)
            Harvest.opened[guid] = nil
            Harvest.shown[guid] = nil
        end)
    end
    return self.aging
end

function Harvest:NoteShown(guid)
    -- Without the corpse's own guid it could be any of them.
    if not guid then return end
    for _, source in ipairs(self:LootSources()) do
        if source ~= guid and not self.opened[source] and Harvest.NpcID(source) then
            if not self.shown[source] then
                self.shown[source] = true
                self:Aging():Add(source)
            end
        end
    end
end

--- `sources` with every corpse not yet opened or shown this session first,
--- the rest after, each part in the window's order.
function Harvest:NewSourcesFirst(sources)
    local fresh, seen = {}, {}
    for _, source in ipairs(sources) do
        if self.opened[source] or self.shown[source] then
            seen[#seen + 1] = source
        else
            fresh[#fresh + 1] = source
        end
    end
    for _, source in ipairs(seen) do fresh[#fresh + 1] = source end
    return fresh
end

-- Units a living mob the loot window names could be: one picked from by
-- Pick Pocket is targeted, or under the mouse or the interact key.
Harvest.LIVING_UNITS = { "target", "mouseover", "softinteract", "softenemy" }

--- Is `guid` a mob the client shows alive right now? Only a plain answer
--- counts: a guid or a death it will not let be read says nothing.
function Harvest:StillAlive(guid)
    if type(guid) ~= "string" or not UnitGUID or not UnitIsDead then return false end
    for _, unit in ipairs(Harvest.LIVING_UNITS) do
        local gotGuid, unitGuid = pcall(UnitGUID, unit)
        if gotGuid and Readable(unitGuid) == guid then
            local gotDead, dead = pcall(UnitIsDead, unit)
            local readable, living = pcall(function() return gotDead and (dead == false or dead == nil) end)
            if readable and living == true then return true end
        end
    end
    return false
end

-- Pick Pocket, by id and by name for a client whose ids differ, and how
-- long after the cast its loot window counts as the pocket's.
Harvest.PICK_POCKET_ID = 921
local PICK_POCKET_SECONDS = 2

local function SpellName(spellID)
    if type(C_Spell) == "table" and type(C_Spell.GetSpellName) == "function" then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        local text = ok and Readable(name) or nil
        if text then return text end
    end
    if type(GetSpellInfo) == "function" then
        local ok, name = pcall(GetSpellInfo, spellID)
        return ok and Readable(name) or nil
    end
    return nil
end

local function Now()
    if type(GetTime) ~= "function" then return nil end
    local ok, now = pcall(GetTime)
    return ok and ReadableNumber(now) or nil
end

--- Is `spellID` Pick Pocket?
function Harvest.IsPickPocket(spellID)
    local id = ReadableNumber(spellID)
    if not id then return false end
    if id == Harvest.PICK_POCKET_ID then return true end
    local name = SpellName(id)
    return name ~= nil and name == SpellName(Harvest.PICK_POCKET_ID)
end

--- One of the player's casts was sent or went through.
function Harvest:OnPlayerCast(unit, spellID)
    if Readable(unit) ~= "player" or not Harvest.IsPickPocket(spellID) then return end
    self.pickedPocketAt = Now()
end

--- Did the loot window just open come from your own Pick Pocket?
function Harvest:PickingPockets()
    local at, now = self.pickedPocketAt, Now()
    return at ~= nil and now ~= nil and now - at >= 0 and now - at <= PICK_POCKET_SECONDS
end

--- Is the open loot window a pocket you picked? True after your own Pick
--- Pocket, or when the mob it names is still alive (a client whose cast
--- was not heard). A window from an item in the bags never is. Second: the
--- mob's name, when the client gives it.
-- It is no kill, but the coin and items are yours, so the session's loot
-- and gold take them (2026-10-18: a rogue's pocket coin went uncounted).
function Harvest:PocketLoot()
    local sources = self:LootSources()
    for _, source in ipairs(sources) do
        if type(source) == "string" and source:match("^Item%-") then return false end
    end

    local living
    for _, source in ipairs(sources) do
        if Harvest.NpcID(source) and self:StillAlive(source) then
            living = source
            break
        end
    end
    if not living and not self:PickingPockets() then return false end

    local function NameOf(unit)
        if not UnitName then return nil end
        local ok, name = pcall(UnitName, unit)
        return ok and Readable(name) or nil
    end

    if living and UnitGUID then
        for _, unit in ipairs(Harvest.LIVING_UNITS) do
            local ok, guid = pcall(UnitGUID, unit)
            if ok and Readable(guid) == living then
                local name = NameOf(unit)
                if name then return true, name end
            end
        end
    end
    return true, NameOf("target")
end

--- The mob ID in a creature's guid ("Creature-0-4621-389-76516-11320-..."
--- is 11320), or nil for anything else.
function Harvest.NpcID(guid)
    if type(guid) ~= "string" then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
end

--- What a mob ID is called, without asking the game: a name it gave before
--- (npcNames, account wide), then Classic's (Data/NpcNames.lua). Nil when
--- neither knows it.
function Harvest.KnownNpcName(npcID)
    local db = ns.db
    local names = type(db) == "table" and db.npcNames or nil
    if type(names) == "table" and type(names[npcID]) == "string" then
        return names[npcID]
    end
    -- Forever's own mobs, named by players where the game names none
    -- (Data/ForeverNpcNames.lua, folded in before each release).
    local forever = ns.FOREVER_NPC_NAMES
    if type(forever) == "table" and type(forever[npcID]) == "string" then
        return forever[npcID]
    end
    local shipped = ns.NPC_NAMES
    return type(shipped) == "table" and shipped[npcID] or nil
end

-- The longest name a player can give a mob.
Harvest.NAME_MOST = 60

--- A name as a player typed it, made safe to keep: trimmed, one line, no
--- colour or link codes, not a number, not too long. Nil when nothing is
--- left.
function Harvest.CleanName(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("|", ""):gsub("[%c]", " "):gsub("%s+", " ")
    text = text:match("^%s*(.-)%s*$")
    if text == "" or text:match("^Creature #") or text:match("^%d+$") then return nil end
    if #text > Harvest.NAME_MOST then return nil end
    return text
end

--- A player names a mob the game will not name (the kills panel's
--- right-click, "Name this mob"). Only a mob still known by its number:
--- one the data or the game already names is left as it is. The panel
--- shows the name at once; the kills and loot kept under the number move to
--- it at the next login (NameUnnamed). Returns the name kept, or nil.
function Harvest:NameByHand(npcID, text)
    npcID = tonumber(npcID)
    local name = Harvest.CleanName(text)
    if not (npcID and name) or Harvest.KnownNpcName(npcID) then return nil end
    local db = ns.db
    if type(db) ~= "table" then return nil end
    if type(db.npcNames) ~= "table" then db.npcNames = {} end
    db.npcNames[npcID] = name
    return name
end

--- What a mob ID is called. The game's own answer, through the unit link
--- the guid makes, is asked once and kept in npcNames, since Forever's
--- names beat Classic's. Inside a dungeon the game gives none (Ragefire
--- Chasm, 2026-10-10), so Classic's name stands in; a mob Forever added has
--- none, and is "Creature #11320", with the ID kept on the record so the
--- name can be put back once it is known (NameUnnamed).
function Harvest:NpcName(npcID, guid)
    local db = ns.db
    local learned = type(db) == "table" and type(db.npcNames) == "table" and db.npcNames[npcID]
    if type(learned) == "string" then return learned end

    local name = Harvest.NameFromLink(guid)
    if name and type(db) == "table" then
        if type(db.npcNames) ~= "table" then db.npcNames = {} end
        db.npcNames[npcID] = name
        return name
    end
    return Harvest.KnownNpcName(npcID) or ("Creature #%d"):format(npcID)
end

--- Keeps what the game called a mob ID the data does not know (one Forever
--- added), in npcNames, so a mob looted where the game hides names (a
--- dungeon) is named by it, and what was kept as "Creature #ID" is named at
--- the next login (NameUnnamed). An ID Classic's list or an earlier answer
--- already names is left alone, so its records keep the name they have.
function Harvest:KeepName(npcID, name)
    local db = ns.db
    if type(npcID) ~= "number" or type(name) ~= "string" or name == "" or type(db) ~= "table" then
        return false
    end
    if name:match("^Creature #") or name == _G.UNKNOWNOBJECT or name == "Unknown" then return false end
    if Harvest.KnownNpcName(npcID) then return false end
    if type(db.npcNames) ~= "table" then db.npcNames = {} end
    db.npcNames[npcID] = name
    self.namesLearned = (self.namesLearned or 0) + 1
    return true
end

--- The name shown for a mob kept as "Creature #ID" once that ID has one;
--- any other name as it is. For showing only: what is kept moves to the
--- name at the next login.
function Harvest.ShowName(mob)
    if type(mob) ~= "string" then return mob end
    local npcID = tonumber(mob:match("^Creature #(%d+)$"))
    return npcID and Harvest.KnownNpcName(npcID) or mob
end

--- A unit's name and guid off the tooltip the game builds for it, for when
--- UnitName or UnitGUID will not say. Either can be nil.
function Harvest.TooltipUnit(unit)
    local info = C_TooltipInfo
    if type(info) ~= "table" or type(info.GetUnit) ~= "function" then return nil end
    local ok, data = pcall(info.GetUnit, unit)
    if not ok or type(data) ~= "table" then return nil end
    local gotGuid, guid = pcall(function() return data.guid end)
    local gotLine, line = pcall(function() return data.lines[1].leftText end)
    return gotLine and Readable(line) or nil, gotGuid and Readable(guid) or nil
end

--- Learns the name of the creature in `unit` whenever the client lets its
--- name and its guid both be read. `deep` also asks the unit's tooltip,
--- which costs more, so only for a target or the mob under the mouse.
function Harvest:LearnName(unit, deep)
    if type(unit) ~= "string" then return false end
    local name, guid
    if UnitGUID then
        local ok, value = pcall(UnitGUID, unit)
        guid = ok and Readable(value) or nil
    end
    -- Only a creature the data cannot name is worth more reading.
    local npcID = Harvest.NpcID(guid)
    if npcID and Harvest.KnownNpcName(npcID) then return false end
    if UnitName then
        local ok, value = pcall(UnitName, unit)
        name = ok and Readable(value) or nil
    end
    if deep and not (name and guid) then
        local tipName, tipGuid = Harvest.TooltipUnit(unit)
        name, guid = name or tipName, guid or tipGuid
        npcID = Harvest.NpcID(guid)
    end
    if not (npcID and name) then return false end
    return self:KeepName(npcID, name)
end

--- The name the game's tooltip gives for a creature guid's unit link, or nil.
function Harvest.NameFromLink(guid)
    local info = C_TooltipInfo
    if type(guid) ~= "string" or type(info) ~= "table"
        or type(info.GetHyperlink) ~= "function" then
        return nil
    end

    local ok, data = pcall(info.GetHyperlink, "unit:" .. guid)
    if not ok or type(data) ~= "table" then return nil end

    local gotLine, line = pcall(function() return data.lines[1].leftText end)
    return gotLine and Readable(line) or nil
end

-- Units that can be the corpse when the target is not: the one under the
-- mouse (a right-click loot) and the interact key's (soft interact).
Harvest.CORPSE_UNITS = { "softinteract", "mouseover" }

--- A dead mob in `unit`, as name, level and guid; nil for anything else.
-- Not `name == ""`: in an instance that comparison is the line that blew
-- up. Comparisons happen inside Readable, where a raise is an answer.
function Harvest:UnitCorpse(unit)
    if not UnitName or not UnitIsDead then return nil end

    local ok, dead = pcall(UnitIsDead, unit)
    if not ok then return nil end
    local plain, isDead = pcall(function() return dead == true or dead == 1 end)
    if not plain or not isDead then return nil end

    local gotName, unitName = pcall(UnitName, unit)
    if not gotName then return nil end

    local name = Readable(unitName)
    if not name then return nil end

    -- Players and their corpses are not farming spots.
    if UnitIsPlayer then
        local gotPlayer, isPlayer = pcall(UnitIsPlayer, unit)
        if gotPlayer then
            local readable, player = pcall(function() return isPlayer == true or isPlayer == 1 end)
            if not readable or player then return nil end
        end
    end

    local level
    if UnitLevel then
        local gotLevel, unitLevel = pcall(UnitLevel, unit)
        local number = gotLevel and ReadableNumber(unitLevel) or nil
        -- -1 is the client's way of saying "higher than you can tell".
        if number and number > 0 then
            level = number
        end
    end

    local guid
    if UnitGUID then
        local gotGuid, unitGuid = pcall(UnitGUID, unit)
        if gotGuid then guid = Readable(unitGuid) end
    end

    return name, level, guid
end

function Harvest:LootSource()
    local name, level = self:Corpse()
    return name, level
end

--------------------------------------------------------------------------------
-- Mobs seen alive
--
-- A guid names no mob by itself, so the mobs you meet are remembered by guid
-- as the client shows them: your target, the mob under the mouse, nameplates
-- coming into view, the interact key's unit. A corpse looted without being
-- targeted is then recognised by the guid the loot window gives for it.
-- Memory only, and kept short: two lots of SEEN_LIMIT at most.
--------------------------------------------------------------------------------

local SEEN_LIMIT = 300

Harvest.seen, Harvest.seenOld, Harvest.seenCount = {}, {}, 0

function Harvest:NoteUnit(unit)
    if not UnitGUID or not UnitName then return end

    local gotGuid, unitGuid = pcall(UnitGUID, unit)
    local guid = gotGuid and Readable(unitGuid) or nil
    if not guid or not guid:match("^Creature%-") and not guid:match("^Vehicle%-") then return end

    local gotName, unitName = pcall(UnitName, unit)
    local name = gotName and Readable(unitName) or nil
    if not name then return end

    -- A mob Forever added: its name, for where the game hides it.
    local npcID = Harvest.NpcID(guid)
    if npcID then self:KeepName(npcID, name) end

    local level
    if UnitLevel then
        local gotLevel, unitLevel = pcall(UnitLevel, unit)
        local number = gotLevel and ReadableNumber(unitLevel) or nil
        if number and number > 0 then level = number end
    end

    -- Seen alive this session: once it is, it stays so after it dies.
    local known = self:KnownUnit(guid)
    local alive = known and known.alive or false
    if not alive and UnitIsDead then
        local gotDead, dead = pcall(UnitIsDead, unit)
        local readable, living = pcall(function() return gotDead and dead == false end)
        alive = readable and living == true
    end

    if not self.seen[guid] then
        self.seenCount = self.seenCount + 1
        if self.seenCount > SEEN_LIMIT then
            self.seenOld, self.seen, self.seenCount = self.seen, {}, 1
        end
    end
    self.seen[guid] = { name = name, level = level, alive = alive or nil }

    -- Its creature type, for the Grind tab (Logic/Grinding.lua).
    if ns.Grinding then ns.Grinding:Learn(unit, name) end
end

function Harvest:KnownUnit(guid)
    if type(guid) ~= "string" then return nil end
    return self.seen[guid] or self.seenOld[guid]
end

--- Did this session see the mob alive? A corpse it never saw alive may be
--- one looted before a /reload, which the addon cannot tell from new.
function Harvest:SeenAlive(guid)
    local known = self:KnownUnit(guid)
    return known ~= nil and known.alive == true
end

--- Where you are standing: the zone, and the subzone if you are in one.
-- Either is nil when the client will not say.
function Harvest:Where()
    local caps = self:Capabilities()
    local zone, location

    if caps.realZone then
        local gotZone, zoneText = pcall(GetRealZoneText)
        if gotZone then zone = Readable(zoneText) end
    end

    if caps.subZone then
        -- Readable answers nil for the empty string a mob outside any
        -- subzone comes back with, which is what this wants anyway.
        local gotSub, subText = pcall(GetSubZoneText)
        if gotSub then location = Readable(subText) end
    end

    return zone, location
end

--- The corpse's guid, if the client will say. Read, not compared.
function Harvest:CorpseID()
    local name, _, guid = self:Corpse()
    if name then return guid end

    if not UnitGUID then return nil end
    local ok, target = pcall(UnitGUID, "target")
    if not ok then return nil end
    return Readable(target)
end

--- Is the open loot window a fishing catch or a gathered herb or vein?
--
-- Either way it is nobody's corpse, whatever is targeted. A herb picked with
-- a looted corpse still targeted used to go down as that corpse's drop.
function Harvest:IsNodeLoot()
    if self:Capabilities().fishingLoot then
        local ok, fishing = pcall(IsFishingLoot)
        if ok then
            -- Read before it is believed, as Fishing:IsCatch does.
            local readable, answer = pcall(function() return fishing == true or fishing == 1 end)
            if readable and answer == true then return true end
        end
    end

    if ns.Gathering ~= nil and ns.Gathering:IsGathering() then return true end

    -- A clam opened from the bags, a Giant Clam or a chest.
    return ns.Containers ~= nil and ns.Containers:Claims() == true
end

-- A guid the client spells "Creature-0-...", "GameObject-0-...": the kinds
-- that can own a loot window.
local GUID_KIND = {
    Creature = true, Vehicle = true, Pet = true, Player = true,
    GameObject = true, Item = true,
}

local function GuidKind(guid)
    local kind = type(guid) == "string" and guid:match("^(%a+)%-") or nil
    return kind and GUID_KIND[kind] and kind or nil
end

--- Every guid the open loot window names as a source, each once, in slot
--- order: the corpses (and chests, and nodes) its loot came off. Empty when
--- the client will not say.
function Harvest:LootSources()
    -- While one loot window is being read every reader asks this many times
    -- over (once per slot, and again per corpse check), and nothing in the
    -- window can change in between, so the first answer serves the rest.
    local reading = self.lootReading
    if reading and reading.sources then return reading.sources end

    local list, seen = {}, {}
    if reading then reading.sources = list end
    if type(GetLootSourceInfo) ~= "function" then return list end

    local gotCount, lootCount = pcall(GetNumLootItems)
    local count = gotCount and ReadableNumber(lootCount) or nil
    if not count then return list end

    for slot = 1, count do
        local ok, sources = pcall(function() return { GetLootSourceInfo(slot) } end)

        -- Guid, quantity, guid, quantity...
        for index = 1, ok and #sources or 0, 2 do
            local guid = Readable(sources[index])
            if GuidKind(guid) and not seen[guid] then
                seen[guid] = true
                list[#list + 1] = guid
            end
        end
    end

    return list
end

--- Does the open loot window belong to `guid`?
--
-- Where the client says whose loot each slot is (GetLootSourceInfo), a window
-- none of whose slots is that unit's -- a chest, a clam opened from the bags,
-- another corpse -- is not its loot. This answers false only on that
-- evidence: guids it cannot read, or a client spelling them some other way,
-- leave it answering true, the way it was before it asked.
function Harvest:LootIsFrom(guid)
    if not GuidKind(guid) then return true end

    local sources = self:LootSources()
    if #sources == 0 then return true end

    for _, source in ipairs(sources) do
        if source == guid then return true end
    end
    return false
end

--- Does the open loot window belong to the corpse being looted? Corpse()
--- only names one it does, so this is whether there is one.
function Harvest:LootIsTargets()
    return (self:Corpse()) ~= nil
end

--- Whether loot slot `slot` came off the corpse you target, and if the
--- client says so, how many of it came off that corpse.
--
-- With area loot one window holds several corpses' drops. Counting them all
-- against the one you clicked would make it look like it dropped three
-- times as much, so a slot whose sources are readable and are all other
-- corpses is left out. Anything unreadable counts, as before: this only
-- ever takes away what the client plainly says is someone else's.
function Harvest:SlotIsTargets(slot)
    if type(GetLootSourceInfo) ~= "function" then return true end

    local target = self:CorpseID()
    if not GuidKind(target) then return true end

    local ok, sources = pcall(function() return { GetLootSourceInfo(slot) } end)
    if not ok then return true end

    local elsewhere = false
    for index = 1, #sources, 2 do
        local guid = Readable(sources[index])
        if guid == target then return true, ReadableNumber(sources[index + 1]) end
        if GuidKind(guid) then elsewhere = true end
    end

    return not elsewhere
end

--------------------------------------------------------------------------------
-- Recording
--------------------------------------------------------------------------------

local function RecordKey(mob, zone, location)
    return ("%s|%s|%s"):format(mob, zone or "?", location or "")
end

-- Adds every number in `from` into `into`, table by table. A kill tally is
-- numbers all the way down, so two tallies of one mob add up this way.
local function AddCounts(into, from)
    for key, value in pairs(from) do
        if type(value) == "number" then
            into[key] = (tonumber(into[key]) or 0) + value
        elseif type(value) == "table" then
            if type(into[key]) ~= "table" then into[key] = {} end
            AddCounts(into[key], value)
        elseif into[key] == nil then
            into[key] = value
        end
    end
end

--- What partners and handouts gave under `from` (shareIn's ledgers, by
--- record key) follows the record to `to`. Left under the old key, the
--- ledger no longer matched: a partner's counts were sent back to them as
--- this side's own, and a handout could not be taken back out. A partner
--- with a ledger under both keys sent the same mob twice, before and after
--- it had a name, so the ledger keeps the larger and what own counts took
--- twice is handed back, for the caller to take off (UndoTwice).
local function MoveCredit(section, from, to)
    local twice = {}
    local share = ns.Share
    local spec = share and share.Parts and share.Parts.BY_KEY[section] and share.Parts.BY_KEY[section].spec
    for _, held in pairs(type(ns.db) == "table" and type(ns.db.shareIn) == "table" and ns.db.shareIn or {}) do
        local credit = type(held) == "table" and type(held.credit) == "table" and held.credit[section]
        local taken = type(credit) == "table" and credit[from]
        if type(taken) == "table" then
            credit[from] = nil
            if type(credit[to]) ~= "table" then
                credit[to] = taken
            elseif spec and share.Combine then
                local hi, lo = share.Combine(spec, credit[to], taken)
                credit[to] = hi
                twice[#twice + 1] = lo
            else
                AddCounts(credit[to], taken)
            end
        end
    end
    return twice, spec
end

--- Takes what MoveCredit found counted twice off the merged record.
local function UndoTwice(record, twice, spec)
    if not (spec and ns.Share and ns.Share.Subtract) then return end
    for _, lo in ipairs(twice) do ns.Share.Subtract(spec, record, lo) end
end

--- Puts names on what was kept as "Creature #ID" once the name is known,
--- in the harvest and the kill tally both, adding it to a record of that
--- name already there. Nothing is dropped: one still nameless stays.
function Harvest:NameUnnamed()
    local moves = {}
    for key, record in pairs(self.records) do
        if Harvest.Unnamed(record) then
            local npcID = tonumber(record.npc) or tonumber(record.mob:match("%d+"))
            local name = npcID and Harvest.KnownNpcName(npcID)
            if name then moves[#moves + 1] = { key = key, record = record, name = name } end
        end
    end

    for _, move in ipairs(moves) do
        local old = move.record
        local key = RecordKey(move.name, old.zone, old.location)
        local into = self.records[key]
        self.records[move.key] = nil
        local twice, spec = MoveCredit("h", move.key, key)

        if not into then
            old.mob = move.name
            self.records[key] = old
            UndoTwice(old, twice, spec)
        else
            into.corpses = (into.corpses or 0) + (old.corpses or 0)
            into.npc = into.npc or old.npc
            into.coords = into.coords or old.coords
            if old.minLevel then into.minLevel = math.min(into.minLevel or old.minLevel, old.minLevel) end
            if old.maxLevel then into.maxLevel = math.max(into.maxLevel or old.maxLevel, old.maxLevel) end
            for itemName, entry in pairs(old.items or {}) do
                local have = into.items[itemName]
                if have then
                    have.corpses = (have.corpses or 0) + (entry.corpses or 0)
                    have.count = (have.count or 0) + (entry.count or 0)
                    have.id = have.id or entry.id
                else
                    into.items[itemName] = entry
                end
            end
            -- Corpses skinned with a Legacy perk stay noted as such.
            if type(old.boosted) == "table" then
                local rank = math.max(tonumber(type(into.boosted) == "table" and into.boosted.rank) or 0,
                    tonumber(old.boosted.rank) or 0)
                if type(into.boosted) ~= "table" then into.boosted = {} end
                AddCounts(into.boosted, old.boosted)
                into.boosted.rank = rank > 0 and rank or nil
            end
            UndoTwice(into, twice, spec)
        end
    end

    local tracker = type(ns.db) == "table" and type(ns.db.tracker) == "table" and ns.db.tracker.mobs
    if type(tracker) == "table" then
        local renames = {}
        for mob, tally in pairs(tracker) do
            local npcID = type(mob) == "string" and tonumber(mob:match("^Creature #(%d+)$"))
            local name = npcID and Harvest.KnownNpcName(npcID)
            if name and type(tally) == "table" then renames[#renames + 1] = { mob = mob, name = name } end
        end
        for _, rename in ipairs(renames) do
            local tally = tracker[rename.mob]
            tracker[rename.mob] = nil
            local twice, spec = MoveCredit("k", rename.mob, rename.name)
            if type(tracker[rename.name]) == "table" then
                -- A tally from before coin was counted over kills is set
                -- aside first, or its old coin was split over the new kills.
                if ns.Tracker and tally.coinKills ~= nil then pcall(ns.Tracker.GetMob, ns.Tracker, rename.name) end
                AddCounts(tracker[rename.name], tally)
            else
                tracker[rename.name] = tally
            end
            UndoTwice(tracker[rename.name], twice, spec)
        end
    end
end

function Harvest:GetRecord(mob, level, zone, location)
    local key = RecordKey(mob, zone, location)
    local record = self.records[key]

    if not record then
        record = {
            mob = mob,
            zone = zone,
            location = location,
            minLevel = level,
            maxLevel = level,
            corpses = 0,
            items = {},
        }
        self.records[key] = record
    end

    -- A mob type spans a level band; widen it as we meet the edges.
    if level then
        record.minLevel = math.min(record.minLevel or level, level)
        record.maxLevel = math.max(record.maxLevel or level, level)
    end

    return record
end

--- Is this loot slot money rather than an item?
--
-- A loot window lists coins in a slot like anything else, and GetLootSlotInfo
-- hands back a name for it -- "23 Copper" -- which went straight into the data
-- as if it were a farmable drop. The first real session produced 25 coin
-- entries out of 53.
--
-- Two ways of telling. GetLootSlotType says so outright and is authoritative
-- where it exists, which on this client is not yet known. Failing that, the
-- name reads as coins -- a weaker test, because a real item could in principle
-- be named that way, and the reason NameLooksLikeMoney is as strict as it is.
--
-- A third test suggests itself and is deliberately not used: money has no item
-- link. That is true of coins, but it is equally true of any item the link
-- call happens to fail for, and it deleted Silver Bar the first time it was
-- tried. Dropping a real drop is worse than keeping a coin.
local COIN = { Copper = 1, Silver = 100, Gold = 10000 }

-- A client in another language names its coins in its own ("23 Kupfer"):
-- its words are read from the game's own COPPER_AMOUNT, SILVER_AMOUNT and
-- GOLD_AMOUNT ("%d Kupfer"), once, beside the English ones.
local coinWords

--- Copper in one `word` coin ("Silver" is 100), or nil for no coin word.
function Harvest.CoinValue(word)
    if not coinWords then
        coinWords = {}
        for english, value in pairs(COIN) do coinWords[english] = value end
        for name, value in pairs({ COPPER_AMOUNT = 1, SILVER_AMOUNT = 100, GOLD_AMOUNT = 10000 }) do
            local format = rawget(_G, name)
            local word = type(format) == "string" and format:match("^%%d%s+(%a+)$")
            if word then coinWords[word] = coinWords[word] or value end
        end
    end
    return coinWords[word]
end

function Harvest:IsMoney(slot, name)
    local caps = self:Capabilities()

    -- Pruning old data has no slot to ask about: the loot window is long
    -- closed. Both slot tests would then be asking about slot nil, and the
    -- link test in particular would answer "no link, so money" for every item
    -- in the database. Skip to the name.
    if slot == nil then return self:NameLooksLikeMoney(name) end

    if caps.lootSlotType then
        local ok, slotType = pcall(GetLootSlotType, slot)
        -- Read before it is compared, like everything else off this client.
        local kind = ok and ReadableNumber(slotType) or nil

        -- LOOT_SLOT_MONEY is 2 on every client that defines it; the constant
        -- itself may not exist here, so compare to both.
        if kind then
            if kind == (LOOT_SLOT_MONEY or 2) then return true end
            if kind == (LOOT_SLOT_ITEM or 1) then return false end
        end
    end

    return self:NameLooksLikeMoney(name)
end

--- "23 Copper", "1 Gold 2 Silver 3 Copper" -- and nothing else.
--
-- Every part of the name has to be a number followed by a coin, with nothing
-- left over, so "Copper Ore" and "10 Pound Sledge" are safely items.
function Harvest:NameLooksLikeMoney(name)
    if type(name) ~= "string" or name == "" then return false end

    local words, coins = 0, 0

    for _, unit in name:gmatch("(%d+)%s+(%a+)") do
        words = words + 1
        if Harvest.CoinValue(unit) then coins = coins + 1 end
    end

    if words == 0 or words ~= coins then return false end

    return (name:gsub("%d+%s+%a+%s*", "")) == ""
end

--- One looted corpse: the denominator of every rate this module reports.
function Harvest:RecordCorpse()
    if not self.enabled then return end

    local caps = self:Capabilities()
    if not caps.usable then return end

    -- Fishing pools, herbs and veins are not mobs.
    if self:IsNodeLoot() then return end

    local mob, level = self:LootSource()
    local _, _, sourceGuid, unit = self:Corpse()
    if not mob or not self:LootIsTargets() then
        self.skipped = (self.skipped or 0) + 1
        return
    end

    -- One corpse opened twice is one corpse. Skinning opens a second loot
    -- window on a corpse already looted, and so does coming back for what
    -- was left; counting each as a corpse would halve every other item's
    -- rate on anything you skin. What the second opening finds -- the leather
    -- -- is still a drop from that corpse and is counted, once.
    --
    -- Without a readable guid (an instance can refuse it) the corpse cannot
    -- be recognised again, so each opening counts as before, apart from a
    -- skinning one, which never starts a corpse (next).
    --
    -- A corpse first opened by skinning is no sample at all: it is another
    -- player's kill, one whose drops an area loot already took with another
    -- corpse's, or one looted before a /reload. Its drops are not in this
    -- window, so counting it would add a corpse that held nothing.
    --
    -- Your own kill that dropped nothing is the exception, as in the kill
    -- tally (Tracker:EmptyOwnKill): it opens no window until the skin, and a
    -- rate has to count the corpses that held nothing.
    --
    -- A corpse whose loot already showed in another corpse's window (area
    -- loot) went with that window. With full bags it keeps what you could
    -- not take, and opening it later, after other loot, counted it as a
    -- second corpse holding its leftovers (2026-10-13). It is no sample.
    local guid = self:CorpseID()
    local corpse = guid and self.opened[guid]
    local record

    -- What else this window shows was looted with it, whichever way it goes.
    self:NoteShown(guid)

    if corpse then
        record = corpse.record
    elseif guid and self.shown[guid] then
        self.skipped = (self.skipped or 0) + 1
        return
    elseif ns.Gathering ~= nil and ns.Gathering:IsSkinning()
        and not (guid and guid == sourceGuid and ns.Tracker
            and ns.Tracker:EmptyOwnKill(guid, unit)) then
        self.skipped = (self.skipped or 0) + 1
        return
    else
        local zone, location = self:Where()

        record = self:GetRecord(mob, level, zone, location)
        record.corpses = record.corpses + 1
        record.npc = record.npc or Harvest.NpcID(sourceGuid)
        -- Moves with every corpse, so views that sum the harvest (world
        -- drops) know when to sum it again.
        Harvest.changes = (Harvest.changes or 0) + 1

        if not record.coords then
            local x, y = self:PlayerPosition()
            if x then record.coords = { x, y } end
        end

        corpse = { record = record, items = {} }
        if guid then
            self.opened[guid] = corpse
            self:Aging():Add(guid)
        end
    end

    -- An item in two slots of one corpse is one corpse that held it, not two.
    -- `counted` spans every opening of this corpse; `seenHere` only this one,
    -- so two slots of the same item now still add up, while leftovers seen
    -- again on a return visit add nothing.
    local counted = corpse.items
    local seenHere = {}

    local gotCount, lootCount = pcall(GetNumLootItems)
    local count = gotCount and ReadableNumber(lootCount) or nil
    if not count then return end

    for slot = 1, count do
        local ok, _, slotName, quantity = pcall(GetLootSlotInfo, slot)

        -- Another corpse's drop in the same window (area loot) is not this
        -- one's; where the client gives this corpse's share, that is it.
        local ours, share = self:SlotIsTargets(slot)
        if share then quantity = share end

        -- An unreadable loot name loses that one slot. The corpse itself is
        -- already counted, and the rest of the window is still worth reading.
        local name = ours and ok and Readable(slotName) or nil

        local already = name and counted[name] and not seenHere[name]

        if name and not already and not self:IsMoney(slot, name) then
            local entry = record.items[name]

            if not entry then
                entry = { name = name, count = 0, corpses = 0 }
                record.items[name] = entry
            end

            entry.count = entry.count + (ReadableNumber(quantity) or 1)
            corpse.counts = corpse.counts or {}
            corpse.counts[name] = (corpse.counts[name] or 0) + (ReadableNumber(quantity) or 1)

            if not seenHere[name] then
                seenHere[name] = true
                counted[name] = true
                entry.corpses = entry.corpses + 1
            end

            if not entry.id and caps.lootSlotLink then
                local gotLink, link = pcall(GetLootSlotLink, slot)
                -- The link comes from the same restricted source as the name,
                -- so it is read the same way before anything matches on it.
                local text = gotLink and Readable(link) or nil
                if text then
                    entry.id = tonumber(text:match("item:(%d+)"))
                end
            end
        end
    end

    -- Skinned with Bountiful Harvest: the whole corpse is noted beside the
    -- record, so it never reaches anyone's rates (Logic/Legacy.lua).
    local skinning = ns.Gathering ~= nil and ns.Gathering:IsSkinning()
    local boost = skinning and ns.Legacy and ns.Legacy:GatherBoost("skin")
    if boost or corpse.boosted then self:NoteBoosted(record, corpse, boost) end

    self.dirty = true
    -- What the goal arrow's ranking was made from moved (Arrow:Sources).
    self.changes = (self.changes or 0) + 1
end

--- Move one corpse skinned with Bountiful Harvest into its record's
--- `boosted` tally: the corpse once, and everything it gave, every opening
--- of it (Logic/Legacy.lua). A later opening of the same corpse moves what
--- it adds too.
function Harvest:NoteBoosted(record, corpse, rank)
    local boosted = ns.Legacy.Boosted(record, "corpses")
    if rank then boosted.rank = math.max(tonumber(boosted.rank) or 0, rank) end

    if not corpse.boosted then
        corpse.boosted = {}
        boosted.corpses = boosted.corpses + 1
    end

    for name, total in pairs(corpse.counts or {}) do
        local moved = corpse.boosted[name]
        local item = boosted.items[name]
        if type(item) ~= "table" then
            item = { corpses = 0, count = 0 }
            boosted.items[name] = item
        end
        if moved == nil then
            item.corpses = (tonumber(item.corpses) or 0) + 1
            moved = 0
        end
        item.count = (tonumber(item.count) or 0) + total - moved
        corpse.boosted[name] = total
    end
end

--- The records the export is made from: Harvest's own, less every corpse
--- skinned with a Legacy perk.
function Harvest:ExportRecords()
    return ns.Legacy and ns.Legacy.WithoutAll(self.records, "corpses") or self.records
end

--------------------------------------------------------------------------------
-- Random suffixes
--------------------------------------------------------------------------------

-- Gear with a random suffix drops under its whole name, "Lead Band of the
-- Monkey", "Lead Band of the Owl", so one green spread over its suffixes
-- took far longer to reach a rate. A player asked (2026-10-15) for them to
-- count as one item. The saved records are never rewritten: each suffix
-- stays under its own name, and the readers below put them together under
-- the item's own name (Harvest:GroupedItems, Tracker:Summary).

-- When nothing else names the item (a tool reading the save, with no
-- client): Classic's two-stat suffixes, the only ones a name alone can be
-- trusted to end with.
Harvest.ROLL_ANIMALS = {
    Bear = true, Boar = true, Eagle = true, Falcon = true, Gorilla = true,
    Monkey = true, Owl = true, Tiger = true, Whale = true, Wolf = true,
}

-- name -> the item's own name, or false for a name that is the item's own.
Harvest.rollBase = {}

--- The item's own name as the client gives it, or nil while it is not
--- loaded; and as the data has it.
local function OwnNames(id)
    local client
    local api = _G.C_Item
    for _, get in ipairs({ type(api) == "table" and api.GetItemNameByID,
        type(api) == "table" and api.GetItemInfo, _G.GetItemInfo }) do
        if not client and type(get) == "function" then
            local ok, name = pcall(get, id)
            if ok and type(name) == "string" and name ~= "" then client = name .. "" end
        end
    end
    local DB = ns.DB
    local byID = DB and DB.ByID and DB:ByID()
    local item = type(byID) == "table" and byID[id]
    local data = type(item) == "table" and type(item.name) == "string" and item.name or nil
    return client, data
end

-- A suffix follows the item's own name, in any language.
local function Prefixes(own, name)
    return type(own) == "string" and #own < #name and name:sub(1, #own + 1) == own .. " "
end

--- The item's own name when `name` is one of its random suffixes ("Lead
--- Band" for "Lead Band of the Monkey"), else nil. `id` is the item ID the
--- loot link gave. Kept per name once known.
function Harvest.RollBase(name, id)
    if type(name) ~= "string" then return nil end
    local known = Harvest.rollBase[name]
    if known ~= nil then return known or nil end

    id = tonumber(id)
    if not id then return nil end

    local client, data = OwnNames(id)
    local base
    if client == name then
        Harvest.rollBase[name] = false
        return nil
    elseif Prefixes(client, name) then
        base = client
    elseif Prefixes(data, name) then
        base = data
    else
        -- The data can name the item by one of its suffixes (what was
        -- harvested before), so only these two stats are read off the name.
        local stem, animal = name:match("^(.+) of the (%a+)$")
        if stem and Harvest.ROLL_ANIMALS[animal] then base = stem end
    end

    -- Only an answer is kept: an item the client has not loaded yet may
    -- still name itself on the next look.
    if base then
        Harvest.rollBase[name] = base
    elseif client then
        Harvest.rollBase[name] = false
    end
    return base
end

-- Per record: its items with each item's suffixes put together, kept until
-- the record's corpses move.
local groupedCache = setmetatable({}, { __mode = "k" })

--- A record's items with random suffixes counted as their item, as
--- `record.items` is shaped ({ [name] = { name, id, count, corpses } }).
--- The record's own table when it holds no suffix. Nothing is written.
function Harvest:GroupedItems(record)
    local items = type(record) == "table" and record.items
    if type(items) ~= "table" then return {} end

    local kept = groupedCache[record]
    if kept and kept.corpses == record.corpses and kept.items == items then return kept.grouped end

    local grouped, folded = nil, false
    for name, entry in pairs(items) do
        local base = type(entry) == "table" and Harvest.RollBase(name, entry.id)
        if base then folded = true break end
    end

    if not folded then
        grouped = items
    else
        grouped = {}
        for name, entry in pairs(items) do
            if type(entry) == "table" then
                local key = Harvest.RollBase(name, entry.id) or name
                local into = grouped[key]
                if not into then
                    into = { name = key, id = entry.id, count = 0, corpses = 0 }
                    grouped[key] = into
                end
                into.id = into.id or entry.id
                into.count = into.count + (tonumber(entry.count) or 0)
                -- A corpse holds one suffix of an item, so corpses add up.
                into.corpses = into.corpses + (tonumber(entry.corpses) or 0)
                if key ~= name then into.suffixes = (into.suffixes or 0) + 1 end
            end
        end
        -- A suffix and the item seen under its own name on one corpse
        -- would count it twice; never more corpses than the record has.
        for _, into in pairs(grouped) do
            local most = tonumber(record.corpses)
            if most and into.corpses > most then into.corpses = most end
        end
    end

    groupedCache[record] = { corpses = record.corpses, items = items, grouped = grouped }
    return grouped
end

--------------------------------------------------------------------------------
-- Reading it back
--------------------------------------------------------------------------------

function Harvest:CountCorpses(records)
    local total = 0
    for _, record in pairs(records or self.records) do
        total = total + record.corpses
    end
    return total
end

--- How many mobs, by name. A mob looted in two places keeps a record for
--- each, but it is still one mob.
function Harvest:CountMobs(records)
    local seen, total = {}, 0
    for _, record in pairs(records or self.records) do
        if not seen[record.mob] then
            seen[record.mob] = true
            total = total + 1
        end
    end
    return total
end

--- Everything seen for one item, best-sampled first. `records` are
--- Harvest's own unless given (the export's, ExportRecords).
function Harvest:ForItem(itemName, records)
    local rows = {}

    for _, record in pairs(records or self.records) do
        local entry = self:GroupedItems(record)[itemName]

        if entry then
            -- Not rounded: one in 300 is a third of a percent, not 0. Shown
            -- through Tracker.FormatChance, which says "<1%".
            rows[#rows + 1] = {
                record = record,
                entry = entry,
                chance = entry.corpses / record.corpses * 100,
            }
        end
    end

    table.sort(rows, function(a, b)
        if a.record.corpses ~= b.record.corpses then
            return a.record.corpses > b.record.corpses
        end
        if a.record.mob ~= b.record.mob then return a.record.mob < b.record.mob end
        -- One mob in two places with as many corpses each: the same order
        -- every time, so an export does not shuffle its rows.
        if (a.record.zone or "") ~= (b.record.zone or "") then
            return (a.record.zone or "") < (b.record.zone or "")
        end
        return (a.record.location or "") < (b.record.location or "")
    end)

    return rows
end

--- The harvested item a typed name means.
--
-- Exact first, then a prefix, then anything containing it, so "wool" finds
-- Wool Cloth without "cloth" silently picking whichever cloth sorts first.
-- Returns nil rather than guessing when more than one item matches loosely.
function Harvest:ResolveItem(text)
    text = tostring(text or ""):lower()
    if text == "" then return nil end

    local items = self:Items()
    local prefixes, contains = {}, {}

    for _, item in ipairs(items) do
        local name = item.name:lower()

        if name == text then
            return item.name
        elseif name:sub(1, #text) == text then
            prefixes[#prefixes + 1] = item.name
        elseif name:find(text, 1, true) then
            contains[#contains + 1] = item.name
        end
    end

    if #prefixes == 1 then return prefixes[1] end
    if #prefixes == 0 and #contains == 1 then return contains[1] end

    -- More than one fits: say which, rather than picking one.
    local candidates = #prefixes > 0 and prefixes or contains
    if #candidates > 1 then
        table.sort(candidates)
        return nil, candidates
    end
    return nil
end

--- Every item seen, with how many corpses back each one.
function Harvest:Items(records)
    local items, order = {}, {}

    for _, record in pairs(records or self.records) do
        for name, entry in pairs(self:GroupedItems(record)) do
            if not items[name] then
                items[name] = { name = name, corpses = 0, count = 0 }
                order[#order + 1] = items[name]
            end

            items[name].corpses = items[name].corpses + entry.corpses
            items[name].count = items[name].count + entry.count
        end
    end

    table.sort(order, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)

    return order
end

function Harvest:Reset()
    -- Shared and imported counts went with the records: their ledgers too.
    if ns.Share and ns.Share.ForgetSection then ns.Share:ForgetSection("h") end
    self.records = {}
    self.opened = {}
    self.shown = {}
    if self.aging then self.aging:Clear() end
    self.skipped = 0
    self.dirty = true
    self.changes = (self.changes or 0) + 1
    self:Persist()
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------

local function Escape(text)
    return (tostring(text):gsub("\\", "\\\\"):gsub('"', '\\"'))
end

--- One item as a data-file entry, ready to paste into Data/.
--
-- Rows come out marked provenance = "forever": they were measured on this
-- client, which is exactly what that marker is for.
--- A record kept under "Creature #11320" because the game would not name
--- the mob. It stays in the save, ID and all, but is no use as data until
--- the name is known, so it is not exported.
function Harvest.Unnamed(record)
    return type(record.mob) == "string" and record.mob:match("^Creature #%d+$") ~= nil
end

function Harvest:ExportItem(itemName, records)
    local rows = {}
    for _, row in ipairs(self:ForItem(itemName, records or self:ExportRecords())) do
        if not Harvest.Unnamed(row.record) then rows[#rows + 1] = row end
    end
    if #rows == 0 then return nil end

    local out = {}
    local id

    for _, row in ipairs(rows) do
        id = id or row.entry.id
    end

    out[#out + 1] = "DB:RegisterItem({"
    out[#out + 1] = ('    name = "%s",'):format(Escape(itemName))

    if id then
        out[#out + 1] = ("    id = %d,"):format(id)
    end

    out[#out + 1] = "    sources = {"

    for _, row in ipairs(rows) do
        local record = row.record
        local fields = {}

        fields[#fields + 1] = ('name = "%s"'):format(Escape(record.mob))
        fields[#fields + 1] = ('zone = "%s"'):format(Escape(record.zone or "?"))

        if record.location then
            fields[#fields + 1] = ('location = "%s"'):format(Escape(record.location))
        end

        if record.coords then
            fields[#fields + 1] = ("coords = { %.1f, %.1f }")
                :format(record.coords[1], record.coords[2])
        end

        if record.minLevel then
            fields[#fields + 1] = ("minLevel = %d"):format(record.minLevel)
            fields[#fields + 1] = ("maxLevel = %d"):format(record.maxLevel or record.minLevel)
        end

        -- A rate off five corpses is a number pretending to be evidence.
        local chance = record.corpses >= MIN_SAMPLE
            and Harvest.ExportChance(row.entry.corpses / record.corpses * 100)
        if chance then fields[#fields + 1] = chance end

        fields[#fields + 1] = 'provenance = "forever"'

        out[#out + 1] = ("        { %s },"):format(table.concat(fields, ", "))

        if record.corpses >= MIN_SAMPLE then
            out[#out + 1] = ("            -- %d of %d corpses"):format(
                row.entry.corpses, record.corpses)
        else
            out[#out + 1] = ("            -- %d of %d corpses: too few for a rate")
                :format(row.entry.corpses, record.corpses)
        end
    end

    out[#out + 1] = "    },"
    out[#out + 1] = "})"

    return table.concat(out, "\n")
end

--- Everything harvested, as one pasteable block.
--
-- `opts.generated` says this is being written to a file by a tool rather than
-- copied out of the window by hand, which changes only the header: one tells
-- you what to do with it, the other tells the next reader not to hand-edit it.
function Harvest:ExportAll(opts)
    opts = opts or {}

    -- Corpses skinned with a Legacy perk are left out of every rate.
    local records = self:ExportRecords()
    local items = self:Items(records)

    -- Catches go in the same file, as fishing rows (Logic/Fishing.lua).
    local fishing = ns.Fishing and ns.Fishing:ExportBlocks()

    if #items == 0 and not fishing then
        return "-- Nothing harvested yet. Go and kill something."
    end

    local out = {
        "-- Harvested on WoW: Forever by Blackthornes Farmer.",
        ("-- %d mobs, %d corpses looted."):format(self:CountMobs(records), self:CountCorpses(records)),
    }

    -- Its own line, so tools/harvest_import.py can check casts never shrink
    -- the way it checks corpses.
    if fishing then
        out[#out + 1] = ("-- %d fishing casts."):format(ns.Fishing:CountCasts(true))
    end

    out[#out + 1] = "--"

    if opts.generated then
        out[#out + 1] = "-- Generated by tools/harvest_import.py from your SavedVariables."
        out[#out + 1] = "-- Do not edit by hand: the next import overwrites this file."
    else
        out[#out + 1] = "-- Paste into a file under Data/ and add it to the .toc."
    end

    out[#out + 1] = ""
    out[#out + 1] = "local _, ns = ..."
    out[#out + 1] = ""
    out[#out + 1] = "local DB = ns.DB"
    out[#out + 1] = ""

    for _, item in ipairs(items) do
        -- Herbs and ore count per node, never as a mob's drop. One the seed
        -- data knows only from nodes was picked with a corpse targeted, by a
        -- version before Logic/Gathering.lua, and stays out of the data.
        local nodeOnly = ns.Gathering ~= nil and ns.Gathering.IsNodeOnly(item.name)
        local block = not nodeOnly and self:ExportItem(item.name, records)
        if block then
            out[#out + 1] = block
            out[#out + 1] = ""
        end
    end

    if fishing then
        out[#out + 1] = "-- Fishing"
        out[#out + 1] = ""
        out[#out + 1] = fishing
    end

    -- The creature types read off these mobs in game, for the Grind tab.
    local types = ns.Grinding and ns.Grinding:ExportBlock()
    if types then
        out[#out + 1] = ""
        out[#out + 1] = "-- Creature types, as the game named them"
        out[#out + 1] = ""
        out[#out + 1] = types
    end

    -- Green gear and better by mob level, for the world drop chances.
    local world = ns.WorldDrops and ns.WorldDrops:ExportBlock()
    if world then
        out[#out + 1] = ""
        out[#out + 1] = "-- World drops, green and better, by mob level"
        out[#out + 1] = ""
        out[#out + 1] = world
    end

    return table.concat(out, "\n")
end

--------------------------------------------------------------------------------
-- Saved variables
--
-- The harvest lives in SavedVariables and keeps growing from one session to
-- the next: Restore reads it at login, and ns.db.harvest is the very table
-- RecordCorpse adds to, so whatever the client writes -- at logout, at /reload
-- -- is the whole total, not one session of it.
--
-- Until the Forever patch of 2026-09-24 the client never read saved variables
-- back, and the running total had to be kept outside the game by the import
-- tool. What it had gathered by then arrives once, from
-- Data/Harvest_Carryover.lua; see ApplyCarryover.
--------------------------------------------------------------------------------

--- Drop coin entries an older version recorded as items.
--
-- Slot numbers are long gone by the time this runs, so it can only go on the
-- name -- which is what IsMoney falls back to anyway.
function Harvest:PruneMoney()
    local dropped = 0

    for _, record in pairs(self.records) do
        for name in pairs(record.items) do
            if self:IsMoney(nil, name) then
                record.items[name] = nil
                dropped = dropped + 1
            end
        end
    end

    return dropped
end

--- Add one spot's record into this harvest, as if its corpses were looted here.
--
-- The same rules tools/harvest_import.py used to merge sessions with: corpse
-- and item counts add up, the level band widens to cover both, and the first
-- coordinates seen for a camp are kept. The incoming record is copied, never
-- shared, so the carryover table itself is left exactly as shipped.
function Harvest:MergeRecord(key, incoming)
    if type(incoming) ~= "table" or not incoming.mob then return end

    local existing = self.records[key]

    if not existing then
        existing = {
            mob = incoming.mob,
            zone = incoming.zone,
            location = incoming.location,
            corpses = 0,
            items = {},
        }
        self.records[key] = existing
    end

    existing.corpses = (existing.corpses or 0) + (incoming.corpses or 0)

    if not existing.coords and type(incoming.coords) == "table" then
        existing.coords = { incoming.coords[1], incoming.coords[2] }
    end

    for _, field in ipairs({ "minLevel", "maxLevel" }) do
        local theirs = incoming[field]
        if theirs then
            local mine = existing[field]
            local pick = field == "minLevel" and math.min or math.max
            existing[field] = mine and pick(mine, theirs) or theirs
        end
    end

    for name, arriving in pairs(incoming.items or {}) do
        local held = existing.items[name]

        if not held then
            held = { name = arriving.name or name, count = 0, corpses = 0 }
            existing.items[name] = held
        end

        held.count = held.count + (arriving.count or 0)
        held.corpses = held.corpses + (arriving.corpses or 0)
        held.id = held.id or arriving.id
    end
end

--- Fold in what was harvested before saved variables worked, exactly once.
--
-- The save is stamped with the carryover's id in the same step, so the next
-- login finds the stamp and adds nothing. If the client ever stops reading
-- saved variables back again, the stamp is lost along with the harvest and
-- the carryover comes back in on its own, which is the right answer then too.
function Harvest:ApplyCarryover()
    local carryover = ns.HarvestCarryover

    if type(carryover) ~= "table" or type(carryover.records) ~= "table" then
        return 0
    end

    if ns.db.harvestCarryover == carryover.id then return 0 end

    local added = 0

    for key, record in pairs(carryover.records) do
        self:MergeRecord(key, record)
        added = added + (record.corpses or 0)
    end

    ns.db.harvestCarryover = carryover.id

    return added
end

--- Load the saved harvest. Returns how many spots came back.
function Harvest:Restore()
    if not ns.db then return 0 end

    local restored = 0

    if type(ns.db.harvest) == "table" then
        for key, record in pairs(ns.db.harvest) do
            if type(record) == "table" and record.mob and record.corpses then
                self.records[key] = record
                restored = restored + 1
            end
        end
    end

    -- Versions before 2026-09-21 recorded coins as items.
    self:PruneMoney()

    self.carriedOver = self:ApplyCarryover()

    -- Dungeon mobs kept as "Creature #ID" get their names where now known.
    self:NameUnnamed()

    -- Left behind by the version that worked around the client bug. Nothing
    -- reads it any more.
    ns.db.harvestRestored = nil

    self:Persist()

    return restored
end

--- Point the saved harvest at the live one.
--
-- They are the same table from here on, so everything looted is already in
-- what the client writes, whenever it writes it.
function Harvest:Persist()
    if not ns.db then return end
    ns.db.harvest = self.records
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Harvest:OnInitialize()
    local restored = self:Restore()

    if restored > 0 then
        ns.Debug(("restored %d harvested mobs"):format(restored))
    end

    if (self.carriedOver or 0) > 0 then
        ns.Print(L.Format("added %d corpses you looted before saving worked. /farm harvest shows the total.",
            self.carriedOver))
    end
end

function Harvest:OnEnable()
    -- The loot check reads any loot window, even where harvesting cannot.
    ns.OnLootWindow(self, function() Harvest:RunArmedCheck() end)

    local caps = self:Capabilities()

    if not caps.usable then
        ns.Debug("this client does not expose the loot API; harvesting is off")
        self.enabled = false
        return
    end

    -- Paused on purpose, from the settings page or /farm harvest off.
    if ns.db and ns.db.harvestPaused then
        self.enabled = false
    end

    ns.OnLootWindow(self, function() Harvest:RecordCorpse() end)

    -- The mobs you meet, so a corpse looted untargeted is still known.
    ns.RegisterEvent(self, "PLAYER_TARGET_CHANGED", function()
        Harvest:NoteUnit("target")
        Harvest:LearnName("target", true)
        Harvest:NotePicked()
    end)
    ns.RegisterEvent(self, "UPDATE_MOUSEOVER_UNIT", function()
        Harvest:NoteUnit("mouseover")
        Harvest:LearnName("mouseover", true)
    end)
    -- Pick Pocket's window is a living mob's, never a kill: SENT where the
    -- client says it first, SUCCEEDED where it does not.
    ns.RegisterPlayerEvent(self, "UNIT_SPELLCAST_SENT", function(_, _, unit, _, _, spellID)
        Harvest:OnPlayerCast(unit, spellID)
    end)
    ns.RegisterPlayerEvent(self, "UNIT_SPELLCAST_SUCCEEDED", function(_, _, unit, _, spellID)
        Harvest:OnPlayerCast(unit, spellID)
    end)
    ns.RegisterEvent(self, "PLAYER_SOFT_ENEMY_CHANGED", function() Harvest:NoteUnit("softenemy") end)
    ns.RegisterEvent(self, "PLAYER_SOFT_INTERACT_CHANGED", function() Harvest:NoteUnit("softinteract") end)
    ns.RegisterEvent(self, "NAME_PLATE_UNIT_ADDED", function(_, _, unit)
        if type(unit) == "string" then Harvest:NoteUnit(unit) end
    end)

    -- ns.db.harvest already is the live table, so this only matters if
    -- something replaced one or the other. Cheap insurance at the one moment
    -- the client is certain to save.
    ns.RegisterEvent(self, "CHAT_MSG_COMBAT_XP_GAIN", function(_, _, message)
        Harvest:NoteKillLine(message)
    end)
    ns.RegisterEvent(self, "PLAYER_LOGOUT", function() Harvest:Persist() end)
end

--------------------------------------------------------------------------------
-- Loot check
--
-- Inside a dungeon (first noticed in the Ruins of Lordaeron, 2026-10-10;
-- any dungeon or raid can do it) nothing gets recorded: the client hides the mob's name, and a corpse with no readable
-- name is dropped. Which of the other values it still lets an addon read is
-- not known, and that decides what a fix can use. So `/farm harvest check`
-- arms a check, and the next loot window opened prints, for each value the
-- harvest reads, whether it came back readable, secret, or not at all. The
-- lines are kept through ns.KeepCheck as lastProbe, for Claude to read.
--
-- It only reads, and every value goes through Describe, inside a pcall.
-- A player's name is never printed: a unit that is a player says so instead.
--------------------------------------------------------------------------------

-- How many loot slots it describes, so area loot cannot flood chat.
Harvest.CHECK_SLOTS = 8
-- How many live nameplates it describes.
Harvest.CHECK_PLATES = 3

local function PlateOf(unit)
    local plates = _G.C_NamePlate
    local forUnit = type(plates) == "table" and plates.GetNamePlateForUnit
    if type(forUnit) ~= "function" then return nil end
    local ok, plate = pcall(forUnit, unit)
    return ok and type(plate) == "table" and plate or nil
end

--- What a value off the client looks like to this addon: its text, or
--- "secret", "unreadable" or "nil". Never raises.
function Harvest.Describe(value)
    local kind = type(value)
    if kind == "nil" then return "nil" end

    local isSecret = _G.issecretvalue
    if type(isSecret) == "function" then
        local ok, secret = pcall(isSecret, value)
        if ok and secret == true then return "secret" end
    end

    local ok, text = pcall(function()
        local copy = tostring(value) .. ""
        if copy == "" then return "(empty)" end
        return copy
    end)
    if not ok or type(text) ~= "string" then return "unreadable (" .. kind .. ")" end
    return text
end

-- Every value a client call hands back, described, or why the call failed.
local function Call(name, ...)
    local fn = _G[name]
    if type(fn) ~= "function" then return "no such call" end

    local results = { pcall(fn, ...) }
    if not results[1] then return "raised" end

    local parts = {}
    for i = 2, math.max(#results, 2) do
        parts[#parts + 1] = Harvest.Describe(results[i])
    end
    return table.concat(parts, ", ")
end

local function Line(label, text)
    ns.PrintRaw(("  %s: %s"):format(label, text))
end

local function DescribeUnit(unit)
    local gotPlayer, isPlayer = pcall(UnitIsPlayer or function() return false end, unit)
    local readable, player = pcall(function() return isPlayer == true or isPlayer == 1 end)
    if gotPlayer and readable and player then
        Line(unit, "a player (left out)")
        return
    end

    Line(unit .. " name", Call("UnitName", unit))
    Line(unit .. " guid", Call("UnitGUID", unit))
    Line(unit .. " level", Call("UnitLevel", unit))
    Line(unit .. " dead", Call("UnitIsDead", unit))
    Line(unit .. " type", Call("UnitCreatureType", unit))
    local tipName, tipGuid = Harvest.TooltipUnit(unit)
    Line(unit .. " tooltip", ("%s, %s"):format(tipName and "name read" or "no name",
        tipGuid and "guid read" or "no guid"))
end

function Harvest:LootCheck()
    -- Which dungeon, first, so results from different ones can be told apart.
    -- Nothing here is about one dungeon: the same reads run in any of them.
    local gotInfo, instanceName, instanceType = pcall(GetInstanceInfo or error)
    local place = gotInfo and Readable(instanceName) or nil
    ns.Print(("loot check in %s (%s), for the loot window just opened:"):format(
        place or "an unnamed place", gotInfo and Harvest.Describe(instanceType) or "type unknown"))

    Line("secret test", type(_G.issecretvalue) == "function" and "yes" or "no")
    Line("in instance", Call("IsInInstance"))
    Line("instance info", Call("GetInstanceInfo"))
    Line("zone", Call("GetRealZoneText"))
    Line("subzone", Call("GetSubZoneText"))
    local mapID = C_Map and C_Map.GetBestMapForUnit
    local gotMap, map = pcall(mapID or error, "player")
    Line("map", gotMap and Harvest.Describe(map) or "raised")
    local x, y = self:PlayerPosition()
    Line("position", x and ("%.1f, %.1f"):format(x, y) or "none")
    Line("fishing loot", Call("IsFishingLoot"))

    for _, unit in ipairs({ "target", "mouseover", "softinteract" }) do
        DescribeUnit(unit)
    end

    -- Live mobs' nameplates, for the kill count beside them: it can only
    -- show over a mob whose name or ID the plate lets an addon read.
    local plates = ns.KillPlates and ns.KillPlates.Units and ns.KillPlates:Units() or {}
    Line("nameplates", tostring(#plates))
    for i = 1, math.min(#plates, Harvest.CHECK_PLATES) do
        local unit = plates[i]
        DescribeUnit(unit)
        local shown = ns.KillPlates:Shown(PlateOf(unit))
        Line(unit .. " kill count", shown and "shown" or "not shown")
    end

    local gotCount, lootCount = pcall(GetNumLootItems or error)
    local count = gotCount and ReadableNumber(lootCount) or nil
    Line("loot slots", gotCount and Harvest.Describe(lootCount) or "raised")
    if count == 0 then
        Line("note", "this window was empty: loot one that drops something")
    end
    -- How often fast looting got there first (Core/Init.lua, ns.OnLootWindow).
    local windows = ns.lootWindows
    if windows then
        Line("loot windows this session", ("%d read, %d empty when first ready"):format(windows.read, windows.empty))
    end

    for slot = 1, math.min(count or 0, Harvest.CHECK_SLOTS) do
        Line(("slot %d info"):format(slot), Call("GetLootSlotInfo", slot))
        Line(("slot %d link"):format(slot), Call("GetLootSlotLink", slot))
        Line(("slot %d type"):format(slot), Call("GetLootSlotType", slot))
        Line(("slot %d sources"):format(slot), Call("GetLootSourceInfo", slot))
    end

    for _, source in ipairs(self:LootSources()) do
        local npcID = Harvest.NpcID(source)
        if npcID then
            Line(("mob %d by link"):format(npcID), Harvest.NameFromLink(source) or "not given")
        end
    end

    -- What the harvest itself makes of it, which is the answer that matters.
    local name, level, guid, unit = self:Corpse()
    Line("harvest corpse", name and ("%s, level %s, %s, via %s"):format(
        name, tostring(level or "?"), guid and "guid read" or "no guid",
        unit or "a mob seen alive") or "none: this corpse would be skipped")
    local zone, location = self:Where()
    Line("harvest place", ("%s / %s"):format(zone or "none", location or "none"))
    Line("mobs seen alive", tostring(self.seenCount or 0))
    Line("names learned this session", tostring(self.namesLearned or 0))
    local kill = self.killLine
    local gotNow, now = pcall(GetTime or error)
    local ago = kill and kill.at and gotNow and type(now) == "number"
        and (" %d s ago"):format(math.floor(now - kill.at)) or ""
    Line("kill chat line", kill and (kill.state .. (kill.name and (": " .. kill.name) or "") .. ago)
        or "none seen this session")
    -- Picked is when the target last changed; the same unit since then.
    local picked = self.picked
    Line("target name when picked", picked and picked
        or picked == false and "hidden then too" or "no target picked")
end

--- The target's name as it read the moment it was picked, for the loot
--- check. A dungeon hides the name of a dead target (Ragefire Chasm,
--- 2026-10-10); whether it hid it while the mob was alive and just
--- targeted decides whether a fix can carry the name over to the corpse.
function Harvest:NotePicked()
    local gotName, unitName = pcall(UnitName or error, "target")
    local name = gotName and Readable(unitName) or nil
    if name then
        self.picked = name
    elseif gotName and type(unitName) ~= "nil" then
        self.picked = false
    else
        self.picked = nil
    end
end

--- The last kill line in chat ("Broodling dies, you gain 45 experience."),
--- for the loot check: whether a dungeon hides the mob's name there too.
--- Only what it looked like is kept, for this session; nothing is learned
--- from it yet.
function Harvest:NoteKillLine(message)
    local state, name
    local isSecret = _G.issecretvalue
    if type(isSecret) == "function" then
        local ok, secret = pcall(isSecret, message)
        if ok and secret == true then state = "secret" end
    end
    if not state then
        local parse = ns.XP and ns.XP.ParseKill
        local ok, found = pcall(parse or error, message)
        name = ok and Readable(found) or nil
        if name then
            state = "name read"
        elseif type(message) ~= "nil" and not Readable(message) then
            state = "secret"
        else
            state = "not understood"
        end
    end
    local gotTime, now = pcall(GetTime or error)
    self.killLine = { state = state, name = name, at = gotTime and now or nil }
end

--- Runs the check on this loot window if one was asked for.
function Harvest:RunArmedCheck()
    if not self.checkArmed then return end
    self.checkArmed = nil
    ns.KeepCheck("harvest check", Harvest.LootCheck, Harvest)
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

ns.RegisterCommand("harvest", L["what you've looted as you played (check shows what the next loot window lets Farmer read)"], function(rest)
    local argument = Util.Trim(rest):lower()

    -- The harvest is the whole history now, not one session, and a reset is
    -- saved at the next logout like anything else. So it takes two words.
    if argument == "reset" then
        ns.Print(L.Format("this deletes all %s you have recorded, for good. Type /farm harvest reset confirm to do it.",
            Util.Plural(ns.Harvest:CountCorpses(), L["corpse"], L["corpses"])))
        return
    end

    if argument == "reset confirm" then
        ns.Harvest:Reset()
        ns.Print(L["your loot counts are cleared."])
        return
    end

    if argument == "check" then
        ns.Harvest.checkArmed = true
        ns.Print(L["loot check ready. Loot a corpse and it runs on that loot window."])
        return
    end

    if argument == "off" then
        ns.Harvest.enabled = false
        ns.db.harvestPaused = true
        ns.Print(L["loot recording paused. /farm harvest on starts it again."])
        return
    end

    if argument == "on" then
        ns.db.harvestPaused = false
        ns.Harvest.enabled = ns.Harvest:Capabilities().usable and true or false
        ns.Print(L["loot recording on."])
        return
    end

    local corpses = ns.Harvest:CountCorpses()

    if corpses == 0 then
        if not ns.Harvest:Capabilities().usable then
            ns.Print(L["this game client doesn't let addons read loot, so nothing is being recorded."])
        else
            ns.Print(L["nothing recorded yet. Loot some corpses first."])
        end
        return
    end

    ns.Print(L.Format("%s looted across %s:",
        Util.Plural(corpses, L["corpse"], L["corpses"]), Util.Plural(ns.Harvest:CountMobs(), L["mob"], L["mobs"])))

    local items = ns.Harvest:Items()

    for index = 1, math.min(#items, 12) do
        local item = items[index]
        ns.PrintRaw(("  %s %s  %s"):format(
            Util.Colored("accent", tostring(item.count)),
            Util.ColorItem(item.name, item.id),
            Util.Colored("muted", L.Format("from %s", Util.Plural(item.corpses, L["corpse"], L["corpses"])))))
    end

    if #items > 12 then
        ns.PrintRaw(Util.Colored("muted", L.Format("  ... and %d more items", #items - 12)))
    end

    ns.PrintRaw(Util.Colored("muted", L["  /farm export to get it as a data file."]))
end)

ns.RegisterCommand("export", L["everything you've looted, as text ready to paste"], function(rest)
    local wanted = ns.Util.Trim(rest or "")

    -- "/farm export csv [loot|kills|gathering|fishing]": the spreadsheet
    -- (Logic/CSV.lua).
    local sheetWord = wanted:lower():match("^csv%s*(.*)$")
    if sheetWord and ns.CSV then
        local sheet = ns.CSV.SheetFor(sheetWord)
        if not sheet then
            ns.Print(L.Format("No sheet called %s. Try loot, kills, gathering or fishing.", sheetWord))
            return
        end
        ns.CSV:Show(sheet)
        return
    end

    if wanted == "" then
        ns.UI:ShowExport(ns.Harvest:ExportAll(), L["Export: everything you looted"])
        return
    end

    -- Name an item and you get only that item, which is the usual case: you
    -- farmed one thing for an evening and want that one block.
    local name, candidates = ns.Harvest:ResolveItem(wanted)
    -- A herb or ore credited to a mob stays out, as in ExportAll.
    local nodeOnly = name and ns.Gathering ~= nil and ns.Gathering.IsNodeOnly(name)
    local block = name and not nodeOnly and ns.Harvest:ExportItem(name)

    if candidates then
        local shown, more = {}, #candidates - 8
        for index = 1, math.min(8, #candidates) do shown[index] = candidates[index] end
        local list = table.concat(shown, ", ")
        if more > 0 then list = L.Format("%s and %d more", list, more) end
        ns.Print(L.Format("%s could be %s. Type more of the name.", wanted, list))
        return
    end

    if nodeOnly then
        ns.Print(L.Format("%s comes from nodes, not mobs, so it isn't in the export.", name))
        return
    end

    if not block then
        ns.Print(L.Format("nothing looted for %s yet.", wanted))
        return
    end

    ns.UI:ShowExport(block, L.Format("Export: %s", name))
end)
