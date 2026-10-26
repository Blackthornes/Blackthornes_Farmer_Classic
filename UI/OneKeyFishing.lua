-- Blackthornes Farmer -- UI/OneKeyFishing.lua
-- One key fishing (a player asked, the owner said build it, 2026-10-26,
-- words approved): one key in the game's Key Bindings, "Fish" under
-- Blackthornes Farmer. With a fishing pole in the main hand and no lure on,
-- it puts on the best lure in the bags; otherwise it casts Fishing. While
-- the line is out, the same key reels in.
--
-- The key clicks a hidden secure button (`BlackthornesFarmerFishKey`), whose
-- attributes are set only out of combat: a macro that puts the lure on (the
-- fishing bar's `LureMacro`), else the Fishing spell, else nothing. Reeling
-- in is the game's own Interact With Target on the bobber: while Fishing
-- channels, the key is pointed at INTERACTTARGET with an override binding
-- (`SetOverrideBinding`, out of combat only), and the override goes as the
-- channel ends or a fight starts. The bobber is the interact target only
-- when soft interact reaches it, so for the cast the reach is raised as the
-- sparkles do (`NodeSparkle:RaiseReach(true)`) and `SoftTargetInteract` is
-- turned to all input (3) when lower; what it was waits in
-- `oneKeyFishingInteract` and is put back when the channel ends (or at the
-- next login, if the game closed mid-cast).
--
-- Never in a fight, never touching a game frame. Off unless ticked: "One
-- Key Fishing:" under FISHING on the Loot page (`oneKeyFishing`). Both keys
-- are account wide; never rename them.

local _, ns = ...
local L = ns.L

local OneKeyFishing = ns.NewModule("OneKeyFishing")

OneKeyFishing.BUTTON = "BlackthornesFarmerFishKey"
OneKeyFishing.BINDING = "CLICK " .. OneKeyFishing.BUTTON .. ":LeftButton"
OneKeyFishing.REEL = "INTERACTTARGET"
-- Soft interact on for keyboard, mouse and gamepad alike.
OneKeyFishing.INTERACT_ALL = 3
OneKeyFishing.SETTLE = 0.2

-- The Key Bindings page names. "Fish" is the verb here, and other languages
-- word it apart from the Grind tab's "Fish" (the noun), so it has its own
-- key, read as plain "Fish" where no translation gives it.
local function KeyName()
    local named = L["Fish (key binding)"]
    if named == "Fish (key binding)" then return "Fish" end
    return named
end
OneKeyFishing.KEY_NAME = KeyName()
_G.BINDING_HEADER_BLACKTHORNESFARMER = L["Blackthornes Farmer"]
_G["BINDING_NAME_" .. OneKeyFishing.BINDING] = OneKeyFishing.KEY_NAME

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2)
end

local function InCombat()
    return Call(rawget(_G, "InCombatLockdown")) and true or false
end

local function Readable(value)
    local ok, text = pcall(function()
        if type(value) == "string" then return value .. "" end
    end)
    return ok and text or nil
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

function OneKeyFishing:Enabled()
    return ns.db ~= nil and ns.db.oneKeyFishing == true
end

