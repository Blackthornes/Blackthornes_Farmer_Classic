-- Blackthornes Farmer -- UI/TrackerFX.lua
-- What the kills panel does when something lands (2026-09-26: "I'd
-- like it to give dopamine hits as you're killing stuff").
--
-- Before this the panel simply redrew, so nothing told your eye what had
-- changed. Now, on each redraw, whatever went up since the last one moves:
--
--   * Gathered value counts up to its new total, with a green "+38s" beside
--     it for a few seconds.
--   * Each item looted floats off the panel's right edge, "+2 Wool Cloth" in
--     its quality colour, and fades, like combat text.
--   * Any line whose count went up gets a wash that fades out: green, or the
--     item's own colour for green-and-better drops.
--   * The mob just killed glows gold and its kill count pops bigger for a
--     beat. Its progress bar toward 20 moves like a goal's
--     (2026-09-27): it slides up, the part just gained lights, a shine runs
--     along it, passing a quarter, half or three quarters pulses it gold and
--     floats "Halfway there!", and the last few float "2 more!" in green.
--   * A green-or-better drop plays the rare-drop sound, and its line pulses
--     in its quality colour with an outline, and floats as "Rare! ...".
--   * A kill streak (kills close together) pops at each kill and floats a
--     "Streak x10!" at every fifth.
--   * The kill that unlocks a mob's drop rates (or a spot's catch rates)
--     drops a gold banner over the top of the panel, with sparkles, a shine
--     across the title bar, a long gold pulse on the mob's band, and the
--     glow round the panel flaring and settling.
--   * On a card's loot icons (2026-09-28): the icon whose count went
--     up flashes and shows "+2" in its corner, and an item a mob has never
--     dropped before pops in with a gold NEW tag.
--
-- /farm effects (or Settings) picks Full, Subtle (washes and the count-up,
-- no floats or pops) or Off. The rare-drop sound has its own switch.
--
-- Everything here compares the addon's own counts from one redraw to the
-- next. Nothing reads the client, so a dungeon's secret values never reach
-- it, and anything that goes wrong is dropped rather than raised: the panel
-- is drawn by the loot handler, and an effect must never cost a kill.
--
-- It all runs off one OnUpdate on a small frame that is shown only while an
-- effect is playing, so an idle panel costs nothing per frame.

local ADDON, ns = ...
local L = ns.L

local TrackerFX = ns.NewModule("TrackerFX")

local Theme = ns.Theme
local Util = ns.Util

local LEVELS = { "off", "subtle", "full" }
TrackerFX.LEVELS = LEVELS

local LEVEL_NAMES = { off = L["Off"], subtle = L["Subtle"], full = L["Full"] }
TrackerFX.LEVEL_NAMES = LEVEL_NAMES

-- How long each effect runs, in seconds, and how strong it starts.
local GLOW_TIME = 1.2
local GLOW_ALPHA = 0.32
local BAND_ALPHA = 0.45
local POP_TIME = 0.4
local POP_SIZE = 17
local BAR_TIME = 0.45
-- The progress bar toward rates slides and shines as a goal's does.
local SLIDE_TIME = 0.5
local BAR_SHINE = 26
local COUNT_TIME = 0.7
local CHIP_TIME = 4
local FLOAT_TIME = 1.8
local FLOAT_RISE = 30
local FLOAT_GAP = 0.18
local FLOAT_SIZE = 13
local FLOAT_RARE_SIZE = 16
local MAX_FLOATS = 6

-- A loot icon: its flash, the "+2" in its corner, and how long NEW stays.
local SLOT_FLASH = 0.7
local GAIN_TIME = 2.2
local NEW_TIME = 6
local POP_GROW = 8

-- The rare-drop pulse, and the gold one on an unlocking mob's band.
local PULSE_TIME = 2.2
local PULSE_ALPHA = 0.55

-- The unlock banner: how long it stays, and its height.
local BANNER_TIME = 3.6
local BANNER_HEIGHT = 38
local SHINE_TIME = 0.9
local SHINE_WIDTH = 36
local BRIGHT_GOLD = { 1, 0.906, 0.639 }   -- #FFE7A3

-- A mob's 100th kill adds to the banner (2026-10-13): gold coins rain down
-- the panel, and its rim burns red and gold for BURN_TIME seconds and then
-- cools over BURN_FADE.
local COINS = 24
local COIN_ICON = [[Interface\Icons\INV_Misc_Coin_01]]
local COIN_FALL = 1.6
local COIN_STAGGER = 1.2
local COIN_SIZE = 14
local BURN_TIME = 10
local BURN_FADE = 1.5
local BURN_SPREAD = 26
local BURN_INNER = 10
local EMBERS = 16
TrackerFX.BURN_TIME = BURN_TIME

-- The 1000th kill takes the screen for TAKEOVER seconds: a flash, the
-- screen dimmed to DIM, gold rays turning behind the title, motes rising.
local TAKEOVER = 5.2
local DIM = 0.6
local RAYS = 12
local MOTES = 36
local GLOW_ART = ([[Interface\AddOns\%s\Media\Frame\Glow]]):format(ADDON or "Blackthornes_Farmer")
TrackerFX.TAKEOVER = TAKEOVER

-- Kill milestones between the 100th and the 1000th (2026-10-15): hearts
-- floating up the panel at 200, the Slayer sweep across the screen at 500
-- and the screen's edge flickering red at a beast's 666th.
local HEARTS = 14
local HEART_ART = ([[Interface\AddOns\%s\Media\Frame\Heart]]):format(ADDON or "Blackthornes_Farmer")
local HEART_RISE = 2.2
local HEART_STAGGER = 1.4
local HEART_PINK = { 1, 0.55, 0.75 }
local SPARK_ART = ([[Interface\AddOns\%s\Media\Frame\Sparkle]]):format(ADDON or "Blackthornes_Farmer")
local SPARKS_OUT = 18
local SPARK_TIME = 1.3
local SLAYER_TIME = 4.2
local SLAYER_DIM = 0.3
local EDGE_TIME = 1.2
local EDGE_SIZE = 180
TrackerFX.SLAYER_TIME = SLAYER_TIME
TrackerFX.EDGE_TIME = EDGE_TIME

-- What the banner says when its whole title will not fit a narrow panel.
local SHORT_TITLE = L["RATES UNLOCKED"]

-- As rates unlock, the glow round the panel flares to this many times its
-- resting brightness and settles back over this long.
local FLARE = 5
local FLARE_TIME = 1.4

-- A streak floats a cheer at every this many kills.
local STREAK_CHEER = 5

-- The soft glow art on a texture of `parent`; defined below, with the takeover.
local Glow

-- What a float says ahead of a drop's name, by quality.
local CHEERS = { [2] = L["Nice!"], [3] = L["Rare!"], [4] = L["Epic!"], [5] = L["Legendary!"] }

-- Two rare-drop sounds in a row would step on each other.
local RARE_GAP = 1

-- Uncommon (green) and better.
local RARE_QUALITY = 2

-- Rare (blue) and better: the goblin's line instead of the chime.
local VOICE_QUALITY = 3

-- Spoken lines the game already has, played by file ID (nothing is shipped):
-- a goblin vendor for a blue or better drop, the orc peon's "Work complete!"
-- for a goal reached (the owner picked both, 2026-10-12), and Whitemane's
-- "Arise, my champion!" for a mob's 100th kill (2026-10-13). Each waits
-- VOICE_GAP seconds before it can play again, so it stays a treat.
-- A beast's 666th kill gets a low, dark laugh (2026-10-15).
TrackerFX.VOICE = { drop = 550785, goal = 558132, champion = 551838, bane = 558795,
    beast = 542595 }
local VOICE_GAP = 180

-- Each row's wash, and which float labels are in the air, kept here rather
-- than as fields on the frames themselves.
local flashes = setmetatable({}, { __mode = "k" })
local busy = setmetatable({}, { __mode = "k" })
local outlines = setmetatable({}, { __mode = "k" })

TrackerFX.effects = {}
TrackerFX.clock = 0
TrackerFX.chips = {}
TrackerFX.rareAt = nil
TrackerFX.saidAt = {}

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

--- "full", "subtle" or "off". Full unless you chose otherwise.
function TrackerFX.Level()
    local level = ns.db and ns.db.trackerEffects
    if level == "off" or level == "subtle" then return level end
    return "full"
end

function TrackerFX.RareSoundOn()
    return not (ns.db and ns.db.trackerRareSound == false)
end

--- Voice lines: on unless unticked.
function TrackerFX.VoiceOn()
    return not (ns.db and ns.db.trackerVoice == false)
end

