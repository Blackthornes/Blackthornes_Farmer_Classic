-- Tests for the loot feed (UI/LootFeed.lua): off until ticked, a slot shows
-- once it is taken, the same thing stacks and moves to the top, rows fade
-- after Show For, the foot adds up coin and worth, and the feed only takes
-- the mouse while it is being moved.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("lootfeed")

local FANG = { name = "Large Fang", id = 5637, quantity = 2 }
local CLOTH = { name = "Linen Cloth", id = 2589 }
local COIN = { name = "12 Copper", money = true }

local now = 100

-- The client's clock: env.Load puts in a fresh client, so this goes after it.
local function Load(opts)
    local ns = env.Load(opts)
    _G.GetTime = function() return now end
    return ns
end

local function Window(ns, items)
    local fire = ns.eventFrame:GetScript("OnEvent")
    env.world.loot = items
    fire(ns.eventFrame, "LOOT_READY")
    return function(slot) fire(ns.eventFrame, "LOOT_SLOT_CLEARED", slot) end,
        function() fire(ns.eventFrame, "LOOT_CLOSED") end
end

local function TakeAll(ns, items)
    local take, close = Window(ns, items)
    for slot = 1, #items do take(slot) end
    close()
end

-- 1. Off until it is turned on.
do
    local ns = Load({ ui = true })
    suite.check("off by default", ns.db.lootFeed == false and not ns.LootFeed:Enabled())
    suite.check("Show For starts at 5 seconds", ns.LootFeed:Hold() == 5 and ns.db.lootFeedHold == nil)
    suite.check("Show Worth starts on", ns.LootFeed:ShowsWorth())
    suite.check("Transparent starts at Some", ns.SeeThrough:Level("lootfeed") == 1)
    TakeAll(ns, { FANG })
    suite.check("off, nothing shows", #ns.LootFeed.rows == 0
        and not (ns.LootFeed.frame and ns.LootFeed.frame:IsShown()))
end

