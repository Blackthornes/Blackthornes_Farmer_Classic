-- Rankings' "Vendor only" (the owner, 2026-10-27).
--
-- What matters: off unless ticked, so worth per kill is as it was; ticked,
-- every drop counts at what a vendor pays, coin stays, a drop no vendor
-- buys leaves, the order follows the new worth, the mob's own worth is
-- untouched, the price note says vendor prices, climbers show "+N", and
-- the tick box, Settings and /farm rankings vendor all write the same key.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("rankingsvendor")

local ns = env.Load({ ui = true })
local Rankings = ns.Rankings
local Tracker = ns.Tracker

-- Cloth sells well at auction and for little at a vendor; the claw is a
-- grey that only a vendor buys; the gem has no vendor price at all.
local AUCTION = { [2592] = 300, [7101] = 900 }
local VENDOR = { [2592] = 33, [7100] = 90 }
local QUALITY = { [2592] = 1, [7100] = 0, [7101] = 1 }

_G.C_Item = {
    GetItemInfo = function(id)
        return "item", nil, QUALITY[id] or 1, 1, 1, "", "", 1, "", "", VENDOR[id] or 0
    end,
    GetItemQualityByID = function(id) return QUALITY[id] end,
}
_G.BlackthornesTS = {
    Prices = { GetValue = function(_, id) return AUCTION[id] end },
}

local serial = 0
local function Loot(mob, items)
    serial = serial + 1
    env.world.zone, env.world.subZone = "Redridge Mountains", ""
    env.world.target = { name = mob, level = 20, dead = true, guid = "U-" .. serial }
    env.world.loot = { { name = "5 Copper", money = true } }
    for _, item in ipairs(items) do env.world.loot[#env.world.loot + 1] = item end
    Tracker:OnLoot()
end

for _ = 1, 20 do
    Loot("Cloth Gnoll", { { name = "Wool Cloth", id = 2592 }, { name = "Shiny Gem", id = 7101 } })
    Loot("Claw Dog", { { name = "Chipped Claw", id = 7100, color = "ff9d9d9d" } })
end

local function Find(list, mob)
    for _, entry in ipairs(list) do
        if entry.mob == mob then return entry end
    end
    return nil
end

suite.check("off by default", not Rankings.VendorOnly())
local board = Rankings:Build()
local gnoll, dog = Find(board.measured, "Cloth Gnoll"), Find(board.measured, "Claw Dog")
suite.check("off, both are measured", gnoll ~= nil and dog ~= nil)
suite.check("off, the gnoll is first", gnoll and gnoll.rank == 1)
suite.check("off, the gnoll counts auction prices", gnoll and gnoll.value >= 1200)

ns.UI:Show()
ns.UI:ShowTab("rankings")
local UI = ns.RankingsUI
suite.check("the tab has the box", UI.vendor ~= nil)
suite.check("the tab's box shows it off", UI.vendor and not UI.vendor:GetChecked())

-- Hold timers so the climbs stay up while the test looks at them.
local timers, after = {}, _G.C_Timer.After
_G.C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
local stamp = ns.RankUp.Stamp()
UI.vendor:GetScript("OnClick")(UI.vendor)
suite.check("ticking the tab's box turns it on", Rankings.VendorOnly() and ns.db.rankingsVendorOnly == true)
suite.check("ticking it moves the rank-up stamp", ns.RankUp.Stamp() ~= stamp)
suite.check("the price note says vendor prices", UI:PriceText() == "vendor prices")

board = Rankings:Build()
gnoll, dog = Find(board.measured, "Cloth Gnoll"), Find(board.measured, "Claw Dog")
suite.check("ticked, both stay on the board", gnoll ~= nil and dog ~= nil)
suite.check("ticked, the gnoll counts coin and the cloth's vendor price", gnoll and math.abs(gnoll.value - (5 + 33)) < 0.01)
suite.check("ticked, the gem no vendor buys leaves", gnoll and #gnoll.details.priced == 1)
suite.check("ticked, the dog goes first", dog and dog.rank == 1)
suite.check("ticked, the dog's claw counts", dog and math.abs(dog.value - (5 + 90)) < 0.01)
suite.check("ticked, the mob's own worth is untouched", (ns.Value:ForMob("Cloth Gnoll")) >= 1200)
suite.check("the dog climbed one place", UI:ClimbOf(dog) == 1)
suite.check("the gnoll did not climb", UI:ClimbOf(gnoll) == nil)
_G.C_Timer.After = after
for _, fn in ipairs(timers) do fn() end
suite.check("the climbs go after a moment", UI.climbs == nil and UI:ClimbOf(dog) == nil)

ns.HandleSlash("rankings vendor off")
suite.check("/farm rankings vendor off unticks it", not Rankings.VendorOnly())
board = Rankings:Build()
suite.check("off again, the gnoll is first", Find(board.measured, "Cloth Gnoll").rank == 1)
ns.HandleSlash("rankings vendor on")
suite.check("/farm rankings vendor on ticks it", Rankings.VendorOnly())
ns.HandleSlash("rankings vendor")
suite.check("/farm rankings vendor on its own toggles it", not Rankings.VendorOnly())

suite.done()
