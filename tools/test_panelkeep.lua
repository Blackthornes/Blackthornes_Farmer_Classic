-- The kills and loot panel kept between sessions (2026-10-11), a choice
-- since 2026-10-13: by default each session starts empty, every tally kept.
--
-- What matters: a /reload or a relog brings back what the panel showed, for
-- the character that did it and no other; the lifetime tallies are not
-- counted twice; gold per hour goes on from where it stopped; a character
-- whose GUID the client will not read keeps and gets nothing; a bad save is
-- read safely; and Clear panel empties the view alone, after a second click,
-- with every tally, and the corpses already opened, still known.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("panelkeep")

local clock = 1000
local serial = 0

--- One session: the addon loaded with `saved` as the account save, logged
--- in as `name`.
local function Login(saved, name)
    local ns = env.Load({ ui = true })
    _G.GetTime = function() return clock end
    _G.UnitName = function(unit)
        if unit ~= "target" then return name or "Blackthornes" end
        return env.world.target and env.world.target.name or nil
    end
    _G.BlackthornesFarmerDB = saved
    ns.LoadSavedVariables()
    for _, module in ipairs(ns.moduleOrder) do
        if module.OnEnable then module:OnEnable() end
    end
    return ns
end

local function Fire(ns, event)
    ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, event)
end

local function Loot(ns, mob, items, guid)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, guid = guid or ("K-" .. serial) }
    env.world.loot = items or {}
    ns.Tracker:OnLoot()
end

local LINEN = { name = "Linen Cloth", id = 2589, quantity = 2 }
local MEAT = { name = "Stringy Wolf Meat", id = 2672 }

--------------------------------------------------------------------------------
-- By default each session starts empty
--------------------------------------------------------------------------------

local me = "Player-1-Blackthornes"
local ns = Login(nil)
local Tracker = ns.Tracker

suite.check("keeping the panel is off by default", not ns.Session.KeepOn())
Loot(ns, "Mangy Wolf", { MEAT })
Loot(ns, "Mangy Wolf", { MEAT, LINEN })
local fresh = _G.BlackthornesFarmerDB
Fire(ns, "PLAYER_LOGOUT")
suite.check("logging out writes no run", fresh.panelSessions == nil or fresh.panelSessions[me] == nil)

ns = Login(fresh)
suite.check("after a reload the panel starts empty", next(ns.Tracker.session) == nil
    and next(ns.Tracker.sessionLoot) == nil)
suite.check("but the lifetime tally is kept", ns.Tracker:Store()["Mangy Wolf"].kills == 2)

-- A run kept earlier, while the box was ticked, is neither read nor removed.
local old = { tracker = { session = { ["Defias Thug"] = 4 }, clock = 1, recent = { ["Defias Thug"] = 1 } } }
fresh.panelSessions = { [me] = old }
ns = Login(fresh)
suite.check("a run saved earlier is not put back", next(ns.Tracker.session) == nil)
Fire(ns, "PLAYER_LOGOUT")
suite.check("and is left in the save", fresh.panelSessions[me] == old)

ns.HandleSlash("tracker keep on")
suite.check("/farm tracker keep on turns it on", ns.db.keepPanel == true and ns.Session.KeepOn())
ns.HandleSlash("tracker keep off")
suite.check("/farm tracker keep off turns it off", ns.db.keepPanel == false)
ns.HandleSlash("tracker keep")
suite.check("/farm tracker keep flips it", ns.db.keepPanel == true)

--------------------------------------------------------------------------------
-- A session, then a reload, with the panel kept
--------------------------------------------------------------------------------

ns = Login(nil)
ns.db.keepPanel = true
Tracker = ns.Tracker

suite.check("a new character starts empty", next(Tracker.session) == nil)

Loot(ns, "Mangy Wolf", { MEAT })
Loot(ns, "Mangy Wolf", { MEAT, LINEN })
Loot(ns, "Defias Thug", { LINEN }, "kept-corpse")
Tracker.sessionCopper = 125
Tracker.bestStreak = 3
ns.Fishing:Record("Elwynn Forest", "Crystal Lake", nil, { "Raw Brilliant Smallfish" }, { ["Raw Brilliant Smallfish"] = 1 })
ns.Gathering:Record("Elwynn Forest", "Fargodeep Mine", "Copper Vein", "mining", { "Copper Ore" }, { ["Copper Ore"] = 2 })
ns.TrackerUI.startedAt = clock
clock = clock + 600

local lifetimeWolf = Tracker:Store()["Mangy Wolf"].kills
suite.check("the session counted", Tracker.session["Mangy Wolf"] == 2 and lifetimeWolf == 2)

