-- A German client (2026-10-11): the data names items, zones, skills and
-- creature types in English, and a German client names them in German.
-- Every check that compared the client's words with English ones now also
-- knows the client's own word, by ID; on an English client nothing changes.
--
-- What matters: "Leinenstoff" is Linen Cloth to the database, the search,
-- goals (Tradeskills' Set goal passes the German name) and Butler; Bergbau,
-- Kürschnerei and Angeln are Mining, Skinning and Fishing; "Wald von
-- Elwynn" is Elwynn Forest by its map; "Wildtier" is kept as Beast; and
-- "2 Silber 3 Kupfer" is coin.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("german")

local fireEvent

local LINEN, COPPER_ORE = 2589, 2770

-- What a German client calls things, by ID.
local ITEM_NAMES = { [LINEN] = "Leinenstoff", [COPPER_ORE] = "Kupfererz" }
local SPELL_NAMES = {
    [2575] = "Bergbau", [2366] = "Kräutersammeln", [8613] = "Kürschnerei", [7620] = "Angeln",
    -- Spells whose IDs the addon does not list, named as the skills are.
    [90001] = "Bergbau", [90002] = "Kräuterkunde", [90003] = "Kürschnerei",
}
local SKILL_LINES = {
    [186] = "Bergbau", [2946] = "Bergbau", [182] = "Kräuterkunde", [2944] = "Kräuterkunde",
    [393] = "Kürschnerei", [2947] = "Kürschnerei", [356] = "Angeln",
}
local TYPES = { [1] = "Wildtier", [3] = "Dämon", [6] = "Untoter", [7] = "Humanoid", [10] = "Nicht spezifiziert" }

local bags = {}

local function German(ns)
    _G.GetLocale = function() return "deDE" end
    _G.C_Item = {
        GetItemNameByID = function(id) return ITEM_NAMES[id] end,
        GetItemInfo = function(item)
            for id, name in pairs(ITEM_NAMES) do
                if item == id or item == name then
                    return name, ("|cffffffff|Hitem:%d::::::::25::::|h[%s]|h|r"):format(id, name)
                end
            end
            return nil
        end,
        GetItemCount = function(item) return bags[item] or 0 end,
    }
    _G.C_Spell = { GetSpellName = function(id) return SPELL_NAMES[id] end }
    _G.C_TradeSkillUI = {
        GetProfessionInfoBySkillLineID = function(id)
            return SKILL_LINES[id] and { professionName = SKILL_LINES[id] } or nil
        end,
    }
    _G.C_CreatureInfo = {
        GetCreatureTypeInfo = function(id)
            local names = { [2] = "Drachkin", [4] = "Elementar", [5] = "Riese", [8] = "Kleintier", [9] = "Mechanisch" }
            local name = TYPES[id] or names[id]
            return name and { name = name, creatureTypeID = id } or nil
        end,
    }
    _G.COPPER_AMOUNT, _G.SILVER_AMOUNT, _G.GOLD_AMOUNT = "%d Kupfer", "%d Silber", "%d Gold"
    fireEvent = ns.eventFrame:GetScript("OnEvent")
end

--------------------------------------------------------------------------------
-- An English client: nothing new runs
--------------------------------------------------------------------------------

local ns = env.Load({ ui = true })

suite.check("English: Linen Cloth by its name", ns.DB:GetItem("Linen Cloth").id == LINEN)
suite.check("English: an unknown name is nothing", ns.DB:GetItem("Leinenstoff") == nil)
suite.check("English: the client's names are never read", not ns.DB.learning)
suite.check("English: the coin is read as before", ns.Tracker.CoinCopper("1 Gold 2 Silver 3 Copper") == 10203)
suite.check("English: German coin is not coin", ns.Tracker.CoinCopper("2 Silber") == nil)
env.world.zone = "Wald von Elwynn"
env.world.mapID = 1429
suite.check("English: the zone stays as the client says", ns.Spots:Player().zone == "Wald von Elwynn")
env.world.zone = "Elwynn Forest"
suite.check("English: an English zone is itself", ns.Spots:Player().zone == "Elwynn Forest")
suite.check("English: Fishing is Fishing", ns.Gathering.SkillOf("Fishing", { "Fishing" }) == "Fishing")
suite.check("English: Angeln is nothing", ns.Gathering.SkillOf("Angeln", { "Fishing" }) == nil)
local englishLinen = ns.DB:GetItem("Linen Cloth")
suite.check("English: the shown name is the data's", ns.DB:ShowName(englishLinen) == "Linen Cloth")
suite.check("English: the kind is the data's", ns.DB:CategoryLabel(englishLinen) == "Cloth")

--------------------------------------------------------------------------------
-- A German client
--------------------------------------------------------------------------------

ns = env.Load({ ui = true })
German(ns)
local DB = ns.DB

-- Items by the client's name.
local linen, byClient = DB:GetItem("Leinenstoff")
suite.check("Leinenstoff is Linen Cloth", linen and linen.id == LINEN, linen and linen.name)
suite.check("found by the client's name", byClient == true)
suite.check("any case", DB:GetItem("  leinenstoff ") == linen)
suite.check("English still works", DB:GetItem("Linen Cloth") == linen)
suite.check("Kupfererz is Copper Ore", DB:GetItem("Kupfererz") and DB:GetItem("Kupfererz").name == "Copper Ore")
suite.check("the client's name is kept", DB:ClientName(linen) == "Leinenstoff")

-- A name the client had not loaded comes in later.
local silk = DB:GetItem("Silk Cloth")
suite.check("Silk Cloth not named yet", silk and DB:ClientName(silk) == nil)
ITEM_NAMES[silk.id] = "Seidenstoff"
fireEvent(ns.eventFrame, "GET_ITEM_INFO_RECEIVED", silk.id, true)
suite.check("named once it arrives", DB:GetItem("Seidenstoff") == silk)

-- The search finds it by the German name.
local found = false
for _, result in ipairs(ns.Search:Run("leinen")) do
    if result.item == linen then found = true end
end
suite.check("the search finds 'leinen'", found)

-- Names shown in the window are the client's (a German player saw the
-- suggestions in English, 2026-11-03).
suite.check("Linen Cloth shows as Leinenstoff", DB:ShowName(linen) == "Leinenstoff", DB:ShowName(linen))
suite.check("the header names it in German", ns.Search:ItemHeader(linen):find("Leinenstoff", 1, true) ~= nil)
local wool = DB:GetItem("Wool Cloth")
suite.check("one not loaded shows the data's name", wool and DB:ShowName(wool) == "Wool Cloth")
suite.check("and is not named yet", not DB:HasShownName(wool))
ITEM_NAMES[wool.id] = "Wollstoff"
fireEvent(ns.eventFrame, "GET_ITEM_INFO_RECEIVED", wool.id, true)
suite.check("then shows the client's name", DB:ShowName(wool) == "Wollstoff")
suite.check("a kind not listed shows as it is", DB:CategoryLabel({ category = "Something" }) == "Something")

