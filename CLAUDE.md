# Notes for Claude

Read this before working in this repo. The owner runs two Claude projects, one per
addon: this one (**Blackthornes_Farmer**) and **Blackthornes_Tradeskills**
(`Blackthornes/Blackthornes_Tradeskills`). They cannot read each other's
memory, so what one needs to know about the other lives in the repos, in this
file and in Tradeskills' `CLAUDE.md`. Keep both current: when a change here
leans on something new in Tradeskills, or a standing rule from the owner applies to
both addons, add it to both files.

Nothing private goes in this file (no local paths, emails or account names).
It never ships: `.pkgmeta` leaves it out of the zip and
`tools/check_package.py` refuses it.

## This repo is the Classic Era copy

`Blackthornes/Blackthornes_Farmer_Classic` is Farmer for WoW Classic Era,
copied from `Blackthornes/Blackthornes_Farmer` (Forever) with its history on
2026-10-24 (the owner said build it; Butler and Tradeskills follow in their
own repos). Its releases, tests and CurseForge page are its own. Forever
comes first, and nothing done here may ever touch the Forever addon. So:

- Never push to, or open PRs on, the Forever repo from work here. Changes
  come over from Forever on purpose (cherry-pick or copy), never the other
  way.
- The addon folder and TOC stay `Blackthornes_Farmer`, the saved data
  `BlackthornesFarmerDB`, so nothing is renamed.
- The TOC names Era's interface (`## Interface: 11507, 11508`; check the
  number the Era client reports and add it). Classic's own data stays: the
  seed files, `Data/Data_ClassicDrops.lua`, `Data/NpcNames.lua`,
  `Data/Zones.lua` and the travel files (their Forever-only zones and flight
  masters are never met on Era, and a flight is used only once the character
  knows it). What Forever added is left out (`env.FOREVER_DATA` in
  `tools/testenv.lua`): `Data/ForeverNpcNames.lua`, the owner's Forever
  harvest (`Data/Data_Harvested.lua`, `Data/Harvest_Carryover.lua`) and the
  Legacy perks (`Logic/Legacy.lua`; every reader asks `ns.Legacy` first).
  The files stay in the repo so Forever changes merge cleanly.
  `tools/test_era.lua` checks it and that the addon loads, logs in and
  searches without them. `Data/Data_Harvested.lua` comes back once it is
  made from Era play (`tools/harvest_import.py` adds it to the TOC).
- Sending drops to Blackthornes goes to the owner's own Era characters
  (2026-10-26), never Forever's, so Era drops never reach Forever's shipped
  data. `Contribute.RECIPIENTS` names them as Name-Realm; an Era whisper
  only reaches its own realm, so only players on that realm send and see
  the About page's tick box (`Contribute:Recipients`, `RealmKey`,
  `MyRealm`). Forever's region 110 is gone. See `docs/CLASSIC_DIFFERENCES.md`.
- Never put Forever's CurseForge ID (1710618) in the TOC:
  `tools/check_release.py` refuses a tag that does. The owner makes the Era
  project himself: Farmer Classic is **1763311** (2026-10-24), on the TOC's
  `X-Curse-Project-ID` line, and `tools/test_era.lua` checks it is there.
- Not yet seen in an Era client. Read client calls in a pcall as everywhere
  else; the code already falls back to the classic calls (skill lines,
  spell info, the older tooltip scripts) where Era lacks the newer ones.
- The rest of this file describes the Forever addon; read it as the
  starting point, not as what Era has.

## What Tradeskills provides

Tradeskills is the house standard for layout (`Core/ Data/ Logic/ UI/
tools/`), palette, module registry and tooling; check it before inventing a
convention. Its `docs/FOREVER_API_FINDINGS.md` records what the Forever client
actually does.

At runtime it is Farmer's source of auction prices. `Logic/Value.lua` reads,
inside a pcall and read only:

```lua
_G.BlackthornesTS.Prices:GetValue(itemID)   -- Tradeskills' smoothed market value, in copper
```

Since 2026-10-14 Farmer also asks, in a pcall, to hear when a scan
finishes (`_G.BlackthornesTS.Prices:WatchScans(fn)`, see "Your top 15
after an auction scan"). Nothing is copied, nothing is written back, and there is no TOC dependency.
Tradeskills itself fills gaps from TradeSkillMaster, then Auctionator
(2026-10-12; the owner allowed naming both in public). Without Tradeskills,
Farmer reads them itself (`Value:OtherPrice`: `TSM_API.GetCustomPriceValue
("DBMarket", "i:<id>")`, then `Auctionator.API.v1.GetAuctionPriceByItemID
("Blackthornes_Farmer", id)`, in a pcall, kept 60 s), "TSM and Auctionator"
on the Loot page (`otherPriceAddons`, on unless unticked, never rename it;
`tools/test_otherprices.lua`), asking TSM first unless "Price Order:" there
says Auctionator First (`priceOrder`, "tsm" unless picked, never rename it;
the owner, 2026-10-25; Tradeskills has the same choice); with none of them, the vendor price. Tradeskills'
`CLAUDE.md` asks its side to keep that global, `Prices` and `GetValue(itemID)`
stable; if Farmer needs more from it, change both repos together.

CurseForge project IDs: Farmer **1710618**, Tradeskills **1710638**. Both
release the same way (a `vX.Y.Z` tag on `main`, checked clear to post before
upload; see the README under Releasing). v0.2.0 of both is on CurseForge.

## What Tradeskills calls here

Tradeskills' Gather tab has a **Set goal** button that makes a goal here for a
material its craft queue needs. It shows only when Farmer is loaded and
calls, inside a pcall:

```lua
_G.BlackthornesFarmer.Goals:Find(name)            -- optional
_G.BlackthornesFarmer.Goals:Set(name, amount)     -- goal table, or nil and why
_G.BlackthornesFarmer.GoalsUI:Show()
_G.BlackthornesFarmer.Goals:Remove(name)          -- true when there was one
```

Since 2026-10-11 a goal Set goal made follows Tradeskills' queue: when the
queue changes, Tradeskills calls `Goals:Set` again with the new amount, or
`Goals:Remove` when nothing queued needs it, but only while the goal's
`target` is still the one it set (a goal the player changed here is left
alone). Keep the `_G.BlackthornesFarmer` global, `Goals:Find`, `Goals:Set`
(returning the goal with `item`, `target`, `have` and `done`, or nil and a
reason), `Goals:Remove` and `GoalsUI:Show` stable.
If one has to change, change Tradeskills' `Logic/FarmerGoals.lua` too.

Goals belong to the character that set them (`goal.owner`, its GUID since
2026-10-11; "Name-Realm" before, still read as that character's by
`Goals:IsOwner` and given the GUID when it gathers toward it or changes
it), since a goal counts one character's bags, so `Find` and `Set` act on
the character playing. A goal saved before owners existed shows on every
character until one gathers toward it or changes it.

## Craft or farm (Tradeskills' Your time view)

The owner said yes (2026-10-15, from a mockup) to weighing a craft's
materials farmed against sold as they are and against bought. Tradeskills
works it out (its `Logic/CraftOrFarm.lua`, the Profit tab's YOUR TIME
view) and asks Farmer how long you take to farm one of a material, inside
a pcall, read only:

```lua
_G.BlackthornesFarmer.Pace:ForItem(item)   -- item ID or name
  -- { seconds, kind ("kill", "skin", "gather"), source, zone, samples,
  --   perAction }, or nil and { samples } while too little is behind it
```

`Logic/Pace.lua` reads only the player's own play: kills at the mob's own
pace (`Stats:SecondsPerKill`, never the average over every mob), skins
(`skinLog`) at that pace, and gathers (`gathering.pace`), each source only
once `MIN_SAMPLE` (20) are behind it; the fastest wins. Never a database
rate and never guild data. Hidden items and sources are left out. Laid
out once as a lookup by name, kept `KEEP` seconds. Tested in
`tools/test_pace.lua`. Keep the call and fields stable; if one changes,
change Tradeskills' `Logic/CraftOrFarm.lua` too.

Back the other way, the material tooltip (`UI/ItemTooltip.lua`) adds
"Sold as it is" and "As CRAFT", each gold an hour, under the farming line
when Tradeskills names a craft that pays more for your time:

```lua
_G.BlackthornesTS.CraftOrFarm:ForMaterial(itemID)
  -- { name, recipeID, perHour, rawPerHour }, or nil
```

"Craft or sell" under Tooltips on the Map & goals page
(`itemTooltipCraft`, on unless unticked, never rename it) and `/farm
tooltip craft [on|off]`. Tested in `tools/test_itemtooltip.lua`. Not yet
seen in game.

## Find a material (Tradeskills' Disenchanting tab)

The owner said build it (2026-10-16): Tradeskills' Find a material view
lists, for one enchanting material, the mobs whose drops break into it,
from the player's own kills only. `Logic/DisenchantFarm.lua` answers,
inside a pcall, read only:

```lua
_G.BlackthornesFarmer.DisenchantFarm:Best(gives, max)
  -- gives(itemID): how many breaking one gives on average, asked once each
  -- { { mob, zone, shownZone (Spots.Show), kills, perKill, seconds, perHour,
  --     items = { { id, name, corpses } } } }, best a kill first
_G.BlackthornesFarmer.DisenchantFarm:DroppedBy(itemID)  -- mob that dropped it most, or nil
_G.BlackthornesFarmer.DisenchantFarm:Show(mob)          -- opens the loot table; true when it did
```

Only `Harvest.records` (never shipped or guild data), a mob by name and
zone once `MIN_SAMPLE` (20) corpses are behind it, suffixes grouped
(`GroupedItems`), hidden mobs and items left out, an hour only at the
mob's own pace (`Stats:SecondsPerKill`). Nothing is written. Tested in
`tools/test_disenchantfarm.lua`. Keep the calls and fields stable; if one
changes, change Tradeskills' `Logic/MaterialFinder.lua` too.

## Farmed (Tradeskills' Profit by method)

The owner said build it (2026-10-16): an auction sale Tradeskills knows
no cost for goes under "Farmed" when you got the item yourself, not
"Other sales". `Logic/Looted.lua` answers, inside a pcall, read only:

```lua
_G.BlackthornesFarmer.Looted:Has(item)   -- item ID or name; true or false
```

Only the player's own `Harvest.records`, `gathering.nodes` and
`fishing.spots` (never shipped or guild data), laid out once as a lookup
by name and ID and again when a corpse, gather or cast is recorded, at
most every `GAP` seconds. Nothing is saved. Tested in
`tools/test_looted.lua`. Tradeskills' Sell list (its
`Logic/SisterKeeps.lua`, the same day) also reads `Butler:Advise` and
`Value:Contents(name)`, so keep those as they are too. If one changes,
change Tradeskills' `Logic/MethodProfit.lua` and `Logic/SisterKeeps.lua`.

## Goblin Gold (Tradeskills' gold bar)

The owner said build it (2026-10-20, from a mockup): Goblin Gold's hover
card shows this week's gold from mobs beside how many you killed and what
their loot was worth. Tradeskills asks, inside a pcall, read only:

```lua
_G.BlackthornesFarmer.Stats:KillsAndLoot(7)   -- { kills, loot, coin } over the last 7 days, today in
```

From `farmStats.days` only (the player's own play, account wide): `loot`
is `drops` plus `grey` as priced when looted, never gathering or fishing.
Tested in `tools/test_stats.lua`. Keep it stable; if it changes, change
Tradeskills' `GoldGoal:Sources` too.

## Kill goal

A player asked, the owner said build it from a mockup (2026-10-20): a goal
of a number of kills, of any mob or one, and a summary when it is done.
`Logic/KillGoal.lua` keeps one per character by GUID in
`killGoals[guid] = { goal, last }` (account wide, never rename it): the
goal counts only kills from the moment Start is pressed
(`KillGoal:Corpse`, from `Tracker:Record`, never skinning windows), each
corpse once (a later window on it adds its new items, `corpse[3]`), its
coin, items by mob, farming time (gaps under `BREAK`) and XP
(`GainedXP`, from `XP:Update`). It lives apart from `ns.db.goals`, so
Butler, Tradeskills and the arrow never see it. It shows first in the
Goals panel (`GoalsUI:List`, a sword, "N to go" and time left at your
pace) with the usual 25%, halfway and 75% tags; it never names or hints
at the kill milestones. Done, `last` keeps the summary and
`UI/KillGoal.lua` opens Goal Done! (Time, Gold, Gold an Hour, XP Gained,
WHAT EACH MOB DROPPED, best drop); Got It takes it off the panel. The New
Goal box (Item or Kills, How Many:, Which Mobs:) opens from the panel's
Set another and `/farm killgoal`; `/farm killgoal 1000 [mob]`, `stop`,
`summary`; Settings, Map & goals, "Kill Goal:" Open and Summary; a Kill
Goal button on the Stats tab once one is done. Its windows share
`killGoalScale` (never rename it). Tested in `tools/test_killgoal.lua`.
Not yet seen in game.

## What Butler calls here

Blackthornes Butler (`Blackthornes/Blackthornes_Butler`, 2026-10-10) tells
the player what to do with each bag item, and asks whether a goal here
needs it. It calls, inside a pcall, read only, with no TOC dependency:

```lua
_G.BlackthornesFarmer.Butler:Advise(itemID)   -- a table, or nil; never raises
```

`Logic/Butler.lua` answers for the goals of the character playing (a goal
saved before owners counts, as `Goals:Find` has it), or nil when none is
for that item:

- `goal`: the goal's item name.
- `have`: how many the character has toward it (`Goals:Have`, bank
  included when goals count it; the saved `have` if the client will not say).
- `target`: the goal's number.
- `need`: `target - have`, never below 0 (0 once the goal is reached).

Goals are kept by name, so an item ID is matched by the ID the database
gives the goal's name, else by the name the client gives the ID (kept per
ID once given). Butler asks once per bag item in a burst, so the goals are
laid out as a lookup once and built again only when `Goals.version` moves
(`Set`, `Remove`, `ClearDone`) or the character's name comes in; only an
item with a goal reads its count. Keep the global, `Butler:Advise(itemID)`
and these four fields stable; if one has to change, change Butler's
`Logic/Sisters.lua` too.

## Sharing with the player's other account

The owner agreed (2026-10-11, a viewer's question on stream: can Farmer track
across characters and accounts?). Farmer's saved data was already shared by
every character on one account (`BlackthornesFarmerDB`; only goals are per
character, by `owner`), but WoW keeps accounts apart, so `Logic/Share.lua`
passes it over addon whispers the way Tradeskills' account link does
(`Logic/AccountLink.lua`, setting `linkNames`, both sides name each other).
Farmer has its own pairing, `shareNames`, rather than reading Tradeskills',
since neither addon depends on the other.

`Core/Comm.lua` and `Core/Serialize.lua` are Tradeskills' files brought over
(the prefix is `BFRshare`, so the two never read each other's messages; the
test command is gone and `Comm:Start`/`Stop` listen only while sharing is on,
since every addon's messages come through in a raid). A fix to the wire or
the serializer belongs in both repos.

What is shared is counts only: the loot harvest (`ns.Harvest.records`), the
kill tally (`tracker.mobs`), `gathering.nodes` and `fishing.spots`. Never
goals, settings or positions. How it never counts one twice: a side sends
only its own (its totals less what it has taken, `Share.Export`), and the
other adds only the rise over the most it has ever taken from that partner
(`Share.Merge`, kept in `shareIn[partner].credit`; a partner whose counts
fell, a reset, adds nothing until they pass it). So nothing goes round a
loop and nothing is relayed to a third account. Saved, never renamed:
`shareData` (off by default), `shareNames` (full names, comma apart) and
`shareIn` (`[partner] = { name, hashes, credit }`). Taken counts are merged
into the ordinary tables and cannot be taken back out; nothing is deleted. A
kill tally is made through `Tracker:GetMob`, which sets a pre-coin tally
aside first. Records are whitelisted and type-checked (`Share.CleanRecord`),
and a record whose key is not what its own fields make is refused. Lists are
built a slice a frame (`Share.SLICE`), never in combat, and sent a batch at a
time as the pacing frees up. Tested in `tools/test_share.lua`, which plays two
accounts over a pretend chat. Not yet seen in game; the owner has one account,
so only Tradeskills' one-account whisper test (full names, 2026-10-07) backs
the wire.

Naming several characters (2026-10-11): a partner is the account, not the
name. The manifest carries `i`, the sender's Farmer id (`Transfer:SourceId`,
`exportId`), and `Share:Identify` keeps it in `shareIn[partner].account`; a
second character with an id already held, or this account's own, is a
duplicate (`state.duplicate`) and nothing is taken from it. First heard
holds the ledger. Tested in `tools/test_share.lua`.

