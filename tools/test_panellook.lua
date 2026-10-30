-- The kill and loot panel's look (asked for: next-gen, neon glow, "dopamine
-- hits", nothing cut off).
--
-- What matters: the panel wears the house glow, low at rest, fades up only
-- as it comes into view (never on a redraw, which shows it every kill) and
-- flares as rates unlock; a card's band eases into its hover and stays lit
-- through a kill under a still mouse; a tab eases under the mouse, the tab
-- showing is lit, and the gold line turns round from where it is; the bar
-- toward rates has a spark, green in the last stretch; the card you are on
-- wears the house halo; the unlock banner's title fits a 180 pixel panel;
-- Effects sits with the windows; and Off lands everything at once.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("panellook")

local ns = env.Load({ ui = true })
local Tracker = ns.Tracker
local TUI = ns.TrackerUI
local FX = ns.TrackerFX
local Motion = ns.Motion
local Theme = ns.Theme

_G.PlaySoundFile = function() return true end

-- What every gradient was last shaded to, by texture.
local shaded = {}
local SetGradientAlpha = Theme.SetGradientAlpha
Theme.SetGradientAlpha = function(texture, orientation, key, from, to)
    shaded[texture] = { orientation = orientation, key = key, from = from, to = to }
    return SetGradientAlpha(texture, orientation, key, from, to)
end

-- The panel's alpha, and every brightness its glow is set to, in order.
local frame = TUI:Build()
frame.SetAlpha = function(self, alpha) self._alpha = alpha end
local glow = {}
local SetHalo = Theme.SetHalo
Theme.SetHalo = function(target, alpha, key)
    if target == frame then glow[#glow + 1] = alpha end
    return SetHalo(target, alpha, key)
end

local serial = 0
local function Loot(mob, items)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, guid = "Look-" .. serial }
    env.world.loot = items or {}
    Tracker:OnLoot()
end

local function Shown(key)
    for index, line in ipairs(TUI.shown or {}) do
        if line.key == key then return line, TUI.lines[index] end
    end
end

