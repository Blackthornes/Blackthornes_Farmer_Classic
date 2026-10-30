-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.8.0", lines = {
        "All your Blackthornes add-ons now open in one window, with a button for each add-on down the side.",
        "The window moves beside the auction house, mailbox, vendor and trainer when you open them.",
    } },
    { version = "0.7.0", lines = {
        "Every window has a new look that matches the other Blackthornes add-ons.",
    } },
    { version = "0.6.0", lines = {
        "The Grind tab now shows what each camp earns an hour.",
        "The minimap button has a new Blackthornes badge.",
        "Show the way now puts a gold marker on your map.",
    } },
}
