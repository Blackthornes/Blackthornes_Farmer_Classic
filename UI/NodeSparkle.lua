-- Blackthornes Farmer -- UI/NodeSparkle.lua
-- Sparkles over the herb or ore node you are facing.
--
-- Colours (the owner, 2026-10-24): herbs and ore take your skill's colour,
-- as recipes do (orange a sure point, yellow likely, green now and then,
-- grey not yet gatherable, which still sparkles); quest objects are blue;
-- chests, schools and the bobber white; gold when no skill can be read or
-- "Sparkle Colors" is unticked (`nodeSparkleColors`, on unless unticked;
-- never rename it). "Skinnable Corpses" (`nodeSparkleCorpses`, off unless
-- ticked; never rename it) sparkles a dead beast you could skin, in your
-- Skinning's colour, until you skin it.
--
-- The game tells addons nothing about the nodes around you: not where they
-- are, not where they sit on screen. The one it does name is the node the
-- interact key would pick, "softinteract": the one in front of you, close
-- by. With the game's own nameplate for that object turned on, the
-- nameplate is a frame that follows the node in the world, so a few
-- sparkles anchored above it stay on the node as you move.
--
-- The game's own icon over the object (SoftTargetIconGameObject,
-- SoftTargetIconInteract) is turned on with them; the sparkles gather round
-- it when the nameplate lets us read where it is.
--
-- So, while "Sparkles in the world" is ticked (`nodeSparkle`, on unless
-- unticked; never rename it), Farmer turns on, out of combat, the two game
-- settings that make that nameplate (SoftTargetInteract to "always",
-- SoftTargetNameplateInteract on) and lets it look farther and all the way
-- round (SoftTargetInteractRange, SoftTargetInteractArc), keeping what each was in
-- `nodeSparkleCVars` (never rename it) and putting them back when the box
-- is unticked. Nothing is set that the player had already set that way.
--
-- A node is a herb or ore the data knows (a herb's own name, a vein's
-- source name), the client's name for that herb, or any node the player
-- has gathered (Gathering keeps the name the client gave). A hidden source
-- gets nothing. Fishing schools, chests and objects a quest in the log
-- still wants sparkle too (the owner asked 2026-10-13); a mailbox, a door
-- or a chair does not. A quest pickup is often named apart from what the
-- objective counts, so its tooltip's objective line and what it gave when
-- looted before count as well as its name.
--
-- Without a game controller the game's icon is left out of sight (the
-- owner asked 2026-10-13): it is only there because Farmer turned it on to
-- get the nameplate, and on a keyboard it says nothing the beacon does not.
-- It is made see-through (SetAlpha), never hidden, and put back as it was;
-- see NodeSparkle:VeilIcon. "Hide the game's icon" (`nodeSparkleHideIcon`,
-- on unless unticked; never rename it). A player who had the icon on before
-- Farmer, or who plays with a controller, keeps it.
--
-- The nameplates themselves are Farmer's doing too: with them on, the game
-- puts a name, a health bar and a level over every NPC and object the
-- interact key picks. On an NPC the game then takes the name off its head
-- for a white, cut-short one on the plate, so while the interact key picks
-- a creature that setting goes back to the player's own
-- (NodeSparkle:FitPlateToTarget). While Farmer is the one that turned them on, the
-- plate's pieces other than the icon are see-through the same way (a
-- creature you could attack, or any with friendly nameplates on, keeps its
-- plate). The beacon is anchored to the plate, not parented, so it shows.
--
-- Smooth play: no OnUpdate and no timer. The soft target and nameplate
-- events say when to look again, the anchor makes it follow the node, and
-- the twinkle is an animation the game plays, only while it shows. Every
-- client value is read in a pcall. Nothing is written on a game frame: the
-- sparkles are Farmer's own frame, anchored to the nameplate, never
-- parented to it.

local _, ns = ...
local L = ns.L

local NodeSparkle = ns.NewModule("NodeSparkle")

local UNIT = "softinteract"

-- The game settings Farmer turns on, and to what.
NodeSparkle.CVARS = {
    { name = "SoftTargetInteract", value = "3", atLeast = 3 },
    { name = "SoftTargetNameplateInteract", value = "1", atLeast = 1 },
    -- How far the interact target looks, in yards (the game's own is about
    -- 10), and how wide: 2 is all the way round you, 1 only in front. The
    -- owner asked 2026-10-13 for 30, then 100, then back to 15 once he saw
    -- in game that about 15 is as far as Forever lets it reach. `lower`
    -- brings a save Farmer set to 100 back down.
    { name = "SoftTargetInteractRange", value = "15", atLeast = 15, lower = true },
    { name = "SoftTargetInteractArc", value = "2", atLeast = 2 },
    -- The game's own icon over the object you face (the owner picked it
    -- 2026-10-13, once the probe showed Forever gave no nameplate without
    -- it). A client without one of these simply skips it.
    { name = "SoftTargetIconGameObject", value = "1", atLeast = 1 },
    { name = "SoftTargetIconInteract", value = "1", atLeast = 1 },
}

-- Where each sparkle sits round the node, in pixels from the anchor, how
-- big it is and when in the loop it lights.
NodeSparkle.SPARKS = {
    { x = -26, y = 10, size = 18, delay = 0.0 },
    { x = 24, y = 22, size = 14, delay = 0.5 },
    { x = 18, y = -8, size = 12, delay = 1.0 },
    { x = -12, y = -14, size = 10, delay = 0.8 },
    { x = 2, y = 34, size = 13, delay = 0.3 },
    { x = -30, y = 30, size = 9, delay = 1.2 },
}

NodeSparkle.TWINKLE = 0.8          -- seconds to light up, and again to fade
-- How far below the game's icon the node sits, in interface units at the
-- nameplate's own size (measured on a Silverleaf, 2026-10-13). The icon
-- floats above the object; the sparkles go down onto the plant. A plate
-- the game draws smaller (farther off) moves them less.
NodeSparkle.DROP = 75
NodeSparkle.GOLD = { 1.0, 0.84, 0.36 }
-- What each thing sparkles in (see the top of the file).
NodeSparkle.COLORS = {
    orange = { 1.0, 0.5, 0.25 },
    yellow = { 1.0, 1.0, 0.0 },
    green = { 0.25, 0.75, 0.25 },
    grey = { 0.62, 0.62, 0.62 },
    quest = { 0.3, 0.65, 1.0 },
    white = { 1.0, 1.0, 1.0 },
}
-- How far past a node's need each colour runs, as the skill-up chance does
-- (GatherToCap: sure to 25 over). Green from 50 over on, never grey.
NodeSparkle.ORANGE_TO = 25
NodeSparkle.YELLOW_TO = 50
NodeSparkle.GLOW = "Interface\\AddOns\\Blackthornes_Farmer\\Media\\Frame\\Glow"
-- A four-pointed star, drawn by tools/make_sparkle_art.py.
NodeSparkle.STAR = "Interface\\AddOns\\Blackthornes_Farmer\\Media\\Frame\\Sparkle"
-- The other look, a beam of light rising off the spot (the owner asked
-- 2026-10-13): `nodeSparkleStyle`, "sparkles" or "beacon", account wide,
-- the beacon unless sparkles are picked (the owner, the same day); never
-- rename it. `nodeSparkleStylePicked` says the player picked it, so the
-- "sparkles" the first default wrote into a save becomes the beacon.
NodeSparkle.BEAM = "Interface\\AddOns\\Blackthornes_Farmer\\Media\\Frame\\Beacon"
NodeSparkle.STYLES = { "sparkles", "beacon" }
NodeSparkle.BEACON_WIDTH, NodeSparkle.BEACON_HEIGHT = 22, 240
NodeSparkle.PULSE = 1.2            -- seconds for the beacon to dim, and again to brighten
-- Era gives no nameplate for objects (the probe, 2026-10-25: none showing
-- while facing a herb), so there is nothing that follows the node on
-- screen. Then the beacon or sparkles stand in one spot above the middle
-- of the screen, over the character, with the node's name under them, in
-- the same colour (the owner picked it from a mockup, 2026-10-25). The
-- game's own icon still marks the node itself. `SCREEN_Y` is how far up
-- from the middle, as a share of the screen's height.
NodeSparkle.SCREEN = "screen"
NodeSparkle.SCREEN_Y = 0.11