-- 2. A slot shows once it is taken, coin goes to the foot.
do
    local ns = Load({ ui = true })
    local Feed = ns.LootFeed
    ns.HandleSlash("lootfeed on")
    suite.check("/farm lootfeed on turns it on", Feed:Enabled())
    Feed:SetHold(3)

    local take, close = Window(ns, { FANG, COIN, CLOTH })
    suite.check("nothing shows before a slot is taken", #Feed.rows == 0)
    take(1)
    suite.check("a taken slot shows", #Feed.rows == 1 and Feed.rows[1].name == "Large Fang"
        and Feed.rows[1].count == 2, #Feed.rows)
    suite.check("with its item ID from the link", Feed.rows[1].id == 5637)
    suite.check("the feed shows", Feed.frame and Feed.frame:IsShown())
    take(2)
    suite.check("coin goes to the foot", Feed.coin == 12 and #Feed.rows == 1, Feed.coin)
    close()
    take(3)
    suite.check("a slot after the window closed is not shown", #Feed.rows == 1)

    local left = Feed:FootText()
    suite.check("the foot says the coin", type(left) == "string" and left:find("Coin:", 1, true) ~= nil, left)

    -- The same thing again stacks, moves to the top and holds again.
    now = 101
    TakeAll(ns, { CLOTH })
    suite.check("a new thing goes on top", Feed.rows[1].name == "Linen Cloth" and Feed.rows[2].name == "Large Fang")
    now = 102
    TakeAll(ns, { FANG })
    suite.check("the same thing adds to its count", #Feed.rows == 2 and Feed.rows[1].name == "Large Fang"
        and Feed.rows[1].count == 4, Feed.rows[1].count)
    local top = Feed.lines and Feed.lines[1]
    suite.check("how many sits on the icon's corner", top and ns.ItemLook
        and ns.ItemLook.CountShown(top.icon) == 4 and top.count:GetText() == "")
    suite.check("and holds again from now", Feed.rows[1].at == 102)

    -- Fades: the cloth goes first.
    now = 101 + 3 + 0.25
    Feed:Tick(0)
    suite.check("a row fading is still there", #Feed.rows == 2)
    suite.check("half way through its fade", math.abs(Feed:Alpha(101, now) - 0.5) < 0.01, Feed:Alpha(101, now))
    now = 101 + 3 + 0.6
    Feed:Tick(0)
    suite.check("a row past its fade is gone", #Feed.rows == 1 and Feed.rows[1].name == "Large Fang")
    now = 102 + 3 + 0.6
    Feed:Tick(0)
    suite.check("the last row gone, the feed hides", #Feed.rows == 0 and not Feed.frame:IsShown())
    suite.check("and the coin starts again", Feed.coin == 0)

    -- Show For.
    ns.LootFeed:SetHold(7)
    suite.check("Show For keeps 7 seconds", Feed:Hold() == 7 and ns.db.lootFeedHold == 7)
    ns.LootFeed:SetHold(99)
    suite.check("and never past 10", Feed:Hold() == 10)
    ns.LootFeed:SetHold(3)

    -- Window effects Off: no fade, gone when the hold ends.
    local realLevel = ns.Motion.Level
    ns.Motion.Level = function() return "off" end
    suite.check("with effects off a row goes when it stops holding", Feed:Alpha(0, 3.1) == nil)
    ns.Motion.Level = realLevel

    -- At most six rows.
    local many = {}
    for i = 1, 8 do many[i] = { name = "Thing " .. i, id = 9000 + i } end
    TakeAll(ns, many)
    suite.check("at most six rows", #Feed.rows == ns.LootFeed.MAX_ROWS, #Feed.rows)
    suite.check("the newest on top", Feed.rows[1].name == "Thing 8")

    -- Show Worth off leaves the worth out.
    Feed.rows[1].unit = 50
    ns.LootFeed:SetShowsWorth(false)
    local _, right = Feed:FootText()
    suite.check("Show Worth off leaves the worth out", right == nil and ns.db.lootFeedWorth == false)
    ns.LootFeed:SetShowsWorth(true)
    _, right = Feed:FootText()
    suite.check("Show Worth on puts it back", type(right) == "string" and right:find("Loot worth:", 1, true) ~= nil, right)

    ns.HandleSlash("lootfeed off")
    suite.check("/farm lootfeed off turns it off and empties it", not Feed:Enabled() and #Feed.rows == 0)
end

-- 2b. A 3 the first build saved, nobody picked, goes to 5; a picked one stays.
do
    local ns = Load({ ui = true })
    ns.db.lootFeedHold = 3
    suite.check("an unpicked 3 reads as 5", ns.LootFeed:Hold() == 5 and ns.db.lootFeedHold == nil, ns.LootFeed:Hold())
    ns.db.lootFeedHold, ns.db.lootFeedHoldPicked = 3, true
    suite.check("a picked 3 stays 3", ns.LootFeed:Hold() == 3)
    ns.db.lootFeedHold, ns.db.lootFeedHoldPicked = 8, nil
    suite.check("any other number stays", ns.LootFeed:Hold() == 8)
end

-- 2c. Nothing fades while the mouse is over it.
do
    local ns = Load({ ui = true })
    local Feed = ns.LootFeed
    Feed:SetEnabled(true)
    now = 200
    TakeAll(ns, { FANG })
    local over = true
    Feed.frame.IsMouseOver = function() return over end
    now = 200 + 30
    Feed:Tick(0)
    suite.check("the mouse on it keeps the row", #Feed.rows == 1 and Feed.rows[1].at == now)
    over = false
    now = now + Feed:Hold() + 1
    Feed:Tick(0)
    suite.check("and it fades once the mouse leaves", #Feed.rows == 0)
end

-- 3. Locked slots, hidden things and secret values never go in.
do
    local ns = Load({ ui = true })
    local Feed = ns.LootFeed
    Feed:SetEnabled(true)

    local realInfo = _G.GetLootSlotInfo
    _G.GetLootSlotInfo = function(slot)
        local icon, name, quantity = realInfo(slot)
        return icon, name, quantity, nil, 2, true
    end
    TakeAll(ns, { FANG })
    _G.GetLootSlotInfo = realInfo
    suite.check("a locked slot is left out", #Feed.rows == 0)

    ns.DB:Hide("item", "Large Fang")
    TakeAll(ns, { FANG })
    suite.check("a hidden item is left out", #Feed.rows == 0)
    ns.DB:Unhide("item", "Large Fang")

    TakeAll(ns, { { name = env.Secret("name"), quantity = env.Secret("quantity") } })
    suite.check("a secret value adds nothing and raises nothing", #Feed.rows == 0)
end

-- 4. A client without LOOT_SLOT_CLEARED shows the window as it is read.
do
    local ns = Load({ ui = true, unknownEvents = { LOOT_SLOT_CLEARED = true } })
    local Feed = ns.LootFeed
    Feed:SetEnabled(true)
    suite.check("the client refused the event", not Feed.slotEvent)
    Window(ns, { FANG, CLOTH })
    suite.check("every slot shows when the window is read", #Feed.rows == 2, #Feed.rows)
end

-- 5. It takes the mouse only while it is moved; Move and Reset.
do
    local ns = Load({ ui = true })
    local Feed = ns.LootFeed
    local frame = Feed:Build()
    local mouse
    frame.EnableMouse = function(_, on) mouse = on end

    ns.HandleSlash("lootfeed move")
    suite.check("Move lets it be dragged", Feed.moving and mouse == true)
    suite.check("and shows a row to hold on to", frame:IsShown() and Feed:Shown()[1].sample == true)
    suite.check("and the size grip", Feed.sizeGrip:IsShown())

    frame._left, frame._top = 400, 700
    ns.HandleSlash("lootfeed move")
    suite.check("Move again takes no mouse", not Feed.moving and mouse == false)
    suite.check("and keeps where it was left", ns.db.lootFeedX == 400 and ns.db.lootFeedY == 700)
    suite.check("with nothing looted it hides", not frame:IsShown())

    ns.db.lootFeedScale = 120
    ns.HandleSlash("lootfeed reset")
    suite.check("Reset puts it back", ns.db.lootFeedX == nil and ns.db.lootFeedY == nil
        and ns.db.lootFeedScale == nil)
end

-- 6. The Settings button reads Done while the feed is moved.
do
    local ns = Load({ ui = true })
    ns.SettingsUI:Show()
    local button = ns.SettingsUI.controls.lootFeedMove
    suite.check("the button starts as Move", button.label:GetText() == "Move", button.label:GetText())
    button:GetScript("OnClick")(button)
    suite.check("a click starts moving", ns.LootFeed.moving == true)
    suite.check("and the button reads Done", button.label:GetText() == "Done", button.label:GetText())
    button:GetScript("OnClick")(button)
    suite.check("Done locks it in place", ns.LootFeed.moving == false)
    suite.check("and the button reads Move again", button.label:GetText() == "Move", button.label:GetText())
    ns.HandleSlash("lootfeed move")
    suite.check("the typed command changes it too", button.label:GetText() == "Done")
end

suite.done()
