-- The Classic Era copy.
--
-- This repo is Farmer for WoW Classic Era. Classic's own data fits Era and
-- stays; what Forever added (its mob names, the owner's Forever harvest and
-- the Legacy perks) does not, so the TOC leaves it out, and the TOC must
-- never point a tag at the Forever project on CurseForge. Then the addon has
-- to load, log in and answer a search without them.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("era")

local handle = assert(io.open(lfs_cwd .. "/Blackthornes_Farmer.toc", "r"))
local toc = handle:read("*a")
handle:close()

suite.check("the TOC is not Forever's", not toc:find("## Interface: 16001", 1, true))
suite.check("the TOC names a Classic Era interface", toc:find("## Interface: 115", 1, true) ~= nil)
suite.check("the TOC never names Forever's CurseForge project",
    not toc:find("^## X%-Curse%-Project%-ID:%s*1710618") and not toc:find("\n## X%-Curse%-Project%-ID:%s*1710618"))

-- Data_Harvested.lua is the exception: tools/harvest_import.py writes it
-- from a save and adds it to the TOC, so once it is made from Era play it
-- belongs there. The copy in the repo now is Forever's and is left out.
for file in pairs(env.FOREVER_DATA) do
    if file ~= "Data/Data_Harvested.lua" then
        local line = file:gsub("/", "\\")
        suite.check("the TOC leaves out " .. file, not toc:find("\n" .. line, 1, true))
    end
end
suite.check("the TOC keeps Classic's drops", toc:find("\nData\\Data_ClassicDrops.lua", 1, true) ~= nil)
suite.check("the TOC keeps Classic's mob names", toc:find("\nData\\NpcNames.lua", 1, true) ~= nil)

-- Loading as Era does.
local ns = env.Load({ ui = true, era = true })
suite.check("Classic's mob names are there", type(ns.NPC_NAMES) == "table")
suite.check("no Forever mob names", ns.FOREVER_NPC_NAMES == nil)
suite.check("no Legacy perks", ns.Legacy == nil)
suite.check("nothing is sent to Blackthornes", not ns.Contribute:HasRecipients())

local boot = ns.modules.Bootstrap
local ok, err = pcall(function()
    boot:ADDON_LOADED("ADDON_LOADED", "Blackthornes_Farmer")
    boot:PLAYER_LOGIN()
end)
suite.check("it loads and logs in", ok, err)

local found, results = pcall(function() return ns.Search:Run("copper ore") end)
suite.check("a search answers", found and type(results) == "table", results)

suite.done()