Fire(ns, "PLAYER_LOGOUT")
local save = _G.BlackthornesFarmerDB
local kept = save.panelSessions and save.panelSessions[me]
suite.check("logging out keeps the panel under the character's GUID", type(kept) == "table")
suite.check("with the kills", kept.tracker.session["Mangy Wolf"] == 2)
suite.check("and how long the run was timed", kept.played == 600, kept.played)
suite.check("never the corpses opened", kept.tracker.corpses == nil)

-- A /reload: a fresh Lua state reading the same save.
clock = clock + 5
ns = Login(save)
Tracker = ns.Tracker

suite.check("the kills are back after a reload", Tracker.session["Mangy Wolf"] == 2
    and Tracker.session["Defias Thug"] == 1)
suite.check("the loot is back", Tracker.sessionLoot["Linen Cloth"] == 4, Tracker.sessionLoot["Linen Cloth"])
suite.check("where it came from is back",
    Tracker.sessionFrom["Linen Cloth"]["Defias Thug"] == 2)
suite.check("the coin is back", Tracker.sessionCopper == 125)
suite.check("the best streak is back", Tracker.bestStreak == 3)
suite.check("the last mob is the one on top", Tracker.current == "Defias Thug")
suite.check("fishing is back", ns.Fishing.sessionCasts == 1
    and ns.Fishing.sessionCatch["Raw Brilliant Smallfish"] == 1)
suite.check("gathering is back", ns.Gathering.sessionGathers == 1
    and ns.Gathering.sessionItems["Copper Ore"] == 2)
suite.check("what was done last is back", ns.lastLoot == "gathering", ns.lastLoot)
suite.check("the lifetime tally is not counted twice",
    Tracker:Store()["Mangy Wolf"].kills == lifetimeWolf)
suite.check("the per-hour clock goes on from where it stopped",
    ns.TrackerUI.startedAt == clock - 600, ns.TrackerUI.startedAt)

local mobs = Tracker:SessionMobs()
suite.check("the order is kept", mobs[1].mob == "Defias Thug" and mobs[2].mob == "Mangy Wolf")

Loot(ns, "Mangy Wolf", { MEAT })
mobs = Tracker:SessionMobs()
suite.check("a new kill adds to the kept run", Tracker.session["Mangy Wolf"] == 3)
suite.check("and goes on top", mobs[1].mob == "Mangy Wolf")

local saved = save.panelSessions[me]
suite.check("logging in again changes nothing in the save before logout",
    saved.tracker.session["Mangy Wolf"] == 2)

Fire(ns, "PLAYER_LOGOUT")
suite.check("the next logout keeps the new total",
    save.panelSessions[me].tracker.session["Mangy Wolf"] == 3)

--------------------------------------------------------------------------------
-- Another character
--------------------------------------------------------------------------------

ns = Login(save, "Otheralt")
suite.check("another character's panel starts empty", next(ns.Tracker.session) == nil)
suite.check("and leaves the first one's alone", save.panelSessions[me] ~= nil)
Fire(ns, "PLAYER_LOGOUT")
suite.check("an empty panel saves nothing", save.panelSessions["Player-1-Otheralt"] == nil)
suite.check("the first character's run is still there",
    save.panelSessions[me].tracker.session["Mangy Wolf"] == 3)

--------------------------------------------------------------------------------
-- No GUID: not sure who is playing
--------------------------------------------------------------------------------

local realGUID = _G.UnitGUID
ns = env.Load({ ui = true })
_G.GetTime = function() return clock end
_G.UnitGUID = function(unit) if unit == "player" then return nil end return realGUID(unit) end
_G.BlackthornesFarmerDB = save
ns.LoadSavedVariables()
for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end
suite.check("without a GUID nothing is put back", next(ns.Tracker.session) == nil)
Loot(ns, "Kobold Vermin", { LINEN })
Fire(ns, "PLAYER_LOGOUT")
suite.check("and nothing is written over", save.panelSessions[me].tracker.session["Kobold Vermin"] == nil
    and save.panelSessions[me].tracker.session["Mangy Wolf"] == 3)

-- The next loading screen reads it: the kept run joins what was done since.
_G.UnitGUID = realGUID
Fire(ns, "PLAYER_ENTERING_WORLD")
suite.check("once the GUID can be read the run comes back",
    ns.Tracker.session["Mangy Wolf"] == 3 and ns.Tracker.session["Kobold Vermin"] == 1)
suite.check("what was done meanwhile stays on top", ns.Tracker:SessionMobs()[1].mob == "Kobold Vermin")
Fire(ns, "PLAYER_ENTERING_WORLD")
suite.check("and only once", ns.Tracker.session["Mangy Wolf"] == 3)

--------------------------------------------------------------------------------
-- A bad save
--------------------------------------------------------------------------------

