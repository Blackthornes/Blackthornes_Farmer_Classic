-- Shared test environment: enough of the WoW client to load the addon.
--
-- Not a test itself -- runtests.py only runs tools/test_*.lua -- this is what
-- each suite calls to get a loaded addon and a widget layer that remembers
-- what was written to it.
--
--   local env = dofile(lfs_cwd .. "/tools/testenv.lua")
--   local ns = env.Load()            -- data and logic
--   local ns = env.Load({ ui = true })

local env = {}

local ROOT = lfs_cwd or "."

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

-- Any method a test does not care about answers as a no-op, so the window can
-- build its panels, labels and anchors undisturbed.
local function Stub(fields)
    local frame = fields or {}

    frame._shown = frame._shown or false
    frame._height = frame._height or 300
    frame._text = frame._text or ""

    function frame:Show() self._shown = true end
    function frame:Hide() self._shown = false end
    function frame:IsShown() return self._shown end
    function frame:SetShown(value) self._shown = value and true or false end

    function frame:SetHeight(value) self._height = value end
    function frame:GetHeight() return self._height end
    function frame:SetWidth(value) self._width = value end
    function frame:GetWidth() return self._width or 500 end

    function frame:SetText(value) self._text = tostring(value or "") end
    function frame:SetTextColor(r, g, b) self._color = { r, g, b } end
    function frame:GetText() return self._text end
    -- About as wide as the game's small font: 6 pixels a character.
    function frame:GetStringWidth() return #(self._text or "") * 6 end

    function frame:SetScript(script, fn) self._scripts[script] = fn end
    function frame:GetScript(script) return self._scripts[script] end

    function frame:GetPoint()
        local p = self._point
        if p and #p == 5 then return p[1], p[2], p[3], p[4], p[5] end
        return "CENTER", nil, "CENTER", 0, 40
    end
    -- Nil until a test places the frame on screen, as before layout.
    function frame:GetLeft() return self._left end
    function frame:GetTop() return self._top end
    function frame:GetRight() return self._right end
    function frame:GetFrameLevel() return rawget(self, "_frameLevel") or 1 end
    function frame:SetFrameLevel(value) self._frameLevel = value end
    function frame:SetFrameStrata(value) self._strata = value end
    function frame:GetFrameStrata() return rawget(self, "_strata") or "MEDIUM" end

    -- Recorded so a test can check where something was anchored.
    function frame:SetPoint(...) self._point = { ... } end
    function frame:GetCenter() return self._cx or 0, self._cy or 0 end
    function frame:GetEffectiveScale() return 1 end

    function frame:RegisterEvent(event) self._events[event] = true end
    function frame:UnregisterEvent(event) self._events[event] = nil end

    function frame:CreateTexture() return Stub() end
    function frame:CreateLine() return Stub() end
    function frame:CreateFontString() return Stub() end

    function frame:SetMinMaxValues(low, high) self._min, self._max = low, high end
    function frame:SetValue(value) self._value = value end
    function frame:GetValue() return self._value or 0 end

    frame._scripts = frame._scripts or {}
    frame._events = frame._events or {}

    return setmetatable(frame, { __index = function(self, key)
        local noop = function() end
        rawset(self, key, noop)
        return noop
    end })
end

env.Stub = Stub

--------------------------------------------------------------------------------
-- Client
--------------------------------------------------------------------------------

