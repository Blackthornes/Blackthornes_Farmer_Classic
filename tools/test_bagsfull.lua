-- The notice when the bags fill up (the owner asked 2026-10-15).
--
-- What must hold:
--   1. Nothing while the bags have room, and nothing for how they are at
--      login.
--   2. Bags that fill show "Your bags are full." once, not on every loot
--      after, and again only after a slot frees and they fill again.
--   3. A fill in a fight waits for it to end, and shows nothing if a slot
--      freed meanwhile.
--   4. A fill at a vendor, the bank or a mailbox shows nothing, and walking
--      away full shows nothing either.
--   5. It goes away by itself.
--   6. Settings and /farm bagsfull turn it off and on; test shows it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("bagsfull")

local ns = env.Load({ ui = true })

local freeSlots = 4
_G.NUM_BAG_SLOTS = 4
_G.C_Container = {
    GetContainerNumSlots = function(b) return b == 0 and 16 or 0 end,
    GetContainerNumFreeSlots = function(b) return b == 0 and freeSlots or 0, 0 end,
}
local fighting = false
_G.InCombatLockdown = function() return fighting end

-- Timers wait until the test lets them run.
local timers = {}
_G.C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
local function Wait()
    while #timers > 0 do
        local due = timers
        timers = {}
        for _, fn in ipairs(due) do fn() end
    end
end
-- Window effects off, so a fade lands at once.
ns.db.trackerEffects = "off"

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end
local handler = _G.BlackthornesFarmerEventFrame:GetScript("OnEvent")
local function Fire(event, ...) handler(_G.BlackthornesFarmerEventFrame, event, ...) end

local BagsFull = ns.BagsFull
local shows = 0
local realShow = BagsFull.Show
BagsFull.Show = function(self, ...)
    shows = shows + 1
    return realShow(self, ...)
end
-- It goes in the shared note slot (UI/Notice.lua), with every addon's notes.
local function Note() return BagsFull.card or BagsFull.frame end
local function Showing() return Note() ~= nil and Note():IsShown() end

-- Fires the event and lets the settle timer run, not the fade.
local function Bags(free)
    freeSlots = free
    Fire("BAG_UPDATE_DELAYED")
    local due = timers
    timers = {}
    for _, fn in ipairs(due) do fn() end
end

-- 1.
freeSlots = 0
Fire("PLAYER_ENTERING_WORLD")
Wait()
suite.check("full bags at login show nothing", shows == 0)
Bags(2)
suite.check("nothing while the bags have room", shows == 0)

-- 2.
Bags(0)
suite.check("bags that fill show the notice", shows == 1 and Showing())
suite.check("it says so", Note().text:GetText() == "Your bags are full.", Note().text:GetText())
Bags(0)
Bags(0)
suite.check("not again on every loot after", shows == 1)

-- 5.
Wait()
suite.check("it goes away by itself", not Showing())

Bags(1)
Bags(0)
suite.check("a slot freed and filled again shows it again", shows == 2)
Wait()

-- 3.
Bags(1)
fighting = true
Bags(0)
suite.check("a fill in a fight waits", shows == 2)
fighting = false
Fire("PLAYER_REGEN_ENABLED")
suite.check("and shows when the fight ends", shows == 3)
Wait()

Bags(1)
fighting = true
Bags(0)
Bags(1)
fighting = false
Fire("PLAYER_REGEN_ENABLED")
suite.check("nothing after the fight once a slot freed", shows == 3)

-- 4.
Fire("MERCHANT_SHOW")
Bags(0)
suite.check("a fill at a vendor shows nothing", shows == 3)
Fire("MERCHANT_CLOSED")
Bags(0)
suite.check("nor walking away full", shows == 3)
Bags(1)
Fire("BANKFRAME_OPENED")
Bags(0)
Fire("BANKFRAME_CLOSED")
Bags(0)
suite.check("nor at the bank", shows == 3)
Bags(1)
Fire("MAIL_SHOW")
Bags(0)
Fire("MAIL_CLOSED")
Bags(0)
suite.check("nor at a mailbox", shows == 3)

-- 6.
Bags(1)
ns.HandleSlash("bagsfull")
suite.check("/farm bagsfull turns it off", ns.db.bagsFullNotice == false)
Bags(0)
suite.check("and nothing shows", shows == 3)
ns.HandleSlash("bagsfull test")
suite.check("test shows it anyway", shows == 4 and Showing())
Wait()

ns.SettingsUI:Show()
local box = ns.SettingsUI.controls.bagsFull
suite.check("the Settings box shows it off", box ~= nil and not box:GetChecked())
box:GetScript("OnClick")(box)
suite.check("ticking it turns it back on", ns.db.bagsFullNotice == true)
Bags(1)
Bags(0)
suite.check("and it shows again", shows == 5)

suite.done()
