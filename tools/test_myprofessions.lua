-- Map markers for this character's gathering skills only.
--
-- What matters: on by default, a character sees only the herb, ore and
-- fishing spots its own skills can use; unticked, every spot shows; a
-- client that will not say the skills shows every spot, so nothing goes
-- missing by mistake; a skill learned shows its spots at once; and the
-- Settings tick and /farm markers mine are the same switch.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("myprofessions")

local clock = 500
local ns = env.Load({ ui = true })
local Gathering, MapMarkers = ns.Gathering, ns.MapMarkers
_G.GetTime = function() return clock end

-- The character's professions, as the client gives them.
local profs = { { "Herbalism", 182 } }
_G.GetProfessions = function()
    local idx = {}
    for i = 1, #profs do idx[i] = i end
    return idx[1], idx[2], idx[3], idx[4], idx[5]
end
_G.GetProfessionInfo = function(index)
    local p = profs[index]
    if not p then return nil end
    return p[1], nil, 100, 150, 0, 0, p[2]
end

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

Gathering:AddSpot(37, 0.2, 0.2, "Peacebloom", "herb")
Gathering:AddSpot(37, 0.5, 0.5, "Copper Vein", "ore")
Gathering:AddSpot(37, 0.8, 0.8, "Oily Blackmouth School", "fish")

local function Kinds()
    local seen = {}
    for _, spot in ipairs(MapMarkers:SpotsOn(37)) do seen[#seen + 1] = spot.kind end
    table.sort(seen)
    return table.concat(seen, ",")
end

suite.check("on by default", MapMarkers.MineOnly())
suite.check("a herbalist sees only herbs", Kinds() == "herb", Kinds())

-- Learning Mining shows its veins at once, without waiting.
profs[2] = { "Mining", 186 }
ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, "SKILL_LINES_CHANGED")
suite.check("a skill learned shows its spots at once", Kinds() == "herb,ore", Kinds())

-- Fishing sits in its own place in GetProfessions (the 4th return).
_G.GetProfessions = function() return 1, nil, nil, 2, nil end
profs = { { "Herbalism", 182 }, { "Fishing", 356 } }
MapMarkers.known = nil
suite.check("fishing counts from its own slot", Kinds() == "fish,herb", Kinds())

-- Matched by the skill line too, whatever the client calls it.
profs = { { "Bergbau", 186 }, { "Angeln", 356 } }
MapMarkers.known = nil
suite.check("a German client matches by skill line", Kinds() == "fish,ore", Kinds())

-- No gathering skills: no gathering spots.
_G.GetProfessions = function() return nil end
MapMarkers.known = nil
suite.check("no gathering skills, no spots", Kinds() == "", Kinds())

-- Unticked: every spot shows.
ns.HandleSlash("markers mine off")
suite.check("/farm markers mine off saves it", ns.db.markersMyProfessions == false)
suite.check("unticked, every spot shows", Kinds() == "fish,herb,ore", Kinds())
ns.HandleSlash("markers mine on")
suite.check("/farm markers mine on brings it back", MapMarkers.MineOnly() and Kinds() == "", Kinds())

-- A client that will not say: every spot shows.
_G.GetProfessions = nil
_G.GetNumSkillLines = nil
MapMarkers.known = nil
suite.check("unreadable skills show every spot", Kinds() == "fish,herb,ore", Kinds())

-- Read again after a while, not on every draw.
_G.GetProfessions = function() return 1 end
profs = { { "Mining", 186 } }
suite.check("kept for a moment", Kinds() == "fish,herb,ore", Kinds())
clock = clock + MapMarkers.KNOWN_EVERY + 1
suite.check("read again after KNOWN_EVERY", Kinds() == "ore", Kinds())

-- The Settings tick is the same switch.
ns.SettingsUI:Show()
local box = ns.SettingsUI.controls.markersMine
suite.check("the page shows it ticked", box and box:GetChecked())
box:GetScript("OnClick")(box)
suite.check("unticking saves it off", ns.db.markersMyProfessions == false)
ns.SettingsUI:Hide()

suite.done()
