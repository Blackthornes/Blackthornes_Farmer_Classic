-- /farm fishing check: watches casts for what changes when a fish bites.
--
-- What must hold:
--   1. Nothing is watched until it is armed, and only Fishing casts.
--   2. A cast keeps its events and the bobber's changes, with times, and
--      lastProbe is written after each cast.
--   3. Chat and the combat log are never kept (no one's name or words).
--   4. It stops after CASTS casts and says to /reload.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("fishingcheck")

local ns = env.Load({ ui = true })
local now = 100
_G.GetTime = function() return now end
_G.GetSpellInfo = function(id) if id == 7620 then return "Fishing" end end
_G.IsFishingLoot = function() return true end
local softName
_G.UnitExists = function(unit) return unit == "softinteract" and softName ~= nil end
_G.UnitName = function(unit) if unit == "softinteract" then return softName end end
_G.UnitGUID = function() return nil end
_G.UnitChannelInfo = function() return nil end

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end
local handler = _G.BlackthornesFarmerEventFrame:GetScript("OnEvent")
local function Fire(event, ...) handler(_G.BlackthornesFarmerEventFrame, event, ...) end

local Check = ns.FishingCheck
local function Tick(seconds)
    now = now + seconds
    Check.frame:GetScript("OnUpdate")(Check.frame, seconds)
end
local function Watch(event, ...) Check.frame:GetScript("OnEvent")(Check.frame, event, ...) end

-- 1.
Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
suite.check("not armed: nothing watched", Check.cast == nil and ns.db.lastProbe == nil)

ns.commands.fishing.fn("check")
suite.check("armed from the fishing command", Check.armed ~= nil
    and ns.db.lastProbe and ns.db.lastProbe.check == "fishing check")
suite.check("not in help", not ns.commands.check)

Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 133)
suite.check("another spell: nothing watched", Check.cast == nil)

-- 2.
Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
suite.check("a Fishing cast is watched", Check.cast ~= nil)
softName = "Fishing Bobber"
Tick(1)
Watch("CHAT_MSG_SAY", "hello", "Someone-Realm")
Watch("COMBAT_LOG_EVENT_UNFILTERED")
Watch("SOUNDKIT_FINISHED", 12345)
Tick(2)
Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player")
Watch("LOOT_OPENED", false)
Tick(2)
suite.check("the cast is finished after the loot window", Check.cast == nil)

local text = table.concat(ns.db.lastProbe.lines, "\n")
suite.check("the bobber's name is kept with its time",
    text:find("+1.00 softinteract name: Fishing Bobber", 1, true) ~= nil, text)
suite.check("events are kept", text:find("SOUNDKIT_FINISHED", 1, true) ~= nil
    and text:find("LOOT_OPENED fishing loot true", 1, true) ~= nil, text)
suite.check("the channel's end is kept", text:find("channel ended", 1, true) ~= nil)
-- 3.
suite.check("no chat or combat log kept", not text:find("CHAT_MSG", 1, true)
    and not text:find("Someone", 1, true) and not text:find("COMBAT_LOG", 1, true))
suite.check("settings noted", text:find("cvar SoftTargetInteract:", 1, true) ~= nil)

-- 4.
for _ = 2, Check.CASTS do
    Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
    Tick(1)
    Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    Tick(2)
end
suite.check("stops after its casts", Check.armed == nil)
suite.check("and says to reload", env.chat[#env.chat - 1]:find("/reload", 1, true) ~= nil,
    tostring(env.chat[#env.chat - 1]))
Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
suite.check("nothing watched after", Check.cast == nil)

_G.GetTime, _G.GetSpellInfo, _G.IsFishingLoot, _G.UnitExists = nil, nil, nil, nil
_G.UnitName, _G.UnitGUID, _G.UnitChannelInfo = nil, nil, nil

suite.done()
