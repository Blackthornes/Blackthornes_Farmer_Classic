-- Blackthornes Farmer -- UI/OpenButton.lua
-- The Open button: one click opens the next clam, sack or lockbox in the
-- bags (the owner asked 2026-10-15, "just the button with hover text that
-- say Open", and wanted it in Farmer).
--
-- Where: on the Kills & Loot panel's title bar, left of its X, the panel
-- that is up while farming. An icon only: the next item's own icon, how
-- many are waiting in its corner, and "Open" under the mouse.
--
-- What counts: a bag slot the client says has loot in it
-- (C_Container.GetContainerItemInfo's hasLoot). Left shut, so nothing kept on
-- purpose is used up:
--   * anything a Farmer goal of this character still needs (Butler:Advise);
--   * anything Tradeskills' craft queue needs, here or on another character
--     (its Butler:Advise, `need` and `mailCount`, in a pcall when loaded);
--   * anything on Butler's Always keep, bank or mail lists, or that Butler
--     keeps for an open quest (its Verdicts:Choice and Quests:Reason, in a
--     pcall when loaded);
--   * quest items, a lockbox still locked (its tooltip says so) and a slot
--     the game has locked while it moves.
--
-- Addon code may not use an item, but the player's own click on a secure
-- button may. So this is a secure button, aimed at one slot ("/use bag
-- slot") just before the click runs and emptied after. At a vendor, the
-- bank, a mailbox, the auction house or a trade a /use would sell, bank,
-- attach or trade the item, so the button hides there (BagsFull:AtAPlace).
--
-- The panel stays up in a fight and must stay free to move, so the button
-- sits on it only out of combat: as a fight starts (PLAYER_REGEN_DISABLED)
-- it is hidden, emptied and handed back to UIParent, and it comes back on
-- the panel when the fight ends.
--
-- Open after loot (`autoOpen`, off unless ticked) opens the next one from
-- addon code each time a loot window closes, out of combat, away from those
-- places, with a free bag slot. The first one it opens is the check that
-- the game allows it (`openTest`, the owner 2026-10-23: no Test button):
-- once the game refuses the call it stays off; /farm openbutton test still
-- runs the check by hand. One that stays shut is tried
-- again (the game can refuse one while a loot window is still closing) and
-- left for the session only after `STRIKES` tries in a row; one that opens,
-- or a click on the button, starts the count again.
--
-- "Open button" on the Loot page (`openButton`, on unless unticked) and
-- /farm openbutton. Never rename `openButton`, `autoOpen` or `openTest`.

local _, ns = ...
local L = ns.L

local OpenButton = ns.NewModule("OpenButton")

OpenButton.SIZE = 18
-- Slots read a frame.
OpenButton.BUDGET = 40
-- After the last bag event, how long before the bags are read.
OpenButton.SETTLE = 0.3
-- After a loot window closes, how long before the next one opens by itself.
OpenButton.AUTO_DELAY = 1.0
-- After a loot window closes, the longest to wait for the bags to take its
-- loot before the next one opens (using one while they still are gives the
-- game's internal bag error).
OpenButton.BAG_WAIT = 2
-- How many times Open after loot looks again while the next one's slot is
-- still locked from the last opening, AUTO_DELAY apart.
OpenButton.RETRIES = 6
-- Tries in a row that stay shut before Open after loot leaves an item alone.
OpenButton.STRIKES = 3
-- How long the test waits for a loot window.
OpenButton.TEST_WAIT = 1.5

-- What the last read found: { bag, slot, itemID, count, icon, link }, in
-- bag order, and how many items that is.
OpenButton.queue = {}
OpenButton.total = 0
-- Items Open after loot tried that stayed shut, this session: [itemID] =
-- tries in a row.
OpenButton.tried = {}

--------------------------------------------------------------------------------
-- Client calls
--------------------------------------------------------------------------------

local function Field(object, key)
    if type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

local function Container(name, ...)
    local api = rawget(_G, "C_Container")
    local fn = type(api) == "table" and api[name] or rawget(_G, name)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2)
end

local function Number(value)
    local ok, n = pcall(function()
        local n = tonumber(value)
        if n then return n + 0 end
    end)
    if ok and type(n) == "number" then return n end
    return nil
end

local function InCombat()
    local fn = rawget(_G, "InCombatLockdown")
    if type(fn) ~= "function" then return false end
    local ok, fighting = pcall(fn)
    return ok and fighting and true or false
end

--- One slot as the client has it, or nil when it is empty.
function OpenButton.ReadSlot(bag, slot)
    local info = Container("GetContainerItemInfo", bag, slot)
    if type(info) ~= "table" then return nil end
    local ok, entry = pcall(function()
        local id = tonumber(info.itemID)
        if not id then return nil end
        return {
            bag = bag, slot = slot, itemID = id,
            count = tonumber(info.stackCount) or 1,
            locked = info.isLocked and true or false,
            loot = info.hasLoot and true or false,
            icon = info.iconFileID,
            link = info.hyperlink,
        }
    end)
    return ok and entry or nil
end

--- Is it a quest item, or one that starts a quest?
local function QuestItem(bag, slot)
    local info = Container("GetContainerItemQuestInfo", bag, slot)
    if type(info) ~= "table" then return false end
    local ok, quest = pcall(function() return (info.isQuestItem or info.questID) and true or false end)
    return ok and quest == true
end

--- Does the slot's tooltip say the lockbox is still locked?
function OpenButton.LockedBox(bag, slot)
    local tip = rawget(_G, "C_TooltipInfo")
    if type(tip) ~= "table" or type(tip.GetBagItem) ~= "function" then return false end
    local word = rawget(_G, "LOCKED") or "Locked"
    local ok, locked = pcall(function()
        local data = tip.GetBagItem(bag, slot)
        for _, line in ipairs(data and data.lines or {}) do
            if line.leftText == word then return true end
        end
        return false
    end)
    return ok and locked == true
end

--- A sister's Butler:Advise answer for `itemID`, or nil.
local function Advise(global, itemID)
    local butler = Field(rawget(_G, global), "Butler")
    local fn = Field(butler, "Advise")
    if type(fn) ~= "function" then return nil end
    local ok, answer = pcall(fn, butler, itemID)
    return ok and type(answer) == "table" and answer or nil
end

local function Positive(answer, key)
    local n = Number(Field(answer, key))
    return n ~= nil and n > 0
end

--- Butler's word on the item: true when one of its lists or an open quest
--- keeps it.
local function ButlerKeeps(itemID)
    local butler = rawget(_G, "BlackthornesButler")
    local verdicts = Field(butler, "Verdicts")
    local choice = Field(verdicts, "Choice")
    if type(choice) == "function" then
        local ok, said = pcall(choice, verdicts, itemID)
        if ok and (said == "keep" or said == "bank" or said == "mail") then return true end
    end
    local quests = Field(butler, "Quests")
    local reason = Field(quests, "Reason")
    if type(reason) == "function" then
        local ok, said = pcall(reason, quests, itemID)
        if ok and said then return true end
    end
    return false
end

--- Is the item kept on purpose? Then it is never opened.
function OpenButton.Kept(entry)
    local itemID = entry.itemID
    local goal = ns.Butler and ns.Butler:Advise(itemID)
    if Positive(goal, "need") then return true end
    local ts = Advise("BlackthornesTS", itemID)
    if Positive(ts, "need") or Positive(ts, "mailCount") then return true end
    if ButlerKeeps(itemID) then return true end
    return QuestItem(entry.bag, entry.slot)
end

--- May this slot be opened? `entry` as ReadSlot gives it.
function OpenButton.Openable(entry)
    if not (entry and entry.loot) or entry.locked then return false end
    if OpenButton.Kept(entry) then return false end
    return not OpenButton.LockedBox(entry.bag, entry.slot)
end

--- At a vendor, the bank, a mailbox, the auction house or a trade, where a
--- /use does something else with the item.
OpenButton.at = {}
local PLACES = {
    MERCHANT_SHOW = "MERCHANT_CLOSED",
    BANKFRAME_OPENED = "BANKFRAME_CLOSED",
    MAIL_SHOW = "MAIL_CLOSED",
    AUCTION_HOUSE_SHOW = "AUCTION_HOUSE_CLOSED",
    TRADE_SHOW = "TRADE_CLOSED",
}

function OpenButton.Busy()
    for _, open in pairs(OpenButton.at) do
        if open then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

function OpenButton:Enabled()
    return ns.db ~= nil and ns.db.openButton ~= false
end

function OpenButton:SetEnabled(on)
    ns.db.openButton = on and true or false
    if on then self:Changed() else self:Draw() end
end

function OpenButton:AutoOn()
    return ns.db ~= nil and ns.db.autoOpen == true
end

function OpenButton:SetAuto(on)
    ns.db.autoOpen = on and true or false
end

--- "works", "blocked" or nil when the test has not run.
function OpenButton:TestResult()
    local test = ns.db and ns.db.openTest
    return type(test) == "table" and test.result or nil
end

--- May Open after loot open things now? Until the game has refused it, yes:
--- the first opening is the test.
function OpenButton:MayAuto()
    return self:AutoOn() and self:TestResult() ~= "blocked"
end

--- Keep what an opening from addon code showed, once: "works" when one
--- opened, "blocked" when the game refused the call.
function OpenButton:Learned(works, err)
    if self:TestResult() == "works" then return end
    ns.db.openTest = { at = time(), result = works and "works" or "blocked",
        error = err and tostring(err):sub(1, 120) or nil, quiet = true }
end

--------------------------------------------------------------------------------
-- Reading the bags
--------------------------------------------------------------------------------

--- The bags changed: read them once the burst is over.
function OpenButton:Changed()
    if self.settling then return end
    self.settling = true
    C_Timer.After(self.SETTLE, function()
        OpenButton.settling = false
        OpenButton:Scan()
    end)
end

--- Read the bags a few dozen slots a frame, then draw. `done` runs after.
function OpenButton:Scan(done)
    if done then
        self.waiters = self.waiters or {}
        self.waiters[#self.waiters + 1] = done
    end
    if self.scanning then
        self.again = true
        return
    end
    if not self:Enabled() and not self:AutoOn() and not done then return end
    self.scanning = true

    local places = {}
    local last = Number(rawget(_G, "NUM_BAG_SLOTS")) or 4
    for bag = 0, last do
        for slot = 1, Number(Container("GetContainerNumSlots", bag)) or 0 do
            places[#places + 1] = { bag, slot }
        end
    end

    local found, index, locked = {}, 0, false
    local function Step()
        local stop = math.min(#places, index + OpenButton.BUDGET)
        for i = index + 1, stop do
            local entry = OpenButton.ReadSlot(places[i][1], places[i][2])
            -- Only a slot with loot is looked at further.
            if entry and entry.loot and OpenButton.Openable(entry) then
                found[#found + 1] = entry
            elseif entry and entry.loot and entry.locked then
                -- Locked for a moment, as the one just opened is.
                locked = true
            end
        end
        index = stop
        if index < #places then
            C_Timer.After(0, Step)
            return
        end

        local total = 0
        for _, entry in ipairs(found) do total = total + entry.count end
        OpenButton.queue, OpenButton.total = found, total
        OpenButton.lockedLoot = locked
        OpenButton.scanning = false
        if OpenButton.again then
            OpenButton.again = false
            return OpenButton:Scan()
        end
        OpenButton:Draw()
        local waiters = OpenButton.waiters
        OpenButton.waiters = nil
        for _, fn in ipairs(waiters or {}) do fn() end
    end
    Step()
end

--- Open after loot has tried this one `STRIKES` times in a row and it stayed shut.
function OpenButton:GaveUp(itemID)
    return (self.tried[itemID] or 0) >= self.STRIKES
end

--- One more try that stayed shut.
function OpenButton:Strike(itemID)
    self.tried[itemID] = (self.tried[itemID] or 0) + 1
end

--- The next slot that still holds something to open, read again now, or nil.
--- `skipTried` leaves out what Open after loot tried and could not open.
function OpenButton:Next(skipTried)
    for _, item in ipairs(self.queue) do
        local entry = OpenButton.ReadSlot(item.bag, item.slot)
        if entry and entry.itemID == item.itemID and not (skipTried and OpenButton:GaveUp(entry.itemID))
            and OpenButton.Openable(entry) then
            return entry
        end
    end
end

--------------------------------------------------------------------------------
-- The button
--------------------------------------------------------------------------------

local function Clear(button)
    button:SetAttribute("type", nil)
    button:SetAttribute("macrotext", nil)
end

function OpenButton:Create()
    if self.button then return self.button end

    local button = CreateFrame("Button", "BlackthornesFarmerOpen", UIParent, "SecureActionButtonTemplate")
    button:SetSize(self.SIZE, self.SIZE)
    button:Hide()
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false)

    ns.Theme.Fill(button, "row")
    ns.Theme.Border(button, "accent")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon = icon

    local count = ns.Theme.CreateLabel(button, "tiny", "text", "RIGHT")
    count:SetPoint("BOTTOMRIGHT", 2, -2)
    button.count = count

    local glow = button:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints(icon)
    glow:SetColorTexture(1, 0.9, 0.6, 0.25)

    button:HookScript("OnEnter", function(frame)
        if not GameTooltip then return end
        GameTooltip:SetOwner(frame, "ANCHOR_TOP")
        GameTooltip:SetText(L["Open"], 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    -- Last look before the secure action runs: aimed at the next slot that
    -- may still be opened, or at nothing.
    button:SetScript("PreClick", function(frame)
        if InCombat() then return end
        local item = not OpenButton.Busy() and OpenButton:Next() or nil
        if not item then
            Clear(frame)
            return
        end
        -- Opened by hand, so the game allows it: Open after loot tries again.
        OpenButton.tried = {}
        frame:SetAttribute("type", "macro")
        frame:SetAttribute("macrotext", ("/use %d %d"):format(item.bag, item.slot))
    end)
    -- Nothing is left aimed at a slot between clicks.
    button:SetScript("PostClick", function(frame)
        if not InCombat() then Clear(frame) end
    end)

    self.button = button
    return button
end

--- Show it on the panel's title bar while there is something to open.
function OpenButton:Draw()
    if self.fighting or InCombat() then return end
    local Tracker = ns.TrackerUI
    local header = Tracker and Tracker.header
    local close = Tracker and (Tracker.openAnchor or Tracker.closeButton)
    local show = self:Enabled() and self.total > 0 and header ~= nil and not OpenButton.Busy()
    local button = self.button
    if not show then
        if button then button:Hide() end
        return
    end

    button = self:Create()
    if button:GetParent() ~= header then button:SetParent(header) end
    button:ClearAllPoints()
    if close then
        button:SetPoint("RIGHT", close, "LEFT", -6, 0)
    else
        button:SetPoint("TOPRIGHT", header, "TOPRIGHT", -30, -5)
    end
    local first = self.queue[1]
    button.icon:SetTexture(first and first.icon or 134400)
    button.count:SetText(self.total > 1 and tostring(self.total) or "")
    button:Show()
end

--------------------------------------------------------------------------------
-- The test, and opening after loot
--------------------------------------------------------------------------------

local function Use()
    local api = rawget(_G, "C_Container")
    local fn = type(api) == "table" and api.UseContainerItem or rawget(_G, "UseContainerItem")
    return type(fn) == "function" and fn or nil
end

--- Open the next one from addon code, to see whether the game allows it.
--- What it finds is kept in openTest.
function OpenButton:Test()
    if InCombat() then
        ns.Print(L["not in a fight. Try again after it."])
        return
    end
    if OpenButton.Busy() then
        ns.Print(L["step away from vendors, the bank and the mailbox first, or the test would sell, bank or mail the item."])
        return
    end
    local use = Use()
    if not use then
        ns.Print(L["this version of the game can't open items from addon code."])
        return
    end

    self:Scan(function()
        local item = OpenButton:Next()
        if not item then
            ns.Print(L["no clam, sack or lockbox in your bags to test with. Carry one and try again."])
            return
        end
        ns.Print(L["trying to open one from addon code..."])
        OpenButton.testLoot = false
        OpenButton.testing = true
        local called, err = pcall(use, item.bag, item.slot)

        C_Timer.After(OpenButton.TEST_WAIT, function()
            OpenButton.testing = false
            local still = OpenButton.ReadSlot(item.bag, item.slot)
            local used = not (still and still.itemID == item.itemID and still.count == item.count)
            local works = called and (OpenButton.testLoot or used) and true or false
            ns.db.openTest = { at = time(), result = works and "works" or "blocked",
                error = (not called and err) and tostring(err):sub(1, 120) or nil }
            if works then
                ns.Print(L["|cff4fd18bopening from Farmer works|r. Tick Open after loot on the Loot page and they open as you loot."])
            else
                ns.Print(L["|cffe5604fthe game won't let Farmer open things by itself|r. The Open button still works."])
            end
        end)
    end)
end

--- Whether the last try opened: a strike when it stayed shut, a fresh count
--- when it opened.
function OpenButton:Settle()
    local last = self.last
    self.last = nil
    if not last then return end
    local still = OpenButton.ReadSlot(last.bag, last.slot)
    if still and still.itemID == last.itemID and still.count >= last.count then
        self:Strike(last.itemID)
    else
        self.tried[last.itemID] = nil
        self:Learned(true)
    end
end

--- A loot window closed: once the bags have taken the loot, note what the
--- last try did and open the next (BAG_UPDATE_DELAYED), or `BAG_WAIT`
--- later when nothing came.
function OpenButton:LootClosed()
    if not self:MayAuto() then
        self:Settle()
        return
    end
    local token = {}
    self.waitBags = token
    C_Timer.After(self.BAG_WAIT, function() OpenButton:BagsTook(token) end)
end

--- The bags took the loot (or the wait ran out): open the next one shortly.
function OpenButton:BagsTook(token)
    if not self.waitBags or (token and self.waitBags ~= token) then return end
    self.waitBags = nil
    -- Judged once the bags show it: at LOOT_CLOSED the stack can still read
    -- as before, which counted a clam that opened as one that stayed shut.
    self:Settle()
    self.retries = 0
    C_Timer.After(self.AUTO_DELAY, function() OpenButton:OpenNext() end)
end

--- The player loots by itself (the game's Auto Loot setting).
function OpenButton.AutoLootOn()
    local get = (_G.C_CVar and _G.C_CVar.GetCVarBool) or _G.GetCVarBool
    if type(get) ~= "function" then return false end
    local ok, on = pcall(get, "autoLootDefault")
    return ok and on == true
end

--- A window Open after loot opened: take everything in it, as the game's
--- Auto Loot would on a click (it does not when an addon opens it). Done a
--- frame later, after Farmer has read the window.
function OpenButton:TakeLoot()
    if not self.AutoLootOn() then return end
    C_Timer.After(0, function()
        if not OpenButton.lootOpen or InCombat() then return end
        local gotCount, count = pcall(_G.GetNumLootItems)
        if not gotCount or type(count) ~= "number" or type(_G.LootSlot) ~= "function" then return end
        for slot = count, 1, -1 do pcall(_G.LootSlot, slot) end
    end)
end

--- Open the next one by itself, when that is allowed now.
function OpenButton:OpenNext()
    if not self:MayAuto() then return false end
    if InCombat() or OpenButton.Busy() or self.lootOpen then return false end
    local space = ns.Trash and ns.Trash.Space and ns.Trash.Space()
    if space and space.free < 1 then return false end
    local use = Use()
    if not use then return false end

    self:Scan(function()
        if InCombat() or OpenButton.Busy() or OpenButton.lootOpen then return end
        local item = OpenButton:Next(true)
        if not item then
            -- The next one's slot can still be locked from the last opening:
            -- look again shortly rather than stop.
            if OpenButton.lockedLoot and (OpenButton.retries or 0) < OpenButton.RETRIES then
                OpenButton.retries = (OpenButton.retries or 0) + 1
                C_Timer.After(OpenButton.AUTO_DELAY, function() OpenButton:OpenNext() end)
            end
            return
        end
        OpenButton.retries = 0
        local last = { bag = item.bag, slot = item.slot, itemID = item.itemID, count = item.count }
        OpenButton.last = last
        local called, err = pcall(use, item.bag, item.slot)
        if not called then
            OpenButton.last = nil
            if OpenButton:TestResult() ~= "works" then
                -- The game won't let addon code open things: stop trying.
                OpenButton:Learned(false, err)
                return
            end
            OpenButton:Strike(item.itemID)
            return
        end
        -- The game can refuse it with no loot window at all ("internal loot
        -- error"), and then no LOOT_CLOSED comes: look again a little later.
        C_Timer.After(OpenButton.TEST_WAIT, function()
            if OpenButton.last ~= last or OpenButton.lootOpen then return end
            OpenButton:Settle()
            OpenButton:OpenNext()
        end)
    end)
    return true
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function OpenButton:OnEnable()
    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", function()
        OpenButton:Changed()
        OpenButton:BagsTook()
    end)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function() OpenButton:Changed() end)
    -- Just before combat locks secure frames: hidden, emptied and off the
    -- panel, so the panel stays free to move.
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
        OpenButton.fighting = true
        local button = OpenButton.button
        if button then
            button:Hide()
            Clear(button)
            button:ClearAllPoints()
            button:SetParent(UIParent)
        end
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        OpenButton.fighting = false
        OpenButton:Draw()
    end)
    -- Vendors and the rest, where a /use does something else.
    for open, close in pairs(PLACES) do
        ns.RegisterEvent(self, open, function()
            OpenButton.at[open] = true
            OpenButton:Draw()
        end)
        ns.RegisterEvent(self, close, function()
            OpenButton.at[open] = nil
            OpenButton:Draw()
        end)
    end
    ns.RegisterEvent(self, "LOOT_OPENED", function()
        OpenButton.lootOpen = true
        if OpenButton.testing then OpenButton.testLoot = true end
        if OpenButton.last then OpenButton:Learned(true) end
        if OpenButton.last or OpenButton.testing then OpenButton:TakeLoot() end
    end)
    ns.RegisterEvent(self, "LOOT_CLOSED", function()
        OpenButton.lootOpen = false
        OpenButton:LootClosed()
    end)
end

ns.RegisterCommand("openbutton", L["the Open button for clams, sacks and lockboxes (on/off, auto on/off)"], function(rest)
    local word, more = ns.Util.Trim(rest):lower():match("^(%S*)%s*(.-)$")
    if word == "test" then
        OpenButton:Test()
        return
    end
    if word == "auto" then
        local on
        if more == "on" then on = true elseif more == "off" then on = false else on = not OpenButton:AutoOn() end
        OpenButton:SetAuto(on)
        if on and OpenButton:TestResult() == "blocked" then
            ns.Print(L["|cffe5604fthe game won't let Farmer open things by itself|r. The Open button still works."])
        else
            ns.Print(on and L["clams, sacks and lockboxes open after you loot."]
                or L["nothing opens by itself."])
        end
        return
    end
    local on
    if word == "on" then on = true elseif word == "off" then on = false else on = not OpenButton:Enabled() end
    OpenButton:SetEnabled(on)
    ns.Print(on and L["the Open button shows on the Kills & Loot panel while you carry a clam, sack or lockbox."]
        or L["the Open button is hidden."])
end)