local function Last(list) return list[#list] end

local function Near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end

local function Coloured(label, key)
    local r, g, b = Theme.Unpack(key)
    local c = label._color
    return c ~= nil and Near(c[1], r) and Near(c[2], g) and Near(c[3], b)
end

local function Settle()
    for _ = 1, 100 do FX:Step(0.1) end
    Motion:FinishAll()
end

local FANG = { name = "Large Fang", id = 5637 }

--------------------------------------------------------------------------------
-- The glow round the panel, and the fade-up
--------------------------------------------------------------------------------

local rest = tonumber(rawget(frame, "haloRest"))
suite.check("the panel wears the house glow",
    type(rawget(frame, "haloTextures")) == "table" and #frame.haloTextures == 4)
suite.check("low at rest: it is up the whole time you farm", rest ~= nil and rest > 0 and rest <= 0.08, rest)

TUI:OnEnable()
local placed = frame._point
suite.check("coming into view, it fades up from clear",
    Motion:Running(frame, "open") and frame._alpha == 0, frame._alpha)
suite.check("its glow flaring as it comes", rest ~= nil and (glow[1] or 0) > rest, glow[1])
Motion:Step(0.1)
suite.check("in place: players drag it where they want it",
    Motion:Running(frame, "open") and frame._point == placed)
Motion:FinishAll()
suite.check("it lands fully drawn, its glow at rest", frame._alpha == 1 and Near(Last(glow), rest), Last(glow))

-- Refresh shows it on every kill: only coming into view fades it up.
local fades = 0
local Open = Motion.Open
Motion.Open = function(self, target, ...)
    if target == frame then fades = fades + 1 end
    return Open(self, target, ...)
end
Loot("Mangy Wolf", { FANG })
Loot("Mangy Wolf", { FANG })
local onRedraws = fades
ns.HandleSlash("tracker off")
ns.HandleSlash("tracker on")
Motion.Open = Open
suite.check("it fades up as it comes into view and never on a redraw",
    onRedraws == 0 and fades == 1, ("%d on redraws, %d in all"):format(onRedraws, fades))
Settle()

--------------------------------------------------------------------------------
-- A card's band under the mouse
--------------------------------------------------------------------------------

local _, band = Shown("mob:Mangy Wolf")
band.IsVisible = function() return true end
band.IsMouseOver = function() return true end
band.hover.SetAlpha = function(self, alpha) self._alpha = alpha end

band:GetScript("OnEnter")(band)
suite.check("the band under the mouse eases in rather than snapping on",
    Motion:Running(band, "hover") and Motion:Value(band, "hover") < 1)
Motion:Step(0.06)
local part = Motion:Value(band, "hover")
suite.check("part way there", part > 0 and part < 1, part)
Motion:FinishAll()
suite.check("and lands lit", Motion:Value(band, "hover") == 1 and band.hover._alpha == 1, band.hover._alpha)

-- No OnEnter comes for a redraw: a kill used to put the band out.
Loot("Mangy Wolf", { FANG })
local _, again = Shown("mob:Mangy Wolf")
suite.check("a kill under a still mouse leaves the band lit, at once",
    again == band and band.hover._alpha == 1 and Motion:Value(band, "hover") == 1
    and not Motion:Running(band, "hover"), band.hover._alpha)

-- Folded by a click under the same still mouse.
GameTooltip._lines = {}
band:GetScript("OnMouseUp")(band, "LeftButton")
local said = table.concat(GameTooltip._lines, " / ")
suite.check("folded by a click, it stays lit and its tooltip says what a click does now",
    band.hover._alpha == 1 and said:find("Click to show its loot.", 1, true) ~= nil, said)
band:GetScript("OnMouseUp")(band, "LeftButton")

band:GetScript("OnLeave")(band)
suite.check("leaving, it eases out", Motion:Running(band, "hover"))
Motion:FinishAll()
suite.check("and goes dark", band.hover._alpha == 0 and Motion:Value(band, "hover") == 0, band.hover._alpha)
band.IsMouseOver = function() return false end

--------------------------------------------------------------------------------
-- The bar toward rates
--------------------------------------------------------------------------------

local function Spark()
    local line, row = Shown("mob:Mangy Wolf:progress")
    return row and row.progress.spark, line
end

local spark = Spark()
suite.check("the bar has a spark at its tip", spark ~= nil and spark:IsShown())
local shade = spark and shaded[spark]
suite.check("gold, brightening toward the tip", shade ~= nil and shade.key == "accent"
    and shade.orientation == "HORIZONTAL" and shade.to > shade.from)

while Tracker:Store()["Mangy Wolf"].kills < Tracker.MIN_KILLS - 2 do Loot("Mangy Wolf", { FANG }) end
local line
spark, line = Spark()
shade = spark and shaded[spark]
suite.check("in the last stretch it turns green with the bar",
    line ~= nil and line.final and shade ~= nil and shade.key == "good" and spark:IsShown(),
    shade and shade.key)
Settle()

--------------------------------------------------------------------------------
-- Rates unlocking: the banner drops and the glow flares
--------------------------------------------------------------------------------

Loot("Mangy Wolf", { FANG })
Settle()
glow = {}
Loot("Mangy Wolf", { FANG })
suite.check("the twentieth wolf drops the banner, and the glow round the panel flares to five times its rest",
    FX.banner and FX.banner:IsShown() and Motion:Running(frame, "halo")
    and rest ~= nil and Near(glow[1], rest * 5), glow[1])
Motion:Step(0.7)
local fading = Last(glow) or 0
suite.check("fading as it goes", rest ~= nil and fading < rest * 5 and fading > rest, fading)
Settle()
suite.check("and settling back to rest", Near(Last(glow), rest), Last(glow))

-- Subtle keeps the flare, as it keeps the goals panel's; the banner is Full's.
ns.db.trackerEffects = "subtle"
if FX.banner then FX.banner:Hide() end
glow = {}
FX:Unlocked({ title = "DROP RATES UNLOCKED", subject = "Mangy Wolf  |  20 kills", key = "mob:Mangy Wolf" })
suite.check("on Subtle the glow flares too, with no banner",
    Motion:Running(frame, "halo") and Near(glow[1], rest * 5)
    and not (FX.banner and FX.banner:IsShown()), glow[1])
Settle()
ns.db.trackerEffects = "full"

--------------------------------------------------------------------------------
-- The card you are on
--------------------------------------------------------------------------------

Loot("Gnoll", { FANG })
TUI:Toggle("mob:Mangy Wolf", false)
Settle()
local live, other = TUI.cards[1], TUI.cards[2]
local sides = live and rawget(live, "haloTextures")
suite.check("the card you are on wears the house halo",
    type(sides) == "table" and #sides == 4 and sides[1]:IsShown())
-- Its colour is the halo's own business (test_motion); the test client's
-- frames answer every missing field, so the key it reads here is not one.
local top = type(sides) == "table" and shaded[sides[1]]
suite.check("bright at its edge and fading out", top and top.orientation == "VERTICAL"
    and math.max(top.from, top.to) > 0 and math.min(top.from, top.to) == 0)
local otherSides = other and rawget(other, "haloTextures")
suite.check("an open card you are not on has none",
    type(otherSides) == "table" and not otherSides[1]:IsShown())

--------------------------------------------------------------------------------
-- The tabs
--------------------------------------------------------------------------------

local farm, loot = TUI.tabs[1], TUI.tabs[2]
farm.hover.SetAlpha = function(self, alpha) self._alpha = alpha end
loot.hover.SetAlpha = function(self, alpha) self._alpha = alpha end

suite.check("the tab showing sits in a gold light",
    rawget(farm, "lit") ~= nil and farm.lit:IsShown() and not loot.lit:IsShown())
local underGlow = shaded[TUI.tabGlow]
suite.check("its line glows softly upward", underGlow ~= nil and underGlow.key == "accent"
    and underGlow.orientation == "VERTICAL" and underGlow.from > underGlow.to
    and TUI.tabGlow:GetHeight() == 7)

loot:GetScript("OnEnter")(loot)
suite.check("the other tab eases in under the mouse", Motion:Running(loot, "hover"))
Motion:FinishAll()
suite.check("lit, its name bright gold", loot.hover._alpha == 1 and Coloured(loot.label, "accentHi"))
Loot("Gnoll", { FANG })
suite.check("and still so after a kill", loot.hover._alpha == 1 and Coloured(loot.label, "accentHi"))
loot:GetScript("OnLeave")(loot)
Motion:FinishAll()
suite.check("leaving, it settles back to gold", loot.hover._alpha == 0 and Coloured(loot.label, "accent"))

local function LineX() return TUI.tabLine._point and TUI.tabLine._point[4] end
local farmX = LineX()
TUI:SetTab("loot")
Motion:FinishAll()
local lootX = LineX()
TUI:SetTab("farm")
Motion:Step(0.08)
local midX = LineX()
Loot("Gnoll", { FANG })
suite.check("a kill while the line slides does not make it jump",
    midX > farmX and midX < lootX and Near(LineX(), midX), LineX())
TUI:SetTab("loot")
local turned = LineX()
Motion:Step(0.05)
local back = LineX()
Motion:FinishAll()
suite.check("picked again mid-slide, it turns round from where it is and lands under its tab",
    Near(turned, midX) and back > midX and Near(LineX(), lootX), turned)
TUI:SetTab("farm")
Settle()

--------------------------------------------------------------------------------
-- The unlock banner's title on a narrow panel
--------------------------------------------------------------------------------

-- The game's outlined capitals run wider than the test client's six pixels
-- a letter: about three quarters of the font size.
local TextWidth = Theme.TextWidth
Theme.TextWidth = function(size, text)
    local px = Theme.sizes[size] or tonumber(size) or Theme.sizes.normal
    return math.ceil(#ns.Util.StripColor(text or "") * px * 0.75)
end

local banner = FX:Banner()
banner.title.SetFont = function(self, _, size) self._size = size end

local function TitleFits(room)
    local size = banner.title._size == Theme.sizes.large and "large" or "normal"
    return Theme.TextWidth(size, banner.title:GetText()) + 2 <= room
end

local GATHER = { title = "GATHER RATES UNLOCKED", subject = "Copper Vein  |  20 gathers", key = "node:none" }

-- The narrowest panel: 180 wide, the banner 8 less, its title 12 less again.
banner._width = 180 - 8
FX:Unlocked(GATHER)
suite.check("on the narrowest panel the title is not cut off", TitleFits(160), banner.title:GetText())
suite.check("it says RATES UNLOCKED, as big as fits",
    banner.title:GetText() == "RATES UNLOCKED" and banner.title._size == Theme.sizes.large,
    banner.title:GetText())

banner._width = 220 - 8
FX:Unlocked(GATHER)
suite.check("a little wider, the whole title a size down",
    banner.title:GetText() == "GATHER RATES UNLOCKED" and banner.title._size == Theme.sizes.normal
    and TitleFits(200), banner.title._size)

banner._width = 260 - 8
FX:Unlocked(GATHER)
suite.check("at the usual width, whole and large",
    banner.title:GetText() == "GATHER RATES UNLOCKED" and banner.title._size == Theme.sizes.large,
    banner.title._size)

Theme.TextWidth = TextWidth
banner._width = nil
Settle()

--------------------------------------------------------------------------------
-- The Effects setting
--------------------------------------------------------------------------------

ns.SettingsUI:Show()
local controls = ns.SettingsUI.controls
local effectsRow = controls.effects._parent
controls.effects:Pick(controls.effects:GetValue() - 1)
local saved = ns.db.trackerEffects
controls.effects:Pick(controls.effects:GetValue() + 1)
suite.check("Effects sits with the windows, not under the kill tally, and saves where it always has",
    effectsRow._parent == controls.windowScale._parent._parent
    and effectsRow._parent ~= controls.tracker._parent._parent and saved == "subtle", saved)
suite.check("named for what it moves", effectsRow.label:GetText() == "Effects:",
    effectsRow.label:GetText())
suite.check("and has no hover words (the owner, 2026-10-15)",
    (effectsRow.hint:GetText() or "") == "")
ns.SettingsUI:Hide()

ns.HandleSlash("effects full")
suite.check("/farm effects says it is about the windows",
    (Last(env.chat) or ""):find("window effects: full", 1, true) ~= nil, Last(env.chat))
Settle()

--------------------------------------------------------------------------------
-- Off lands everything at once
--------------------------------------------------------------------------------

ns.HandleSlash("tracker off")
ns.HandleSlash("tracker on")
TUI:SetTab("loot")
farm:GetScript("OnEnter")(farm)
suite.check("the panel fading up, the line sliding, a tab lighting",
    Motion:Running(frame, "open") and Motion:Running(TUI, "tabline") and Motion:Running(farm, "hover"))

glow = {}
ns.HandleSlash("effects off")
suite.check("switching Effects off lands everything at once", #Motion.tweens == 0, #Motion.tweens)
suite.check("the panel fully drawn, its glow at rest, the tab lit, the line under its tab",
    frame._alpha == 1 and Near(Last(glow), rest) and farm.hover._alpha == 1 and Near(LineX(), lootX))

-- With Off, nothing moves at all.
frame._alpha = nil
glow = {}
ns.HandleSlash("tracker off")
ns.HandleSlash("tracker on")
FX:Unlocked({ title = "DROP RATES UNLOCKED", subject = "Gnoll  |  20 kills", key = "mob:Gnoll" })
suite.check("off: shown again it is there at once, and rates unlocking leave its glow at rest",
    frame._alpha == 1 and #glow == 1 and Near(glow[1], rest) and #Motion.tweens == 0, #glow)
TUI:SetTab("farm")
loot:GetScript("OnEnter")(loot)
suite.check("off: the line is under its tab and a tab lights, at once",
    Near(LineX(), farmX) and not Motion:Running(TUI, "tabline")
    and Motion:Value(loot, "hover") == 1 and loot.hover._alpha == 1 and not Motion:Running(loot, "hover"))
loot:GetScript("OnLeave")(loot)
ns.HandleSlash("effects full")

-- A Loot tab line lights under the mouse too (the owner, 2026-10-12: the
-- hover "doesn't appear when moving over this list"). It took no mouse, so
-- nothing lit it; now it does, the gold edge, wash and bleed come up over
-- its quality light, and its tooltip says a right-click hides it.
TUI:SetTab("loot")
local item
for index, line in ipairs(TUI.shown or {}) do
    if line.style == "loot" then item = TUI.lines[index] break end
end
suite.check("loot: the Loot tab has an item line", item ~= nil)
if item then
    local takes
    item.EnableMouse = function(_, on) takes = on end
    TUI:Render()
    suite.check("loot: an item line takes the mouse", takes == true and TUI.TakesMouse(item.line))
    item.IsVisible = function() return true end
    item.IsMouseOver = function() return true end
    item.hover.SetAlpha = function(self, alpha) self._alpha = alpha end
    item.hoverEdge.SetAlpha = function(self, alpha) self._alpha = alpha end
    GameTooltip._lines = {}
    item:GetScript("OnEnter")(item)
    Motion:FinishAll()
    local said = table.concat(GameTooltip._lines, " / ")
    suite.check("loot: under the mouse it lights, gold edge and wash shown",
        item.hover._alpha == 1 and item.hoverEdge._alpha == 1
        and item.hoverWash:IsShown() and item.hoverBleed:IsShown(), said)
    suite.check("loot: its tooltip says a right-click hides it",
        said:find("Right-click to hide it.", 1, true) ~= nil, said)
    item:GetScript("OnLeave")(item)
    Motion:FinishAll()
    suite.check("loot: leaving, the wash and bleed are hidden, not faded",
        item.hover._alpha == 0 and not item.hoverWash:IsShown() and not item.hoverBleed:IsShown())
    item.IsMouseOver = function() return false end
end
TUI:SetTab("farm")

-- Dark glass lines (the owner, 2026-10-12, "like the Tradeskills queue"):
-- folded mobs and loose lines take glass and glassAlt in turn, a heading
-- keeps its band, an open card's lines sit on the card, and the Loot tab
-- shades by rank.
local striped = TUI.Stripe({
    { style = "heading" },
    { style = "mob", folded = false, live = true },
    { style = "place" }, { style = "icons" },
    { style = "mob", folded = true },
    { style = "mob", folded = true },
    { style = "heading" },
    { style = "note" }, { style = "value" },
})
suite.check("glass: a heading keeps its band",
    striped[1].glass == "header" and striped[7].glass == "header")
suite.check("glass: an open card's lines sit on the card",
    striped[3].glass == false and striped[4].glass == false)
suite.check("glass: mobs and loose lines take glass and glassAlt in turn",
    striped[2].glass == "glass" and striped[5].glass == "glassAlt" and striped[6].glass == "glass"
    and striped[8].glass == "glass" and striped[9].glass == "glassAlt")
local ranked = TUI.Stripe({ { style = "loot", rank = 1 }, { style = "loot", rank = 2 } })
suite.check("glass: the Loot tab shades by rank",
    ranked[1].glass == "glass" and ranked[2].glass == "glassAlt")

-- The panels close with the small red gem, not a flat "X", and the gem
-- does what the X did.
local gem = TUI.closeButton
suite.check("Kills & Loot closes with the red gem", gem and gem.glow ~= nil)
local printed
local realPrint = ns.Print
ns.Print = function(text) printed = text end
gem:GetScript("OnClick")(gem)
suite.check("the gem hides the panel", ns.db.trackerHidden == true)
suite.check("and says how to bring it back", printed and printed:find("/farm tracker", 1, true) ~= nil, printed)
ns.db.trackerHidden = nil

-- The gold gem left of the red one folds Kills & Loot to its title bar.
TUI.frame:Show()
suite.check("Kills & Loot has a fold gem", TUI.gems and TUI.gems.fold ~= nil)
TUI:SetFolded(true)
suite.check("folded, its tabs and lines hide",
    not TUI.tabStrip:IsShown() and not TUI.toolbar:IsShown())
TUI:SetFolded(false)
suite.check("opened, they come back", TUI.tabStrip:IsShown() and TUI.toolbar:IsShown())
if ns.GoalsUI and ns.GoalsUI.Build then
    ns.GoalsUI:Build()
    local goalsGem = ns.GoalsUI.closeButton
    suite.check("Goals closes with the red gem too", goalsGem and goalsGem.glow ~= nil)
    suite.check("Goals has a fold gem and a count chip",
        ns.GoalsUI.gems and ns.GoalsUI.gems.fold ~= nil and ns.GoalsUI.countChip ~= nil)
    printed = nil
    goalsGem:GetScript("OnClick")(goalsGem)
    suite.check("the gem hides the goals panel", ns.db.goalsHidden == true)
    suite.check("and says how to bring it back", printed and printed:find("/farm goals", 1, true) ~= nil, printed)
    ns.db.goalsHidden = nil
end
ns.Print = realPrint

Theme.SetGradientAlpha = SetGradientAlpha
Theme.SetHalo = SetHalo
_G.PlaySoundFile = nil

suite.done()