--- An item's quality, from the colour the tracker kept for it. Nil when the
--- loot window never gave a readable link (inside a dungeon, say).
function TrackerFX.QualityOf(name)
    local look = ns.Tracker:LookOf(name)
    local color = type(look.color) == "string" and look.color:lower() or nil
    if not color then return nil end

    for quality, hex in pairs(ns.Tracker.QUALITY) do
        if hex == color then return quality end
    end

    return nil
end

--------------------------------------------------------------------------------
-- The clock
--------------------------------------------------------------------------------

local function EaseOut(p)
    return 1 - (1 - p) ^ 3
end

function TrackerFX:Driver()
    if self.driver then return self.driver end

    local parent = ns.TrackerUI and ns.TrackerUI.frame or UIParent
    local driver = CreateFrame("Frame", nil, parent)
    driver:SetScript("OnUpdate", function(_, elapsed) TrackerFX:Step(elapsed) end)
    driver:Hide()

    self.driver = driver
    return driver
end

--- Start `effect`: { slot, row, key, duration, delay, apply(p), stop() }.
-- `apply` gets 0 to 1 as it runs. A new effect in the same slot replaces the
-- old one, so a second kill mid-glow restarts the glow rather than stacking.
-- `stop` puts things back when it ends early.
function TrackerFX:Start(effect)
    for index = #self.effects, 1, -1 do
        local other = self.effects[index]
        if effect.slot and other.slot == effect.slot then
            table.remove(self.effects, index)
        end
    end

    effect.age = -(effect.delay or 0)
    self.effects[#self.effects + 1] = effect
    self:Driver():Show()
end

--- A row's wash, if it has had one. For the tests.
function TrackerFX.FlashOf(row)
    local made = flashes[row]
    return made and made[1] or nil
end

--- Whether a float label is in the air.
function TrackerFX.Floating(label)
    return busy[label] == true
end

--- A pooled row can be handed a different line by a later redraw; an effect
--- still running on it would then be drawing over someone else's line.
local function Moved(effect)
    local row = effect.row
    return row ~= nil and effect.key ~= nil
        and not (row.line and row.line.key == effect.key)
end

local function Stop(effect)
    if effect.stop then pcall(effect.stop) end
end

function TrackerFX:Step(elapsed)
    elapsed = tonumber(elapsed) or 0
    self.clock = self.clock + elapsed

    local live = {}

    for _, effect in ipairs(self.effects) do
        effect.age = effect.age + elapsed

        if Moved(effect) then
            Stop(effect)
        elseif effect.age >= 0 then
            local p = math.min(1, effect.age / effect.duration)
            local ok, err = pcall(effect.apply, p)

            if not ok then
                Stop(effect)
                ns.Debug("panel effect dropped:", tostring(err))
            elseif p < 1 then
                live[#live + 1] = effect
            end
        else
            live[#live + 1] = effect
        end
    end

    self.effects = live
    if #live == 0 and self.driver then self.driver:Hide() end
end

--- End everything at once, everything back as it was. The panel was hidden,
--- or effects were turned off.
function TrackerFX:Forget()
    for _, effect in ipairs(self.effects) do Stop(effect) end
    self.effects = {}
    self.chips = {}
    self.seen = nil
    self.loot = nil
    if self.driver then self.driver:Hide() end
end

--- What the panel shows changed without anything being gained (another tab,
--- a card opened or folded, a new order): the next redraw only takes note.
function TrackerFX:Rebase()
    self.seen = nil
end

local function Color(key)
    local r, g, b = Theme.Unpack(key)
    return { r, g, b }
end

--- "ff1eff00" as three 0-1 numbers.
local function HexRGB(hex)
    if type(hex) ~= "string" or #hex ~= 8 then return nil end
    local r = tonumber(hex:sub(3, 4), 16)
    local g = tonumber(hex:sub(5, 6), 16)
    local b = tonumber(hex:sub(7, 8), 16)
    if not (r and g and b) then return nil end
    return { r / 255, g / 255, b / 255 }
end

--------------------------------------------------------------------------------
-- What changed
--------------------------------------------------------------------------------

--- Every item gathered this session, by source: kills, fishing, gathering.
-- Skinning while it is hidden, and items on the hide list, are left out
-- (Tracker.Counts), as the panel leaves them out.
local function SessionItems()
    local items = {}
    local function Take(prefix, counts)
        for name, count in pairs(counts or {}) do
            if ns.Tracker.Counts(name) then
                items[prefix .. name] = { name = name, count = count }
            end
        end
    end

    Take("kill:", ns.Tracker.sessionLoot)
    if ns.Fishing then Take("fish:", ns.Fishing.sessionCatch) end
    if ns.Gathering then Take("gather:", ns.Gathering.sessionItems) end

    return items
end

--- The panel is hidden, but a green-or-better drop still chimes: the sound
--- has its own switch and does not depend on the panel being on screen.
--- Keeps its own count of the session's items, from the first hidden
--- redraw on; the panel coming back clears it (TrackerFX:Shown).
function TrackerFX:HiddenLoot()
    local items = SessionItems()
    local was = self.hiddenLoot
    self.hiddenLoot = {}
    for key, item in pairs(items) do self.hiddenLoot[key] = item.count end
    if not was then return end

    local best = 0
    for key, item in pairs(items) do
        if item.count > (was[key] or 0) then
            best = math.max(best, TrackerFX.QualityOf(item.name) or 0)
        end
    end
    if best >= RARE_QUALITY then self:PlayRare(best) end
end

--- The panel is drawing again; the hidden count is done with.
function TrackerFX:Shown()
    self.hiddenLoot = nil
end

--- Before the panel draws `shown` (the lines that fit, out of `all`): work
--- out what went up since the last redraw, and give the value line its
--- "+38s". Returns what Play needs, or nil when there is nothing to play.
--
-- The first redraw after login, or after the panel was hidden, only takes
-- note: that is where the counts start, not something that just happened.
function TrackerFX:Prepare(all, shown)
    local seen = {}
    for _, line in ipairs(all) do
        if line.key and line.count then
            seen[line.key] = { count = line.count, bar = line.bar,
                progress = line.progress, milestone = line.milestone }
        end
        -- A card's loot icons are counted one by one.
        for _, icon in ipairs(line.icons or {}) do
            if icon.key and icon.count then seen[icon.key] = { count = icon.count } end
        end
        -- A folded card counts its bar and icons too, though they are not
        -- drawn: the kill that opens it must find where they were.
        for _, hidden in ipairs(line.hidden or {}) do
            seen[hidden.key] = { count = hidden.count, progress = hidden.progress,
                milestone = hidden.milestone }
        end
    end

    local items = SessionItems()
    local previous, previousItems = self.seen, self.loot
    self.seen, self.loot = seen, items

    if not previous then return nil end

    local plan = { lines = {}, items = {}, icons = {}, shown = shown }

    for key, entry in pairs(items) do
        local before = previousItems and previousItems[key] and previousItems[key].count or 0
        local count = tonumber(entry.count) or 0

        if count > before then
            plan.items[#plan.items + 1] = { key = key, name = entry.name,
                delta = count - before, quality = TrackerFX.QualityOf(entry.name) }
        end
    end

    -- Best first, so the rare one floats first and is never the one cut.
    table.sort(plan.items, function(a, b)
        local qa, qb = a.quality or 1, b.quality or 1
        if qa ~= qb then return qa > qb end
        return a.name < b.name
    end)

    -- Icons: one whose count went up, and one this mob never dropped before
    -- (its first, and just looted).
    local gained = {}
    for _, item in ipairs(plan.items) do gained[item.name] = true end

    for index, line in ipairs(shown) do
        for slot, icon in ipairs(line.icons or {}) do
            local was = icon.key and previous[icon.key]
            if was and (icon.count or 0) > (was.count or 0) then
                plan.icons[#plan.icons + 1] = { index = index, slot = slot, icon = icon,
                    delta = icon.count - was.count }
            elseif not was and icon.count == 1 and gained[icon.item] then
                plan.icons[#plan.icons + 1] = { index = index, slot = slot, icon = icon,
                    delta = 1, new = true }
            end
        end
    end

    for index, line in ipairs(shown) do
        local was = line.key and previous[line.key]
        if line.key and line.count and (not was or line.count > was.count) then
            plan.lines[#plan.lines + 1] = { index = index, line = line, was = was }

            if line.key == "total" and was and TrackerFX.Level() ~= "off" then
                self.chips.total = { text = "+" .. ns.Value.Coins(line.count - was.count),
                    until_ = self.clock + CHIP_TIME }
            end
        end
    end

    -- The "+38s" stays for a few seconds, through any redraw in between.
    local chip = self.chips.total
    if chip and self.clock < chip.until_ then
        for _, line in ipairs(shown) do
            if line.key == "total" then line.badge = chip.text end
        end
    else
        self.chips.total = nil
    end

    return plan
end

--- After the panel drew: play what Prepare found. `rowFor(index)` is the
--- row drawing shown line `index`.
function TrackerFX:Play(plan, rowFor)
    if not plan then return end

    local best = 0
    for _, item in ipairs(plan.items) do
        best = math.max(best, item.quality or 0)
    end
    if best >= RARE_QUALITY then self:PlayRare(best) end

    local level = TrackerFX.Level()
    if level == "off" then return end

    local rows = {}

    for _, gain in ipairs(plan.lines) do
        local row = rowFor(gain.index)
        if row then
            rows[gain.line.key] = row
            self:LineGained(row, gain.line, gain.was, level)
        end
    end

    -- A card's icons: their row is the anchor for their floats too.
    for _, gain in ipairs(plan.icons or {}) do
        local row = rowFor(gain.index)
        local slot = row and row.slots and row.slots[gain.slot]
        if slot and slot:IsShown() then
            rows["loot:" .. gain.icon.item] = rows["loot:" .. gain.icon.item] or row
            self:SlotGained(slot, gain, level)
        end
    end

    -- A green-or-better drop pulses on every line it is drawn on, counted
    -- or not: a mob past 20 kills shows it as a rate.
    for _, item in ipairs(plan.items) do
        if (item.quality or 0) >= RARE_QUALITY then
            local rgb = HexRGB(ns.Tracker:LookOf(item.name).color) or Color("good")
            for index, line in ipairs(plan.shown or {}) do
                local row = line.item == item.name and line.key and rowFor(index)
                if row then self:Pulse(row, line.key, rgb) end
            end
        end
    end

    if level == "full" then
        -- The top row of the column. The gathered value in the title bar
        -- stops short of the X, so floats would start on top of it.
        local first = rowFor(1)
        if first and first.line and first.line.key == "total" then first = rowFor(2) or first end

        for index = 1, math.min(#plan.items, MAX_FLOATS) do
            local item = plan.items[index]
            local name = item.key:match("^kill:(.+)$")
            self:Float(item, (name and rows["loot:" .. name]) or first, (index - 1) * FLOAT_GAP)
        end
    end
end

--------------------------------------------------------------------------------
-- The effects
--------------------------------------------------------------------------------

--- The wash over a row, and a brighter edge down its left side.
local function Flash(row)
    local made = flashes[row]
    if made then return made[1], made[2] end

    local flash = row:CreateTexture(nil, "BORDER")
    flash:SetAllPoints(row)
    pcall(flash.SetBlendMode, flash, "ADD")
    flash:SetAlpha(0)

    local edge = row:CreateTexture(nil, "ARTWORK")
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("BOTTOMLEFT")
    edge:SetWidth(2)
    edge:SetAlpha(0)

    flashes[row] = { flash, edge }
    return flash, edge
end

function TrackerFX:Glow(row, key, rgb, peak)
    local flash, edge = Flash(row)
    flash:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
    edge:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)

    local function Hide()
        flash:SetAlpha(0)
        edge:SetAlpha(0)
    end

    -- A plain glow taking over from a pulse leaves no outline behind.
    for _, line in ipairs(outlines[row] or {}) do line:SetAlpha(0) end

    self:Start({ slot = flash, row = row, key = key, duration = GLOW_TIME,
        apply = function(p)
            local alpha = peak * (1 - p) ^ 2
            flash:SetAlpha(alpha)
            edge:SetAlpha(math.min(1, alpha * 2.5))
        end,
        stop = Hide })
end

--- A one-pixel outline round a row, for the pulse.
local function Outline(row)
    local made = outlines[row]
    if made then return made end

    made = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = row:CreateTexture(nil, "ARTWORK")
        if side == "TOP" or side == "BOTTOM" then
            edge:SetPoint(side .. "LEFT")
            edge:SetPoint(side .. "RIGHT")
            edge:SetHeight(1)
        else
            edge:SetPoint("TOP" .. side)
            edge:SetPoint("BOTTOM" .. side)
            edge:SetWidth(1)
        end
        edge:SetAlpha(0)
        made[#made + 1] = edge
    end

    outlines[row] = made
    return made
end

--- A longer, beating glow with an outline: a rare drop's line in its
--- quality colour, or a mob's band in gold as its rates unlock.
function TrackerFX:Pulse(row, key, rgb, peak)
    peak = peak or PULSE_ALPHA

    local flash, edge = Flash(row)
    local outline = Outline(row)
    flash:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
    edge:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
    for _, line in ipairs(outline) do line:SetColorTexture(rgb[1], rgb[2], rgb[3], 1) end

    local function Alpha(alpha)
        flash:SetAlpha(alpha)
        edge:SetAlpha(math.min(1, alpha * 2))
        for _, line in ipairs(outline) do line:SetAlpha(math.min(1, alpha * 1.8)) end
    end

    self:Start({ slot = flash, row = row, key = key, duration = PULSE_TIME,
        apply = function(p)
            -- Three beats, each a little weaker than the last.
            local beat = 0.55 + 0.45 * math.cos(p * 6 * math.pi)
            Alpha(peak * (1 - p) ^ 1.5 * beat)
        end,
        stop = function() Alpha(0) end })
end

--- The kill count, bigger for a beat and back.
function TrackerFX:Pop(row, key)
    local label = row.right
    local small = Theme.sizes.small

    local function Size(size)
        pcall(label.SetFont, label, Theme.FONT, size, "")
    end

    self:Start({ slot = label, row = row, key = key, duration = POP_TIME,
        apply = function(p)
            Size(small + (POP_SIZE - small) * (1 - EaseOut(p)))
        end,
        stop = function() Size(small) end })
end

--- The bar under the value, sliding from where it was to where it is.
function TrackerFX:Slide(row, key, from, to)
    local fill = row.fill
    local width = ns.TrackerUI.BAR

    self:Start({ slot = fill, row = row, key = key, duration = BAR_TIME,
        apply = function(p)
            local fraction = math.min(1, from + (to - from) * EaseOut(p))
            fill:SetWidth(math.max(1, width * fraction))
        end })
end

-- What a mark on the progress bar floats as it is passed.
local MARK_CHEERS = { "25%!", L["Halfway there!"], "75%!" }

--- A band's progress bar went up: the goal bar's slide, lit gain and shine,
--- a gold pulse at each mark, and the countdown floating in the last stretch.
function TrackerFX:Progress(row, line, was, level)
    local UI = ns.TrackerUI
    local bar = row.progress
    local key = line.key
    if not (UI and bar) then return end

    local from = was and tonumber(was.progress) or 0
    local to = tonumber(line.progress) or 0
    if to <= from then return end

    local width = UI:ProgressWidth(row)
    local full = level == "full"

    local slide = { slot = bar.fill, row = row, key = key, duration = SLIDE_TIME,
        apply = function(p)
            UI:SetProgress(row, from + (to - from) * EaseOut(p), line.final)
        end,
        stop = function()
            if row.line and row.line.key == key then UI:SetProgress(row, to, line.final) end
        end }
    self:Start(slide)
    -- From where it was straight away, so the new length never shows first.
    pcall(slide.apply, 0)

    bar.fresh:ClearAllPoints()
    bar.fresh:SetPoint("TOPLEFT", bar.track, "TOPLEFT", width * from, 0)
    bar.fresh:SetWidth(math.max(1, width * (to - from)))
    self:Start({ slot = bar.fresh, row = row, key = key, duration = GLOW_TIME,
        delay = SLIDE_TIME * 0.6,
        apply = function(p) bar.fresh:SetAlpha(0.6 * (1 - p) ^ 2) end,
        stop = function() bar.fresh:SetAlpha(0) end })

    if full then
        local reach = math.max(BAR_SHINE, width * to)
        bar.shine:SetWidth(BAR_SHINE)
        self:Start({ slot = bar.shine, row = row, key = key, duration = SHINE_TIME,
            delay = SLIDE_TIME * 0.5,
            apply = function(p)
                bar.shine:ClearAllPoints()
                bar.shine:SetPoint("TOPLEFT", bar.track, "TOPLEFT",
                    math.max(0, (reach - BAR_SHINE) * p), 0)
                bar.shine:SetAlpha(0.55 * math.sin(p * math.pi))
            end,
            stop = function() bar.shine:SetAlpha(0) end })
    end

    local passed = was ~= nil and (line.milestone or 0) > (was.milestone or 0)
    if passed then
        self:Pulse(row, key, BRIGHT_GOLD, PULSE_ALPHA)
    end

    if not (full and was) then return end

    if passed then
        self:FloatText(Util.Colored("accent", MARK_CHEERS[line.milestone] or L["Nice!"]),
            row, 0.35, FLOAT_RARE_SIZE)
    elseif line.final then
        local left = (line.target or 0) - (line.have or 0)
        self:FloatText(Util.Colored("good", L.Format("%d more!", left)), row, 0.35, 15)
    end
end

--- Gathered value, counting up to its new total.
function TrackerFX:CountUp(row, key, from, to)
    local label = row.right

    self:Start({ slot = "count", row = row, key = key, duration = COUNT_TIME,
        apply = function(p)
            label:SetText(ns.Value.Coins(from + (to - from) * EaseOut(p)))
        end,
        stop = function()
            -- Only if the row still shows the value: it may show another
            -- line by now.
            if row.line and row.line.key == key then label:SetText(ns.Value.Coins(to)) end
        end })

    -- The "+38s" beside it fades out at the end of its few seconds.
    local badge = row.badge
    self:Start({ slot = "chip", row = row, key = key, duration = CHIP_TIME,
        apply = function(p)
            local fade = 0.8
            badge:SetAlpha(p < fade and 1 or 1 - (p - fade) / (1 - fade))
            if p >= 1 then
                badge:SetText("")
                badge:Hide()
                badge:SetAlpha(1)
            end
        end,
        stop = function() badge:SetAlpha(1) end })
end

function TrackerFX:LineGained(row, line, was, level)
    local key = line.key

    if key == "total" then
        self:Glow(row, key, Color("good"), GLOW_ALPHA)
        if was then self:CountUp(row, key, was.count, line.count) end
        return
    end

    if key == "streak" then
        local cheer = was and line.count % STREAK_CHEER == 0
        self:Glow(row, key, Color("accent"), cheer and PULSE_ALPHA or BAND_ALPHA)

        if level == "full" then
            self:Pop(row, key)
            if cheer then
                self:FloatText(Util.Colored("accent", L.Format("Streak x%d!", line.count)),
                    row, 0, FLOAT_RARE_SIZE)
            end
        end
        return
    end

    if line.style == "progress" then
        self:Progress(row, line, was, level)
        return
    end

    if line.style == "mob" then
        self:Glow(row, key, Color("accent"), BAND_ALPHA)
        if level == "full" then self:Pop(row, key) end

        if line.bar and was and was.bar and line.bar > was.bar then
            self:Slide(row, key, was.bar, line.bar)
        end
        return
    end

    -- An item in green or better washes in its own colour.
    local rgb = Color("good")
    if line.item and (TrackerFX.QualityOf(line.item) or 0) >= RARE_QUALITY then
        rgb = HexRGB(ns.Tracker:LookOf(line.item).color) or rgb
    end

    self:Glow(row, key, rgb, GLOW_ALPHA)
end

--------------------------------------------------------------------------------
-- A card's loot icons
--------------------------------------------------------------------------------

--- An icon's count went up, or it is new: it flashes (in its quality
--- colour for green and better), "+2" rises in its corner, and a first drop
--- pops in bigger with a gold NEW tag.
function TrackerFX:SlotGained(slot, gain, level)
    local icon = gain.icon
    local key = icon.key
    local rgb = Color("good")
    local quality = TrackerFX.QualityOf(icon.item) or 0
    if quality >= RARE_QUALITY then
        rgb = HexRGB(ns.Tracker:LookOf(icon.item).color) or rgb
    end
    if gain.new then rgb = BRIGHT_GOLD end

    slot.flash:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
    slot.glow:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
    local rest = tonumber(rawget(slot, "rest")) or 0

    self:Start({ slot = slot.flash, row = slot, key = key, duration = SLOT_FLASH * 2,
        apply = function(p)
            slot.flash:SetAlpha(0.65 * (1 - p) ^ 2)
            slot.glow:SetAlpha(rest + (0.9 - rest) * (1 - p) ^ 1.5)
        end,
        stop = function()
            slot.flash:SetAlpha(0)
            slot.glow:SetAlpha(rest)
        end })

    if gain.new then
        slot.tag:SetAlpha(1)
        slot.tagText:SetAlpha(1)
        self:Start({ slot = slot.tag, row = slot, key = key, duration = NEW_TIME,
            apply = function(p)
                local alpha = p < 0.8 and 1 or (1 - p) / 0.2
                slot.tag:SetAlpha(alpha)
                slot.tagText:SetAlpha(alpha)
            end,
            stop = function()
                slot.tag:SetAlpha(0)
                slot.tagText:SetAlpha(0)
            end })

        if level == "full" then
            -- It swells from its middle, over its neighbours, rather than
            -- from its top-left corner down onto the next icon.
            -- Its resting level is the one the panel gives every slot, so a
            -- second pop on the same slot can never stack the raise.
            local size = ns.TrackerUI.SLOT
            local row = slot:GetParent()
            local level = (row and row:GetFrameLevel() or slot:GetFrameLevel()) + 2

            -- Set from the spot the panel last placed it in, never moved by a
            -- difference: a redraw mid-pop, or a second pop replacing this
            -- one, can't leave it off by a few pixels.
            local function Shift(to)
                local x, y = slot.baseX, slot.baseY
                local anchor = slot.baseTo or row
                if type(x) ~= "number" or type(y) ~= "number" or not anchor then return end
                slot:ClearAllPoints()
                slot:SetPoint("TOPLEFT", anchor, "TOPLEFT", x - to, y + to)
            end

            slot:SetFrameLevel(level + 2)
            self:Start({ slot = slot, row = slot, key = key, duration = POP_TIME * 1.5,
                apply = function(p)
                    local grow = POP_GROW * (1 - EaseOut(p))
                    slot:SetSize(size + grow, size + grow)
                    Shift(grow / 2)
                    if p >= 1 then slot:SetFrameLevel(level) end
                end,
                stop = function()
                    slot:SetSize(size, size)
                    Shift(0)
                    slot:SetFrameLevel(level)
                end })
        end
        return
    end

    slot.gain:SetText(("+%d"):format(gain.delta))
    self:Start({ slot = slot.gain, row = slot, key = key, duration = GAIN_TIME,
        apply = function(p)
            slot.gain:SetAlpha(p < 0.1 and p / 0.1 or (p < 0.6 and 1 or (1 - p) / 0.4))
        end,
        stop = function() slot.gain:SetAlpha(0) end })
end

--------------------------------------------------------------------------------
-- Floating loot
--------------------------------------------------------------------------------

function TrackerFX:FloatLabel()
    self.floats = self.floats or {}

    for _, label in ipairs(self.floats) do
        if not busy[label] then return label end
    end

    if #self.floats >= MAX_FLOATS then
        -- All in the air: take the oldest.
        local label = table.remove(self.floats, 1)
        self.floats[#self.floats + 1] = label
        return label
    end

    if not self.holder then
        -- Over the panel, the size of it, so the labels draw above its rows.
        local panel = ns.TrackerUI.frame
        self.holder = CreateFrame("Frame", nil, panel)
        self.holder:SetAllPoints(panel)
        self.holder:SetFrameLevel(panel:GetFrameLevel() + 10)
    end
    local label = Theme.CreateLabel(self.holder, "normal", "text")
    label:Hide()
    self.floats[#self.floats + 1] = label
    return label
end

--- "+2 Wool Cloth" rising off the panel's right edge beside `anchor`; a
--- green-or-better drop bigger, with a cheer ahead of it ("Rare! ...").
function TrackerFX:Float(item, anchor, delay)
    local color = ns.Tracker:LookOf(item.name).color or ns.Util.ItemHex(item.name)
    local text = ("+%d %s"):format(item.delta, item.name)

    local cheer = CHEERS[item.quality or 0]
    if cheer then text = cheer .. " " .. text end

    if type(color) == "string" and #color == 8 then
        text = ("|c%s%s|r"):format(color, text)
    end

    local rare = (item.quality or 0) >= RARE_QUALITY
    self:FloatText(text, anchor, delay, rare and FLOAT_RARE_SIZE or FLOAT_SIZE)
end

--- Any text rising off the panel's right edge beside `anchor`, and fading.
function TrackerFX:FloatText(text, anchor, delay, size)
    if not anchor then return end

    local label = self:FloatLabel()
    pcall(label.SetFont, label, Theme.FONT, size or FLOAT_SIZE, "OUTLINE")
    label:SetText(text)
    label:SetAlpha(0)
    busy[label] = true

    local function Place(rise)
        label:ClearAllPoints()
        label:SetPoint("LEFT", anchor, "RIGHT", 8, rise)
    end

    Place(0)
    label:Show()

    self:Start({ slot = label, duration = FLOAT_TIME, delay = delay,
        apply = function(p)
            Place(FLOAT_RISE * EaseOut(p))
            label:SetAlpha(p < 0.15 and p / 0.15 or (1 - (p - 0.15) / 0.85))
            if p >= 1 then
                label:Hide()
                busy[label] = nil
            end
        end,
        stop = function()
            label:Hide()
            busy[label] = nil
        end })
end

--------------------------------------------------------------------------------
-- The unlock banner
--------------------------------------------------------------------------------

-- Where the sparkles sit on the banner, as fractions across and down.
local SPARKS = {
    { 0.04, 0.2 }, { 0.12, 0.85 }, { 0.3, 0.1 }, { 0.62, 0.9 },
    { 0.8, 0.12 }, { 0.95, 0.75 }, { 0.5, 0.05 }, { 0.2, 0.5 },
}

function TrackerFX:Banner()
    if self.banner then return self.banner end

    local panel = ns.TrackerUI.frame
    -- Over the top of the column, under the tabs.
    local header = ns.TrackerUI.TOP or ns.TrackerUI.HEADER

    local banner = CreateFrame("Frame", nil, panel)
    banner:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -(header + 4))
    banner:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -(header + 4))
    banner:SetHeight(BANNER_HEIGHT)
    banner:SetFrameLevel(panel:GetFrameLevel() + 12)

    Theme.Fill(banner, "window", 0.96)
    Theme.Border(banner, "accent")

    -- A gold wash that breathes behind the words.
    local wash = banner:CreateTexture(nil, "BORDER")
    wash:SetAllPoints(banner)
    wash:SetColorTexture(Theme.Unpack("accent"))
    pcall(wash.SetBlendMode, wash, "ADD")
    banner.wash = wash

    local title = Theme.CreateLabel(banner, "normal", "accent", "CENTER")
    pcall(title.SetFont, title, Theme.FONT, Theme.sizes.large, "OUTLINE")
    title:SetTextColor(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1)
    title:SetPoint("TOPLEFT", 6, -5)
    title:SetPoint("TOPRIGHT", -6, -5)
    banner.title = title

    local subject = Theme.CreateLabel(banner, "small", "text", "CENTER")
    subject:SetPoint("BOTTOMLEFT", 6, 5)
    subject:SetPoint("BOTTOMRIGHT", -6, 5)
    banner.subject = subject

    banner.sparks = {}
    for index = 1, #SPARKS do
        local spark = banner:CreateTexture(nil, "OVERLAY")
        spark:SetSize(3, 3)
        spark:SetColorTexture(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1)
        pcall(spark.SetBlendMode, spark, "ADD")
        banner.sparks[index] = spark
    end

    -- The shine that sweeps across the title bar. The banner's own, though
    -- it sits over the header: the header is a frame above the panel, so a
    -- texture of the panel's would draw underneath it.
    local shine = banner:CreateTexture(nil, "OVERLAY")
    shine:SetHeight(header)
    shine:SetWidth(SHINE_WIDTH)
    shine:SetColorTexture(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1)
    pcall(shine.SetBlendMode, shine, "ADD")
    shine:SetAlpha(0)
    banner.shine = shine

    banner:Hide()
    self.banner = banner
    return banner
end

--- The banner's second line for a label `room` pixels wide: whole if it fits,
--- else the name alone. "Defias Pillager  |  20 kills" can need more room
--- than a narrow panel has, and the name is the part that matters; the
--- panel is already as wide as the name needs, for the card under it.
function TrackerFX.FitSubject(subject, room)
    if Theme.TextWidth("small", subject) <= room then return subject end
    return subject:match("^(.-)  |  ") or subject
end

--- The banner's title for a label `room` pixels wide, and the size to draw
--- it at: whole and large if it fits, else whole a size down, else the
--- short "RATES UNLOCKED". "GATHER RATES UNLOCKED" in large outlined
--- capitals needs more room than a narrow panel has, and ended in "...".
function TrackerFX.FitTitle(title, room, short)
    short = short or SHORT_TITLE
    local tries = { { title, "large" }, { title, "normal" },
        { short, "large" }, { short, "normal" }, { short, "small" } }

    for _, try in ipairs(tries) do
        -- The outline takes a pixel each side.
        if Theme.TextWidth(try[2], try[1]) + 2 <= room then
            return try[1], Theme.sizes[try[2]]
        end
    end
    return short, Theme.sizes.small or Theme.sizes.normal
end

--- The glow round the panel flares and settles back, the way a window's
--- does as it opens. Through Motion, so Off leaves it at rest, and in the
--- slot the panel's fade-up flares in, so the two never fight.
function TrackerFX:Flare()
    local panel = ns.TrackerUI and ns.TrackerUI.frame
    local rest = panel and tonumber(panel.haloRest)
    if not (rest and ns.Motion) then return end

    local peak = rest * FLARE
    ns.Motion:Run(panel, "halo", FLARE_TIME, function(p)
        Theme.SetHalo(panel, peak + (rest - peak) * p)
    end)
end

--- A mob's drop rates (or a spot's catch rates) just unlocked: `info` is
--- { title, subject, key }. Tracker:Fanfare calls it with the sound.
function TrackerFX:Unlocked(info)
    local level = TrackerFX.Level()
    if level == "off" then return end

    -- The 1000th takes the whole screen, panel or no panel, and needs no
    -- banner of its own on the panel.
    -- A beast's 666th: no banner, only the screen's edge, panel or none.
    if info.beast then
        if level == "full" then self:RedEdge() end
        return
    end

    if info.bane or info.slayer then
        if level == "full" then self:Takeover(info) end
        if info.bane then
            if ns.TrackerUI and ns.TrackerUI.frame and ns.TrackerUI.frame:IsShown() then
                self:Flare()
                self:PulseUnlocked(info)
            end
            return
        end
    end
    if not (ns.TrackerUI and ns.TrackerUI.frame and ns.TrackerUI.frame:IsShown()) then return end

    -- Subtle keeps the long gold pulse on the band and the flare round the
    -- panel, as it keeps the goals panel's flares and every window's; the
    -- banner, sparkles and shine are Full's.
    if level ~= "full" then
        self:Flare()
        self:PulseUnlocked(info)
        return
    end

    local banner = self:Banner()
    banner:SetAlpha(0)
    banner:Show()

    local ok, width = pcall(banner.GetWidth, banner)
    width = ok and tonumber(width) or 200

    -- Its labels run 6 pixels in from each side.
    -- A milestone's title never turns into "RATES UNLOCKED": it goes a size
    -- down instead.
    local title, size = TrackerFX.FitTitle(info.title or SHORT_TITLE, width - 12,
        info.own and info.title or nil)
    pcall(banner.title.SetFont, banner.title, Theme.FONT, size, "OUTLINE")
    banner.title:SetText(title)
    banner.subject:SetText(TrackerFX.FitSubject(info.subject or "", width - 12))

    for index, spark in ipairs(banner.sparks) do
        spark:ClearAllPoints()
        spark:SetPoint("CENTER", banner, "TOPLEFT", SPARKS[index][1] * width,
            -SPARKS[index][2] * BANNER_HEIGHT)
    end

    local panel = ns.TrackerUI.frame
    local okPanel, panelWidth = pcall(panel.GetWidth, panel)
    panelWidth = okPanel and tonumber(panelWidth) or width

    self:Start({ slot = "banner", duration = BANNER_TIME,
        apply = function(p)
            -- In fast, a moment to read it, out slowly.
            local alpha = p < 0.06 and p / 0.06 or (p > 0.8 and (1 - p) / 0.2 or 1)
            banner:SetAlpha(alpha)
            banner.wash:SetAlpha(0.12 + 0.1 * math.sin(p * 8 * math.pi))

            for index, spark in ipairs(banner.sparks) do
                local twinkle = 0.5 + 0.5 * math.sin(p * 14 * math.pi + index * 1.7)
                spark:SetAlpha(twinkle * alpha)
            end

            -- The shine crosses the title bar once, in the first moment.
            local sweep = p * BANNER_TIME / SHINE_TIME
            if sweep < 1 then
                banner.shine:ClearAllPoints()
                banner.shine:SetPoint("TOPLEFT", panel, "TOPLEFT",
                    (panelWidth - SHINE_WIDTH) * sweep, 0)
                banner.shine:SetAlpha(0.35 * math.sin(sweep * math.pi))
            else
                banner.shine:SetAlpha(0)
            end

            if p >= 1 then banner:Hide() end
        end,
        stop = function()
            banner:Hide()
            banner.shine:SetAlpha(0)
        end })

    self:Flare()
    self:PulseUnlocked(info)

    if info.champion then
        self:CoinRain()
        self:Burn()
    end
    if info.cute then self:Hearts() end
    if info.slayer then self:SparkBurst() end
end

--- Pink hearts float up the panel from its foot, swaying, and fade.
function TrackerFX:Hearts()
    local panel = ns.TrackerUI.frame

    local hearts = self.hearts
    if not hearts then
        hearts = CreateFrame("Frame", nil, panel)
        hearts:SetAllPoints(panel)
        hearts:SetFrameLevel(panel:GetFrameLevel() + 14)
        hearts.list = {}
        for index = 1, HEARTS do
            local heart = hearts:CreateTexture(nil, "OVERLAY")
            heart:SetTexture(HEART_ART)
            pcall(heart.SetVertexColor, heart, HEART_PINK[1], HEART_PINK[2], HEART_PINK[3])
            hearts.list[index] = heart
        end
        self.hearts = hearts
    end

    local okW, width = pcall(panel.GetWidth, panel)
    local okH, height = pcall(panel.GetHeight, panel)
    width = okW and tonumber(width) or 200
    height = okH and tonumber(height) or 300

    for index, heart in ipairs(hearts.list) do
        heart.x = (index - 0.5) / HEARTS * width + math.random(-10, 10)
        heart.delay = math.random() * HEART_STAGGER
        heart.size = 10 + math.random(0, 8)
        heart.sway = math.random() * 6.28
        heart:SetSize(heart.size, heart.size)
        heart:Hide()
    end
    hearts:Show()

    local total = HEART_STAGGER + HEART_RISE
    self:Start({ slot = "hearts", duration = total,
        apply = function(p)
            local now = p * total
            for _, heart in ipairs(hearts.list) do
                local t = (now - heart.delay) / HEART_RISE
                if t < 0 or t >= 1 then
                    heart:Hide()
                else
                    local y = height * 0.15 + height * 0.7 * t
                    heart:ClearAllPoints()
                    heart:SetPoint("CENTER", hearts, "BOTTOMLEFT",
                        heart.x + 8 * math.sin(t * 6 + heart.sway), y)
                    -- A little pop as it appears, then up and away.
                    local grow = t < 0.12 and t / 0.12 or 1
                    heart:SetSize(heart.size * grow, heart.size * grow)
                    heart:SetAlpha(t > 0.6 and (1 - t) / 0.4 or 1)
                    heart:Show()
                end
            end
            if p >= 1 then hearts:Hide() end
        end,
        stop = function() hearts:Hide() end })
end

--- Gold sparks burst out of the panel's middle in every direction and fade.
function TrackerFX:SparkBurst()
    local panel = ns.TrackerUI.frame

    local burst = self.burst
    if not burst then
        burst = CreateFrame("Frame", nil, panel)
        burst:SetAllPoints(panel)
        burst:SetFrameLevel(panel:GetFrameLevel() + 14)
        burst.list = {}
        for index = 1, SPARKS_OUT do
            local spark = burst:CreateTexture(nil, "OVERLAY")
            spark:SetTexture(SPARK_ART)
            pcall(spark.SetBlendMode, spark, "ADD")
            pcall(spark.SetVertexColor, spark, BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3])
            burst.list[index] = spark
        end
        self.burst = burst
    end

    local okW, width = pcall(panel.GetWidth, panel)
    local okH, height = pcall(panel.GetHeight, panel)
    width = okW and tonumber(width) or 200
    height = okH and tonumber(height) or 300

    for index, spark in ipairs(burst.list) do
        spark.angle = (index - 1) / SPARKS_OUT * 2 * math.pi + math.random() * 0.3
        spark.reach = 0.6 + math.random() * 0.6
        spark.size = 14 + math.random(0, 10)
        spark:Hide()
    end
    burst:Show()

    self:Start({ slot = "burst", duration = SPARK_TIME,
        apply = function(p)
            local out = EaseOut(p)
            for _, spark in ipairs(burst.list) do
                local dx = math.cos(spark.angle) * width * 0.6 * spark.reach * out
                local dy = math.sin(spark.angle) * height * 0.35 * spark.reach * out
                spark:ClearAllPoints()
                spark:SetPoint("CENTER", burst, "CENTER", dx, dy)
                spark:SetSize(spark.size * (1 - 0.5 * p), spark.size * (1 - 0.5 * p))
                spark:SetAlpha(1 - p)
                spark:Show()
            end
            if p >= 1 then burst:Hide() end
        end,
        stop = function() burst:Hide() end })
end

--- A beast's 666th kill: the edges of the screen flicker red for a moment.
--- Its own frame over everything, taking no mouse.
function TrackerFX:RedEdge()
    local edge = self.edge
    if not edge then
        edge = CreateFrame("Frame", nil, UIParent)
        edge:SetAllPoints(UIParent)
        pcall(edge.SetFrameStrata, edge, "FULLSCREEN_DIALOG")
        edge:EnableMouse(false)

        -- Each side a strip of the soft glow, brightest at the screen's edge.
        local sides = {
            { "TOPLEFT", "TOPRIGHT", 0.49, 0.51, 0.5, 1, height = true },
            { "BOTTOMLEFT", "BOTTOMRIGHT", 0.49, 0.51, 0, 0.5, height = true },
            { "TOPLEFT", "BOTTOMLEFT", 0.5, 1, 0.49, 0.51 },
            { "TOPRIGHT", "BOTTOMRIGHT", 0, 0.5, 0.49, 0.51 },
        }
        edge.strips = {}
        for index, side in ipairs(sides) do
            local strip = Glow(edge, "ARTWORK")
            pcall(strip.SetTexCoord, strip, side[3], side[4], side[5], side[6])
            strip:SetVertexColor(0.9, 0.05, 0.05)
            strip:SetPoint(side[1], edge, side[1], 0, 0)
            strip:SetPoint(side[2], edge, side[2], 0, 0)
            if side.height then strip:SetHeight(EDGE_SIZE) else strip:SetWidth(EDGE_SIZE) end
            edge.strips[index] = strip
        end

        edge:SetScript("OnUpdate", function(frame, elapsed)
            local ok, err = pcall(TrackerFX.StepEdge, TrackerFX, elapsed)
            if not ok then
                frame:Hide()
                ns.Debug("red edge dropped:", tostring(err))
            end
        end)
        edge:Hide()
        self.edge = edge
    end

    edge.age = 0
    edge:Show()
    self:StepEdge(0)
end

function TrackerFX:StepEdge(elapsed)
    local edge = self.edge
    if not edge then return end
    edge.age = edge.age + (tonumber(elapsed) or 0)
    local t = edge.age

    if t >= EDGE_TIME then
        edge:Hide()
        return
    end

    -- Three quick flickers, each a little weaker, never a hard strobe.
    local beat = math.abs(math.sin(t / EDGE_TIME * 3 * math.pi))
    local alpha = 0.75 * beat * (1 - 0.5 * t / EDGE_TIME)
    for _, strip in ipairs(edge.strips) do strip:SetAlpha(alpha) end
end

--- Coins tumble down the panel, a few at a time, and fade near its foot.
function TrackerFX:CoinRain()
    local panel = ns.TrackerUI.frame

    local rain = self.rain
    if not rain then
        rain = CreateFrame("Frame", nil, panel)
        rain:SetAllPoints(panel)
        rain:SetFrameLevel(panel:GetFrameLevel() + 14)
        rain.coins = {}
        for index = 1, COINS do
            local coin = rain:CreateTexture(nil, "OVERLAY")
            coin:SetTexture(COIN_ICON)
            -- The icon's own border trimmed away, so it reads as a coin.
            coin:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            rain.coins[index] = coin
        end
        self.rain = rain
    end

    local okW, width = pcall(panel.GetWidth, panel)
    local okH, height = pcall(panel.GetHeight, panel)
    width = okW and tonumber(width) or 200
    height = okH and tonumber(height) or 300

    -- Where each starts, when, how big and how fast it turns.
    for index, coin in ipairs(rain.coins) do
        coin.x = (index - 0.5) / COINS * width + math.random(-8, 8)
        coin.delay = math.random() * COIN_STAGGER
        coin.size = COIN_SIZE + math.random(0, 8)
        coin.spin = 6 + math.random() * 6
        coin.phase = math.random() * math.pi
        coin:SetSize(coin.size, coin.size)
        coin:Hide()
    end
    rain:Show()

    local total = COIN_STAGGER + COIN_FALL
    self:Start({ slot = "coins", duration = total,
        apply = function(p)
            local now = p * total
            for _, coin in ipairs(rain.coins) do
                local t = (now - coin.delay) / COIN_FALL
                if t < 0 or t >= 1 then
                    coin:Hide()
                else
                    -- Falling faster as it goes, turning as it falls.
                    local y = -coin.size + (height + coin.size) * t * t
                    local turn = math.abs(math.cos(t * coin.spin + coin.phase))
                    coin:SetWidth(math.max(2, coin.size * turn))
                    coin:ClearAllPoints()
                    coin:SetPoint("CENTER", rain, "TOPLEFT", coin.x, -y)
                    coin:SetAlpha(t > 0.7 and (1 - t) / 0.3 or 1)
                    coin:Show()
                end
            end
            if p >= 1 then rain:Hide() end
        end,
        stop = function() rain:Hide() end })
end

--- A soft ring of light round `frame`, `spread` pixels out: the glow art
--- cut in nine, its quarters rounding the corners and its middle stretched
--- along the sides, so the light falls off the same way all round with no
--- seams or square corners. Drawn here rather than as the panel's halo, so
--- the Blizzard window style (which puts halos out) still shows the burn.
local RIM_PIECES = {
    -- point on the piece, point on the frame, texture coordinates
    { "BOTTOMRIGHT", "TOPLEFT", 0, 0.5, 0, 0.5, corner = true },
    { "BOTTOMLEFT", "TOPRIGHT", 0.5, 1, 0, 0.5, corner = true },
    { "TOPRIGHT", "BOTTOMLEFT", 0, 0.5, 0.5, 1, corner = true },
    { "TOPLEFT", "BOTTOMRIGHT", 0.5, 1, 0.5, 1, corner = true },
    { "BOTTOMLEFT", "TOPLEFT", 0.49, 0.51, 0, 0.5, to = { "BOTTOMRIGHT", "TOPRIGHT" } },
    { "TOPLEFT", "BOTTOMLEFT", 0.49, 0.51, 0.5, 1, to = { "TOPRIGHT", "BOTTOMRIGHT" } },
    { "TOPRIGHT", "TOPLEFT", 0, 0.5, 0.49, 0.51, to = { "BOTTOMRIGHT", "BOTTOMLEFT" } },
    { "TOPLEFT", "TOPRIGHT", 0.5, 1, 0.49, 0.51, to = { "BOTTOMLEFT", "BOTTOMRIGHT" } },
}

local function Rim(frame, spread, r, g, b)
    local pieces = {}
    for index, piece in ipairs(RIM_PIECES) do
        local texture = frame:CreateTexture(nil, "ARTWORK")
        texture:SetTexture(GLOW_ART)
        pcall(texture.SetBlendMode, texture, "ADD")
        pcall(texture.SetTexCoord, texture, piece[3], piece[4], piece[5], piece[6])
        pcall(texture.SetVertexColor, texture, r, g, b)
        texture:SetPoint(piece[1], frame, piece[2], 0, 0)
        if piece.corner then
            texture:SetSize(spread, spread)
        else
            texture:SetPoint(piece.to[1], frame, piece.to[2], 0, 0)
            if index <= 6 then texture:SetHeight(spread) else texture:SetWidth(spread) end
        end
        pieces[index] = texture
    end
    return pieces
end

local function LightRim(pieces, alpha)
    alpha = math.max(0, math.min(1, alpha))
    for _, texture in ipairs(pieces) do
        texture:SetAlpha(alpha)
        texture:SetShown(alpha > 0)
    end
end

--- The panel's rim burns: a red glow outside, gold against the edge,
--- breathing slowly, and embers drifting up off the top. It burns
--- BURN_TIME seconds, then cools away.
function TrackerFX:Burn()
    local panel = ns.TrackerUI.frame

    local burn = self.burn
    if not burn then
        burn = CreateFrame("Frame", nil, panel)
        burn:SetAllPoints(panel)
        burn:SetFrameLevel(math.max(0, panel:GetFrameLevel() - 1))
        burn.outer = Rim(burn, BURN_SPREAD, 1, 0.22, 0.06)
        burn.inner = Rim(burn, BURN_INNER, 1, 0.72, 0.28)
        burn.embers = {}
        for index = 1, EMBERS do
            local ember = burn:CreateTexture(nil, "OVERLAY")
            ember:SetTexture(GLOW_ART)
            pcall(ember.SetBlendMode, ember, "ADD")
            pcall(ember.SetVertexColor, ember, 1, 0.45 + 0.3 * (index % 3) / 2, 0.12)
            burn.embers[index] = ember
        end
        self.burn = burn
    end

    local okW, width = pcall(panel.GetWidth, panel)
    width = okW and tonumber(width) or 200
    for _, ember in ipairs(burn.embers) do
        ember.x = math.random() * width
        ember.rise = 24 + math.random() * 30
        ember.speed = 0.35 + math.random() * 0.4
        ember.phase = math.random()
        ember.sway = math.random() * 6.28
        local size = 6 + math.random() * 5
        ember:SetSize(size, size)
    end
    burn:Show()

    local total = BURN_TIME + BURN_FADE
    self:Start({ slot = "burn", duration = total,
        apply = function(p)
            local now = p * total
            -- In over a second, burning, then cooling away, eased both ways.
            local heat = math.min(1, now / 1)
            if now > BURN_TIME then heat = math.max(0, 1 - (now - BURN_TIME) / BURN_FADE) end
            heat = heat * heat * (3 - 2 * heat)
            -- A slow breath with a faint shimmer, never a strobe.
            local breath = 0.86 + 0.1 * math.sin(now * 2.2) + 0.04 * math.sin(now * 5.3 + 1)

            LightRim(burn.outer, 0.85 * heat * breath)
            LightRim(burn.inner, 0.7 * heat * (0.92 + 0.08 * math.sin(now * 2.2 + 1.4)))

            for _, ember in ipairs(burn.embers) do
                local t = (now * ember.speed + ember.phase) % 1
                ember:ClearAllPoints()
                ember:SetPoint("CENTER", burn, "TOPLEFT", ember.x + 5 * math.sin(now * 1.6 + ember.sway),
                    t * ember.rise)
                -- Fades in off the rim and out as it rises.
                ember:SetAlpha(heat * math.min(1, t * 5) * (1 - t))
                ember:SetShown(heat > 0)
            end

            if p >= 1 then burn:Hide() end
        end,
        stop = function() burn:Hide() end })
end

--- "Witchwing Slayers", "Thieves", "Harpies": the plural the title
--- needs, English only. Another language's client keeps the name.
function TrackerFX.Plural(name)
    if type(name) ~= "string" or name == "" then return "" end
    if not (Util.EnglishClient and Util.EnglishClient()) then return name end
    if name:find("[^aeiou]y$") then return name:sub(1, -2) .. "ies" end
    if name:find("man$") then return name:sub(1, -4) .. "men" end
    if name:find("fe$") then return name:sub(1, -3) .. "ves" end
    if name:find("[^f]f$") then return name:sub(1, -2) .. "ves" end
    if name:find("[sxz]$") or name:find("[cs]h$") then return name .. "es" end
    return name .. "s"
end

Glow = function(parent, layer)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK")
    texture:SetTexture(GLOW_ART)
    pcall(texture.SetBlendMode, texture, "ADD")
    return texture
end

--- The screen the 1000th kill takes over: its own frame over everything,
--- taking no mouse, so play goes on under it.
function TrackerFX:Stage()
    if self.stage then return self.stage end

    local stage = CreateFrame("Frame", nil, UIParent)
    stage:SetAllPoints(UIParent)
    pcall(stage.SetFrameStrata, stage, "FULLSCREEN_DIALOG")
    stage:EnableMouse(false)

    stage.dim = stage:CreateTexture(nil, "BACKGROUND")
    stage.dim:SetAllPoints(stage)
    stage.dim:SetColorTexture(0, 0, 0, 1)

    stage.rays = {}
    for index = 1, RAYS do
        local ray = Glow(stage, "BORDER")
        ray:SetSize(2600, 70)
        ray:SetPoint("CENTER", stage, "CENTER", 0, 40)
        ray:SetVertexColor(1, 0.75, 0.3)
        ray.angle = (index - 1) / RAYS * math.pi
        stage.rays[index] = ray
    end

    stage.motes = {}
    for index = 1, MOTES do
        local mote = Glow(stage, "ARTWORK")
        mote:SetVertexColor(1, 0.86, 0.5)
        stage.motes[index] = mote
    end

    local holder = CreateFrame("Frame", nil, stage)
    holder:SetSize(1400, 260)
    holder:SetPoint("CENTER", stage, "CENTER", 0, 40)
    stage.holder = holder

    local function Text(size, flags, r, g, b)
        local label = holder:CreateFontString(nil, "OVERLAY")
        pcall(label.SetFont, label, Theme.FONT, size, flags)
        label:SetTextColor(r, g, b, 1)
        label:SetJustifyH("CENTER")
        return label
    end

    stage.top = Text(30, "OUTLINE", 1, 0.88, 0.6)
    stage.top:SetPoint("BOTTOM", holder, "CENTER", 0, 44)
    stage.big = Text(64, "THICKOUTLINE", 1, 0.8, 0.3)
    stage.big:SetPoint("CENTER", holder, "CENTER", 0, 0)
    stage.sub = Text(26, "OUTLINE", 1, 1, 1)
    stage.sub:SetPoint("TOP", holder, "CENTER", 0, -46)

    stage.shine = Glow(holder, "OVERLAY")
    stage.shine:SetSize(160, 200)
    stage.shine:SetVertexColor(1, 1, 0.9)

    stage.flash = stage:CreateTexture(nil, "OVERLAY")
    stage.flash:SetAllPoints(stage)
    stage.flash:SetColorTexture(1, 0.94, 0.78, 1)
    pcall(stage.flash.SetBlendMode, stage.flash, "ADD")

    stage:SetScript("OnUpdate", function(_, elapsed)
        local ok, err = pcall(TrackerFX.StepStage, TrackerFX, elapsed)
        if not ok then
            stage:Hide()
            ns.Debug("bane takeover dropped:", tostring(err))
        end
    end)
    stage:Hide()

    self.stage = stage
    return stage
end

--- The 1000th kill: `info` is the fanfare's, with `mob` and `kills`. The
--- 500th (`info.slayer`) borrows the same stage, lighter: the screen only
--- a little dimmed, no rays or motes, and the words sweep in from the left.
function TrackerFX:Takeover(info)
    local stage = self:Stage()
    local mob = info.mob or ""

    stage.slayer = info.slayer and true or false
    stage.length = stage.slayer and SLAYER_TIME or TAKEOVER
    stage.top:SetText(stage.slayer and L["SLAYER OF"] or L["BANE OF THE"])
    stage.big:SetText(TrackerFX.Plural(mob):upper())
    stage.sub:SetText(L.Format("%d kills", info.kills or (stage.slayer and 500 or 1000)))

    local okW, width = pcall(stage.GetWidth, stage)
    local okH, height = pcall(stage.GetHeight, stage)
    stage.width = okW and tonumber(width) or 1920
    stage.height = okH and tonumber(height) or 1080
    for _, mote in ipairs(stage.motes) do
        mote.x = math.random() * stage.width
        mote.y = math.random() * stage.height
        mote.speed = 40 + math.random() * 90
        mote.phase = math.random() * 6
        local size = 6 + math.random(0, 6)
        mote:SetSize(size, size)
    end

    stage.age = 0
    stage:SetAlpha(1)
    stage:Show()
    self:StepStage(0)
end

local function Clamp(p) return math.max(0, math.min(1, p)) end

function TrackerFX:StepStage(elapsed)
    local stage = self.stage
    if not stage then return end
    stage.age = stage.age + (tonumber(elapsed) or 0)
    local t = stage.age
    local length = stage.length or TAKEOVER
    local slayer = stage.slayer

    if t >= length then
        stage:Hide()
        return
    end

    -- In over half a second, held, then out over the last second.
    local fade = t > length - 1 and Clamp(length - t) or 1
    local dim = EaseOut(Clamp(t / 0.5)) * fade

    stage.flash:SetAlpha((slayer and 0.35 or 0.8) * Clamp(1 - t / 0.35))
    stage.dim:SetAlpha((slayer and SLAYER_DIM or DIM) * dim)

    for _, ray in ipairs(stage.rays) do
        pcall(ray.SetRotation, ray, ray.angle + t * 0.25)
        ray:SetAlpha(slayer and 0 or 0.3 * dim)
    end

    for _, mote in ipairs(stage.motes) do
        local y = (mote.y + t * mote.speed) % stage.height
        mote:ClearAllPoints()
        mote:SetPoint("CENTER", stage, "BOTTOMLEFT", mote.x, y)
        mote:SetAlpha(slayer and 0 or dim * (0.5 + 0.5 * math.sin(t * 6 + mote.phase)))
    end

    local land = EaseOut(Clamp((t - 0.2) / 0.6))
    stage.holder:ClearAllPoints()
    if slayer then
        -- The words sweep in from the left and settle in the middle.
        stage.holder:SetScale(1)
        stage.holder:SetPoint("CENTER", stage, "CENTER", -(stage.width or 1920) * (1 - land), 40)
    else
        -- The title lands from a little larger, then fades with the rest.
        stage.holder:SetScale(1.35 - 0.35 * land)
        stage.holder:SetPoint("CENTER", stage, "CENTER", 0, 40)
    end
    stage.holder:SetAlpha(Clamp((t - 0.2) / 0.5) * (t > length - 1.2 and Clamp((length - 0.2 - t)) or 1))

    -- A light crosses the letters once.
    local sweep = (t - 1.1) / 0.9
    if sweep >= 0 and sweep <= 1 then
        stage.shine:ClearAllPoints()
        stage.shine:SetPoint("CENTER", stage.holder, "LEFT", 1400 * sweep, 0)
        stage.shine:SetAlpha(0.6 * math.sin(sweep * math.pi))
    else
        stage.shine:SetAlpha(0)
    end
end

--- The mob's band beats gold for longer than a plain kill.
function TrackerFX:PulseUnlocked(info)
    for index, line in ipairs(ns.TrackerUI.shown or {}) do
        if line.key == info.key and ns.TrackerUI.lines[index] then
            self:Pulse(ns.TrackerUI.lines[index], line.key, BRIGHT_GOLD, 0.6)
        end
    end
end

--------------------------------------------------------------------------------
-- Sound
--------------------------------------------------------------------------------

--- A green or better drop. Blue and better say the goblin's line when it
--- has not played lately; otherwise (or with voice lines off) the chime.
function TrackerFX:PlayRare(quality)
    if (quality or 0) >= VOICE_QUALITY and self:Say("drop") then return end

    if not TrackerFX.RareSoundOn() then return end
    local now = type(GetTime) == "function" and GetTime() or self.clock
    if self.rareAt and now - self.rareAt < RARE_GAP then return end

    self.rareAt = now
    ns.Tracker.PlayFile(ns.Tracker.SOUNDS.rare)
end

--- Say one of the voice lines ("drop" or "goal"). True when the client says
--- it will play; false when they are off, it played lately, or it is refused.
function TrackerFX:Say(kind)
    local id = TrackerFX.VOICE[kind]
    if not id or not TrackerFX.VoiceOn() or type(PlaySoundFile) ~= "function" then return false end

    local now = type(GetTime) == "function" and GetTime() or self.clock
    local last = self.saidAt[kind]
    if last and now - last < VOICE_GAP then return false end

    local ok, willPlay = pcall(PlaySoundFile, id, "Dialog")
    if not (ok and willPlay) then return false end
    self.saidAt[kind] = now
    return true
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

function TrackerFX:SetLevel(level)
    ns.db.trackerEffects = level
    if ns.SharedChoices then ns.SharedChoices:Changed("effects", level or "full") end
    if level == "off" then
        self:Forget()
        -- What is moving in any window lands at once rather than finishing
        -- slowly.
        if ns.Motion then ns.Motion:FinishAll() end
    end
    if ns.SettingsUI and ns.SettingsUI.Refresh then ns.SettingsUI:Refresh() end
end

ns.RegisterCommand("effects", L["how much the panels and windows move: full, subtle or off"], function(rest)
    local argument = Util.Trim(rest):lower()

    if not LEVEL_NAMES[argument] then
        -- No word: step round full, subtle, off.
        local current = TrackerFX.Level()
        for index, level in ipairs(LEVELS) do
            if level == current then argument = LEVELS[index == 1 and #LEVELS or index - 1] end
        end
    end

    TrackerFX:SetLevel(argument)

    local lines = {
        full = L["window effects: full. Windows fade up and glow, counts glow and loot floats off the kill panel."],
        subtle = L["window effects: subtle. Shorter fades, and nothing floats."],
        off = L["window effects off. Nothing moves. /farm effects full turns them back on."],
    }
    ns.Print(lines[argument])
end)

ns.RegisterCommand("voice", L["spoken lines for a blue drop or a goal reached (on/off)"], function(rest)
    local argument = Util.Trim(rest):lower()

    if argument == "on" then
        ns.db.trackerVoice = true
    elseif argument == "off" then
        ns.db.trackerVoice = false
    else
        ns.db.trackerVoice = ns.db.trackerVoice == false
    end

    ns.Print(TrackerFX.VoiceOn()
        and L["voice lines on: a goblin cheers a blue or better drop, and a peon says \"Work complete!\" when a goal is done. /farm voice off to stop."]
        or L["voice lines off. /farm voice on to bring them back."])

    if ns.SettingsUI and ns.SettingsUI.Refresh then ns.SettingsUI:Refresh() end
end)

ns.RegisterCommand("raresound", L["a sound when something green or better drops (on/off)"], function(rest)
    local argument = Util.Trim(rest):lower()

    if argument == "on" then
        ns.db.trackerRareSound = true
    elseif argument == "off" then
        ns.db.trackerRareSound = false
    else
        ns.db.trackerRareSound = ns.db.trackerRareSound == false
    end

    ns.Print(TrackerFX.RareSoundOn()
        and L["a sound plays when something green or better drops. /farm raresound off to stop."]
        or L["no sound for rare drops. /farm raresound on to bring it back."])

    if ns.SettingsUI and ns.SettingsUI.Refresh then ns.SettingsUI:Refresh() end
end)
