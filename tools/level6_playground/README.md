# Level 6: Indoor Playground Backrooms

A 90s soft-play warehouse with a hide-and-seek round against a mutated counting child.
Entered from the Level 6 queue bays in the lobby.

## The Arena (2026-10-06): the map the level uses now

One structure, wall to wall, round the post. Everything below "Pipeline" describes the hall it replaced; the
shared conventions (coordinates, `L6Slide`, anchors, the round's three searches, the Counter) still hold.

```
/Applications/Blender.app/Contents/MacOS/Blender -b --python tools/level6_playground/build_arena.py --
python3 tools/level6_playground/upload_arena_slides.py      # when Roblox allows it (see "Slide meshes")
python3 tools/level6_playground/import_arena.py             # --only <Group> | --finish | --slide-source | --nav | --dry
python3 tools/level6_playground/run_luau.py tools/level6_playground/check_nav.luau
```

The build writes `artifacts/level6-arena-20261006/` (`blend/Level6_Arena.blend`, `export/prims.json`,
`export/nav.json`, `export/slide_meshes.json`). The importer replaces `Workspace."Level 6 Indoor Playground"`
(same name and origin, so every script that looks the level up keeps working) with about 11 100 native Parts.

**Shape** (constants at the top of `build_arena.py`): a round hall of radius 156 with a roof at 150. The court
(radius 44) holds the post. Round it seven bands of cells in twelve floors of 10 studs: four floors straight up
from the court's edge, a ledge, four more, a second ledge, four more, and behind that face the frame runs solid
to the wall. Band 4 is a ring corridor on every floor. A Kruskal maze opens the cells to each other; twelve
stairwells of soft steps join the floors. Two rope-net bridges cross from the second ledge (sectors 4/16 and
10/22), 80 studs above the post. Players arrive in a padded tunnel (14 wide, 13 high, 30 long) through the hall
wall, looking straight at the PLAY ZONE gate; one lane of 112 studs runs from the gate to the court.

**The way out** (`exit_layout()` and `EXIT_*` in the build): the hole where the post stood is a funnel (three
`Arena_SlideSurfaces` panels) that tips you east into the mouth of a slide. The slide winds down three turns
(radius 14, 10 studs per turn, 284 studs in all) and comes out of the ceiling of a small padded room
(30 x 24 x 13) with a cut-back lip on the floor, clamp bands, a collar in the ceiling: the owner's picture. The
room is worn: missing pads over bare concrete, grime on every surface, one failing strip light, a steel door
with a green EXIT sign and a passage behind it. `L6_Anchor_Exit` stands in that passage; a player within
`ArenaExitRadius` (6) of it is out, which is the moment they step through the door.

**Slides carry their own direction and pace.** Every trough floor of a slide has `L6SlideDir` (which way that
stretch runs) and, where the build sets one, `L6SlideSpeed`; the client pushes a body along that way at that
pace, so a slide takes hold at its almost level mouth, and the way out eases from 40 studs/s to walking pace
over its last turn. The first three trough segments of a slide have no roof (a standing body can step in).
Four slides in the frame: orange and yellow from the second ledge to the first, blue from the first ledge to
the court, green from floor 2 to the court. All run ONE way and their mouths stand mid-sector: the build prints
each one's distance to its nearest post and stops if a post would stand in the trough.

**Slide meshes.** A slide's look is one moulded mesh (vertex colours carry the plastic, its highlights and its
dirt). `upload_arena_slides.py` turns a mesh into a group asset with `AssetService:CreateAssetAsync` and records
id and hash in `arena_slide_ids.json`. That call answers "not available yet" on some days (it worked in the
small hours of 2026-10-06 and not after Studio was restarted). A mesh without a recorded asset for exactly its
present data is therefore kept as numbers in `ServerStorage.Level6ArenaSlideSource` and built once per server
by the game module (`arenaSlides.build`, `CreateDataModelContentAsync`), the way the Counter's own mesh is. The
importer decides per mesh (`baked_names`). In Edit mode those slides are not there; they appear when a server
starts. Today orange, yellow, blue and the two pieces of the way out are built this way.

