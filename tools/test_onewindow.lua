-- Farmer's tabs in the one Blackthornes window (UI/Main.lua's FarmerTabs,
-- the owner said build it, 2026-10-30).
--
-- What must hold:
--   1. On unless unticked; unticked, the main window opens in its own place.
--   2. Ticked, opening Farmer opens the one window on it, with the main
--      window laid into its area, bare of its own rim and grip.
--   3. Settings and the other tabs open in the same area; one at a time.
--   4. Closing the one window gives the tabs back their own place.
--   5. "One Window:" on the General page writes every save.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("onewindow")

_G.BlackthornesWindow = nil
local ns = env.Load({ ui = true })
local UI, SettingsUI, Tabs, SW = ns.UI, ns.SettingsUI, ns.FarmerTabs, ns.SharedWindow

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end
UI:JoinSharedMinimap()
local hub = _G.BlackthornesWindow
suite.check("Farmer joins with its tabs", hub.entries.farmer and hub.entries.farmer.host == Tabs.host)
suite.check("the one window is Farmer's own copy", Tabs.One() == SW)

-- 1.
ns.db.oneWindow = nil
suite.check("on unless unticked", SW.On())
ns.db.oneWindow = false
UI:Show()
suite.check("off: the main window opens by itself", UI.frame:IsShown() and not Tabs:Hosted())
UI:Hide()

-- 2.
SW.SetOn(true)
UI:Show()
local area = hub.frame and hub.frame.area
suite.check("on: the one window opens", hub.frame and hub.frame:IsShown())
suite.check("on Farmer", hub.current == hub.entries.farmer and ns.db.oneWindowPick == "farmer")
suite.check("the main window is in it", Tabs:Hosted() and UI.frame:GetParent() == area
    and UI.frame:IsShown())
suite.check("without its own rim", UI.trim and not UI.trim:IsShown())
suite.check("or its own size grip", UI.sizeGrip and not UI.sizeGrip:IsShown())

-- 3.
UI:ShowTab("settings")
suite.check("Settings is in the same area", SettingsUI.frame:GetParent() == area and SettingsUI.frame:IsShown())
suite.check("and the main window stepped aside", not UI.frame:IsShown())
suite.check("the one window stays up", hub.frame:IsShown() and Tabs:Hosted())

-- Show Descriptions makes the pages taller: the one window grows to hold
-- them. On the client Settings fills the area, so its own size only says
-- how big the area is; the stand-in frame is made to answer the same way.
do
    local frame = SettingsUI.frame
    local getW, getH = frame.GetWidth, frame.GetHeight
    frame.GetWidth = function() return area:GetWidth() end
    frame.GetHeight = function() return area:GetHeight() end
    local before, oneBefore = area:GetHeight(), hub.frame:GetHeight()
    SettingsUI.pages:ShowDescriptions(true)
    local need = SettingsUI.pages.need
    suite.check("descriptions on: the pages say how tall they are", type(need) == "table" and need[2] > before)
    suite.check("Settings keeps what the pages need", SettingsUI.need and SettingsUI.need[2] == need[2])
    -- The test's frames don't follow their anchors, so the area keeps its
    -- old height; the one window around it is what grows.
    suite.check("and the one window grows to hold them",
        hub.frame:GetHeight() - oneBefore >= need[2] - before)
    SettingsUI.pages:ShowDescriptions(false)
    frame.GetWidth, frame.GetHeight = getW, getH
end
SettingsUI:OpenTab("rankings")
suite.check("Rankings back in the area", UI.frame:IsShown() and UI.tab == "rankings"
    and UI.frame:GetParent() == area and not SettingsUI.frame:IsShown())

-- A window built for the first time hides itself before it is laid in
-- (a player's report, 2026-10-30: picking another addon on the rail once
-- turned the one window into that addon's own window).
local fresh = { GetParent = function() return UIParent end }
Tabs:Closed(fresh)
suite.check("a window not yet laid in hiding keeps the one window", hub.frame:IsShown() and Tabs:Hosted())

-- 4.
hub.frame:Hide()
local onHide = hub.frame:GetScript("OnHide")
if onHide then onHide(hub.frame) end
suite.check("closing it lets Farmer go", not Tabs:Hosted() and hub.current == nil)
suite.check("the main window is back on its own", UI.frame:GetParent() == UIParent and not UI.frame:IsShown())
suite.check("with its rim", UI.trim:IsShown() and UI.sizeGrip:IsShown())
suite.check("Settings too", SettingsUI.frame:GetParent() == UIParent)
suite.check("at the shared size", UI.frame:GetWidth() == UI:WindowWidth(), UI.frame:GetWidth(), UI:WindowWidth())

-- 5.
local other = {}
SW:Join({ key = "pets", order = 3, name = "Pets", db = function() return other end })
SettingsUI:Show()
suite.check("Settings opens in the one window", Tabs:Hosted() and SettingsUI.frame:GetParent() == hub.frame.area)
SettingsUI:SetOneWindow(false)
local onHideAgain = hub.frame:GetScript("OnHide")
if onHideAgain then onHideAgain(hub.frame) end
suite.check("unticked in every save", ns.db.oneWindow == false and other.oneWindow == false)
SettingsUI:Show()
suite.check("Settings opens on its own again", not Tabs:Hosted() and SettingsUI.frame:GetParent() == UIParent
    and SettingsUI.frame:IsShown())
SettingsUI:SetOneWindow(true)
suite.check("ticked again in every save", ns.db.oneWindow == true and other.oneWindow == true)
suite.check("and Settings moves into the one window", Tabs:Hosted() and SettingsUI.frame:GetParent() == hub.frame.area)

SW.SetOn(false)
_G.BlackthornesWindow = nil
suite.done()
