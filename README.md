# Backrooms: No Way Out

A round-based **Backrooms-inspired multiplayer horror game** for Roblox, by **ERN Studios**.

You spawn in a road-tunnel lobby, queue up a party at a launch station, and get
teleported into a level. One life per round. Solve the level's objective while
something hunts you — escape together, or watch your friends try.

**Status:** Level 1 is **done** (including its full positional-audio pass).
Level 2's world is **built**, with two hostiles (Pool Foam + Slidemouth) and the
slide systems in active development. Level 3 — the **Mall Backrooms Party** —
has its core systems in place (layout generator, Mall Manager AI, hiding,
music/blackout cycle) and is being built out. Then we publish on Roblox.

## 🚇 The lobby ("Zyntra Transit — Powering the Future.")

- A persistent tunnel lobby built at server start (`TunnelLobbyBuilder`). You walk
  around in your **own Roblox avatar** (third person, jumping allowed, dance emote
  on `G`).
- Six **level bays**; bays **1–3 are active**, 4–6 are sealed ("ACCESS UNSTABLE").
  Each bay is themed after its level (yellow office, poolrooms tile, mall party)
  and has four **launch stations** — wall-mounted monitors on articulated arms
  over circular launch pads. Step onto a pad to host, pick **party size (1–6)**
  and **public / friends-only**, and a countdown starts as the party fills.
  Station monitors are depth-tested (no more screens showing through walls) and
  the bays' floor furniture is **solid** — only the deliberately wall-glitched
  "geometry error" props stay intangible.
- Launching teleports the party to a **reserved server** that generates exactly one
  world for that party (in Studio it falls back to an in-place test round).
- Entering a round swaps everyone into the **hazmat gameplay rig**
  (`StarterCharacter`) with normalized avatar size (hitbox parity), locked
  first-person camera, and the full horror HUD. Back in the lobby you get your
  personal avatar and relaxed camera again — everything is gated on the
  `InRound` attribute.

## 🟨 Level 1 — The Yellow Maze (done)

Procedurally generated 40×40 office maze (corridors, plazas, pit rooms, and a
brushed-aluminum service elevator with its own roof texture), new layout every
round.

**Objective** (scales per player — each player adds 1 fuse box, 1 lever, and one
**coloured circuit**; twice as many wall relays spawn as fuses needed):
1. Extract **fuses** from wall-mounted ZYNTRA relays — nearby ceiling lights
   cluster-glow to hint where they are, and extraction makes noise the entity
   hears.
2. Insert into wall-mounted **fuse boxes** (status plates, carried fuse shows in
   your hand). Every insert raises the danger — flicker, entity speed — and draws
   the entity to that area. All boxes full → continuous red **ALERT**.
3. Pull every **lever** within 10 s of each other (countdown + status HUD; if a
   teammate dies the sync requirement is dropped — levers latch).
4. A radial **POWERDOWN** wave kills the lights, the **exit gate** opens (an
   energy-signal detector in your HUD leads you there), the entity guards it.
5. Escapees spectate; the round ends when everyone alive is out (win) or
   everyone is dead (lose).

**Coloured circuits:** every fuse-box + lever pair gets its own cable colour
(red, blue, green, yellow, magenta, cyan) with physical floor cables routed from
just outside the elevator doors to both ends. The cabin's **maintenance poster
shows the full circuit list — total cable count and one coloured row per
circuit — from the moment the elevator ride starts**, so the party can plan
before the doors open.

**Audio:** the fluorescent **hum is positional, per ceiling panel** — each lit
panel hums on its own (nearest panels only, streaming-safe), and a panel that is
dead, flickering, blacked out or powered down is **silent**, so your ears tell
you which fixtures are live. The entity also lets out **distant screams the
whole server hears simultaneously** from its actual direction (4 sound slots,
server-scheduled so everyone hears the same take). Death screams, chase music,
yells, lunges, footsteps and the grandfather-clock strike are all positional.

