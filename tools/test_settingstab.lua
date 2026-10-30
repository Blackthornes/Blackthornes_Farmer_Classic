-- Settings as the window's last tab (the owner, 2026-10-27: "Last tab on
-- bottom right will always be settings").
--
-- What must hold:
--   1. The tabs are Search, Rankings, Grind, Stats and Settings, Settings
--      last and flush right on the strip.
--   2. Settings opens in the window's place, at the same size and scale,
--      and only one shows.
--   3. A tab under Settings opens the window back in its place.
--   4. The minimap's right-click still opens and closes Settings.
--   5. The header has no Settings button any more.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("settingstab")

local ns = env.Load({ ui = true })
local UI, SettingsUI = ns.UI, ns.SettingsUI

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

-- 1.
local tabs = UI.Tabs()
suite.check("five tabs", #tabs == 5, #tabs)
suite.check("Settings last, on the right", tabs[5].key == "settings" and tabs[5].right == true)
suite.check("the others in order", tabs[1].key == "search" and tabs[2].key == "rankings"
    and tabs[3].key == "grind" and tabs[4].key == "stats")

UI:Show()
local strip = UI.tabStrip
local search, settings
for _, button in ipairs(strip.tabs or {}) do
    if button.key == "search" then search = button end
    if button.key == "settings" then settings = button end
end
suite.check("Settings sits past the others",
    settings and search and settings.right == true and (settings.left or 0) > (search.left or 0))

-- 2.
UI.frame:ClearAllPoints()
UI.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 120, 640)
UI:SavePosition()
UI:ShowTab("settings")
suite.check("Settings opens", SettingsUI.frame:IsShown())
suite.check("and the window steps aside", not UI.frame:IsShown())
suite.check("the window's tab stays lit", strip.selected == "search", strip.selected)
local point, _, _, x, y = SettingsUI.frame:GetPoint()
suite.check("in the window's place", point == "TOPLEFT" and x == 120 and y == 640, point, x, y)
suite.check("at the same size", SettingsUI.frame:GetWidth() == UI.frame:GetWidth()
    and SettingsUI.frame:GetHeight() == UI.frame:GetHeight(),
    SettingsUI.frame:GetWidth(), UI.frame:GetWidth())
suite.check("and the same scale", SettingsUI.frame:GetScale() == UI.frame:GetScale())
suite.check("Settings is lit on its own strip",
    SettingsUI.tabStrip and SettingsUI.tabStrip.selected == "settings")

-- 3.
SettingsUI:OpenTab("rankings")
suite.check("Rankings opens", UI.frame:IsShown() and UI.tab == "rankings")
suite.check("and Settings steps aside", not SettingsUI.frame:IsShown())
local point2, _, _, x2, y2 = UI.frame:GetPoint()
suite.check("in Settings' place", point2 == "TOPLEFT" and x2 == 120 and y2 == 640, point2, x2, y2)
UI:Hide()

-- 4.
SettingsUI:Toggle()
suite.check("Settings opens from the minimap", SettingsUI.frame:IsShown() and not UI.frame:IsShown())
SettingsUI:Toggle()
suite.check("and closes", not SettingsUI.frame:IsShown())

-- 5.
suite.check("no Settings button in the header", rawget(UI, "settingsButton") == nil)

suite.done()
