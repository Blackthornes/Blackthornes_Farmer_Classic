-- The fishing bar: Cast and Add Lure while a fishing pole is in the hand.
--
-- What must hold:
--   1. Off unless ticked, and only while a fishing pole is in the main hand.
--   2. Cast casts Fishing; each lure row puts its lure on the pole, best first.
--   3. The lure line says how long the lure lasts, or that none is on.
--   4. Hidden in a fight and at a vendor; the close gem puts it away until
--      the pole comes off and goes on again.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("fishingbar")

local realCreate = _G.CreateFrame
local function Create(kind, name, parent, template)
    local frame = realCreate(kind, name, parent, template)
    if template == "SecureActionButtonTemplate" then
        frame._attrs = {}
        frame.SetAttribute = function(self, key, value) self._attrs[key] = value end
        frame.GetAttribute = function(self, key) return self._attrs[key] end
    end
    return frame
end

local ns = env.Load({ ui = true })
_G.CreateFrame = Create

local POLE, SWORD = 6256, 2488
local hand = POLE
local bags = { [6530] = 12, [6533] = 3, [6532] = 6 }
local lureLeft
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

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end
local handler = _G.BlackthornesFarmerEventFrame:GetScript("OnEvent")
local function Fire(event, ...) handler(_G.BlackthornesFarmerEventFrame, event, ...) end

local Bar = ns.FishingBar

-- 1.
Fire("PLAYER_EQUIPMENT_CHANGED")
suite.check("off unless ticked", not (Bar.frame and Bar.frame:IsShown()))
ns.db.fishingBar = true
Fire("PLAYER_EQUIPMENT_CHANGED")
suite.check("ticked, with a pole in hand, it shows", Bar.frame and Bar.frame:IsShown())
hand = SWORD
Fire("PLAYER_EQUIPMENT_CHANGED")
suite.check("not with a sword in hand", not Bar.frame:IsShown())
hand = POLE
Fire("PLAYER_EQUIPMENT_CHANGED")

-- 2.
suite.check("Cast casts Fishing", Bar.cast:GetAttribute("type") == "spell"
    and Bar.cast:GetAttribute("spell") == "Fishing", tostring(Bar.cast:GetAttribute("spell")))
local order = {}
for _, lure in ipairs(Bar.lures) do order[#order + 1] = lure.id end
suite.check("lures best first", table.concat(order, ",") == "6533,6532,6530", table.concat(order, ","))
Bar:TogglePicker()
suite.check("Add Lure opens the list", Bar.picker and Bar.picker:IsShown())
suite.check("a row puts its lure on the pole",
    Bar.rows[1]:GetAttribute("type") == "macro" and Bar.rows[1]:GetAttribute("macrotext") == "/use item:6533\n/use 16",
    tostring(Bar.rows[1]:GetAttribute("macrotext")))
suite.check("one row a lure", Bar.rows[3]:IsShown() and not Bar.rows[4]:IsShown())
suite.check("the row's name, count and skill", Bar.rows[2].name:GetText() == "Bright Baubles"
    and Bar.rows[2].count:GetText() == "x6" and Bar.rows[2].bonus:GetText() == "+75")

bags = {}
Fire("BAG_UPDATE_DELAYED")
suite.check("no lures: the list closes", not Bar.picker:IsShown())
Bar:TogglePicker()
suite.check("and Add Lure opens nothing", not Bar.picker:IsShown())
bags = { [6529] = 2 }
Fire("BAG_UPDATE_DELAYED")

-- 3.
suite.check("no lure on", Bar.status:GetText() == "No lure on", Bar.status:GetText())
lureLeft = 401
Fire("UNIT_INVENTORY_CHANGED", "player")
suite.check("lure on, minutes left", Bar.status:GetText() == "Lure on: 7 min left", Bar.status:GetText())

-- 4.
Fire("PLAYER_REGEN_DISABLED")
suite.check("a fight hides it", not Bar.frame:IsShown())
Fire("PLAYER_REGEN_ENABLED")
suite.check("back after", Bar.frame:IsShown())
Fire("MERCHANT_SHOW")
suite.check("hidden at a vendor", not Bar.frame:IsShown())
Fire("MERCHANT_CLOSED")
suite.check("back after the vendor", Bar.frame:IsShown())

-- A mailbox whose close the client never said: the bar comes back once
-- the game's window is gone, without a /reload.
_G.MailFrame = { shown = true, IsShown = function(self) return self.shown end }
Fire("MAIL_SHOW")
suite.check("hidden at a mailbox", not Bar.frame:IsShown())
Fire("BAG_UPDATE_DELAYED")
suite.check("still hidden while the mailbox shows", not Bar.frame:IsShown())
_G.MailFrame.shown = false
Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
suite.check("back once the mailbox is gone, no close heard", Bar.frame:IsShown())
_G.MailFrame = nil

Bar:Close()
Fire("BAG_UPDATE_DELAYED")
suite.check("the close gem puts it away", not Bar.frame:IsShown())
hand = SWORD
Fire("PLAYER_EQUIPMENT_CHANGED")
hand = POLE
Fire("PLAYER_EQUIPMENT_CHANGED")
suite.check("back when the pole goes on again", Bar.frame:IsShown())

ns.HandleSlash("fishingbar off")
suite.check("/farm fishingbar off hides it", not Bar.frame:IsShown() and ns.db.fishingBar == false)

_G.CreateFrame = realCreate
_G.GetInventoryItemID, _G.GetItemInfoInstant, _G.GetItemCount, _G.GetItemInfo, _G.GetSpellInfo, _G.GetWeaponEnchantInfo = nil, nil, nil, nil, nil, nil

suite.done()
