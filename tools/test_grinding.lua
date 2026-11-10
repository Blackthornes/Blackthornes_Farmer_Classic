-- The Grind tab: where mobs of a level band and a kind gather.
--
-- What matters: only mobs the data or your own loot knows are listed, and
-- nothing is made up; a creature type comes from the game (learned when you
-- meet a mob, or shipped in the harvest file) and a mob nobody has seen is
-- left out of a type filter and counted; a mob confirmed on Forever drops
-- its Classic rows in that zone; camps are named places, or spots close
-- together, and point at a real mob's spot; the band follows your level
-- until you pick one, never past 30; the tab sits in the window, the
-- command and Settings reach it, and a camp points the arrow and shows on
-- the world map.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("grinding")
local check = suite.check

local ns = env.Load({ ui = true })
local Grinding, GrindingUI, GrindPins, UI = ns.Grinding, ns.GrindingUI, ns.GrindPins, ns.UI
local DB = ns.DB

env.world.zone = "Westfall"
env.world.subZone = ""

-- The player is level 25 in the test client.

--------------------------------------------------------------------------------
-- Test mobs, in a zone of their own so the seed data stays out of the way
--------------------------------------------------------------------------------

local ZONE = "Test Vale"

DB:RegisterItem({ name = "Test Cloth", category = "Cloth", sources = {
    { name = "Vale Bandit", zone = ZONE, location = "Bandit Camp", coords = { 40, 40 },
        minLevel = 24, maxLevel = 25, chance = 30 },
    { name = "Vale Thug", zone = ZONE, location = "Bandit Camp", coords = { 42, 41 },
        minLevel = 25, maxLevel = 26, chance = 20 },
    -- Classic says 30-31 here; Forever measured it lower, below.
    { name = "Vale Ghoul", zone = ZONE, location = "Old Crypt", minLevel = 30, maxLevel = 31 },
    { name = "Vale Ogre", zone = ZONE, minLevel = 40, maxLevel = 41 },
} })

DB:RegisterItem({ name = "Test Bone", category = "Misc", sources = {
    { name = "Vale Ghoul", zone = ZONE, location = "The Graves", coords = { 70, 20 },
        minLevel = 23, maxLevel = 24, provenance = "forever" },
} })

DB:RegisterItem({ name = "Test Hide", category = "Leatherworking", sources = {
    { kind = "skinning", name = "Vale Wolf", zone = ZONE, coords = { 10, 80 }, minLevel = 22, maxLevel = 24 },
    { kind = "skinning", name = "Vale Boar", zone = ZONE, coords = { 13, 82 }, minLevel = 23, maxLevel = 25 },
    { kind = "skinning", name = "Vale Bear", zone = ZONE, coords = { 60, 90 }, minLevel = 25, maxLevel = 26 },
    { kind = "node", name = "Not A Mob", zone = ZONE, minLevel = 25 },
} })

