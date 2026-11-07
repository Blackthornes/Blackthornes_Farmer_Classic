-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.11.0", lines = {
        "The Top 15 window can be dragged anywhere and remembers its place.",
    } },
    { version = "0.10.0", lines = {
        "A new fishing panel shows your session, your spot and every fish you've caught.",
    } },
    { version = "0.9.0", lines = {
        "Item icons now have a ring and a name colour that match their quality.",
        "Stack counts show on the corner of item icons.",
        "Items show a small mark and colour for what to do with them.",
        "Loot table worth shows in gold, silver and copper coins.",
    } },
}