-- The empty search's suggestions.
if ns.UI and ns.UI.empty then
    _G.UnitLevel = function() return 10 end
    ns.UI:ShowEmpty()
    local named = false
    for _, chip in ipairs(ns.UI.suggestChips) do
        if chip:IsShown() and chip.itemName == "Leinenstoff" then named = true end
    end
    suite.check("the suggestions name Linen Cloth in German", named)
end

-- Goals: Tradeskills' Set goal passes the German name.
bags[LINEN] = 4
local goal = ns.Goals:Set("Leinenstoff", 20)
suite.check("a goal by the German name", goal and goal.item == "Leinenstoff", goal and goal.item)
suite.check("it counts the bags by ID", goal and goal.have == 4, goal and goal.have)
suite.check("Find by the German name", ns.Goals:Find("Leinenstoff") == goal)
suite.check("Find by the English name", ns.Goals:Find("Linen Cloth") == goal)
suite.check("Have counts it", ns.Goals:Have("Leinenstoff") == 4)
suite.check("the best spot is found", ns.Goals:BestSpot("Leinenstoff") ~= nil)
local advice = ns.Butler:Advise(LINEN)
suite.check("Butler knows the goal", advice and advice.goal == "Leinenstoff" and advice.need == 16,
    advice and advice.need)
suite.check("a link resolves", ns.Goals:ResolveItem("|cffffffff|Hitem:2589::::|h[Leinenstoff]|h|r") == "Leinenstoff")
suite.check("an English name stays English", ns.Goals:ResolveItem("linen cloth") == "Linen Cloth")
suite.check("Remove by the German name", ns.Goals:Remove("Leinenstoff") == true)

-- Gathering and skill names.
local Gathering = ns.Gathering
suite.check("a Bergbau spell is ore", Gathering.KindOf(90001) == "ore")
suite.check("a Kräuterkunde spell is a herb", Gathering.KindOf(90002) == "herb")
suite.check("a Kürschnerei spell is Skinning", Gathering.IsSkinningSpell(90003))
suite.check("Bergbau is not Skinning", not Gathering.IsSkinningSpell(90001))