## Sharing with the guild

The owner asked (2026-10-13) for Farmer to share with the guild too, off by
default, and then that a guildmate's data must never raise the player's own
counts: "you've killed 3/20 should not update", only "the data goes in".
`Logic/GuildShare.lua` reuses `Share`'s whispered conversation (manifest,
want, records) through hooks on the partner state (`sections`, `store`,
`book`); only how partners are found and where counts go differ.

- Finding guildmates: each side says hello on the GUILD addon channel
  (`G<farmer id>:<hash of its drop records>`) 30 s after login and every
  quarter hour (2026-10-22, a player's report), and once (at most a minute
  apart) to someone new. A hello whose
  hash is not the one last taken in full (`guildIn[...].top`) queues that
  guildmate; one is synced at a time, each at most every ten minutes, waited
  on while its records keep coming (`STILL_COMING`), and a
  guildmate's whispers are heard only after their hello
  (`GuildShare:PartnerFor`, which `Share:PartnerFor` falls back to).
- Only drop records ("h") go, only the sender's own, and they never join
  the player's: they are kept in `guildDrops` (Harvest's record shape) with
  ledgers by Farmer id in `guildIn["guild:<id>"]` (account wide; never rename
  `shareGuild`, `guildDrops` or `guildIn`). Kill tallies, session loot,
  Rankings, the tooltip kill count, the rank-up pop-up and every kill
  milestone read only the player's own data and never see the guild's.
- What shows: records from `MIN_SAMPLE` (20) corpses become database rows
  with provenance "guild" (`DB.RANK`: forever beats guild beats classic; a
  guild row keeps the Classic row it replaced in `replaced`, and
  `DB:RemoveSource` puts it back), a few records
  a frame and only the changed ones (`GuildShare:Publish`). A mob's loot
  table shows no rate before the player's own (the owner, 2026-10-15), the
  guild's included. Nothing in the windows says "guild" (the owner, 2026-10-13:
  "The UI should be all about the player"): no tag, no note; only Settings
  and `/farm share` name it. Turned off, the rows leave and the data stays.
- Safety: records must pass `GuildShare.Plausible`, at most `MAX_GUILDMATES`
  (20) are kept, the other account named in Settings is left to account
  sharing, and `/farm share guild forget confirm` deletes `guildDrops` and
  `guildIn` and turns it off; there is no Settings button for it, since
  Settings never deletes data.

A tick box under YOUR GUILD on the Sharing page, "Guild Status:" under it
(`GuildShare:Status`, from the save; the names box shows `Share:Status`
the same way), and `/farm share guild on|off`. Tested in `tools/test_guildshare.lua` (three accounts and an alt
over a pretend chat). Not yet seen in game.

## Sending drops to Blackthornes

