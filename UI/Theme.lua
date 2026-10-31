-- Blackthornes Farmer -- UI/Theme.lua
-- Palette and panel construction.
--
-- The same palette as Blackthornes Tradeskills on purpose: the two addons are
-- worn together and should read as one set. Everything is built from plain
-- textures rather than Blizzard backdrops, which keeps the look consistent and
-- avoids depending on BackdropTemplate being present on this client.

local _, ns = ...

local Theme = {}
ns.Theme = Theme

Theme.colors = {
    window    = { 0.055, 0.063, 0.078 },   -- #0E1014 outermost shell
    panel     = { 0.086, 0.094, 0.114 },   -- #16181D
    header    = { 0.110, 0.122, 0.145 },
    row       = { 0.133, 0.145, 0.172 },   -- #22252C
    rowAlt    = { 0.106, 0.118, 0.141 },
    rowHover  = { 0.180, 0.200, 0.239 },
    rowActive = { 0.220, 0.190, 0.110 },   -- a gold-tinted row, as in Tradeskills
    -- Dark glass (2026-10-10, asked to calm the gold glare behind list
    -- rows; Tradeskills' and Equipment's palettes have the same): rows sit
    -- in the dark, a faint band apart, with a fine line under each. Hover
    -- lifts a little and keeps the gold to the row's edge.
    glass       = { 0.067, 0.075, 0.094 },   -- #111318
    glassAlt    = { 0.039, 0.047, 0.063 },   -- #0A0C10
    glassHover  = { 0.094, 0.106, 0.129 },   -- #181B21
    glassActive = { 0.141, 0.122, 0.078 },   -- #241F14, gold in the dark

    border    = { 0.204, 0.224, 0.263 },
    borderLit = { 0.302, 0.333, 0.388 },

    accent    = { 0.784, 0.643, 0.302 },   -- #C8A44D
    -- Titanforged (2026-10-04), as in Tradeskills: the lit gold of a hovered
    -- edge, the gold of a button's label, the dark ink on a gold button, the
    -- dark well a list sits recessed in, and the dim metal edge of a button
    -- at rest.
    accentHi  = { 0.945, 0.831, 0.533 },   -- #F1D488
    gilt      = { 0.941, 0.824, 0.494 },   -- #F0D27E
    ink       = { 0.110, 0.078, 0.024 },   -- #1C1406
    well      = { 0.039, 0.047, 0.063 },   -- #0A0C10
    metal     = { 0.541, 0.427, 0.180 },   -- #8A6D2E
    good      = { 0.310, 0.820, 0.545 },   -- #4FD18B
    warn      = { 0.910, 0.757, 0.353 },
    loss      = { 0.898, 0.376, 0.310 },   -- #E5604F, a close button under the mouse

    -- A fishing pool's name on the Grind tab's Fish view, so a pool reads
    -- apart from the open water of the same zone at a glance.
    pool      = { 0.424, 0.690, 0.941 },   -- #6CB0F0

    text      = { 0.902, 0.910, 0.925 },   -- #E6E8EC
    -- Tradeskills' greys: Farmer's had drifted darker, and its hints and
    -- column headings were hard to read on the window's near-black.
    muted     = { 0.545, 0.569, 0.608 },   -- #8B919B
    dim       = { 0.420, 0.440, 0.482 },   -- #6B707B
}

local FONT do
    local ok, path = pcall(function() return (GameFontNormal:GetFont()) end)
    FONT = (ok and path) or [[Fonts\FRIZQT__.TTF]]
end

Theme.FONT = FONT

-- The sizes at Normal text size.
Theme.BASE_SIZES = {
    tiny = 10,
    small = 11,
    normal = 12,
    large = 14,
    title = 16,
}

