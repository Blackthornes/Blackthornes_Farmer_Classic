-- The windows' look (asked for: neon glow, "dopamine hits", nothing cut off).
--
-- What matters: the goals panel wears the house glow and fades up as it
-- appears, not on every redraw, and the glow flares on a milestone and
-- brighter on a goal done; goal cards, Where to farm rows, checkboxes and
-- search boxes light under the mouse, eased, and let go when hidden; a
-- ticked box looks ticked; a goal's bar has a spark that turns green with
-- it; the gold tab line turns round from where it is; a held button lets go
-- of its whole label when hidden; and with effects off it all lands at once.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("windowlook")

local ns = env.Load({ ui = true })
local Motion = ns.Motion
local Theme = ns.Theme
local Widgets = ns.Widgets
local GUI = ns.GoalsUI
local UI = ns.UI

-- Widgets that keep the colours, alphas and gradients written to them,
-- which the shared stub lets fall on the floor.
local function Recording(fields)
    local frame = env.Stub(fields)
    frame.SetColorTexture = function(self, r, g, b, a) self._rgba = { r, g, b, a or 1 } end
    frame.SetVertexColor = function(self, r, g, b, a) self._vertex = { r, g, b, a or 1 } end
    frame.SetAlpha = function(self, a) self._alpha = a end
    frame.GetAlpha = function(self) return rawget(self, "_alpha") or 1 end
    frame.SetGradient = function(self, orientation, from, to) self._gradient = { orientation, from, to } end
    frame.CreateTexture = function() return Recording() end
    frame.CreateFontString = function() return Recording() end
    return frame
end

local realCreateFrame = _G.CreateFrame
_G.CreateFrame = function(_, name, parent)
    local frame = Recording({ _parent = parent })
    if name then _G[name] = frame end
    return frame
end

local realItem = _G.C_Item
local bags = {}
_G.C_Item = { GetItemCount = function(item) return bags[item] or 0 end }

local COPPER, TIN = 2770, 2771

--- A field set on a stub widget, or nil. The stub answers a field it was
--- never given with a function, and keeps it once read, which would pass
--- any "is it there" test; none of the fields read here is a function.
local function Raw(object, key)
    local value = type(object) == "table" and rawget(object, key) or nil
    if type(value) == "function" then return nil end
    return value
end

local function Color(key)
    local r, g, b = Theme.Unpack(key)
    return { r, g, b }
end

local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for index = 1, 3 do
        if math.abs(a[index] - b[index]) > 1e-6 then return false end
    end
    return true
end

--- How much of a texture shows: its colour's alpha times its own.
local function Showing(texture)
    if type(texture) ~= "table" then return 0 end
    local rgba = Raw(texture, "_rgba")
    return (rgba and rgba[4] or 1) * (Raw(texture, "_alpha") or 1)
end

local function Near(a, b)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6
end

--- The colour a gradient ends on, as { r, g, b }.
local function GradientEnd(texture)
    local gradient = Raw(texture, "_gradient")
    local to = gradient and gradient[3]
    return to and { to.r, to.g, to.b }
end

local function Fire(target, script)
    local fn = target:GetScript(script)
    if fn then fn(target) end
    return fn ~= nil
end

local function Settle()
    for _ = 1, 100 do GUI:Step(0.1) end
    Motion:FinishAll()
end

local function CardOf(item)
    for _, card in ipairs(GUI.cards) do
        if card:IsShown() and card.goal and card.goal.item == item then return card end
    end
end

