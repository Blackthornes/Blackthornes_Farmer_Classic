-- The house size grip on every Farmer window (the owner, 2026-10-11:
-- "Farmer windows need the same resizing feature that others have").
--
-- What must hold:
--   1. Every window and popup has the gold grip: the search window (its
--      Search, Rankings and Grind tabs), Settings, the loot table, Export,
--      the goals panel, Where to farm and the goal picker. The kills panel
--      has had it since 2026-10-07 (test_tallysize.lua).
--   2. Each opens at its saved size, account wide, under a key of its own;
--      nothing saved means normal.
--   3. Dragging sizes it from its top left corner, never under 50% or over
--      150%, and saves on release; only the scale moves while dragging, so
--      no list is drawn again until the drag is done, and then once.
--   4. Right-click puts it back to normal.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("windowgrips")

local ns = env.Load({ ui = true })
for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local SCREEN_W, SCREEN_H = 1280, 720
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.001 end

UIParent.GetWidth = function() return SCREEN_W end
UIParent.GetHeight = function() return SCREEN_H end
UIParent.GetEffectiveScale = function() return 1 end

local cursorX, cursorY = 0, 0
_G.GetCursorPosition = function() return cursorX, cursorY end
GameTooltip.IsOwned = function(self, frame) return self._owner == frame end
GameTooltip.SetOwner = function(self, owner) self._owner, self._lines = owner, {} end
GameTooltip.SetText = function(self, text) self._lines = { text } end

-- Saved sizes set before the windows are built, to see them opened at it.
ns.db.windowScale = 100
ns.db.lootTableScale = 90
ns.db.exportScale = 120
ns.db.importScale = 110

-- A window that works out its edges from its one point, as the game does.
local function Geometry(frame, width, height)
    frame._scale = frame._scale or 1
    frame._width, frame._height = width, height
    frame.SetScale = function(self, s) self._scale = s end
    frame.GetScale = function(self) return self._scale end
    frame.GetWidth = function(self) return self._width end
    frame.GetHeight = function(self) return self._height end
    frame.ClearAllPoints = function(self) self._point = nil end
    frame.SetPoint = function(self, point, relativeTo, relativePoint, x, y)
        self._point = { point, relativeTo, relativePoint, x or 0, y or 0 }
    end
    frame.GetPoint = function(self)
        local p = self._point or {}
        return p[1], p[2], p[3], p[4], p[5]
    end
    frame.GetLeft = function(self)
        local p = self._point
        return p and p[4]
    end
    frame.GetTop = function(self)
        local p = self._point
        return p and p[5]
    end
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 100 / frame._scale, 600 / frame._scale)
end

local windows = {
    { name = "search window", key = "windowScale",
      build = function() return ns.UI:Build() end, grip = function() return ns.UI.sizeGrip end },
    { name = "settings", key = "windowScale",
      build = function() return ns.SettingsUI:Build() end, grip = function() return ns.SettingsUI.sizeGrip end },
    { name = "loot table", key = "lootTableScale", saved = 90,
      build = function() return ns.LootTableUI:Build() end, grip = function() return ns.LootTableUI.sizeGrip end },
    { name = "export", key = "exportScale", saved = 120,
      build = function() return ns.UI:BuildExport() end, grip = function() return ns.UI.exportGrip end },
    { name = "take data", key = "importScale", saved = 110,
      build = function() return ns.UI:BuildImport() end, grip = function() return ns.UI.importGrip end },
    { name = "goals panel", key = "goalsScale",
      build = function() return ns.GoalsUI:Build() end, grip = function() return ns.GoalsUI.sizeGrip end },
    { name = "where to farm", key = "goalSpotsScale",
      build = function() return ns.GoalsUI:BuildSpots() end, grip = function() return ns.GoalsUI.spots.sizeGrip end },
    { name = "goal picker", key = "goalPickerScale",
      build = function() return ns.GoalsUI:BuildPicker() end, grip = function() return ns.GoalsUI.picker.sizeGrip end },    { name = "hidden", key = "hiddenScale",
      build = function() return ns.HiddenUI:Build() end, grip = function() return ns.HiddenUI.sizeGrip end },
}

-- The size each window is opened at.
local applied = {}
local ApplySize = ns.Widgets.ApplySize
ns.Widgets.ApplySize = function(frame, percent, ...)
    applied[frame] = percent
    return ApplySize(frame, percent, ...)