function env.InstallClient()
    env.chat = {}

    _G.UIParent = Stub()
    -- The arrows' shared table (one Blackthornes arrow at a time) would
    -- carry one suite's arrow into the next.
    _G.BlackthornesArrows = nil

    -- Gradients: the glows, halos and fades are drawn with these.
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end

    -- A default-sized minimap, and a cursor parked somewhere unambiguous so a
    -- simulated drag lands at a known angle.
    _G.Minimap = Stub({ _width = 140, _cx = 500, _cy = 500 })
    _G.GetCursorPosition = function() return 600, 500 end

    -- A level-25 player, so difficulty colouring has something to compare to.
    -- The world below supplies the target.
    _G.UnitLevel = function(unit)
        if unit == "target" then return env.world.target and env.world.target.level or 0 end
        return 25
    end

    env.InstallWorld()

    _G.GameTooltip = Stub({
        _lines = {},
        SetOwner = function() end,
        AddLine = function(self, text) self._lines[#self._lines + 1] = text end,
    })

    -- Timers run straight away: the addon only uses them to let the minimap
    -- settle after login, and a test has nothing to wait for.
    _G.C_Timer = {
        After = function(_, fn) fn() end,
        NewTicker = function(_, fn) return Stub({ _fn = fn }) end,
    }

    _G.CreateFrame = function(_, name, parent)
        local frame = Stub({ _parent = parent })
        if name then _G[name] = frame end
        return frame
    end

    _G.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, message) env.chat[#env.chat + 1] = message end,
    }

    _G.SlashCmdList = {}

    -- Suites share one Lua state; prices one suite sets up must not leak
    -- into the next.
    _G.C_Item = nil
    _G.GetItemCount = nil
    _G.BlackthornesTS = nil
    _G.GetLootSourceInfo = nil
    _G.PlaySound = nil
    _G.PlaySoundFile = nil
    _G.GetTime = nil
    _G.SendChatMessage = nil
    -- The list the game closes with Escape.
    _G.UISpecialFrames = {}
    _G.C_ChatInfo = nil
    _G.geterrorhandler = function() return function(err) error(err, 0) end end
    _G.BlackthornesFarmerDB = nil
    _G.BlackthornesSisterNote = nil
    -- An English client unless a suite says otherwise (test_german.lua).
    _G.GetLocale = nil
    _G.C_TradeSkillUI = nil
    _G.C_CreatureInfo = nil
    _G.COPPER_AMOUNT, _G.SILVER_AMOUNT, _G.GOLD_AMOUNT = nil, nil, nil

    -- Theme asks for the default font through pcall and falls back on its own,
    -- so leaving GameFontNormal absent exercises that path.
    _G.GameFontNormal = nil
end

--------------------------------------------------------------------------------
-- The world
--
-- The loot harvester reads the game rather than the addon: a corpse, a zone, a
-- position, a loot window. `env.world` is that game, and a test moves the
-- player or swaps the corpse by assigning to it, then fires LOOT_OPENED.
--------------------------------------------------------------------------------

function env.InstallWorld()
    env.world = {
        zone = "Silverpine Forest",
        subZone = "The Sepulcher",
        mapID = 21,
        -- Fractions, the way the client reports them.
        position = { 0.45, 0.68 },
        fishing = false,
        target = { name = "Dalaran Apprentice", level = 22, dead = true, isPlayer = false },
        loot = {},
    }

    local world = env.world

    _G.GetRealZoneText = function() return world.zone end
    _G.GetSubZoneText = function() return world.subZone or "" end
    _G.IsFishingLoot = function() return world.fishing and true or false end

    _G.UnitName = function(unit)
        if unit ~= "target" then return "Blackthornes" end
        return world.target and world.target.name or nil
    end

    _G.UnitIsDead = function(unit)
        if unit ~= "target" then return false end
        return world.target ~= nil and world.target.dead ~= false
    end

    -- Every corpse is its own creature; a test that loots one twice (skinning
    -- it, or coming back for what was left) gives the target a fixed guid.
    _G.UnitGUID = function(unit)
        -- The character playing: one GUID per name, so a test that logs in
        -- as another character (a new UnitName) is another GUID.
        if unit == "player" then
            local name = _G.UnitName("player")
            return type(name) == "string" and ("Player-1-" .. name) or nil
        end
        if unit ~= "target" or not world.target then return nil end
        return world.target.guid
    end

    _G.UnitIsPlayer = function(unit)
        if unit ~= "target" then return true end
        return world.target ~= nil and world.target.isPlayer == true
    end

    _G.GetNumLootItems = function() return #world.loot end

    -- icon, name, quantity, ... -- the addon takes the second and third.
    _G.GetLootSlotInfo = function(slot)
        local item = world.loot[slot]
        if not item then return nil end
        return "Interface\\Icons\\INV_Misc_Dust_01", item.name, item.quantity or 1
    end

    _G.GetLootSlotLink = function(slot)
        local item = world.loot[slot]
        if not item or not item.id then return nil end
        return ("|c%s|Hitem:%d::::::::25::::|h[%s]|h|r"):format(item.color or "ffffffff", item.id, item.name)
    end

    -- Coins come out of a loot window in a slot of their own, alongside the
    -- items, which is how "12 Copper" ended up in the data looking like a
    -- drop. A loot entry marked money = true is one of those.
    _G.LOOT_SLOT_ITEM = 1
    _G.LOOT_SLOT_MONEY = 2

    _G.GetLootSlotType = function(slot)
        local item = world.loot[slot]
        if not item then return nil end
        if item.money then return LOOT_SLOT_MONEY end
        return LOOT_SLOT_ITEM
    end

    -- A map position comes back as a vector with GetXY, as on a live client.
    _G.C_Map = {
        GetBestMapForUnit = function() return world.mapID end,
        GetPlayerMapPosition = function()
            if not world.position then return nil end
            local x, y = world.position[1], world.position[2]
            return { GetXY = function() return x, y end }
        end,
    }
