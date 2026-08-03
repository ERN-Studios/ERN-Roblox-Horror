# Backrooms: No Way Out

A round-based **Backrooms-inspired multiplayer horror game** for Roblox, by **ERN Studios**.

You spawn in a road-tunnel lobby, queue up a party at a launch station, and get
teleported into a level. One life per round. Solve the level's objective while
something hunts you — escape together, or watch your friends try.

**Status:** Level 1 is **done**. Level 2 is **in progress**. Level 3 comes next —
then we publish on Roblox.

## 🚇 The lobby ("A-Sync Transit")

- A persistent tunnel lobby built at server start (`TunnelLobbyBuilder`). You walk
  around in your **own Roblox avatar** (third person, jumping allowed, dance emote
  on `G`).
- Six **level bays**; bays 1–2 are active, 3–6 are sealed ("ACCESS UNSTABLE").
  Each bay has **launch stations**: step in to host, pick **party size (1–6)** and
  **public / friends-only**, and a countdown starts as the party fills.
- Launching teleports the party to a **reserved server** that generates exactly one
  world for that party (in Studio it falls back to an in-place test round).
- Entering a round swaps everyone into the **hazmat gameplay rig**
  (`StarterCharacter`) with normalized avatar size (hitbox parity), locked
  first-person camera, and the full horror HUD. Back in the lobby you get your
  personal avatar and relaxed camera again — everything is gated on the
  `InRound` attribute.

## 🟨 Level 1 — The Yellow Maze (done)

Procedurally generated 40×40 office maze (corridors, plazas, pit rooms, worn-90s
elevator), new layout every round.

**Objective** (scales per player: 2 fuses, 1 fuse box, 1 lever each):
1. Find **fuses** — nearby ceiling lights cluster-glow to hint where they are.
2. Insert into wall-mounted **fuse boxes** (status plates, carried fuse shows in
   your hand). Every insert raises the danger — flicker, entity speed — and draws
   the entity to that area. All boxes full → continuous red **ALERT**.
3. Pull every **lever** within 10 s of each other (countdown + status HUD; if a
   teammate dies the sync requirement is dropped — levers latch).
4. A radial **POWERDOWN** wave kills the lights, the **exit gate** opens (an
   energy-signal detector in your HUD leads you there), the entity guards it.
5. First escapee lights the **green guide line** — ceiling lights along the actual
   route from the elevator to the exit. Escapees spectate; the round ends when
   everyone alive is out (win) or everyone is dead (lose).

**The Entity** (custom skinned Meshy rig, 51 bones, full Blender animation set):
hunts by **sight and sound** — sprinting is loud, sneaking silent, your flashlight
extends its vision range. Grid-navigates the maze it has learned (never clips
walls), remembers your live position 5 s after losing sight, and re-picks a hunt
target every minute. Glowing eyes (amber → **red when hunting**), ballistic
**pounce lunge**, pit-edge **howl** that shoves beam-walkers into the void, and a
**5-second cinematic ground-pin kill** with a first-person kill camera, synced
scream, and fade to spectate.

Colour-coded floor cables run from the elevator trunk to every fuse box (yellow)
and lever (orange) in separate lanes — follow the wires to navigate. A cabin
poster teaches the colour code during the elevator ride.

## 🌊 Level 2 — Flooded Poolrooms (in progress)

Hand-authored flooded poolrooms: pool halls, water channels, sunken galleries,
curved flooded corridors — plus a secret party room for those who look.

- **Objective:** open **3 pressure valves** (each triggers a 30 s blackout with a
  flicker recovery), then escape through the **glossy green pool slide**.
- **Two hostiles** (tag-driven, shared brain): the **PoolFoam** stalker and the
  **PoolPipe** entity — pathfinding with waypoint gating, blackout burst
  aggression, last-seen memory, stuck recovery, and real melee combat
  (windup → impact → recovery), all in `Level2EntityController`.
- Dedicated **water audio engine** in `SoundController`: loudness-normalized wade
  takes, a sample-exact SFX sprite sheet, per-entity step/breathing/attack audio
  with echo in the pipes. (Asset IDs are wired via attributes on the Studio side.)
- Level 2 disables the Level 1 scripts while active and restores everything on
  cleanup — including terrain water and the stored lobby.

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

**Roblox Studio is the source of truth.** This repo is a mirror kept in sync over
Studio's built-in MCP (`tools/sync_from_studio.py` → sha256 manifest in
`studio-sync-manifest.json`). Folders mirror the Studio Explorer 1:1.

```
ServerScriptService/
  GameManager.Script.lua            lobby queue, reserved servers, round loop
  TunnelLobbyBuilder.ModuleScript   the tunnel lobby + launch stations
  MazeGenerator.Script.lua          Level 1: maze, pits, elevator, lights, decor
  PuzzleManager.Script.lua          Level 1: fuses → boxes → levers → exit
  EntityAI / EntityAnimation / EntityKill      Level 1 entity (AI, clips, kill)
  Level2Generator.ModuleScript      Level 2: poolrooms world + valves + slide
  Level2EntityController/Profiles/Navigation   Level 2 entity brain (modules)
  Level2MeshyAnimationPlayer        embedded-keyframe animation fallback
  FlashlightSync / AvatarNormalize / NoiseRegistry   shared services
StarterPlayer/
  StarterCharacter/                 hazmat gameplay rig (+ Animate)
  StarterCharacterScripts/          run anim, muted default steps, dance emote
  StarterPlayerScripts/             HUD, audio hub, flashlight, spectate, scares…
ReplicatedStorage/Remotes/          RemoteEvents (.txt markers)
assets/                             source assets: textures · sounds · models ·
                                    banners · animations (FBX + keyframes) · blender
tools/                              Studio/Blender MCP pipeline (see below)
artifacts/                          captured screenshots from automated playtests
```

## 🔧 Tooling (MCP pipeline)

Everything below drives **live Roblox Studio and Blender** over MCP:

- `sync_from_studio.py` — one-way Studio → repo mirror (this repo).
- `push_level1_to_studio.py` — push edited scripts back into Studio (with drift
  guard).
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

Override locally in Studio for quick tests (don't sync these):

| Script | Setting | Testing | Production |
|---|---|---|---|
| MazeGenerator | `GRID` | `10` | `40` |
| GameManager | `ELEVATOR_TIME` | `2` | `19` (matches the elevator sound) |

**Dev cheats** (`DevCheats.LocalScript` — whitelisted accounts only):
`B` ESP + 3 s fast queue · `V` noclip fly · `P` pause entity · `I` push immunity ·
`U` unlimited battery/stamina. Lock down / remove before publishing.

## 🗺️ Roadmap to release

- [x] **Level 1 — done** (maze, entity, puzzle, escape flow, cinematic kill,
      full audio/animation set, lobby + matchmaking around it)
- [ ] **Level 2 — finish** (world + entity brain are in; remaining: entity
      audio module + kill camera/jumpscare parity with Level 1, published
      animation hookup on the Studio templates, noise-hearing wiring,
      wander-node usage, general playtest pass)
- [ ] **Level 3 — build** (bay 3 is waiting in the lobby)
- [ ] **Pre-publish pass**: restrict/remove DevCheats (key on UserId, not name),
      strip Studio-only test hooks, mold/stain texture slots, final audio slots
      (`LUNGE_SOUND`, `ENTITY_STEP_RUN`, `IDLE_SOUNDS`)
- [ ] **Publish on Roblox** 🚀