**The Counter never uses Roblox pathfinding here.** The build writes a route graph (`export/nav.json`, about
2 850 nodes and 3 450 links with their via points: cells, stair flights, the court's two rings, the lane, the
bridges) and asserts every node can be reached from the post. The importer stores it in `model.NavGraph`; the
game module's `navOf` / `navNodeAt` / `navRoute` (A* over it) give `Session:routeTo`, and `walkTo`, the chase and
the finale all travel along it. `check_nav.luau` ray-tests every link in the built level every 1.5 studs
(something solid in the way, no floor within 4 studs under it, less than 7 studs of headroom) and must print
three zeros after any change to geometry. The Counter is 8.2 studs tall: crawl tubes, nooks, the tunnel and the
room under the court are out of its reach by construction.

**Round changes for the arena** (`ARENA_20261006` in the game module, every number in `CONFIG`):
- *Arrival.* The Counter stands idle at the post until every player is through the gate (or 25 s after the
  first, 120 s at most). A player who has entered cannot walk back out through it.
- *Sight.* Outside a chase it sees a player only in front of it (`SightCos`; all round inside `CloseRange`, and
  all round while it stops to look), with nothing solid between, and a player who stands still behind netting
  further than `NetCoverRange` away is not seen. Moving behind a net is seen. Seen is still dead.
- *Search* (`HUNT_20261006`, owner). 90 s (`ArenaSeekSeconds`). It does not look in hiding places: it walks, calmly,
  toward whoever is nearest (`Session:nearestPlayer`, a straight line), keeps coming, and looks again at where
  they are now every so often. Quicker each time it counts: `ArenaHuntSpeeds` 7 / 9.5 / 12 studs a second and
  `ArenaHuntReplan` 1.6 / 1.1 / 0.7 s for searches one to three, then +1.5 a search up to 15 (a player walks
  at 16). As near as it can get without having seen them, it stops and looks all round for a moment.
- *The last minute.* The third search won: every lamp turns red, the post counts down from 60 with digits over
  it and the yellow ring on the floor going dark mark by mark (`Finale_Dial`), and the Counter hunts at
  `FinaleChaseSpeed`. At zero the lid drops, the post sinks, green light comes up (`Finale_Glow`: `Pool` over
  the hole, `Rim`, `Up`, `Down`), `Level6HatchOpen` is set and the client says GO DOWN THE HOLE, then EXIT once
  you are under the floor. `finaleReset` puts the post, the lid, the ring and the lights back.