-- On screen the beam is left out (the owner, 2026-10-25: "drop the beam");
-- a glowing arrow by the character's feet points at the node instead, with
-- a dotted trail going on past it, pulsing, in the node's colour. Era says
-- nowhere where an object stands, so it points at the spot you gathered
-- that node at before (`gathering.spots`), the nearest within POINT_YARDS
-- on the map you stand on, else the nearest spot Classic grows it at
-- (`ns.NODE_SPOTS`, Data/NodeSpots.lua; the owner, 2026-10-25); with
-- neither, only the name shows. POINTER_Y is
-- how far down from the middle of the screen the feet are, as a share of
-- its height; POINTER_REACH how far from them the arrow sits and TRAIL
-- where each dot sits, in pixels; NEAR_ENOUGH the yards at which you are
-- on it and the arrow goes.
NodeSparkle.ARROW = "Interface\\AddOns\\Blackthornes_Farmer\\Media\\Frame\\GlowArrow"
NodeSparkle.DOT = "Interface\\AddOns\\Blackthornes_Farmer\\Media\\Frame\\TravelDot"
NodeSparkle.POINT_YARDS = 40
-- A spot Classic grows the node at counts only this near and in front of
-- you, where the game picks the node you face from, so it is that node.
NodeSparkle.SHIPPED_YARDS = 20
NodeSparkle.NEAR_ENOUGH = 2.5
NodeSparkle.POINTER_Y = 0.08
NodeSparkle.POINTER_REACH = 64
NodeSparkle.ARROW_SIZE = 46
NodeSparkle.TRAIL = { { at = 100, size = 12 }, { at = 128, size = 10 }, { at = 154, size = 8 } }
-- A short glowing beam stands at the trail's end, a soft flare at its foot
-- (the owner asked, 2026-10-25), the same art as the beacon.
NodeSparkle.TRAIL_BEAM = { at = 182, width = 14, height = 90, flare = 34 }
-- With "Sparkles" picked under Sparkle Look, these twinkle at the trail's
-- end in place of the beam (the owner, 2026-10-25: the look did nothing on
-- Era). Pixels from the trail's end, size and when in the loop each lights.
-- Each has a soft glow behind it at TRAIL_SPARK_GLOW, so they read on
-- bright ground without glaring (the owner, 2026-10-25: brighter, not
-- super bright).
NodeSparkle.TRAIL_SPARKS = {
    { x = 0, y = 18, size = 32, delay = 0.0 },
    { x = -18, y = 40, size = 24, delay = 0.5 },
    { x = 16, y = 54, size = 22, delay = 1.0 },
    { x = -6, y = 76, size = 18, delay = 0.3 },
    { x = 22, y = 26, size = 16, delay = 0.8 },
    { x = -22, y = 12, size = 14, delay = 1.2 },
}
NodeSparkle.TRAIL_SPARK_GLOW = 0.45
-- What shows (the owner, 2026-10-25): the arrow, dots and beam, the arrow
-- and dots alone, or the beam alone. `nodePointer`, account wide, "both"
-- unless picked; never rename it. Alone, the beam stands toward the node,
-- nearer your feet the nearer it is: BEAM_NEAR pixels from them on top of
-- it, BEAM_FAR at POINT_YARDS or more.
NodeSparkle.POINTER_LOOKS = { "both", "arrow", "beam" }
NodeSparkle.BEAM_NEAR, NodeSparkle.BEAM_FAR = 40, 240
NodeSparkle.POINTER_LOOK = 0.03     -- seconds between turns of the arrow
NodeSparkle.POINTER_PULSE = 0.6     -- seconds to dim, and again to brighten

function NodeSparkle:PointerLook()
    local look = ns.db and ns.db.nodePointer
    if look == "arrow" or look == "beam" then return look end
    return "both"
end

function NodeSparkle:SetPointerLook(look)
    ns.db.nodePointer = (look == "arrow" or look == "beam") and look or "both"
    if self.pointer then self.pointer.turn = nil end
    self:SafeRefresh()
end

-- A spoken line when the arrow finds a node (the owner asked, 2026-10-25):
-- your own character's "Follow me!" in its race and voice, or the orc
-- peon's "Ready to work!". The game's own files by ID, nothing shipped.
-- `nodeVoice` is "off", "character" or "peon", account wide, off unless
-- picked; never rename it. Once a node, and not again for VOICE_GAP seconds.
NodeSparkle.VOICES = { "off", "character", "peon" }
NodeSparkle.VOICE_GAP = 20
NodeSparkle.FOLLOW_ME = {   -- [race] = { male, female }
    Human = { 540711, 540631 }, Dwarf = { 540057, 540004 },
    NightElf = { 541086, 541066 }, Gnome = { 540474, 540419 },
    Orc = { 541410, 541337 }, Scourge = { 542744, 542695 },
    Tauren = { 543048, 542972 }, Troll = { 543288, 543258 },
}
NodeSparkle.PEON_READY = 558137

function NodeSparkle:Voice()
    local voice = ns.db and ns.db.nodeVoice
    if voice == "character" or voice == "peon" then return voice end
    return "off"
end

function NodeSparkle:SetVoice(voice)
    ns.db.nodeVoice = (voice == "character" or voice == "peon") and voice or "off"
end

--- The file the picked voice plays, or nil.
function NodeSparkle:VoiceFile(voice)
    voice = voice or self:Voice()
    if voice == "peon" then return self.PEON_READY end
    if voice ~= "character" then return nil end
    local race, sex
    if type(UnitRace) == "function" then
        local ok, _, file = pcall(UnitRace, "player")
        if ok and type(file) == "string" then race = file end
    end
    if type(UnitSex) == "function" then
        local ok, value = pcall(UnitSex, "player")
        if ok and type(value) == "number" then sex = value end
    end
    local pair = race and self.FOLLOW_ME[race]
    if not pair then return self.FOLLOW_ME.Human[1] end
    return sex == 3 and pair[2] or pair[1]
end

--- Say the line for the node `guid`, once, unless one was said lately.
--- `force` plays it now (Try it). True when the client will play it.
function NodeSparkle:SayFound(guid, force)
    local id = self:VoiceFile(force and force ~= true and force or nil)
    if not id or type(PlaySoundFile) ~= "function" then return false end
    local now = type(GetTime) == "function" and GetTime() or 0
    if not force then
        if guid and guid == self.saidGuid then return false end
        if self.saidAt and now - self.saidAt < self.VOICE_GAP then
            self.saidGuid = guid
            return false
        end
    end
    local ok, willPlay = pcall(PlaySoundFile, id, "Dialog")
    if not (ok and willPlay) then return false end
    self.saidGuid, self.saidAt = guid, now
    return true
end

--- How far from your feet the beam stands alone, for a node `yards` away.
function NodeSparkle.BeamReach(yards)
    local share = math.max(0, math.min(1, (tonumber(yards) or 0) / NodeSparkle.POINT_YARDS))
    return NodeSparkle.BEAM_NEAR + share * (NodeSparkle.BEAM_FAR - NodeSparkle.BEAM_NEAR)
end

function NodeSparkle:Style()
    local db = ns.db
    if not db then return "beacon" end
    if db.nodeSparkleStyle == "sparkles" and db.nodeSparkleStylePicked ~= true then
        db.nodeSparkleStyle = "beacon"
    end
    if db.nodeSparkleStyle == "sparkles" then return "sparkles" end
    return "beacon"
end

function NodeSparkle:SetStyle(style)
    ns.db.nodeSparkleStyle = style == "sparkles" and "sparkles" or "beacon"
    ns.db.nodeSparkleStylePicked = true
    if self.shownOn then
        local plate, guid = self.shownOn, self.shownGuid
        self:ShowSparkle(plate, guid)
    end
end

local function Field(object, key)
    if type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

local function Readable(value)
    return ns.Harvest and ns.Harvest.Readable(value) or nil
end

local function InCombat()
    if type(InCombatLockdown) ~= "function" then return false end
    local ok, value = pcall(InCombatLockdown)
    return ok and value == true
end

function NodeSparkle:IsEnabled()
    return not (ns.db and ns.db.nodeSparkle == false)
end

--------------------------------------------------------------------------------
-- The game's settings
--------------------------------------------------------------------------------

function NodeSparkle.GetCVar(name)
    local cvar = _G.C_CVar
    local get = Field(cvar, "GetCVar") or _G.GetCVar
    if type(get) ~= "function" then return nil end
    local ok, value = pcall(get, name)
    if not ok or value == nil then return nil end
    return tostring(value)
end

function NodeSparkle.SetCVar(name, value)
    local cvar = _G.C_CVar
    local set = Field(cvar, "SetCVar") or _G.SetCVar
    if type(set) ~= "function" then return false end
    local ok, result = pcall(set, name, value)
    return ok and result ~= false
end

local function Saved()
    local db = ns.db
    if type(db.nodeSparkleCVars) ~= "table" then db.nodeSparkleCVars = {} end
    return db.nodeSparkleCVars
end

--- Turn on the game settings the sparkle needs, keeping what each was.
--- Out of combat only; in a fight it waits for the fight to end.
function NodeSparkle:ApplySettings()
    if not ns.db or not self:IsEnabled() then return false end
    if InCombat() then
        self.applyAfterCombat = true
        return false
    end
    self.applyAfterCombat = nil

    local saved = Saved()
    for _, cvar in ipairs(self.CVARS) do
        local now = self.GetCVar(cvar.name)
        if now ~= nil and (tonumber(now) or 0) < cvar.atLeast then
            if saved[cvar.name] == nil then saved[cvar.name] = now end
            self.SetCVar(cvar.name, cvar.value)
        end
        -- Farmer set it higher before: bring it to what it sets now.
        if now ~= nil and cvar.lower and saved[cvar.name] ~= nil and (tonumber(now) or 0) > cvar.atLeast then
            self.SetCVar(cvar.name, cvar.value)
        end
    end
    return true
end

--- Put back what the player had before Farmer changed it.
function NodeSparkle:RestoreSettings()
    if not ns.db then return false end
    local saved = ns.db.nodeSparkleCVars
    if type(saved) ~= "table" or next(saved) == nil then return true end
    if InCombat() then
        self.restoreAfterCombat = true
        return false
    end
    self.restoreAfterCombat = nil

    for name, value in pairs(saved) do
        if self.SetCVar(name, value) then saved[name] = nil end
    end
    return true
end

function NodeSparkle:SetEnabled(on)
    ns.db.nodeSparkle = on and true or false
    if on then
        self.restoreAfterCombat = nil
        self:ApplySettings()
        self:Refresh()
    else
        self.applyAfterCombat = nil
        self:LowerReach()
        self:RestoreSettings()
        self:HideSparkle()
        pcall(self.VeilIcon, self)
    end
end

--------------------------------------------------------------------------------
-- Reaching the bobber while fishing
--------------------------------------------------------------------------------

