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

Every catch-up reads `docs/CLASSIC_DIFFERENCES.md` first, and the PR that
brings Forever commits over updates the line above to the newest one it took.