- *Everyone down* (`TAUNT_20261006`, owner). The moment every player still standing is in the room under the
  court, the server sends `exittaunt` once and each client plays `l6_exit_taunt` from the mouth of the tube in
  the ceiling (`ExitLights.L6_ExitRoom_Tube`), with the music ducked: it screams after them, stops, and ends on
  a sweet laugh. Source: `assets/level6-exit-taunt-20261006` (ElevenLabs, the voice "Demonic child for level
  6", three takes; take 2 cleaned and levelled is `l6_exit_taunt.mp3`). Until a Sound of that name is in
  `ReplicatedStorage.Level6Counter.Voice`, `l6_angry_1` stands in.
- *The ending* (`WIN_SCREEN_20261006`, owner: "like all other maps, same screen and options"). A player through
  the green door leaves the session and is sent the round remote's own `"win"` (time, survivors, a 15 s
  deadline, no next level, a serial from 600001), so RoundUI draws LEVEL 6 CLEARED with BACK TO LOBBY, as on
  the last level of a campaign. `returntolobby` with that serial, or the deadline, sends them home
  (`releaseWinner`). When the party got out, whoever fell gets the same word ("THE OTHERS FOUND A WAY OUT").
  RoundUI names the level 6 for a player with `Level6PlaygroundPreview` (the lobby server's `SelectedLevel` is 1).
- The easter egg's button is at `L6_Anchor_PartyButton` (the floor of a dead end low in the frame); the dance is
  on the court.
- *Music* (`MUSIC_SMOOTH_20261006` in the client; owner: "the music stutters, every time for me"). The copies on
  the four nearest horns are kept in step with the wall clock by running 1.5% slower or faster for a moment;
  a copy is set once as it comes in and jumps again only if it is 0.75 s out. Before, any copy that read 0.05 s
  out was seeked, twenty times a second, which on a slow frame rate is all the time. The equaliser and pitch
  shifter sit once on a sound group per tape (`Level6MusicBus<n>`), not on every copy. Measured in Studio: no
  jumps in 18 s, copies at most 0.02 s apart.

**The look** is set by the client (`ARENA_LOOK`): exposure -0.45, saturation -0.3 and contrast -0.1 (worn
vinyl, lifted blacks), and 24 faint fill lights hung in the open well (`L6_Fill_*`), because a light's range
ends at 60 studs and the roof lamps reach nothing. In the last minute the lamps keep their spread, turn red and
swell (dark for a moment in each cycle). The exit room's three lights are in `ExitLights`, outside that.

**Weight.** Draw calls come from Texture instances, not from parts: with every texture hidden the heaviest view
(court, looking up the galleries) drew in 18 calls, with them in about 950 (the lobby: 214). The faint sheet
behind each net used to add 570 more; it is fully transparent now and only the cords show. About 16 000
textures remain. Not measured on a phone.

**Testing in Studio.** Server: stand the player on the Level 6 pad (`CFrame.new(274, 35.2, -693.2)`); Client:
`Remotes.ConfigureQueue:FireServer(121, 1, "public", "normal")`. `model:SetAttribute("Level6DevTag", true)`
scores a tag. In a play session the Server datamodel keeps a `task.spawn`ed thread alive after the call that
started it, so a whole run can be driven in the background (write progress to a workspace attribute and poll
it; a single call over about 100 s answers "Request timeout") while `screen_capture` with a camera position
shows what the client sees. Give the lighting ten seconds after a camera jump. To try the way out alone, set
`CanCollide = false` on `Finale_Lid` and `Finale_Post` and drop a body in from court level. The doll is
`model."Level 6 Counting Child"` (attributes `Anim`, `Chasing`); a body left standing in the open is caught
within a minute of the count ending.

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

**v3 look (2026-10-03):** the concept images are the target. Hero props are MeshParts in
`ReplicatedStorage.Level6PropKit` (18 Meshy models joined by `tools/level6_props/build_kit.py` and uploaded with
Studio's File > Import); the builder places them with `prop(...)` and printed panels with `board(...)`. Surfaces use
the Codex textures in `textures.json` (foam mat, vinyl, block wall, roof deck, Backrooms wallpaper, carpets, ceiling
tiles, ball sea, menu boards, prize wall, mural), tinted with the part colour. Ambient and Fog have no visible effect
under this place's Realistic lighting, and the lobby's Atmosphere blacks the hall out if it is left on: the dusty
grey air is ExposureCompensation 0.4 plus a ColorCorrection with Contrast -0.17, set by the client script.
Review shots are in `artifacts/level6-playground-20261002/review-v3/`. To review silently, set
`Level6PlaygroundPreview` on the player from the server instead of queueing (no round, no voice), move the character
to each viewpoint so the area streams in, and capture Studio's window with `screencapture -l <id>`.

**v4 (2026-10-03, afternoon):** signs are printed artwork (Codex, `artifacts/.../signs_v1`, keys `sign_*` in
`textures.json`; `SIGN_ART` in the builder maps a sign's first words to its image and fixes the aspect). Slide tubes
are the kit's hollow `tube_segment` mesh, scaled per segment, with a tinted SurfaceAppearance. `pa_speaker` horns hang
under the roof; the client plays every voice line from the doll and from the five nearest horns. The round needs three
tags on the post (`TagsToWin`), shows an objective card and a see-through marker (model attributes `HomePosition` /
`ExitPosition`), and on the last tag the server sets `Level6Enraged` on the model: the client turns every light deep
red and the doll chases at 24. Angry lines `l6_angry_1..3` are picked when they exist in `Level6Counter.Voice`; until
then the exit lines stand in. The doll is avatar height (`STUDS_PER_METRE = 4.5` in `tools/level6_entity`).

**Release (2026-10-03, evening):** Level 6 is open to every player. `release_level6.py` holds the exact edits
(`DevAccess.IsLevel6Allowed`, GameManager's bay gate and station subtitle, Level6PreviewAccess, DevBayAccessGuard,
R4DevGateController, Level6PreviewTransport, Level4PreviewPrompt); Level 5 stays developer-only. Sources before the
change: `artifacts/level6-release-20261003/before/`. The doll is 8.2 studs (`STUDS_PER_METRE = 6.3`), the frame
entrances were raised for it, and it stands next to hide spots it cannot enter (walkTo offsets). Footsteps, doll steps,
spotted sting, catch, tag chime and room tone are ElevenLabs sounds in `assets/level6-sfx-elevenlabs/` (generated by
Codex through its ElevenLabs MCP), stored with the voice lines in `ReplicatedStorage.Level6Counter.Voice`. The game
module dresses the lobby's Level 6 queue bay at run time (`dressLobbyBay`). Setting `Level6DevTag` on the map model
scores a tag in Studio only, for playing the finale through in a test.

## Round (`ServerScriptService."Level 6 Systems"."Level 6 Playground Game"`)

`Level6PreviewAccess` calls `AddPlayer`/`RemovePlayer` and supplies the return-to-lobby handler.

1. The child stands at Home Base, covers its eyes and counts to 20 (a faster recording each round).
2. It then walks to hide spots (nearer ones first), pauses to look, investigates running players and chases
   anyone it can see. A player inside a hide spot is only spotted within 6 studs, or when moving fast nearby.
3. While it is 22+ studs from home, a player touching the post scores a dunk (once per player per round).
   The round ends after 75 s or when everyone has dunked, and it goes back to count.
4. Dunks needed: 2 per player, clamped to 3..8. Then the exit by the arcade opens (green beacon) and the
   child chases at full speed; reaching it sets `Level6PlaygroundCleared` and returns the player to the lobby.
5. Caught players are returned to the lobby; if everyone is caught the party has lost. The session resets
   when the last player leaves.

The child is The Counter, a rigged doll with ten clips and 38 recorded lines: `tools/level6_entity/README.md`.
Count times are the recordings' lengths (22.9, 21.2, 19.2, 15.9 s). It walks at 9, chases at 20, and stops
for 0.9 s to point and speak when it first sees someone. Level 6 plays no sound borrowed from another level:
only the recorded voice (3D, from the doll) and a dunk ping; the lobby music group is muted while inside.
Chase and catch stings are still to be made.

Textures: the net is the public Creator Store decal 81104945973317 (image 82491821601855). The floor seams,
padding and grime overlays are the user's own uploads; a group-owned experience may only use them after
"Share access" (Output: click the "doesn't have access permission ... Click to share access" line, then
Share access). That was done for this universe on 2026-10-03. New uploads need it again.

Multiplayer tests: toolbar mode "Server & Clients". `DevAccess.IsLevel6PreviewAllowed` admits Studio test
players (negative UserIds, Studio only) so they can use the dev-only queue bays.

Client: `StarterPlayerScripts."Level 6 Playground Client"` (HUD, night lighting while
`Level6PlaygroundPreview` is set, slide ride, the child's limb animation). RoundUI stands down while the
client-local attribute `Level6PlaygroundLightingOwned` is true.