--- Is this channel the Fishing spell? By its ID, else by its name.
function NodeSparkle.IsFishingCast(spellID)
    if type(spellID) == "number" and NodeSparkle.FISHING_SPELLS[spellID] then return true end
    if type(UnitChannelInfo) ~= "function" then return false end
    local ok, name = pcall(UnitChannelInfo, "player")
    name = ok and Readable(name) or nil
    if not name then return false end
    local names = ns.Gathering and ns.Gathering.ClientNames and ns.Gathering.ClientNames("Fishing")
    return type(names) == "table" and names[name] == true or name == "Fishing"
end

--- Let the interact target reach as far as a cast lands. Only out of a
--- fight, only when it reaches less now, and what it was is kept.
function NodeSparkle:RaiseReach()
    if not ns.db or not self:IsEnabled() or InCombat() then return false end
    local now = self.GetCVar("SoftTargetInteractRange")
    if now == nil or (tonumber(now) or 0) >= self.FISHING_RANGE then return false end
    if ns.db.nodeSparkleFishingRange == nil then ns.db.nodeSparkleFishingRange = now end
    return self.SetCVar("SoftTargetInteractRange", tostring(self.FISHING_RANGE))
end

--- Put the reach back as it was before the cast. In a fight it waits.
function NodeSparkle:LowerReach()
    local kept = ns.db and ns.db.nodeSparkleFishingRange
    if kept == nil then return true end
    if InCombat() then
        self.lowerAfterCombat = true
        return false
    end
    self.lowerAfterCombat = nil
    if self.SetCVar("SoftTargetInteractRange", kept) then ns.db.nodeSparkleFishingRange = nil end
    return true
end

local function After(seconds, fn)
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        pcall(C_Timer.After, seconds, fn)
    end
end

function NodeSparkle:FishingStarted(spellID)
    if not self.IsFishingCast(spellID) then return end
    self.fishing = true
    if not self:IsEnabled() then return end
    self:RaiseReach()
    self:SafeRefresh()
    for _, seconds in ipairs(self.FISHING_LOOKS) do
        After(seconds, function()
            if NodeSparkle.fishing then NodeSparkle:SafeRefresh() end
        end)
    end
end

function NodeSparkle:FishingStopped()
    if not self.fishing then return end
    self.fishing = nil
    self:LowerReach()
    self:SafeRefresh()
end

--------------------------------------------------------------------------------
-- Which objects are nodes
--------------------------------------------------------------------------------

local names, namesKey, needs = nil, nil, nil

local function GatherCount()
    local gathering = ns.db and ns.db.gathering
    local nodes = type(gathering) == "table" and gathering.nodes
    if type(nodes) ~= "table" then return 0 end
    local count = 0
    for _ in pairs(nodes) do count = count + 1 end
    return count
end

local function Add(set, name)
    if type(name) == "string" and name ~= "" then set[name:lower()] = name end
end

--- Every node name Farmer knows, in lower case. Laid out again only when the
--- data, the client's names or the gathered nodes changed.
function NodeSparkle:Names()
    local DB = ns.DB
    local key = ("%s:%s:%d"):format(tostring(DB and DB.changes), tostring(DB and DB.namesVersion), GatherCount())
    if names and namesKey == key then return names end

    local set, need = {}, {}
    -- The least skill a node asks for anywhere, by name in lower case.
    local function Needs(name, requires)
        if type(name) ~= "string" or name == "" or type(requires) ~= "string" then return end
        local skill, number = requires:match("^(%a+)%s+(%d+)%s*$")
        number = tonumber(number)
        if not skill or not number then return end
        local key, kept = name:lower(), need[name:lower()]
        if not kept or number < kept.need then need[key] = { skill = skill, need = number } end
    end
    if DB then
        for item in DB:Iterate() do
            for _, source in ipairs(item.sources or {}) do
                if source.kind == "herb" then
                    Add(set, item.name)
                    Add(set, DB:ClientName(item))
                    Needs(item.name, source.requires)
                    Needs(DB:ClientName(item), source.requires)
                elseif source.kind == "node" then
                    Add(set, source.name)
                    Needs(source.name, source.requires)
                end
            end
        end
    end

    local gathering = ns.db and ns.db.gathering
    if type(gathering) == "table" and type(gathering.nodes) == "table" then
        for _, entry in pairs(gathering.nodes) do
            if type(entry) == "table" and (entry.kind == "herb" or entry.kind == "ore") then
                Add(set, entry.node)
            end
        end
    end

    names, namesKey, needs = set, key, need
    return set
end

--- The skill a node needs, as "Mining", 65, or nil when the data does not
--- say (a node only the player has gathered).
function NodeSparkle:NodeNeeds(name)
    if type(name) ~= "string" or name == "" then return nil end
    self:Names()
    local entry = needs and needs[name:lower()]
    if not entry then return nil end
    return entry.skill, entry.need
end

-- Chests by the endings their names share (and the German word).
NodeSparkle.CHEST_PATTERNS = { "Chest$", "Footlocker$", "Strongbox$", "Lockbox$", "Truhe$" }

-- The player's own bobber, so a bite is easy to spot (English, German).
NodeSparkle.BOBBERS = { ["Fishing Bobber"] = true, ["Schwimmer"] = true }
-- While fishing, any object with one of these in its name is the bobber.
NodeSparkle.BOBBER_WORDS = { "bobber", "schwimmer" }

-- A cast lands farther out than the interact target looks the rest of the
-- time (15 yards), so it never picked the bobber (the owner, 2026-10-13).
-- While the Fishing channel runs, the reach goes up to this and comes back
-- when it ends. What it was waits in `nodeSparkleFishingRange` (never
-- rename it) in case the game closes mid-cast, and is put back at login.
NodeSparkle.FISHING_RANGE = 35
NodeSparkle.FISHING_SPELLS = { [7620] = true, [7731] = true, [7732] = true, [18248] = true }
-- The bobber appears a moment after the cast starts: look again then.
NodeSparkle.FISHING_LOOKS = { 0.3, 1.0, 2.5 }

function NodeSparkle.IsChest(name)
    if type(name) ~= "string" or name == "" then return false end
    for _, pattern in ipairs(NodeSparkle.CHEST_PATTERNS) do
        if name:find(pattern) then return true end
    end
    return false
end

-- The objectives still to do in the quest log, in lower case, read again
-- only after the log changes (QUEST_LOG_UPDATE marks it stale).
local questText, questStale = nil, true