local function CampsIn(camps, zone)
    local found = {}
    for _, camp in ipairs(camps) do
        if camp.zone == zone then found[#found + 1] = camp end
    end
    return found
end

local function CampNamed(camps, label)
    for _, camp in ipairs(camps) do
        if camp.zone == ZONE and camp.label == label then return camp end
    end
end

local function Names(camp)
    local names = {}
    for _, mob in ipairs(camp and camp.mobs or {}) do names[#names + 1] = mob.name end
    return table.concat(names, ",")
end

--------------------------------------------------------------------------------
-- The level band
--------------------------------------------------------------------------------

local low, high = Grinding:Range()
check("the band follows your level", low == 23 and high == 27, low .. "-" .. high)
check("until one is picked", Grinding:FollowsLevel())

check("a picked band is swapped round", select(1, Grinding:SetRange(26, 22)) == 22)
low, high = Grinding:Range()
check("and kept", low == 22 and high == 26 and not Grinding:FollowsLevel(), low .. "-" .. high)
Grinding:SetRange(28, 45)
check("a band past 30 is kept", select(2, Grinding:Range()) == 45)
Grinding:SetRange(55, 70)
check("never past the level cap", select(2, Grinding:Range()) == 60)
Grinding:FollowLevel()
check("My level goes back to following", Grinding:FollowsLevel())

--------------------------------------------------------------------------------
-- Camps, any type
--------------------------------------------------------------------------------

local camps, unknown = Grinding:Camps({ low = 22, high = 26, type = false, gives = false })
local mine = CampsIn(camps, ZONE)

local bandit = CampNamed(camps, "Bandit Camp")
check("a named place is one camp", bandit and Names(bandit) == "Vale Bandit,Vale Thug", Names(bandit))
check("its band spans its mobs", bandit and bandit.minLevel == 24 and bandit.maxLevel == 26)
check("its spot is one of its mobs' own",
    bandit and (bandit.coords[1] == 40 or bandit.coords[1] == 42), bandit and bandit.coords[1])

local graves = CampNamed(camps, "The Graves")
check("a mob confirmed on Forever is listed at its Forever level", graves
    and graves.mobs[1].minLevel == 23 and graves.forever, Names(graves))
check("and its Classic row in that zone is gone", CampNamed(camps, "Old Crypt") == nil)

local pack
for _, camp in ipairs(mine) do
    if camp.mobs[1] and camp.mobs[1].name == "Vale Wolf" then pack = camp end
end
check("unnamed spots close together are one camp", pack and Names(pack) == "Vale Wolf,Vale Boar", Names(pack))
check("named by where it is", pack and pack.label:find("^around ") ~= nil, pack and pack.label)
check("a spot further off is a camp of its own", (function()
    for _, camp in ipairs(mine) do
        if Names(camp) == "Vale Bear" then return true end
    end
    return false
end)())

for _, camp in ipairs(mine) do
    for _, mob in ipairs(camp.mobs) do
        check("out of the band is left out: " .. mob.name, mob.name ~= "Vale Ogre")
        check("a node is not a mob", mob.name ~= "Not A Mob")
    end
end
check("busiest camps first", camps[1].count >= camps[#camps].count)

--------------------------------------------------------------------------------
-- What they give
--------------------------------------------------------------------------------

camps = Grinding:Camps({ low = 22, high = 26, type = false, gives = "skinning" })
for _, camp in ipairs(CampsIn(camps, ZONE)) do
    for _, mob in ipairs(camp.mobs) do
        check("skinning lists only skinning sources: " .. mob.name, mob.skinning == true)
    end
end

camps = Grinding:Camps({ low = 22, high = 26, type = false, gives = "cloth" })
check("cloth lists the cloth droppers", CampNamed(camps, "Bandit Camp") ~= nil)
check("and not a mob with no cloth", CampNamed(camps, "The Graves") == nil)

--------------------------------------------------------------------------------
-- Creature types: from the game, never guessed
--------------------------------------------------------------------------------

camps, unknown = Grinding:Camps({ low = 22, high = 26, type = "Humanoid", gives = false })
check("no type seen yet: none listed as humanoid", #CampsIn(camps, ZONE) == 0)
check("and they are counted", unknown >= 7, unknown)

-- Shipped types (the harvest file) ...
DB:CreatureTypes({ ["Vale Bandit"] = "Humanoid", ["Vale Wolf"] = "Beast", [""] = "Beast", ["Vale Boar"] = 7 })
check("shipped types are read", Grinding.TypeOf("Vale Bandit") == "Humanoid")
check("bad rows are skipped", Grinding.TypeOf("Vale Boar") == nil)

-- ... and ones met in game, which win.
local seenType = { ["Vale Thug"] = "Humanoid", ["Vale Wolf"] = "Beast", ["Vale Bear"] = "Beast",
    ["Vale Ghoul"] = "Undead", ["Some Guard"] = "Humanoid", ["Vale Boar"] = "Not specified" }
_G.UnitCreatureType = function(unit)
    return env.world.target and seenType[env.world.target.name]
end
local serial = 0
local function Meet(name)
    serial = serial + 1
    env.world.target = { name = name, level = 25, dead = false, guid = "Creature-0-0-0-0-" .. serial }
    ns.Harvest:NoteUnit("target")
end
for _, name in ipairs({ "Vale Thug", "Vale Wolf", "Vale Bear", "Vale Ghoul", "Some Guard", "Vale Boar" }) do
    Meet(name)
end

check("a mob met in game is learned", ns.db.creatureTypes["Vale Thug"] == "Humanoid")
check("\"Not specified\" is not a type", ns.db.creatureTypes["Vale Boar"] == nil)

_G.UnitCreatureType = function() error("secret") end
Meet("Vale Bandit")
check("a type the client will not hand over breaks nothing", ns.db.creatureTypes["Vale Bandit"] == nil)
_G.UnitCreatureType = nil
Meet("Vale Bandit")
check("nor a client without the call", Grinding.TypeOf("Vale Bandit") == "Humanoid")

ns.db.creatureTypes["Vale Bandit"] = "Undead"
check("what you saw beats what shipped", Grinding.TypeOf("Vale Bandit") == "Undead")
ns.db.creatureTypes["Vale Bandit"] = nil

camps, unknown = Grinding:Camps({ low = 22, high = 26, type = "Humanoid", gives = false })
check("humanoids: the bandit camp", Names(CampNamed(camps, "Bandit Camp")) == "Vale Bandit,Vale Thug",
    Names(CampNamed(camps, "Bandit Camp")))
check("and no undead", CampNamed(camps, "The Graves") == nil)

camps = Grinding:Camps({ low = 22, high = 26, type = "Beast", gives = false })
check("beasts: the wolf pack, the boar's type still unseen",
    #CampsIn(camps, ZONE) == 2 and pack ~= nil)

check("a type with no chip of its own is Other", Grinding.Chip("Giant") == "Other"
    and Grinding.Chip("Beast") == "Beast" and Grinding.Chip(nil) == nil)

--------------------------------------------------------------------------------
-- The export ships types for mobs the data knows, and nothing else
--------------------------------------------------------------------------------

local block, count = Grinding:ExportBlock()
check("the export writes the learned types", block and block:find('%["Vale Thug"%] = "Humanoid"') ~= nil, block)
check("not a mob outside the data", block and not block:find("Some Guard"), block)
check("as one call the data file runs", block and block:find("DB:CreatureTypes%(") ~= nil)
-- Equipment's and Pets' tools read the harvest file with only RegisterItem.
local okRun, errRun = pcall(function()
    local chunk = assert(loadstring("local DB = ... " .. block))
    chunk({ RegisterItem = function() end })
end)
check("a reader without CreatureTypes still loads it", okRun, errRun)
local shipped = {}
assert(loadstring("local DB = ... " .. block))({ CreatureTypes = function(_, map) shipped = map end })
check("and the addon reads it back", shipped["Vale Thug"] == "Humanoid")
check("counted", count == 4, count)

--------------------------------------------------------------------------------
-- The order of the camps (2026-10-10: by distance, by level, or both)
--------------------------------------------------------------------------------

local ALL = { low = 1, high = 30, type = false, gives = false }

check("busiest first until another order is picked", Grinding.Sort() == "busiest")

-- Before the menu there was only Nearest first; a save that has it on
-- keeps it, and the old key is never renamed or cleared.
ns.db.grindNearFirst = true
check("an old Nearest first is still read", Grinding.Sort() == "nearest" and Grinding.NearFirst())
ns.db.grindNearFirst = nil

Grinding:SetNearFirst(true)
camps = Grinding:Camps(ALL)
check("nearest first: your own zone leads", camps[1].hops == 0, camps[1].zone)
check("saved under its own key", ns.db.grindSort == "nearest")
Grinding:SetNearFirst(false)
check("and back to busiest", Grinding.Sort() == "busiest")

Grinding:SetSort("nonsense")
check("an unknown order is ignored", Grinding.Sort() == "busiest")

camps = Grinding:Camps({ low = 22, high = 26, type = false, gives = false })
check("busiest: most mobs first", CampsIn(camps, ZONE)[1].count == 2)

Grinding:SetSort("level")
camps = Grinding:Camps({ low = 22, high = 26, type = false, gives = false })
local levels = {}
for _, camp in ipairs(CampsIn(camps, ZONE)) do levels[#levels + 1] = camp.minLevel end
check("level: the lowest camps first", table.concat(levels, ",") == "22,23,24,25", table.concat(levels, ","))

local function InOrder(list, nearToo)
    for index = 2, #list do
        local a, b = list[index - 1], list[index]
        if a.minLevel > b.minLevel then return false end
        if nearToo and a.minLevel == b.minLevel and (a.hops or 99) > (b.hops or 99) then return false end
    end
    return true
end
check("level: across every zone", InOrder(Grinding:Camps(ALL), false))

Grinding:SetSort("levelnear")
check("level, then nearest: same level, the nearer first", InOrder(Grinding:Camps(ALL), true))
check("its menu words", Grinding.SortLabel() == "Level, then nearest")
Grinding:SetSort("busiest")

--------------------------------------------------------------------------------
-- The command
--------------------------------------------------------------------------------

ns.HandleSlash("grind 15-20 humanoids cloth")
check("/farm grind sets the band", ns.db.grindMin == 15 and ns.db.grindMax == 20)
check("and the type", Grinding:Type() == "Humanoid")
check("and what they give", Grinding:Gives() == "cloth")
check("and opens the tab", UI.frame:IsShown() and UI.tab == "grind", UI.tab)
check("which is remembered", ns.db.lastTab == "grind")

ns.HandleSlash("grind any me")
check("any clears the filters", Grinding:Type() == nil and Grinding:Gives() == nil)
check("me follows your level", Grinding:FollowsLevel())

ns.HandleSlash("grind 61 70")
check("a typed band is held to the cap", ns.db.grindMin == 60 and ns.db.grindMax == 60)

--------------------------------------------------------------------------------
-- The tab
--------------------------------------------------------------------------------

check("the window has a Grind tab", UI.tabs.grind ~= nil)
Grinding:SetRange(22, 26)
UI:ShowTab("grind")
check("its view shows", UI.grindView:IsShown() and not UI.searchView:IsShown()
    and not UI.rankingsView:IsShown())

local rows = GrindingUI.list.data
local campRow, mobRow
for _, row in ipairs(rows) do
    if row.type == "camp" and row.camp.zone == ZONE and row.camp.label == "Bandit Camp" then campRow = row end
    if row.type == "mob" and row.mob.name == "Vale Thug" then mobRow = row end
end
check("a band per camp", campRow ~= nil)
check("its mobs under it", mobRow ~= nil)
check("a mob's type shows", mobRow and GrindingUI:MobTexts(mobRow.mob).type == "Humanoid")
check("an unseen type is a question mark", GrindingUI:MobTexts({ name = "Nobody", minLevel = 1 }).type == "?")
check("what it gives", mobRow and GrindingUI:MobTexts(mobRow.mob).gives == "Cloth")
check("the band names the place and level", GrindingUI.CampText(campRow.camp):find("Test Vale, Bandit Camp") ~= nil)

Grinding:SetType("Humanoid")
GrindingUI:Render()
local note
for _, row in ipairs(GrindingUI.list.data) do
    if row.type == "note" and row.text:find("until Farmer learns their type") then note = row end
end
check("mobs left out by type are counted in the list", note ~= nil)
check("its chip is lit, and only it", (function()
    for _, chip in ipairs(GrindingUI.typeChips) do
        if chip.selected ~= (chip.filterKind == "Humanoid") then return false end
    end
    return true
end)())
Grinding:SetType(nil)

Grinding:SetRange(1, 1)
Grinding:SetGives("skinning")
Grinding:SetType("Demon")
GrindingUI:Render()
check("an empty band says so", GrindingUI.list.data[1].type == "note"
    and GrindingUI.list.data[1].text:find("level 1 to 1") ~= nil, GrindingUI.list.data[1].text)
Grinding:SetType(nil)
Grinding:SetGives(nil)
Grinding:SetRange(22, 26)
GrindingUI:Render()

--------------------------------------------------------------------------------
-- A camp points the arrow
--------------------------------------------------------------------------------

local printed = {}
local print0 = ns.Print
ns.Print = function(text) printed[#printed + 1] = text end
GrindingUI:OnRowClick(campRow)
ns.Print = print0

check("a click on a camp follows it", ns.Arrow.grind == campRow.camp)
check("and turns the arrow on", ns.Arrow.IsOn())
local following = ns.Arrow:Following()
check("the arrow follows the camp", following.grind == campRow.camp
    and following.item == "Test Vale, Bandit Camp", following.item)
check("and says where", printed[#printed] and printed[#printed]:find("Bandit Camp") ~= nil)

local targets = ns.Arrow:GrindTargets(campRow.camp, nil)
-- The test client has no map for Test Vale: one place, named for the camp,
-- rather than a point made up.
check("a camp off the maps is one place, never a made-up point", #targets == 1
    and targets[1].name == "Bandit Camp" and targets[1].x == nil, targets[1] and targets[1].name)

ns.db.goals = { list = { { item = "Copper Ore", target = 10, have = 0 } }, today = {} }
check("following a goal again lets the camp go", ns.Arrow:Follow("Copper Ore") and ns.Arrow.grind == nil)
ns.Arrow:Grind(campRow.camp)
check("the dial's click goes back to goals", ns.Arrow:NextGoal() and ns.Arrow.grind == nil)

--------------------------------------------------------------------------------
-- The world map
--------------------------------------------------------------------------------

check("the map shows what the tab lists", GrindPins.camps == GrindingUI.camps)
local onMap = GrindPins:CampsOn(ZONE)
check("camps with a spot, on their zone's map", #onMap >= 3, #onMap)
for _, camp in ipairs(onMap) do
    check("never one without a spot", type(camp.coords) == "table")
end
check("not on another zone's", #GrindPins:CampsOn("Durotar") == 0 or GrindPins:CampsOn("Durotar")[1].zone == "Durotar")

-- Only while the tab is open, plus the camp the arrow follows (a player
-- found the swords left on the map all session, 2026-11-10).
UI:ShowTab("grind")
check("the tab open shows every camp it lists", GrindPins.TabOpen() and GrindPins:Shown() == GrindPins.camps)
ns.Arrow:StopGrind()
UI:Hide()
check("the tab shut, nothing followed: no swords", not GrindPins.TabOpen() and #GrindPins:Shown() == 0)
check("and none on the zone's map", #GrindPins:CampsOn(ZONE, nil, GrindPins:Shown()) == 0)
ns.Arrow:Grind(campRow.camp)
local followed = GrindPins:Shown()
check("the tab shut, a camp followed: only that one", #followed == 1 and followed[1] == campRow.camp)
ns.Arrow:StopGrind()
check("let go, it goes too", #GrindPins:Shown() == 0)

check("on unless turned off", GrindPins.IsOn())
ns.HandleSlash("grind pins off")
check("/farm grind pins off", not GrindPins.IsOn() and ns.db.grindPins == false)
check("draws nothing then", GrindPins:Draw() == 0)

--------------------------------------------------------------------------------
-- Sorting from the tab: the menu, the headings, the command
--------------------------------------------------------------------------------

UI:ShowTab("grind")
check("the sort chip names the order", GrindingUI.sortChip.label:GetText() == "SORT: BUSIEST",
    GrindingUI.sortChip.label:GetText())
GrindingUI.sortChip:GetScript("OnClick")(GrindingUI.sortChip, "LeftButton")
check("a click opens the menu", GrindingUI.sortMenu:IsShown())
-- 2026-10-10: in the window's own layer the chips behind showed through it.
check("drawn above the window, not in its layer", GrindingUI.sortMenu._strata == "FULLSCREEN_DIALOG",
    GrindingUI.sortMenu._strata)
check("and over its rim and trim",
    GrindingUI.sortMenu:GetFrameLevel() > UI.frame:GetFrameLevel() + 20)
check("with every order", #GrindingUI.sortMenu.items == #Grinding.SORTS)
check("the one in use lit", GrindingUI.sortMenu.items[1].selected == true)
local levelItem = GrindingUI.sortMenu.items[3]
levelItem:GetScript("OnClick")(levelItem, "LeftButton")
check("picking one sorts by it", Grinding.Sort() == "level")
check("and closes the menu", not GrindingUI.sortMenu:IsShown())
check("the chip says so", GrindingUI.sortChip.label:GetText() == "SORT: LEVEL")
GrindingUI.sortChip:GetScript("OnClick")(GrindingUI.sortChip, "LeftButton")
GrindingUI.sortChip:GetScript("OnClick")(GrindingUI.sortChip, "LeftButton")
check("a second click closes it", not GrindingUI.sortMenu:IsShown())

local function MobsUnder(label)
    local names, inside = {}, false
    for _, row in ipairs(GrindingUI.list.data) do
        if row.type == "camp" then inside = row.camp.zone == ZONE and row.camp.label == label end
        if inside and row.type == "mob" then names[#names + 1] = row.mob.name end
    end
    return table.concat(names, ",")
end

check("a camp's mobs lowest first", MobsUnder("Bandit Camp") == "Vale Bandit,Vale Thug")
local mobHeading = GrindingUI.sorter.buttons.mob
mobHeading:GetScript("OnClick")(mobHeading)
check("a heading sorts each camp's mobs", ns.db.grindColumns.key == "mob" and ns.db.grindColumns.ascending)
mobHeading:GetScript("OnClick")(mobHeading)
check("and turns them round", MobsUnder("Bandit Camp") == "Vale Thug,Vale Bandit", MobsUnder("Bandit Camp"))
check("which is remembered", ns.db.grindColumns.ascending == false)
mobHeading:GetScript("OnClick")(mobHeading)
check("a third click is the usual order again", ns.db.grindColumns == nil
    and MobsUnder("Bandit Camp") == "Vale Bandit,Vale Thug")
local worthHeading = GrindingUI.sorter.buttons.worth
worthHeading:GetScript("OnClick")(worthHeading)
check("worth starts high", ns.db.grindColumns.key == "worth" and not ns.db.grindColumns.ascending)
worthHeading:GetScript("OnClick")(worthHeading)
worthHeading:GetScript("OnClick")(worthHeading)

ns.HandleSlash("grind sort level then nearest")
check("/farm grind sort level then nearest", Grinding.Sort() == "levelnear")
ns.HandleSlash("grind sort nearest")
check("/farm grind sort nearest", Grinding.Sort() == "nearest")
ns.HandleSlash("grind sort busiest")
check("/farm grind sort busiest", Grinding.Sort() == "busiest")

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local SettingsUI = ns.SettingsUI
SettingsUI:Show()
local controls = SettingsUI.controls
check("Settings shows the map switch as saved", controls.grindPins:GetChecked() == false)
controls.grindPins:GetScript("OnClick")(controls.grindPins)
check("and turns it back on", GrindPins.IsOn(), ns.db.grindPins)
UI:Hide()
controls.grindOpen:GetScript("OnClick")(controls.grindOpen, "LeftButton")
check("its Open button opens the tab", UI.frame:IsShown() and UI.tab == "grind")
SettingsUI:Hide()

--------------------------------------------------------------------------------
-- The filter chips never overlap (2026-10-10: Skinning ran into Nearest
-- first, the game's font being wider than the guess; Sort took its place)
--------------------------------------------------------------------------------

do
    local chips = {}
    for _, chip in ipairs(GrindingUI.typeChips) do chips[#chips + 1] = chip end
    for _, chip in ipairs(GrindingUI.givesChips) do chips[#chips + 1] = chip end
    chips[#chips + 1] = GrindingUI.sortChip

    local function Overlaps(room)
        local spans = {}
        for _, chip in ipairs(chips) do
            local point = chip._point
            if point and point[2] == GrindingUI.filters then
                local x, y = point[4], point[5]
                local w = chip:GetWidth()
                if x + w > room + 0.5 then return "past the edge: " .. chip.label:GetText() end
                for _, other in ipairs(spans) do
                    if other.y == y and x < other.x + other.w and other.x < x + w then
                        return chip.label:GetText() .. " on " .. other.text
                    end
                end
                spans[#spans + 1] = { x = x, y = y, w = w, text = chip.label:GetText() }
            end
        end
        return nil
    end

    -- Words drawn twice as wide as the guess, as a large text size might.
    for _, chip in ipairs(chips) do
        chip.label.GetStringWidth = function(label) return #(label._text or "") * 13 end
    end

    GrindingUI.filters._width = 682
    GrindingUI:LayoutChips()
    check("each chip is as wide as its words",
        GrindingUI.sortChip:GetWidth() >= #GrindingUI.sortChip.label:GetText() * 13 + 16,
        GrindingUI.sortChip:GetWidth())
    check("no chip runs into another", Overlaps(682) == nil, Overlaps(682))
    check("they wrap onto another line rather than overlap", GrindingUI.chipLines >= 2, GrindingUI.chipLines)
    check("and the list moves down with them",
        GrindingUI.filters:GetHeight() >= 18 + 22 * (GrindingUI.chipLines - 1))

    GrindingUI.filters._width = 300
    GrindingUI:LayoutChips()
    check("however narrow the row", Overlaps(300) == nil, Overlaps(300))

    for _, chip in ipairs(chips) do chip.label.GetStringWidth = nil end
    GrindingUI.filters._width = 682
    UI.frame._width = 724
    GrindingUI:LayoutChips()
    check("at normal size the chips fit one line", GrindingUI.chipLines == 1, GrindingUI.chipLines)
    check("and Sort sits up beside My level",
        GrindingUI.sortChip._point and GrindingUI.sortChip._point[2] == GrindingUI.mineButton)
end

--------------------------------------------------------------------------------
-- A seed-file group ("spiders") is not a mob anyone can target to learn its
-- type, so it is never counted as one waiting to be learned. Last, since
-- the row would otherwise sit in the lists above.
--------------------------------------------------------------------------------

local _, unknownBefore = Grinding:Camps({ low = 22, high = 26, type = "Humanoid", gives = false })
DB:RegisterItem({ name = "Test Silk", category = "Cloth", sources = {
    { name = "vale spiders", zone = ZONE, minLevel = 23, maxLevel = 25 },
} })
local _, unknownWithGroup = Grinding:Camps({ low = 22, high = 26, type = "Humanoid", gives = false })
check("a group row is known for one", Grinding.IsGroup("vale spiders") and not Grinding.IsGroup("Vale Thug"))
check("and never counted as a mob of unknown type", unknownWithGroup == unknownBefore, unknownWithGroup)

--------------------------------------------------------------------------------
-- The level boxes take a typed number and the mouse wheel (2026-10-22)
--------------------------------------------------------------------------------

do
    local low, high = GrindingUI.low, GrindingUI.high
    check("the level boxes can be typed in", low.box ~= nil and high.box ~= nil)
    low:Edit()
    low.box:SetText("23")
    low.Done(true)
    check("a typed number sets the low end", low:GetValue() == 23, low:GetValue())
    low:Edit()
    low.box:SetText("999")
    low.Done(true)
    check("a number past the cap stops at the cap", low:GetValue() == Grinding.MaxLevel(), low:GetValue())
    check("and pushes the high end up with it", high:GetValue() >= low:GetValue(), high:GetValue())
    low:Edit()
    low.box:SetText("12")
    low.Done(false)
    check("Escape keeps the number as it was", low:GetValue() == Grinding.MaxLevel(), low:GetValue())
    low:SetValue(20)
    low:GetScript("OnMouseWheel")(low, 1)
    check("rolling the wheel up adds a level", low:GetValue() == 21, low:GetValue())
    low:GetScript("OnMouseWheel")(low, -1)
    check("and down takes one off", low:GetValue() == 20, low:GetValue())
    Grinding:SetRange(22, 26)
    GrindingUI:Render()
end

--------------------------------------------------------------------------------
-- Columns stay put as the type chips change (2026-10-22)
--------------------------------------------------------------------------------

do
    local function Widths()
        local list = {}
        for key, column in pairs(GrindingUI.columns) do
            if type(column) == "table" and column.w then list[#list + 1] = key .. "=" .. column.w end
        end
        table.sort(list)
        return table.concat(list, " ")
    end
    GrindingUI:Render()
    local before = Widths()
    Grinding:SetType("Humanoid")
    GrindingUI:Render()
    local after = Widths()
    Grinding:SetType(nil)
    GrindingUI:Render()
    check("a type chip leaves the column widths as they were", before == after, before .. " | " .. after)
    local level = GrindingUI.columns.level
    check("the level column has room for its sort arrow",
        level and level.w >= ns.Theme.TextWidth("tiny", L and L["LEVEL"] or "LEVEL") + GrindingUI.ARROW_ROOM * 2,
        level and level.w)
end

suite.done()
