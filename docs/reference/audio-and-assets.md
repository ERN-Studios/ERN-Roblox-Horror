# Historical reference: audio-and-assets

Read only the section needed for the current task. This is retained history, not current startup policy.
CLAUDE.md and AGENTS.md supersede old model, ownership, testing and sync commands below.
Never automatically import this file into startup context. Dates and environment limitations may be obsolete.

### Added 2026-10-04 (late evening) - lobby ends, spawn view, new store artwork

- **DJ end** (`INFINITE_END_20261004` in Builder, folder `InfiniteTunnelEnd`): a metal fence wall to wall 7.6 studs
  in front of the end wall (behind the stage; `FenceCollision` is the invisible 30-stud sheet that stops a body),
  three yellow signs "WARNING / UNSTABLE AFTER THIS POINT / STAY BEHIND THIS FENCE", and `TunnelBeyond`: one flat
  part on the wall that shows `assets/lobby-infinite-tunnel-20261004/lobby_tunnel_infinite.png` once its asset id
  is put in `IMAGE` (empty = a dark wall). The picture is the real tunnel photographed in play from 40 studs in
  front of the wall at eye height (y 39), stage/signs/bay dressing hidden client-side, `FogEnd` 215 in black,
  cropped to the wall's cross-section with two magenta corner marks found in the screenshot's BMP.
- **Spawn end** (`ARRIVAL_GATE_20261004`, folder `ArrivalGate`): a two-leaf blast door 26 x 22 studs in a heavy
  frame on the end wall behind the spawn, "ZYNTRA - ARRIVAL GATE" over it, and the whole wall under one
  ForceField sheet in the store's teal (73, 245, 204) with a faint SurfaceLight. Nothing collides.
- **Spawn view** (`SPAWN_VIEW_20261004` in First Entry Guide): on every lobby spawn the default camera is turned
  to look from the spawn toward the lobby centre (the DJ end). `GameManager.scatterAt` already faces the body
  that way (`facing = math.pi`).
- **Publishing works without bringing Studio to the front**: the System Events click on File > Publish to Roblox
  goes through while another app is in front (and hangs if preceded by `activate` when Studio is on another
  Space). `screencapture` cannot see Studio when it is on another Space; CGWindowList lists no window for it.
- **Discord attachments without the GUI**: Discord's cache (`~/Library/Application Support/discord/Cache/
  Cache_Data`) holds the signed CDN URLs (`ex`, `is`, `hm`) of every attachment the app has shown; the attachment
  id is a snowflake, so its upload time is `(id >> 22) + 1420070400000` ms. Curl the `cdn.discordapp.com` URL.
- **Store artwork v2**: `~/Desktop/Backrooms Stay Quiet - Covers 2026-10-04` (16 thumbnails 1920x1080, 4 icons
  1024, Krille's 35 in-game references of 2026-10-04, prompts). The earlier Desktop gallery was moved to
  `artifacts/gallery-20261004/old-desktop-gallery`.
- **No briefings anywhere** (`BRIEFINGS_OFF_20261004`, owner): `lobbyBriefing.playOnce`, `playLevelOneBriefing`,
  `playLevelTwoBriefing` and `levelThreeBriefing.play` in RoundUI return
  at once (Level 4's three opening caption lines were switched off too and put back the same day on the owner's word: they stay) (`do return end`; RoundUI has no room for a new local). Level 1's objectives are made available before
  that return. The code, sounds and cue tables are left in place. RoundUI and Level 4 Round Client in the repo
  were brought level with Studio for this edit (they carried another session's changes).
- **Arrival gate nameplate**: 19 x 2.1 studs, text sized in pixels (`TextScaled` off), lamps at the lintel's ends.
- **Tutorial and Help** (`TUTORIAL_20261004`, `HELP_20261004` in First Entry Guide): four pages (THE GAME, HOW YOU
  PLAY, PLAY TOGETHER, RESEARCH TOKENS) for a first login, SKIP on every page; a HELP button under BADGES on the
  left rail opens ten topics and PLAY THE TUTORIAL. Token numbers are read from ZyntraConfig. Test hooks (client
  attributes, no input device needed): `PlayerGui.WelcomeCard:SetAttribute("Page", n)` (0 closes),
  `PlayerGui.HelpButton:SetAttribute("Toggle", x)`, `PlayerGui.HelpPanel:SetAttribute("Topic", n)`; set
  `workspace.DevShowWelcome` on the CLIENT within the first seconds of play. VirtualInputManager is not
  available to `execute_luau`.
- **Level loading cover** (`LEVEL_LOADING_20261004`, the block at the end of `ReplicatedFirst."Lobby Loading
  Screen"`; push with `tools/push_loading_screen.py`): the lobby cover's layout in each level's colours (`LEVELS`:
  1 amber, 2 cyan, 3 orange, 4 magenta, 5 rose, 6 yellow; 0 = level not known yet). ROUNDS: it stands over
  RoundUI's `RoundGui.LevelLoading` for as long as that is visible (RoundUI publishes the client attribute
  `LoadingLevel` on the `loading` event), then one bounded fetch (2.5 s) and a quiet-queue wait (1.5 s); on a
  reserved round server it is up from the first frame. LIVE levels 5 and 6: raised on the rising edge of
  `Level6PlaygroundPreview` (`Level5VoidRound` picks 5), held for body in the level, model settled, ground under
  the feet, the level's assets (cap 8 s) and a quiet queue. Client attribute `LevelLoadingOpen`; it prints
  `[LevelLoading] level N covered for X s`. Measured in Studio: Level 6 9.9 s on a cold cache, Level 1 16.2 s.
  The level's game does not wait for it (the Level 6 doll starts counting behind the cover).
