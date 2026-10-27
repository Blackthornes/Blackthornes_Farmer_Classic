-- Blackthornes Farmer -- UI/FishingCheck.lua
-- `/farm fishing check` (the owner asked how to test a "PULL!" alert,
-- 2026-10-27): the game says nothing to addons when a fish bites, so this
-- watches what does change during a cast, to find something that lines up
-- with the splash. Typed only, never in help or Settings, and in English
-- like every check.
--
-- Armed, each Fishing cast (up to CASTS, or for ARMED_FOR seconds) is
-- watched from the channel's start until a moment after it ends: every
-- event the game sends (a frame registered for all of them only during the
-- cast; chat and the combat log left out, so no one's name or words are
-- kept, and no event's values beyond a unit token or the game's own error
-- text), and, every POLL seconds, the soft interact target, the mouseover,
-- the bobber's nameplate and the game's icon on it, written down only when
-- one changes (a name only as "changed", never the name). The loot window's opening is the click at the splash, so
-- whatever changes a little before it every time is the bite.
--
-- Each finished cast rewrites lastProbe (the same shape ns.KeepCheck saves),
-- so a /reload at any point keeps what was seen. It only reads; nothing is
-- touched on a game frame.

local _, ns = ...

local FishingCheck = ns.NewModule("FishingCheck")

FishingCheck.CASTS = 8
FishingCheck.ARMED_FOR = 15 * 60
FishingCheck.POLL = 0.05
-- How long after the channel ends it keeps watching, for the loot window.
FishingCheck.AFTER = 1.5
-- An event seen more often than this in one cast is only counted.
FishingCheck.EVENT_TIMES = 4
-- Lines a cast at most, so a busy place can't flood the save.
FishingCheck.CAST_LINES = 120

-- Never kept: other people's words and names, and the busiest streams.
FishingCheck.SKIP_PREFIX = { "CHAT_MSG_", "COMBAT_LOG_EVENT" }
FishingCheck.SKIP = {
    UPDATE_CHAT_WINDOWS = true, CHAT_MSG = true, GUILD_ROSTER_UPDATE = true,
    FRIENDLIST_UPDATE = true, WHO_LIST_UPDATE = true, PLAYER_FLAGS_CHANGED = true,
}
-- Settings worth knowing beside the results.
FishingCheck.CVARS = {
    "SoftTargetInteract", "SoftTargetInteractRange", "SoftTargetInteractArc",
    "SoftTargetNameplateInteract", "SoftTargetIconGameObject", "SoftTargetIconInteract",
    "autoLootDefault", "Sound_EnableSFX",
}

local function Now()
    local ok, now = pcall(GetTime or error)
    return ok and type(now) == "number" and now or 0
end

-- A value off the client as text, or what kept it from being read.
local function Describe(value)
    local Harvest = ns.Harvest
    if Harvest and Harvest.Describe then return Harvest.Describe(value) end
    local ok, text = pcall(function() return tostring(value) .. "" end)
    return ok and text or "unreadable"
end