_G.GetProfessions, _G.GetProfessionInfo = nil, nil
_G.GetNumSkillLines = function() return 4 end
_G.GetSkillLineInfo = function(index)
    if index == 1 then return "Berufe", 1 end
    if index == 2 then return "Angeln", nil, nil, 88 end
    if index == 3 then return "Bergbau", nil, nil, 65 end
    if index == 4 then return "Kürschnerei", nil, nil, 30 end
end
suite.check("Angeln is the fishing skill", ns.Fishing:Skill() == 88, ns.Fishing:Skill())
local skills = ns.Spots.ReadSkills()
suite.check("Bergbau is Mining", skills and skills.Mining == 65)
suite.check("Kürschnerei is Skinning", skills and skills.Skinning == 30)
suite.check("no Herbalism", skills and skills.Herbalism == nil)
_G.GetNumSkillLines, _G.GetSkillLineInfo = nil, nil

-- Zones by the map.
local Spots = ns.Spots
_G.C_Map.GetMapInfo = function(id)
    return ({
        [1429] = { name = "Wald von Elwynn", parentMapID = 1415, mapType = 3 },
        [1415] = { name = "Östliche Königreiche", parentMapID = 947, mapType = 2 },
        [1433] = { name = "Rotkammgebirge", parentMapID = 1415, mapType = 3 },
        [9001] = { name = "Nordhain", parentMapID = 1429, mapType = 5 },
    })[id]
end
env.world.zone = "Wald von Elwynn"
env.world.mapID = 9001
local player = Spots:Player()
suite.check("Wald von Elwynn is Elwynn Forest", player.zone == "Elwynn Forest", player.zone)
suite.check("next door to Westfall", Spots.Hops(player.zone, "Westfall") == 1)
suite.check("your own record's zone counts too", Spots.ZoneOf("Wald von Elwynn") == "Elwynn Forest")
env.world.zone = "Irgendwo"
env.world.mapID = 7777
suite.check("a map not known leaves the name", Spots:Player().zone == "Irgendwo")

-- The arrow finds the zone's map by its ID.
_G.C_Map.GetMapChildrenInfo = function()
    return { { name = "Rotkammgebirge", mapType = 3, mapID = 1433 } }
end
local here = { map = 1429 }
suite.check("the arrow's zone map, where you stand", ns.Arrow:ZoneMap("Elwynn Forest", here) == 1429)
suite.check("the arrow's zone map, next door", ns.Arrow:ZoneMap("Redridge Mountains", here) == 1433)

-- Grind pins on a German map.
ns.GrindPins:Show({ { zone = "Elwynn Forest", coords = { 40, 50 } }, { zone = "Westfall", coords = { 1, 2 } } })
suite.check("grind camps on the German map", #ns.GrindPins:CampsOn("Wald von Elwynn", 1429) == 1)

-- Creature types are kept in English.
_G.UnitCreatureType = function() return "Wildtier" end
ns.Grinding:Learn("target", "Prowler")
suite.check("Wildtier is kept as Beast", ns.Grinding:Store()["Prowler"] == "Beast", ns.Grinding:Store()["Prowler"])
suite.check("Beast has its chip", ns.Grinding.Chip(ns.Grinding.TypeOf("Prowler")) == "Beast")
_G.UnitCreatureType = function() return "Nicht spezifiziert" end
ns.Grinding:Learn("target", "Barrel")
suite.check("no type is not kept", ns.Grinding:Store()["Barrel"] == nil)
ns.Grinding:Store()["Old Ghoul"] = "Untoter"
suite.check("an old German one reads in English", ns.Grinding.TypeOf("Old Ghoul") == "Undead")
_G.UnitCreatureType = nil

-- Coin.
suite.check("German coin", ns.Tracker.CoinCopper("1 Gold 2 Silber 3 Kupfer") == 10203)
suite.check("English coin still", ns.Tracker.CoinCopper("3 Copper") == 3)
suite.check("Kupfererz is no coin", not ns.Harvest:NameLooksLikeMoney("Kupfererz"))

-- Back to an English client for the suites after this one.
_G.GetLocale, _G.C_TradeSkillUI, _G.C_CreatureInfo, _G.C_Spell = nil, nil, nil, nil
_G.COPPER_AMOUNT, _G.SILVER_AMOUNT, _G.GOLD_AMOUNT = nil, nil, nil

suite.done()
