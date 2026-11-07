# Forever sync

Where this Classic Era copy stands against Forever Farmer
(`Blackthornes/Blackthornes_Farmer`). Forever is only ever read from here.

This copy was made from Forever main at `f4a63c0` (the merge of its PR
#357, 2026-10-23) with its history on 2026-10-24.

Copied over since, one at a time:
- `16167e1` Add a fold gem beside the close gem (2026-10-24, cherry-picked
  as it is; `UI/FoldWindow.lua`, its art tool and test match the other
  Classic repos).
- `c493162` Start release posts with the game name (2026-10-24, copied
  by hand with "Classic Era" in place of "Forever"; see
  `docs/CLASSIC_DIFFERENCES.md`).
- `3e278ad` Show the gathered item on map markers, greyed until it grows
  back (2026-10-24, blended with Retail's spot counts and joining; see
  "Gathered spots on the maps" in `docs/CLASSIC_DIFFERENCES.md`).
- `82cb9cd` Share data with Blackthornes faster (2026-10-26, copied by
  hand: hellos and syncs every five minutes; Classic's own recipients
  kept, see "Sending drops to Blackthornes goes to Era characters").
- `2c4977a` One minimap button for every Blackthornes addon (2026-10-28,
  Forever PR #381, cherry-picked as it is; `UI/SharedMinimap.lua` and its test
  are the same in all five Classic repos).
- `5df8a9c` Shared minimap button shows the Blackthornes thorn B (2026-10-29,
  taken as it is: `UI/SharedMinimap.lua` at FILE_VERSION 2,
  `Media/Frame/MinimapBadge.tga` and `tools/make_minimap_art.py`, the same
  in all five Classic repos).
- `2a7e7f3` Slim the shared minimap menu: names only, sized to fit (2026-10-29,
  taken as it is: `UI/SharedMinimap.lua` at FILE_VERSION 3 and its test, the
  same in all five Classic repos).
- `6049bf6` Time arrow flights by their real length (2026-10-29, as it is).
- `a61b1c5` Where to farm says pinned only when a marker really shows
  (2026-10-29, as it is; `UI/SpotMarker.lua` is the same in Farmer, Butler,
  Tradeskills and Pets Classic).
- `dea75f5` (Butler's) the way there card's rows grow when a step wraps
  (2026-10-29, `UI/TravelCard.lua` only; the rest of `a246e8c` is not taken yet).
- `af3d6fd` Settings as the window's last tab (2026-10-29, Forever PR
  #373, as it is).
- `a2c2aa4` House look for the right-click menu and close gems (2026-10-29,
  Forever PR #374, as it is, with the menu's rows kept at Classic's height).
- `3154560` One look across the five addons (2026-10-29, Forever PR #388):
  `UI/HouseKit.lua`, `UI/RowMenu.lua`, `UI/Notice.lua` and
  `UI/SharedChoices.lua` as they are (the same in all five Classic repos),
  `UI/PanelSnap.lua`, and the footers, hovers, Title Case tabs and General
  page. Left out: Arrow Size (Farmer Classic has none, so an arrowSize from
  a sister is ignored). The Grind tab's hover hint keeps Classic's camp
  worth line, and the search hover hint has no "not yet seen" part.
  `UI/Plaque.lua` keeps Classic's own copy with the new `Plaque.TextWidth`,
  the same in Farmer, Pets, Equipment and Tradeskills Classic.
- `88d21a8` One Window steps aside for an open letter (2026-10-31): docked at
  the mailbox it moves beside the letter and back, and tells side panels
  when it docks, moves or undocks (`SharedWindow.Watch`, `DockedFrame`).
  `UI/SharedWindow.lua` is FILE_VERSION 5, the same in all five Classic
  repos.
- `8a7fff4` Set Default under Window Position keeps Settings in the one
  window (2026-11-02, as it is).
- `700ed82` One Key Fishing says "Your bobber is too far to reel in. Cast
  again from closer." when the key picks nothing (2026-11-02; only the new
  line added to each locale).
- `773be8f` My Professions Only map markers (2026-11-02, on unless
  unticked). Blended with Classic's joined herbs and veins: `JoinedOn` reads
  the filtered `SpotsOn` and keys its cache on the kinds shown, so the
  filter runs before joining. Era has no `GetProfessions`, so the skill
  lines answer.

- `f6bccf4` The fishing panel: This Session, This Spot and Fish Log with
  small cheers (2026-11-02, `UI/FishingPanel.lua` as it is but for
  `PlaceStrip`, which Classic's fishing bar hands its lure line; see "The
  fishing bar" in `docs/CLASSIC_DIFFERENCES.md`).

- Fixes of 2026-11-05 (copied 2026-11-07, as they are): `efabe13` One
  Window keeps its size when it docks or undocks while folded
  (`UI/SharedWindow.lua` FILE_VERSION 8, the same in all five Classic
  repos; Classic has no `SharedWindow.Fit`, so only Dock, Undock and Refit
  read `FullSize`); `7232ac3` and `3c43153` sparkles leave the Interact Key
  as the player sets it and take the interact plate off NPCs; `65b920f`,
  `b0357be`, `6fee325`, `a24df14` and `789c756` guild sharing answers a
  guildmate's hello after a reload, with the typed `/farm share guild
  check`. Left out: `45ccea4` (guild drops in the loot table).
- `e6a9531` The Top 15 window can be dragged and keeps its spot (2026-11-07,
  as it is: `rankUpX`/`rankUpY`, "Top 15 Position:" Set Default on the Kills
  page, `/farm rankup reset`).
- `45ccea4` and its test `a5b7d3b` Guild drops blend into the loot table's
  Drop Rate and Per Kill once the player has 20 kills of the mob (2026-11-07,
  as they are: `GuildShare:LootFor`, `LootTableUI.Blend`; only items already
  on the player's own table, read from `guildDrops`, nothing saved).

Every catch-up reads `docs/CLASSIC_DIFFERENCES.md` first, and the PR that
brings Forever commits over updates the line above to the newest one it took.