**The Entity** (custom skinned Meshy rig, 51 bones, full Blender animation set):
hunts by **sight and sound** — sprinting is loud, sneaking silent, your flashlight
extends its vision range. Grid-navigates the maze it has learned (never clips
walls), remembers your live position 5 s after losing sight, and re-picks a hunt
target every minute. Glowing eyes (amber → **red when hunting**), ballistic
**pounce lunge**, pit-edge **howl** that shoves beam-walkers into the void, and a
**5-second cinematic ground-pin kill** with a first-person kill camera, synced
scream, and fade to spectate.

## 🩵 Level 2 — Sunken Leisure Complex (world built, hostiles in development)

A bright, sunlit liminal poolrooms **water park** with its **own** generator —
it shares only the tile texture and the water look with Level 1. (The previous
hand-authored Flooded Poolrooms level is preserved in
`ServerStorage.Level2Backup_20260805`.)

- **Binary space partition** of a 1400-stud region: ~45 halls capped at ~250
  studs a side (`MaximumLeafSize`), joined by flooded **arch-tunnel corridors**.
  A **fresh random seed every round**. Water covers the floor **wall-to-wall**
  in every pool hall at **wading depth only** — nobody ever swims.
- **Real sunlight**: translucent no-shadow glass roof, and per-hall **skylight
  patterns** — full lines, dashes, a punched checkerboard, or a single centre
  band — so no two ceilings read the same. Smooth trumpet-curved columns run
  flush from floor to ceiling; a world-level column registry plus doorway
  keep-out strips guarantee no pillar ever overlaps anything or blocks an exit.
- **Play furniture in every water hall**, randomized per seed and
  collision-verified: slide kits (straight railed stairs → platform on legs →
  chute into the water), **diving towers** with blue/yellow/red/green boards at
  several heights, play towers with tube flumes, railed overlooks, and a swarm
  of **buoyant** noodles, beach balls, rings and rafts that bob and drift when
  players wade into them (each spawned only in verified-open water).
- **Slide halls** (3): mezzanine deck, straight parallel flumes with
  colour-moulded tubs and clean bores, a dense whole-turn spiral stair docking
  onto the east catwalk, and a **helix slide on its own dedicated column** fed
  by a catwalk bridge. Riding a slide is a real physics ride (`Level 2 Slide
  Controller` + server-side **slide ragdoll service**). The grand hall carries
  the exit flume east into a large gateway room (next-level placeholder behind
  a story door).
- **Kids wing**: cosy painted rooms with whole-room ankle-deep water, kids
  slides in the room's own colour, a hex-packed **ball pit** (~370 balls), and
  round roof skylights.
- **Pump rooms**: raised walkway ring + centre pump island over shallow water,
  with a diagonal three-board jump stand.
- **Objective:** start **3 pump stations** — each drains a flooded corridor
  (terrain water actually removed) — then the pressure doors into the grand
  hall unseal; ride the exit flume from the top deck.
- **Sound**: `Level 2 Sound Controller` + StringValue slots in
  `ReplicatedStorage["Level 2 Sound Library"]` — ambience beds, authored cues
  (the pressure door gets a spatial multi-emitter corridor echo), random
  contextual one-shots anchored to real world geometry, **wading footsteps**
  (three complete human-wading phrases plus a quiet underwater-resistance
  layer, driven by an actual water raycast) and a separate
  **dry-tile footstep slot** (`Level 2 Player Dry Tile Walking Sound`) for
  walking where there's no water underfoot.
- **Hostiles in development:** the **Pool Foam** stack (controller, navigator
  with roof-safe floor probing, observer, proxy rig, animation adapter, client
  effects) and the **Slidemouth** (its own controller + client, tied to the
  pump/slide soundscape with warning/scream serials and four monster-groan
  recordings). Dens, per-hall patrol nodes and spawn markers are generated.
- Every change is validated in live play sessions across multiple seeds by
  geometry probes (clip scan, stair connections, swim depth, wedged props, exit
  clearance) before it lands.
- Tweak guide for collaborators: `ServerScriptService."Level 2 Systems".README
  - LEVEL 2 TWEAKS`. Force a layout with the `Level2Seed` workspace attribute,
  set to any number **≥ 1**. Set it to **0** — or clear it — for a fresh random
  map every round; 0, negatives and non-numbers all mean OFF. A round never
  writes its random pick back into the attribute.

## 🟣 Level 3 — Mall Backrooms Party (in development)