- **GitHub, 2026-10-04 (owner: "Studio is source of truth; get everything in Studio in as main, and all local files
  into the repo too")**: the local history and GitHub's `main` had no commit in common (131 local, 264 remote).
  The remote `main` as it was is kept as the branch `backup/main-before-2026-10-04`; local `main` (every Studio
  script pulled with `mac_pull_from_studio.py`, every local file, `.gitignore` = both sides of an old unfinished
  merge) was then pushed over `main`. Pushes of this repo need `http.postBuffer` 1048576000 and HTTP/1.1.
- **Lobby backdrop image** is uploaded: `rbxassetid://89904369379943` (`IMAGE` in `INFINITE_END_20261004`).

### Added 2026-10-05 (night) - Level 6 concept v3: a draft in pictures, nothing built

- **Owner's brief**: a new revision of the Level 6 map. Remove the arcade, make the hall bigger, make the Big Frame
  (the soft-play structure; the owner calls it "the play area between the net fences") a far larger share of the map
  "so you almost have to hide in there", and make the roof far higher with the frame correspondingly taller.
- **The draft** (numbers live in `NEW` in `tools/level6_playground/concept_v3/draw_plan.py`): hall 600 x 400 ->
  864 x 576 studs, roof 46 -> 120, frame 10% -> 47% of the floor (main block plus a wing on the arcade's wall), 6 floors
  everywhere, 7 in Tube Town, 10 in the Tower, Home Base as a round court inside the frame, the Ball Ocean sunk inside
  it, three gates and dog-legged lanes wide enough for the Counter. Arcade and Prizes go; the other zones stay round
  the edge.
- **Where it is**: `~/Desktop/Level 6 nyt koncept` (16 pictures, a contact sheet, a README); sources, prompts and every
  raw generation in `artifacts/level6-concept-20261005/`. `draw_plan.py` draws the three to-scale sheets (plan,
  today/new, heights) with headless Chrome; `assemble.py` rebuilds the Desktop folder.
- **Nothing in Studio or in `build_playground.py` changed.** A build waits for the owner's yes, and for three answers:
  does the Counter climb (six to ten floors are out of its reach otherwise), is the 20 s count still right in a hall
  twice the size, and the frame has to become joined meshes (about twenty times today's cells is too many loose parts).
  The easter egg's party button sits on the arcade carpet and needs a new place when the arcade goes.
- **Image generation**: four `codex exec` jobs in parallel (built-in image tool, at most five reference paths each)
  made 14 views in about twelve minutes. Giving it a to-scale drawing as a reference is what made the map picture
  follow the layout; it still understates height unless told how much of the picture the empty air must fill.

### Added 2026-10-06 - Level 6 concept v4, "the Arena" (supersedes concept v3; still pictures only)

- **Owner, after seeing v3**: "brilliant, but I want something else". The whole map is to be the structure: drop every
  other area, the post and the Counter in the middle, "a fuck ton" of structure all the way round and high up "so you
  can look down on the post if you're high up", players spawn in a small hole in the wall (a little tunnel) right in
  front of the PLAY ZONE sign and walk in, where the intro starts. They also asked for ideas for the escape after
  the third touch, and for the old concept folder to be deleted and a new one made.
- **The draft** (constants at the top of `tools/level6_playground/concept_v4/draw_arena.py`): a ROUND hall 548 studs
  across, roof 150; court radius 44 with the post; six rings of frame 38 studs deep, each two floors taller than the one
  in front (2, 4, 6, 8, 10, 12 floors: "the bowl"), every ring's top a terrace; eight stair aisles wide enough for the
  Counter; a spawn tunnel 12 x 8 through the wall (the Counter is 8.2 tall and does not fit), the PLAY ZONE gate, one
  straight lane of 228 studs to the court. The frame is 95% of the floor, about 13 200 cells against today's 504.
- **Why the rings step**: a terrace's front edge sees the post at floor level only if no ring is deeper than the
  court's radius (the sight line from ring n clears ring n-1 by `R(court - depth) + eye * ...`, independent of the rise).
  With twelve floors straight up from the court ("the well", drawn as the alternative, 43% more structure) only the
  inner galleries see it.
- **Four ways out drawn as ideas**: A the big slide from the top terrace out through the wall (recommended), B back
  through the gate and tunnel, C a chute under the post, D one of four fire doors high in the wall.
- **Where it is**: `~/Desktop/Level 6 nyt koncept` was deleted and rebuilt by `concept_v4/assemble.py` (16 pictures, a
  sheet, a README); sources and prompts in `artifacts/level6-concept-20261006/`. The v3 pictures remain in
  `artifacts/level6-concept-20261005/`.
- **Still nothing built.** Open with the owner: bowl or well, which way out, and the Counter's sight rule on open
  terraces ("seen = dead" would reach half the level from the post). A build would be one 45-degree slice of joined
  meshes repeated eight times, measured on a phone before the rest.
- **Image generation**: the model keeps drawing a vertical wall of galleries for "terraces stepping back"; the views
  from above came out right at once, the views from the court needed a retry with an already-correct picture passed
  as the geometry reference. Codex copies its generations into `raw/` only at the end of a job; while it runs they
  sit in `~/.codex/generated_images/<session>/`.

### Added 2026-10-06 (later) - Level 6 concept v5: tall walls, and the way out is under the post (pictures only)

- **Owner on v4**: "I like that but don't make the structure look like a circle staircase that much." They picked two
  of the generated pictures as the look for the main area and asked for a blend: the gallery looking down on the court
  (v4 picture 09, `refs/owner_ref.png`) and the twelve floors standing straight up round it (v4 picture 16,
  `refs/tall_walls.png`). So v4's six stepped rings ("the bowl") are out.
- **The escape is decided** (owner): the third touch makes the post start a countdown of about a minute; then the post
  goes down into the ground "to a green exit light where the players have to go down to and escape". The other three
  ideas from v4 (big slide, back through the gate, fire door) are dropped.
- **The draft** (constants at the top of `tools/level6_playground/concept_v5/draw_arena.py`): same round hall (548
  across, roof 150, court radius 44, tunnel + PLAY ZONE gate + one straight lane of 228 studs). `TIERS`: four floors
  straight up from the court's edge, a 16-stud ledge, four more, a 16-stud ledge, then twelve floors solid to the wall.
  `numbers()` works out which gallery floors see the foot of the post over the ledge in front: 1-4, 7-8, 11-12.
  Two ring corridors (r 118 and 196), staggered spokes and stair cores are the Counter's ways on every floor.
  Under the post: a shaft 10 across and 30 deep with a slide winding round the sinking post, an exit room 14 high
  (too low for the Counter), a green EXIT door. `COUNTDOWN` 60; the floor ring is a 60-segment clock so the galleries
  can read it. About 18 400 cells (v4's bowl: 13 200; today: 504).
- **Where it is**: `~/Desktop/Level 6 nyt koncept` rebuilt by `concept_v5/assemble.py` (16 pictures, sheet, README; it
  reuses four v4 pictures the new shape does not change); sources in `artifacts/level6-concept-20261006b/`.
- **Still nothing built.** My own choices in the draft, not the owner's: the clock on the floor, the hole staying open
  until everyone standing is out or caught, the post going down the middle of the slide. Still open: the Counter's
  sight rule, and the size (one slice first, measured on a phone; narrow the hall rather than lower it).
- **zsh aborts a whole `&&` chain when a glob matches nothing** (`rm -f /tmp/x_*.txt` with no such file: "no matches
  found"), so the jobs after it never started. Name the files, or `setopt nonomatch`.


### Added 2026-10-06 (later in the morning) - Level 6: calm hunt, standard ending, the line in the exit room, music

- **Owner**: Level 6 must complete "like all other maps with the same screen and options"; "the music stutters ...
  it happens for me every time"; each round the Counter is to pathfind calmly toward the nearest player, its
  pathfinding and walk speed quicker every round; and the second everyone is down in the exit room, a furious
  ElevenLabs line in the Level 6 voice that ends in a sweet laugh.
- **What changed** is in `tools/level6_playground/README.md` ("Round changes for the arena": Search, Everyone down,
  The ending, Music). Markers: `HUNT_20261006`, `WIN_SCREEN_20261006`, `TAUNT_20261006` in the game module,
  `MUSIC_SMOOTH_20261006` in the client. RoundUI got one expression (the level's number).
- **Tested in Studio, solo**: searches walked at 7, 9.5 and 12 toward the player; the ending drew LEVEL 6 CLEARED,
  TIME, SURVIVORS 1/1, the countdown and BACK TO LOBBY, and the deadline sent the player home; `exittaunt` fired
  on arrival in the room; music 0 jumps in 18 s. **Not tested**: the button's own message (the deadline came first;
  it is the same word and serial RoundUI sends for every level), the line itself in the game (not uploaded when
  this was written), several players.
- **A second `local` further down a script is not in scope above it**: `lifeWatch` was declared 400 lines below
  the finale that began to use it, where it would have read as a nil global. Moved to the top.
- **Codex commits what it writes** (`b74f047`, the three takes) even when told to touch nothing else; check
  `git log` after a Codex job.
- **Measuring something that moves from `execute_luau`**: count real elapsed time between samples, not the number
  of samples (a slow server tick made 9.5 studs/s read as 17.7). The doll publishes its own `Speed` attribute.
- **Published state**: the owner published the arena themselves at 08:38 on 2026-10-06 (v2739, in Studio's log:
  "Published new changes"). `game.PlaceVersion` in an edit session keeps the number the place was opened at
  (it still said 2724), so read the log, not that. Everything in this section came AFTER v2739 and is in Studio
  (Team Create) but was NOT published when the session ended.
- **`l6_exit_taunt` is in**: the owner imported it through the Asset Manager (group asset 128590836842587, 19.0 s);
  a Sound of that name with `Seconds` 19 is in `ReplicatedStorage.Level6Counter.Voice`, and it loaded and played on
  a client in Studio. Not heard in the exit room itself yet (the trigger was tested with the stand-in line), and
  not published when this was written.
- **Codex computer use failed four times on Studio this morning**, each for a new reason: it took the window of a
  Studio process that had lost its place the night before (an old "Unable to Connect, RCC-275" dialog), then a
  second empty Studio ("Low System Resources"), then the Asset Manager stayed blank (Studio at 6.3 GB on an 8 GB
  Mac), then "two installed app paths share its identifier". Before sending it in: only ONE Studio process (the
  stale ones answer "Place is not open" to the MCP and can be closed), and expect it not to work. It also launched
  a Studio of its own once. `osascript ... set frontmost` still works without the accessibility permission;
  clicking a menu does not.

### Added 2026-10-07 (evening) - Promo pictures: 12 gallery, 6 thumbnails, 25 ads (nothing in Studio changed)

- **Owner**: playtest every level, understand each entity and how each level is cleared, then a batch for the
  gallery, the thumbnail and 25 for an ad campaign; Codex makes the pictures, Claude is the QA; Level 2 is the NEW
  map (no entity). Result: `~/Desktop/Backrooms Stay Quiet - Promo 2026-10-07` (43 pictures, each with lettering
  and clean; README; `ANALYSIS - the six levels.txt`). Sources: `artifacts/promo-20261007` (42 in-game references,
  briefs, all 68 generations; `final/` is ignored there, it is rebuilt) and `tools/promo`.
- **How**: `tools/promo/make_briefs.py` holds every picture (references, scene, tagline) and writes one brief per
  Codex job; seven `codex exec` jobs side by side made 68 generations in about 25 minutes; `tools/promo/finish.py`
  crops to exact size and sets ALL lettering (DIN Condensed), so nothing is misspelled. Codex is told to draw no
  lettering at all. `accept.json` carries QA's per-picture decisions. The only Pillow on this Mac is the venv in
  `~/Desktop/Backrooms Stay Quiet - Covers 2026-10-04/.artwork-venv`.
- **What things really look like** (the covers of 2026-10-04 had three of these wrong):
  the PLAYER is a chunky hooded mustard hazmat figure with a black TWIN-LENS GAS MASK and a black backpack with
  two olive tanks (not "a dark visor"); the MALL MANAGER is tall and thin with a RED BALLOON for a head, an
  orange-and-cream striped shirt with a name tag and red gloves; the USHER wears a crimson bellhop uniform with
  gold buttons and a pillbox cap, has a glossy BLACK faceless head and glowing WHITE gloves (not a pale pink
  figure); the COUNTER wears a striped paper party hat.
- **The new Level 2** is `Workspace."Level 2 Poolrooms New (preview)"` (origin 70000, 300, 0; about 32 000 parts;
  attribute `Route = "P0 A1 P1 A3 P2 A4 P3 A2 P4 A5 P5 A6 EXIT"`; markers `A<n>_<nn>`, `P<n>_<nn>`, `EXIT`), entered
  by developers from `Level2NewMapPreviewEntry` in the lobby's Level 2 bay (`Level2BlenderPreviewAccess`). Six
  areas, no entity, no round. The public Level 2 queue (105) still starts the old round: the README of the promo
  folder says to hold the Level 2 pictures until the new map is what players get.
- **Two entities are not in their level when a round starts.** The Mall Manager only exists once
  `Level3MallManagerHuntActive` is true (the blackout); the Usher is `Dormant` at (0, -600, 0) until the power is
  on, and the Level 4 round STARTS with the power off (black, red emergency light). For a look at them: clone
  `ServerStorage.Level3Assets.EntityTemplates.MallManagerTemplate` (Server) or
  `ReplicatedStorage."Level 4 Usher Visual"` (Client; that is what the client draws) into the level, anchored.
  Both stand in a stiff rig pose without their animations.
- **Taking pictures in a play session.** A `BindToRenderStep` at `Camera.Value + 5` that reads a CFrame from a
  workspace attribute parks the camera; a `RunService.PreRender` connection that disables every ScreenGui hides
  the HUD (ProtectionHUD turns itself back on after the render step, so the render step alone is not enough).
  The body turns its back to a Scriptable camera: `Humanoid.AutoRotate = false`, then `PivotTo` facing it.
  `player.ReplicationFocus = <part>` (Server) streams the place round a far entity in, so a camera that follows
  `Workspace.Entity` 400 studs from the body shows a lit maze. Queue ids: 101, 105, 109, 113, 117, 121 for
  Levels 1 to 6. Put `QualityLevel` back to `Automatic` afterwards (it was).
- **Codex's ElevenLabs connector fails to refresh its login** (`failed to refresh OAuth tokens for server
  ElevenLabs` at the top of every job's log). Harmless for pictures; an audio job will need the owner to sign in.
- **Played on this run / not played**: every level was entered as a real round or session and photographed;
  the Level 1 fuse run, the Level 3 CDs and blackout and the Level 4 breaker puzzle were NOT played tonight (the
  analysis says so per level and names the earlier runs it leans on).

### Added 2026-10-08 - Ten game icons (pictures only; the icon on Roblox was NOT changed)

- **Owner**: "Create 10 new icons". They are in `~/Desktop/Backrooms Stay Quiet - Promo 2026-10-07/4 Icons
  (1024x1024)` (and at 512 x 512 in its subfolder), with a sheet at 150 and 64 pixels in `contact sheets`.
  I01 shh with the Entity in both lenses, I02 Entity behind a player, I03 Entity round a corner, I04 half player
  half Entity, I05 Mall Manager, I06 Usher, I07 Counter peeking, I08 four players under a hand's shadow, I09 void
  jump, I10 alone in the new poolrooms. Recommended: I01, tested against I03. None is uploaded.
- **Same pipeline, one more set**: `make_briefs.py` has the set `icon` (jobs H, I, K; its `SPACE` line tells Codex
  what an icon needs: one subject, big shapes, readable at 64, everything inside the middle 80 percent), and
  `finish.py --only icon` writes 1024 and 512 without lettering. `--only <set>` rebuilds one set and leaves the
  other folders alone. Three `codex exec` jobs made 16 generations in about eight minutes.
- **The generator's square size is 1024 x 1024**, so the icons are at native size (the 1920 x 1080 pictures are
  enlargements of 1536 x 1024).

### Added 2026-10-08 (night) - Ads Manager: library replaced, first campaign submitted (LIVE, spends ad credit)

- **Owner**: "create a great ads campaign, we have 57 ads credits, maximize reach and click rate, upload the best
  pictures", then "archive all existing assets and upload all the new ads assets". Done from the session.
- **Asset library** (`create.roblox.com/advertise/creative-library`): the 27 old assets are archived (they can be
  brought back), 31 new ones are in and approved: the 25 ad pictures and the 6 title thumbnails. Square and
  vertical ads are there because they were asked for; Roblox's only ad placement is the 16:9 tile.
- **Campaign** `4f4b9c87-81b9-468b-8967-7c415489a63c`, "Stay Quiet | Plays | Oct 8-13 | 6 creatives": objective
  Plays, all players, all ages/devices/regions, LIFETIME budget 57 credits over 5 days from 2026-10-08 01:30
  local, paid from the GROUP's ad credit, auto-reload off, no card on file (so 57 is the most it can spend; 0.46
  stays). Pictures: A01 run, T01 hide, T04 shh, A03 table check, T03 Counter, T05 Usher. Six and not ten because
  a campaign shows its pictures in EVEN shares: a weak one costs as much as a strong one. No Level 2 picture is
  in it (the new map is not what players get yet). Record: `artifacts/promo-20261007/ads-campaign.json`.
- **To do after about two days**: read the results per picture and take the weak ones out.
- **`tools/promo/ads.py`** has the calls and `status`. Facts that cost time: the Ads Manager draws NOTHING while
  its tab is in the background (so only its API is usable from a session); "archive" in the library is the
  DELETE call (a PATCH to `is_archived: true` is refused, 400); a campaign is created AND submitted by one POST
  to `/v3/native/campaigns`; the real minimum daily budget is 0.95 credits (`/v1/metadata`), not the 10 in the
  page's defaults; Roblox's own suggestion for this game was 12 to 20 a day; the "No payment method on file"
  banner did not stop a campaign paid from ad credit. `dashboard.py` now takes any tab (`dashboard.TAB`), and
  its `call` keeps ONE answer slot in the page: never run two jobs through the same tab at once.
- Roblox says review takes up to 24 hours; the review state itself could not be read from the session (the
  list query's enum values were not found). The owner sees it under Manage ads.

### Added 2026-10-08 (night, later) - Ads: daily budget of 11, no square or vertical assets (LIVE)

- **Owner**: "do not have squared and vertical ads pushed as they would be stretched", and "run the ad with 11
  credits a day". The 16 square and vertical pictures are archived in the asset library (15 are left, all
  1920 x 1080; none of the 16 was ever in a campaign).
- **The campaign that runs is `fc071f73-178a-491c-8257-c8be9e222e3c`**, "Stay Quiet | Plays | 11 a day | 6
  creatives": DAILY budget 11 for 5 days from 2026-10-08 01:30 local (55 in all; about 2.46 credits stay), same
  six pictures, everyone, group ad credit, auto-reload off. The first one (`4f4b9c87...`, lifetime 57) is
  SWITCHED OFF and never delivered: do not switch it on again, the two together would spend twice as fast.
- **Why two**: the budget type of an existing campaign cannot be changed, and Roblox refuses to cancel a
  campaign within 6 hours of its start ("CAMPAIGN_INELIGIBLE_FOR_UPDATE"). Switching off (`status: 3`) works at
  any time. `ads.py` has `states`, `switch` and the status numbers; its `status` lists both campaigns.
- Chrome answered one request with "Connection is invalid (-609)" while a prompt was up on the owner's screen;
  after a failed call, READ the state before sending the request again (the cancel had not gone through).

### Added 2026-10-08 (night) - The game's public name became "(UPDATE) BACKROOMS: BE QUIET" (superseded 35 minutes later, see below)

- **Owner**: "Change our game name to just BACKROOMS: Be quiet, remove the co-op horror part and add (UPDATE) to
  the start", then "with all caps". Was `BACKROOMS: STAY QUIET [CO-OP HORROR]`. Changed through the dashboard's own
  call (`PATCH develop.roblox.com/v2/places/<start place>` with name and the unchanged description;
  `store_pictures.rename`); place, experience and public page all read the new name three seconds later. The old
  name and the description are in `artifacts/promo-20261007/store-upload.json` (`name`).
- **Not changed, and now out of step with the name**: every title thumbnail and ad picture still says STAY QUIET
  and CO-OP HORROR (on the store page, the Home tile and in the running ad campaign); the description still has
  "1-6 PLAYER CO-OP HORROR"; in-game text was not touched. The owner was told; re-lettering is one run of
  `finish.py` after the wording in it is changed, plus a re-upload.
- This file's own heading and the repo's folder names keep the old name.

### Added 2026-10-08 (night, later) - The game's public name is "(UPDATE) BACKROOMS: STAY QUIET" (live)

- **Owner**, after asking for other name ideas and weighing them ("We will just keep be quite"), then: "Change to
  (UPDATE)BACKROOOMS: STAY QUIET". Set at 01:45 with `store_pictures.rename` (typed with a space after "(UPDATE)"
  and BACKROOMS spelled right); place and public page both read it six seconds later. `store-upload.json`'s `name`
  holds the name before all of this, the BE QUIET one under `history`, and the description, which was never changed.
- **In step again**: the thumbnails, the Home tile and the running ads say STAY QUIET, as the name does. Still on
  them and no longer in the name: the small "CO-OP HORROR" line. The description still has "1-6 PLAYER CO-OP HORROR".
- **The owner's "slip" is Danish** ("drop it"), not the English word: "Slip STAY QUIET" was first read as "BE QUIET
  was a slip". Nothing was changed on that reading; when a short message can be read both ways, ask before a
  public change.

### Added 2026-10-08 (midday, later) - The Reach has sounds (in Studio, NOT published)

- **Owner**: "give the lobby monster sounds behind the fence. Use ElevenLabs and remember to sound engineer the AI
  static out." Fourteen sounds of its own (wake x2, a breathing loop, a crawl loop per hand, windup x2, slam x2,
  grab, a drag loop, kill x2, retreat x2). What plays when: `tools/lobby_reach/README.md` ("The sounds"). How they
  were made, which takes were thrown out and what the cleaning measured: `assets/lobby-reach-20261008/README.md`.
  Marker `REACH_SOUNDS_20261008`, the last block of `Lobby Tunnel Reach Client`.
- **Audio can be uploaded from a session, no Asset Manager and no hands**: `tools/lobby_reach/upload_sounds.py`
  posts each file as an `Audio` asset of the group through the owner's signed-in Creator Dashboard tab (the icon
  upload's endpoint, `assetType: "Audio"`; `dashboard.stage` takes mp3/ogg/wav now). The experience can use them
  without any "share access" step. Review took minutes; meanwhile a sound fails with "Asset has not been
  reviewed". The tab was gone when needed: `tell window 1 to make new tab` and put `active tab index` back keeps
  the owner's tab showing, but Chrome still came to the front once (it was put back).
- **Cleaning, beyond `clean_screams.py`** (`clean_reach.py`): a gate against the print of the file's own quietest
  frames takes the hiss (and a hum) that is there with or without the sound; the per-frame haze gate is only for
  voiced groans (on a breath the noise IS the sound); a limiter that ducks the gain round a peak, because soft
  clipping a knuckle crack put back the treble the low-pass had taken. Also: a sound that is nearly all under
  150 Hz is nothing on a phone's speaker (lift what is above it), a loop ElevenLabs made seamless has to be
  ROLLED until its join lies in a silence before anything is cross-faded, and a loop's "energy above the cutoff"
  must be measured with the join inside (a file's cut ends read as a click that is not there).
- **ElevenLabs refuses prompts over 450 characters**; `codex exec` has no `--full-auto` (use `-s workspace-write`),
  waits on stdin unless it is closed (`< /dev/null`), and its sandbox has no network: have it print
  `FILE <name> <signed url>` and fetch with curl.
- **`tools/mobile_qa/qa.py play` mutes by forcing every `Sound.Volume` to 0, which breaks any script that keeps
  state in a Sound's volume** (these loops fade through it and would never start). To test sound logic silently,
  put every Sound in a SoundGroup of volume 0 instead (`/tmp/qa/reach_play.py` did; the README has the recipe).
- **A test started while the lobby is still loading has the client's camera at the spawn** for half a minute
  although the server has moved the body: wait for `[LobbyLoading] lobby in ...` before measuring distances.
- **Tested in Studio, solo, muted**: a whole taking (wake, breathing, four crawls, windup, grab, drag, the
  victim's own kill) and an escape (windup, slam, crawl back, retreat), each logged with volume, speed, load state
  and distance; all 14 assets load; console clean. **Nobody has listened to them**: a session cannot hear, and
  the Mac had been idle for a quarter of an hour. Not tested: two or more players, a phone's speaker.
- **The owner had closed Studio at 11:26**; it was reopened in the background for this (new MCP id) and left
  open in Edit mode on the place. Everything since v2816 (the phone QA fixes, own servers for everyone, the
  12-hour board, these sounds) is in Studio and was NOT published when this was written.

### Added 2026-10-08 (afternoon, later) - Ads: first numbers, ten pictures in the campaign; phones locked to landscape

- **Owner**: read the campaign's first numbers, "do extensive research and submit the level 2 pictures even though
  its under maintenance to the campaign and maybe just add the max 25 assets", and "lock the screen on phones to
  landscape".
- **The numbers, 12.6 hours in** (`python3 tools/promo/ads.py results`; snapshot in
  `artifacts/promo-20261007/ads-results-20261008.json`): 44 546 impressions, 2 334 clicks, 5.24% click rate, 5.05
  credits (0.11 per thousand impressions, 0.002 per click). Per picture: T01 hide 45% of the impressions at 4.66%,
  A01 run 21% at 5.26%, T03 Counter 15% at 6.70%, T04 shh 7% at 4.88%, A03 table check 6% at 6.57%, T05 cinema 6%
  at 4.93%. The two pictures with a monster close in the frame click best. Third-party benchmarks put a usual
  sponsored click rate at 1 to 2% and "great" at 3% and over. **Plays were not reported yet**: Roblox says plays
  and earnings can take up to 48 hours. I had told the owner the campaign had run "about a day and a half": it had
  run half a day (it started 2026-10-08 01:30).
- **Three things I had wrong, now corrected in `ads.py`**: a campaign holds TEN pictures, not 25; delivery between
  pictures is NOT even (45 / 21 / 15 / 7 / 6 / 6 percent for six ads approved in the same second), so the reason
  given on 2026-10-08 for running only six does not hold; and the per-picture query needs an ISO timestamp.
- **The campaign has ten pictures now** (edit at 14:13, HTTP 200; nothing else about it changed: daily 11, 5 days,
  group ad credit, auto-reload off): added A02 poolrooms hall and A08 poolrooms rotunda (Level 2, by the owner's
  word although the level is under maintenance), A09 the four entities, A04 the Usher. All four ads were approved
  at once and the campaign stayed on, still "learning" (its first 24 hours). The five landscape pictures not in
  it: A05, A06, A07, T02, T06. No new pictures were made: with a cap of ten there was no room for more.
- **How a running campaign is changed**: `PATCH /v3/native/campaigns/<id>?groupId=` with `{"campaign": {"id",
  "asset_ids": [only the NEW pictures]}}`. Sending the full list is refused ("AssetId ... already exists on this
  campaign") and changes nothing. Roblox lets only the name and the pictures of a running campaign be changed.
  Numbers per picture come from the analytics gateway broken down by `AdId` (addresses in `ads.py`'s docstring);
  they move in batches, not live. `PATCH /v1/ads/<ad id>` switches one picture off: not used yet.
- **To do about 2026-10-10**: `ads.py results` again, now with plays; judge the pictures on cost per play, switch
  the weak ones off, and only then think about new pictures in the manner of the winners.
- **Phones are locked to landscape**: `StarterGui.ScreenOrientation` was `Sensor` and is `LandscapeSensor` (either
  landscape way up, never portrait). A place property, not a script, so the repo does not mirror it. Read back in
  a play session: `PlayerGui.ScreenOrientation = LandscapeSensor`. **In Studio, NOT published** when this was
  written. The portrait layouts found wanting in the phone QA (shop, daily rewards) no longer matter.
- **Studio had lost Team Create at 13:10** ("heartbeat failure") and answered `execute_luau` with timeouts while
  still listing the place. `tell application "RobloxStudio" to quit` answered "User cancelled", `pkill` did not end
  it, `kill -9 <pid>` did; `open -g "roblox-studio:..."` started a new one beside it (two processes for a moment:
  end the old one by pid, never by name).

### Changed 2026-10-05 - Level 4 is a normal public round, the campaign's last level; previews deleted (supersedes the Level 4 notes below)

- **Level 4 is an ordinary level.** Anyone can host it from the new lobby's Level 4 bays. QueueBridge marks only levels > 4
  `previewOnly`, so those bays are plain pads with CREATE PARTY: no TRIAL ROUND / MAP PREVIEW choice, even for developers.
  The `LEVEL4_QUEUE_CHOICE` code in GameManager is dormant. **A Level 3 clear offers CONTINUE into Level 4**
  (`Routing.MaxLevel = 4`, Version `2026-10-05.1`; NO_LEVEL3_CONTINUE_20260923 lifted), and Level 4 offers BACK TO
  LOBBY only. The old tunnel lobby (the fallback) opens its Level 4 door: "bays open: 1, 2, 3, 4".
- **The old cinema versions and the preview are deleted** (owner, per item):
  - Workspace "Level 4 Cinema Preview" and "Level 4 Cinema V9 QA".
  - ServerStorage Level4CinemaV3Archived, Level4V4Archived_20260927, Level4V7Templates, Level4V10Templates.
  - The scripts Level4PreviewAccess, Level4V4PreviewAccess, Level4Generator, Level4CinemaV4-V7, Level4Expansion, Level4Renovation.
  - The preview attributes and Level4V4Exit on "Level 4 Cinema Blender".

  .rbxm backups with sha256 are in `G:\Roblox\_local\l4public\backup\`. `Level4PreviewPrompt` stays: it also hides the
  Level 5/6 preview prompts.
- **The Blender importer still needs the original layout**: `tools/level4_blender/place.luau` `OLD_NAME = "Level 4 Cinema
  Preview"`, which supplies the signage carriers. Insert `backup/Workspace__Level_4_Cinema_Preview.rbxm` into Workspace
  before the next place_driver run, and delete it again afterwards.
- **Progression:**
  - `CampaignComplete` ("Four Doors Down") needs clears of Levels 1-4, both on a clear and in the achievements backfill
    at profile load.
  - `Challenges.HiddenUntilPlayed = {}`: the Level 4 RECORDS card always shows.
  - `FirstClearLevel4` has a real badge id (another session's ACHIEVEMENTS_20261004 work).
- **Reel findability (2026-10-08, owner's pick):**
  - The server publishes `Level4_ReelRooms`, from `Reels.RoomNames`, and the objective panel shows "Reels: Cafe, Arcade".
  - TORCH_GLINT_20261008: a client-only sparkle and warm flash when this player's flashlight beam hits a loose reel.
    Range 55, cone 16 degrees. Walls (`Collision`) and door leaves (`Doors`) block it.
- **Co-op breaker fallback** (`Breaker.CoopFuseAfterSeconds = 45`): with 2+ living players the lever hold is the way.
  The first fuse attempt with nobody on the lever starts a 45 s wait, and after it the fuse works, so an AFK teammate
  cannot stall the round. The fuse prompt is no longer gated on solo. Escapees spread over the `L4ExitSafeSpawn`s in
  escape order.
- **Tooling (2026-10-08):**
  - The place is named "(UPDATE) BACKROOMS: STAY QUIET", so `push_repo_to_studio.py` needs `--studio-name`.
  - The Studio lock is `_local/studio-lock.json`.
  - `apply_scoped_patch.py` must run through `artifacts/level4-reels-20261008/apply_with_current_studio.py`, because
    `export_readonly.py` hardcodes an old studio id.

<!-- End of preserved original sections. -->
