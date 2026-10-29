-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.6.0", lines = {
        "The Grind tab now shows what each camp earns an hour.",
        "The minimap button has a new Blackthornes badge.",
        "Show the way now puts a gold marker on your map.",
    } },
    { version = "0.5.0", lines = {
        "One minimap button now opens all your Blackthornes add-ons.",
    } },
    { version = "0.4.0", lines = {
        "One key fishing lets you add a lure, cast and reel in with a single key.",
        "Rankings has a new Vendor Only box that counts drops at what a vendor pays.",
        "The fishing buttons have a new gold look.",
    } },
}
