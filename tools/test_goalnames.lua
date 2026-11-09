-- A goal set by name gets the item named, not a longer one that starts the
-- same way (2026-11-09, a player's report: a goal for Salt became a goal for
-- Salty Scorpid Venom). Salt is a vendor item the data never lists, so the
-- loose match used to find the one data item starting with "salt".

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("goalnames")

local ns = env.Load({})
local Goals = ns.Goals

-- The client knows Salt by name and by ID, as it does once seen.
local known = { ["Salt"] = 4289 }
local names = { [4289] = "Salt" }
_G.C_Item = {
    GetItemCount = function() return 0 end,
    GetItemInfoInstant = function(text)
        if type(text) == "number" then return names[text] and text or nil end
        return known[text]
    end,
    GetItemNameByID = function(id) return names[id] end,
}

suite.check("the data has Salty Scorpid Venom", ns.DB:GetItem("Salty Scorpid Venom") ~= nil)
suite.check("the data has no Salt", ns.DB:GetItem("Salt") == nil)

suite.check("Salt stays Salt", Goals:ResolveItem("Salt") == "Salt")
suite.check("salt in any case stays as typed", Goals:ResolveItem("salt") == "salt")
suite.check("a Salt link stays Salt",
    Goals:ResolveItem("|cffffffff|Hitem:4289::::|h[Salt]|h|r") == "Salt")
suite.check("Salt by its ID", Goals:ResolveItem(4289) == "Salt")
suite.check("Salt by its ID typed", Goals:ResolveItem("4289") == "Salt")

-- Even before the client knows Salt, half a word never picks a longer name.
known = {}
suite.check("Salt unknown to the client still stays Salt", Goals:ResolveItem("Salt") == "Salt")

-- Whole words still find their one item.
suite.check("Salty Scorpid Venom by its name",
    Goals:ResolveItem("salty scorpid venom") == "Salty Scorpid Venom")
suite.check("Salty Scorpid by whole words", Goals:ResolveItem("Salty Scorpid") == "Salty Scorpid Venom")
suite.check("a data item by its ID", Goals:ResolveItem(ns.DB:GetItem("Salty Scorpid Venom").id) == "Salty Scorpid Venom")

-- A goal set for Salt is a goal for Salt.
known = { ["Salt"] = 4289 }
local goal = Goals:Set("Salt", 20)
suite.check("the goal is for Salt", goal and goal.item == "Salt")
suite.check("and not for the venom", Goals:Find("Salty Scorpid Venom") == nil)
suite.check("Find gets it back", Goals:Find("Salt") == goal)

suite.done()
