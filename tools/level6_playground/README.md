# Level 6: Indoor Playground Backrooms

A 90s soft-play warehouse with a hide-and-seek round against a mutated counting child.
Developer preview only, entered from the Level 6 queue bays in the R4 lobby (or the old lobby's
`Level6SealedDoor`).

## Pipeline (run from the repo root, Studio open on the place)

1. `Blender -b --python tools/level6_playground/build_playground.py -- [--render]`
   builds the map from `SEED` (studs, Z up) into `artifacts/level6-playground-20261002/blend/`, and writes
   every primitive to `export/prims.json`. `--render` adds the previews in `renders/`.
2. `python3 tools/level6_playground/make_textures.py` writes the overlay PNGs. They are uploaded with the
   Studio MCP `upload_image` tool (serve the folder on localhost); the ids live in `textures.json`.
3. `python3 tools/level6_playground/import_to_studio.py` replaces `Workspace."Level 6 Indoor Playground"`
   with native Parts (about 14.8k), textures, signs, lights, anchors and the `Level6Exit` landing.
   It talks to Studio through `StudioMCP` directly, so the geometry never passes through a chat.
4. `python3 tools/level6_playground/push_scripts.py` writes `studio/*.lua` into Studio with
   `UpdateSourceAsync`. The MCP sandbox cannot create scripts, so the two scripts took over obsolete ones
   from the retired Level 3 copy (`Level 6 Preview Runtime`, `Level 6 CD Dev ESP`); their old source is in
   `artifacts/level6-playground-20261002/studio-before/`.

## Map

**v2 (2026-10-03): one hall, nine fixed zones**, following `artifacts/level6-playground-20261002/concepts/10_map_overview.png`:
Reception (south-west, entrance and spawn), Snack Shack with picnic tables (west wall), Party Rooms (north-west
block with its own ceiling), Arcade and Prizes (north wall), Staff Only (north-east Backrooms corridors, the
emergency exit is inside), The Big Frame (12 x 14 cells, three storeys), Ball Ocean (south of the frame, about 100
balls only), Toddler Town, Inflatables (east) and Home Base in the middle. Stairs, passages and zone props are
authored by hand; the frame maze and staff corridors use fixed seeds. Signs are listed in the build script. The
earlier single-hall build is `build_playground_v1_single_hall.py`. The notes below describe shared conventions.

- Hall 600 x 400 x 60 studs at Studio X = 52000 (Blender (x, y, z) -> Roblox (x - 300 + 52000, z + 100, 200 - y)).
- Play frame 22 x 26 cells of 12 studs, three storeys (decks at 10 and 20), 18 soft-step flights, a maze per
  storey with every cell reachable. `PASSAGES` in the build script opens the bays where slides, crawl tubes and
  the net bridge are entered.
- Slides: tube slides are a non-colliding shell around an invisible trough (`TubeFloor` + `TubeWall`); the
  wave slide lanes are thick ramps. Riding surfaces carry the attribute `L6Slide`, which the client turns into
  downhill speed.
- 120 hide spots (`Anchors/L6_Hide_<kind>_<n>`, attribute `HideKind`), `L6_Anchor_HomeBase`, `L6_Anchor_Exit`.

## Round (`ServerScriptService."Level 6 Systems"."Level 6 Playground Game"`)

`Level6PreviewAccess` calls `AddPlayer`/`RemovePlayer` and supplies the return-to-lobby handler.

1. The child stands at Home Base and counts to 20 (20, 16, 13 then 10 seconds per round).
2. It then walks to hide spots (nearer ones first), pauses to look, investigates running players and chases
   anyone it can see. A player inside a hide spot is only spotted within 6 studs, or when moving fast nearby.
3. While it is 22+ studs from home, a player touching the post scores a dunk (once per player per round).
   The round ends after 75 s or when everyone has dunked, and it goes back to count.
4. Dunks needed: 2 per player, clamped to 3..8. Then the exit by the arcade opens (green beacon) and the
   child chases at full speed; reaching it sets `Level6PlaygroundCleared` and returns the player to the lobby.
5. Caught players are returned to the lobby; if everyone is caught the party has lost. The session resets
   when the last player leaves.

Audio: the child's voice is `AudioTextToSpeech` on each client (VoiceId 1, pitched up). Roblox's text filter
rejects long runs of numbers and every utterance costs one request (budget 1 + 6 x players per minute), so it
says the count in four short bursts (1-5, 6-10, 13-15, 19-20), then "Ready or not. Here I come!" and "Found
you!". Stings reuse SoundController's ids (spot, chase, jumpscare, death, alert, hum).

Textures: the net is the public Creator Store decal 81104945973317 (image 82491821601855). The floor seams,
padding and grime overlays are the user's own uploads; a group-owned experience may only use them after
"Share access" (Output: click the "doesn't have access permission ... Click to share access" line, then
Share access). That was done for this universe on 2026-10-03. New uploads need it again.

Multiplayer tests: toolbar mode "Server & Clients". `DevAccess.IsLevel6PreviewAllowed` admits Studio test
players (negative UserIds, Studio only) so they can use the dev-only queue bays.

Client: `StarterPlayerScripts."Level 6 Playground Client"` (HUD, night lighting while
`Level6PlaygroundPreview` is set, slide ride, the child's limb animation). RoundUI stands down while the
client-local attribute `Level6PlaygroundLightingOwned` is true.
