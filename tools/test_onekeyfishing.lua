-- One key fishing: one key puts on a lure, casts, and reels in.
--
-- What must hold:
--   1. Off unless ticked, and nothing without a fishing pole in hand.
--   2. No lure on and a lure in the bags: the key puts on the best one.
--      A lure on, or none in the bags: the key casts Fishing.
--   3. While Fishing channels, the key is pointed at the game's interact
--      action, and soft interact reaches the bobber; it all goes back as the
--      channel ends or a fight starts.
--   4. Turned on with no key set, chat says where to set it.
--   5. While the line is out, the key reels in only while you face your
--      bobber; facing a vendor or a mailbox, it shows the note and opens
--      nothing. It follows what you face, and never changes in a fight.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("onekeyfishing")

local POLE, SWORD = 6256, 2488
local hand = POLE
local bags = { [6530] = 12, [6533] = 3 }
local lureLeft
local fighting = false
local boundKeys = {}
local overrides = {}
local cvars = { SoftTargetInteract = "1", SoftTargetInteractRange = "15" }
local BOBBER = "GameObject-0-4372-0-1234-35591-0000ABCDEF"
local MAILBOX = "GameObject-0-4372-0-1234-32349-0000ABCDEF"
local VENDOR = "Creature-0-4372-0-1234-1257-0000ABCDEF"
local facing, facingName = BOBBER, "Fishing Bobber"
local ns = env.Load({ ui = true })
_G.GetInventoryItemID = function(_, slot) if slot == 16 then return hand end end
_G.GetItemInfoInstant = function(id)
    if id == POLE then return id, "Weapon", "Fishing Poles", "INVTYPE_2HWEAPON", 1, 2, 20 end
    if id == SWORD then return id, "Weapon", "Swords", "INVTYPE_WEAPON", 1, 2, 7 end
    return id, "Trade Goods", "", "", 2000 + id, 0, 8
end
_G.GetItemCount = function(id) return bags[id] or 0 end
_G.GetItemInfo = function() return nil end
_G.GetSpellInfo = function(id) if id == 7620 then return "Fishing" end end
_G.GetWeaponEnchantInfo = function()
    if lureLeft then return true, lureLeft * 1000, 0, 263 end
    return false
end
_G.InCombatLockdown = function() return fighting end
_G.GetBindingKey = function() return unpack(boundKeys) end
_G.SetOverrideBinding = function(_, _, key, command) overrides[key] = command end
_G.ClearOverrideBindings = function() overrides = {} end
_G.GetCVar = function(name) return cvars[name] end
_G.SetCVar = function(name, value) cvars[name] = tostring(value) return true end
_G.C_CVar = { GetCVar = _G.GetCVar, SetCVar = _G.SetCVar }
local realGUID, realName = _G.UnitGUID, _G.UnitName
_G.UnitGUID = function(unit) if unit == "softinteract" then return facing end return realGUID and realGUID(unit) end
_G.UnitName = function(unit) if unit == "softinteract" then return facingName end return realName and realName(unit) end

local realCreate = _G.CreateFrame
_G.CreateFrame = function(kind, name, parent, template)
    local frame = realCreate(kind, name, parent, template)
    if template == "SecureActionButtonTemplate" then
        frame._attrs = {}
        frame.SetAttribute = function(self, key, value) self._attrs[key] = value end
        frame.GetAttribute = function(self, key) return self._attrs[key] end
    end
    return frame
end


for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end
local handler = _G.BlackthornesFarmerEventFrame:GetScript("OnEvent")
local function Fire(event, ...) handler(_G.BlackthornesFarmerEventFrame, event, ...) end

local Key = ns.OneKeyFishing
local button = _G.BlackthornesFarmerFishKey

suite.check("the key has its name on the Key Bindings page",
    _G["BINDING_NAME_CLICK BlackthornesFarmerFishKey:LeftButton"] == "Fish"
    and _G.BINDING_HEADER_BLACKTHORNESFARMER == "Blackthornes Farmer")

-- 1.
Fire("PLAYER_EQUIPMENT_CHANGED")
suite.check("off unless ticked", button and button:GetAttribute("type") == nil)