local function CallText(fn, ...)
    if type(fn) ~= "function" then return "no such call" end
    local results = { pcall(fn, ...) }
    if not results[1] then return "raised" end
    local parts = {}
    for i = 2, math.max(#results, 2) do parts[#parts + 1] = Describe(results[i]) end
    return table.concat(parts, ", ")
end

-- A unit token is safe to keep ("player", "nameplate3"); anything else is not.
local function UnitToken(value)
    local ok, token = pcall(function()
        if type(value) == "string" and value:match("^%a+%d*$") and #value <= 20 then return value .. "" end
    end)
    return ok and token or nil
end

function FishingCheck.Skipped(event)
    if FishingCheck.SKIP[event] then return true end
    for _, prefix in ipairs(FishingCheck.SKIP_PREFIX) do
        if event:sub(1, #prefix) == prefix then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- What it watches
--------------------------------------------------------------------------------

local function PlateOf(unit)
    local plates = _G.C_NamePlate
    local forUnit = type(plates) == "table" and plates.GetNamePlateForUnit
    if type(forUnit) ~= "function" then return nil end
    local ok, plate = pcall(forUnit, unit)
    return ok and type(plate) == "table" and plate or nil
end

local function Shown(frame)
    if type(frame) ~= "table" then return "none" end
    local ok, shown = pcall(function() return frame:IsVisible() end)
    if not ok then return "unreadable" end
    return shown and "shown" or "hidden"
end

local function Alpha(frame)
    local ok, alpha = pcall(function() return frame:GetAlpha() end)
    return ok and type(alpha) == "number" and ("%.2f"):format(alpha) or "?"
end

--- Everything polled, as label = text. Only changes are written down.
function FishingCheck:Read()
    local state = {}
    for _, unit in ipairs({ "softinteract", "mouseover" }) do
        state[unit .. " exists"] = CallText(_G.UnitExists, unit)
        state[unit .. " name"] = CallText(_G.UnitName, unit)
    end
    -- The bobber's own GUID changes with each cast; only whether it moved.
    state["softinteract guid"] = CallText(_G.UnitGUID, "softinteract")
    local plate = PlateOf("softinteract")
    state["bobber plate"] = Shown(plate)
    local sparkle = ns.NodeSparkle
    local icon = plate and sparkle and sparkle.Icon and sparkle.Icon(plate)
    state["bobber icon"] = Shown(icon)
    if icon then
        state["bobber icon alpha"] = Alpha(icon)
        local tex = icon.Icon or icon.icon
        local ok, texture = pcall(function() return tex:GetTexture() end)
        state["bobber icon texture"] = ok and Describe(texture) or "none"
        local gotAtlas, atlas = pcall(function() return tex:GetAtlas() end)
        state["bobber icon atlas"] = gotAtlas and Describe(atlas) or "none"
    end
    state["channel"] = CallText(_G.UnitChannelInfo, "player")
    return state
end

--------------------------------------------------------------------------------
-- A cast
--------------------------------------------------------------------------------

function FishingCheck:Note(text)
    local cast = self.cast
    if not cast then return end
    if #cast.lines >= self.CAST_LINES then
        cast.cut = (cast.cut or 0) + 1
        return
    end
    cast.lines[#cast.lines + 1] = ("  %+.2f %s"):format(Now() - cast.start, text)
end

function FishingCheck:Poll()
    local cast = self.cast
    if not cast then return end
    local state = self:Read()
    for label, text in pairs(state) do
        local was = cast.state[label]
        if was ~= text then
            -- Names are never written down (the owner, 2026-10-27): only
            -- that one changed, so no player's name reaches the save.
            if label == "softinteract guid" or label == "channel"
                or label:find(" name$") then
                if was ~= nil then self:Note(label .. " changed") end
            else
                self:Note(("%s: %s"):format(label, text))
            end
        end
    end
    for label in pairs(cast.state) do
        if state[label] == nil then self:Note(label .. ": gone") end
    end
    cast.state = state
end

function FishingCheck:OnEvent(event, ...)
    local cast = self.cast
    if not cast or FishingCheck.Skipped(event) then return end
    local count = (cast.events[event] or 0) + 1
    cast.events[event] = count
    if count > self.EVENT_TIMES then return end
    local extra = ""
    local first = ...
    if event == "UI_ERROR_MESSAGE" or event == "UI_INFO_MESSAGE" then
        extra = " " .. Describe(select(2, ...))
    elseif event == "LOOT_OPENED" or event == "LOOT_READY" then
        extra = " fishing loot " .. CallText(_G.IsFishingLoot)
    elseif UnitToken(first) then
        extra = " " .. UnitToken(first)
    end
    self:Note(event .. extra)
end

function FishingCheck:Watcher()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame")
    frame:Hide()
    frame:SetScript("OnEvent", function(_, event, ...)
        FishingCheck:OnEvent(event, ...)
    end)
    local waited = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + (elapsed or 0)
        if waited < FishingCheck.POLL then return end
        waited = 0
        FishingCheck:Poll()
        local cast = FishingCheck.cast
        if cast and cast.stopped and Now() - cast.stopped >= FishingCheck.AFTER then
            FishingCheck:Finish()
        end
    end)
    self.frame = frame
    return frame
end

function FishingCheck:Begin()
    if not self.armed or self.cast then return end
    if Now() > self.armed then
        self:Disarm("time ran out")
        return
    end
    self.cast = { start = Now(), lines = {}, events = {}, state = {} }
    self.casts = (self.casts or 0) + 1
    local frame = self:Watcher()
    pcall(function() frame:RegisterAllEvents() end)
    frame:Show()
    self:Note("cast " .. self.casts .. " started")
    self:Poll()
end

function FishingCheck:Stopped()
    local cast = self.cast
    if not cast or cast.stopped then return end
    cast.stopped = Now()
    self:Note("channel ended")
end

function FishingCheck:Finish()
    local cast = self.cast
    if not cast then return end
    local frame = self.frame
    if frame then
        pcall(function() frame:UnregisterAllEvents() end)
        frame:Hide()
    end
    self.cast = nil
    local lines = self.lines
    lines[#lines + 1] = ("cast %d:"):format(self.casts)
    for _, line in ipairs(cast.lines) do lines[#lines + 1] = line end
    if cast.cut then lines[#lines + 1] = ("  (%d more lines left out)"):format(cast.cut) end
    local counted = {}
    for event, count in pairs(cast.events) do
        if count > self.EVENT_TIMES then counted[#counted + 1] = ("%s x%d"):format(event, count) end
    end
    table.sort(counted)
    if #counted > 0 then lines[#lines + 1] = "  busy events: " .. table.concat(counted, ", ") end
    self:Save()
    if self.casts >= self.CASTS then
        self:Disarm("done")
    else
        ns.Print(("fishing check: cast %d of %d kept."):format(self.casts, self.CASTS))
    end
end

--- lastProbe, in the shape ns.KeepCheck saves, rewritten after each cast.
function FishingCheck:Save()
    if type(ns.db) ~= "table" then return end
    local lines = {}
    for i, line in ipairs(self.lines) do lines[i] = line end
    ns.db.lastProbe = {
        check = "fishing check",
        at = type(date) == "function" and date("%Y-%m-%d %H:%M:%S") or nil,
        version = ns.VERSION,
        lines = lines,
    }
end

--------------------------------------------------------------------------------
-- Arming
--------------------------------------------------------------------------------

function FishingCheck:Arm()
    self.armed = Now() + self.ARMED_FOR
    self.casts = 0
    self.cast = nil
    local lines = { "fishing check, a cast at a time:" }
    for _, name in ipairs(self.CVARS) do
        local sparkle = ns.NodeSparkle
        local value = sparkle and sparkle.GetCVar and sparkle.GetCVar(name)
        lines[#lines + 1] = ("  cvar %s: %s"):format(name, Describe(value))
    end
    local OneKey = ns.OneKeyFishing
    lines[#lines + 1] = ("  one key fishing: %s, %d key(s)"):format(
        OneKey and OneKey:Enabled() and "on" or "off", OneKey and #OneKey.Keys() or 0)
    lines[#lines + 1] = "  sparkles: " .. (ns.NodeSparkle and ns.NodeSparkle:IsEnabled() and "on" or "off")
    self.lines = lines
    self:Save()
    ns.Print(("fishing check on: fish %d catches, clicking the bobber as soon as it splashes. Then /reload."):format(self.CASTS))
end

function FishingCheck:Disarm(why)
    local was = self.armed
    self.armed = nil
    if self.cast then self:Finish() end
    if was then
        ns.Print(("fishing check %s. Type /reload and tell Claude \"read the probe\"."):format(why or "off"))
        ns.Print("Saved for Claude, /reload to write it.")
    end
end

function FishingCheck:OnEnable()
    ns.RegisterPlayerEvent(self, "UNIT_SPELLCAST_CHANNEL_START", function(_, _, unit, _, spellID)
        if not FishingCheck.armed or Describe(unit) ~= "player" then return end
        local sparkle = ns.NodeSparkle
        if sparkle and sparkle.IsFishingCast and sparkle.IsFishingCast(spellID) then FishingCheck:Begin() end
    end)
    ns.RegisterPlayerEvent(self, "UNIT_SPELLCAST_CHANNEL_STOP", function(_, _, unit)
        if FishingCheck.cast and Describe(unit) == "player" then FishingCheck:Stopped() end
    end)
end
