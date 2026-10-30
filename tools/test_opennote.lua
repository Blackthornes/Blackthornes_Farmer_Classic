-- The note on screen when a clam or sack from the bags is opened.
--
-- What matters: it says how many are opened out of 10 until then, and what
-- one is worth after; it shows when Containers counts an opening; it goes
-- after a few seconds; unticked, it never shows.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("opennote")

local ns = env.Load({ ui = true })
local OpenNote, Containers, Value = ns.OpenNote, ns.Containers, ns.Value

local CLAM = { name = "Small Barnacled Clam", id = 5523 }
local MEAT = { name = "Clam Meat", id = 5503 }
local clock = 100
_G.GetTime = function() return clock end

_G.C_Item = { GetItemInfo = function(id)
    return "item", nil, 1, 1, 1, "", "", 1, "", "", id == MEAT.id and 25 or 1
end }

suite.check("on unless unticked", OpenNote:Enabled())
suite.check("under 10 it counts up",
    ns.Util.StripColor(OpenNote.Text(CLAM.name, 3)) == "Small Barnacled Clam: 3 of 10 opened", OpenNote.Text(CLAM.name, 3))

-- Opened from the bags, as the loot window sees it.
local function OpenOne()
    Containers.opening = { id = CLAM.id, name = CLAM.name, at = GetTime(), unsure = false }
    env.world.loot = { MEAT }
    Containers:OnLoot()
    Containers:OnLootClosed()
end

OpenOne()
-- It goes in the shared note slot (UI/Notice.lua), with every addon's notes.
local frame = OpenNote.card
suite.check("an opening shows the note", frame ~= nil and frame:IsShown())
suite.check("with the count", ns.Util.StripColor(frame.text:GetText()) == "Small Barnacled Clam: 1 of 10 opened",
    frame and frame.text:GetText())

clock = clock + 20
frame:GetScript("OnUpdate")(frame)
suite.check("it goes after a few seconds", not frame:IsShown())

for _ = 2, 10 do OpenOne() end
frame = OpenNote.card
local text = frame.text:GetText()
suite.check("at 10 it says what one is worth", text:find("10 opened, about", 1, true) ~= nil, text)
suite.check("in coins", text:find("25c", 1, true) ~= nil, text)

OpenNote:Hide()
OpenNote:SetEnabled(false)
OpenOne()
suite.check("unticked, nothing shows", not frame:IsShown())
suite.check("but the opening still counts", Containers:Store()[CLAM.name].opens == 11)
OpenNote:SetEnabled(true)

ns.HandleSlash("opennote")
suite.check("/farm opennote turns it off", not OpenNote:Enabled())
ns.HandleSlash("opennote")
suite.check("and on again", OpenNote:Enabled())

suite.done()