The owner asked (2026-10-15): players can opt in to send their drop
records to his characters, for the shipped data. Off by default
(`shareDrops`, never rename it), never announced: one tick box on the
About page of Settings (2026-10-17) and `/farm share drops on|off`. Only
North American clients send or see the box (`Contribute:InRegion`,
`GetCurrentRegion` 1, or 110 on the Forever test client, else `GetCurrentRegionName` "US"; unknown sends
nothing). `Logic/Contribute.lua` is guild
sharing's conversation one way: the sender whispers a hello (`Q<id>:<hash>`)
to each name in `Contribute.RECIPIENTS` (full names, kept only in code;
never shown in chat or Settings; the game's "No player named" line is
hidden, so a player can't tell whether a name exists on their realm) 30 s
after login and every half hour. Only those characters answer, by full
name (`Contribute:Receiving`). Share's states carry `giveOnly` (the sender
never asks for anything) and `takeOnly` (the receiver never says what it
has), so nothing comes back to the player. Only the sender's own "h"
records go, checked by `GuildShare.Plausible`, kept apart on the receiver
in `sharedDrops` with ledgers by Farmer id in `sharedIn` (never rename
either; at most `MAX_SENDERS`); they never join the receiver's own counts
or show in the windows. One sender is synced at a time, each at most every
half hour, and a chat line says "Got drops for N mobs from NAME."
Each finished share is kept on the receiving account in `sharedLog`
(`{ at, name, mobs }`, the newest `LOG_KEEP`; never rename it) and read
back with `/farm share drops log` (typed only, not in the help line). Only
English clients send (records keep the client's names). At a release,
`tools/harvest_import.py --shared` folds `sharedDrops` into the shipped
data (in memory; the save is never changed, ledger names never read).
Never announce the fold-in. Tested in `tools/test_contribute.lua` and
`tools/test_harvest_import.py`. Not yet seen in game. A recipient whose
first name trips `check_package.py`'s owner's-name check would stop the
release; check before adding names. Two recipients since 2026-10-18, the
owner's two characters on one account (one save between them), so the one
online takes a share and the other skips it. Tradeskills has the same
choice for disenchants and recipe levels (its `Logic/Contribute.lua`,
"Sending data to Blackthornes" in its `CLAUDE.md`), with the same two
names; change both lists together.

## Giving data to another player

A player asked (2026-10-11, the owner agreed) to export Farmer's data and
have someone else merge it into theirs. `Logic/Transfer.lua`, `UI/Import.lua`
(`/farm give`, `/farm take`, both with Settings buttons on the Sharing page).
It is account sharing by text: `Transfer:Make` builds
`BFR1:<id>:<part>/<parts>:<checksum>:<base 64 of Serialize.Encode>`, one line,
in parts of about 200,000 characters (`PART_RAW`), each complete in itself, and
the Export window hands it out with a Next part button. Nothing in it but
counts (the same sections and `Share.Export` as sharing, so it leaves out
everything taken from anyone: nothing is relayed). `id` is this Farmer's
`exportId`, made once and kept (never rename it). `Transfer:Parse` checks the
line, checksum and `Serialize.Decode` (data only, never run), then every
record through `Share.CleanRecord` and the key check, and refuses a count
over `MAX_COUNT`, a drop record with far more items than corpses
(`MAX_PER_CORPSE`) and more than `MAX_RECORDS` records a section. Nothing
changes before Apply. `Transfer:Apply` merges with `Share.Merge` into the
ledger `shareIn["import:<id>"]` (`kind = "import"`; never rename it), so the
same text twice adds nothing and a newer one adds the rise; `Transfer:Remove`
subtracts exactly the ledger from the records (dropping one that is left
empty) and deletes it. Everything is worked a few records a frame. Tested in
`tools/test_transfer.lua` and `tools/test_importwindow.lua`. Not yet seen in
game. A fix to `Core/Serialize.lua` still belongs in Tradeskills' too.

## Grind: Leather, Ore and Herbs

The owner said yes (2026-10-14, from a mockup) to the Grind tab giving
Leather, Ore and Herbs beside Cloth (`grindGives`: "cloth", "skinning" for
Leather, "ore", "herbs"; never rename it or its values). Leather lists mobs
as Cloth does, with the skill to skin them (Classic's rule,
`Grinding.SkinSkill`, a mob's own `requires` first; not yet seen in game)
and what one skin is worth. It is offered while the character knows
Skinning even with "Hide skinning" ticked (`Grinding.OffersLeather`).
Ore and Herbs (`Logic/GrindGather.lua`) list zones and their nodes, not
mobs: the type chips hide, the footer says your skill, and a node your
skill does not reach is greyed with "125, you have 87". A click aims the
arrow at your mapped spots (`GrindGather:NodeCamp`, `Arrow:Grind`).

Two new records, the player's own play only, account wide, never renamed:
`skinLog[mob]` (skins by guid, once each, and their items, for worth a
skin; `GrindGather:NoteSkin` from `Tracker`) and `gathering.pace[zone|node]`
(seconds between gathers in one zone under `GrindGather.BREAK`, gathers and
items, for worth an hour once `MIN_SECONDS` is reached;
`GrindGather:NoteGather` from `Gathering:Record`). Guild data never feeds
any of it. The data rows are kept until `DB.hiddenVersion` or the counts
move (`GrindGather:DataRows`). Tested in `tools/test_grindgather.lua`.
Not yet seen in game.

## Grind: Fish

The owner said build it (2026-10-24, from a mockup): a **Fish** chip on the
Grind tab beside Cloth, Leather, Ore and Herbs (`grindGives` "fish"; never
rename it). It lists the spots you fished, grouped by zone, from your own
casts alone: the pools you moused over before casting in `Theme.colors.pool`
(a new palette entry) and open water for the rest of each zone. Nothing
shipped and nothing from the guild ever reaches it, and the level boxes are
ignored, since a spot has no level.

Columns SPOT, CASTS, BEST CATCH, PER CAST and AN HOUR, sortable as the other
views are (`GrindingUI:SortedSpots`, the same `grindColumns`). Catch rates
and a cast's worth wait for `Fishing.MIN_CASTS` casts, as a mob's kills do;
before that BEST CATCH counts ("Oily Blackmouth, 12 so far"). The hover card
is WHAT YOU CAUGHT, a click aims the arrow where you fished
(`GrindGather.FishCamp`, `Arrow:Grind`) and a right-click hides the spot
through the usual hide list.

AN HOUR is new: one saved key, account wide, never renamed,
`fishing.pace[spot key]` = `{ seconds, casts }`. `Fishing:NotePace` counts
the gap between two casts at the same spot only while it is under
`Fishing.BREAK` (300), so a walk away, a flight or a night off never count;
`Fishing:SecondsPerCast` answers nothing until `Fishing.MIN_SECONDS` (600)
are behind it, and the row says "Fish a while longer" until then.
`Fishing:WorthPerHour` is a cast's worth at that pace. `Fishing.paceVersion`
moves with every cast. Sharing carries only `fishing.spots` (Share's
section "f"), so the pace never leaves the account.
`Logic/GrindGather.lua` has `FishSpot`, `FishZones`, `FishCamp` and
`FishLine`; `UI/Grinding.lua` the `fish` layout, `CatchText`, `FishTexts`,
`FishZoneText`, `FishRows`. `/farm grind fish`. Tested in
`tools/test_fishview.lua`. Not yet seen in game.

## The fishing bar (Classic only)

A player asked, the owner approved the mockup and said build it
(2026-10-25). `UI/FishingBar.lua`: a small house-framed window ("Fishing",
fold gem, size grip) that shows only while a fishing pole is in the main
hand (item class 2, subclass 20). **Cast** is a secure button casting
Fishing by the client's name for spell 7620. **Add Lure** (both plain metal, the owner 2026-10-25) opens a list of
the Era lures in the bags (`FishingBar.LURES`), best first, each row a
secure button running "/use item:ID" then "/use 16"; the game's own box
asks before it replaces a lure. Under them, the lure's time left
(`GetWeaponEnchantInfo`, read every `TICK` seconds only while shown) and
the Fishing skill (`GatherToCap.ReadSkill`). Attributes are set only out
of combat; the bar hides at `PLAYER_REGEN_DISABLED` and at a vendor, bank,
mailbox, auction house or trade. The close gem puts it away until the pole
comes off and goes on again. "Fishing Buttons:" under FISHING on the Loot
page (`fishingBar`, off unless ticked) and `/farm fishingbar [on|off]`
(`/farm fishing` is the chat list it always was). Saved, account wide,
never rename them: `fishingBar`, `fishingBarX`, `fishingBarY`,
`fishingBarScale`. Tested in `tools/test_fishingbar.lua`. Not yet seen in
game.

## The gold plaque

Buttons that sit out on the screen on their own wear the gold plaque (the
owner picked it from a mockup, 2026-10-27, "Option B"): a gold rim with a
red gem at each end round dark glass, the item's icon in a small gold
frame, a first line saying what the click does and a second under it, and
a soft glow that breathes while it waits (Effects Full; still on Subtle,
none on Off). `UI/Plaque.lua` is the same file in Pets, Equipment and
Farmer (a fix to it belongs in all three): `Plaque.Create(parent, { name,
template, width })` and `:SetLines`, `:SetIcon`, `:SetGlowing`, `:Flash`.
Here it is the fishing bar's Cast ("Fishing 87 / 150" under it) and Add
Lure ("Bright Baubles, 3 left"; it glows while no lure is on and one is in
the bags). A plaque given a fixed width wraps both lines and grows taller to fit them
(`fitHeight`; the fishing bar sets both to the taller and grows by as
much, `FishingBar:FitButtons`), so other languages never end in "...".
Each catch flashes Cast gold (`FishingBar:Caught`, from
`Fishing:OnLoot`), a small cheer. Tested in `tools/test_fishingbar.lua`.
Not yet seen in game.

## One key fishing (Classic only)

A player asked, the owner said build it with the words he approved
(2026-10-26). `UI/OneKeyFishing.lua`: one key, "Fish" under Blackthornes
Farmer in the game's Key Bindings (`Bindings.xml`, which the client loads
by itself; the binding clicks the hidden secure button
`BlackthornesFarmerFishKey`). With a fishing pole in hand and no lure on,
it puts on the best lure in the bags (the fishing bar's `LureMacro`);
otherwise it casts Fishing. While Fishing channels, the key is pointed at
the game's INTERACTTARGET with `SetOverrideBinding`, so the same key reels
in the bobber; the override goes when the channel ends or a fight starts.
Only while you face your own bobber (the owner, 2026-10-27: a vendor or
mailbox closer than the bobber was opened instead): `OneKeyFishing:Aim`
points the key at INTERACTTARGET while the soft interact target is a game
object with the bobber's entry ID (`BOBBER_ID`, 35591) or a bobber's name
(`OneKeyFishing.IsBobber`), else at a plain hidden button
(`BlackthornesFarmerFishNote`) that shows "Face your bobber to reel in."
through `OpenNote:Notice`. Looked at again on
`PLAYER_SOFT_INTERACT_CHANGED`, or every `LOOK` seconds while the line is
out on a client without it; the binding is set only when the aim moves.
For the cast, the interact reach is raised (`NodeSparkle:RaiseReach(true)`)
and `SoftTargetInteract` turned to 3 when lower, its old value kept in
`oneKeyFishingInteract` and put back after (or at the next login).
Attributes and bindings change only out of combat. "One Key Fishing:"
under FISHING on the Loot page (`oneKeyFishing`, off unless ticked); turned
on with no key set, chat says where to set one. The binding's name has its
own locale key, `Fish (key binding)` (the verb), apart from the Grind
tab's "Fish". Never rename `oneKeyFishing` or `oneKeyFishingInteract`.
Tested in `tools/test_onekeyfishing.lua`. Not yet seen in game.

`/farm fishing check` (typed only, the owner asked how to test a "PULL!"
bite alert, 2026-10-27; `UI/FishingCheck.lua`): the game tells addons
nothing at a bite, so for the next `CASTS` (8) Fishing casts it writes down,
with times, every event (chat and the combat log left out, no values but a
unit token or the game's error text) and each change to the soft interact
target, the mouseover, the bobber's nameplate and the game's icon on it (a name only as
"changed", never the name itself; the owner, 2026-10-27), until a moment after the loot window. Each cast rewrites `lastProbe`. Read
the probe: whatever changes a little before LOOT_OPENED every time is the
bite. Tested in `tools/test_fishingcheck.lua`.

## Legacy perks (read only)

The owner said build it (2026-10-22): Forever's Legacy trees give
perks that change what a gather or a cast gives, and records made with
them would push the shipped rates up. `Logic/Legacy.lua` reads, inside a
pcall, the ranks the character has set in two of them, Bountiful Harvest
(herbs, ore, skins) and Luremaster (fish, with a lure on). It never
spends a point and never suggests one (the owner: "we just read what
they have set"). The config is found by a trait system the client calls
Legacy (`GetConfigIDBySystemID`), else by the trees holding nodes
`NODE_FIRST` to `NODE_LAST` (a few trees a frame, never in a fight); the
perks are told apart by English name, so other clients record as before.
No rank read means nothing changes. A gather, skin or cast made with one
is still counted in its record, and also noted beside it in `boosted`
(the record's own shape: `{ gathers | casts | corpses, items, rank }`;
never rename it); a skinned corpse moves aside whole. What leaves the
save as a rate leaves those out: the export and the shipped data
(`Harvest:ExportRecords`, `Fishing:CountCasts(true)`, `Legacy.Without`)
and every share (Share's `CreditsFor`). `/farm gathering check` has a
Legacy line. Never announced. Tested in `tools/test_legacy.lua`. Not
yet seen in game.

## Gather to cap

The owner approved the mockup (2026-10-20): the Grind tab's Ore, Herbs and
Leather views (Leather while the character knows Skinning) open with a
path from your skill to 300. `Logic/GatherToCap.lua` works it out;
`UI/GatherToCap.lua` draws it above the list (`GrindingUI:PlacePath`
moves the headings and list down by its height). A heading ("MINING 87 /
150", skill and cap from the client, `GatherToCap.ReadSkill`), a meter a
segment a stop, then dark glass rows: the last stop done (dimmed, a
check, "Done"), the one you are on (`glassActive`, gold edge, its item's
icon, "now to N", your mapped spots there and about how many gathers are
left, gold an hour and a primary Show the Way: `NodeCamp`, then
`Arrow:Grind`) and up to three later ones ("Train RANK SKILL at N first."
when they pass your cap, else the zone's mob levels). A footer and Set
Goal (`Goals:Set` for the stop's item, at least `MIN_GOAL` (20) more than
you have, then `GoalsUI:Show`). Stops are Classic's ladders
(`GatherToCap.LADDERS`, the data's skill winning; Skinning by mob level
bands, the camp you skinned most); the gathers left follow Classic's
skill-up chance (`Chance`: sure to 25 over, none past 100, never under
`MIN_CHANCE`); the zone is where you mapped the most (`gathering.spots`),
else the zone you stand in when it has the node and is in reach, else the
data's nearest your level on your side (`SIDE_ZONES`). Worth is your own pace
(`gathering.pace`, `skinLog`) where you have it, else a typical hour.
Nothing saved; it only reads. Laid out again only when the skill, cap,
level, spots, `GrindGather.paceVersion` (moved by `NoteGather` and
`NoteSkin`) or `DB.hiddenVersion` move. Hidden nodes and sources are left
out, and guild data never reaches it. Tested in
`tools/test_gathertocap.lua`. Not yet seen in game.

## The panel kept between sessions

The owner asked (2026-10-11) for the kills and loot panel to stop starting
empty after every /reload or relog, per character, with a way to clear it,
then (2026-10-13) for it to start empty each session again, all data kept.
So keeping it is now a choice, off by default: "Between sessions" on the
Kill tally page (`keepPanel`, account wide, never rename it) and `/farm
tracker keep [on|off]`. Unticked, `Session:Restore` reads nothing and
logout writes nothing; a run saved while it was ticked stays in the save
untouched. Ticked, it works as below. `Logic/Session.lua`: at `PLAYER_LOGOUT` (a reload too) Tracker's, Fishing's
and Gathering's session counts, the order last done, coin, best streak,
`ns.lastLoot` and the per-hour clock's play time go in the account save as
`panelSessions[guid]` (never rename it; the GUID from `Goals:Owner`), and
are added back at login, or on the first `PLAYER_ENTERING_WORLD` that reads
the GUID. Nothing is written while playing. A character whose GUID is never
read keeps and gets nothing. Corpses opened (by guid) and the running streak
are not kept. **Clear panel** (`Session:Clear`; the panel's Clear button
beside Sort and Settings > Kill tally, both `TrackerUI.ClearButton`, a
second click within `CLEAR_ARMED` seconds; `/farm tracker clear`) empties
the view only: every tally stays, so it is allowed on the Settings page.
Tested in `tools/test_panelkeep.lua`. Not yet seen in game.

## Search finds your own loot

A player searched "crates" and saw only what the data ships (2026-10-15):
the search read only the database (shipped data, folded in from the owner's
play at each release, and the guild's rows), so anything a player looted,
gathered or fished that the data does not know never showed.
`Search:FoundItems` now adds every item in the player's own harvest,
gathering and fishing records that `DB:GetItem` does not know as a result of
its own ("Your finds", the spots it came from, a rate once
`FOUND_SAMPLE` (20) are behind it, "7 in 12" in the drop column before
that, provenance "forever"). An item the data does know keeps its rows
and gains your spots the data does not list (`Search:WithYourSpots`, a
copy; 2026-10-15, clams off Wrathtail mobs never showed). Nothing is added
to the database, so Rankings, the tooltips and the Grind tab are unchanged;
nothing is saved; guild data never reaches it. Built only when a search
runs and the records moved, at most every `FOUND_GAP` seconds. Found items
have no Goal button (`Goals:Set` knows only database items). A plural
query also matches names by its singular (`Search.Singular`: "crates" finds
Crate), names only, never zones or mobs. Clams and sacks you opened from your
bags count too (2026-10-18, a player saw no Giant Clams and none of the
clams they opened for Iridescent Pearl): what came out shows at the zones
your own kills dropped the clam, "3 in 10" opened, never a guess at a
place (`Containers.changes` moves the search). Tested in
`tools/test_searchfinds.lua` and `tools/test_clamspots.lua`.

Where to farm (`Spots:For`, `MAX` places) keeps the best place of every
clam, chest, node or school by name before any of them takes a second
row, so the clams you opened, found in many zones, no longer push Giant
Clams off. Mobs are ranked as before.

## Quest items in the loot lists

A player asked (2026-10-18, the owner said yes): quest items sell for
nothing, so they read as loot with no price. `Value:IsQuest(name, id)`
(the client's item class 12, else the data's "Quest item" category) marks
them: "Quest" under the count on the Loot tab (`TrackerUI:SessionItems`'
`quest`), "Quest" in the loot table's Per Kill column (`row.quest`) and
"Quest item" on an icon's hover. They stay worth nothing: never a made-up
price, so every total is the same, and `Value:Session` counts them in
`details.quest`, not `unpriced`, so the "no price left out" note leaves
them out. No setting. Tested in `tools/test_questloot.lua`.

## Classic drops in the search

The owner said yes (2026-10-17) to filling the search with Classic's drops
before anyone loots them on Forever. `Data/Data_ClassicDrops.lua` is written
by `tools/make_classic_drops.py <Classic data> <Forever tables folder>`
(never by hand; never name where the Classic data came from): trade goods
and quest items the Forever client still has (Item.csv class 7 and 12),
and recipes (class 9, at `MIN_RECIPE_CHANCE` or better, 2026-10-17),
up to `MAX_SPOTS` ordinary mobs an item (no rares or bosses, at least
`MIN_SPAWNS` spawns in the zone), one real spawn spot each, gathered items
left to the node files. Every row is `searchOnly` and has no `chance`, so
it feeds the search, the item tooltip and Spots, never worth, Rankings
(`Rankings:Spot`), the Grind tab or Moments. `DB:AddSource`'s `SameMob`
matches it by mob and zone (any location): a generated row never joins
one already there, and a forever or guild row takes its place by
`DB.RANK`. In the search your own records do the same
(`WithYourSpots`, `entry.mine`). Rerun it when the tables are pulled again.
Never announced. Tested in `tools/test_classicdrops.lua`.

## Random suffixes count as their item

A player asked (2026-10-15, the owner said build it): gear with a random
suffix drops under its whole name ("Lead Band of the Monkey", "... of the
Owl"), so one green was spread over its suffixes and took far longer to
reach a rate. The saved records are never rewritten (each suffix stays
under its own name); the readers put them together under the item's own
name. `Harvest.RollBase(name, id)` names the item from the client
(`C_Item.GetItemNameByID`), else the data, else Classic's ten two-stat
animal suffixes off the name (for the export tool, which has no client).
`Harvest:GroupedItems(record)` (kept per record until its corpses move) is
read by `ForItem`, `Items` (so the export and the shipped data name the item
once), `Search:FoundItems`; `Tracker:Summary` groups the tally the same way
(the kills panel, the loot table), with a suffix's look standing in
(`Tracker.rollLooks`), and `Value.FoldSuffixes` names the item once in the
best drops. Worth per kill is the same either way. Tested in
`tools/test_suffixdrops.lua`. Not yet seen in game.

## Same name, another zone

The owner asked (2026-10-16): a mob of the same name in another zone gets
its own line. The kill tally keeps, beside each mob's whole tally under
its name (untouched), `tracker.mobs[name].zones[zone]` (never rename it),
each with the tally's own fields. Once a name has kills in two zones it is
split: its lines are keyed `name.."\t"..zone` (`Tracker.ZoneKey`,
`SplitKey`, `NameOf`, shown as "Name (Zone)" by `Tracker.ShowKey`), and
Rankings, the rank-up board, the kills panel, the loot table, worth
(`Value:FromTally`, `FromDatabase` by the key's zone), the mob tooltip and
the nameplates (`Tracker:KeyHere`, the zone you are in) read the line's
tally (`Tracker:Tally`, `Tallies`, `Lines`, `IsSplit`). A plain name is
still the whole. Kills from before were laid out once at login, before any
loot, from the player's own loot records (`Tracker:SeedAllZones`; one zone
is copied whole). Milestones, fanfares, goals, Stats and Moments still
count the whole name. Never shared (Share's whitelist). Tested in
`tools/test_zonelines.lua`.

## Drops only

A player asked (2026-10-11, the owner agreed) for Farmer to leave skinning
out and show only drops, on by default (the owner, 2026-10-11). "Hide
skinning" on the Loot page of Settings (`hideSkinning`, account wide, on
unless unticked; never rename it) and `/farm skinning [on|off]` (on shows
skinning). Ticked, `DB:HidesItem` and `DB:HidesSource`
leave out every `kind = "skinning"` source and every item the data names a
skinning spot for (`item.fromSkinning`: leather, hides, scales), since a
skin opens a loot window and recorded loot has the leather as a drop. The
search is the exception (the owner, 2026-10-15: "skinning should be
searchable, it just doesn't pollute mob value"): it lists skinning items and
spots ticked or not and leaves out only the hide list (`DB:IsHiddenItem`),
while its PER KILL worth (`Value:ForMob`) still leaves skinning out.
`DB:ByName` (Rankings, worth estimates), `Value:FromTally`,
`Tracker:Summary` (panel, loot table), the Grind tab and the tooltip line
follow it, and so does the session (the Loot tab, its looted count, a
mob's loot worth, the session's worth and gold per hour, `Value:Session`,
`Tracker.Counts`); recorded data is never changed, and goals and their
arrow still follow a goal for leather. The Grind tab's Leather view is the
one exception: it shows while the character knows Skinning, ticked or not
(see "Grind: Leather, Ore and Herbs"). Every item a skinning window gives
is noted account wide in `skinnedItems` (`DB:NoteSkinned`,
`DB:WasSkinned`; never rename it), so a skin the data lists only as a drop,
or one Forever added, counts as skinning too. `DB:SetShowSkinning` moves `DB.hiddenVersion`
and calls `DB.hideWatchers`, so only the lists that show it redraw.
Tested in `tools/test_showskinning.lua`.

The hide list (the owner asked the same day for a blacklist): a mob, node
or item the player never wants to see, kept account wide in `hiddenItems`
and `hiddenSources` (`[lower case name] = name`; never rename either; an
item is keyed by the data's English name). `DB:Hide`, `DB:Unhide`,
`DB:IsHiddenItem`, `DB:IsHiddenSource`; `DB:HidesItem` and
`DB:HidesSource` answer for both rules, and the same `hiddenVersion` and
watchers redraw. A right-click on a row in the search, Rankings, Grind,
the loot table or the kills panel opens `UI/HideMenu.lua` ("Hide NAME",
nothing hidden until a line is clicked); `UI/HiddenWindow.lua` (`/farm
hidden`, Settings > Loot, `hiddenScale`) lists them with Show again;
`/farm hide <name>` and `/farm unhide <name>`. Rankings, the panel's
mobs (`Tracker:SessionMobs`) and the Loot tab (`TrackerUI:SessionItems`)
leave hidden ones out; recorded data is never changed. Tested in
`tools/test_hidelist.lua`.

## The shared minimap button

A player asked, the owner said build it from a mockup (2026-10-28), in all
five addons: one minimap button for every Blackthornes addon loaded, whose
click opens a small menu (the house frame, "BLACKTHORNES" on the plate, a
dark glass row for each addon with its icon, name and what it does). A
row's left-click opens the addon, right-click its settings; Farmer's
middle-click brings back its panels and Equipment's Shift-click toggles
the upgrade quest. `UI/SharedMinimap.lua` is the same file in all five (a
fix to it belongs in all five), and so is `tools/test_sharedminimap.lua`.
There is no shared core addon: every copy signs up in
`_G.BlackthornesMinimap`, each addon joins with its own button
(`SharedMinimap:Join`), and the copy with the highest `FILE_VERSION` draws
the shared button and menu. It is on by default (the owner, 2026-10-28):
"Combine Addon Buttons:" in each addon's Settings, ticked unless unticked;
unticked, every addon keeps its own button. Only our own buttons are hidden
or shown, never the game's. Saved in every loaded addon's account save,
account wide, never rename them: `minimapButton` ("shared" or "each", nil
reads as shared), `minimapButtonAt` (the newest answer wins) and
`minimapSharedAngle`. Never call it "One for All" (another addon's name).
Every addon's own button also takes left-click to open and right-click for
settings. Not yet seen in game.

## The settings pages (from Tradeskills)

The owner asked (2026-10-09) for Tradeskills' Settings upgrade in Pets,
Equipment and Farmer. `UI/SettingsPages.lua` is the same file in all three
(a fix to it belongs in all three): category pages along the top
(`settingsPage`, the one left on), two columns a page, what a setting does
as the row's tooltip ("Show descriptions", `settingsDescriptions`, off by
default, puts it back under the rows), "Find a setting", and Text size
(`textSize` normal/large/larger adds 0/1/2 to `Theme.sizes`, now a lookup
over `Theme.BASE_SIZES`; read once, so it waits for /reload). The window
fits its fullest page, so no page scrolls. Add a setting with
`pages:Row(page, column, label, description)` and
`pages:Section(page, column, "HEADING")` in `UI/Settings.lua`; every
`/farm` command has a button or control there (`tools/test_settings.lua`
checks `ns.commandOrder` against them), but never one that deletes data:
resets stay typed `reset confirm` commands. Commands that only list things
in chat are typed only (the owner, 2026-10-15; the test's `chatOnly`
list); checks and debug are typed only too (the owner, 2026-10-23). The owner's Settings standard
(2026-10-15): labels in Title Case ending with ":" ("Text Size:"),
one-word buttons ("Open", "Show", "On"), a hover only when it adds
something (`pages:Row(..., nil)` shows none), never "Same as /farm ...",
section headings ALL CAPS. The pages are UI, Kills, Loot, Map & goals,
Sharing, Advanced and About. The minimap button always shows: no setting,
no `/farm minimap`, and a saved `minimapHidden` is kept but not read.
Word choices are drop-downs, never < > pickers or word steppers (the
owner, 2026-10-23): `Widgets.CreateChoice` takes a stepper's opts
(min, max, step, value, format, onChange) on Pets' `Widgets.CreateDropdown`
and answers `SetValue(value, silent)`, `GetValue()`, `.text` and
`:Pick(value)` (what a menu click does); only numbers keep a +/- stepper.

## The house frame (Titanforged)

The owner picked this look for all four addons on 2026-10-04 (Tradeskills had it
first). It's the game's own window shape with the light turned up: a gold
metal rim with corner gems, a round portrait with the addon's emblem, the
name on a plate across the top edge, a red close gem, and tabs hanging below
the window. Buttons are raised metal with gold labels; the main action is
solid gold with dark "ink" lettering, and only a gold face gets ink (a
button given its own dark `baseColor` keeps a gold label).

`UI/Titanforged.lua` (`Titanforged:Dress(frame, opts)`, `:Opened(frame)`)
is Tradeskills' file with the plate measuring by size, since Farmer's
`Theme.TextWidth(size, text)` differs. The art is `Media/Frame/*.tga`, drawn
by `tools/make_frame_art.py` with `EMBLEM = "pick"`; rerun it, never edit the
TGAs. Hanging tabs are `Widgets.CreateTabStrip(..., { hanging = true })`,
ported from Tradeskills. Glows and glints follow the Window effects setting
(`Motion.Level()`). The search window wears the whole frame; settings,
export and the loot table the plate and close gem; the goal picker and
Where to farm the rim and close gem (their own titles stay inside). The
kills panel, the goals panel, banners and toasts stay up while playing and
keep their own frame, though their lines are dark glass too (2026-10-12:
`TrackerUI.Stripe` shades each line once a redraw, the open mob is
`glassActive` with a bright gold edge, an open card's lines sit on its
`glassAlt` card; the goal cards and spot rows alternate by index). Anything placed inside a dressed window stays 6 pixels
in from its edge, or it covers the rim.

Every window wears the house size grip (the owner, 2026-10-11, as in
Tradeskills, Equipment's quest panel and Butler): `Widgets.CreateSizeGrip`,
a gold-edged square with six dots outside the bottom right corner. Dragging
changes only the window's scale, from its top left corner, 50% to 150%, so
nothing is laid out again mid-drag and no text is cut; right-click is
normal size. Saved in percent, account wide, never renamed: `windowScale`
(search window, Rankings and Grind), `trackerScale` (kills panel, its own
grip), `settingsScale`, `lootTableScale`, `exportScale`, `goalsScale`,
`goalSpotsScale`, `goalPickerScale`. A new window gets one too
(`tools/test_windowgrips.lua`). The goal arrow is the shared dial, left
as it is.

List rows are dark glass (the owner picked it 2026-10-10 over a gold glow
that lit every row; Tradeskills and Equipment have the same):
`Widgets.CreateRowList` rows alternate `glass`/`glassAlt` with a fine line
under each, and the gold wash lights only the row under the mouse. A
gradient that fades goes through `Theme.LightGradient`, which hides it at
0; faded with SetAlpha alone it stayed lit on Forever.

## The fold gem

A player asked, the owner picked the mockup (2026-10-24), in all five
addons: a small gold gem left of a window's red close gem folds the window
down to its plate and opens it back up. `UI/FoldWindow.lua` is the same
file in all five (a fix to it belongs in all five), and so are
`tools/make_fold_art.py` (draws `Media/Frame/FoldGem.tga`; rerun it, never
edit the TGA) and `tools/test_foldwindow.lua`. `FoldWindow:Add(frame,
{ onToggle, canFold })` after `Titanforged:Dress`; it sits on the trim, so
`Titanforged.lua` and `BlizzardLook.lua` are untouched. Folded, the window
keeps its place and width and is `FoldWindow.HEIGHT` tall: the rim, fill
and halo stay (`FoldWindow.Keeps`, by where each lies), the bottom corners
and everything else on it hide and stay hidden while folded, and it can
still be dragged. The gem again, closing it, or opening it by a command or
the minimap button opens it full (`Unfold`). In a fight it will not fold
over a button the game guards. With the Blizzard style it is the game's
own minimize and maximize art when the client has it. Tooltips "Collapse
this window" and "Expand this window"; nothing is saved. Here: the main window (search, Rankings, Grind and Stats; `UI/Main.lua`).

## The Blizzard window style

The owner asked (2026-10-10) for a choice of the game's own look beside
Titanforged, in all four addons. "Window style" in Settings (`windowStyle`,
`titanforged` or `blizzard`, Titanforged by default; read once at login,
so a change waits for /reload, as Text size does; a drop-down on the Windows
page). `UI/BlizzardLook.lua`
is the same file in all four (a fix to it belongs in all four): picked, it
lays the game's colours over `Theme.colors` (grey metal, the game's gold,
plain rows with a blue bar for the one picked) and puts out the halos;
`Titanforged:Dress` hands the window to `BlizzardLook.Dress` (silver rim,
a title tab where the plate sits, a silver-ringed portrait and the game's
`UIPanelCloseButton`, with the same trim fields); and the widgets call
`BlizzardLook.Button`, `.Checkbox`, `.Tab`/`.SelectTab` (hanging tabs) and
`.Thumb`/`.LightThumb` (Farmer's list scrollbars and the export box) to
wear the game's own texture files. It never touches a Blizzard frame. Each
file is checked once (`BlizzardLook.HasArt`); a client without one keeps
that widget in the house look. Farmer has no probe; Tradeskills',
Equipment's and Pets' probes list what is missing. Not yet seen in game.
New widgets should look right in both styles.

## The goal arrow, copied to Equipment and Pets

Equipment's upgrade quest and Pets' compendium have the same dial (asked
2026-10-08): Equipment's `Logic/QuestArrow.lua` and `UI/QuestArrow.lua`
and Pets' `Logic/BeastArrow.lua` and `UI/BeastArrow.lua` copy
`Logic/Arrow.lua` and `UI/Arrow.lua` here, and their
`tools/make_arrow_art.py` is this repo's, drawing the same
`Media/Arrow/*.tga`. None of them calls another for it. A fix to the dial
or its art in one belongs in all three.

The dial lies back like a compass on the ground (the owner picked it
2026-10-13 from `previews/arrow-3d/` in the project files). A tilted view
cannot be turned with SetRotation, so `tools/make_arrow_art.py` (numpy)
draws `Ring.tga` once and the blade with its shadow at 64 headings in
`Blade.tga` (8 a row, frame 0 straight ahead, then anticlockwise), its
glow in `BladeGlow.tga`; the dial shows the nearest frame with
SetTexCoord (`ArrowUI.FrameFor`), only when the frame changes. The blade
carries its own gold, so only its glow is tinted. Not yet seen in game.

TomTom (a player asked, the owner agreed 2026-10-09, then asked for it in
every addon with an arrow): with TomTom installed, each arrow hands its
place to TomTom (`Logic/TomTom.lua` in Farmer, Equipment and Pets, read
through `_G.TomTom:AddWaypoint`/`RemoveWaypoint` inside a pcall, waypoints
never persistent). "Use TomTom" (`useTomTom`, account wide, on unless
unticked; `arrow tomtom` on each addon's command) hides the dial while
TomTom shows the way, and the waypoint goes whenever the dial would hide,
so the one-arrow rule holds. The files are the same apart from names
(Farmer's reads the goal arrow's `x`/`y`, the others `mx`/`my`); a fix to
one belongs in all three.

Farmer's arrow can also follow a camp from the Grind tab (a player asked,
the owner agreed 2026-10-09; `Arrow:Grind`, `Logic/Grinding.lua`). That is
Farmer's own feature, not part of the shared dial. The harvest file now ends
with the creature types seen in game, as `if DB.CreatureTypes then ... end`
so Equipment's and Pets' readers of `Data/Data_Harvested.lua`, whose `DB`
has only `RegisterItem`, keep working.

The dial takes no clicks and shows no hover text (the owner,
2026-10-23: the clicks confused players): drag moves it, the red gem
closes it, and nothing else. Never add a click or tooltip to it again
unasked; the same in every addon with an arrow.

Only one Blackthornes arrow is on screen at a time (the owner asked
2026-10-08): Farmer's goal arrow, Equipment's quest arrow and Pets' beast
arrow agree through one global table, `_G.BlackthornesArrows`
(`wants[addon]` while that arrow has something to show, `claims[addon]` the
`GetTime()` it was last turned on or aimed). The one wanting to show with
the latest claim is drawn; the others wait hidden. The lines are the same
in each dial's file (`ArrowUI:Claim`, `ArrowUI.Wins`); a change to them
belongs in all three.

## The way there (arrows across zones and the sea)

The owner said build it (2026-10-21, from a mockup): an arrow aimed at a
place in another zone or on the other continent leads the way step by
step instead of pointing straight over mountains and sea. On unless
unticked: "Guide Me:" under GOAL ARROW on the Map & goals page
(`arrowRoute`, account wide, never rename it) and `/farm arrow route
[on|off]`. `Logic/Travel.lua` plans it: a shortest-time search over the
flight masters this character knows (read when a flight master's map
opens, `TAXIMAP_OPENED`, kept by GUID in `travelFlights[guid]`), the boats
and zeppelins of its side, its Hearthstone once the landing spot has been
seen (`travelHearth[bind]`) and walking. A walk through other zones aims at
the spot you crossed that border before (`travelCrossings["From|To"]`,
learned as you walk, averaged), else the nearest edge of the next zone,
"toward NAME"; never a made up spot. Never rename any of these. Planned
again on a new place, zone change, landing or flight learned, else every
`REPLAN` seconds; held still on a flight (`UnitOnTaxi`) and in a fight.
`Data/Travel.lua` (flight masters, flights, docks, rides) is written by
`tools/make_travel.py <tables> <build>` from the Forever client's game
tables (TaxiNodes, TaxiPath, GameObjects); never by hand, and each dock
spot is a real row (`DOCKS`). The arrow's state carries `trip`
(`Arrow:TripState`: "Step 2 of 3", the step's words); TomTom gets the next
stop (`TomTomLink.Point`). `UI/TravelCard.lua` is "Your Way There"
(`travelCardX`, `travelCardY`, `travelCardScale`), `UI/TravelMap.lua` the
gold line on the world map (dotted flights, dashed boats, solid walks,
never in a fight, its dot `Media/Frame/TravelDot.tga`).

The same files in every addon (a fix to one belongs in all):
`Logic/Travel.lua`, `Data/Travel.lua`, `Data/TravelZones.lua` (the zones'
map IDs, which border which, the capitals inside a zone and the flight
masters' short zone names, written by `tools/make_travel_zones.py <Farmer
folder>` from Farmer's zone data; never by hand) and, where an arrow takes
trips, `UI/TravelCard.lua` and `UI/TravelMap.lua`. They never name an
addon: what differs comes through `ns.TravelHost` (DB, Owner, ZoneOf,
Show, Here, InInstance, Key, Changed, Refresh, State, Print; Farmer's is at
the end of `Logic/Arrow.lua`), each left out falling back to
`Travel.Defaults`. Each copy plans for its own arrow, keeps its own save,
and signs up in `_G.BlackthornesTravel.copies`, so the flights, crossings
and Hearthstone spot one addon learned count in all (`Travel:AllFlights`,
`Travel:Kept`). An addon without a dial (Tradeskills, Butler) asks
`Travel:Guide(target)` for its Show the Way: the steps as lines and the
next stop as `{ map, x, y, name }` to pin. `/farm arrow check` has a "way there" line. Tested in
`tools/test_travel.lua`. Not yet seen in game.

## Reading the probe

The owner asked (2026-10-10) for check results without screenshots, in all
four addons. `ns.KeepCheck(name, fn)` in `Core/Init.lua` runs a check that
prints to chat, keeps every line it prints (colours and links taken out, a
secret value kept as "(secret)") and saves them in the account save as
`lastProbe = { check, at, version, lines }`, replacing the last one; chat
adds "Saved for Claude, /reload to write it." It wraps `/bts probe`
(Tradeskills, saved under `BlackthornesTSDB.global`), `/beq probe` and
`/beq arrow check` (Equipment), `/bpet probe` and `/bpet arrow check`
(Pets), and `/farm arrow check`, `/farm gathering check` and `/farm harvest
check` (Farmer, which has no probe; the harvest check readies itself and
runs on the next loot window, to see what a dungeon lets it read). None has a Settings button (the owner, 2026-10-23: checks and debug are typed only, so players never see them; `RegisterHiddenCommand` keeps them out of help, Tradeskills' short help leaves them out). Never rename `lastProbe`; a new
check that players run for a report goes through `ns.KeepCheck` too, and a
fix to it belongs in all four.

When the owner says "read the probe": he has run the check and typed
`/reload` (or logged out). In the thread, connect to his device, ask for
his game's WTF folder (already approved; the path is in the project's
memory) and stage the addon's account save from
`WTF\Account\<account>\SavedVariables\` (`Blackthornes_TS.lua`,
`Blackthornes_Farmer.lua`, `Blackthornes_Equipment.lua` or
`Blackthornes_Pets.lua`), read only. Read its `lastProbe`: `check` says
which one ran and `at` when; one older than his message means the save was
not written yet, so ask him to `/reload`. Use only the probe lines; never
commit the save or copy anything else out of it.

## Discord

The addons share a Discord server, Blackthornes AddOns (public invite
https://discord.gg/f2geDecrw2, set up 2026-10-05). After a release uploads,
`release.yml` runs `tools/announce_discord.py`, which posts the version's
CHANGELOG section to the server's #announcements through a channel webhook
kept in the `DISCORD_WEBHOOK_URL` repository secret. The owner sets that secret
himself; never ask him to paste the webhook address anywhere. Without it the
step does nothing, and a failed post never undoes the upload. The tool is the
same in all four repos; a fix to it belongs in all four.

The owner asked (2026-10-09) for one post in #general per release too,
and (2026-10-10) for it to be short: a few bullets in plain words, a
sixth-grade reading level, warm, in his voice (short, contractions, no
jargon, no file or setting names, never his name), saying what players will
notice. Each release PR writes the new version's section in `NEWS.md`
(`## X.Y.Z`, like CHANGELOG.md; it never ships) next to the CHANGELOG
section: the bullets, then one line of thanks. After the upload
`tools/post_general.py` scans it with `check_package.py`'s PRIVATE list and
posts it through the `DISCORD_GENERAL_WEBHOOK_URL` secret, which the owner
sets himself, under a line with the addon's name and version (so each
addon's bullets are their own group) and "(full list of changes in
#announcements)". It carries no CurseForge link and no card (link previews
are turned off). No section or no secret means no post.
A player's name never goes in a report (the owner, 2026-10-09): no
CHANGELOG, #announcements post, commit or PR text names a player, and
`check_release.py` refuses a CHANGELOG section that credits one
(`names_a_player` in `post_general.py`). The #general post is the one
exception: its last line thanks, by their Discord name, everyone who asked
for or reported the changes, each name once ("Thanks Ana and Bob for the
ideas and reports!"); leave it out when nobody asked. Find who asked from
the project's threads.
The thanks line no longer goes out with the webhook post (the owner,
2026-10-13: thank each player with a real @mention, so they get a
notification): `post_general.py` leaves out the paragraph that starts
"Thanks" (`without_thanks`), and the owner's bot, on his PC, posts it under
the release post with the mentions once he approves the wording, looking
the Discord names up there. Discord IDs never go in a repo. NEWS.md keeps
the thanks line, by Discord name, as before; ask the owner for any name
that isn't known.
This tool is also the same in all four repos.
Changes to the Discord bots, the digest or the release posting tools
(like this one) never go in a CHANGELOG, #announcements or #general
section (the owner, 2026-10-10): they are not changes to the addon.

The language is "Deutsch" in every post (the owner, 2026-10-11): a
CHANGELOG.md or NEWS.md section about the German translation or German
clients says "Deutsch", or "Deutsch (German)" where English readers need
the hint, never "German" alone. `tools/check_release.py` warns (it does
not refuse) when this version's CHANGELOG.md or NEWS.md section says
German without Deutsch. This rule is in every addon's notes; keep them
the same.

## The rank-up pop-up

The owner asked (2026-10-13, after a mockup in
`previews/farmer-rank-up/` in the project files) for a lift while farming:
when a kill moves a mob up the measured board's top 15, or onto it, the top
15 pops up beside the kills panel and shows the move, with a short sound,
then fades. `Logic/RankUp.lua` keeps the order as it last stood (laid out a
few mobs a frame after login, `RankUp.SLICE`; nothing saved): a kill only
marks its mob (`RankUp:Killed`, from `Tracker:Record`), a second later
(`SETTLE`) and never in a fight (it waits for `PLAYER_REGEN_ENABLED`)
`RankUp:Compare` values again only mobs whose kill count moved, through
`Rankings:Entry`, so the numbers are Rankings' own. One pop-up a look, for
the mob that moved most. `UI/RankUp.lua` draws it: dark glass stripes by
place, the rows sliding over them (`RankUpUI.Items`, `Step`), the climb or
NEW chip, the glow, a hold of `HOLD` seconds while the mouse is away, then a
fade; Window effects Subtle or Off show the new order at once. The sound is
`Media/Sounds/rank-up.ogg` (`tools/make_sounds.py`), never on the 20th kill,
whose fanfare plays instead. "Rank-up pop-up" (`rankUpPopup`) and "Rank-up
sound" (`rankUpSound`), both on unless unticked, and `rankUpScale` (its size
grip) are account wide; never rename them. `/farm rankup [on|off|sound
on|off|show]`. Tested in `tools/test_rankup.lua`. Not yet seen in game.

## Rankings outside dungeons only

The owner asked (2026-10-14) for a tick box on the Rankings tab that leaves out
mobs found only in dungeons. "Outside dungeons only" sits after the chips
(`RankingsUI.outside`), with a row on the Windows page of Settings and
`/farm rankings outside [on|off]`; off unless ticked, `rankingsOutside`,
account wide, never rename it. `Rankings:InDungeon` says by where your
kills were (the zone part of each `tracker.mobs[mob].places` key, which
inside an instance is the instance), else by the database's rows (a
Classic row's subzone naming a dungeon, or any row's zone), else outside.
A mob killed inside and out stays. `Spots.IsInstance` knows Forever's own
instances from `ns.ZONE_DATA.instances` (written by `tools/make_zones.py`;
a name that is also an open world zone, such as Deadwind Pass, is left
out) and the dungeons of `Spots.INSIDE`; capitals are no dungeon.
`Rankings:LeftOut` (hidden, or a dungeon's while ticked) is what
`Rankings:Build` and the rank-up order (`RankUp`'s `Measured`) both ask, so
the rank-up pop-up and the top farm alert follow the tick box; `RankUp.Stamp`
lays the order out again when it moves (`Rankings.outsideVersion`). Tested
in `tools/test_rankingsoutside.lua`. Not yet seen in game.

## Rankings without Uncommon and better

The owner asked (2026-10-18) for a tick box on the Rankings tab that leaves
Uncommon, Rare and Epic drops out of worth per kill. "Skip Uncommon and
better" sits after "Outside dungeons only", with "Skip Uncommon Drops:" on
the UI page of Settings and `/farm rankings uncommon [on|off]`; off unless
ticked, `rankingsSkipUncommon`, account wide, never rename it.
`Rankings:Entry` takes the drops out (`Rankings.WithoutUncommon`, quality
from the loot link's colour, else the client, `WorldDrops.QualityOf`; a
quality not known stays in), so the order, the best drop, the row's hover
and the rank-up order follow (it moves `outsideVersion`). `Value:ForMob` is
untouched, so tooltips and the loot table still count every drop. Tested in
`tools/test_rankingsuncommon.lua`. Not yet seen in game.

## Rankings at vendor prices (Classic only)

The owner said build it (2026-10-27, from a mockup): "Vendor only" on the
Rankings tab, on a second line under the chips (the top row is full),
counts every drop at what a vendor pays, never the auction house; coin
stays and a drop no vendor buys leaves (`Rankings.AtVendor`,
`VendorPriceOf`, after Skip Uncommon in `Rankings:Entry`). "Vendor Only:"
on the UI page of Settings and `/farm rankings vendor [on|off]`; off unless
ticked, `rankingsVendorOnly`, account wide, never rename it. It moves
`outsideVersion`, so the rank-up order follows; `Value:ForMob` is
untouched. The price note says "vendor prices" while ticked. Ticked from
the tab, the board comes in fresh and mobs that climbed show a green "+N"
after their name for `RankingsUI.CLIMB_SHOWS` seconds
(`RankingsUI:NoteClimbs`, `ClimbOf`). Tested in
`tools/test_rankingsvendor.lua`. Not yet seen in game.

## Your top 15 after an auction scan

The owner asked (2026-10-14): an alert after an auction scan when there is
a new top farm, based on your verified kills only, and the board shuffling
when other places change too. `Logic/TopFarm.lua` asks Tradeskills to say
when a scan finishes (`_G.BlackthornesTS.Prices:WatchScans(fn)`, in a
pcall; Tradeskills' `Prices:ScanFinished` calls it after a scan that wrote
prices); without that call it looks when the auction house closes.
`SETTLE` seconds later, never in a fight, `RankUp:Build(true, done)`
values the measured board again a few mobs a frame, keeping the old order
readable until the new one is done, and `TopFarm.Moves(old, new)` says
what moved. A different mob first, worth `LEAD` (10%) more a kill than the
old leader at the new prices and not called the top farm in `QUIET` (a
day; `topFarmTold[mob]`, account wide, never rename it), is NEW TOP FARM
with TOP on it and `Media/Sounds/top-farm.ogg` (`tools/make_sounds.py
top-farm.ogg`); any other change in the top 15 is a shuffle with the
rank-up chime. Either way `UI/RankUp.lua` draws it: every row slides from
its old place, every worth counts (`RankUpUI.counting`), climbers show
"+N". It waits, sound and all, until the auction house and the game's
own panels (`GetUIPanel`) are closed and no fight is on (`TopFarm:Busy`,
the owner 2026-10-14: the sound played behind the auction house); a scan
before then folds into the one held. Only mobs with `MIN_KILLS` kills of your own; guild data never
reaches it. "After an auction scan" on the Kill tally page (`topFarmAlert`,
on unless unticked, never rename it) with Try it, and `/farm topfarm
[on|off|test]`; the sound follows "Rank-up sound". Tested in
`tools/test_topfarm.lua`. Not yet seen in game.

## The trash can when bags are full

The owner asked (2026-10-13) for a small can on the item worth the least
when the bags are full, in Butler and Farmer both. `UI/Trash.lua`: while a
bag window is open and the bags that take anything have no free slot
(`Trash.FREE`, 0), a gold can (`Media/Trash/TrashCan.tga`, drawn
by `tools/make_trash_art.py`, the same tool and art as Butler's; rerun it,
never edit the TGA) sits on the top right of the stack worth least by
`Value:UnitPrice` times the stack. A trade good counts as
`Trash.MATERIAL_LEAN` (1.5) times its worth, so close calls go to junk;
and two short stacks of one item that fit in one slot come first: the can
says "Stack these to make room" and a click joins them (`Trash:Merge`,
the owner 2026-10-16). Never a goal's item (`Goals:Find`), a
quest item, anything soulbound above grey, gear that could be worn (only
grey gear), a locked slot or an unpriced item. A red glow lies round that
slot too, pulsing slowly (the owner, 2026-10-19; `Trash:Glow`,
`Media/Trash/PickGlow.tga` from the same tool, `Trash.GLOW_REACH`), our own
frame with no mouse, shown and hidden with the can. Farmer never deletes: a
click picks the item up and says to drop it outside the bags, where the
game's own box asks first. Its own button on UIParent anchored to the
game's item button; the bag windows are only hooked. Hidden in combat, at
a vendor, while the cursor holds something, and while Butler is loaded
(`_G.BlackthornesButler.Trash`): only Butler's can shows then, so keep
that name in Butler, or change `Trash.ButlerHasIt` here. Bags read only
while open and nearly full, `Trash.BUDGET` slots a frame. "Trash can when
full" on the Loot page (`trashCan`, on unless unticked, never rename it)
and `/farm trash`. Tested in `tools/test_trash.lua`. Not yet seen in game.

## Bags full notice

The owner asked (2026-10-15) for a notice on screen when the bags are
full. `UI/BagsFull.lua` shows "Your bags are full." near the top of the
screen once each time the bags that take anything (`Trash.Space`) go from
room to none, then fades; it comes back only after a slot frees. The bags
as they are at login are only noted; a fill in a fight waits for
`PLAYER_REGEN_ENABLED` (nothing if a slot freed); a fill at a vendor, the
bank, a mailbox, the auction house or a trade shows nothing. Its own frame
on UIParent, no mouse, no sound, independent of Butler. "Bags full
notice" on the Loot page (`bagsFullNotice`, on unless unticked, never
rename it) with Try it, and `/farm bagsfull [on|off|test]`. Tested in
`tools/test_bagsfull.lua` (also listed in `tools/testenv.lua`'s
`UI_FILES`). Not yet seen in game.

## The loot feed

A player asked (2026-10-19, the owner said build it from a mockup he
approved word for word): a small feed of what you loot, off unless ticked.
`UI/LootFeed.lua`: a dark glass row a thing (icon, name in its rarity
colour, "x3"), newest on top with a gold edge; the same thing again adds
to its count, moves to the top and holds again; rows fade after Show For
(`lootFeedHold`, 2 to 10 seconds, nil for `HOLD` 5; the owner, the same day:
3 went too fast; a 3 the first build saved is read as 5 until
`lootFeedHoldPicked` says one was picked); nothing fades while the mouse is
over it (`IsMouseOver`, the feed still takes no mouse); at most `MAX_ROWS` (6). A warm glass
foot under a gold rule says "Coin: X" and, with Show Worth on
(`lootFeedWorth`), "Loot worth: X" (`Value:WorthOf` for each row's count,
greys at vendor). It reads each loot window once through `ns.OnLootWindow`
(ahead of fast-loot addons) and shows a slot when `LOOT_SLOT_CLEARED` says
it was taken (a client without the event shows the window as read);
locked slots, hidden items and secret values never go in. Its own frame on
UIParent that never takes the mouse, except in Move, which shows a sample
row, the gold edge and the house size grip (`lootFeedScale`); its top left
is kept in `lootFeedX`/`lootFeedY` (nil for the first place). Transparent
is `lootFeedSeeThrough` (`UI/SeeThrough.lua`'s "lootfeed", Some unless
picked). All account wide; never rename them. Settings > Loot > LOOT FEED
("Loot Feed:", "Show For:", "Show Worth:", "Feed Place:" Move and Reset),
"Loot Feed:" under TRANSPARENT, and `/farm lootfeed on|off|move|reset`.
Tested in `tools/test_lootfeed.lua`. Not yet seen in game.

## Clams and sacks worth what's inside

The owner asked (2026-10-15) for what comes out of a clam, sack or lockbox
a mob drops to count toward the mob. `Logic/Containers.lua` keeps each
opening by the item's name (`containers.opened`, account wide, never rename
it); not by mob, since clams stack and give the same whoever dropped them.
`Value:Contents(name)` is one opening's average worth once `MIN_OPENS` (10; 20 until the owner picked 10, 2026-10-15)
are behind it (hidden items left out), and `Value:WorthOf(name, id)` takes
it over `UnitPrice` when it pays more, so `FromTally`, `FromDatabase`
(Rankings, the tooltip, rank-up) and the loot table's per kill follow; the
loot table's item tooltip lists what it opens to
(`LootTableUI:ContentsLines`). The session haul follows it too (the
owner, 2026-10-15: `Value:Session`, the Loot tab, a mob's loot worth and
the panel's slot tooltip use `WorthOf`); opened loot never joins
`Tracker.sessionLoot`, so nothing counts twice. Stats still prices the
clam when looted. An opening is caught by the bag click (`UseContainerItem`),
else by the loot window's `Item-` source guid matched to a bag slot
(`Containers:FromSource`, `C_Item.GetItemGUID`), since none had been
recorded in game. A disenchant opens a window that names the broken item
too, so it is told apart (2026-10-17, the owner saw greens counted as
opened): gear (`Containers.IsGear`, `WorldDrops.IsGear`) is never a
container, and a window just after the player's own Disenchant
(`Containers.IsBreakSpell`, `BREAK_SECONDS`) is the spell's
(`Containers:IsBreaking`). That window is still kept off the targeted
corpse (`Claims`) and nothing is counted. Gear counted before is left in
the save and skipped by every reader (`Containers:Entry`, `Holding`).
Tested in `tools/test_containerworth.lua` and
`tools/test_containers.lua`.

Each counted opening shows a small note near the top of the screen
(`UI/OpenNote.lua`, the owner asked 2026-10-15): "3 of 10 opened", then
what one is worth; "Clams and sacks" on the Loot page (`openNote`, on
unless unticked, never rename it) and `/farm opennote`. Tested in
`tools/test_opennote.lua`.

## The Open button

The owner asked (2026-10-15) for one click to open clams, sacks and
lockboxes, in Farmer. `UI/OpenButton.lua`: a secure icon button
(`BlackthornesFarmerOpen`, the next item's icon, how many in its corner,
"Open" on hover) on the Kills & Loot panel's title bar, left of its X.
Each click aims a `/use bag slot` macro at the next slot with `hasLoot`,
read again first, and empties it after. Left shut: a goal's item (Farmer's
own `Butler:Advise`), what Tradeskills' queue needs (its `Butler:Advise`
`need` or `mailCount`), what Butler keeps (`_G.BlackthornesButler.Verdicts:Choice`
keep, bank or mail, `Quests:Reason`), quest items and a lockbox whose
tooltip says `LOCKED`; each sister read in a pcall, none required. In a
fight it hides and goes back to UIParent, so the panel can still move;
hidden at a vendor, bank, mailbox, auction house or trade. "Open after
loot" (`autoOpen`, off unless ticked) opens the next one each
`LOOT_CLOSED`, out of combat, with a free slot, until the game refuses
the call (no Test button since the owner, 2026-10-23: the first opening
is the check, `OpenButton:Learned`, kept in `openTest` with `quiet`;
`/farm openbutton test` still runs it by hand); one the game refuses (its "internal loot error", with no loot window) is tried again, and left for the session only after `OpenButton.STRIKES` (3) tries in a row stay shut (`OpenButton.tried`, counted; a click on the button or one that opens starts it again). It waits for the bags to take the last loot (`BAG_UPDATE_DELAYED`, at most `BAG_WAIT`) before the next, since using one sooner gives the game's internal bag error, and with the game's Auto Loot on it loots a window it opened itself (`TakeLoot`, `LootSlot` a frame after Farmer reads it), which the game does not when an addon opens it. A try is judged only once the bags show it (`Settle` in `BagsTook`), and when the next clam's slot is still locked from the last opening it looks again (`RETRIES`, `lockedLoot`) rather than stop.
`openButton` (on unless
unticked), `autoOpen` and `openTest` are account wide; never rename them.
Loot page; `/farm openbutton [on|off|test|auto on|off]`. Tested in
`tools/test_openbutton.lua`. Not yet seen in game.

## The see-through panel

The owner said build it (2026-10-16, from a mockup in
`previews/kills-loot-transparent/` in the project files): the Kills & Loot
panel's dark glass thins out so the world shows through, every word gets
a black shadow (`TrackerUI.ShadeAll`) so it reads over a busy scene, and
the glass comes back while the mouse is on the panel (a watcher looks
every `SEE_THROUGH_LOOK` seconds, only while ticked and shown). Only the
panel's own fills are faded (`TrackerUI:AddGlass`, texture SetAlpha,
which the colours each redraw sets are multiplied by); the open card's
gold keeps at least `LIVE_GLASS_FLOOR`; gold edges, icons, bars and glows
stay; the cut-edge fades are left out while it is on. Saved as
`trackerSeeThrough` (off unless ticked) and `trackerSeeThroughLevel`
(Some, More, Most: `SEE_THROUGH_LEVELS`, 2 by default), account wide,
never rename either; `/farm tracker transparent [on|off|some|more|most]`. Tested in
`tools/test_seethrough.lua`. Not yet seen in game.

The other panels that stay on screen have it too (the owner asked the same
day, "a button for each unique window"): the goals panel, Where to farm,
the rank-up board, the run recap and the XP bar (the whole bar since
2026-10-17, the well alone hardly showed: its gold keeps at least
`XPBarUI.GOLD_FLOOR` and its rim `RIM_FLOOR`). `UI/SeeThrough.lua`
does it the same way for each (`SeeThrough:AddGlass(id, texture, floor)`,
`:Grew(id, row)` for rows made later, `:Attach(id, frame)`, `:Set`), and a
word's own shadow comes back when it is turned off. One stepper each, Off,
Some, More or Most, saved 0 to 3, off by default, account wide, never
rename them: `goalsSeeThrough`, `goalSpotsSeeThrough`, `rankUpSeeThrough`,
`recapSeeThrough` and `xpBarSeeThrough`; `/farm transparent
goals|places|rankup|recap|xpbar [off|some|more|most]`. The main window
and the loot table are left out, since the mouse is on them while they are
used. The Kills & Loot panel keeps its own code above. Tested in
`tools/test_seethroughpanels.lua`. Not yet seen in game.

All six sit in one TRANSPARENT section on the UI page of Settings (the
owner, 2026-10-17), a row a panel named for it ("Kills & Loot:",
"Goals:", "Where to Farm:", "Top 15:", "Run Recap:", "XP Bar:"), each a
stepper Off, Some, More or Most; Kills & Loot's sets both its keys, and
Off keeps its level. Players read "Transparent" (the owner, 2026-10-16):
the commands are `/farm transparent ...` and `/farm tracker transparent ...`.
`seethrough` still works as the old word and is left out of the help
list; the code, the module and the saved keys keep their see-through
names. Never announce the wording change.

## Kill heat map (a test feature)

The owner asked (2026-10-17, from a mockup in `previews/mob-heatmap/` in the
project files) for a heat map of where you kill, on the world map and the
minimap, and said he may or may not keep it. `Logic/Heat.lua` keeps
`killHeat[mapID][mob][cell] = count` on a 100 by 100 grid (a mob keeps at
most `MAX_CELLS` cells, a map `MAX_MOBS` mobs), only while a switch is on,
from `Tracker:Record`'s new kill (`Harvest:PlayerMapPosition`; a spot the
client will not give adds nothing). Older kills have no spot. Own kills
only; guild and shipped data never reach it. `UI/Heat.lua` draws soft dots
(`Media/Frame/HeatDot.tga`, `tools/make_heat_art.py`) blue to red, a slice
a frame, redone only when the cells, map, mob or strength change. The world
map is never drawn in combat and sits over the map's art and under the
gathered-node markers (`HeatUI.WORLD_ABOVE` 2 levels over the canvas,
`MapMarkers.WORLD_ABOVE` 3, Grind pins 4; at the canvas's own level it was
drawn under the art and never showed, 2026-10-18). On a zone map the
parts you have explored are pins over the art, so all three count up from
`MapMarkers.BaseLevel` (those pins' level, else the level the map keeps
for them, else the canvas; the glow showed on Kalimdor, not Ashenvale,
2026-10-18); the minimap is fainter
(`MINIMAP_ABOVE`, 1 for the glow, 2 for the markers). Hidden mobs are left out. Saved, never renamed:
`killHeat`, `heatWorld`, `heatMinimap` (both off unless ticked), `heatLevel`
(Some, More, Most) and `heatMob`. KILL HEAT on the Map & goals page and
`/farm heat [on|off|map|minimap|strength|mob <name>|all|clear confirm]`;
`clear confirm` is typed only. A kill is kept under the map the game
names where you stood, which can be a smaller map, the continent or a
map beside the one shown (it glowed on Kalimdor, not Ashenvale,
2026-10-18), so `Heat:Cells` reads every map kept, moved over by where
both maps' corners lie in the world (`C_Map.GetWorldPosFromMapPos`, one
continent only), else `C_Map.GetMapRectOnMap` (`Heat.MapRect`,
`Heat.Carry`; the minimap reads the same; `BestMap` still counts each
map's own kills). `/farm heat check`
(`ns.KeepCheck`, typed only) prints where you stand, the map shown, each
map kills are kept on and the world layer. Tested in `tools/test_heat.lua`.
Not yet seen in game.

Show on Map (the owner, 2026-10-18, from a mockup; he approved the words):
while the heat map is on the world map, search rows get a **Map** button,
mob rows in a slot of their own (`UI.MapsMob`, the `map` column, no room
taken otherwise) and the item heading left of Goal (`UI.MapTarget`). It
aims the glow at that mob (`heatMob`) or item (`Heat:SetItem`, kept for the
session only: the mobs your own `Harvest.records` say drop it, each
weighted by its rate, `Heat:ItemMobs`) and opens the world map where it is
brightest (`Heat:BestMap`, `OpenWorldMap`, never in a fight). The same row
again, or **Stop Tracking** on the map's card (`HeatUI:UpdateCard`, our own
frame on the map in the house frame, the owner's pick of 2026-10-18: a
Kill Heat plate, the item's icon and its name in rarity colour under
SHOWING, an item's mobs in dark glass rows with "N% a kill" on the right,
the colour key and a solid gold button; `HeatUI.CardText` gives `{ name,
item, id, rows }`), stops tracking. Dim with "Kill a few first and it will
show here." until a spot is kept (`Heat:HasSpots`, `ItemHasSpots`), and
the card says the same (`HeatUI.HasGlow`): kills from before the heat map
was on have no spot. The card can be dragged and stays where it was left,
inside the map, plate and corners too (`heatCardX`, `heatCardY`, never
rename them; `HeatUI:PlaceCard`, `KeepCardPlace`). The loot table has the same **Map**
button at the top right, beside its numbers, for its mob by name
(`LootTableUI:MapName`, `DressMap`; the owner asked 2026-10-18), shown only
while the heat map is on the world map.
The maps glow only while a mob or item is tracked (the owner, 2026-10-18;
`HeatUI.Tracking`): with nothing picked, neither map draws. The glow's
outer edge has a gold line over a dark one (the owner asked the same day,
so where you have killed reads at a glance): `HeatUI.Outline` grows the
cells by one all round and traces their edge by marching squares, laid on
the world map a slice a frame after the dots and on the minimap through
`MinimapOffset` (`MAX_WORLD_EDGES`, `MAX_MINIMAP_EDGES`).

## Kills on the mob tooltip

The owner asked (2026-10-13) for a mob's tooltip to say how many you have
killed. `UI/KillTooltip.lua` adds one line, through the same hooks as the
material line (`TooltipDataProcessor` for units, `OnTooltipSetUnit` too):
below `Tracker.MIN_KILLS` "Kills: 7/20" in red, from 0/20 on a mob never
killed; from 20 "Kills: 134, worth 1s 20c each" from `Value:ForMob` (the
count alone when nothing it drops has a price). It reads
`tracker.mobs[name].kills` only, never `Tracker:GetMob`, so a hover makes no
tally. A mob you cannot attack, players, pets and critters get nothing until
killed; a hidden mob gets nothing. Inside a dungeon the name falls back to
the guid's mob ID (`Harvest.KnownNpcName`, else "Creature #ID"), as the
harvest keys it. "Kill count" under Tooltips on the Map & goals page
(`killTooltip`, on unless unticked, never rename it) and `/farm killcount`.
Under it, "Best drops" (the owner asked 2026-10-14): the three drops that
add most to a kill, chance times price, straight from `Value:ForMob`'s
sorted `priced` list (each entry carries `chance`), kept with the worth in
`KillTooltip:Read`, so a hover adds no work; only from the player's own
rates, never the database's (below). A drop under half a copper a kill is left out. "Best drops" on the
Map & goals page (`killTooltipDrops`, on unless unticked, never rename it)
and `/farm killcount drops [on|off]`.
Tested in `tools/test_killtooltip.lua`. Not yet seen in game.

## Off, Shift or Always on tooltip lines

The owner said yes (2026-10-18): each tooltip line Farmer adds can be Off,
Shift (only while Shift is held) or Always. The four TOOLTIPS rows on the
Map & goals page are steppers (`TooltipShiftStepper` in `UI/Settings.lua`):
"Where to Farm:" (`whereToFarm`, `itemTooltip`), "Craft or Sell:"
(`craftOrSell`, `itemTooltipCraft`), "Kill Count:" (`killCount`,
`killTooltip`; its marks and the greens line go with it) and "Best Drops:"
(`bestDrops`, `killTooltipDrops`). Whether a line is on stays in its own
key, so nobody's settings moved: on reads as Always, off as Off. Shift is
kept account wide in `tooltipShift[key] = true` (never rename it; only a
true is ever written). `UI/TooltipShift.lua` is the same file in all five
addons (a fix to it belongs in all five): `Shows(key)` is asked each time
the tooltip is built, after the kept lines (`ItemTooltip`'s and
`KillTooltip`'s caches never hold the Shift answer), `Held(tooltip)` adds
"Hold Shift for more." once per tooltip across the addons, and one shared
frame redraws GameTooltip when Shift goes down or up, only while a line is
on Shift. The slash commands still turn lines on and off as before. Tested
in `tools/test_tooltipshift.lua`. Not yet seen in game.

## Rates are the player's to find

The owner (2026-10-15): learning what a mob drops is most of the fun, so
before a mob has `Tracker.MIN_KILLS` of the player's own kills, no drop
rate for it shows on its tooltip ("Best drops") or its loot table: not the
shipped data's, the guild's or Classic's. Always on, no setting, never
announced (no CHANGELOG, NEWS or What's New line). The player's own
records are never touched; at 20 kills their own rates show. The search
(where an item drops), Rankings' estimates, worth per kill "(est.)" and
the other addons still read the shipped data. Tested in
`tools/test_killtooltip.lua` and `tools/test_guildshare.lua`.

## World drops

The owner asked (2026-10-13) how often green, blue, purple and orange gear
drops and whether it changes with the mob's level, then for it in four
places. `Logic/WorldDrops.lua` counts it from the harvest only: gear is the
client's item class 2 or 4 (`IsGear`, `GetItemInfoInstant`), quality the
loot link's colour in `tracker.looks` else the client's, mobs grouped five
levels a band (`Band`), a record in a dungeon, raid or city left out
(`Inside`, `Spots.INSIDE`). A band says nothing under `MIN_KILLS` (200).
The import writes the counts after the creature types
(`if DB.WorldDrops then DB:WorldDrops(...) end`, `ExportBlock`;
`tools/harvest_import.py` passes the save's `tracker` for the colours), and
a band uses whichever has more kills, the player's own or those, never the
two added. Sums are kept per record until its corpses move and per band
until `Harvest.changes` moves (each corpse) or `KEEP_FOR` passes.

It shows as "World drops, level N" and "You've had here" under the open
mob in the kills panel (`WorldDrops:CardLines`), a WORLD DROPS chip and
rows on Rankings (`RankingsUI:WorldRows`; under ALL only once there are
kills; the chip's own view, `WorldViewRows`, has four quality tiles, a
band a row with kills, greens, a bar, a percent and 1 in, BEST and YOUR
LEVEL tags and its own sorting, `rankingsWorldSort`, never rename it), "Greens: 1 in N kills" on the mob tooltip (`KillTooltip:GreensLine`)
and a search for "greens" or "world drops" (`WorldDrops.IsQuery`,
`SearchItem`: a result with no Goal button or hide choice). "World drops"
on the Loot page (`worldDrops`, account wide, on unless unticked, never
rename it) and `/farm worlddrops [on|off]`. Tested in
`tools/test_worlddrops.lua`.

## Sparkles on the node you face

The owner asked (2026-10-13) for gatherable nodes to sparkle in the world.
The client tells addons nothing about the nodes around you, so only the one
the interact key would pick ("softinteract", in front of you and close)
can sparkle. `UI/NodeSparkle.lua` anchors gold sparkles (its own frame,
never parented, the star `Media/Frame/Sparkle.tga` from
`tools/make_sparkle_art.py` over a soft glow, twinkling by an animation
group) to the game's nameplate for that object
(`C_NamePlate.GetNamePlateForUnit("softinteract")`). The nameplate only
exists with `SoftTargetInteract` at 3 and `SoftTargetNameplateInteract` on,
and `SoftTargetInteractRange` 15 (30 at first, then 100; about 15 is all Forever allows, the owner saw in game, so a save left at 100 is brought down) and `SoftTargetInteractArc` 2 (all round)
let it pick a node farther off (2026-10-13). The probe found no nameplate
for a node with those alone (Peacebloom, 2026-10-13), so the game's own
icon over the object is turned on too (`SoftTargetIconGameObject`,
`SoftTargetIconInteract`; the owner picked it), and the sparkles gather
round that icon (`NodeSparkle.Icon`, the plate's `UnitFrame.SoftTargetFrame`,
read only) when the plate lets us read it. So while "Sparkle on nodes" (`nodeSparkle`, on unless unticked, Map & goals
page, `/farm sparkle`) is ticked Farmer raises them out of combat, keeping
the old values in `nodeSparkleCVars` (never rename either) and putting them
back when unticked. A node is a herb or vein the data knows, the client's
herb name, or a node the player gathered; a hidden source gets nothing.
`/farm sparkle check` (`ns.KeepCheck`) reports what the client gives.
Seen in game 2026-10-13 round the icon. Since then (the owner asked the
same day): the sparkles sit `NodeSparkle.DROP` below the icon, on the
node, scaled by the plate's size (`NodeSparkle:Drop`); fishing schools
(`Fishing.IsSchool`), chests (`CHEST_PATTERNS`), the player's bobber
(`BOBBERS`; a cast lands past the 15 yards the interact target reaches, so while the Fishing channel runs `NodeSparkle:RaiseReach` sets `SoftTargetInteractRange` to `FISHING_RANGE` and `LowerReach` puts it back when it ends, keeping the old value in `nodeSparkleFishingRange`, never rename it, put back at login if the game closed mid-cast) and objects an unfinished quest objective names
(`NodeSparkle:QuestText`, read again after `QUEST_LOG_UPDATE`, or
`C_QuestLog.UnitIsRelatedToActiveQuest`; a pickup named apart from its
objective, such as Raw Windstone for Windstone Cluster, by an objective
on its tooltip, `NodeSparkle:QuestInTooltip`, or by what it gave when
looted before, `QuestByLoot`) count too (`NodeSparkle:Kind`);
and the look can be a beacon instead, a beam of light rising off the spot
(`Media/Frame/Beacon.tga`, same tool; "Sparkle look" in Settings,
`nodeSparkleStyle` "sparkles" or "beacon", the beacon by default (the owner,
the same day), account wide, never rename it, nor `nodeSparkleStylePicked`,
which turns the first default's "sparkles" into the beacon until picked;
`/farm sparkle beacon|sparkles`). The row is "Sparkles in the world".
Without a controller (`C_GamePad.IsEnabled`, else `GamePadEnable`) the
game's icon is kept out of sight (the owner, the same day), only while
Farmer is the one that turned its CVars on: `NodeSparkle:VeilIcon` sets its
alpha to 0 from Farmer's own table (never Hide), never in a fight, and puts
it back when a controller comes on or the box is unticked. "Game's
interact icon" (`nodeSparkleHideIcon`, on unless unticked, never rename
it) and `/farm sparkle icon [show|hide]`.
The plates are Farmer's doing too: with them on, the game draws a name,
bars and a level over every NPC and object the interact key picks (the
owner saw them on a vendor, 2026-10-13). While Farmer turned those CVars on
(`NodeSparkle:OwnsPlates`), the plate's pieces other than the icon
(`NodeSparkle.PlatePieces`) are see-through the same way, whatever the icon
setting, unless the player would see that plate anyway (a creature they
could attack, or friendly nameplates on: `PlateShownAnyway`). A creature's
plate keeps its name (`NodeSparkle.IsPlateName`): the game takes the name
off a creature's head while it has a plate, so veiling it left NPCs
nameless up close (2026-10-14). That name is white and cut short, though,
so while the interact key picks a creature `NodeSparkle:FitPlateToTarget`
puts `SoftTargetNameplateInteract` back to the player's own value (kept in
`nodeSparkleCVars`), and an object or nothing turns it on again; never in a
fight. Looked at
again `VEIL_AGAIN` after each event, since the game sets a plate up after
telling us.
Colours (the owner said build it, 2026-10-24, from a mockup): herbs and
ore take the player's skill colour against the node's least `requires`
in the data (`NodeSparkle:NodeNeeds`, `SkillColor`: orange under
`ORANGE_TO` (25) over, yellow under `YELLOW_TO` (50), then green, never
grey; grey when the skill is short or missing, and it still sparkles),
quest objects blue, chests, schools and the bobber white, gold when no
skill is read or "Sparkle Colors:" is unticked (`nodeSparkleColors`, on
unless unticked, never rename it; `/farm sparkle colors [on|off]`). The
beacon and the sparkles are tinted the same (`NodeSparkle:Tint`). "Skinnable
Corpses:" (`nodeSparkleCorpses`, off unless ticked, never rename it;
`/farm sparkle corpses [on|off]`) sparkles a dead creature the interact
key picks while the player knows Skinning, whose tooltip says it can be
skinned (`UNIT_SKINNABLE_LEATHER`) or whose kind the player has skinned
before (`skinLog`), until `GrindGather.skinned` has it
(`NodeSparkle:SkinnableCorpse`, `Skinned`), in the Skinning colour for
its level (`Grinding.SkinSkill`); its plate stays on
(`FitPlateToTarget`). Both rows sit under Sparkles on the Map & goals
page. Not yet seen in game.
Tested in `tools/test_nodesparkle.lua`.

## Gathered spots on the maps

The world map marker where you gathered shows the item you got there (the
owner said build it, 2026-10-24, from a mockup; Forever's `3e278ad` with
Retail's spot counts and joining, see `docs/CLASSIC_DIFFERENCES.md`). Each
spot counts what it gave, `spot.items[name] = count` (`Gathering.NoteItems`,
never rename it), and the marker shows the item given most
(`MapMarkers.SpotItems`, `SpotItem`, `IconFor`); a spot saved before then
reads its node's own gathering or fishing records, else the data, else the
plain herb, ore or fish icon. The hover lists up to `TOOLTIP_ITEMS` of them,
icon and "Silverleaf x9", above the old lines. The icon stays grey until
`Respawn:BackAt` says the node should be back, then shows in full colour at
full strength; a once a second look (`MapMarkers:WakeWorld`) recolours pins
already placed and places nothing again. A cast into a school you moused
over is marked too (`kind = "fish"`, from `Fishing:OnLoot`; open water
marks nothing), in full colour in a `pool` blue ring, "Fished" or "Fished
%d times" on the hover, never a grow-back time. Era grows a different herb
or vein on one spawn point, so a herb or vein within `Gathering.NEAR_YARDS`
(3.3) of a spot of its own kind joins it (`Gathering.Joins`; its name kept
in `spot.also`, never rename it, which `Respawn:Gathered` reads; only the
same node teaches a grow-back time); fishing never joins. Older spots that
close draw as one on the world map (`Gathering.Joined`), the save
unchanged. The minimap keeps its hollow corners. Tested in
`tools/test_markers.lua` and `tools/test_mapicons.lua`. Not yet seen in
game.

## Quest count over quest mobs

The owner picked it (2026-10-13, from a mockup of three light touches):
"3/8" in gold just right of the name over a mob an unfinished quest
objective still needs. `UI/QuestMobs.lua` reads the count from the mob's
tooltip lines (`C_TooltipInfo.GetUnit`), else from a quest log objective
that names it, when a nameplate appears and again for every plate 0.3 s
after quest log events. Its own frames on UIParent, anchored to the
plate's name, never parented; only where the game lets addons read the
plate (not in dungeons). "Quest count" on the Map & goals page
(`questMobCount`, on unless unticked, never rename it) and `/farm
questcount`. Tested in `tools/test_questmobs.lua`. Not yet seen in game.

## Kill count beside mobs' nameplates

A player asked, the owner said build it (2026-10-15): the tooltip's kill
count to the left of a mob's nameplate. `UI/KillPlates.lua` shows "7/20"
in bright gold, outlined and a size up (Classic, 2026-10-25), under `Tracker.MIN_KILLS`, then the whole count, and with "Worth
on nameplates" ticked what a kill is worth after it, only from your own
kills (`KillTooltip:Read`'s kept answer, never an estimate). The same
mobs as the tooltip (`KillTooltip:Attackable`, `MobName`, hidden ones
left out). Its own frames on UIParent anchored to the left of the plate's
name, never parented, as `UI/QuestMobs.lua` does on the right; only where
the game lets addons read the plate. A plate is read when it appears and
again when a mob of that name is killed (`KillPlates:Killed`, from
`Tracker:Record`), a setting changes or the hide list moves. "Kill count
on nameplates" (`killPlates`, on unless unticked) and "Worth on
nameplates" (`killPlatesWorth`, off unless ticked) on the Map & goals
page, account wide, never rename either; `/farm plates [on|off|worth
on|off]`. "Counter Position:" under it (a player asked, the owner said
yes 2026-10-18: it covered another nameplate addon's text) picks Above
(over the name), Below (under the cast bar, else the health bar), Left
or Right (past the quest count when one shows, `QuestMobs:LabelFor`):
`killPlatesSide`, "left" unless picked, account wide, never rename it.
Tested in `tools/test_killplates.lua`.
The crown the kills panel puts after a mob's name (`TrackerUI.MarkFor`,
through `KillTooltip.Crown`) follows the count on its plate and on the
tooltip's kill line too (the owner asked 2026-10-15); no setting of its
own, and like the other kill marks it is never announced.

## Damage numbers (taken out)

The owner had big damage numbers built (2026-10-19) and took them out
again (2026-10-20: "just take damage numbers out of farmer"); never add
them back unasked. While ticked they had set the game's own numbers to 0,
so `Logic/GameNumbers.lua` puts back any value kept in
`damageNumbersCVars` at login, never in a fight. `damageNumbers`,
`damageNumbersSize`, `damageNumbersCombo` and `damageNumbersCVars` stay
in the save, unread; never rename them. Tested in
`tools/test_gamenumbers.lua`.

## The XP bar

The owner asked (2026-10-13) for an XP bar in the house style that does
more than show a number, picked the mockup (`previews/xp-bar/` in the
project files) with its small rewards, and said leveling goes to 60 at
release. `Logic/XP.lua` works it out; `UI/XPBar.lua` draws it.

- The cap is the client's (`GetMaxLevelForPlayerExpansion`, then
  `GetMaxPlayerLevel`, then `MAX_PLAYER_LEVEL`), else `XP.CAP` (60). Never
  hard-code Forever's beta cap of 30. The bar hides at the cap and while XP
  is turned off (`XP.Earning`). Levels past the one you are on are
  Classic's (`XP.TABLE`) scaled by this client's number for your level.
- What it reads: XP from `PLAYER_XP_UPDATE` (gains counted across a
  level-up), a kill's XP from the game's own chat format
  (`COMBATLOG_XPGAIN_FIRSTPERSON` through `XP.Pattern`, so a German line
  in another order reads too), quest XP from `QUEST_TURNED_IN`, and the
  quest log (`C_QuestLog`, `GetQuestLogRewardXP`) only after it moved
  (`XP.SETTLE`). Mob XP is kept for the session only.
- Saved per character by GUID in `xpProgress[guid]` (never rename it):
  played time and time on this level as last read, how long each level
  took (`levels[n]`), past sessions' XP and time (`paceXP`,
  `paceSeconds`, for "your usual pace") and the session at logout, picked
  up again within `XP.RESUME` (a /reload). The game is asked for played
  time (`RequestTimePlayed`, which prints in chat) only when nothing is
  kept for this level.
- The bar: played and level time, finished quests' XP and rested above;
  level, XP and percent on it, with this session, the quests and rested as
  their own bands; time to level and XP an hour below (gold "(up N%)" when
  `XP.AHEAD` faster than usual); a kill streak of 3 or more. The hover card
  says how to finish the level (hand in, kills of the last mob, quests
  under way, rested, the cap at your usual pace).
- Small rewards (Window effects Full only for motion): XP floats off the
  tip, a light runs along it for a quest, each tenth chimes
  (`Media/Sounds/xp-tick.ogg`, `tools/make_sounds.py`), a green glow while
  finished quests would level you, and the level-up cheer (`Cheer`: the
  time it took, fastest since, coins on every tenth level and the cap). The
  cheer looks through the bags a few slots a frame for gear Equipment
  calls an upgrade, inside a pcall, read only:
  `_G.BlackthornesEquipment.Compare:IsUpgrade(link)`.
- The game's XP bar is never hidden: "Game's XP bar" makes it see-through
  through `ns.Veil` (`UI/Veil.lua`, Equipment's file; a fix to it belongs
  in both) and puts it back; a fight makes it wait.
- Settings, Kill tally page, XP BAR: "XP bar" (`xpBar`, off unless ticked
  since 2026-10-15; the cheer waits for it too), "Level-up cheer"
  (`xpBarCheer`) with Try it, "Chime every tenth" (`xpBarChime`), on
  unless unticked; "Game's XP bar" (`xpBarHideGame`, off unless ticked);
  "Put it back". Place and size: `xpBarPoint`, `xpBarRelPoint`, `xpBarX`,
  `xpBarY`, `xpBarScale`. All account wide; never rename them. `/farm
  xpbar [on|off|cheer on|off|chime on|off|game show|hide|reset|try]`.
- Class spells to train: Farmer has no spell list, so the cheer asks
  Butler, else Equipment, `TRAIN_DELAY` seconds after the level, inside a
  pcall and read only: `_G.BlackthornesButler.ClassTraining:IsOn()` and
  `:Plan()` (`ready`, `cost`, `unknown`; their `Logic/ClassTraining.lua`,
  the same file in both, which learns prices the first time a class
  trainer is opened). "New spells at your trainer", with the cost only
  when every spell is priced. Neither loaded, or nothing to train, no row.
  If `Plan` changes there, change `XPBarUI.Training` here.

Tested in `tools/test_xpbar.lua`. Not yet seen in game.

## The Stats tab

The owner asked (2026-10-13) for a tab that is only charts, and picked the
mockup (`previews/farmer-data-tab/` in the project files). `Logic/Stats.lua`
keeps the log as you play, account wide in `farmStats` (never rename it):
`days["YYYY-MM-DD"]` (copper by source: `drops`, `coin`, `gather`, `fish`,
`grey`; kills, farming seconds, kills by mob), `sessions` (one a login,
kept from the first loot) and `pace[mob]` (seconds a kill). Loot is priced
when looted (`Value:UnitPrice`, greys at vendor); an unpriced item waits in
`Stats.pending` and `Stats:Settle` prices it later. Only farming time
counts: a gap over `Stats.BREAK` is a break. Hidden items stay out, and
guild data never reaches it (it is fed only by `Tracker:Record`,
`AddHaul`, Fishing and Gathering). Days past `KEEP_DAYS` and sessions past
`KEEP_SESSIONS` are let go. `UI/Stats.lua` draws the tab (the window grows
to `StatsUI.WIDTH` by `StatsUI.HEIGHT` on it only): four numbers on top,
then gold an hour by session against your usual pace, where the gold came
from, best mobs at your kill speed (a click opens the loot table), luck
since login, ten weeks of days and how long each level took (the XP bar's
`xpProgress`). Drawn only while the tab shows, again `REDRAW` seconds after
something moved (`Stats.version`). A best gold an hour yet is cheered once
("Best session cheer", `statsBestCheer`, on unless unticked, never rename
it). A switch beside Settings picks This session or Overall (the owner
asked the same day; `statsView`, account wide, "session" by default, never
rename it; `/farm charts session|overall`): This session draws this
login's numbers, how its gold grew (`Stats:Curve`, kept in memory),
its sources (each session's `sources`), the mobs killed in it and its
luck; Overall every session, every day kept, and the whole kill tally
(kills, luck by `Stats:Luck("overall")`, kept `LUCK_KEEP` seconds). Days
and levels are the same in both and say so. `/farm charts [cheer on|off]`.
Tested in `tools/test_stats.lua`.

## Loot inside dungeons

Inside a dungeon the client hides the corpse's name and guid from addons,
so until 2026-10-11 nothing looted there was recorded. The loot window
still names its source by guid (`GetLootSourceInfo`, readable in Ragefire
Chasm), and that guid carries the mob's ID, so `Harvest:Corpse` falls back
to the first creature the window names (`Harvest.NpcID`). Its name comes
from the game's unit link (`Harvest.NameFromLink`), kept account wide in
`npcNames[id]` (never rename it). Inside a dungeon the game gives none
(Ragefire Chasm, 2026-10-11), so Classic's name from `Data/NpcNames.lua`
stands in (`ns.NPC_NAMES`, generated by `tools/make_npc_names.py` from
pfQuest; never edit it by hand). A mob neither knows (one Forever added)
is kept as "Creature #ID" with `record.npc`, never exported
(`Harvest.Unnamed`), and renamed on load once a name is known
(`Harvest:NameUnnamed`, harvest and kill tally both). A partner's or an
import's "Creature #ID" record goes under the name this side knows
(`Share.Canonical`, not for the guild), and a partner with a ledger under
both keys keeps the larger while what was taken twice comes off
(`Share.Combine`, `Share.Subtract`; `tools/test_unnamedshare.lua`). This works the same in every dungeon and raid.
Names for mobs Forever added (a player's Ruins of Lordaeron kills showed
as numbers, 2026-10-14): whenever the client lets a creature's name and
guid both be read (target and mouse, also off their tooltip, nameplates,
the soft targets, any unit tooltip), `Harvest:KeepName` keeps it in
`npcNames`, only for an ID neither Classic's list nor an earlier answer
names, so no record already named changes key (`Harvest:LearnName`,
`NoteUnit`, `KillTooltip:Learn`). The kills panel shows the name at once
(`Harvest.ShowName`, for showing only) and `NameUnnamed` moves the kept
data at the next login. If the game hides every name in that dungeon too,
it stays a number until the mob is met where it does not; `/farm harvest
check` now says whether the tooltip gives a name and how many names were
learned. Tested in `tools/test_learnnames.lua`.
Inside Ruins of Lordaeron the probe (2026-10-14) found every name, guid
and tooltip line hidden, alive or dead, and the client's tables have no
names for Forever's new mobs, so there a player names them by hand: the
kills panel's right-click on a "Creature #ID" mob offers "Name this mob"
(`UI/NamePrompt.lua`, `namePromptScale`, never rename it), and
`Harvest:NameByHand` keeps the name in `npcNames` (only for an ID nothing
names; `Harvest.CleanName` refuses numbers and junk). Names everyone gets
are `Data/ForeverNpcNames.lua` (`ns.FOREVER_NPC_NAMES`, read by
`KnownNpcName` after `npcNames`, before Classic's), written by
`tools/forever_npc_names.py <Farmer save> [creaturecache.wdb]` from the
owner's `npcNames` and the game's English creature cache on his PC
(`Cache\WDB\enUS\creaturecache.wdb` beside `WTF`, read only, only IDs and
names; it holds every creature name the game has shown, Ruins mobs too,
2026-10-14), at each release with the other fold-ins, never by hand and
never announced. Never commit the cache or name it in public. `/farm
harvest check` also says whether the kill line in chat names the mob
(`Harvest:NoteKillLine`). Tested in `tools/test_namemob.lua` and
`tools/test_forever_npc_names.py`.
`/farm harvest check` reports what a dungeon lets the addon read.

## What's New

The owner asked (2026-10-12) for the Discord #general post to show in game,
the first time it loads after an update, in one window for every addon.
`UI/WhatsNew.lua` is the same file in all five (a fix to it belongs in all
five), and so are `tools/test_whatsnew.lua`, `tools/make_whatsnew.py` and
`tools/test_make_whatsnew.py`. There is no shared core addon: every copy
signs up in `_G.BlackthornesWhatsNew` as it loads, the first to reach
PLAYER_LOGIN starts the only timer (`WhatsNew.DELAY`, 5 s, never in a
fight), and that one check gathers what is new in all of them. The copy
with the highest `FILE_VERSION` draws the window (first in
`WhatsNew.ADDONS` on a tie); raise it when a change needs the newer copy.

The words are NEWS.md's: it never ships, so `tools/make_whatsnew.py` writes
its newest three sections, bullets only (the thanks line names players and
never ships), into `Core/WhatsNewText.lua` (`ns.WHATS_NEW`; never edit it by
hand). The window shows new features only (the owner,
2026-10-13): a section's
fixes and other changes go under a "Fixes and changes:" line, which go to
Discord but not the window, and every line is plain words with no hype,
no questions to the reader, no exclamation marks and no dashes as
punctuation (the tool notes one that trips `STYLE`). **Every release PR that writes a NEWS.md section runs
`python tools/make_whatsnew.py` too**; `check_release.py` refuses a tag
while the file is behind, and `tools/test_make_whatsnew.py` fails on every
push. The bullets stay in English, also on a German client.

Shown once a version: each addon keeps the newest version shown in its own
account save (`whatsNewSeen`); after an update the sections newer than that
(at most three) show, and an addon that never kept one shows its newest.
"After an update" (`whatsNewPopup`) and "What's New motion"
(`whatsNewMotion`) are on unless unticked, off in all when off in any;
`whatsNewScale` is the size grip's, where the addon has one. Never rename
them. The `whatsnew` command and a Settings button open it any time, with
each addon's newest. It rises in, its divider draws out, each addon's card
slides up with its icon popping and a light crossing it, and the Got it
button glows (one looping animation the game plays, only while it shows);
Motion off lands it all at once. Not yet seen in game.

## The About page and the note

The owner asked (2026-10-13) for a note on how the addons are made, once at
the top of What's New and kept on an About page in every addon's Settings.
`UI/About.lua` is the same file in all five (a fix to it belongs in all
five): `About.NOTE` is the owner's wording, a paragraph a key; change it
only when he asks, in all five, with each `Locale/deDE.lua`. `About:Note`
and `About:Info` build the page's two columns (the version, the Discord in
a box to copy, how to report a bug, a thank-you that names no player, a
What's New button and the other Blackthornes addons from
`SisterNote.ADDONS`); each addon's Settings places them on its "about"
page. `UI/WhatsNew.lua` (FILE_VERSION 3) puts the note at the top of the
next window that comes up by itself, alone when nothing is new, then sets
`aboutNoteSeen` in every sister's account save (never rename it); with the
window turned off it waits. Tested in `tools/test_whatsnew.lua`.

One-time cards (the owner, 2026-10-13): an addon can put cards in
`ns.WHATS_NEW_TIPS`, each `{ key, title, icon, paragraphs, hint, button,
run, due }`. The next window that comes up by itself shows each one after
the note, only when `due()` says so (in a pcall), with a button that calls
`run()` and closes the window. Looked at once either way: the key goes in
that addon's account save as `whatsNewTipsSeen[key]` (never rename it), so
a card never comes back; with the window turned off it waits.
`UI/WhatsNew.lua` is at FILE_VERSION 4 for it. Equipment's
`Logic/UpgradeQuest.lua` has the first, for the upgrade quest, due while
it is off.

## The sister note

The owner asked (2026-10-11) for the addons to say, once, which of the
others a player does not have. `Core/SisterNote.lua` is the same file in
all five (a fix to it belongs in all five), and so is
`tools/test_sisternote.lua`. Every copy signs up in `_G.BlackthornesSisterNote`
as it loads; the first to reach PLAYER_LOGIN starts the only timer
(`SisterNote.DELAY`, 8 s, no ticker), and that one check prints one line for
all of them: the sisters not installed (`C_AddOns.DoesAddOnExist`, else
`GetAddOnInfo`'s "MISSING"), each with what it adds. One installed but
turned off is never named. Once per account: what it named is kept in every
loaded addon's account save as `sisterNoteTold[folder] = true`, so only a
sister never named before (one released later) brings it back. "Sister
addons" in Settings (`sisterNote`, on unless unticked) and the `sisters`
command on each addon: off in any is off in all, and changing it writes all.
Never rename `sisterNote` or `sisterNoteTold`. A new addon goes in
`SisterNote.ADDONS` in all the copies. It names only our own addons.

## One key per character

The owner asked (2026-10-11) that a character can never be mistaken for
another again. Old records had sent errands to the character playing:
Butler filled a mail to itself and told a player to mail Medium Leather to,
and log out for, the character they were on (an old "Name-Realm" record of
Tradeskills' beside the GUID one), and a reload wiped alts' saved gear in
Equipment. The rule, in every addon:

- **A character is its GUID** (`UnitGUID("player")`) in saved data and in
  every call between the addons. Never a first name, "Name-Realm" or a
  short name: Forever lets characters share a first name. Names are for
  showing and for a mail's To line only, always first and last.
- **A GUID the client won't read (a dungeon) means "not sure who's
  playing":** write nothing under another key, and offer nothing for an
  alt. Tradeskills remembers each character's GUID in its own file
  (`BlackthornesTSCharDB.guid`) for that case.
- **Old records stay readable and count as the same character; nothing is
  deleted.** Tradeskills folds an old "Name-Realm" record into the GUID one
  at login, once (`Config:AdoptLegacyCharacter`): it is kept whole in
  `formerCharacters[old key]` with `retiredInto` (never rename either), what
  the GUID record lacks is filled from it when it carries that GUID, and
  the queue's references to the old key follow. Farmer reads a goal tagged
  "Name-Realm" as the character's and tags it with the GUID once the
  character gathers toward it or changes it.
- **One test per addon answers "the same character?" and "the one
  playing?"; never compare keys or names by hand.** Tradeskills:
  `Characters:Same`, `:IsPlaying` and `:Canonical` (`Core/Characters.lua`),
  and `playing` on each `Butler:Holdings()` entry. Butler:
  `Errands:IsMe(name)` (full name, first name alone, any old record's name,
  any case, with or without a realm). Farmer: `Goals:IsOwner`. Equipment:
  `Alts.PlayerGUID()`.
- **Every errand that targets a character asks that test right before it
  acts and refuses the character playing:** a mail, a gold top-up, a Log
  out, an alt's upgrade, a learned habit, the disenchanter.
- Tested in Tradeskills' `tools/test_onecharacter.lua`, Butler's
  `tools/test_notme.lua`, Farmer's `tools/test_goals.lua` and Equipment's
  `tools/test_alts.lua`. This rule is in every addon's notes; keep them the
  same.

## German and other language clients

The data names items, zones, skills and creature types in English; a
German client names them in German. Nothing is translated: each check
also knows the client's own word, by ID, and only when
`Util.EnglishClient()` (`GetLocale`) says the client is not English, so
an English client runs exactly as before. Items: `DB:GetItem` falls back
to the name the client gives each ID (`DB:ByClientName`, read a few items
a frame and on `GET_ITEM_INFO_RECEIVED`), the search matches it too, and a
goal set by the client's name keeps that name (`Goals:ResolveItem`;
`Goals:Find` matches either name). Skills: `Gathering.ClientNames` and
`SkillOf` (spell names by ID, skill line names through
`C_TradeSkillUI.GetProfessionInfoBySkillLineID`). Zones: see "Zone names from
the client" below. Creature types are kept in English (`Grinding.EnglishType`,
`C_CreatureInfo.GetCreatureTypeInfo`), and coin words come from
`COPPER_AMOUNT` and the like (`Harvest.CoinValue`). Loot records stay keyed
by the client's mob name, and fishing schools are still told by English
name endings. Tested in `tools/test_german.lua`. Not yet seen in game.

The translation (the owner said yes, 2026-10-11, after Pets' pilot):
Farmer's own words are in German on a German client. Players are told
the language as "Deutsch"; the code names stay `deDE` and
`Locale/deDE.lua`.

- **English is the key and the fallback.** `Locale/Locale.lua` (first in
  the TOC, Pets' file) makes `ns.L`, whose missing keys answer the key
  itself. `L.Format(key, ...)` is `string.format` on the translation and
  puts values named by place (`%2$s ... %1$d`) in order.
- **Adding a string:** write it as `L["English text"]` or
  `L.Format("English %s", value)`, a literal where it is written, one
  whole sentence a key (never pieces joined with `..`), both forms for a
  plural (`Util.Plural(n, L["kill"], L["kills"])`); add its line to
  `Locale/deDE.lua` (informal "du" and the game's words: Beute, Ziel,
  Gegner, Vorkommen, Fundort, Kürschnerei, Fischschwarm, Stufe, Gebiet,
  Meter) and run `python tools/check_locale.py` (warns only; keep it at 0
  missing). `tools/test_locale.lua` loads the addon as a German client.
- **Left in English on purpose:** slash command words, saved and internal
  keys, anything compared against data or the client (zone names, coin
  words, skill names, creature types: `Grinding.TypeLabel` only shows
  one), data names (items, mobs; zones are kept English and only shown
  in German, `Spots.Show`), "Creature #ID", the harvest and
  fishing export text, debug lines, and the checks players run for a
  report (`/farm arrow check`, `gathering check`, `harvest check`).
  `Spots.Hops`' `travel` stays English; only `Spots.DistanceText` says it.
- German runs about 30% longer: buttons grow to fit, settings rows wrap,
  and a new fixed width must wrap or grow, never end in "...".
- `Locale/Locale.lua` and `tools/check_locale.py` are the same as Pets';
  a fix to either belongs in every addon that has them.

## Simplified Chinese, French, Spanish and Russian

The owner asked (2026-10-18) for Simplified Chinese, French, Spanish and
Russian in every addon, after a player asked for Chinese. They work like
German: written by us from the English keys, never from a player's or
anyone else's file (the owner turned down a player's zip for safety).
`Locale/zhCN.lua`, `Locale/frFR.lua` ("tu"), `Locale/esES.lua` (one
Spanish for both Spanish clients: it loads on "esES" and "esMX", neutral
words, "tú") and `Locale/ruRU.lua` ("ты"), each in the game's own words,
listed in the TOC and in `tools/testenv.lua`'s `FILES` after deDE. Yards
show as metres as in German, except Chinese keeps 码. Talk to the owner
about "Simplified Chinese", "French" and so on, never the codes. Every new
string gets a line in all five files; `tools/check_locale.py` checks them
all. Tested in `tools/test_locale.lua`. Not yet seen in game.

## Zone names from the client

The owner said "do it all" (2026-10-12) to using the Forever client's game
tables in every addon. Farmer's part is `Data/Zones.lua`, written by
`tools/make_zones.py` from the tables' AreaTable, Map and UiMap (English
and deDE exports, build named in the file; never edit it by hand, and never
commit the tables or name where they came from: "the Forever client's game
tables"). It holds names and map IDs only, no drop rates or spawns.

- `ns.ZONE_DATA.maps`: each zone's map ID, Forever's own (they match
  Classic's, and Forever's new zones are there). `Spots.ZONE_MAPS` is
  built from it; `Spots:Player` names the zone by the map when the name
  alone does not say.
- `ns.ZONE_DATA.english.deDE`: the English name of every German zone,
  dungeon and raid name the client gives. `Spots.English` reads it on a
  German client (after the names seen this session), so a record kept
  under "Wald von Elwynn" counts as Elwynn Forest anywhere.
- `ns.ZONE_DATA.names.deDE`: the German name of each, for showing.
  `Spots.Show(zone)` gives it on a German client (`Spots.ZoneLocale`, read
  once) and the zone as it is otherwise. The search rows and zone
  headings, Where to farm, the Grind tab and its pins, the item tooltip,
  Rankings, fishing and gathering places and the arrow show zones through
  it, and the search matches the German name too. Everything kept or
  compared stays English. A new place that shows a zone calls it too.

Tested in `tools/test_zones.lua`. Not yet seen in game.

## Writing for players

Every word a player reads (labels, buttons, tooltips, Settings rows and
their descriptions, empty lists, chat lines, slash command help) reads the
way a friend who plays would say it: plain, warm and human. Write it at a sixth grade reading level. Short
sentences in everyday words, contractions welcome. Say what the player
sees or does, not how the addon works inside. No hype or sales words
("seamlessly", "effortlessly", "now you can", "powerful"), no filler, no
em-dashes, and no questions to the reader. The German in
`Locale/deDE.lua` changes with the English, in the same informal "du"
voice. Farmer's play cheers keep their "!" (drop-quality cheers, goal
marks, streaks, "Up to #N!", "Goal done: X!"), and `About.NOTE` is the
owner's own wording. This rule is in every addon's notes; keep them the
same.

## The owner's standing rules (both addons)

- **Every list is dark glass** (the owner, 2026-10-12: "keep this as the
  standard across all Blackthornes addons", after Farmer's Kills & Loot
  panel was given the look of Tradeskills' queue). Rows or lines take
  `glass` and `glassAlt` in turn, by place, with a 1 px `border` line
  (alpha 0.6) under each; under the mouse `glassHover` and a gold edge,
  only on that row; the row picked or open is `glassActive` with a bright
  gold edge down its left. Never the older `row`/`rowAlt` bands for a
  list, a panel's lines or cards. A gradient fades through
  `Theme.LightGradient` or is hidden, never with SetAlpha alone (it stayed
  lit on Forever). This rule is in every addon's notes; keep them the same.
- **"Always check that it's clear to post."** Anything public is checked for
  private or unexpected content first, and nothing is published or uploaded
  without the owner's go-ahead. He tags releases himself.
- **Changelogs come from git history,** never from asking the owner. Claude drafts
  the CHANGELOG section in a PR; the owner merges, pulls `main`, tags and pushes.
- **A checkout shows the real version number** (the owner,
  2026-10-12). `ns.RELEASED_VERSION` in `Core/Init.lua` is the newest
  `## X.Y.Z` in CHANGELOG.md, shown when the packager has not filled in the
  TOC's `@project-version@` (he plays from a clone). The release PR that
  writes the CHANGELOG section changes it too; `tools/check_release.py`
  refuses a tag it does not match, and `tools/test_check_release.py` fails
  while the two disagree. This rule is in every addon's notes.
- **Every reply that ships code ends with the GitHub Desktop steps,** naming
  the branch: merge the PR on github.com, switch **Current branch** to
  **main**, **Pull origin**, then `/reload` or a full restart (a full restart
  when a file is added, removed or renamed, or the TOC changes).
- **Grey (poor quality) items are priced at vendor only;** everything else is
  max(auction, vendor).
- **CurseForge descriptions are features only:** no privacy notes and no
  explanation of public emotes or their switches.
- **Smooth play comes first, but never at the cost of looks** (the owner,
  2026-10-09, after a hitch while crafting). Nothing on a timer or
  OnUpdate rebuilds or re-places a whole list, map or set of markers when
  only one thing moved: keep what is drawn, and redo only rows or pins
  whose inputs changed (a per-row key, a version number). Bag, loot,
  cast, skill and profession-list events arrive in bursts, several per
  craft or loot: coalesce them, read only what they changed, and skip
  work for windows that are hidden. Work over hundreds of items (recipes,
  sources, saved spots) is spread over frames (a worker with a small
  per-frame budget) rather than done in one frame, and shown when done.
  Clicks and typing still answer at once. The two causes found: Farmer's
  minimap markers gathered, sorted and re-placed every saved spot once a
  second because the clock second was in their redraw key (now only the
  fade moves, `MapMarkers:FadeMinimap`); and on every craft Tradeskills
  re-read every recipe in the profession window and repriced the whole
  craft pane in one frame (now `Recipes:NothingNewMidCraft` skips the
  re-read mid-run and `CraftPanel:RefreshInSlices` spreads the pane over
  frames). Visuals and usability are never traded away for speed. This
  rule is in all four addons' notes; keep them the same.
- **The client is WoW: Forever, a retail engine** (`## Interface: 16001`,
  modern Lua), not 1.12. Read client values inside a pcall; instances hand out
  secret values that raise when touched.
