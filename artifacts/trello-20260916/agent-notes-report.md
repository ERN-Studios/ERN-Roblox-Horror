# A-NOTES — Field Notes (#85/#88)

Baseline `aa40f70`. Nothing pushed to Studio, nothing committed, `studio-sync-manifest.json`
untouched. All four `.lua` files are NEW mirror files for the lead to create in Studio.

## Files

| Path | Class | Lines |
|---|---|---|
| `G:\Roblox\MongoTV\ReplicatedStorage\ZyntraFieldNotes.ModuleScript.lua` | ModuleScript (shared) | 179 |
| `G:\Roblox\MongoTV\ReplicatedStorage\ZyntraFieldNotesPage.ModuleScript.lua` | ModuleScript (client UI page) | 384 |
| `G:\Roblox\MongoTV\ServerScriptService\FieldNotesService.Script.lua` | Script | 504 |
| `G:\Roblox\MongoTV\StarterPlayer\StarterPlayerScripts\Field Notes Client.LocalScript.lua` | LocalScript | 257 |
| `G:\Roblox\MongoTV\tools\tests\test_field_notes.py` | offline suite | 1422 |

Nothing else was created or edited. Other files in `git status` belong to the parallel agents.

## What it does

One optional prop per round. It spends nothing, grants no stat, and never gates an exit.

1. `FieldNotesService` watches `workspace` for `RoundActive == true` **and**
   `RoundLoadingState == "ready"`, reads `workspace:GetAttribute("SelectedLevel")`
   (verified by grep: GameManager:1412/1531 and both Round Adapters are the only writers),
   and makes **one** placement attempt per (round, level).
2. It scans the level world root for walkable floor parts, shuffles them with a
   `Random` seeded off the round's own layout seed, computes at most **14**
   `PathfindingService` routes from the spawn pad, keeps only `Status == Success`,
   and places the prop at the **median** surviving route length.
3. Holding `READ NOTE` (0.4 s, 8 studs) re-validates server-side, then calls
   `ServerStorage.ZyntraInventory:Invoke("DiscoverNote", player, level)` and answers
   `Remotes.FieldNote` with `("discovered", noteId)` / `("alreadyLogged", noteId?)` /
   `("unavailable")`.
4. `Field Notes Client` opens a non-modal reading card; `ZyntraFieldNotesPage` is the
   terminal's NOTES tab.

## Decisions taken (not asked)

- **World roots are three string literals** (`Maze`, `Level 2 Generated World`,
  `Level 3 Generated World`) rather than a require of each level's Configuration.
  Every other file in the repo already hardcodes them (`Level 3 Reader Client:19`,
  `Level 3 Sound Controller:17`, `GameManager:816`, `Level 2 Round Adapter:250`), and
  a server service that needs one string should not pull in a level's whole config.
  It also kept me out of `Level 3 Configuration`, which Codex owns.
- **Start point is `ElevatorSpawn`, falling back to `MazeStart`.** Both are parented to
  `workspace` by all three builders, but on Level 2 `MazeStart` sits on the arrival deck at
  `topY` while `ElevatorSpawn` is the pad the party lands on
  (`Level 2 World Builder:5578-5581`). Route length has to be measured from where the
  players are.
- **The candidate point is the floor part's top-face CENTRE.** A candidate is already
  `> 4` studs on both horizontal axes, so its centre is `>= 2` studs from every edge —
  past the 1.5-stud clearance the brief asks for, with no edge arithmetic, and it is the
  point on a maze floor tile furthest from the walls that sit on the tile boundaries.
