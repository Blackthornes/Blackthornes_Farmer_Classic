# Classic differences

Every place this Classic Era copy differs from Forever Farmer, and why. Keep
it short and current: a PR that adds a Classic-only change adds its line
here in the same breath.

## The catch-up rule

Every Forever catch-up checks this note first, before sorting commits into
"fits Era", "Forever only, skip" or "needs changes for Era".

- A Forever commit that touches nothing listed here comes over as it is.
- A Forever commit that touches only a file Classic leaves out of the TOC
  (below) is "Forever only, skip", unless it also changes how the readers
  that ask for it behave.
- A Forever commit that lands on something listed here is a clash. Show the
  owner both versions side by side and offer three choices:
  - **Keep Classic's:** skip the Forever change.
  - **Take Forever's:** only when it really replaces what Classic did.
  - **Blend them (the usual pick):** bring Forever's idea over on top of
    Classic's version.
- Whatever is picked, nothing below gets lost by accident. If a pick changes
  a line here, the same PR changes the note.

## What differs

### The TOC
- `## Interface: 11509`, what the owner's Era client reports. Forever is 16001.
- `## X-Curse-Project-ID: 1763311`, Farmer Classic's own project. Forever's
  1710618 must never be here: `tools/check_release.py` refuses a tag that has
  it (tested in `tools/test_check_release.py`).
- The folder, TOC name, saved data (`BlackthornesFarmerDB`) and slash
  commands are the same as Forever's, on purpose. Never rename them.

### Forever data and features left out of the TOC
The files stay in the repo so Forever changes still merge cleanly; Era never
loads them. Every reader asks for them first, so Era works without them.
`env.FOREVER_DATA` in `tools/testenv.lua` lists them, and `tools/test_era.lua`
loads, logs in and searches with them gone.
- `Data/ForeverNpcNames.lua`: Forever's own mob names.
- `Data/Data_Harvested.lua` and `Data/Harvest_Carryover.lua`: the owner's
  Forever harvest. Era drops must never mix with Forever's shipped data.
  `Data_Harvested.lua` comes back once it is made from Era play
  (`tools/harvest_import.py` adds it to the TOC).
- `Logic/Legacy.lua`: Forever's Legacy perks. Every reader asks `ns.Legacy`
  first.

### Classic data kept
Classic's own data stays loaded: the seed files, `Data/Data_ClassicDrops.lua`,
`Data/NpcNames.lua`, `Data/Zones.lua` and the travel files. Their
Forever-only zones and flight masters are never met on Era, and a flight is
used only once the character knows it, so they need no change.

### Sending drops to Blackthornes is off
- `Contribute.RECIPIENTS` in `Logic/Contribute.lua` is empty: those
  characters play on Forever, and Era drops must never reach Forever's
  shipped data. `Contribute:HasRecipients()` says so, and `Sending()` asks it.
- `Contribute.REGIONS` is only `[1]`; Forever's test client region 110 is gone.
- `UI/Settings.lua`'s About page shows no tick box while nobody is named.
- Tested in `tools/test_contribute.lua`.

### Hiding an item hides its random rolls
- `DB:IsHiddenItem` in `Data/Database.lua` also checks the item's own name
  for a random roll (`RollBaseOf`, through `Harvest.RollBase`), so hiding
  "Primal Leggings" from Rankings (which shows the item once) leaves every
  "of the ..." roll out of a mob's worth and best drop. Forever has the same
  bug; keep this on a catch-up.
- `Value.FoldSuffixes` gives the folded drop the item's `id` and a roll's
  `lookName`, and `Rankings.IsUncommonOrBetter` reads it, so "Skip Uncommon
  and better" leaves out a folded green too.
- Tested in `tools/test_suffixdrops.lua`.

### Gathered spots on the maps
- Forever's `3e278ad` came over blended with Retail Farmer's idea: a spot
  counts everything it gave (`spot.items`, from `Gathering.NoteItems`)
  rather than Forever's one `spot.item`, and the hover lists those items with
  counts.
- A herb or vein within `Gathering.NEAR_YARDS` of a spot of its own kind
  joins it (`Gathering.Joins`, `spot.also`), since Era grows a different node
  on one spawn point; older close spots draw as one (`Gathering.Joined`).
  Forever has neither.
- A fishing spot's marker is in full colour in a blue ring; Forever's stays
  grey. Fishing still marks only schools you moused over, as Forever does.
- Tested in `tools/test_mapicons.lua`. Keep all of it on a catch-up.

### Notes and docs
- `CLAUDE.md` opens with "This repo is the Classic Era copy".
- `README.md` names the Classic CurseForge project.

### Discord release posts
- `tools/announce_discord.py` and `tools/post_general.py` start both
  posts with "Classic Era: " (their `GAME`), where Forever's start with
  "Forever: ", so the two games' releases read apart. A catch-up that
  touches these tools keeps Classic's word. Tested in
  `tools/test_announce_discord.py` and `tools/test_post_general.py`.

### No Forever words for players
- The owner asked (2026-10-24) for no "Forever" a player can see. Search
  rows, chat lines (`Search:SourceLine`) and Grind rows carry no Forever
  tag, the search footer is only "Click a row to put it in chat.", and
  `/farm data` has no "Forever can be different" line and calls the
  `forever` rows "seen in your own play" (`DB.PROVENANCE`; the key stays). The badge slot stays
  for clean merges. Tested in `tools/test_search.lua` and
  `tools/test_textfit.lua`.
- The About thank-you (`About.THANKS`) has no "WoW Forever is almost here"
  paragraph (the owner, 2026-10-24). `UI/About.lua` is shared with Forever;
  a catch-up that brings the paragraph back keeps Classic's.

## Not yet done
- Not yet seen in an Era client. Client calls are read in a pcall, and the
  code already falls back to the classic calls (skill lines, spell info, the
  older tooltip scripts) where Era lacks the newer ones.
