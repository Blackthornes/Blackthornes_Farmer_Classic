-- An open drop-down list draws over the rows under its box, also once its
-- window is laid into the one window (a player found the rows below showing
-- through the list in Settings, 2026-10-31). The same test in Butler,
-- Equipment, Farmer and Pets.
--
-- What must hold:
--   1. The menu opens in its own strata, above the window's rows.
--   2. When the window was moved under another parent and the menu took that
--      parent's strata, opening it lifts it back up.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("dropdownmenu")

local ns = env.Load({ ui = true })
if env.Enable then env.Enable(ns) end

local parent = CreateFrame("Frame")
local box = ns.Widgets.CreateDropdown(parent, {
    { text = "Off", value = "off" },
    { text = "Shift", value = "shift" },
    { text = "Always", value = "always" },
})
local menu = box.menu

-- Each test client keeps strata its own way, so note it here.
local strata = "MEDIUM"
rawset(menu, "SetFrameStrata", function(_, value) strata = value end)

box:Toggle()
suite.check("the menu opens", menu:IsShown())
suite.check("the menu draws above the rows", strata == "FULLSCREEN_DIALOG", tostring(strata))
box:Toggle()
suite.check("a second click closes it", not menu:IsShown())

-- 2. Laid into the one window, the game hands the menu that window's strata.
strata = "HIGH"
box:Toggle()
suite.check("opening it again lifts it back up", strata == "FULLSCREEN_DIALOG", tostring(strata))

suite.done()
