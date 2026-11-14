-- Gathering: herbs and ore.
--
-- What matters: a herb picked or a vein mined is recorded against that node,
-- never a kill and never a mob's drop -- not even with a looted corpse still
-- targeted, which is how herbs used to turn up as a mob's loot; a gather is
-- known only from a Herb Gathering or Mining cast that nothing interrupted, so
-- a corpse looted after a failed or stale cast is still the mob's; skinning
-- stays the mob's, but a corpse first opened by skinning is no harvest
-- sample; loot the client says came from something other than the target is
-- nobody's drop; no percentage before MIN_GATHERS; gathered items count
-- toward the session's value; the panel's Gathering section shows only once
-- you have gathered; the check lists herbs already credited to a mob, even
-- with the measured data loaded, changes nothing, and keeps them out of the
-- export; a reset keeps the map markers; and nothing off the client is
-- touched outside a pcall.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("gathering")

local clock = 500

local ns = env.Load({ ui = true })
local Gathering = ns.Gathering
local Tracker = ns.Tracker
local Harvest = ns.Harvest

_G.GetTime = function() return clock end

local tooltipShown = {}
local tooltip = {}

_G.GameTooltip.HookScript = function(_, script, fn)
    if script == "OnShow" then tooltipShown[#tooltipShown + 1] = fn end
end
_G.GameTooltip.GetUnit = function() return tooltip.unit end
_G.GameTooltip.GetItem = function() return tooltip.item end
_G.GameTooltipTextLeft1 = { GetText = function() return tooltip.text end }

-- Prices, so the session's value has something to add up.
local VENDOR = { [2447] = 10, [2770] = 5, [2835] = 2, [5637] = 50 }
_G.C_Item = {
    GetItemInfo = function(id)
        return "item", nil, 1, 1, 1, "", "", 1, "", "", VENDOR[id] or 0
    end,
}

Harvest:OnEnable()
Tracker:OnEnable()
ns.Fishing:OnEnable()
Gathering:OnEnable()
ns.TrackerUI:OnEnable()

local fire = ns.eventFrame:GetScript("OnEvent")

local HERB_GATHERING, MINING, SKINNING, FROSTBOLT = 2366, 2575, 8613, 116

local PEACEBLOOM = { name = "Peacebloom", id = 2447 }
local COPPER = { name = "Copper Ore", id = 2770 }
local ROUGH = { name = "Rough Stone", id = 2835 }
local FANG = { name = "Large Fang", id = 5637 }
local LEATHER = { name = "Light Leather", id = 2318 }

local casts = 0

--- You start a cast on `target`. Returns its cast guid.
local function Send(spell, target)
    casts = casts + 1
    local id = "Cast-" .. casts
    fire(ns.eventFrame, "UNIT_SPELLCAST_SENT", "player", target, id, spell)
    return id
end

--- A loot window opens on `items` and, unless told otherwise, closes.
local function Open(items, opts)
    opts = opts or {}
    env.world.loot = items
    fire(ns.eventFrame, "LOOT_OPENED")
    if not opts.keepOpen then fire(ns.eventFrame, "LOOT_CLOSED") end
end

--- Pick a herb or mine a vein: the cast, it going through, the loot.
local function Gather(spell, node, items)
    local id = Send(spell, node)
    clock = clock + 2
    fire(ns.eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", id, spell)
    Open(items)
    clock = clock + 1
end

local serial = 0

--- Kill and loot a mob. Returns its guid so it can stay targeted.
local function Kill(name, items, guid)
    serial = serial + 1
    guid = guid or ("Creature-0-1-2-3-4-" .. serial)
    env.world.target = { name = name, level = 8, dead = true, guid = guid }
    Open(items)
    return guid
end

local function Line(left)
    for index, line in ipairs(ns.TrackerUI.shown or {}) do
        if line.left == left then return line, index end
        -- An item on an open card is an icon: its number is its right.
        for _, icon in ipairs(line.icons or {}) do
            if icon.item == left then return { left = icon.item, right = icon.text, icon = icon }, index end
        end
    end
end

local function MobItem(mob, item)
    local tally = ns.db.tracker and ns.db.tracker.mobs[mob]
    return tally and tally.items[item]
end

local function HarvestItem(mob, item)
    for _, record in pairs(Harvest.records) do
        if record.mob == mob and record.items[item] then return record.items[item] end
    end
end

env.world.zone = "Elwynn Forest"
env.world.subZone = "Goldshire"

suite.check("fishing and gathering share one tooltip hook", #tooltipShown == 1, #tooltipShown)
do
    local asks, realGetUnit = 0, _G.GameTooltip.GetUnit
    _G.GameTooltip.GetUnit = function(...) asks = asks + 1 return realGetUnit(...) end
    tooltip.text = "Peacebloom"
    tooltipShown[1](_G.GameTooltip)
    suite.check("which asks whether it shows a unit once per showing", asks == 1, asks)
    suite.check("and still tells gathering the name", Gathering.hovered and Gathering.hovered.name == "Peacebloom")
    _G.GameTooltip.GetUnit = realGetUnit
    tooltip.text, Gathering.hovered = nil, nil
end
suite.check("no Gathering section before you gather", Line("GATHERING") == nil)

--------------------------------------------------------------------------------
-- Picking a herb with nothing targeted
--------------------------------------------------------------------------------

env.world.target = nil
Gather(HERB_GATHERING, "Peacebloom", { PEACEBLOOM })

local BLOOM = Gathering.NodeKey("Elwynn Forest", "Goldshire", "Peacebloom")
local bloom = Gathering:Summary(BLOOM)

suite.check("a herb picked is one gather", bloom and bloom.gathers == 1, bloom and bloom.gathers)
suite.check("named for the node the cast was on", bloom.name == "Peacebloom", bloom.name)
suite.check("in the zone and subzone", bloom.place == "Goldshire, Elwynn Forest", bloom.place)
suite.check("what it gave is counted", bloom.items[1] and bloom.items[1].name == "Peacebloom")
suite.check("with its item id", ns.db.gathering.nodes[BLOOM].items.Peacebloom.id == 2447)
suite.check("and where you stood", type(bloom.node.coords) == "table")
suite.check("a herb is a herb", bloom.node.kind == "herb", bloom.node.kind)
suite.check("it is not a kill", next(Tracker:Store()) == nil)
suite.check("nor a harvested corpse", Harvest:CountCorpses() == 0, Harvest:CountCorpses())
suite.check("the window closing ends the gather", not Gathering:IsGathering())

suite.check("the Gathering section appears once you have gathered", Line("GATHERING") ~= nil)
suite.check("it counts this session's nodes", Line("GATHERING").right == "1 gather",
    Line("GATHERING").right)
suite.check("gathering alone gets the session's total",
    ns.TrackerUI.titleLine and ns.TrackerUI.titleLine.right == ns.Value.Coins(10),
    ns.TrackerUI.titleLine and ns.TrackerUI.titleLine.right)
suite.check("a thin node says how many more",
    Line("19 more for gather rates") ~= nil)

--------------------------------------------------------------------------------
-- The bug: a herb picked beside a corpse you just looted
--------------------------------------------------------------------------------

local wolf = Kill("Mangy Wolf", { FANG })
suite.check("the wolf is one kill", Tracker:Store()["Mangy Wolf"].kills == 1)

-- The corpse is still targeted when you walk over and pick the herb.
Gather(HERB_GATHERING, "Peacebloom", { PEACEBLOOM })

suite.check("the herb is not the wolf's drop in the tally",
    MobItem("Mangy Wolf", "Peacebloom") == nil)
suite.check("nor in the harvest", HarvestItem("Mangy Wolf", "Peacebloom") == nil)
suite.check("nor another kill", Tracker:Store()["Mangy Wolf"].kills == 1)
suite.check("it went to the node", Gathering:Summary(BLOOM).gathers == 2)

-- An untouched corpse targeted is no different.
env.world.target = { name = "Kobold Vermin", level = 3, dead = true, guid = "Creature-0-9" }
Gather(HERB_GATHERING, "Peacebloom", { PEACEBLOOM })
suite.check("picking beside an unlooted corpse is not a kill",
    Tracker:Store()["Kobold Vermin"] == nil)
suite.check("nor that corpse's loot", HarvestItem("Kobold Vermin", "Peacebloom") == nil)


--------------------------------------------------------------------------------
-- Casts that end without a gather
--------------------------------------------------------------------------------

-- Interrupted, then the wolf's corpse looted: that loot is the wolf's.
local id = Send(HERB_GATHERING, "Peacebloom")
fire(ns.eventFrame, "UNIT_SPELLCAST_INTERRUPTED", "player", id, HERB_GATHERING)
Kill("Mangy Wolf", { FANG })
suite.check("after an interrupted gather a corpse is still a kill",
    Tracker:Store()["Mangy Wolf"].kills == 2)
suite.check("and its loot is the mob's", MobItem("Mangy Wolf", "Large Fang") == 2)

id = Send(MINING, "Copper Vein")
fire(ns.eventFrame, "UNIT_SPELLCAST_FAILED", "player", id, MINING)
suite.check("a failed cast is no gather", not Gathering:IsGathering())

-- Another player's failure of the same spell is not yours.
Send(MINING, "Copper Vein")
fire(ns.eventFrame, "UNIT_SPELLCAST_FAILED", "party1", "Cast-other", MINING)
suite.check("someone else's failed cast leaves yours", Gathering:IsGathering())

-- A gather sent long ago cannot claim a corpse looted now.
clock = clock + Gathering.GATHER_SECONDS + 1
suite.check("a stale cast is no gather", not Gathering:IsGathering())
Kill("Mangy Wolf", { FANG })
suite.check("so the corpse after it is a kill", Tracker:Store()["Mangy Wolf"].kills == 3)

-- Another spell of yours ends the gather.
Send(MINING, "Copper Vein")
Send(FROSTBOLT, "Mangy Wolf")
suite.check("casting something else ends it", not Gathering:IsGathering())

--------------------------------------------------------------------------------
-- Skinning stays the mob's (the house rule)
--------------------------------------------------------------------------------

Kill("Mangy Wolf", { FANG }, "Creature-0-skin")
local skinID = Send(SKINNING, "Mangy Wolf")
fire(ns.eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", skinID, SKINNING)
Open({ LEATHER })
suite.check("skinning is not gathering", Gathering:Summary(
    Gathering.NodeKey("Elwynn Forest", "Goldshire", "Mangy Wolf")) == nil)
suite.check("the leather is the wolf's drop", MobItem("Mangy Wolf", "Light Leather") == 1)
suite.check("and the skinned corpse is still one kill", Tracker:Store()["Mangy Wolf"].kills == 4)

--------------------------------------------------------------------------------
-- Mining
--------------------------------------------------------------------------------

env.world.target = nil
Gather(MINING, "Copper Vein", { COPPER, ROUGH })
Gather(MINING, "Copper Vein", { COPPER })

local VEIN = Gathering.NodeKey("Elwynn Forest", "Goldshire", "Copper Vein")
local vein = Gathering:Summary(VEIN)
suite.check("each mining is one gather", vein.gathers == 2, vein.gathers)
suite.check("ore is ore", vein.node.kind == "ore")
suite.check("each item counted over the gathers that held it",
    vein.items[1].name == "Copper Ore" and vein.items[1].gathers == 2
    and vein.items[2].name == "Rough Stone" and vein.items[2].gathers == 1)
suite.check("the panel puts the latest on top",
    select(2, Line("Copper Vein")) < select(2, Line("Peacebloom")))
suite.check("and gathering over the kills, since it was last",
    select(2, Line("GATHERING")) < select(2, Line("THIS SESSION")))
suite.check("the total stays in the title bar, out of the column",
    Line("Gathered value") == nil and ns.TrackerUI.titleLine ~= nil)

-- The session's value: 3 Peacebloom at 10, 2 Copper at 5, 1 Rough Stone at 2,
-- and four Large Fangs at 50 off the wolves.
suite.check("gathered items count toward the session's value",
    ns.Value:Session() == 3 * 10 + 2 * 5 + 2 + 4 * 50, ns.Value:Session())

-- A kill puts the kills back on top.
Kill("Mangy Wolf", {})
suite.check("a kill after it puts the kills on top",
    select(2, Line("THIS SESSION")) < select(2, Line("GATHERING")))

--------------------------------------------------------------------------------
-- A client that will not name the node
--------------------------------------------------------------------------------

env.world.target = nil

-- The cast names nothing; the tooltip showed the herb a moment ago.
tooltip.text = "Silverleaf"
for _, fn in ipairs(tooltipShown) do fn(_G.GameTooltip) end
Gather(HERB_GATHERING, nil, { { name = "Silverleaf", id = 765 } })
suite.check("the node under the mouse names it",
    Gathering:Summary(Gathering.NodeKey("Elwynn Forest", "Goldshire", "Silverleaf")) ~= nil)

-- A mob's tooltip is never a node.
tooltip.text, tooltip.unit = "Mangy Wolf", "mouseover"
for _, fn in ipairs(tooltipShown) do fn(_G.GameTooltip) end
tooltip.unit = nil
Gather(HERB_GATHERING, env.Secret("target"), { PEACEBLOOM })
suite.check("an unreadable target is no error, and a unit is no node name",
    Gathering:Summary(Gathering.NodeKey("Elwynn Forest", "Goldshire", "Herb")) ~= nil)

-- Secret everything: a cast whose every value refuses to be read.
local ok, err = pcall(fire, ns.eventFrame, "UNIT_SPELLCAST_SENT",
    env.Secret("unit"), env.Secret("target"), env.Secret("guid"), env.Secret("spell"))
suite.check("a secret cast raises nothing", ok, err)

--------------------------------------------------------------------------------
-- Loot the client says is not the target's
--------------------------------------------------------------------------------

local sources = {}
_G.GetLootSourceInfo = function(slot) return sources[slot], 1 end

-- A clam opened from the bags with the wolf's corpse targeted.
env.world.target = { name = "Mangy Wolf", level = 8, dead = true, guid = "Creature-0-clam" }
sources = { "Item-0-0-0-77" }
Open({ { name = "Small Lustrous Pearl", id = 5498 } })
suite.check("an item's loot is not the targeted corpse's",
    MobItem("Mangy Wolf", "Small Lustrous Pearl") == nil
    and HarvestItem("Mangy Wolf", "Small Lustrous Pearl") == nil)

-- A chest.
sources = { "GameObject-0-0-0-12" }
Open({ { name = "Brilliant Smallfish", id = 6291 } })
suite.check("a chest's loot is not the corpse's either",
    MobItem("Mangy Wolf", "Brilliant Smallfish") == nil)

-- Another corpse than the one targeted.
sources = { "Creature-0-someone-else" }
local kills = Tracker:Store()["Mangy Wolf"].kills
Open({ FANG })
suite.check("another corpse's loot is not the target's",
    Tracker:Store()["Mangy Wolf"].kills == kills)

-- The target's own loot still counts.
sources = { "Creature-0-clam" }
Open({ FANG })
suite.check("the target's own loot counts", Tracker:Store()["Mangy Wolf"].kills == kills + 1)

-- Guids spelled some other way, or unreadable: judged as before.
env.world.target = { name = "Mangy Wolf", level = 8, dead = true, guid = "Creature-0-odd" }
sources = { "0xF130000000001" }
Open({ FANG })
suite.check("a guid it cannot place leaves the loot the target's",
    Tracker:Store()["Mangy Wolf"].kills == kills + 2)

env.world.target = { name = "Mangy Wolf", level = 8, dead = true, guid = "Creature-0-secret" }
sources = { env.Secret("source") }
Open({ FANG })
suite.check("a secret source leaves it the target's too",
    Tracker:Store()["Mangy Wolf"].kills == kills + 3)

-- Area loot: one window, two corpses. Only the target's slot counts, and
-- only its share of a slot both corpses filled.
env.world.target = { name = "Mangy Wolf", level = 8, dead = true, guid = "Creature-0-area" }
local sourcesOf = {
    { "Creature-0-area", 1 },
    { "Creature-0-other", 3 },
    { "Creature-0-area", 2, "Creature-0-other", 5 },
}
_G.GetLootSourceInfo = function(slot) return unpack(sourcesOf[slot] or {}) end
local function Qty(item) return tonumber(ns.db.tracker.mobs["Mangy Wolf"].qty[item]) or 0 end
local fangsBefore, leatherBefore = Qty("Large Fang"), MobItem("Mangy Wolf", "Light Leather")
Open({ FANG, LEATHER, { name = "Large Fang", id = 5637, quantity = 7 } })
suite.check("area loot: the other corpse's leather is not the target's",
    MobItem("Mangy Wolf", "Light Leather") == leatherBefore, MobItem("Mangy Wolf", "Light Leather"))
suite.check("area loot: only the target's share of a shared slot",
    Qty("Large Fang") == fangsBefore + 3, Qty("Large Fang") - fangsBefore)

-- The coin slot's name holds both corpses' coin; the share is the target's.
sourcesOf = { { "Creature-0-area", 1500, "Creature-0-other", 2300 } }
env.world.loot = { { name = "38 Silver", money = true } }
local _, _, areaCopper = Tracker:LootedItems()
suite.check("area loot: only the target's coin", areaCopper == 1500, areaCopper)

_G.GetLootSourceInfo = nil

--------------------------------------------------------------------------------
-- Rates, and the pause
--------------------------------------------------------------------------------

env.world.target = nil
for _ = 1, Gathering.MIN_GATHERS - 2 do
    Gather(MINING, "Copper Vein", { COPPER })
end
vein = Gathering:Summary(VEIN)
suite.check("rated from MIN_GATHERS", vein.rated and vein.gathers == 20, vein.gathers)
suite.check("with a percentage", vein.items[1].chance == 100, vein.items[1].chance)
suite.check("the rated node shows it", Line("Copper Ore") and Line("Copper Ore").right == "100%",
    Line("Copper Ore") and Line("Copper Ore").right)

ns.db.harvestPaused = true
Gather(MINING, "Copper Vein", { COPPER })
suite.check("paused records nothing", Gathering:Summary(VEIN).gathers == 20)
suite.check("and credits nothing to a mob either", Tracker:Store()["Copper Vein"] == nil)
ns.db.harvestPaused = nil

--------------------------------------------------------------------------------
-- Herbs already credited to a mob
--------------------------------------------------------------------------------

-- As the old code left it: a herb in a mob's tally and harvest record.
local mobs = Tracker:Store()
mobs["Mangy Wolf"].items["Peacebloom"] = 2
local record = Harvest:GetRecord("Mangy Wolf", 8, "Elwynn Forest", "Goldshire")
record.items["Copper Ore"] = { name = "Copper Ore", count = 1, corpses = 1 }

local found = Gathering:Suspects()
suite.check("the check finds both", #found == 2, #found)
suite.check("the tally one", found[1].where == "tally" and found[1].item == "Peacebloom"
    and found[1].times == 2, found[1].item)
suite.check("the harvest one", found[2].where == "harvest" and found[2].item == "Copper Ore")
suite.check("a mob drop is never a suspect", not Gathering.IsNodeOnly("Large Fang"))
suite.check("nor an item mobs drop too", not Gathering.IsNodeOnly("Linen Cloth"))

env.chat = {}
ns.HandleSlash("gathering check")
suite.check("it says so", env.chat[1] and env.chat[1]:find("2 entries", 1, true), env.chat[1])
suite.check("and changes nothing", mobs["Mangy Wolf"].items["Peacebloom"] == 2
    and record.items["Copper Ore"] ~= nil)

-- Nor does it go into the data: herbs and ore count per node, never as a
-- mob's drop. What the mob does drop still goes.
local exported = Harvest:ExportAll()
suite.check("the export leaves the ore out",
    exported:find('name = "Copper Ore"', 1, true) == nil)
suite.check("and keeps the mob's own drop",
    exported:find('name = "Large Fang"', 1, true) ~= nil)

-- Asked for by name, the ore stays out too.
env.chat = {}
local exportShown
local ShowExport = ns.UI.ShowExport
ns.UI.ShowExport = function(_, text) exportShown = text end
ns.HandleSlash("export copper ore")
ns.UI.ShowExport = ShowExport
suite.check("/farm export of an ore opens no window", exportShown == nil, exportShown)
suite.check("and says why", env.chat[1] and env.chat[1]:find("comes from nodes", 1, true) ~= nil,
    env.chat[1])

mobs["Mangy Wolf"].items["Peacebloom"] = nil
record.items["Copper Ore"] = nil
env.chat = {}
ns.HandleSlash("gathering check")
suite.check("clean data says it is clean",
    env.chat[1] and env.chat[1]:find("clean", 1, true), env.chat[1])

--------------------------------------------------------------------------------
-- The command, and reset
--------------------------------------------------------------------------------

env.chat = {}
ns.HandleSlash("gathering")
suite.check("/farm gathering lists this zone's nodes",
    env.chat[1] and env.chat[1]:find("gathered in Elwynn Forest", 1, true), env.chat[1])

local before = Gathering:CountGathers()
local markers = #Gathering:Spots()
env.chat = {}
ns.HandleSlash("gathering reset")
suite.check("reset asks first", Gathering:CountGathers() == before)
suite.check("and says the map markers stay",
    env.chat[1] and env.chat[1]:find("map markers stay", 1, true) ~= nil, env.chat[1])
ns.HandleSlash("gathering reset confirm")
suite.check("a confirmed reset clears it", Gathering:CountGathers() == 0)
suite.check("and leaves the kills alone", Tracker:Store()["Mangy Wolf"].kills > 0)
-- The markers have their own clear (/farm markers clear confirm).
suite.check("and the map markers", markers > 0 and #Gathering:Spots() == markers,
    markers .. " before, " .. #Gathering:Spots() .. " after")

-- The client naming the node as the loot's source, with a corpse targeted:
-- the herb is still the node's (the corpse check is for kills only).
env.world.target = { name = "Kobold Vermin", level = 3, dead = true, guid = "Creature-0-9" }
_G.GetLootSourceInfo = function() return "GameObject-0-1-2-3-99", 1 end
Gather(HERB_GATHERING, "Peacebloom", { PEACEBLOOM })
_G.GetLootSourceInfo = nil
local sourced = Gathering:Summary(BLOOM)
suite.check("a node's own loot counts with a corpse targeted",
    sourced and sourced.gathers == 1 and sourced.items[1] and sourced.items[1].name == "Peacebloom")

--------------------------------------------------------------------------------
-- Skinning, told apart
--
-- Never a gather, but the harvester and the kill tally need to know a loot
-- window is a skin's: IsSkinning is true from your own Skinning cast until
-- its window closes, it fails or is interrupted, or GATHER_SECONDS pass.
--------------------------------------------------------------------------------

suite.check("every rank of Skinning is skinning", Gathering.IsSkinningSpell(8613)
    and Gathering.IsSkinningSpell(8617) and Gathering.IsSkinningSpell(8618)
    and Gathering.IsSkinningSpell(10768))
suite.check("a gather is not", not Gathering.IsSkinningSpell(HERB_GATHERING))
suite.check("nor a secret spell, and it raises nothing",
    not Gathering.IsSkinningSpell(env.Secret("spell")))

-- A client whose ids differ: known by name.
local realSpell = _G.C_Spell
_G.C_Spell = { GetSpellName = function(spell) return spell == 194174 and "Skinning" or nil end }
suite.check("known by name where the id differs", Gathering.IsSkinningSpell(194174))
_G.C_Spell = realSpell

env.world.target = nil
suite.check("no skin, no skinning", not Gathering:IsSkinning())

fire(ns.eventFrame, "UNIT_SPELLCAST_SENT", "party1", "Mangy Wolf", "Cast-party", SKINNING)
suite.check("someone else's skin is not yours", not Gathering:IsSkinning())

local skin = Send(SKINNING, "Mangy Wolf")
suite.check("a skin sent is skinning", Gathering:IsSkinning())
suite.check("and no gather", not Gathering:IsGathering())

-- The window you had open shuts as the skin begins: it is not the skin's.
fire(ns.eventFrame, "LOOT_CLOSED")
suite.check("a window closing before the skin's own leaves it", Gathering:IsSkinning())

fire(ns.eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", skin, SKINNING)
suite.check("still skinning once it goes through", Gathering:IsSkinning())
Open({ LEATHER }, { keepOpen = true })
suite.check("and while its window is open", Gathering:IsSkinning())
fire(ns.eventFrame, "LOOT_CLOSED")
suite.check("over when its window closes", not Gathering:IsSkinning())

-- A client that says the cast went through only once its window is open.
skin = Send(SKINNING, "Mangy Wolf")
Open({ LEATHER }, { keepOpen = true })
fire(ns.eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", skin, SKINNING)
fire(ns.eventFrame, "LOOT_CLOSED")
suite.check("a late word that it went through does not outlast its window",
    not Gathering:IsSkinning())

skin = Send(SKINNING, "Mangy Wolf")
fire(ns.eventFrame, "UNIT_SPELLCAST_FAILED", "player", skin, SKINNING)
suite.check("a failed skin is over", not Gathering:IsSkinning())

skin = Send(SKINNING, "Mangy Wolf")
fire(ns.eventFrame, "UNIT_SPELLCAST_INTERRUPTED", "player", skin, SKINNING)
suite.check("so is an interrupted one", not Gathering:IsSkinning())

skin = Send(SKINNING, "Mangy Wolf")
fire(ns.eventFrame, "UNIT_SPELLCAST_FAILED", "player", "Cast-other", FROSTBOLT)
suite.check("another spell failing is not the skin failing", Gathering:IsSkinning())
fire(ns.eventFrame, "UNIT_SPELLCAST_FAILED", "party1", skin, SKINNING)
suite.check("nor is someone else's", Gathering:IsSkinning())
clock = clock + Gathering.GATHER_SECONDS + 1
suite.check("a skin from long ago is over", not Gathering:IsSkinning())

-- Cast guids the client will not hand over: told apart by the spell.
fire(ns.eventFrame, "UNIT_SPELLCAST_SENT", "player", "Mangy Wolf", env.Secret("guid"), SKINNING)
fire(ns.eventFrame, "UNIT_SPELLCAST_FAILED", "player", env.Secret("guid"), FROSTBOLT)
suite.check("without guids another spell failing is still not the skin", Gathering:IsSkinning())
fire(ns.eventFrame, "UNIT_SPELLCAST_FAILED", "player", env.Secret("guid"), SKINNING)
suite.check("but the skin failing is", not Gathering:IsSkinning())

-- A client that only says the cast went through.
casts = casts + 1
fire(ns.eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. casts, SKINNING)
suite.check("a skin seen only going through counts", Gathering:IsSkinning())
Open({ LEATHER })
suite.check("and ends with its window", not Gathering:IsSkinning())

--------------------------------------------------------------------------------
-- A corpse first opened by skinning is no harvest sample
--
-- Its drops were never in your window: another player took them, an area
-- loot took them with another corpse's, or you looted it before a /reload
-- made the harvester forget it. Counting it would add a corpse that held
-- nothing and pull every other rate down.
--------------------------------------------------------------------------------

local function Skin(guid, name, items)
    env.world.target = { name = name, level = 7, dead = true, guid = guid }
    local id = Send(SKINNING, name)
    clock = clock + 2
    fire(ns.eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", id, SKINNING)
    Open(items)
    clock = clock + 1
end

local function HarvestRecord(mob)
    for _, entry in pairs(Harvest.records) do
        if entry.mob == mob then return entry end
    end
end

-- Another player's kill, looted by them: you only skin it.
local skipped = Harvest.skipped or 0
Skin("Creature-0-theirs", "Timber Wolf", { LEATHER })
suite.check("someone else's kill you only skinned is no corpse",
    HarvestRecord("Timber Wolf") == nil)
suite.check("it is counted as skipped", (Harvest.skipped or 0) == skipped + 1)

-- Area loot: two wolves, one window holding a fang from each. Only the one
-- you clicked is counted, with its own fang. Then you skin both.
local WOLF_A, WOLF_B = "Creature-0-area-a", "Creature-0-area-b"
local shares = { { WOLF_A, 1, WOLF_B, 1 } }
_G.GetLootSourceInfo = function(slot) return unpack(shares[slot] or {}) end
env.world.target = { name = "Timber Wolf", level = 7, dead = true, guid = WOLF_A }
Open({ { name = "Large Fang", id = 5637, quantity = 2 } })
shares = { { WOLF_A, 1 } }
Skin(WOLF_A, "Timber Wolf", { LEATHER })
shares = { { WOLF_B, 1 } }
Skin(WOLF_B, "Timber Wolf", { LEATHER })
_G.GetLootSourceInfo = nil

local timber = HarvestRecord("Timber Wolf")
suite.check("a corpse the area loot emptied is not counted when skinned",
    timber and timber.corpses == 1, timber and timber.corpses)
suite.check("so every corpse still held its fang",
    timber and timber.items["Large Fang"] and timber.items["Large Fang"].corpses == 1)
suite.check("and the leather off the one you looted counts",
    timber and timber.items["Light Leather"] and timber.items["Light Leather"].corpses == 1)

-- Looted, then a /reload forgets the corpse, then skinned.
env.world.target = { name = "Timber Wolf", level = 7, dead = true, guid = "Creature-0-reload" }
Open({ { name = "Large Fang", id = 5637 } })
Harvest.opened = {}
Skin("Creature-0-reload", "Timber Wolf", { LEATHER })
suite.check("a corpse skinned after a /reload is not counted twice",
    timber and timber.corpses == 2, timber and timber.corpses)

--------------------------------------------------------------------------------
-- The same check with the measured data loaded, as in game
--
-- Data/Data_Harvested.lua adds "forever" rows to every item it measured. A
-- herb an import once credited to a mob must not vouch for itself there:
-- 0.13.0 shipped Peacebloom and Silverleaf as Cursed Darkhound drops, and
-- with them loaded the check said the data was clean.
--------------------------------------------------------------------------------

if env.HasHarvested() then
    local live = env.Load({ harvested = true })

    local credited = {}
    for item in live.DB:Iterate() do
        if item.category == "Herbalism" or item.category == "Mining" then
            for _, source in ipairs(item.sources) do
                if source.provenance == "forever" and live.DB.KindOf(source) == "mob" then
                    credited[#credited + 1] = item.name .. " on " .. tostring(source.name)
                end
            end
        end
    end
    suite.check("no herb or ore in the measured data is a mob's drop",
        #credited == 0, table.concat(credited, ", "))

    -- An import that kept one, the way 0.13.0's did.
    live.DB:RegisterItem({ name = "Silverleaf", sources = {
        { name = "Cursed Darkhound", zone = "Tirisfal Glades", minLevel = 7, maxLevel = 8,
            chance = 3, provenance = "forever" },
    } })
    suite.check("a measured mob row does not make a herb a mob's drop",
        live.Gathering.IsNodeOnly("Silverleaf"))

    local hound = live.Harvest:GetRecord("Cursed Darkhound", 7, "Tirisfal Glades", nil)
    hound.corpses = 33
    hound.items["Silverleaf"] = { name = "Silverleaf", count = 1, corpses = 1 }
    hound.items["Linen Cloth"] = { name = "Linen Cloth", count = 9, corpses = 8 }

    env.chat = {}
    live.HandleSlash("gathering check")
    suite.check("so the check still lists it",
        env.chat[1] and env.chat[1]:find("1 entry", 1, true) ~= nil, env.chat[1])

    local data = live.Harvest:ExportAll()
    suite.check("and the export leaves it out",
        data:find('name = "Silverleaf"', 1, true) == nil)
    suite.check("but keeps what the mob does drop",
        data:find('name = "Linen Cloth"', 1, true) ~= nil)
end

suite.done()
