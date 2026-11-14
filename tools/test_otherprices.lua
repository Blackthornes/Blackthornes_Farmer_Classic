-- TradeSkillMaster's and Auctionator's prices when Tradeskills is not
-- loaded (the owner asked 2026-10-12).
--
-- What matters: Tradeskills always wins when it is loaded; without it TSM's
-- DBRecent comes first, then Auctionator's; greys stay vendor only and the
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
suite.check("TSM's DBRecent comes first", Value:AuctionPrice(5637) == 400, Value:AuctionPrice(5637))
suite.check("asked for DBRecent by item string", tsmAsked[1] == "DBRecent i:5637", tsmAsked[1])
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

-- TSM Price Source (a player asked, the owner said build it, 2026-11-13).
local reads, valid = {}, { DBMarket = true, DBMinBuyout = true, ["dbmarket*1.1"] = true }
local noRecent = {}
_G.TSM_API = {
    GetCustomPriceValue = function(source, item)
        reads[#reads + 1] = source
        if source == "DBRecent" then return not noRecent[item] and 400 or nil end
        if source == "DBMinBuyout" then return 777 end
        if source == "DBMarket" then return 500 end
        return nil
    end,
    IsCustomPriceValid = function(text) return valid[text] == true end,
}
Value:SetTSMSource(nil)
suite.check("no source typed reads DBRecent", Value:OtherPrice(6001) == 400 and reads[#reads] == "DBRecent")
noRecent["i:6002"] = true
suite.check("no DBRecent price falls back to DBMarket", Value:OtherPrice(6002) == 500 and reads[#reads] == "DBMarket", reads[#reads])
Value:SetTSMSource("  DBMinBuyout ")
suite.check("a typed source is kept trimmed", ns.db.tsmPriceSource == "DBMinBuyout")
suite.check("and it is read", Value:OtherPrice(6001) == 777 and reads[#reads] == "DBMinBuyout", reads[#reads])
suite.check("a known source is not refused", not Value:TSMSourceRefused())
Value:SetTSMSource("dbmarket*1.1")
suite.check("a source with no price falls back to DBRecent", Value:OtherPrice(6001) == 400 and reads[#reads] == "DBRecent")
Value:SetTSMSource("NotAPrice")
suite.check("a source TSM doesn't know is refused", Value:TSMSourceRefused())
suite.check("and reads DBRecent", Value:OtherPrice(6001) == 400 and reads[#reads] == "DBRecent")
Value:SetTSMSource("")
suite.check("an empty box saves nothing", ns.db.tsmPriceSource == nil and Value:TSMSource() == "DBRecent")
_G.TSM_API.IsCustomPriceValid = nil
Value:SetTSMSource("NotAPrice")
suite.check("without the check call it is tried as typed", Value:TSMSource() == "NotAPrice")
_G.TSM_API = nil
suite.check("without TSM nothing is refused", not Value:TSMSourceRefused())
Value:SetTSMSource(nil)

-- TSM Gear Source (a player asked, the owner said build it, 2026-11-14).
local CLASS, BIND = { [7001] = 4, [7002] = 2, [7003] = 7, [7004] = 4 }, { [7001] = 2, [7002] = 1, [7003] = 0 }
local oldItem = _G.C_Item
_G.C_Item = {
    GetItemInfoInstant = function(id) return id, "", "", "", 0, CLASS[id] end,
    GetItemInfo = function(id)
        if not BIND[id] then return nil end
        return "item", nil, 2, 1, 1, "", "", 1, "", "", 0, CLASS[id], 0, BIND[id]
    end,
}
suite.check("BoE armor is BoE gear", Value.IsBoEGear(7001) == true)
suite.check("bind on pickup is not", Value.IsBoEGear(7002) == false)
suite.check("a trade good is not", Value.IsBoEGear(7003) == false)
suite.check("gear not loaded yet can't say", Value.IsBoEGear(7004) == nil)
reads = {}
_G.TSM_API = {
    GetCustomPriceValue = function(source, item)
        reads[#reads + 1] = source
        if source == "DBRecent" then return 400 end
        if source == "DBMinBuyout" then return 777 end
        if source == "DBMarket" then return 500 end
        return nil
    end,
    IsCustomPriceValid = function(text) return valid[text] == true end,
}
Value:SetTSMSource(nil)
Value:SetTSMGearSource("   ")
suite.check("an empty gear box saves nothing", ns.db.tsmGearPriceSource == nil and Value:TSMGearSource() == nil)
suite.check("so gear reads the TSM Price Source", Value:OtherPrice(7001) == 400 and reads[#reads] == "DBRecent")
Value:SetTSMGearSource(" DBMarket ")
suite.check("a gear source is kept trimmed", ns.db.tsmGearPriceSource == "DBMarket")
suite.check("BoE gear reads it", Value:OtherPrice(7001) == 500 and reads[#reads] == "DBMarket", reads[#reads])
suite.check("a trade good doesn't", Value:OtherPrice(7003) == 400 and reads[#reads] == "DBRecent")
suite.check("bind on pickup gear doesn't", Value:OtherPrice(7002) == 400 and reads[#reads] == "DBRecent")
suite.check("gear not loaded yet reads the TSM Price Source", Value:OtherPrice(7004) == 400)
CLASS[7004], BIND[7004] = 4, 2
suite.check("and isn't kept, so it is asked again", Value:OtherPrice(7004) == 500)
Value:SetTSMSource("DBMinBuyout")
suite.check("the main box still prices trade goods", Value:OtherPrice(7003) == 777)
suite.check("while gear keeps its own", Value:OtherPrice(7001) == 500)
Value:SetTSMGearSource("dbmarket*1.1")
suite.check("a gear source with no price falls back to the TSM Price Source", Value:OtherPrice(7001) == 777)
Value:SetTSMGearSource("NotAPrice")
suite.check("a gear source TSM doesn't know is refused", Value:TSMGearSourceRefused())
suite.check("and reads the TSM Price Source", Value:OtherPrice(7001) == 777)
Value:SetTSMGearSource(nil)
Value:SetTSMSource(nil)
suite.check("the main box is never touched by the gear box", ns.db.tsmPriceSource == nil)
_G.C_Item = oldItem

_G.TSM_API, _G.Auctionator, _G.GetTime = nil, nil, nil
suite.done()