end

-- Draws of the search window's list, which a drag must not cause.
local renders = 0
local Render = ns.UI.Render
ns.UI.Render = function(...) renders = renders + 1 return Render(...) end

for _, w in ipairs(windows) do
    local frame = w.build()
    local grip = w.grip()
    suite.check(w.name .. ": has the gold grip", grip ~= nil and grip.dots and #grip.dots == 6)
    if grip then
        suite.check(w.name .. ": outside its bottom right corner",
            grip._point and grip._point[3] == "BOTTOMRIGHT", grip._point and grip._point[3])
        if w.saved then
            suite.check(w.name .. ": opens at its saved size", applied[frame] == w.saved,
                applied[frame])
        end

        frame._scale = 1
        Geometry(frame, 400, 300)
        ns.UI.frame:Show()
        ns.UI.tab = "search"
        renders = 0

        -- Pressed 10 right of and 15 below the corner, dragged to 80%.
        cursorX, cursorY = 100 + 400 + 10, 600 - 300 - 15
        grip._scripts.OnMouseDown(grip, "LeftButton")
        suite.check(w.name .. ": sizing", grip.sizing == true)
        cursorX, cursorY = 100 + 400 * 0.8 + 10, 600 - 300 * 0.8 - 15
        grip._scripts.OnUpdate(grip)
        suite.check(w.name .. ": 80% while dragging", near(frame._scale, 0.8), frame._scale)
        suite.check(w.name .. ": top left stays put",
            near(frame:GetLeft() * frame._scale, 100) and near(frame:GetTop() * frame._scale, 600))
        grip._scripts.OnUpdate(grip)
        suite.check(w.name .. ": nothing drawn again while dragging", renders == 0, renders)

        cursorX, cursorY = 100 + 400 * 0.2, 600 - 300 * 0.2
        grip._scripts.OnUpdate(grip)
        suite.check(w.name .. ": never under 50%", near(frame._scale, 0.5), frame._scale)
        cursorX, cursorY = 100 + 400 * 3, 600 - 300 * 3
        grip._scripts.OnUpdate(grip)
        suite.check(w.name .. ": never over 150%", frame._scale <= 1.5 + 1e-9, frame._scale)
        cursorX, cursorY = 100 + 400 * 0.8 + 10, 600 - 300 * 0.8 - 15
        grip._scripts.OnUpdate(grip)
        grip._scripts.OnMouseUp(grip, "LeftButton")
        suite.check(w.name .. ": saved on release", ns.db[w.key] == 80, ns.db[w.key])
        suite.check(w.name .. ": stopped", grip._scripts.OnUpdate == nil and not grip.sizing)
        if w.name == "search window" then
            suite.check("search window: its list drawn once, after the drag", renders == 1, renders)
            suite.check("search window: its spot saved at the new size",
                ns.db.point == "TOPLEFT" and near(ns.db.x * 0.8, 100), tostring(ns.db.x))
        end

        grip._scripts.OnMouseDown(grip, "RightButton")
        suite.check(w.name .. ": right-click, normal again", near(frame._scale, 1) and ns.db[w.key] == 100,
            ns.db[w.key])

        grip._scripts.OnEnter(grip)
        suite.check(w.name .. ": its tooltip says the size", GameTooltip._lines[1] == "100%",
            GameTooltip._lines[1])
    end
end

-- Settings' Search window size row shows a dragged size as it is.
ns.db.windowScale = 87
ns.HandleSlash("settings")
suite.check("Settings shows a dragged size", ns.SettingsUI.controls.windowScale.text:GetText() == "87%",
    ns.SettingsUI.controls.windowScale.text:GetText())

-- A size that would not fit the screen is drawn as big as fits.
local Widgets = ns.Widgets
Widgets.ApplySize = ApplySize
local tall = ns.LootTableUI.frame
Geometry(tall, 400, 600)
Widgets.ApplySize(tall, 150)
suite.check("a size too big for the screen: as big as fits",
    tall._scale < 1.5 and (600 + 60) * tall._scale <= SCREEN_H, tall._scale)
Widgets.ApplySize(tall, nil)
suite.check("nothing saved: normal", near(tall._scale, 1))

suite.done()
