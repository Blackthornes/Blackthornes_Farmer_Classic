-- Hide skinning: drops only.
--
-- What matters: on by default (the owner asked), so a new player sees drops
-- only; while it is on, the search, Rankings' worth, the Grind tab, a mob's drops and
-- the tooltip line leave out every skinning spot and every item that comes
-- from skinning; nothing recorded is touched, so ticking it again puts it
-- all back when it is turned off; and the command and the Settings box
-- write the same setting.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("showskinning")

local ns = env.Load({ ui = true, hideSkinning = true })
local DB, Search, Tracker, Value = ns.DB, ns.Search, ns.Tracker, ns.Value

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

_G.C_Item = { GetItemInfo = function() return "item", nil, 1, 1, 1, "", "", 1, "", "", 10 end }

local function Names(results)
    local names = {}
    for _, result in ipairs(results) do names[result.item.name] = true end
    return names
end

local function AnySkinning(results)
    for _, result in ipairs(results) do
        if DB:FromSkinning(result.item) then return true end
        for _, source in ipairs(result.sources or result.item.sources) do
            if source.kind == "skinning" then return true end
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Left out from the start, then shown
--------------------------------------------------------------------------------

suite.check("skinning is left out by default", not DB:ShowsSkinning())
suite.check("saved as Hide skinning on", ns.db.hideSkinning == true and ns.DEFAULTS.hideSkinning == true)
suite.check("a fresh leather search still finds it", Names(Search:Run("light leather"))["Light Leather"])

ns.HandleSlash("skinning on")
suite.check("/farm skinning on shows it", DB:ShowsSkinning() and ns.db.hideSkinning == false)
suite.check("leather comes from skinning", DB:FromSkinning("Light Leather"))
suite.check("so do scraps", DB:FromSkinning("Ruined Leather Scraps"))
suite.check("cloth does not", not DB:FromSkinning("Linen Cloth"))
suite.check("nothing is hidden while it is on", not DB:HidesItem("Light Leather"))

suite.check("a search finds leather", Names(Search:Run("light leather"))["Light Leather"])
suite.check("Durotar turns up skinning", AnySkinning(Search:Run("durotar")))

-- Your own wolves, looted and skinned: a fang and leather each.
local serial = 0
local function Kill(mob, items)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, guid = "Creature-0-1-2-3-99-" .. serial }
    env.world.loot = items
    Tracker:OnLoot()
end
for _ = 1, 20 do
    Kill("Mangy Wolf", { { name = "Large Fang" }, { name = "Light Leather" } })
end

local function DropNames(mob)
    local names = {}
    for _, item in ipairs(Tracker:Summary(mob).items) do names[item.name] = true end
    return names
end

suite.check("the wolf's drops have the leather", DropNames("Mangy Wolf")["Light Leather"])
local before = Value:FromTally("Mangy Wolf")
suite.check("and its worth counts it", before and before > 0, before)

--------------------------------------------------------------------------------
-- Drops only
--------------------------------------------------------------------------------

local redrawn = 0
DB.hideWatchers.test = function() redrawn = redrawn + 1 end

ns.HandleSlash("skinning")
suite.check("/farm skinning leaves it out", not DB:ShowsSkinning())
suite.check("saved as Hide skinning on", ns.db.hideSkinning == true)
suite.check("what lists it is redrawn", redrawn == 1, redrawn)