A dead-mall party floor behind bay 3. The core systems are in and being built
out (`Level 3 Systems`):

- **Deterministic layout generator** for the mall — straight, axis-aligned
  connections, one centered opening per room side, no diagonal corridors.
- **The Mall Manager**: a server-authoritative kinematic custom-rig enemy with
  multi-ray perception, server-inferred hearing, sticky multiplayer targeting,
  last-known-position memory, authored-room strategic routing, stuck recovery
  and fair line-of-sight attacks (plus a client-side visual smoother).
- **The music cycle**: one authoritative server clock runs the five-second
  warning → a 2:30 **blackout** while the song finishes → a final 30-second
  Mall Manager **hunt** → uneven fluorescent recovery, then the next
  synchronized song cycle.
- **Hiding**: server-validated **under-table hiding** with prompts, occupancy
  and character restoration.
- Its own lighting/sound controllers, reader client, and a large in-Studio
  **test suite** (`Level 3 Test Suite`).

## ⌨️ Controls

| Input | Action |
|---|---|
| `WASD` | Walk (quiet — the entity hears at medium range) |
| `Left Shift` | Sprint — **loud**, limited stamina, 3× stamina while being chased |
| `Left Ctrl` | Sneak — slow and silent |
| `F` | Flashlight — battery-limited (~60 s), flickers as warnings; **visible to teammates** |
| `Q` / `E` | Spectate while dead / escaped — full first-person POV of survivors |
| `G` | Dance emote (lobby fun) |
| Touch | On-screen **RUN / JUMP / POV** buttons + flashlight tap target |

## 🗂️ Repository layout

**Roblox Studio is the source of truth.** This repo is a **one-way mirror** of
the Studio place — code changes are made in Studio (or handed to the owner to
apply there) and pulled into the repo; the repo is never pushed back on its
own. Folders mirror the Studio Explorer 1:1; `studio-sync-manifest.json` keeps
per-file sha256 hashes of the mirrored state.

```
ServerScriptService/
  GameManager.Script.lua            lobby queue, reserved servers, round loop
  TunnelLobbyBuilder.ModuleScript   the tunnel lobby + launch stations
  MazeGenerator.Script.lua          Level 1: maze, pits, elevator, lights, decor
  PuzzleManager.Script.lua          Level 1: fuses → boxes → levers → exit
  EntityAI / EntityAnimation / EntityKill      Level 1 entity (AI, clips, kill)
  Level2Generator.ModuleScript      Level 2: doorway into "Level 2 Systems"
  Level 2 Systems/                  Level 2: config, BSP layout, world builder,
                                    pump objective, slides + ragdoll, Pool Foam
                                    + Slidemouth hostiles, tweak README
  Level3Generator.ModuleScript      Level 3: doorway into "Level 3 Systems"
  Level 3 Systems/                  Level 3: config, layout, world builder, Mall
                                    Manager AI, hiding, music cycle, test suite
  FlashlightSync / AvatarNormalize / NoiseRegistry   shared services
StarterPlayer/
  StarterCharacter/                 hazmat gameplay rig (+ Animate)
  StarterCharacterScripts/          run anim, muted default steps, dance emote
  StarterPlayerScripts/             HUD, audio hub (SoundController), per-level
                                    sound/lighting controllers, flashlight,
                                    spectate, slides, scares…
ReplicatedStorage/Remotes/          RemoteEvents (.txt markers)
assets/                             source assets: textures · sounds · models ·
                                    banners · animations (FBX + keyframes) · blender
tools/                              Studio/Blender MCP pipeline (see below)
artifacts/                          captured screenshots from automated playtests
```

## 🔧 Tooling (MCP pipeline)

Everything below drives **live Roblox Studio and Blender** over MCP:

- `pull_source_from_studio.py` — audits every mirrored script against Studio's
  live `.Source` (hash comparison) and pulls whatever drifted. This is the
  primary sync path.
- `sync_from_studio.py` — the original full Studio → repo mirror. **Caveat:**
  its `script_read` calls can serve a stale editor buffer after programmatic
  source writes; prefer the pull tool above.
