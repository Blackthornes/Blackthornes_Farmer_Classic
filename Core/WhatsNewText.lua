-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.12.0", lines = {
        "Loot Beacons put a beam over a body that still has loot.",
        "A map button hides every Farmer mark on the world map.",
        "Mute All Sounds quiets every Blackthornes sound at once.",
        "Windows remember where you drag them.",
    } },
    { version = "0.11.0", lines = {
        "The Top 15 window can be dragged anywhere and remembers its place.",
    } },
    { version = "0.10.0", lines = {
        "A new fishing panel shows your session, your spot and every fish you've caught.",
    } },
}
