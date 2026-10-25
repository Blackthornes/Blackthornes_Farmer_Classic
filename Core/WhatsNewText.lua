-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.2.0", lines = {
        "A fishing bar with Cast and Add Lure shows while you hold a fishing pole.",
        "A Node Pointer shows the way to herbs, ore and chests near you, with an arrow, a beam of light or sparkles.",
        "Node Sound plays a ping or a spoken line when it finds one.",
    } },
    { version = "0.1.0", lines = {
        "Farmer is here for Classic Era. Search any material, mob or zone to see where to farm it.",
        "Rankings sort mobs by what one kill is worth, and the Grind tab lists the best camps for your level.",
        "Set a goal and an arrow points you to the nearest place to get it.",
        "Your herb, ore and fishing spots show on the map.",
        "Kills and Loot shows your kills, your loot and gold an hour.",
    } },
}