-- 4.
local before = #env.chat
Key:SetEnabled(true)
suite.check("no key set: chat says where", #env.chat == before + 1
    and env.chat[#env.chat]:find("Key Bindings", 1, true) ~= nil, tostring(env.chat[#env.chat]))
boundKeys = { "F" }
before = #env.chat
Key:SetEnabled(true)
suite.check("a key set: nothing said", #env.chat == before)

-- 2.
suite.check("no lure on: puts on the best lure", button:GetAttribute("type") == "macro"
    and button:GetAttribute("macrotext") == "/use item:6533\n/use 16", tostring(button:GetAttribute("macrotext")))
lureLeft = 600
Fire("UNIT_INVENTORY_CHANGED", "player")
suite.check("a lure on: casts Fishing", button:GetAttribute("type") == "spell"
    and button:GetAttribute("spell") == "Fishing", tostring(button:GetAttribute("type")))
lureLeft = nil
bags = {}
Fire("BAG_UPDATE_DELAYED")
suite.check("no lure in the bags: casts", button:GetAttribute("type") == "spell")
hand = SWORD
Fire("PLAYER_EQUIPMENT_CHANGED")
suite.check("no pole: does nothing", button:GetAttribute("type") == nil)
hand = POLE
Fire("PLAYER_EQUIPMENT_CHANGED")

-- 3.
Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
suite.check("fishing: the key reels in", overrides.F == "INTERACTTARGET")
suite.check("soft interact on for every input", cvars.SoftTargetInteract == "3"
    and ns.db.oneKeyFishingInteract == "1")
suite.check("and it reaches the bobber", tonumber(cvars.SoftTargetInteractRange) >= 35)
Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player")
suite.check("fishing stops: the key is back", overrides.F == nil)
suite.check("soft interact put back", cvars.SoftTargetInteract == "1" and ns.db.oneKeyFishingInteract == nil)
suite.check("and its reach", cvars.SoftTargetInteractRange == "15", cvars.SoftTargetInteractRange)

-- 5.
local NOTE = "CLICK BlackthornesFarmerFishNote:LeftButton"
facing, facingName = MAILBOX, "Mailbox"
Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
suite.check("facing a mailbox: the key opens nothing", overrides.F == NOTE, tostring(overrides.F))
local note = _G.BlackthornesFarmerFishNote
note:GetScript("OnClick")(note, "LeftButton")
local shown = ns.OpenNote.frame
suite.check("and shows the note", shown and shown:IsShown()
    and shown.label:GetText() == "Face your bobber to reel in.", shown and tostring(shown.label:GetText()))
facing, facingName = BOBBER, "Fishing Bobber"
Fire("PLAYER_SOFT_INTERACT_CHANGED")
suite.check("facing the bobber: the key reels in", overrides.F == "INTERACTTARGET")
facing, facingName = VENDOR, "Innkeeper"
Fire("PLAYER_SOFT_INTERACT_CHANGED")
suite.check("facing a vendor: the note again", overrides.F == NOTE)
facing, facingName = nil, nil
Fire("PLAYER_SOFT_INTERACT_CHANGED")
suite.check("facing nothing: the note", overrides.F == NOTE)
facing, facingName = "GameObject-0-4372-0-1234-99999-0000ABCDEF", "Fishing Bobber"
Fire("PLAYER_SOFT_INTERACT_CHANGED")
suite.check("a bobber known by its name reels in", overrides.F == "INTERACTTARGET")
facing, facingName = MAILBOX, "Mailbox"
fighting = true
Fire("PLAYER_SOFT_INTERACT_CHANGED")
suite.check("nothing changes in a fight", overrides.F == "INTERACTTARGET")
fighting = false
Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player")
suite.check("the line in: the key is back", overrides.F == nil)
Fire("PLAYER_SOFT_INTERACT_CHANGED")
suite.check("and stays back", overrides.F == nil)
suite.check("bobber IDs read from the guid", Key.IsBobber(BOBBER) and not Key.IsBobber(MAILBOX)
    and not Key.IsBobber(VENDOR, "Fishing Bobber") and not Key.IsBobber(nil))
facing, facingName = BOBBER, "Fishing Bobber"

Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
Fire("PLAYER_REGEN_DISABLED")
suite.check("a fight puts the key back", overrides.F == nil and cvars.SoftTargetInteract == "1")
fighting = true
Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
suite.check("nothing changes in a fight", overrides.F == nil)
fighting = false
Fire("PLAYER_REGEN_ENABLED")

Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 12345)
suite.check("another channel leaves the key alone", overrides.F == nil)

Key:SetEnabled(false)
Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
suite.check("turned off: the key does nothing", button:GetAttribute("type") == nil and overrides.F == nil)

_G.CreateFrame = realCreate
_G.GetInventoryItemID, _G.GetItemInfoInstant, _G.GetItemCount, _G.GetItemInfo, _G.GetSpellInfo = nil, nil, nil, nil, nil
_G.GetWeaponEnchantInfo, _G.InCombatLockdown, _G.GetBindingKey, _G.SetOverrideBinding = nil, nil, nil, nil
_G.ClearOverrideBindings, _G.GetCVar, _G.SetCVar, _G.C_CVar = nil, nil, nil, nil
_G.UnitGUID, _G.UnitName = realGUID, realName

suite.done()
