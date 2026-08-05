# Backrooms: No Way Out

A round-based **Backrooms-inspired multiplayer horror game** for Roblox, by **ERN Studios**.

You spawn in a road-tunnel lobby, queue up a party at a launch station, and get
teleported into a level. One life per round. Solve the level's objective while
something hunts you — escape together, or watch your friends try.

**Status:** Level 1 is **done**. Level 2 is **in progress**. Level 3 comes next —
then we publish on Roblox.

## 🚇 The lobby ("Zyntra Transit — Powering the Future.")

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

## 🩵 Level 2 — Sunken Leisure Complex (world done, entity pending)

A bright, sunlit liminal poolrooms complex with its **own** generator — it
shares only the tile texture and the water look with Level 1's palette of
services. (The previous hand-authored Flooded Poolrooms level is preserved in
`ServerStorage.Level2Backup_20260805`.)

- **Binary space partition** of a 1400-stud region: 17–20 halls of wildly
  different sizes joined by flooded **arch-tunnel corridors** (a vaulted ring
  every 11 studs). Water covers the floor **wall-to-wall** in every pool hall —
  shallow wading in most, swimmably deep in others, with stairs descending
  from every doorway.
- **Real sunlight**: the outer roof is translucent glass (no shadow), hall
  ceilings carry genuine skylight slots, and the in-round grade is bright and
  fog-free. Colonnades and tiled columns rise straight out of the water.
- **Slide halls** (3): a mezzanine deck near the ceiling, straight parallel
  flumes into the water, and a **helix slide wrapping a column**. The grand
  hall carries the exit flume to a sealed **Level 4 gateway** placeholder.
- **Kids wing**: 5 contiguous painted (untiled) rooms in 3 colors, connected
  wall-to-wall, with soft-play blocks, a mini slide and a raised paddling pool.
- **Objective:** start **3 pump stations** — each drains a flooded corridor
  (terrain water actually removed) — then the pressure doors into the grand
  hall unseal; ride the exit flume from the top deck.
- **Sound**: `Level 2 Sound Controller` + StringValue slots in
  `ReplicatedStorage["Level 2 Sound Library"]` (paste an asset id, done).
  Level 1 has the same setup. Server fires pump/drain/door/slide cues.
- **Entity space reserved, nothing spawns yet**: two den markers (A deepest,
  B far from A), 4 patrol nodes per hall, 30×19 doorways, and empty profile
  stubs in `Configuration.Entities`.
- Tweak guide for collaborators: `ServerScriptService."Level 2 Systems".README
  - LEVEL 2 TWEAKS`. Force a layout with the `Level2Seed` workspace attribute.

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
  Level2Generator.ModuleScript      Level 2: doorway into "Level 2 Systems"
  Level 2 Systems/                  Level 2: config, BSP layout, world builder,
                                    pump objective, round adapter, tweak README
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
`U` unlimited battery/stamina · `C` third person · `M` Zyntra developer phone.
Lock down / remove before publishing.

## 🗺️ Roadmap to release

- [x] **Level 1 — done** (maze, entity, puzzle, escape flow, cinematic kill,
      full audio/animation set, lobby + matchmaking around it)
- [ ] **Level 2 — Sunken Leisure Complex** (world, objective, lighting and
      sound scaffolding are in; remaining: 1–2 hostiles for the reserved dens,
      sound-library asset ids, and a playtest pass. The previous Flooded
      Poolrooms build is parked in `ServerStorage.Level2Backup_20260805`.)
- [ ] **Level 3 — build** (bay 3 is sealed again and waiting)
- [ ] **Pre-publish pass**: restrict/remove DevCheats (key on UserId, not name),
      strip Studio-only test hooks, mold/stain texture slots, final audio slots
      (`LUNGE_SOUND`, `ENTITY_STEP_RUN`, `IDLE_SOUNDS`)
- [ ] **Publish on Roblox** 🚀