local bad = { keepPanel = true, panelSessions = { [me] = {
    played = "lots",
    lastLoot = "dancing",
    tracker = {
        session = { ["Mangy Wolf"] = 2, ["Bad"] = -4, [7] = 1, ["Nan"] = 0 / 0, ["Huge"] = math.huge },
        sessionLoot = "not a table",
        sessionFrom = { ["Linen Cloth"] = "nope", ["Meat"] = { Wolf = 1 } },
        recent = { ["Mangy Wolf"] = 2 },
        sessionCopper = "a lot",
        clock = 2,
        current = { "table" },
    },
    fishing = 12,
} } }
local ok, err = pcall(Login, bad)
suite.check("a bad save loads without an error", ok, err)
ns = env.ns
suite.check("its good counts are read", ns.Tracker.session["Mangy Wolf"] == 2)
suite.check("its bad ones are left out", ns.Tracker.session["Bad"] == nil
    and ns.Tracker.session[7] == nil and ns.Tracker.session["Nan"] == nil
    and ns.Tracker.session["Huge"] == nil)
suite.check("a bad number counts as none", ns.Tracker.sessionCopper == 0)
suite.check("a bad last loot is not taken", ns.lastLoot == nil)
suite.check("a bad per-hour time is not taken", ns.TrackerUI.startedAt == nil)
suite.check("nested counts are checked too", ns.Tracker.sessionFrom["Meat"].Wolf == 1
    and ns.Tracker.sessionFrom["Linen Cloth"] ~= "nope")

--------------------------------------------------------------------------------
-- Clear panel
--------------------------------------------------------------------------------

ns = Login(save)
Tracker = ns.Tracker
local wolfKills = Tracker:Store()["Mangy Wolf"].kills
suite.check("the kept run is shown", Tracker.session["Mangy Wolf"] == 3)

local clear = ns.TrackerUI.toolbar and ns.TrackerUI.toolbar.clear
if not clear then
    ns.TrackerUI:Refresh()
    clear = ns.TrackerUI.toolbar and ns.TrackerUI.toolbar.clear
end
suite.check("the panel has a Clear button", clear ~= nil)

clear:GetScript("OnClick")(clear)
suite.check("one click only asks", Tracker.session["Mangy Wolf"] == 3 and clear.armed == true)
suite.check("and says so", clear.label:GetText() == "Click Again")

clock = clock + 10
clear:GetScript("OnClick")(clear)
suite.check("a late second click asks again", Tracker.session["Mangy Wolf"] == 3 and clear.armed == true)

clock = clock + 1
clear:GetScript("OnClick")(clear)
suite.check("a second click clears the panel", next(Tracker.session) == nil
    and next(Tracker.sessionLoot) == nil and Tracker.sessionCopper == 0)
suite.check("fishing and gathering too", ns.Fishing.sessionCasts == 0
    and next(ns.Gathering.sessionItems) == nil)
suite.check("the button reads Clear again", clear.label:GetText() == "Clear" and clear.armed == false)
suite.check("the lifetime tally stays", Tracker:Store()["Mangy Wolf"].kills == wolfKills)
suite.check("the per-hour clock stops", ns.TrackerUI.startedAt == nil)
suite.check("the kept run is gone from the save", save.panelSessions[me] == nil)
suite.check("fishing and gathering records stay", ns.Fishing:CountCasts() == 1
    and ns.Gathering:Store()[next(ns.Gathering:Store())] ~= nil)

-- A corpse opened before the clear, opened again: still the same kill.
Loot(ns, "Defias Thug", { LINEN }, "again")
local thug = Tracker:Store()["Defias Thug"].kills
Loot(ns, "Defias Thug", { LINEN }, "again")
suite.check("a corpse opened again is still no new kill", Tracker:Store()["Defias Thug"].kills == thug)

ns.HandleSlash("tracker clear")
suite.check("/farm tracker clear empties it", next(Tracker.session) == nil)
suite.check("and says the tallies are kept", env.chat[#env.chat]:find("kept") ~= nil)

Fire(ns, "PLAYER_LOGOUT")
suite.check("a cleared panel saves nothing", save.panelSessions[me] == nil)

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

ns.SettingsUI:Show()
local button = ns.SettingsUI.controls.clearPanel
suite.check("Settings has a Clear panel button", button ~= nil)
Loot(ns, "Mangy Wolf", { MEAT })
button:GetScript("OnClick")(button)
suite.check("its first click only asks", ns.Tracker.session["Mangy Wolf"] == 1)
button:GetScript("OnClick")(button)
suite.check("its second clears the panel", next(ns.Tracker.session) == nil)

local keepBox = ns.SettingsUI.controls.keepPanel
suite.check("Settings has the Keep it box, ticked here", keepBox ~= nil and keepBox:GetChecked())

suite.done()