end

--- A value this client refuses to let an addon read.
--
-- Inside an instance Forever can hand back a name, a level or a quantity that
-- raises the moment addon code compares, concatenates or formats it -- retail's
-- secret values, which is what took the harvester down in Ragefire Chasm. Lua
-- cannot make a real string behave that way, so this is the nearest thing: a
-- value that raises on exactly the operations a secret value raises on, and
-- answers nothing else.
--
-- `what` only shapes the message, so a test that does catch the error can see
-- which value it came from.
function env.Secret(what)
    local function refuse(verb)
        return function()
            error(("attempt to %s a secret %s value, while execution tainted "
                .. "by 'Blackthornes_Farmer'"):format(verb, what), 0)
        end
    end

    return setmetatable({}, {
        __index = refuse("index"),
        __concat = refuse("concatenate"),
        __add = refuse("perform arithmetic on"),
        __sub = refuse("perform arithmetic on"),
        __lt = refuse("compare"),
        __le = refuse("compare"),
        __tostring = refuse("format"),
    })
end

--- Loot one corpse: point the target at `mob` and fire the loot event.
function env.Loot(ns, mob, items)
    if mob then
        env.world.target = mob
    end

    env.world.loot = items or {}
    ns.Harvest:RecordCorpse()
end

--------------------------------------------------------------------------------
-- Loading
--------------------------------------------------------------------------------

local FILES = {
    "Locale/Locale.lua",
    "Locale/deDE.lua",
    "Locale/zhCN.lua",
    "Locale/frFR.lua",
    "Locale/esES.lua",
    "Locale/ruRU.lua",
    "Core/Init.lua",
    "Core/Util.lua",
    "Core/SisterNote.lua",
    "Core/WhatsNewText.lua",
    "Core/Serialize.lua",
    "Core/Comm.lua",
    "Data/Database.lua",
    "Data/NpcNames.lua",
    "Data/ForeverNpcNames.lua",
    "Data/Zones.lua",
    "Data/NodeSpots.lua",
    "Data/Travel.lua",
    "Data/TravelZones.lua",
    "Data/Data_Mining.lua",
    "Data/Data_Herbalism.lua",
    "Data/Data_Cloth.lua",
    "Data/Data_Leather.lua",
    "Data/Data_Misc.lua",
    "Data/Data_MobDrops.lua",
    "Data/Data_ClassicDrops.lua",
    "Data/Harvest_Carryover.lua",
    "Logic/Search.lua",
    "Logic/Looted.lua",
    "Logic/Legacy.lua",
    "Logic/Harvest.lua",
    "Logic/Tracker.lua",
    "Logic/Heat.lua",
    "Logic/GameNumbers.lua",
    "Logic/Fishing.lua",
    "Logic/Gathering.lua",
    "Logic/Containers.lua",
    "Logic/Respawn.lua",
    "Logic/Value.lua",
    "Logic/Rankings.lua",
    "Logic/WorldDrops.lua",
    "Logic/RankUp.lua",
    "Logic/TopFarm.lua",
    "Logic/Goals.lua",
    "Logic/Session.lua",
    "Logic/XP.lua",
    "Logic/Stats.lua",
    "Logic/KillGoal.lua",
    "Logic/Moments.lua",
    "Logic/Butler.lua",
    "Logic/Pace.lua",
    "Logic/DisenchantFarm.lua",
    "Logic/Spots.lua",
    "Logic/Arrow.lua",
    "Logic/TomTom.lua",
    "Logic/Travel.lua",
    "Logic/Grinding.lua",
    "Logic/GrindGather.lua",
    "Logic/GatherToCap.lua",
    "Logic/Share.lua",
    "Logic/Transfer.lua",
    "Logic/GuildShare.lua",
    "Logic/Contribute.lua",
    "Logic/CSV.lua",
}

-- Written by tools/harvest_import.py from a real session, so it is present on
-- a machine that has harvested and absent in CI. Deliberately not in FILES:
-- the "all shipped data is Classic-sourced" check means the hand-written
-- files, and loading measured data into that check would defeat it.
local HARVESTED = "Data/Data_Harvested.lua"