-- Text size (Tradeskills' setting, asked for here 2026-10-09): Large and
-- Larger add a point or two to every size this addon draws.
Theme.TEXT_STEPS = { normal = 0, large = 1, larger = 2 }

-- Read once, the first time a size is asked for after the saved settings
-- are in: text drawn before a change and after it would not match, so a
-- change waits for /reload.
local textStep

--- The points added to every size: 0, 1 or 2.
function Theme.TextStep()
    if textStep then return textStep end
    if not ns.db then return 0 end
    textStep = Theme.TEXT_STEPS[ns.db.textSize] or 0
    return textStep
end

-- Looked up rather than stored, so the step is added wherever a size is
-- read: Theme.sizes.small is 11 at Normal, 13 at Larger.
Theme.sizes = setmetatable({}, {
    __index = function(_, key)
        local base = Theme.BASE_SIZES[key]
        if base then return base + Theme.TextStep() end
    end,
})

function Theme.Unpack(key, alpha)
    local color = Theme.colors[key] or Theme.colors.text
    return color[1], color[2], color[3], alpha or 1
end

--- Flat filled texture covering a frame.
function Theme.Fill(frame, key, alpha, layer)
    local texture = frame:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetAllPoints(frame)
    texture:SetColorTexture(Theme.Unpack(key, alpha))
    return texture
end

--- One-pixel border drawn as four edge textures, so it stays crisp at any size.
function Theme.Border(frame, key, alpha)
    local r, g, b, a = Theme.Unpack(key or "border", alpha)
    local edges = {}

    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = frame:CreateTexture(nil, "BORDER")
        edge:SetColorTexture(r, g, b, a)

        if side == "TOP" then
            edge:SetPoint("TOPLEFT")
            edge:SetPoint("TOPRIGHT")
            edge:SetHeight(1)
        elseif side == "BOTTOM" then
            edge:SetPoint("BOTTOMLEFT")
            edge:SetPoint("BOTTOMRIGHT")
            edge:SetHeight(1)
        elseif side == "LEFT" then
            edge:SetPoint("TOPLEFT")
            edge:SetPoint("BOTTOMLEFT")
            edge:SetWidth(1)
        else
            edge:SetPoint("TOPRIGHT")
            edge:SetPoint("BOTTOMRIGHT")
            edge:SetWidth(1)
        end

        edges[#edges + 1] = edge
    end

    frame.borderTextures = edges
    return edges
end

--- Recolour a border drawn by Theme.Border.
function Theme.SetBorderColor(frame, key, alpha)
    if not frame.borderTextures then return end

    local r, g, b, a = Theme.Unpack(key, alpha)
    for _, edge in ipairs(frame.borderTextures) do
        edge:SetColorTexture(r, g, b, a)
    end
end

--- A panel: filled background plus a border.
function Theme.CreatePanel(parent, backgroundKey, borderKey)
    local panel = CreateFrame("Frame", nil, parent)
    panel.background = Theme.Fill(panel, backgroundKey or "panel")

    if borderKey ~= false then
        Theme.Border(panel, borderKey or "border")
    end

    return panel
end

--- A text label.
function Theme.CreateLabel(parent, size, colorKey, justify)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(FONT, Theme.sizes[size] or size or Theme.sizes.normal, "")
    label:SetTextColor(Theme.Unpack(colorKey or "text"))
    label:SetJustifyH(justify or "LEFT")
    label:SetWordWrap(false)
    return label
end

-- One unanchored, unbounded label per size, for measuring text: a label
-- anchored at both ends reports the width it was given, not the width its
-- text wants.
local measures = {}

--- How wide `text` is in pixels at a label size, as the game draws it.
--
-- The game's font runs wider than any fixed width we could guess, which is
-- how "Loot a corpse and it shows up he..." happened. Measure instead.
function Theme.TextWidth(size, text)
    if type(text) ~= "string" or text == "" then return 0 end

    local label = measures[size]
    if not label then
        label = Theme.CreateLabel(UIParent, size, "text")
        label:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 0, -200)
        label:SetAlpha(0)
        measures[size] = label
    end

    -- Colour codes take no room on screen.
    label:SetText(ns.Util and ns.Util.StripColor(text) or text)

    -- The unbounded width where the client has it, else the plain one.
    local width
    for _, method in ipairs({ "GetUnboundedStringWidth", "GetStringWidth" }) do
        if not width and type(label[method]) == "function" then
            local ok, value = pcall(label[method], label)
            width = ok and tonumber(value) or nil
        end
    end

    return math.ceil(width or 0)
end

--- Sink a panel into the window, as the game's inset panels sit: a darker
--- well, a shadow falling from its top edge and a faint light along its foot.
function Theme.Recess(frame)
    if frame.background then frame.background:SetColorTexture(Theme.Unpack("well")) end

    local shadow = frame:CreateTexture(nil, "BACKGROUND", nil, 3)
    shadow:SetPoint("TOPLEFT", 1, -1)
    shadow:SetPoint("TOPRIGHT", -1, -1)
    shadow:SetHeight(14)
    shadow:SetColorTexture(0, 0, 0, 1)
    local ok = type(CreateColor) == "function" and type(shadow.SetGradient) == "function"
        and pcall(shadow.SetGradient, shadow, "VERTICAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.6))
    if not ok then shadow:Hide() end

    local foot = frame:CreateTexture(nil, "BORDER", nil, 2)
    foot:SetPoint("BOTTOMLEFT", 1, 0)
    foot:SetPoint("BOTTOMRIGHT", -1, 0)
    foot:SetHeight(1)
    foot:SetColorTexture(1, 1, 1, 0.05)

    if frame.borderTextures then
        Theme.SetBorderColor(frame, "border", 0.8)
        -- The top edge in shadow, so the panel reads as sunk rather than raised.
        local top = frame.borderTextures[1]
        if top then top:SetColorTexture(0.016, 0.020, 0.028, 1) end
    end
    return shadow
end

--- A button's metal: a light along its top half and a shade along its
--- bottom, over whatever fill it has, so it reads as raised and pressable.
function Theme.Bevel(frame)
    local shine = frame:CreateTexture(nil, "BORDER", nil, -1)
    shine:SetPoint("TOPLEFT", 1, -1)
    shine:SetPoint("TOPRIGHT", -1, -1)
    shine:SetPoint("BOTTOM", frame, "CENTER")
    shine:SetColorTexture(1, 1, 1, 0.06)

    local shade = frame:CreateTexture(nil, "BORDER", nil, -1)
    shade:SetPoint("BOTTOMLEFT", 1, 1)
    shade:SetPoint("BOTTOMRIGHT", -1, 1)
    shade:SetPoint("TOP", frame, "CENTER")
    shade:SetColorTexture(0, 0, 0, 0.22)

    if type(CreateColor) == "function" and type(shine.SetGradient) == "function" then
        pcall(shine.SetGradient, shine, "VERTICAL", CreateColor(1, 1, 1, 0.02), CreateColor(1, 1, 1, 0.12))
        pcall(shade.SetGradient, shade, "VERTICAL", CreateColor(0, 0, 0, 0.35), CreateColor(0, 0, 0, 0.02))
    end
    return shine, shade
end

function Theme.CreateDivider(parent, key)
    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(Theme.Unpack(key or "border"))
    divider:SetHeight(1)
    return divider
end

--------------------------------------------------------------------------------
-- House trim, shared with Blackthornes Tradeskills
--
-- The same few touches Tradeskills' Theme.lua draws, so the two windows read as
-- one set: a gold stripe down the left of a header, a faint sheen along the
-- top of a raised surface, and item icons trimmed the way the bags draw them.
--------------------------------------------------------------------------------

--- A gold stripe down the left edge of a header or band.
function Theme.AccentStripe(frame, width, alpha)
    local stripe = frame:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("BOTTOMLEFT")
    stripe:SetWidth(width or 3)
    stripe:SetColorTexture(Theme.Unpack("accent", alpha))
    return stripe
end

--- A faint lighter line along the top edge, so a flat fill reads as a raised
--- surface rather than a hole.
function Theme.TopSheen(frame, alpha)
    local sheen = frame:CreateTexture(nil, "BORDER")
    sheen:SetPoint("TOPLEFT", 1, -1)
    sheen:SetPoint("TOPRIGHT", -1, -1)
    sheen:SetHeight(1)
    sheen:SetColorTexture(1, 1, 1, alpha or 0.05)
    return sheen
end

--- Shade `texture` from one alpha of a palette colour to another, along
--- "VERTICAL" (bottom to top) or "HORIZONTAL" (left to right). Where the
--- client cannot draw a gradient it gets one flat, fainter wash instead.
--- Returns true when the gradient was drawn.
function Theme.SetGradientAlpha(texture, orientation, key, fromAlpha, toAlpha)
    local r, g, b = Theme.Unpack(key or "accent")
    texture:SetColorTexture(1, 1, 1, 1)

    local ok = false
    if type(CreateColor) == "function" and type(texture.SetGradient) == "function" then
        ok = pcall(texture.SetGradient, texture, orientation,
            CreateColor(r, g, b, fromAlpha), CreateColor(r, g, b, toAlpha))
    end

    if not ok then
        texture:SetColorTexture(r, g, b, math.max(fromAlpha, toAlpha) * 0.4)
    end
    return ok
end

--- The house header's trim on `header`: the gold stripe down its left, the
--- soft glow and the sheen along its top. Returns the stripe.
function Theme.HouseHeader(header, glowHeight)
    local stripe = Theme.AccentStripe(header, 3)
    Theme.HeaderGlow(header, glowHeight or 16, 0.10)
    Theme.TopSheen(header)
    return stripe
end

--- Light a gradient made by Theme.SetGradientAlpha to `p` of its full
--- strength, hiding it at 0. The alpha goes into the gradient itself and the
--- texture hides when dark: faded with SetAlpha alone, the rows' hover wash
--- showed lit on every row of a list on Forever (seen 2026-10-10).
function Theme.LightGradient(texture, orientation, key, fromAlpha, toAlpha, p)
    p = math.max(0, math.min(1, tonumber(p) or 0))
    texture:SetShown(p > 0)
    if p > 0 then
        Theme.SetGradientAlpha(texture, orientation, key, fromAlpha * p, toAlpha * p)
    end
end

--- A soft gold glow fading down from the top of a header, drawn as a
--- gradient where the client has one and left out where it does not.
function Theme.HeaderGlow(frame, height, alpha)
    local glow = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    glow:SetPoint("TOPLEFT")
    glow:SetPoint("TOPRIGHT")
    glow:SetHeight(height or 18)
    glow:SetColorTexture(1, 1, 1, 1)

    local r, g, b = Theme.Unpack("accent")
    local top, bottom = alpha or 0.10, 0

    local ok = false
    if type(CreateColor) == "function" and type(glow.SetGradient) == "function" then
        ok = pcall(glow.SetGradient, glow, "VERTICAL",
            CreateColor(r, g, b, bottom), CreateColor(r, g, b, top))
    end

    if not ok then glow:Hide() end
    return glow
end

--- A soft glow round the outside of a frame, fading out from its edge: the
--- neon edge the open card on the kills panel has, for whole windows.
--- Returns the four sides, so a caller can brighten or dim them together
--- with Theme.SetHalo. Where the client cannot draw a gradient the glow is
--- a flat, fainter band instead.
function Theme.Halo(frame, spread, alpha, key)
    spread = spread or 6
    local sides = {}

    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local halo = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        pcall(halo.SetBlendMode, halo, "ADD")

        if side == "TOP" or side == "BOTTOM" then
            local out = side == "TOP" and 1 or -1
            halo:SetPoint(side .. "LEFT", frame, side .. "LEFT", 0, out * spread)
            halo:SetPoint(side .. "RIGHT", frame, side .. "RIGHT", 0, out * spread)
            halo:SetHeight(spread)
        else
            local out = side == "LEFT" and -1 or 1
            halo:SetPoint("TOP" .. side, frame, "TOP" .. side, out * spread, 0)
            halo:SetPoint("BOTTOM" .. side, frame, "BOTTOM" .. side, out * spread, 0)
            halo:SetWidth(spread)
        end

        halo.side = side
        sides[#sides + 1] = halo
    end

    frame.haloTextures = sides
    -- Its colour, so a flare that names none keeps it.
    frame.haloKey = key
    -- Where it settles; Motion:Open flares it from brighter as a window opens.
    frame.haloRest = alpha or 0.12
    Theme.SetHalo(frame, frame.haloRest, key)
    return sides
end

--- Relight a halo drawn by Theme.Halo: `alpha` at the frame's edge, in the
--- palette colour `key` (gold unless given).
function Theme.SetHalo(frame, alpha, key)
    local sides = frame and frame.haloTextures
    if not sides then return end

    key = key or frame.haloKey or "accent"
    alpha = math.max(0, tonumber(alpha) or 0)

    for _, halo in ipairs(sides) do
        -- The bright end sits against the frame: the bottom of the band
        -- above it, the top of the band below, and so on.
        if halo.side == "TOP" then
            Theme.SetGradientAlpha(halo, "VERTICAL", key, alpha, 0)
        elseif halo.side == "BOTTOM" then
            Theme.SetGradientAlpha(halo, "VERTICAL", key, 0, alpha)
        elseif halo.side == "LEFT" then
            Theme.SetGradientAlpha(halo, "HORIZONTAL", key, 0, alpha)
        else
            Theme.SetGradientAlpha(halo, "HORIZONTAL", key, alpha, 0)
        end
        halo:SetShown(alpha > 0)
    end
end

local FALLBACK_ICON = [[Interface\Icons\INV_Misc_QuestionMark]]

--- An item's icon texture, or nil while the game has not sent it. Read in a
--- pcall: this is the client, and inside an instance it can hand back a
--- value that raises when touched.
function Theme.ItemIcon(itemID)
    if not itemID then return nil end

    local icon
    if type(C_Item) == "table" and type(C_Item.GetItemIconByID) == "function" then
        local ok, value = pcall(C_Item.GetItemIconByID, itemID)
        if ok then icon = value end
    end
    if not icon and type(GetItemIcon) == "function" then
        local ok, value = pcall(GetItemIcon, itemID)
        if ok then icon = value end
    end

    local readable = ns.Harvest and (ns.Harvest.ReadableNumber(icon) or ns.Harvest.Readable(icon))
    return readable or nil
end

--- A square item icon, trimmed of its built-in border.
function Theme.CreateItemIcon(parent, size)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size or 16, size or 16)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:Hide()
    return icon
end

--- Show an item's icon, or the question mark while the game has not sent it.
--- Hidden when there is no item at all.
function Theme.SetItemIcon(icon, itemID)
    if not icon then return end

    if not itemID then
        icon:Hide()
        return
    end

    icon:SetTexture(Theme.ItemIcon(itemID) or FALLBACK_ICON)
    Theme.RingItem(icon, nil, itemID)
    icon:Show()
end

--- The thin ring round an item's icon in its quality colour
--- (UI/ItemLook.lua), by name and/or ID; no ring while nobody knows.
function Theme.RingItem(icon, name, itemID)
    if not icon or not ns.ItemLook then return end
    local quality
    if ns.Util and ns.Util.ItemQuality then
        local ok, found = pcall(ns.Util.ItemQuality, name, itemID)
        if ok then quality = found end
    end
    ns.ItemLook.SetQuality(icon, quality)
end
