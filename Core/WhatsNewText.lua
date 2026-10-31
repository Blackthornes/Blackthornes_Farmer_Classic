-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.9.0", lines = {
        "Item icons now have a ring and a name colour that match their quality.",
        "Stack counts show on the corner of item icons.",
        "Items show a small mark and colour for what to do with them.",
        "Loot table worth shows in gold, silver and copper coins.",
    } },
    { version = "0.8.0", lines = {
        "All your Blackthornes add-ons now open in one window, with a button for each add-on down the side.",
        "The window moves beside the auction house, mailbox, vendor and trainer when you open them.",
    } },
    { version = "0.7.0", lines = {
        "Every window has a new look that matches the other Blackthornes add-ons.",
    } },
}