- **Repo → Studio pushes**: `record_pending_push.py` marks repo-edited scripts
  as `pending-studio-push` in the manifest (remembering the hash Studio should
  still hold), and `push_repo_to_studio.py` applies exactly those entries
  through `ScriptEditorService:UpdateSourceAsync` — raw `.Source` writes leave
  LocalScripts running stale bytecode. The push is two-phase and refuses to
  half-apply a batch:

  ```
  python tools/push_repo_to_studio.py --list    # offline: what is queued
  python tools/push_repo_to_studio.py --audit   # read live Studio, classify, write nothing
  python tools/push_repo_to_studio.py           # phase 1 check, then phase 2 write
  ```

  Phase 1 reads every queued script's live source and classifies it
  (already-applied / ready / conflict); **any** conflict aborts before a single
  byte is written (`--skip-conflicts` pushes the clean ones,
  `--overwrite-conflicts` accepts Studio's copy as the baseline). Phase 2 stages
  each source in a ServerStorage buffer, verifies its length, then swaps it in
  through a callback that re-checks the baseline *inside* Studio — so a script
  edited between the check and the write is never clobbered. Every pre-push
  source is saved under `.studio-push-backups/<timestamp>/`, and the manifest is
  rewritten atomically after each file.

  While a push is queued, `pull_source_from_studio.py` **skips** those files
  (their repo copies are newer than Studio); pass `--force` to discard the
  unpushed edits instead. (`push_level1_to_studio.py` /
  `push_level2_poolrooms_to_studio.py` are kept for history but predate this.)
- **Animation pipeline**: author/fix clips in Blender
  (`blender_mcp_client.py`, `build_*` scripts) → export retargeted keyframes
  (`export_entity_keyframes_retargeted.py`) → publish as Roblox animations
  (`publish_entity_animations.py`, versioned manifests in `assets/animations/`).
- **Automated playtests**: `playtest_level1.py` (server/client health, cable
  overlap detector, lunge/run probes), `playtest_entity_kill.py`,
  `playtest_lobby_avatar_transition.py`, `playtest_ui_pit_regressions.py`, plus
  `capture_*.py` screenshot tools (results land in `artifacts/`).
- `publish_elevator_textures.py` — upload texture PNGs through Studio.

## 🧪 Testing vs production values

Both are currently at **production** values. Override locally in Studio for
quick tests (don't sync the overrides):

| Script | Setting | Testing | Production |
|---|---|---|---|
| MazeGenerator | `GRID` | `10` | `40` |
| GameManager | `ELEVATOR_TIME` | `2` | `19` (matches the elevator sound) |

**Dev cheats** (`DevCheats.LocalScript` — whitelisted accounts only):
`B` ESP + 3 s fast queue · `V` noclip fly · `P` pause entity · `I` push immunity ·
`U` unlimited battery/stamina · `C` third person · `J` Zyntra developer phone ·
`M` mute/unmute the active dispatch · `N` stop the current dispatch briefing.
Lock down / remove before publishing.

## 🗺️ Roadmap to release

- [x] **Level 1 — done** (maze, entity, puzzle, coloured-circuit cables +
      elevator briefing poster, escape flow, cinematic kill, per-light hum and
      the full positional audio/animation set, lobby + matchmaking around it)
- [ ] **Level 2 — Sunken Leisure Complex** (world, play structures, slides,
      objective, lighting and sound scaffolding are in and probe-validated;
      remaining: finish the Pool Foam + Slidemouth hostiles, sound-library
      asset ids, and a final playtest pass)
- [ ] **Level 3 — Mall Backrooms Party** (layout generator, world builder, Mall
      Manager AI, hiding, music/blackout cycle and test suite are in; remaining:
      content build-out and a full playtest pass)
- [ ] **Pre-publish pass**: restrict/remove DevCheats (key on UserId, not name),
      strip Studio-only test hooks, mold/stain texture slots, and fill the
      remaining empty audio slots — `SCREAM_SOUNDS` 1–4 (Level 1 distant entity
      screams), `LUNGE_SOUND`, `ENTITY_STEP_RUN`, `IDLE_SOUNDS`,
      `BREATHING_SOUND`, `LOBBY_FOOTSTEP_SOUND`, and the Level 2 library slots
      (incl. `Level 2 Player Dry Tile Walking Sound`)
- [ ] **Publish on Roblox** 🚀
