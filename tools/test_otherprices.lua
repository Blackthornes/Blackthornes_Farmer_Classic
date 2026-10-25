-- TradeSkillMaster's and Auctionator's prices when Tradeskills is not
-- loaded (the owner asked 2026-10-12).
--
-- What matters: Tradeskills always wins when it is loaded; without it TSM's
-- DBMarket comes first, then Auctionator's; greys stay vendor only and the
-- vendor price still wins when higher; unticked, neither is asked; a bad
-- answer or an error is no price; and an answer is kept for a minute.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("otherprices")

local ns = env.Load({ ui = true })
local Value = ns.Value

local VENDOR = { [5637] = 10, [3300] = 20, [4000] = 9000 }
local QUALITY = { [3300] = 0 }
_G.C_Item = {
    GetItemInfo = function(id)
        return "item", nil, QUALITY[id] or 1, 1, 1, "", "", 1, "", "", VENDOR[id] or 0
    end,
}

local clock = 100
_G.GetTime = function() return clock end
_G.BlackthornesTS = nil

local tsmAsked, aucAsked = {}, {}
local TSM = { [5637] = 400.4, [3300] = 900, [4000] = 50 }
local AUC = { [5637] = 300, [2589] = 77 }
local function InstallTSM()
    _G.TSM_API = { GetCustomPriceValue = function(source, item)
        tsmAsked[#tsmAsked + 1] = source .. " " .. item
        return TSM[tonumber(item:match("%d+"))]
    end }
end
local function InstallAuctionator()
    _G.Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(caller, id)
        aucAsked[#aucAsked + 1] = caller .. " " .. id
        return AUC[id]
    end } } }
end
local function Forget() Value:SetUsesOtherAddons(ns.db.otherPriceAddons ~= false) end

suite.check("nothing loaded: no auction prices", Value:PriceSource() == nil and Value:AuctionPrice(5637) == nil)

InstallAuctionator(); Forget()
suite.check("Auctionator alone is the source", Value:PriceSource() == "auctionator")
suite.check("Auctionator's price is used", Value:AuctionPrice(5637) == 300, Value:AuctionPrice(5637))
suite.check("asked with Farmer's caller ID", aucAsked[1] == "Blackthornes_Farmer 5637", aucAsked[1])

InstallTSM(); Forget()
suite.check("with both, TSM is named", Value:PriceSource() == "tsm")
suite.check("TSM's DBMarket comes first", Value:AuctionPrice(5637) == 400, Value:AuctionPrice(5637))
suite.check("asked for DBMarket by item string", tsmAsked[1] == "DBMarket i:5637", tsmAsked[1])
suite.check("Auctionator fills what TSM lacks", Value:AuctionPrice(2589) == 77)

local before = #tsmAsked
Value:AuctionPrice(5637)
suite.check("a second look within the minute is kept", #tsmAsked == before)
clock = clock + 61
Value:AuctionPrice(5637)
suite.check("and asked again after", #tsmAsked == before + 1)

suite.check("a grey stays vendor only", select(2, Value:UnitPrice(3300)) == "vendor" and Value:UnitPrice(3300) == 20)
suite.check("the vendor price wins when higher", Value:UnitPrice(4000) == 9000)
suite.check("the auction price wins when higher", Value:UnitPrice(5637) == 400)

-- Price Order: Auctionator first (the owner, 2026-10-25).
Value:SetPriceOrder("auctionator")
suite.check("Auctionator first is named", Value:PriceSource() == "auctionator")
suite.check("Auctionator first takes its price", Value:AuctionPrice(5637) == 300, Value:AuctionPrice(5637))
suite.check("TSM fills what Auctionator lacks", Value:AuctionPrice(3300) == 900, Value:AuctionPrice(3300))
Value:SetPriceOrder("tsm")
suite.check("back to TSM first", Value:AuctionPrice(5637) == 400)

_G.BlackthornesTS = { Prices = { GetValue = function() return 5 end } }
suite.check("Tradeskills loaded is the source", Value:PriceSource() == "tradeskills")
before = #tsmAsked
suite.check("and TSM is not asked", Value:AuctionPrice(5637) == 5 and #tsmAsked == before)
_G.BlackthornesTS = nil

Value:SetUsesOtherAddons(false)
before = #tsmAsked
suite.check("unticked: no source", Value:PriceSource() == nil)
suite.check("unticked: neither is asked", Value:AuctionPrice(5637) == nil and #tsmAsked == before)
Value:SetUsesOtherAddons(true)

_G.TSM_API.GetCustomPriceValue = function() error("boom") end
_G.Auctionator = nil
Forget()
suite.check("an error is no price", Value:AuctionPrice(5637) == nil)
_G.TSM_API.GetCustomPriceValue = function() return -1 end
Forget()
suite.check("a negative number is no price", Value:AuctionPrice(5637) == nil)

_G.TSM_API, _G.Auctionator, _G.GetTime = nil, nil, nil
suite.done()