local UI_FILES = {
    "UI/Theme.lua",
    "UI/BlizzardLook.lua",
    "UI/Widgets.lua",
    "UI/Plaque.lua",
    "UI/SeeThrough.lua",
    "UI/Titanforged.lua",
    "UI/FoldWindow.lua",
    "UI/About.lua",
    "UI/WhatsNew.lua",
    "UI/SettingsPages.lua",
    "UI/Main.lua",
    "UI/Export.lua",
    "UI/Import.lua",
    "UI/Tracker.lua",
    "UI/TrackerFX.lua",
    "UI/Goals.lua",
    "UI/LootTable.lua",
    "UI/Rankings.lua",
    "UI/RankUp.lua",
    "UI/Recap.lua",
    "UI/KillGoal.lua",
    "UI/Grinding.lua",
    "UI/GatherToCap.lua",
    "UI/Stats.lua",
    "UI/MapMarkers.lua",
    "UI/Heat.lua",
    "UI/GrindPins.lua",
    "UI/Arrow.lua",
    "UI/TravelCard.lua",
    "UI/TravelMap.lua",
    "UI/TooltipShift.lua",
    "UI/ItemTooltip.lua",
    "UI/KillTooltip.lua",
    "UI/NodeSparkle.lua",
    "UI/QuestMobs.lua",
    "UI/KillPlates.lua",
    "UI/HideMenu.lua",
    "UI/NamePrompt.lua",
    "UI/HiddenWindow.lua",
    "UI/Trash.lua",
    "UI/OpenNote.lua",
    "UI/LootFeed.lua",
    "UI/OpenButton.lua",
    "UI/FishingBar.lua",
    "UI/OneKeyFishing.lua",
    "UI/BagsFull.lua",
    "UI/Veil.lua",
    "UI/XPBar.lua",
    "UI/Settings.lua",
}

-- Forever's own data and the Legacy perks the Classic Era TOC leaves out.
-- `opts.era` loads the addon without them, as Era does (tools/test_era.lua).
env.FOREVER_DATA = {
    ["Data/ForeverNpcNames.lua"] = true,
    ["Data/Harvest_Carryover.lua"] = true,
    ["Data/Data_Harvested.lua"] = true,
    ["Logic/Legacy.lua"] = true,
}

--- Is there a generated harvest file to load?
function env.HasHarvested()
    local handle = io.open(ROOT .. "/" .. HARVESTED, "r")
    if not handle then return false end
    handle:close()
    return true
end

--- Load the addon exactly as the TOC does, and return its namespace.
--- `opts.locale` ("deDE") loads it as a client in that language would.
--- `opts.unknownEvents` ({ LOOT_CLOSED = true }) loads it on a client that
--- refuses those events, as Forever does for any event it does not know.
function env.Load(opts)
    opts = opts or {}

    env.InstallClient()
    if opts.unknownEvents then
        local unknown, create = opts.unknownEvents, _G.CreateFrame
        _G.CreateFrame = function(...)
            local frame = create(...)
            local register = frame.RegisterEvent
            frame.RegisterEvent = function(self, event, ...)
                if unknown[event] then error("unknown event " .. event) end
                return register(self, event, ...)
            end
            return frame
        end
    end
    if opts.locale then
        local locale = opts.locale
        _G.GetLocale = function() return locale end
    end

    local ns = {}

    local function Run(relative)
        local chunk = assert(loadfile(ROOT .. "/" .. relative))
        chunk("Blackthornes_Farmer", ns)
    end

    for _, file in ipairs(FILES) do
        if not (opts.era and env.FOREVER_DATA[file]) then Run(file) end
    end

    if opts.harvested and not opts.era and env.HasHarvested() then Run(HARVESTED) end

    if opts.ui then
        for _, file in ipairs(UI_FILES) do Run(file) end
    end

    -- ADDON_LOADED installs saved variables; tests that skip the event loop
    -- still need ns.db to exist.
    ns.LoadSavedVariables()

    -- Farmer leaves skinning out by default ("Hide skinning"); the suites
    -- written before it test the whole picture, so they see it all.
    -- tools/test_showskinning.lua loads with { hideSkinning = true }.
    if not opts.hideSkinning then ns.db.hideSkinning = false end

    env.ns = ns
    return ns
end

--------------------------------------------------------------------------------
-- Assertions
--------------------------------------------------------------------------------

function env.NewSuite(name)
    local suite = { name = name, checks = 0 }

    function suite.check(label, ok, detail)
        suite.checks = suite.checks + 1
        if not ok then
            error(("%s: %s%s"):format(name, label,
                detail and ("  -> " .. tostring(detail)) or ""), 0)
        end
    end

    function suite.done()
        print(("  %s: %d checks passed"):format(name, suite.checks))
    end

    return suite
end

return env