--- The keys bound to Fish, or none.
function OneKeyFishing.Keys()
    local keys = { Call(rawget(_G, "GetBindingKey"), OneKeyFishing.BINDING) }
    local list = {}
    for _, key in ipairs(keys) do
        key = Readable(key)
        if key and key ~= "" then list[#list + 1] = key end
    end
    return list
end

function OneKeyFishing:SetEnabled(on)
    ns.db.oneKeyFishing = on and true or false
    if on and #self.Keys() == 0 then
        ns.Print(L["Pick a key for Fish in the game's Key Bindings, under Blackthornes Farmer."])
    end
    if not on then self:StopReel() end
    self:Changed()
end

--------------------------------------------------------------------------------
-- The key's button
--------------------------------------------------------------------------------

function OneKeyFishing:Build()
    if self.button then return self.button end
    local button = CreateFrame("Button", self.BUTTON, UIParent, "SecureActionButtonTemplate")
    button:Hide()
    -- A binding clicks on the key going down and coming up; registered for
    -- the release only, with useOnKeyDown off, it acts once a press.
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    self.button = button
    return button
end

--- What the key does now: "lure" (and the lure's ID), "cast" or nil.
function OneKeyFishing:Action()
    local Bar = ns.FishingBar
    if not self:Enabled() or not Bar or not Bar.HasPole() then return nil end
    if not Bar.LureLeft() then
        local best = Bar.ReadLures()[1]
        if best then return "lure", best.id end
    end
    return "cast"
end

--- Aim the button at what the key does now. Out of combat only.
function OneKeyFishing:Draw()
    if InCombat() then return end
    local button = self:Build()
    local action, lure = self:Action()
    if action == "lure" then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", ns.FishingBar.LureMacro(lure))
        button:SetAttribute("spell", nil)
    elseif action == "cast" then
        button:SetAttribute("type", "spell")
        button:SetAttribute("spell", ns.FishingBar.SpellName())
        button:SetAttribute("macrotext", nil)
    else
        button:SetAttribute("type", nil)
        button:SetAttribute("spell", nil)
        button:SetAttribute("macrotext", nil)
    end
    self.action = action
end

--- Something moved: look again once, a moment after the burst.
function OneKeyFishing:Changed()
    if self.pending then return end
    self.pending = true
    C_Timer.After(self.SETTLE, function()
        OneKeyFishing.pending = false
        OneKeyFishing:Draw()
    end)
end

--------------------------------------------------------------------------------
-- Reeling in
--------------------------------------------------------------------------------

--- Fishing started: point the key at the bobber.
function OneKeyFishing:StartReel()
    if not self:Enabled() or InCombat() or self.reeling then return false end
    local keys = self.Keys()
    if #keys == 0 then return false end
    local owner = self:Build()
    for _, key in ipairs(keys) do
        Call(rawget(_G, "SetOverrideBinding"), owner, true, key, self.REEL)
    end
    self.reeling = true
    local sparkle = ns.NodeSparkle
    if sparkle then
        if sparkle.RaiseReach then sparkle:RaiseReach(true) end
        local now = tonumber(sparkle.GetCVar("SoftTargetInteract") or "")
        if now and now < self.INTERACT_ALL then
            if ns.db.oneKeyFishingInteract == nil then ns.db.oneKeyFishingInteract = tostring(now) end
            sparkle.SetCVar("SoftTargetInteract", tostring(self.INTERACT_ALL))
        end
    end
    return true
end

--- Put the soft interact setting back as it was before the cast.
function OneKeyFishing:PutBack()
    local kept = ns.db and ns.db.oneKeyFishingInteract
    if kept == nil or InCombat() then return end
    local sparkle = ns.NodeSparkle
    if sparkle and sparkle.SetCVar("SoftTargetInteract", kept) then ns.db.oneKeyFishingInteract = nil end
end

--- Fishing stopped or a fight is starting: the key goes back to normal.
function OneKeyFishing:StopReel()
    if self.reeling and self.button then
        Call(rawget(_G, "ClearOverrideBindings"), self.button)
    end
    self.reeling = false
    self:PutBack()
    local sparkle = ns.NodeSparkle
    if sparkle and not sparkle.fishing and sparkle.LowerReach then sparkle:LowerReach() end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function OneKeyFishing:OnEnable()
    self:Build()
    for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED",
            "GET_ITEM_INFO_RECEIVED", "SPELLS_CHANGED" }) do
        ns.RegisterEvent(self, event, function() OneKeyFishing:Changed() end)
    end
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        if not OneKeyFishing.reeling then OneKeyFishing:PutBack() end
        OneKeyFishing:Changed()
    end)
    -- A lure going on or wearing off.
    ns.RegisterPlayerEvent(self, "UNIT_INVENTORY_CHANGED", function(_, _, unit)
        if Readable(unit) == "player" then OneKeyFishing:Changed() end
    end)
    ns.RegisterPlayerEvent(self, "UNIT_SPELLCAST_CHANNEL_START", function(_, _, unit, _, spellID)
        if Readable(unit) ~= "player" then return end
        local sparkle = ns.NodeSparkle
        local fishing = sparkle and sparkle.IsFishingCast and sparkle.IsFishingCast(spellID)
        if fishing then OneKeyFishing:StartReel() end
    end)
    ns.RegisterPlayerEvent(self, "UNIT_SPELLCAST_CHANNEL_STOP", function(_, _, unit)
        if Readable(unit) == "player" and OneKeyFishing.reeling then OneKeyFishing:StopReel() end
    end)
    -- Just before combat locks bindings: back to normal.
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function() OneKeyFishing:StopReel() end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        OneKeyFishing:PutBack()
        OneKeyFishing:Changed()
    end)
end