-- Every brightness the goals panel's glow is set to, in order.
local seen = {}
local SetHalo = Theme.SetHalo
Theme.SetHalo = function(frame, alpha, key)
    if frame == GUI.frame then seen[#seen + 1] = alpha end
    return SetHalo(frame, alpha, key)
end

local function Peak()
    local peak = 0
    for _, alpha in ipairs(seen) do peak = math.max(peak, alpha) end
    return peak
end

--------------------------------------------------------------------------------
-- The goals panel: its glow, its fade, its flares
--------------------------------------------------------------------------------

bags[COPPER] = 9
ns.Goals:Set("Copper Ore", 40)
local frame = GUI.frame
local halo = Raw(frame, "haloTextures")
local rest = Raw(frame, "haloRest")

suite.check("the goals panel wears the house glow, kept low as it is always up",
    halo and #halo == 4 and rest and rest <= 0.08, rest)

local function Spot(f)
    local p = Raw(f, "_point") or {}
    return table.concat({ tostring(p[1]), tostring(p[2]), tostring(p[3]), tostring(p[4]), tostring(p[5]) }, ",")
end

local placed = Spot(frame)
Motion:Step(0.05)
suite.check("it fades up as it appears, right where it was put",
    Motion:Running(frame, "open") and (Raw(frame, "_alpha") or 1) < 1 and Spot(frame) == placed,
    Raw(frame, "_alpha"))
Motion:FinishAll()
suite.check("and lands fully drawn, its glow back at rest",
    Raw(frame, "_alpha") == 1 and Near(seen[#seen], rest), seen[#seen])

local flares = #seen
ns.Goals:Set("Tin Ore", 40)
suite.check("a goal added to the panel already up neither fades it nor flares it",
    halo and not Motion:Running(frame) and #seen == flares and Raw(frame, "_alpha") == 1)

GUI:Toggle()
local closed = not frame:IsShown()
GUI:Toggle()
suite.check("closed and opened again, it fades up again", closed and frame:IsShown()
    and Motion:Running(frame, "open"))
Motion:FinishAll()

-- Past a quarter: a milestone.
seen = {}
bags[COPPER] = 11
ns.Goals:Update()
suite.check("a milestone flares the glow", Motion:Running(frame, "halo") and Near(Peak(), (rest or 0) * 3.2),
    Peak())
Motion:Step(1)
suite.check("and it settles back to rest", not Motion:Running(frame, "halo") and Near(seen[#seen], rest),
    seen[#seen])
Settle()

-- The last one: the goal is done.
seen = {}
bags[COPPER] = 40
ns.Goals:Update()
suite.check("a goal done flares it brighter", Motion:Running(frame, "halo") and Near(Peak(), (rest or 0) * 5),
    Peak())
Motion:Step(1)
suite.check("and for longer", Motion:Running(frame, "halo"))
Motion:FinishAll()
suite.check("then it settles at rest", Near(seen[#seen], rest), seen[#seen])
Settle()

--------------------------------------------------------------------------------
-- A goal card: its spark, and the mouse
--------------------------------------------------------------------------------

local copper = CardOf("Copper Ore")
local spark = Raw(copper, "spark")
suite.check("a full bar has no spark", spark and not spark:IsShown())

bags[TIN] = 20
ns.Goals:Update()
Settle()
local tin = CardOf("Tin Ore")
spark = Raw(tin, "spark")
local gradient = Raw(spark, "_gradient")
suite.check("a bar part full has a spark at its tip", spark and spark:IsShown())
suite.check("a gold one, fading in toward the tip", gradient and gradient[1] == "HORIZONTAL"
    and gradient[2].a == 0 and gradient[3].a == 0.55 and Same(GradientEnd(spark), Color("accent")))

bags[TIN] = 37
ns.Goals:Update()
Settle()
suite.check("green in the last stretch, with the bar", Same(GradientEnd(spark), Color("good")))

local wash, rims = Raw(tin, "hover"), Raw(tin, "borderTextures")
tin:GetScript("OnEnter")(tin)
suite.check("a goal card eases in under the mouse", Motion:Running(tin, "hover"))
Motion:FinishAll()
suite.check("lifting its wash and lighting its edge", Showing(wash) > 0 and rims
    and Showing(rims[1]) == 1 and Same(Raw(rims[1], "_rgba"), Color("borderLit")))
tin:GetScript("OnLeave")(tin)
local easing = Motion:Running(tin, "hover")
Motion:FinishAll()
suite.check("and eases back when the mouse goes", easing and wash and Showing(wash) == 0
    and Showing(rims[1]) == 0)

tin:GetScript("OnEnter")(tin)
Motion:FinishAll()
local lit = Showing(wash) > 0
suite.check("hidden under the mouse, a card lets go", lit and Fire(tin, "OnHide") and Showing(wash) == 0
    and Motion:Value(tin, "hover") == 0)
tin:Show()

--------------------------------------------------------------------------------
-- Where to farm, and the picker
--------------------------------------------------------------------------------

GUI:OpenSpots("Copper Ore")
Settle()
local panel = GUI.spots
suite.check("the Where to farm panel wears the house glow", Raw(panel, "haloTextures") ~= nil)

local row = panel.rows[1]
local listed = row ~= nil and row:IsShown()
local light, edge = Raw(row, "highlight"), Raw(row, "edge")
row:GetScript("OnEnter")(row)
suite.check("a place eases in under the mouse", listed and Motion:Running(row, "hover"))
Motion:FinishAll()
suite.check("and its row really lights, with the gold edge the lists have",
    Showing(light) > 0 and edge and Showing(edge) == 1)
row:GetScript("OnLeave")(row)
easing = Motion:Running(row, "hover")
Motion:FinishAll()
suite.check("and goes dark, eased, when the mouse leaves", easing and light and Showing(light) == 0)
panel:Hide()

GUI:OpenPicker("Tin Ore")
suite.check("the goal picker wears the house glow", Raw(GUI.picker, "haloTextures") ~= nil)
GUI.picker:Hide()
Motion:FinishAll()

--------------------------------------------------------------------------------
-- Checkboxes
--------------------------------------------------------------------------------

local check = Widgets.CreateCheckbox(UIParent, "Include bank", nil, false)
local rimsOf = Raw(Raw(check, "box"), "borderTextures")
local corner = rimsOf and rimsOf[1]
local function CornerColor() return Raw(corner, "_rgba") end
local function LabelColor() return Raw(check.label, "_color") end

local unticked = CornerColor()
check:SetChecked(true)
suite.check("a ticked box has a lit gold edge, an unticked one a dim metal one",
    Same(unticked, Color("metal")) and Same(CornerColor(), Color("accentHi")))

check:SetChecked(false)
check:GetScript("OnEnter")(check)
suite.check("under the mouse a box eases in", Motion:Running(check, "hover"))
Motion:FinishAll()
suite.check("its label going gold and its edge lifting", Same(LabelColor(), Color("accent"))
    and Same(CornerColor(), Color("accent")))
check:GetScript("OnLeave")(check)
easing = Motion:Running(check, "hover")
Motion:FinishAll()
suite.check("and both ease back after", easing and Same(LabelColor(), Color("text"))
    and Same(CornerColor(), Color("metal")))

check:SetDisabled(true)
check:GetScript("OnEnter")(check)
Motion:FinishAll()
suite.check("a disabled box does not answer the mouse", Same(LabelColor(), Color("dim"))
    and Same(CornerColor(), Color("metal")))

--------------------------------------------------------------------------------
-- Search boxes
--------------------------------------------------------------------------------

local search = Widgets.CreateSearchBox(UIParent, "anything")
local over = true
search.IsVisible = function() return true end
search.IsMouseOver = function() return over end
local box = search.editBox
local rim = search.borderTextures[1]
local function RimColor() return Raw(rim, "_rgba") end

suite.check("a search box answers the mouse on its margin", Fire(search, "OnEnter"))
suite.check("easing in", Motion:Running(search, "hover"))
Motion:FinishAll()
suite.check("its edge lifts", Same(RimColor(), Color("borderLit")))
local glass = Raw(search.icon, "_vertex")
suite.check("and its magnifier lights a little, short of gold", glass
    and not Same(glass, Color("muted")) and not Same(glass, Color("accent")))

-- From the margin onto the text is a leave and an enter.
Fire(search, "OnLeave")
Fire(box, "OnEnter")
Motion:FinishAll()
suite.check("going from the margin onto the text keeps it lit", Motion:Value(search, "hover") == 1)

over = false
Fire(box, "OnLeave")
easing = Motion:Running(search, "hover")
Motion:FinishAll()
suite.check("and it eases back when the mouse goes", easing and Motion:Value(search, "hover") == 0
    and Same(RimColor(), Color("border")))

Fire(search.clear, "OnEnter")
suite.check("the clear x eases under the mouse", Motion:Running(search.clear, "hover"))
Motion:FinishAll()

over = true
Fire(search, "OnEnter")
Motion:FinishAll()
lit = Motion:Value(search, "hover") == 1
suite.check("hidden under the mouse, a search box lets go", lit and Fire(search, "OnHide")
    and Motion:Value(search, "hover") == 0 and Same(RimColor(), Color("border")))

--------------------------------------------------------------------------------
-- The search window
--------------------------------------------------------------------------------

UI:Build()
UI:Show()
Motion:FinishAll()

local strip = UI.tabStrip
local line = strip.line
local spans = { search = { x = UI.tabs.search.left }, rankings = { x = UI.tabs.rankings.left } }

--- Where the gold line is, from the first tab's left edge: it hangs from
--- the tab it is heading for.
local function LineX()
    local p = Raw(line, "_point")
    for _, tab in pairs(UI.tabs) do
        if p and p[2] == tab then return p[4] + tab.left end
    end
end

UI:ShowTab("rankings")
Motion:Step(0.11)
local mid = LineX()
UI:ShowTab("search")
suite.check("picked back mid-slide, the line turns round from where it is",
    mid and mid > spans.search.x and mid < spans.rankings.x and Near(LineX(), mid),
    tostring(LineX()) .. " vs " .. tostring(mid))
Motion:FinishAll()
suite.check("and lands under Search, knowing where it is", Near(strip.lineX, spans.search.x)
    and Near(LineX(), spans.search.x))

local glow = Raw(strip.lineGlow, "_gradient")
suite.check("the glow on the line is a gradient, brightest at the line", glow
    and glow[1] == "VERTICAL" and glow[2].a == 0.32 and glow[3].a == 0)
suite.check("drawn above the tabs, so the tab showing does not hide it",
    strip.lineLayer and strip.lineLayer:GetFrameLevel() > UI.tabs.search:GetFrameLevel())

local hang = Raw(strip, "_point")
suite.check("the tabs hang from the window's bottom edge",
    hang and hang[1] == "TOPLEFT" and hang[2] == UI.frame and hang[3] == "BOTTOMLEFT")

suite.check("Search for something to farm is in gold, as every heading is",
    Same(Raw(UI.emptyLine, "_color"), Color("accent")))

ns.LootTableUI:Build()
local closeGem = Raw(ns.LootTableUI.closeButton, "_point")
local mainGem = Raw(UI.trim.closeButton, "_point")
suite.check("the loot table closes from the gem where the search window's is",
    closeGem and mainGem and closeGem[1] == mainGem[1] and closeGem[3] == mainGem[3]
    and closeGem[4] == mainGem[4] and closeGem[5] == mainGem[5])

do
    local r, g, b = Theme.Unpack("muted")
    local hex = ("ff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5))
    suite.check("grey text in chat is the windows' grey", ns.COLORS.muted == hex, ns.COLORS.muted)
end

--------------------------------------------------------------------------------
-- Every kind of button is readable
--
-- Tradeskills once drew dark lettering on a dark face and its buttons read as
-- empty boxes. Each kind here keeps its label readable on its own face, at
-- rest and under the mouse, and so does a label coloured by hand.
--------------------------------------------------------------------------------

local function Luminance(c)
    local function lin(v) v = v or 0; return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
    return 0.2126 * lin(c[1]) + 0.7152 * lin(c[2]) + 0.0722 * lin(c[3])
end
local function Contrast(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return 0 end
    local la, lb = Luminance(a), Luminance(b)
    if la < lb then la, lb = lb, la end
    return (la + 0.05) / (lb + 0.05)
end

local kinds = {
    { "a plain button", {}, 4.5 },
    { "a primary button", { primary = true }, 4.5 },
    -- Red on dark metal reads as a warning first; it only needs to stand out.
    { "a danger button", { danger = true }, 3.5 },
    { "a button with a gold label of its own", { labelKey = "accent" }, 4.5 },
    { "a primary button with a dark face of its own", { primary = true, baseColor = { 0.06, 0.07, 0.09, 1 } }, 4.5 },
}
for _, kind in ipairs(kinds) do
    local b = Widgets.CreateButton(UIParent, "Set Goal", nil, kind[2])
    b.Light(0)
    suite.check(kind[1] .. " is readable at rest",
        Contrast(Raw(b.label, "_color"), Raw(b.background, "_rgba")) >= kind[3],
        Contrast(Raw(b.label, "_color"), Raw(b.background, "_rgba")))
    b:GetScript("OnEnter")(b)
    Motion:FinishAll()
    suite.check(kind[1] .. " is readable under the mouse",
        Contrast(Raw(b.label, "_color"), Raw(b.background, "_rgba")) >= kind[3],
        Contrast(Raw(b.label, "_color"), Raw(b.background, "_rgba")))
    b:GetScript("OnLeave")(b)
    Motion:FinishAll()
end

local primary = Widgets.CreateButton(UIParent, "Set Goal", nil, { primary = true })
primary.Light(0)
suite.check("a primary button is solid gold with dark lettering",
    Same(Raw(primary.background, "_rgba"), Color("accent")) and Same(Raw(primary.label, "_color"), Color("ink")))
suite.check("and glows a little even at rest", Raw(primary, "haloRest") ~= nil
    and primary.haloTextures[1]:IsShown())

-- The search window's Goal button turns gold for a goal's count, by hand.
local goal = Widgets.CreateButton(UIParent, "23/40", nil, { width = 44 })
goal:SetLabelColor("accent")
goal:GetScript("OnEnter")(goal)
Motion:FinishAll()
suite.check("a label coloured by hand stays readable under the mouse",
    Contrast(Raw(goal.label, "_color"), Raw(goal.background, "_rgba")) >= 4.5)
goal:GetScript("OnLeave")(goal)
Motion:FinishAll()
suite.check("and goes back to the colour it was given",
    Same(Raw(goal.label, "_color"), Color("accent")))
goal:SetLabelColor(nil)
suite.check("nil puts back the button's own gold", Same(Raw(goal.label, "_color"), Color("gilt")))

-- A stepper's end of the range stays dim under the mouse: nothing to press.
local stepper = Widgets.CreateStepper(UIParent, { min = 1, max = 3, value = 1 })
stepper.minus:GetScript("OnEnter")(stepper.minus)
Motion:FinishAll()
suite.check("a stepper's button at the end of its range stays dim",
    Same(Raw(stepper.minus.label, "_color"), Color("dim")))
stepper:SetValue(2, true)
suite.check("and lights again once there is room",
    not Same(Raw(stepper.minus.label, "_color"), Color("dim")))

--------------------------------------------------------------------------------
-- A button held while it hides
--------------------------------------------------------------------------------

local pressed = Widgets.CreateButton(UIParent, "Hold me", nil, { width = 90 })

-- A label hung at both ends, as a caller may hang one.
local label = env.Stub()
label._points = {}
function label:SetPoint(point, relativeTo, relativePoint, x, y)
    for _, p in ipairs(self._points) do
        if p[1] == point then
            p[2], p[3], p[4], p[5] = relativeTo, relativePoint, x, y
            return
        end
    end
    self._points[#self._points + 1] = { point, relativeTo, relativePoint, x, y }
end
function label:ClearAllPoints() self._points = {} end
function label:GetNumPoints() return #self._points end
function label:GetPoint(index)
    local p = self._points[index or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
end
label:SetPoint("LEFT", pressed, "LEFT", 4, 0)
label:SetPoint("RIGHT", pressed, "RIGHT", -4, 0)
pressed.label = label

local function Ys()
    local points = label._points
    return ("%s,%s"):format(tostring(points[1] and points[1][5]), tostring(points[2] and points[2][5]))
end

pressed:GetScript("OnMouseDown")(pressed, "LeftButton")
suite.check("held, the whole label dips a pixel", Ys() == "-1,-1" and #label._points == 2, Ys())
suite.check("hidden while held, it lets go", Fire(pressed, "OnHide") and Ys() == "0,0", Ys())
pressed:GetScript("OnMouseDown")(pressed, "LeftButton")
local dipped = Ys() == "-1,-1"
pressed:GetScript("OnMouseUp")(pressed, "LeftButton")
suite.check("so the next press dips it from its resting place, and lets go again",
    dipped and Ys() == "0,0", Ys())

-- Hidden under the mouse (a panel's X clicked), no leave comes: the light
-- goes out, or the X is still lit when the panel opens again.
Fire(pressed, "OnEnter")
Motion:FinishAll()
local litButton = Motion:Value(pressed, "hover") == 1
suite.check("hidden under the mouse, a button lets go", litButton and Fire(pressed, "OnHide")
    and Motion:Value(pressed, "hover") == 0 and not Motion:Running(pressed, "hover"))

--------------------------------------------------------------------------------
-- Effects off: everything lands at its end at once
--------------------------------------------------------------------------------

ns.db.trackerEffects = "off"

GUI:Toggle()
seen = {}
GUI:Toggle()
suite.check("off: the goals panel opens fully drawn, its glow at rest", frame:IsShown()
    and halo and Raw(frame, "_alpha") == 1 and not Motion:Running(frame) and Near(seen[#seen], rest),
    seen[#seen])

seen = {}
bags[TIN] = 40
ns.Goals:Update()
suite.check("off: a goal done leaves the glow at rest", halo and not Motion:Running(frame)
    and (#seen == 0 or Near(seen[#seen], rest)))

tin = CardOf("Tin Ore")
tin:GetScript("OnEnter")(tin)
suite.check("off: a card lights at once", not Motion:Running(tin) and Showing(Raw(tin, "hover")) > 0)
tin:GetScript("OnLeave")(tin)

GUI:OpenSpots("Copper Ore")
row = GUI.spots.rows[1]
row:GetScript("OnEnter")(row)
suite.check("off: a place lights at once", not Motion:Running(row) and Showing(Raw(row, "highlight")) > 0)
row:GetScript("OnLeave")(row)
GUI.spots:Hide()

check:SetDisabled(false)
check:GetScript("OnLeave")(check)
check:GetScript("OnEnter")(check)
suite.check("off: a box lights at once", not Motion:Running(check)
    and Same(CornerColor(), Color("accent")) and Same(LabelColor(), Color("accent")))

over = true
Fire(search, "OnEnter")
suite.check("off: a search box lights at once", not Motion:Running(search)
    and Same(RimColor(), Color("borderLit")))

UI:ShowTab("rankings")
suite.check("off: the tab line is under Rankings at once", not Motion:Running(line)
    and Near(strip.lineX, spans.rankings.x) and Near(LineX(), spans.rankings.x))
UI:ShowTab("search")

ns.db.trackerEffects = nil

--------------------------------------------------------------------------------
-- Put back what was replaced
--------------------------------------------------------------------------------

Settle()
Theme.SetHalo = SetHalo
_G.C_Item = realItem
_G.CreateFrame = realCreateFrame

suite.done()