function NodeSparkle:QuestText()
    if questText and not questStale then return questText end
    local parts = {}
    local log = _G.C_QuestLog
    local count = Field(log, "GetNumQuestLogEntries")
    local info = Field(log, "GetInfo")
    local objectives = Field(log, "GetQuestObjectives")
    if type(count) == "function" and type(info) == "function" and type(objectives) == "function" then
        local ok, entries = pcall(count)
        for index = 1, (ok and type(entries) == "number") and entries or 0 do
            local read, entry = pcall(info, index)
            local questID = read and type(entry) == "table" and not entry.isHeader and entry.questID
            if questID then
                local got, list = pcall(objectives, questID)
                for _, objective in ipairs(got and type(list) == "table" and list or {}) do
                    local text = type(objective) == "table" and Readable(objective.text)
                    if type(text) == "string" and not objective.finished then parts[#parts + 1] = text:lower() end
                end
            end
        end
    end
    questText, questStale = table.concat(parts, "\n"), false
    return questText
end

function NodeSparkle:QuestLogChanged()
    questStale = true
end

--- Does the game's own tooltip for the interact target carry a quest
--- objective? A quest pickup's tooltip names the quest and the objective
--- ("9/15 Windstone Cluster") under its name, though the object itself is
--- called something else ("Raw Windstone").
function NodeSparkle:QuestInTooltip()
    local get = Field(_G.C_TooltipInfo, "GetUnit")
    if type(get) ~= "function" then return false end
    local ok, data = pcall(get, UNIT)
    local lines = ok and Field(data, "lines")
    if type(lines) ~= "table" then return false end
    local wanted = self:QuestText()
    -- The first line is the name.
    for index = 2, #lines do
        local text = Readable(Field(lines[index], "leftText"))
        if type(text) == "string" and #text >= 4 then
            local have, need = text:match("(%d+)%s*/%s*(%d+)")
            have, need = tonumber(have), tonumber(need)
            if have and need and need > 0 and have < need then return true end
            local lower = text:lower():gsub("^[%s%-]+", "")
            if #lower >= 6 and wanted:find(lower, 1, true) then return true end
        end
    end
    return false
end

-- What each gathered node gave, by node name in lower case, laid out again
-- only when the gathered nodes change.
local nodeItems, nodeItemsKey = nil, nil

--- Has an object called `name` given the player something an objective
--- still wants? A quest pickup Farmer recorded as a gather counts.
function NodeSparkle:QuestByLoot(name)
    local gathering = ns.db and ns.db.gathering
    local nodes = type(gathering) == "table" and gathering.nodes
    if type(nodes) ~= "table" then return false end
    local key = GatherCount()
    if not nodeItems or nodeItemsKey ~= key then
        nodeItems, nodeItemsKey = {}, key
        for _, entry in pairs(nodes) do
            if type(entry) == "table" and type(entry.node) == "string" and type(entry.items) == "table" then
                local list = nodeItems[entry.node:lower()] or {}
                for item in pairs(entry.items) do
                    if type(item) == "string" and #item >= 4 then list[#list + 1] = item:lower() end
                end
                nodeItems[entry.node:lower()] = list
            end
        end
    end
    local items = nodeItems[name:lower()]
    if not items then return false end
    local wanted = self:QuestText()
    if wanted == "" then return false end
    for _, item in ipairs(items) do
        if wanted:find(item, 1, true) then return true end
    end
    return false
end

--- Is `name` something a quest in the log still wants? The game's own
--- answer for the interact target first, then its tooltip, then its name
--- in an objective, then what it gave when it was looted before.
function NodeSparkle:IsQuestObject(name)
    local related = Field(_G.C_QuestLog, "UnitIsRelatedToActiveQuest")
    if type(related) == "function" then
        local ok, yes = pcall(related, UNIT)
        if ok and type(yes) == "boolean" and yes then return true end
    end
    if self:QuestInTooltip() then return true end
    if type(name) ~= "string" or #name < 4 then return false end
    if self:QuestText():find(name:lower(), 1, true) then return true end
    return self:QuestByLoot(name)
end

--- What kind of thing worth a sparkle the object is: "node", "school",
--- "chest", "bobber" or "quest", or nil. A hidden source is nothing.
function NodeSparkle:Kind(name)
    if type(name) ~= "string" or name == "" then return nil end
    if ns.DB and ns.DB:IsHiddenSource(name) then return nil end
    if self:IsNode(name) then return "node" end
    if ns.Fishing and ns.Fishing.IsSchool and ns.Fishing.IsSchool(name) then return "school" end
    if self.IsChest(name) then return "chest" end
    if self:IsBobber(name) then return "bobber" end
    if self:IsQuestObject(name) then return "quest" end
    return nil
end

function NodeSparkle:IsBobber(name)
    if type(name) ~= "string" or name == "" then return false end
    if self.BOBBERS[name] then return true end
    if not self.fishing then return false end
    local lower = name:lower()
    for _, word in ipairs(self.BOBBER_WORDS) do
        if lower:find(word, 1, true) then return true end
    end
    return false
end

function NodeSparkle:IsNode(name)
    if type(name) ~= "string" or name == "" then return false end
    if not self:Names()[name:lower()] then return false end
    if ns.DB and ns.DB:IsHiddenSource(name) then return false end
    return true
end

--- What the interact key points at: its guid, its name, and whether it is a
--- game object. Nil values where the client will not say.
function NodeSparkle:Facing()
    local guid, name
    if type(UnitGUID) == "function" then
        local ok, value = pcall(UnitGUID, UNIT)
        guid = ok and Readable(value) or nil
    end
    if type(UnitName) == "function" then
        local ok, value = pcall(UnitName, UNIT)
        name = ok and Readable(value) or nil
    end
    local object = type(guid) == "string" and guid:find("^GameObject%-") ~= nil
    return guid, name, object
end

--- The game's nameplate for the object, or nil.
function NodeSparkle:Plate(guid)
    local plates = _G.C_NamePlate
    local forUnit = Field(plates, "GetNamePlateForUnit")
    if type(forUnit) == "function" then
        local ok, plate = pcall(forUnit, UNIT)
        if ok and type(plate) == "table" then return plate end
    end

    -- Some clients give the object a nameplateN token instead.
    local all = Field(plates, "GetNamePlates")
    if not guid or type(all) ~= "function" then return nil end
    local ok, list = pcall(all)
    if not ok or type(list) ~= "table" then return nil end
    for _, plate in ipairs(list) do
        local token = Readable(Field(plate, "namePlateUnitToken"))
            or Readable(Field(Field(plate, "UnitFrame"), "unit"))
        if token and type(UnitGUID) == "function" then
            local read, value = pcall(UnitGUID, token)
            if read and Readable(value) == guid then return plate end
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- The game's icon, out of sight without a controller
--------------------------------------------------------------------------------

local ICON_CVARS = { SoftTargetIconGameObject = true, SoftTargetIconInteract = true }
local veiled = setmetatable({}, { __mode = "k" })   -- [icon frame] = its alpha before

--- Is a game controller in use?
function NodeSparkle.Controller()
    local enabled = Field(_G.C_GamePad, "IsEnabled")
    if type(enabled) == "function" then
        local ok, yes = pcall(enabled)
        if ok and type(yes) == "boolean" and yes then return true end
    end
    return NodeSparkle.GetCVar("GamePadEnable") == "1"
end

--- Should the game's icon be kept out of sight? Only while Farmer is the
--- one that turned it on, and nobody plays with a controller.
function NodeSparkle:HidesIcon()
    local db = ns.db
    if not db or not self:IsEnabled() or db.nodeSparkleHideIcon == false then return false end
    local saved = db.nodeSparkleCVars
    if type(saved) ~= "table" then return false end
    local ours = false
    for name in pairs(ICON_CVARS) do
        if saved[name] ~= nil then ours = true end
    end
    return ours and not self.Controller()
end

local function SetAlpha(frame, alpha)
    return pcall(function() frame:SetAlpha(alpha) end)
end

local function Unveil(frame)
    local alpha = veiled[frame]
    veiled[frame] = nil
    if alpha ~= nil then SetAlpha(frame, alpha) end
end

--- Did Farmer turn on the game's nameplate for what the interact key
--- picks? Only then are those plates its own doing to keep out of sight.
function NodeSparkle:OwnsPlates()
    local db = ns.db
    if not db or not self:IsEnabled() then return false end
    local saved = db.nodeSparkleCVars
    return type(saved) == "table"
        and (saved.SoftTargetNameplateInteract ~= nil or saved.SoftTargetInteract ~= nil)
end

--- Would the player see this plate without Farmer? A creature's plate
--- shows anyway when it can be attacked, or when friendly nameplates are on.
function NodeSparkle:PlateShownAnyway(guid)
    if type(guid) ~= "string" or guid:find("^GameObject%-") then return false end
    if type(UnitCanAttack) == "function" then
        local ok, yes = pcall(UnitCanAttack, "player", UNIT)
        if ok and type(yes) == "boolean" and yes then return true end
    end
    return self.GetCVar("nameplateShowFriends") == "1"
end

--- Is this piece of a plate its name? The game hides a creature's own name
--- over its head while it has a plate, so the plate's name stands in for it.
function NodeSparkle.IsPlateName(body, piece)
    if piece == Field(body, "name") then return true end
    local ok, kind = pcall(function() return piece:GetObjectType() end)
    return ok and kind == "FontString"
end

--- The pieces of a plate the game draws for the interact target, its name,
--- bars and level, but not its icon: what the game shows only because
--- Farmer turned these plates on. With `keepName` (a creature) its name is
--- left out, since the game takes the creature's own name away for it.
function NodeSparkle.PlatePieces(plate, keepName)
    local body = Field(plate, "UnitFrame")
    if type(body) ~= "table" then return {} end
    local icon = NodeSparkle.Icon(plate)
    local pieces = {}
    for _, method in ipairs({ "GetRegions", "GetChildren" }) do
        local ok, list = pcall(function() return { body[method](body) } end)
        for _, piece in ipairs(ok and list or {}) do
            if type(piece) == "table" and piece ~= icon
                and not (keepName and NodeSparkle.IsPlateName(body, piece)) then
                pieces[#pieces + 1] = piece
            end
        end
    end
    return pieces
end

--- Keep out of sight what Farmer's settings made the game draw over the
--- thing the interact key picks: the plate's bars and level always, and an
--- object's name (unless the player would see that plate anyway; a
--- creature keeps its name, which the game moves onto the plate), and its icon without a
--- controller. Only alpha is changed, from this file's own table, never in
--- a fight; a plate the game hands to something else gets its own back.
-- @return true while anything is kept out of sight
function NodeSparkle:VeilIcon()
    if InCombat() then return next(veiled) ~= nil end
    local want = {}
    local plate
    local forUnit = Field(_G.C_NamePlate, "GetNamePlateForUnit")
    if type(forUnit) == "function" and (self:HidesIcon() or self:OwnsPlates()) then
        local ok, found = pcall(forUnit, UNIT)
        if ok and type(found) == "table" then plate = found end
    end
    if plate then
        if self:HidesIcon() then
            local icon = self.Icon(plate)
            if icon then want[icon] = true end
        end
        if self:OwnsPlates() then
            local guid = self:Facing()
            if not self:PlateShownAnyway(guid) then
                local creature = type(guid) == "string" and not guid:find("^GameObject%-")
                for _, piece in ipairs(self.PlatePieces(plate, creature)) do want[piece] = true end
            end
        end
    end
    for other in pairs(veiled) do
        if not want[other] then Unveil(other) end
    end
    if next(want) == nil then return false end
    for frame in pairs(want) do
        if veiled[frame] == nil then
            local ok, alpha = pcall(function() return frame:GetAlpha() end)
            veiled[frame] = (ok and type(alpha) == "number") and alpha or 1
        end
        -- Again each time: the game may light it up as the target changes.
        SetAlpha(frame, 0)
    end
    return true
end

--- Put back everything kept out of sight.
function NodeSparkle:UnveilAll()
    local frames = {}
    for frame in pairs(veiled) do frames[#frames + 1] = frame end
    for _, frame in ipairs(frames) do Unveil(frame) end
end

function NodeSparkle:SetHideIcon(hide)
    ns.db.nodeSparkleHideIcon = hide and true or false
    self:SafeRefresh()
end

--------------------------------------------------------------------------------
-- The sparkles
--------------------------------------------------------------------------------

local function Twinkle(texture, delay)
    local ok, group = pcall(texture.CreateAnimationGroup, texture)
    if not ok or type(group) ~= "table" then return nil end
    local made = pcall(function()
        group:SetLooping("REPEAT")
        local light = group:CreateAnimation("Alpha")
        light:SetFromAlpha(0)
        light:SetToAlpha(1)
        light:SetDuration(NodeSparkle.TWINKLE)
        light:SetStartDelay(delay)
        light:SetSmoothing("OUT")
        light:SetOrder(1)
        local fade = group:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        fade:SetDuration(NodeSparkle.TWINKLE)
        fade:SetSmoothing("IN")
        fade:SetOrder(2)
    end)
    return made and group or nil
end

--- One sparkle: a soft glow behind a four-pointed star.
local function MakeSpark(parent, spec)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(spec.size * 2, spec.size * 2)
    holder:SetPoint("CENTER", parent, "CENTER", spec.x, spec.y)

    local r, g, b = NodeSparkle.GOLD[1], NodeSparkle.GOLD[2], NodeSparkle.GOLD[3]
    local tinted = {}
    local pieces = {
        { file = NodeSparkle.GLOW, w = spec.size, h = spec.size, a = 0.45 },
        { file = NodeSparkle.STAR, w = spec.size * 2, h = spec.size * 2, a = 1 },
    }
    for _, piece in ipairs(pieces) do
        local texture = holder:CreateTexture(nil, "OVERLAY")
        texture:SetTexture(piece.file)
        texture:SetSize(piece.w, piece.h)
        texture:SetPoint("CENTER")
        pcall(texture.SetBlendMode, texture, "ADD")
        texture:SetVertexColor(r, g, b, piece.a)
        tinted[#tinted + 1] = { texture = texture, a = piece.a }
    end

    return { holder = holder, twinkle = Twinkle(holder, spec.delay), tinted = tinted }
end

--- The beacon: a beam standing on the spot, a soft flare at its foot, and
--- a slow pulse the game plays.
function NodeSparkle:MakeBeacon(parent)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(self.BEACON_WIDTH * 3, self.BEACON_HEIGHT)
    holder:SetPoint("BOTTOM", parent, "CENTER", 0, -6)
    local r, g, b = self.GOLD[1], self.GOLD[2], self.GOLD[3]

    local beam = holder:CreateTexture(nil, "OVERLAY")
    beam:SetTexture(self.BEAM)
    beam:SetSize(self.BEACON_WIDTH, self.BEACON_HEIGHT)
    beam:SetPoint("BOTTOM")
    pcall(beam.SetBlendMode, beam, "ADD")
    beam:SetVertexColor(r, g, b, 1)

    local flare = holder:CreateTexture(nil, "OVERLAY")
    flare:SetTexture(self.GLOW)
    flare:SetSize(self.BEACON_WIDTH * 3, self.BEACON_WIDTH * 1.4)
    flare:SetPoint("CENTER", holder, "BOTTOM", 0, 4)
    pcall(flare.SetBlendMode, flare, "ADD")
    flare:SetVertexColor(r, g, b, 0.8)

    local pulse
    local ok, group = pcall(holder.CreateAnimationGroup, holder)
    if ok and type(group) == "table" and pcall(function()
        group:SetLooping("BOUNCE")
        local dim = group:CreateAnimation("Alpha")
        dim:SetFromAlpha(1)
        dim:SetToAlpha(0.6)
        dim:SetDuration(self.PULSE)
        dim:SetSmoothing("IN_OUT")
    end) then
        pulse = group
    end
    holder:Hide()
    return { holder = holder, pulse = pulse,
        tinted = { { texture = beam, a = 1 }, { texture = flare, a = 0.8 } } }
end

function NodeSparkle:Build()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "BlackthornesFarmerNodeSparkle", UIParent)
    frame:SetSize(80, 60)
    pcall(frame.SetFrameStrata, frame, "BACKGROUND")
    pcall(frame.EnableMouse, frame, false)
    frame:Hide()

    self.sparks = {}
    for index, spec in ipairs(self.SPARKS) do
        self.sparks[index] = MakeSpark(frame, spec)
    end
    self.beacon = self:MakeBeacon(frame)
    local name = frame:CreateFontString(nil, "OVERLAY")
    if not pcall(name.SetFontObject, name, _G.GameFontNormalLarge) or not name:GetFont() then
        pcall(name.SetFont, name, "Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    end
    pcall(name.SetShadowColor, name, 0, 0, 0, 1)
    pcall(name.SetShadowOffset, name, 1, -1)
    name:SetPoint("TOP", frame, "CENTER", 0, -14)
    name:Hide()
    self.nameText = name
    self.frame = frame
    return frame
end

local function Moving()
    local level = ns.Motion and ns.Motion.Level and ns.Motion.Level() or "full"
    return level ~= "off"
end

--- The game's icon on the nameplate, when it has one we can read; the
--- sparkles gather round it. Read only: nothing is written on it.
function NodeSparkle.Icon(plate)
    local icon = Field(Field(plate, "UnitFrame"), "SoftTargetFrame")
    if type(icon) ~= "table" then return nil end
    local ok, kind = pcall(function() return icon:GetObjectType() end)
    if ok and type(kind) == "string" then return icon end
    return nil
end

--- How far down from the icon to put the sparkles: DROP, scaled by how
--- big the game draws the nameplate against the rest of the interface.
function NodeSparkle:Drop(plate)
    local ratio = 1
    local okPlate, plateScale = pcall(function() return plate:GetEffectiveScale() end)
    local okUI, uiScale = pcall(function() return UIParent:GetEffectiveScale() end)
    if okPlate and okUI and type(plateScale) == "number" and type(uiScale) == "number" and uiScale > 0 then
        ratio = plateScale / uiScale
    end
    if ratio ~= ratio or ratio <= 0 then ratio = 1 end
    return self.DROP * math.min(2, math.max(0.25, ratio))
end

--- Tint every sparkle and the beacon, only when the colour changed.
function NodeSparkle:Tint(color)
    color = color or self.GOLD
    if self.tint == color then return end
    self.tint = color
    local all = { self.beacon }
    for _, spark in ipairs(self.sparks or {}) do all[#all + 1] = spark end
    for _, light in ipairs(all) do
        for _, piece in ipairs(light.tinted or {}) do
            pcall(piece.texture.SetVertexColor, piece.texture, color[1], color[2], color[3], piece.a)
        end
    end
end

--- The colour for a skill against what a thing needs: orange, yellow,
--- green or grey (you lack the skill, or it is too low). Nil when the
--- skills could not be read at all.
function NodeSparkle.SkillColor(have, need, read)
    local colors = NodeSparkle.COLORS
    if type(need) ~= "number" then return nil end
    if type(have) ~= "number" then return read and colors.grey or nil end
    local over = have - need
    if over < 0 then return colors.grey end
    if over < NodeSparkle.ORANGE_TO then return colors.orange end
    if over < NodeSparkle.YELLOW_TO then return colors.yellow end
    return colors.green
end

function NodeSparkle:ColorsOn()
    return not (ns.db and ns.db.nodeSparkleColors == false)
end

--- What a thing of `kind` sparkles in. `level` is a corpse's.
function NodeSparkle:ColorFor(kind, name, level)
    if not self:ColorsOn() then return self.GOLD end
    local colors = self.COLORS
    if kind == "quest" then return colors.quest end
    if kind == "chest" or kind == "school" or kind == "bobber" then return colors.white end
    local skills = ns.Spots and ns.Spots.Skills and ns.Spots.Skills()
    local read = type(skills) == "table"
    if kind == "node" then
        local skill, need = self:NodeNeeds(name)
        if skill then
            return self.SkillColor(read and skills[skill] or nil, need, read) or self.GOLD
        end
    elseif kind == "corpse" then
        local need = ns.Grinding and ns.Grinding.SkinSkill(level)
        return self.SkillColor(read and skills.Skinning or nil, need, read) or self.GOLD
    end
    return self.GOLD
end

--- Where the screen marker stands: above the middle of the screen.
function NodeSparkle.ScreenOffset()
    local ok, height = pcall(function() return UIParent:GetHeight() end)
    if not ok or type(height) ~= "number" or height ~= height or height <= 0 then height = 768 end
    return height * NodeSparkle.SCREEN_Y
end

--- `plate` nil puts the marker in its spot on screen (Era), with `name`
--- under it.
function NodeSparkle:ShowSparkle(plate, guid, color, name)
    local frame = self:Build()
    if color then self.shownColor = color end
    self:Tint(self.shownColor)
    local onScreen = plate == nil or plate == self.SCREEN
    if onScreen then
        name = name or self.shownName
        self.shownName = name
    end
    local label = self.nameText
    if label then
        if onScreen and type(name) == "string" then
            local tint = self.shownColor or self.GOLD
            pcall(label.SetTextColor, label, tint[1], tint[2], tint[3], 1)
            label:SetText(name)
            label:Show()
        else
            label:Hide()
        end
    end
    plate = plate or self.SCREEN
    if self.shownOn ~= plate then
        frame:ClearAllPoints()
        local icon = not onScreen and self.Icon(plate) or nil
        if onScreen then
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, self.ScreenOffset())
        elseif icon then
            -- Under the game's icon, on the node itself.
            frame:SetPoint("CENTER", icon, "CENTER", 0, -self:Drop(plate))
        else
            -- Just above the node, under the name the game writes there.
            frame:SetPoint("BOTTOM", plate, "BOTTOM", 0, -10)
        end
    end
    self.shownOn, self.shownGuid = plate, guid

    local moving = Moving()
    local beacon = self.Style(self) == "beacon"
    local light = self.beacon
    if light then
        light.holder:SetShown(beacon)
        if beacon and light.pulse and moving then
            local ok, playing = pcall(light.pulse.IsPlaying, light.pulse)
            if not (ok and playing == true) then pcall(light.pulse.Play, light.pulse) end
        elseif light.pulse then
            pcall(light.pulse.Stop, light.pulse)
        end
    end
    for _, spark in ipairs(self.sparks) do
        local twinkle = spark.twinkle
        spark.holder:SetShown(not beacon)
        if beacon then
            if twinkle then pcall(twinkle.Stop, twinkle) end
        elseif twinkle and moving then
            spark.holder:SetAlpha(1)
            local ok, playing = pcall(twinkle.IsPlaying, twinkle)
            if not (ok and playing == true) then pcall(twinkle.Play, twinkle) end
        else
            if twinkle then pcall(twinkle.Stop, twinkle) end
            spark.holder:SetAlpha(0.85)
        end
    end
    if onScreen then
        -- No beam on screen: the arrow by your feet points the way.
        if light then
            light.holder:Hide()
            if light.pulse then pcall(light.pulse.Stop, light.pulse) end
        end
        for _, spark in ipairs(self.sparks) do
            spark.holder:Hide()
            if spark.twinkle then pcall(spark.twinkle.Stop, spark.twinkle) end
        end
        if self:ShowPointer(name, self.shownColor) then self:SayFound(guid) end
    else
        self:HidePointer()
        self:SayFound(guid)
    end
    frame:Show()
end

--------------------------------------------------------------------------------
-- The arrow by your feet (on screen, Era)
--------------------------------------------------------------------------------

local function Pulse(texture, low, delay)
    local ok, group = pcall(texture.CreateAnimationGroup, texture)
    if not ok or type(group) ~= "table" then return nil end
    local made = pcall(function()
        group:SetLooping("REPEAT")
        local dim = group:CreateAnimation("Alpha")
        dim:SetFromAlpha(1)
        dim:SetToAlpha(low)
        dim:SetDuration(NodeSparkle.POINTER_PULSE)
        dim:SetStartDelay(delay or 0)
        dim:SetSmoothing("IN_OUT")
        dim:SetOrder(1)
        local glow = group:CreateAnimation("Alpha")
        glow:SetFromAlpha(low)
        glow:SetToAlpha(1)
        glow:SetDuration(NodeSparkle.POINTER_PULSE)
        glow:SetSmoothing("IN_OUT")
        glow:SetOrder(2)
    end)
    return made and group or nil
end

function NodeSparkle:BuildPointer()
    if self.pointer then return self.pointer end
    local frame = CreateFrame("Frame", "BlackthornesFarmerNodePointer", UIParent)
    frame:SetSize(1, 1)
    pcall(frame.SetFrameStrata, frame, "BACKGROUND")
    pcall(frame.EnableMouse, frame, false)
    frame:Hide()

    local pieces = {}
    local arrow = frame:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture(self.ARROW)
    arrow:SetSize(self.ARROW_SIZE, self.ARROW_SIZE)
    pcall(arrow.SetBlendMode, arrow, "ADD")
    pieces[1] = { texture = arrow, at = self.POINTER_REACH, turn = true, part = "arrow",
        pulse = Pulse(arrow, 0.45, 0) }
    for index, dot in ipairs(self.TRAIL) do
        local texture = frame:CreateTexture(nil, "ARTWORK")
        texture:SetTexture(self.DOT)
        texture:SetSize(dot.size, dot.size)
        pcall(texture.SetBlendMode, texture, "ADD")
        pieces[#pieces + 1] = { texture = texture, at = dot.at, part = "arrow",
            pulse = Pulse(texture, 0.15, index * NodeSparkle.POINTER_PULSE / 3) }
    end
    for _, spark in ipairs(self.TRAIL_SPARKS) do
        local halo = frame:CreateTexture(nil, "ARTWORK")
        halo:SetTexture(self.GLOW)
        halo:SetSize(spark.size * 1.3, spark.size * 1.3)
        pcall(halo.SetBlendMode, halo, "ADD")
        pieces[#pieces + 1] = { texture = halo, at = self.TRAIL_BEAM.at, across = spark.x, lift = spark.y,
            part = "beam", style = "sparkles", alpha = self.TRAIL_SPARK_GLOW, pulse = Twinkle(halo, spark.delay) }
        local star = frame:CreateTexture(nil, "OVERLAY")
        star:SetTexture(self.STAR)
        star:SetSize(spark.size, spark.size)
        pcall(star.SetBlendMode, star, "ADD")
        pieces[#pieces + 1] = { texture = star, at = self.TRAIL_BEAM.at, across = spark.x, lift = spark.y,
            part = "beam", style = "sparkles", pulse = Twinkle(star, spark.delay) }
    end
    local spec = self.TRAIL_BEAM
    local flare = frame:CreateTexture(nil, "ARTWORK")
    flare:SetTexture(self.GLOW)
    flare:SetSize(spec.flare, spec.flare * 0.5)
    pcall(flare.SetBlendMode, flare, "ADD")
    pieces[#pieces + 1] = { texture = flare, at = spec.at, part = "beam", style = "beacon",
        pulse = Pulse(flare, 0.4, NodeSparkle.POINTER_PULSE) }
    local beam = frame:CreateTexture(nil, "OVERLAY")
    beam:SetTexture(self.BEAM)
    beam:SetSize(spec.width, spec.height)
    pcall(beam.SetBlendMode, beam, "ADD")
    pieces[#pieces + 1] = { texture = beam, at = spec.at, anchor = "BOTTOM", lift = -4, part = "beam", style = "beacon",
        pulse = Pulse(beam, 0.5, NodeSparkle.POINTER_PULSE) }

    local wait = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        wait = wait - (elapsed or 0)
        if wait > 0 then return end
        wait = NodeSparkle.POINTER_LOOK
        if not NodeSparkle:AimPointer() then NodeSparkle:HidePointer() end
    end)
    self.pointer = { frame = frame, pieces = pieces }
    return self.pointer
end

--- The spots Classic grows the node called `name` at on map `mapID`, as
--- { x, y } from 0 to 1, read from Data/NodeSpots.lua once a map and name.
--- A client in another language names the node in its own words.
function NodeSparkle:ShippedSpots(mapID, name)
    local zone = type(ns.NODE_SPOTS) == "table" and ns.NODE_SPOTS[mapID]
    if type(zone) ~= "table" then return nil end
    local packed = zone[name]
    if not packed and type(ns.NODE_NAMES) == "table" and type(GetLocale) == "function" then
        local ok, locale = pcall(GetLocale)
        local names = ok and ns.NODE_NAMES[locale]
        local english = type(names) == "table" and names[name]
        packed = english and zone[english]
    end
    if type(packed) ~= "string" then return nil end
    self.shippedCache = self.shippedCache or {}
    local found = self.shippedCache[packed]
    if found then return found end
    found = {}
    for at = 1, #packed - 5, 6 do
        local x, y = tonumber(packed:sub(at, at + 2)), tonumber(packed:sub(at + 3, at + 5))
        if x and y then found[#found + 1] = { x / 1000, y / 1000 } end
    end
    self.shippedCache[packed] = found
    return found
end

--- Where the node called `name` lies from you, as yards north and west,
--- from the nearest spot you gathered it at within POINT_YARDS, else the
--- nearest spot Classic grows it at within SHIPPED_YARDS in front of you
--- (the half you face). Nil when none is known or the client
--- will not say where you stand.
function NodeSparkle:PointerTarget(name)
    if type(name) ~= "string" or not ns.Gathering or not ns.Harvest then return nil end
    local mapID, x, y = ns.Harvest:PlayerMapPosition()
    if not (mapID and x and y) then return nil end
    local width, height = ns.Gathering.MapSize(mapID)
    if not (width and height) then return nil end
    local bestNorth, bestWest, best
    local reach, facing = self.POINT_YARDS, nil
    local function Consider(sx, sy)
        local north = (y - sy) * height
        local west = (x - sx) * width
        local yards = math.sqrt(north * north + west * west)
        if facing and yards >= self.NEAR_ENOUGH and math.cos(math.atan2(west, north) - facing) <= 0 then return end
        if yards <= reach and (not best or yards < best) then
            bestNorth, bestWest, best = north, west, yards
        end
    end
    for _, spot in ipairs(ns.Gathering:SpotsOn(mapID)) do
        if spot.node == name or (type(spot.also) == "table" and spot.also[name]) then
            Consider(tonumber(spot.x), tonumber(spot.y))
        end
    end
    if best then return bestNorth, bestWest, best end
    reach = self.SHIPPED_YARDS
    facing = ns.Arrow and ns.Arrow.Facing and ns.Arrow.Facing() or nil
    for _, spot in ipairs(self:ShippedSpots(mapID, name) or {}) do
        Consider(spot[1], spot[2])
    end
    return bestNorth, bestWest, best
end

--- Which way the arrow turns on screen: the node's bearing less your
--- facing, anticlockwise from straight ahead, and the yards to it. Nil
--- when it can't be read or you are standing on it.
function NodeSparkle:PointerTurn(name)
    local north, west, yards = self:PointerTarget(name)
    if not north or yards < self.NEAR_ENOUGH then return nil end
    local facing = ns.Arrow and ns.Arrow.Facing and ns.Arrow.Facing()
    if not facing then return nil end
    return math.atan2(west, north) - facing, yards
end

--- Turn the arrow and lay the trail along it. False when there is nothing
--- to point at.
function NodeSparkle:AimPointer()
    local pointer = self.pointer
    if not pointer or not self.pointName then return false end
    local turn, yards = self:PointerTurn(self.pointName)
    if not turn then return false end
    local look = self:PointerLook()
    local reach = look == "beam" and self.BeamReach(yards) or nil
    -- The end of the trail wears the Sparkle Look: a beam, or sparkles.
    local style = self:Style()
    -- Only a turn or a step the eye could see moves it.
    if pointer.turn and math.abs(turn - pointer.turn) < 0.01 and pointer.look == look
        and pointer.style == style
        and (not reach or math.abs(reach - (pointer.reach or 0)) < 1) then return true end
    pointer.turn, pointer.look, pointer.reach, pointer.style = turn, look, reach, style
    local ok, height = pcall(function() return UIParent:GetHeight() end)
    if not ok or type(height) ~= "number" or height ~= height or height <= 0 then height = 768 end
    local feet = -height * self.POINTER_Y
    local across, up = -math.sin(turn), math.cos(turn)
    for _, piece in ipairs(pointer.pieces) do
        local texture = piece.texture
        local at = (reach and piece.part == "beam") and reach or piece.at
        pcall(texture.SetShown, texture, (look == "both" or piece.part == look)
            and (not piece.style or piece.style == style))
        texture:ClearAllPoints()
        texture:SetPoint(piece.anchor or "CENTER", UIParent, "CENTER",
            across * at + (piece.across or 0), feet + up * at + (piece.lift or 0))
        if piece.turn then pcall(texture.SetRotation, texture, turn) end
    end
    return true
end

--- Show the arrow for the node called `name`, in `color`, when its spot is
--- known; hide it otherwise.
function NodeSparkle:ShowPointer(name, color)
    if type(name) ~= "string" then self:HidePointer(); return false end
    local pointer = self:BuildPointer()
    self.pointName, pointer.turn = name, nil
    if not self:AimPointer() then self:HidePointer(); return false end
    color = color or self.GOLD
    local moving = Moving()
    for _, piece in ipairs(pointer.pieces) do
        pcall(piece.texture.SetVertexColor, piece.texture, color[1], color[2], color[3], piece.alpha or 1)
        if piece.pulse and moving then
            local playing, on = pcall(piece.pulse.IsPlaying, piece.pulse)
            if not (playing and on == true) then pcall(piece.pulse.Play, piece.pulse) end
        elseif piece.pulse then
            pcall(piece.pulse.Stop, piece.pulse)
        end
    end
    pointer.frame:Show()
    return true
end

function NodeSparkle:HidePointer()
    self.pointName = nil
    local pointer = self.pointer
    if not pointer then return end
    for _, piece in ipairs(pointer.pieces) do
        if piece.pulse then pcall(piece.pulse.Stop, piece.pulse) end
    end
    pointer.frame:Hide()
end

function NodeSparkle:HideSparkle()
    self:HidePointer()
    self.shownOn, self.shownGuid, self.shownName = nil, nil, nil
    local frame = self.frame
    if not frame then return end
    for _, spark in ipairs(self.sparks or {}) do
        if spark.twinkle then pcall(spark.twinkle.Stop, spark.twinkle) end
    end
    if self.beacon and self.beacon.pulse then pcall(self.beacon.pulse.Stop, self.beacon.pulse) end
    frame:ClearAllPoints()
    frame:Hide()
end

--------------------------------------------------------------------------------
-- Skinnable corpses
--------------------------------------------------------------------------------

function NodeSparkle:CorpsesOn()
    return ns.db and ns.db.nodeSparkleCorpses == true or false
end

-- The game's tooltip line on a beast that can be skinned, and the English
-- word, in case a client has no global for it.
NodeSparkle.SKINNABLE_WORDS = { "Skinnable" }

local function SaysSkinnable(text)
    if type(text) ~= "string" or text == "" then return false end
    local own = Readable(_G.UNIT_SKINNABLE_LEATHER)
    if type(own) == "string" and own ~= "" and text == own then return true end
    for _, word in ipairs(NodeSparkle.SKINNABLE_WORDS) do
        if text == word then return true end
    end
    return false
end

--- The tooltip of what the interact key picks says it can be skinned.
function NodeSparkle:TooltipSkinnable()
    local get = Field(_G.C_TooltipInfo, "GetUnit")
    if type(get) ~= "function" then return false end
    local ok, data = pcall(get, UNIT)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return false end
    for _, line in ipairs(data.lines) do
        local text = type(line) == "table" and Readable(line.leftText) or nil
        if SaysSkinnable(text) then return true end
    end
    return false
end

--- A dead creature you could skin and have not: its level, or nil. Only
--- while "Skinnable Corpses" is ticked and you know Skinning.
function NodeSparkle:SkinnableCorpse(guid, name)
    if not self:CorpsesOn() then return nil end
    if type(guid) ~= "string" or not guid:find("^Creature%-") then return nil end
    if type(name) ~= "string" or name == "" then return nil end
    if not (ns.Grinding and ns.Grinding.SkinningSkill()) then return nil end
    local skinned = ns.GrindGather and ns.GrindGather.skinned
    if type(skinned) == "table" and skinned[guid] then return nil end
    if ns.DB and ns.DB:IsHiddenSource(name) then return nil end
    if type(UnitIsDead) ~= "function" then return nil end
    local ok, dead = pcall(UnitIsDead, UNIT)
    if not (ok and dead == true) then return nil end
    local log = ns.db and ns.db.skinLog
    if not (self:TooltipSkinnable() or (type(log) == "table" and type(log[name]) == "table")) then
        return nil
    end
    local level = 1
    if type(UnitLevel) == "function" then
        local got, value = pcall(UnitLevel, UNIT)
        value = got and ns.Harvest and ns.Harvest.ReadableNumber(value) or nil
        if type(value) == "number" and value > 0 then level = value end
    end
    return level
end

--- Look again at what the interact key points at.
-- @return "shown", "screen" (no nameplate: the marker on screen), "off",
-- "nothing" or "notnode"
function NodeSparkle:Refresh()
    if not self:IsEnabled() then self:HideSparkle(); return "off" end
    local guid, name, object = self:Facing()
    if guid and not object then
        local level = self:SkinnableCorpse(guid, name)
        if not level then self:HideSparkle(); return "nothing" end
        local plate = self:Plate(guid)
        self:ShowSparkle(plate, guid, self:ColorFor("corpse", name, level), name)
        return plate and "shown" or "screen"
    end
    if not guid then self:HideSparkle(); return "nothing" end
    local kind = self:Kind(name)
    if not kind then self:HideSparkle(); return "notnode" end
    local plate = self:Plate(guid)
    -- On screen the bobber gets nothing: it bobs off where you cast, and a
    -- mark in the middle of the screen can't follow it (the owner, 2026-10-25).
    if not plate and kind == "bobber" then self:HideSparkle(); return "nothing" end
    self:ShowSparkle(plate, guid, self:ColorFor(kind, name), name)
    return plate and "shown" or "screen"
end

--- The interact nameplate is only wanted for objects. On a creature the
--- game moves its name off its head onto that plate, where it is drawn
--- white and cut short, so while the interact key picks a creature the
--- setting goes back to what the player had (an object or nothing puts it
--- on again). Only when Farmer turned it on, never in a fight, and the
--- player's own value stays kept for when sparkles go off.
-- @return the value the setting should have now, or nil when left alone
function NodeSparkle:FitPlateToTarget()
    local db = ns.db
    if not db or not self:IsEnabled() or InCombat() then return nil end
    local saved = db.nodeSparkleCVars
    local own = type(saved) == "table" and saved.SoftTargetNameplateInteract or nil
    if own == nil then return nil end
    local guid, name, object = self:Facing()
    -- A corpse to skin keeps the plate: the sparkle hangs on it.
    local creature = guid and not object and not self:SkinnableCorpse(guid, name)
    local want = creature and own or "1"
    if self.GetCVar("SoftTargetNameplateInteract") ~= want then
        self.SetCVar("SoftTargetNameplateInteract", want)
    end
    return want
end

-- The game sets up a plate after the events that tell us about it, and may
-- light its pieces again then: look once more a moment later.
NodeSparkle.VEIL_AGAIN = 0.1

function NodeSparkle:SafeRefresh()
    pcall(self.FitPlateToTarget, self)
    pcall(self.VeilIcon, self)
    if not self.veilAgain then
        self.veilAgain = true
        After(self.VEIL_AGAIN, function()
            NodeSparkle.veilAgain = nil
            pcall(NodeSparkle.VeilIcon, NodeSparkle)
        end)
    end
    local ok, outcome = pcall(self.Refresh, self)
    if not ok then
        pcall(self.HideSparkle, self)
        return "nothing"
    end
    return outcome
end

function NodeSparkle:OnPlateRemoved(unit)
    if not self.shownOn then return end
    local plates = _G.C_NamePlate
    local forUnit = Field(plates, "GetNamePlateForUnit")
    local gone = true
    if type(forUnit) == "function" then
        local ok, plate = pcall(forUnit, UNIT)
        gone = not (ok and plate == self.shownOn)
    end
    if gone or unit == UNIT then self:SafeRefresh() end
end

function NodeSparkle:OnEnable()
    ns.RegisterEvent(self, "PLAYER_SOFT_INTERACT_CHANGED", function() NodeSparkle:SafeRefresh() end)
    ns.RegisterEvent(self, "NAME_PLATE_UNIT_ADDED", function() NodeSparkle:SafeRefresh() end)
    ns.RegisterEvent(self, "NAME_PLATE_UNIT_REMOVED", function(_, _, unit) NodeSparkle:OnPlateRemoved(unit) end)
    ns.RegisterEvent(self, "QUEST_LOG_UPDATE", function() NodeSparkle:QuestLogChanged() end)
    -- A fight: everything kept out of sight comes back first, while the
    -- game still lets it. The plate may go to the mob attacking you, whose
    -- bars must show; nothing is veiled again until the fight ends.
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function() NodeSparkle:UnveilAll() end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        if NodeSparkle.applyAfterCombat then NodeSparkle:ApplySettings() end
        if NodeSparkle.restoreAfterCombat then NodeSparkle:RestoreSettings() end
        if NodeSparkle.lowerAfterCombat and not NodeSparkle.fishing then NodeSparkle:LowerReach() end
        NodeSparkle:SafeRefresh()
    end)
    -- A controller plugged in or turned on brings the game's icon back.
    for _, event in ipairs({ "GAME_PAD_CONNECTED", "GAME_PAD_DISCONNECTED", "GAME_PAD_ACTIVE_CHANGED" }) do
        ns.RegisterEvent(self, event, function() NodeSparkle:SafeRefresh() end)
    end
    ns.RegisterEvent(self, "CVAR_UPDATE", function(_, _, name)
        if name == "GamePadEnable" then NodeSparkle:SafeRefresh() end
    end)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        -- A cast the game closed on keeps a raised reach: put it back first.
        if not NodeSparkle.fishing then NodeSparkle:LowerReach() end
        if NodeSparkle:IsEnabled() then NodeSparkle:ApplySettings() end
    end)
    ns.RegisterPlayerEvent(self, "UNIT_SPELLCAST_CHANNEL_START", function(_, _, unit, _, spellID)
        if Readable(unit) == "player" then NodeSparkle:FishingStarted(spellID) end
    end)
    ns.RegisterPlayerEvent(self, "UNIT_SPELLCAST_CHANNEL_STOP", function(_, _, unit)
        if Readable(unit) == "player" then NodeSparkle:FishingStopped() end
    end)
end

-- A source hidden or shown again: the node under the sparkle may be one.
ns.DB.hideWatchers.nodeSparkle = function() NodeSparkle:SafeRefresh() end

--------------------------------------------------------------------------------
-- The check, for a report: face a node and run it.
--------------------------------------------------------------------------------

function NodeSparkle:Check()
    ns.Print("sparkle check (face a herb or ore node first, or run it while your bobber is out):")
    ns.PrintRaw(("  setting: %s, %s"):format(self:IsEnabled() and "on" or "off", self:Style()))
    for _, cvar in ipairs(self.CVARS) do
        ns.PrintRaw(("  %s: %s"):format(cvar.name, tostring(self.GetCVar(cvar.name))))
    end
    local saved = ns.db and ns.db.nodeSparkleCVars
    if type(saved) == "table" then
        for name, value in pairs(saved) do
            ns.PrintRaw(("  kept to put back: %s = %s"):format(name, tostring(value)))
        end
    end
    ns.PrintRaw(("  fishing: %s, reach raised from: %s"):format(self.fishing and "yes" or "no",
        tostring(ns.db and ns.db.nodeSparkleFishingRange or "-")))
    ns.PrintRaw(("  C_NamePlate.GetNamePlateForUnit: %s"):format(
        type(Field(_G.C_NamePlate, "GetNamePlateForUnit")) == "function" and "yes" or "no"))

    local guid, name, object = self:Facing()
    local kind = type(guid) == "string" and guid:match("^(%a+)%-") or nil
    ns.PrintRaw(("  facing: %s (%s)"):format(tostring(name), tostring(kind or (guid and "?" or "nothing"))))
    ns.PrintRaw(("  a node Farmer knows: %s"):format(name and (self:IsNode(name) and "yes" or "no") or "-"))
    ns.PrintRaw(("  kind: %s"):format(name and tostring(self:Kind(name) or "none") or "-"))
    local skill, need = self:NodeNeeds(name)
    local color = self.shownColor or self.GOLD
    ns.PrintRaw(("  colors: %s, needs %s %s, corpses %s, skinnable corpse: %s, colour %.2f %.2f %.2f"):format(
        self:ColorsOn() and "on" or "off", tostring(skill or "-"), tostring(need or "-"),
        self:CorpsesOn() and "on" or "off", tostring(self:SkinnableCorpse(guid, name) or "no"),
        color[1], color[2], color[3]))
    ns.PrintRaw(("  quest: tooltip %s, looted before %s"):format(self:QuestInTooltip() and "yes" or "no",
        name and (self:QuestByLoot(name) and "yes" or "no") or "-"))
    local forUnit = Field(_G.C_NamePlate, "GetNamePlateForUnit")
    if object and type(forUnit) == "function" then
        local ok, any = pcall(forUnit, UNIT, true)
        local found = ok and type(any) == "table"
        local read, forbidden = false, nil
        if found then read, forbidden = pcall(function() return any:IsForbidden() end) end
        ns.PrintRaw(("  nameplate counting protected ones: %s"):format(
            found and ((read and forbidden == true) and "yes, protected" or "yes") or "no"))
    end
    local plate = object and self:Plate(guid) or nil
    ns.PrintRaw(("  nameplate for it: %s"):format(object and (plate and "yes" or "no") or "-"))
    ns.PrintRaw(("  game icon on it: %s"):format(plate and (self.Icon(plate) and "yes" or "no") or "-"))
    ns.PrintRaw(("  controller: %s, game icon hidden: %s"):format(self.Controller() and "yes" or "no",
        self:VeilIcon() and "yes" or "no"))
    local all = Field(_G.C_NamePlate, "GetNamePlates")
    if type(all) == "function" then
        local ok, list = pcall(all)
        ns.PrintRaw(("  nameplates showing: %s"):format(ok and type(list) == "table" and tostring(#list) or "?"))
    end
    ns.PrintRaw(("  sparkle: %s"):format(self:SafeRefresh()))
end

function NodeSparkle:SetColors(on)
    ns.db.nodeSparkleColors = on and true or false
    self:SafeRefresh()
end

function NodeSparkle:SetCorpses(on)
    ns.db.nodeSparkleCorpses = on and true or false
    self:SafeRefresh()
end

--- A corpse was just skinned: its sparkle goes.
function NodeSparkle:Skinned(guid)
    if guid and self.shownGuid == guid then self:SafeRefresh() end
end

ns.RegisterCommand("sparkle", L["turn sparkles on or off for the node, school, chest or quest object you face (beacon, sparkles, pointer, voice, colors, corpses, icon, check)"], function(rest)
    local argument = ns.Util.Trim(rest or ""):lower()
    local word, value = argument:match("^(%a+)%s*(%a*)$")
    if word == "colors" or word == "colours" then
        local on
        if value == "on" then on = true
        elseif value == "off" then on = false
        else on = not NodeSparkle:ColorsOn() end
        NodeSparkle:SetColors(on)
        ns.Print(on and L["sparkles show your skill color."] or L["sparkles are all gold."])
        if ns.SettingsUI then ns.SettingsUI:Refresh() end
        return
    end
    if word == "corpses" then
        local on
        if value == "on" then on = true
        elseif value == "off" then on = false
        else on = not NodeSparkle:CorpsesOn() end
        NodeSparkle:SetCorpses(on)
        ns.Print(on and L["corpses you can skin sparkle."] or L["corpses don't sparkle."])
        if ns.SettingsUI then ns.SettingsUI:Refresh() end
        return
    end
    if word == "voice" then
        local voice = (value == "off" or value == "character" or value == "peon") and value or nil
        if value == "try" then
            if not NodeSparkle:SayFound(nil, true) then ns.Print(L["pick a voice first."]) end
            return
        end
        if not voice then
            local voices, now = NodeSparkle.VOICES, NodeSparkle:Voice()
            for index, name in ipairs(voices) do
                if name == now then voice = voices[index % #voices + 1] end
            end
        end
        NodeSparkle:SetVoice(voice)
        ns.Print(voice == "character" and L["your character says \"Follow me!\" when the arrow finds a node."]
            or voice == "peon" and L["a peon speaks up when the arrow finds a node."]
            or L["no voice when the arrow finds a node."])
        if ns.SettingsUI then ns.SettingsUI:Refresh() end
        return
    end
    if word == "pointer" then
        local look = (value == "both" or value == "arrow" or value == "beam") and value or nil
        if not look then
            local looks, now = NodeSparkle.POINTER_LOOKS, NodeSparkle:PointerLook()
            for index, name in ipairs(looks) do
                if name == now then look = looks[index % #looks + 1] end
            end
        end
        NodeSparkle:SetPointerLook(look)
        ns.Print(look == "arrow" and L["the arrow and dots show the way to a node."]
            or look == "beam" and L["a beam stands toward the node."]
            or L["the arrow, dots and beam show the way to a node."])
        if ns.SettingsUI then ns.SettingsUI:Refresh() end
        return
    end
    if argument == "beacon" or argument == "sparkles" then
        NodeSparkle:SetStyle(argument)
        ns.Print(argument == "beacon" and L["a beacon shows the spot."] or L["sparkles show the spot."])
        if ns.SettingsUI then ns.SettingsUI:Refresh() end
        return
    end
    if argument == "icon" or argument == "icon show" or argument == "icon hide" then
        local hide
        if argument == "icon show" then hide = false
        elseif argument == "icon hide" then hide = true
        else hide = ns.db.nodeSparkleHideIcon == false end
        NodeSparkle:SetHideIcon(hide)
        ns.Print(hide and L["the game's interact icon is hidden unless you play with a controller."]
            or L["the game's interact icon shows."])
        if ns.SettingsUI then ns.SettingsUI:Refresh() end
        return
    end
    if argument == "check" then
        ns.KeepCheck("sparkle check", NodeSparkle.Check, NodeSparkle)
        return
    end
    local on
    if argument == "on" then on = true
    elseif argument == "off" then on = false
    else on = not NodeSparkle:IsEnabled() end
    NodeSparkle:SetEnabled(on)
    ns.Print(on and L["sparkles on."] or L["sparkles off."])
    if ns.SettingsUI then ns.SettingsUI:Refresh() end
end)