-- The search always finds skinning (the owner, 2026-10-15): hiding it only
-- keeps it out of a mob's worth and the other lists.
suite.check("a leather search still finds it", Names(Search:Run("light leather"))["Light Leather"])
local durotar = Search:Run("durotar")
suite.check("Durotar still turns up skinning", AnySkinning(durotar))
suite.check("but still turns up drops", #durotar > 0, #durotar)
suite.check("cloth is still found", Names(Search:Run("linen"))["Linen Cloth"])

local rows = Search:BuildRows("leather")
local leatherRow = false
for _, row in ipairs(rows) do
    if row.type == "item" and DB:FromSkinning(row.item) then leatherRow = true end
end
suite.check("the window's rows still have leather", leatherRow)

local kinds = Search:KindsInResults("durotar")
local skinChip = false
for _, kind in ipairs(kinds) do if kind == "skinning" then skinChip = true end end
suite.check("and a Skinning chip", skinChip)

local skinSource = false
for _, entries in pairs(DB:ByName()) do
    for _, source in ipairs(entries) do
        if source.kind == "skinning" or DB:FromSkinning(DB:ItemOf(source)) then skinSource = true end
    end
end
suite.check("the mob index Rankings reads has no skinning", not skinSource)

suite.check("the wolf's drops leave the leather out", not DropNames("Mangy Wolf")["Light Leather"])
suite.check("but keep its fang", DropNames("Mangy Wolf")["Large Fang"])
local after, details = Value:FromTally("Mangy Wolf")
suite.check("its worth leaves the leather out", after and after < before, after)
local listed = false
for _, entry in ipairs(details.priced) do if entry.name == "Light Leather" then listed = true end end
for _, name in ipairs(details.unpriced) do if name == "Light Leather" then listed = true end end
suite.check("and does not list it", not listed)

suite.check("the tally itself is untouched",
    Tracker:Store()["Mangy Wolf"].items["Light Leather"] == 20)

ns.db.grindGives = "skinning"
suite.check("a picked Skinning chip on Grind lets go", ns.Grinding:Gives() == nil)
local leatherDrop, skinMob = false, false
for _, mob in pairs(ns.Grinding:Mobs().all) do
    if mob.skinning then skinMob = true end
    for name in pairs(mob.drops) do
        if DB:FromSkinning(name) then leatherDrop = true end
    end
end
suite.check("no camp is there for skinning", not skinMob)
suite.check("no mob's drops on Grind are leather", not leatherDrop)

local leather = DB:GetItem("Light Leather")
suite.check("leather's tooltip says nothing", ns.ItemTooltip:LineFor(leather, ns.Spots:Player()) == nil)

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

ns.SettingsUI:Show()
local box = ns.SettingsUI.controls.hideSkinning
suite.check("the Hide skinning box is ticked", box:GetChecked() == true)
box:GetScript("OnClick")(box)
suite.check("unticking it shows skinning again", DB:ShowsSkinning() and ns.db.hideSkinning == false)
suite.check("Grind's Skinning comes back", ns.Grinding:Gives() == "skinning")
ns.SettingsUI:Hide()

suite.check("leather is found again", Names(Search:Run("light leather"))["Light Leather"])
suite.check("the wolf's leather is back", DropNames("Mangy Wolf")["Light Leather"])
suite.check("and its worth", Value:FromTally("Mangy Wolf") == before)

ns.HandleSlash("skinning off")
suite.check("/farm skinning off", not DB:ShowsSkinning())
ns.HandleSlash("skinning off")
suite.check("says off twice, stays off", not DB:ShowsSkinning())
ns.HandleSlash("skinning on")
suite.check("/farm skinning on", DB:ShowsSkinning())

-- Every redraw runs clean, with the windows built and a search shown.
ns.UI:Show()
ns.UI:Search("leather")
ns.UI.filterKind = "skinning"
for name, redraw in pairs(DB.hideWatchers) do
    local ok, err = pcall(redraw)
    suite.check("the " .. name .. " redraw runs", ok, err)
end
DB:SetShowSkinning(false)
suite.check("a picked Skinning chip in the search stays", ns.UI.filterKind == "skinning")
DB:SetShowSkinning(true)
ns.UI:Hide()

--------------------------------------------------------------------------------
-- The session, and skins the data does not know
--------------------------------------------------------------------------------

-- A wolf looted, then skinned for a hide the data has never heard of.
local realSkinning = ns.Gathering.IsSkinning
local skinningNow = false
ns.Gathering.IsSkinning = function() return skinningNow end
serial = serial + 1
local guid = "Creature-0-1-2-3-99-" .. serial
env.world.target = { name = "Mangy Wolf", level = 8, dead = true, guid = guid }
env.world.loot = { { name = "Large Fang" } }
Tracker:OnLoot()
skinningNow = true
env.world.loot = { { name = "Forever Wolf Hide" } }
Tracker:OnLoot()
skinningNow = false
ns.Gathering.IsSkinning = realSkinning

suite.check("the data does not know the hide", DB:GetItem("Forever Wolf Hide") == nil)
suite.check("a skin notes what it gave", DB:WasSkinned("Forever Wolf Hide")
    and DB:FromSkinning("Forever Wolf Hide"))
suite.check("a looted fang is not noted", not DB:WasSkinned("Large Fang"))

local function OnLootTab(name)
    for _, entry in ipairs(ns.TrackerUI:SessionItems()) do
        if entry.name == name then return true end
    end
    return false
end
local function SessionNames()
    local names = {}
    for _, entry in ipairs(Tracker:SessionLoot()) do names[entry.name] = true end
    return names
end

local shownWorth = Value:Session()
local _, shownLooted = ns.TrackerUI:TabCounts()
suite.check("shown, the Loot tab has the leather and the hide",
    OnLootTab("Light Leather") and OnLootTab("Forever Wolf Hide"))

redrawn = 0
DB:SetShowSkinning(false)
suite.check("hidden, the Loot tab leaves out the leather", not OnLootTab("Light Leather"))
suite.check("and the hide the data did not know", not OnLootTab("Forever Wolf Hide"))
suite.check("but keeps the fang", OnLootTab("Large Fang"))
suite.check("the session's loot leaves them out",
    not SessionNames()["Light Leather"] and not SessionNames()["Forever Wolf Hide"]
    and SessionNames()["Large Fang"])
local hiddenWorth, hiddenDetails = Value:Session()
suite.check("the session's worth leaves the leather out", hiddenWorth < shownWorth,
    tostring(hiddenWorth) .. " < " .. tostring(shownWorth))
local unpricedHide = false
for _, name in ipairs(hiddenDetails.unpriced) do
    if name == "Forever Wolf Hide" then unpricedHide = true end
end
suite.check("and does not list the hide as unpriced", not unpricedHide)
local _, hiddenLooted = ns.TrackerUI:TabCounts()
suite.check("the looted count leaves them out", hiddenLooted == shownLooted - 21,
    hiddenLooted .. " of " .. shownLooted)
suite.check("a mob's loot worth leaves the leather out",
    ns.TrackerUI:MobLootValue("Mangy Wolf") < shownWorth)
suite.check("the session's counts are untouched", Tracker.sessionLoot["Light Leather"] == 20
    and Tracker.sessionLoot["Forever Wolf Hide"] == 1)
suite.check("the hide's tally is untouched", Tracker:Store()["Mangy Wolf"].items["Forever Wolf Hide"] == 1)
suite.check("nor among the wolf's drops", not DropNames("Mangy Wolf")["Forever Wolf Hide"])

DB:SetShowSkinning(true)
suite.check("shown again, it all comes back", OnLootTab("Forever Wolf Hide")
    and Value:Session() == shownWorth)

-- A new skin while hidden redraws what shows it, once.
DB:SetShowSkinning(false)
redrawn = 0
DB:NoteSkinned({ "Forever Bear Hide" })
suite.check("a new skin while hidden redraws", redrawn == 1, redrawn)
DB:NoteSkinned({ "Forever Bear Hide" })
suite.check("one already noted does not", redrawn == 1, redrawn)
DB:SetShowSkinning(true)

DB.hideWatchers.test = nil
ns.db.grindGives = nil

return suite