- **"Not the exit area" is enforced by the median rule, not by an exit list.**
  The three levels represent their exit three different ways
  (`Level2_ExitPosition`, the Level 1 gate, Level 3's Energon Freight exit); the longest
  route in the sample *is* the far end, and the median is structurally not it. The
  **start** area is excluded explicitly (`START_CLEARANCE = 60` studs).
- **`isFloor` adds three filters the brief did not list**, each one expression and each
  one preventing a sign inside geometry: top face must be level (`CFrame.UpVector.Y >= 0.9`
  — kills slide tubs, ramps, diving boards), the part must be blocky (no wedge, truss,
  ball or cylinder), and it must be visible (`Transparency <= 0.5` — an invisible
  collidable slab with a floor's footprint is a barrier, not a floor).
- **Water:** parts whose own `Material` is `Water` are rejected. Level 2's wading-depth
  water is *Terrain*, not parts, and a sign standing ankle-deep in a water park is correct.
- **ONE attempt per (round, level).** `attemptedLevel` exists only to stop a later
  `RoundLoadingState` or `SelectedLevel` write re-running the scan on a round where
  placement already failed. That is the Pool Slide's retry-forever failure under another
  name, and the suite has a check and a mutation for it.
- **The sign is double-sided.** A generated level has no direction the party arrives from,
  so a single `SurfaceGui` is blank from wherever half of them walk in. Two faces, built
  in a two-iteration loop.
- **The reading card is NOT a modal.** No `ScreenOwningModal`, no movement suppression,
  no cursor unlock, no input-consuming shade, no published attribute. `DisplayOrder 60`
  sits above the HUD and under Round Exit (70) and PARTY DOWN (100). A note is never the
  most important thing on screen while a hostile is hunting.
- **The detail view reuses the page's ONE ScrollingFrame** rather than adding a second,
  because `contract.scroll` publishes one scroll per page to the regression matrix.
- **Notes text has no four-digit numbers anywhere** (a year reads as a claim about the
  real world), numbers inside bodies are spelled out, and no real person, company or
  organisation appears. Bodies are 35–60 words, asserted per note.

## Verified offline, and how

`python tools/tests/test_field_notes.py` with
`LUAU_BIN=C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe`:

```
Field Notes content: 140 checks passed
Field Notes service: 101 checks passed
Field Notes client:   43 checks passed
Field Notes page:    308 checks passed
Field Notes: 592 checks passed (real Lua sources, offline Luau)
```

Four programs, each concatenating the **actual** `.lua` file and driving it under a fake
DataModel. Nothing is string-matched and nothing is reimplemented. `UIStyle` and
`ZyntraFieldNotes` are loaded from their **real** sources too, so the chrome the prop and
the card wear is the chrome the game ships. The fakes are kept honest: `Color3` carries no
arithmetic metamethods, `Vector3`/`CFrame` do, `CFrame` and `Position` are one fact on a
BasePart (the harness failed once because they were not, which is the bug that check now
prevents), `Enum` items are memoised so identity comparison behaves, and
`ProximityPrompt.Triggered` proves nothing about distance or health.

Covered: exactly one prop on ready and none otherwise; the median pick at 1/3/4 successes;
every `isFloor` rejection (small, unanchored, non-collidable, water, tilted, invisible,
wedge, cylinder, non-BasePart) including that no route is even computed for them; spawn
clearance; nothing-pathable places nothing and warns once; a throwing `ComputeAsync` is
survived; missing spawn marker / missing world / unsupported level; the 14-route ceiling;
a pinned layout seed reproducing the same spot; teardown on `RoundActive` false; a
`"loading"` state mid-round NOT tearing down; the Level 2 → Level 3 continuation replacing
rather than stacking; a round ending mid-scan abandoning the remaining routes; both sign
faces; `discovered` / `alreadyLogged` / `unavailable`; the per-player repeat; the 2 s rate
limit; and seven refusal cases (out of reach, dead, no humanoid, no root, bodyless, not
InRound, round over) each proving the inventory was never invoked. Client: DisplayOrder,
the real note text on the card, CLOSE, the 14 s auto-close, a second card not being closed
by the first card's timer, both captions and their 3 s life, an unknown id, closing on
`InRound` false, the 44 px touch floor, and the card staying inside the modal lane above
the movement cluster. Page: the twelve rows, the level group headers, contract
registration (1 scroll, 12 cards, unique keys), discovered vs undiscovered rendering,
progress text and fill fraction, both title-line states, the `ZyntraConfig` title
override, detail open/back, an undiscovered row not opening, 1/2/3 column tiers plus a
narrow-pointer fallback, tap floors and card containment at every tier, no type under
11 px, no key glyphs, profile push and `refresh()`, `destroy()`, a missing content module,
a terminal without `contract`/`registerLayoutHook`, and a nil `UIStyle`.

**Mutation-tested.** Sixteen deliberate faults were introduced one at a time into the real
sources and the suite re-run; **all sixteen were caught**: median → shortest, dropped
`InRound` check, dropped rate limit, dropped distance check, accepting tilted floors,
re-enabling the retry loop, raising the route ceiling, dropping the mid-scan generation
guard, DisplayOrder above PARTY DOWN, auto-close drift, caption wording, touch tap floor,
changing the disabled caption, forcing three columns, leaving undiscovered rows clickable,
and a level/id mismatch in the content. The eighth of those was MISSED on the first run —
a second guard after the loop masked it — so the test was strengthened to assert the scan
*stops* (2 routes computed, not 4) rather than merely that nothing is placed.

`luau-compile.exe --binary` passes on all four files. `luau-analyze.exe` reports only
unknown-Roblox-global type errors (expected without Roblox type definitions) — no unused
locals, no shadowing.

**Interface handshake re-checked against the sibling agents' live working copy:**
`ZyntraMonetization:367` `fieldNoteEntries()` reads `loaded.Notes` and
`ZyntraMonetization:3095` `nextFieldNote` reads `note.Id` / `note.Level` and sorts by
`Id` — exactly the shape this module returns. `ZyntraConfig:70` already carries
`FieldNotes.CompletionTitle = "FIELD ARCHIVIST"`. `ZyntraStore:504` already mounts
`Notes = "ZyntraFieldNotesPage"` and its ctx matches the contract field for field.
`UIRegression:5034` already lists `NOT YET FOUND`, and `Notes` is already deliberately
absent from `Fit.ZyntraExpectedActive` (`UIRegression:5054`). **No change is needed in any
file I do not own.**

## NOT verified — needs Studio

- **Real pathfinding.** The suite's `ComputeAsync` answers from a table. Whether a real
  generated Level 1 maze / Level 2 poolrooms / Level 3 mall actually yields Success for a
  usable fraction of 14 sampled floor tops is unmeasured. **Ask for the placement warn
  count across a few rounds per level**: `[FieldNotes] nothing pathable on level N` in the
  server log means the sample is too small or `START_CLEARANCE` too large.
- **Real geometry.** That the prop does not intersect a column, a pool ladder, a table or
  a slide leg. Top-face-centre plus the `isFloor` filters is the argument, not a
  measurement. Level 2's halls are up to ~250 studs a side, so the centre of one hall
  floor part is a wide open space; Level 1's 24-stud tiles are the tight case.
- **Timing cost.** 14 `ComputeAsync` calls in one spawned thread at round start. Worth one
  `ScriptProfilerService` pass on Level 2, which is the largest world.
- **Fonts and real text bounds.** `TextService:GetTextSize` (synchronous, as ZyntraStore
  already uses) drives the card and detail heights; only a rendered pass proves a 60-word
  body fits the card on the narrowest phone without clipping.
- **The world-space sign.** `PixelsPerStud = 64` on a 2.4 × 3 stud board with 26/13/11 px
  type is arithmetic, not a look. Needs eyes on it at 8 studs in a dark corridor, plus a
  check that the `PointLight` (range 14, brightness 1.6) reads as a marker and not as a
  lamp that spoils the level's darkness.
- **Prompt visibility.** Per the project memory, a `ProximityPrompt` only shows and
  triggers while inside the camera frustum — point a Scriptable camera at it first when
  testing from `execute_luau`.
- **The terminal tab rendered.** Column tiers, the progress track and the detail panel are
  asserted in offset arithmetic, never drawn.

## Open questions for the owner / lead

1. **Twelve is the whole collection.** Four per level, and the level's fourth read is the
   last one that level can ever grant. Is twelve the intended "modest finite initial
   collection", or should each level carry six? Adding notes is a data-only edit: append
   ids at the end of a level's block and raise `Total`. **Ids may never be renamed or
   recycled once a save exists** — a renamed id is an unrecoverable hole in somebody's
   collection.
2. **One note per round, shared.** Every participant may read the same prop once, so a
   full party of six can each log a note in one round. If that is too fast, the lever is
   the prop, not the text: one reader per round instead of one per player.
3. **`START_CLEARANCE = 60` studs.** Tuned by eye against Level 1's 24-stud grid. If
   Level 2 or Level 3 rounds report "no floor candidates", this is the number to lower.
4. **The completion title is published but nothing wears it in-round.** A-SERVER writes
   `ZyntraFieldNotesTitle` and awards the badge; whether a name tag or the lobby shows it
   is A-SERVER's/A-HUD's to answer, not this file's.

## Artwork needed from Codex

**None.** Both surfaces are typography and UI shapes only — `UIStyle` chrome, a 1 px
accent rule on the world sign, a `PointLight` in the accent green, and a track/fill
progress bar on the terminal page. No textures, no decals, no image assets, no invented
asset ids.

## Disabled-caption strings used

| Where | String | Status |
|---|---|---|
| Terminal NOTES card, undiscovered row | `NOT YET FOUND` | already present in `Fit.ZyntraDisabledCaptions` (`UIRegression:5034`) — no change needed |

The card action is taken out of the input stack with `UIDevice.SetEnabled`, not hidden, so
the caption is measurable by the fit matrix. `Notes` must stay **absent** from
`Fit.ZyntraExpectedActive` — how many actions are reachable depends on the tester's save
file, the same reason Shop/Dev/Settings are absent. It already is.

Other player-facing strings this feature introduces: `FIELD NOTE RECOVERED`,
`ALREADY IN YOUR COLLECTION`, `FIELD NOTES UNAVAILABLE`, `FIELD NOTE LOGGED`,
`ZYNTRA // ARCHIVE`, `FIELD NOTES`, `n / 12 RECOVERED`, `TITLE: FIELD ARCHIVIST`,
`Recover every note to earn the FIELD ARCHIVIST title`, `READ`, `BACK`, `CLOSE`,
`READ NOTE`, `UNFILED`, `UNFILED DOCUMENT`, `Not recovered yet.`, `LEVEL 1/2/3`.

## Trello card text draft

> **Field Notes — a twelve-document collection across Levels 1–3**
>
> One optional discovery per round. A lit ZYNTRA document stands somewhere along a route
> the party can already walk; hold READ NOTE and it goes into a permanent collection you
> can re-read any time from the new NOTES tab on the Zyntra terminal. Recovering all
> twelve awards the cosmetic title FIELD ARCHIVIST. No tokens, no Robux, no stat effect,
> and it never blocks an exit.
>
> **Where the note goes.** The server collects the level's walkable floors, asks
> PathfindingService for a real route to fourteen of them from the spawn pad, and places
> the document at the *median* reachable one — a genuine detour, never at spawn and never
> at the exit. If a generated layout offers nothing pathable the round simply has no note
> and says so in the log; there is no retry, ever.
>
> **Reading it.** A card with the document's title, its file stamp and its text, over the
> HUD but under the Back-to-Lobby and PARTY DOWN cards. It does not take the screen: no
> movement lock, no cursor unlock, walk away mid-sentence and the note is still logged. It
> closes itself after fourteen seconds. Every player in the round can read the same
> document once.
>
> **The collection.** NOTES tab on the terminal: progress out of twelve, a track, the
> title line, and all twelve rows grouped by level — recovered ones show their title,
> stamp and opening line and tap through to the full text; the rest show the level they
> live on and NOT YET FOUND, so you always know exactly what you are missing. One column
> on a phone, two on a tablet, three on desktop.
>
> **Four notes per level**, written for the world they are found in: Level 1's circuit
> colours, relay noise, pit rooms and lost property; Level 2's pump order, skylight glazing
> log, kids-wing inventory and flume safety; Level 3's party-room booking, disc-player
> service log, a staff notice about the manager, and a cafeteria stock count. Original
> fiction, no dates, no real people or companies.
>
> Offline suite `tools/tests/test_field_notes.py` — 592 checks against the real Lua under
> the real Luau interpreter, with sixteen deliberate faults introduced and all sixteen
> caught. Studio verification still owed: real pathfinding success rates per level, the
> prop's fit against real geometry, and the rendered card and tab.

## For the lead creating these in Studio

Order matters: `ReplicatedStorage.ZyntraFieldNotes` first (the service, the client, the
page and `ZyntraMonetization` all read it), then `ZyntraFieldNotesPage`, then
`ServerScriptService.FieldNotesService`, then
`StarterPlayerScripts."Field Notes Client"`. Create through `execute_luau` +
`UpdateSourceAsync`, then add each manifest item with `sha256_of` / `canonical_bytes`
from `tools/studio_source_contract.py`. Run the compile probe afterwards.
