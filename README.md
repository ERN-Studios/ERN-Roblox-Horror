# ERN Backrooms Test

A round-based **Backrooms-inspired horror game** for Roblox. You and your party wake
up in an elevator. The doors open into an endless yellow maze. One of you makes it
back — or none of you do.

Built entirely with procedural generation: every round is a new maze.

## 🎮 Gameplay

- Everyone spawns **inside an elevator** — doors shut, countdown, doors slide open
- **One life per round.** Die and you spectate until the round ends
- The **Entity** hunts by sight and sound: sprinting is loud, sneaking is silent
- Flickering lights ahead of it can betray its approach — or just be a dying tube
- **Pit rooms**: huge open halls where the floor is a grid of holes with narrow
  beams between them. Falling in counts as your death. The Entity can't enter —
  balancing over the void is the only safe haven
- **Win by solving the puzzle** (fuses → boxes → levers → exit — see below).
  There is **no timer**. The round ends only when the party escapes (**win**) or
  everyone is dead (**lose**). You're never told how many teammates are still alive.

## ⌨️ Controls

| Key | Action | Effect |
|---|---|---|
| `WASD` | Walk | quiet — the Entity hears it at medium range |
| `Left Shift` | Sprint | **loud** — audible across the maze |
| `Left Ctrl` | Sneak | slow + silent walk (there's no crouch pose) |
| `F` | Flashlight | see further — but the Entity sees YOU much further |
| — | Jump | disabled. The beams are the only way across the pits |

First person is forced. The cursor is hidden. There is no map.

**Dev cheats** (`DevCheats.LocalScript` — testing only, remove before release):
`B` toggles ESP (fuses / boxes / levers / exit / entity glow through walls),
`V` toggles noclip fly (WASD + Space/Ctrl). Restrict via `ALLOWED_NAMES` or delete.

## 🗂️ Repository layout

The folder structure mirrors the **Roblox Studio Explorer** 1:1 — every file
states at the top exactly where it gets pasted.

```
ReplicatedStorage/
  Remotes/                  ← RemoteEvents (objects, not scripts — see the .txt files)
ServerScriptService/
  MazeGenerator.Script.lua      procedural maze, pit zones, elevator, lighting
  GameManager.Script.lua        round loop, one-life rule, elevator doors
  EntityAI.Script.lua           sight/sound hunting, chase, pit avoidance
  EntityKill.Script.lua         touch = death + jumpscare
  FlashlightSync.Script.lua     server-side flashlight state (Entity sight bonus)
  PuzzleManager.Script.lua      fuses → fuse boxes → levers → exit (the win)
  NoiseRegistry.ModuleScript.lua  footstep noise bookkeeping
StarterPlayer/StarterPlayerScripts/
  NoiseReporter.LocalScript.lua      movement state → noise events
  FlashlightController.LocalScript.lua  handheld two-cone flashlight
  SoundController.LocalScript.lua       ambience, proximity breathing, footsteps
  RoundUI.LocalScript.lua            round status bar
  PuzzleUI.LocalScript.lua           objective + fuse counter
  JumpscareUI.LocalScript.lua        death flicker/shake (+ optional image/sound)
  DevCheats.LocalScript.lua          TESTING ONLY — ESP + noclip fly (remove for release)
Workspace/
  Entity.Model.txt          ← checklist for building the Entity rig in Studio
textures/                   ← source PNGs for all our custom decals
```

File naming: `Name.<StudioObjectType>.lua` — the middle part tells you what to
insert in Studio (`Script`, `LocalScript`, `ModuleScript`). In Studio the
instance name has no suffix (`EntityAI`, not `EntityAI.Script`).

## 🛠️ Setting up in Roblox Studio

1. New place → **delete the default `Baseplate` and `SpawnLocation`**
2. Create the RemoteEvents: `ReplicatedStorage → Remotes (Folder)` containing
   `ReportNoise`, `ToggleFlashlight`, `Jumpscare`, `RoundStatus`, `PuzzleStatus`
   (all RemoteEvents, names are case-sensitive — see the `.txt` files in
   `ReplicatedStorage/Remotes/`)
3. Paste each `.lua` file into the matching object per the table above
4. Build the **Entity**: Avatar tab → Rig Builder → block rig → rename to `Entity`,
   set `PrimaryPart` = HumanoidRootPart, `CanCollide = false` on all other parts
   (full checklist in `Workspace/Entity.Model.txt`)
5. **Publish the place** (File → Publish) — unpublished places fail to load assets
6. Play (F5)

### Testing vs production values

For quick testing, override locally in Studio (don't commit these):

| Script | Setting | Testing | Production |
|---|---|---|---|
| MazeGenerator | `GRID` | `10` | `40` |
| GameManager | `ELEVATOR_TIME` | `2` | `12` |

## 🎨 Textures

All decals are **our own uploads** (source PNGs in [`textures/`](textures/)).
To change one: upload the PNG via Studio's Asset Manager → copy the asset ID →
paste it into the matching `*_TEXTURE` config at the top of
`MazeGenerator.Script.lua`. Decal IDs and image IDs both work — the script
resolves them automatically at server start.

Available slots: wall · floor · ceiling tile · mold overlay · lit light fixture ·
dead light fixture · elevator walls/floor/doors · **wall drawings** (`WALL_ART`,
a list — graffiti/clues/scares stamped on random walls) · **carpet stains**
(`STAIN_TEXTURES`, a list — stamped flat on random floor tiles).

Alignment notes:
- **Ceiling**: one image = one office tile; the grid auto-aligns so every light
  panel replaces exactly one tile
- **Mold**: transparent PNG, mold hanging from the image top — tiled once over
  the wall height, applied to random walls and around every pit shaft

## 🧩 How to win (the puzzle)

Scales with the party — **per player: 2 fuses spawn, 1 fuse box, 1 lever.**

1. **Find fuses** on the ground (glowing bricks). Twice as many spawn as needed.
2. **Insert them into the fuse boxes** (one per player, `FUSES_PER_BOX = 1`).
   Boxes are **mounted on walls**. Every insert makes it worse: lights flicker
   more, the entity speeds up, and **the entity appears in that area** (~10 cells
   off — near, not on top of you).
3. **All boxes full → the levers unlock** (also wall-mounted, near the map edges,
   spread far apart, so the party has to **split up**). Once the boxes are done
   there's a chance every 10s of **ALERT** (red pulsing lights + siren) — 50% the
   first roll, 5% after.
4. **Flick every lever within 10 seconds of each other.** Pulling one turns its
   light green — the signal (use voice chat) for everyone else to pull theirs.
5. **All levers together → the lights drop** (a few stay faintly on; the entity
   becomes a blinking beacon), the **EXIT opens in the outer wall** with the
   entity guarding it. Reach the exit to **win** (level 2 later).

The HUD shows **status only** — fuses carried and boxes on. It does **not**
explain the objective; players are briefed beforehand and figure the rest out.

Placeholder shapes for now — model the `Fuse` / `FuseBox` / `Lever` / `Exit`
later, just keep the names. Tuning is at the top of `PuzzleManager.Script.lua`
(`FUSES_PER_BOX`, `SPAWN_MULT`, `LEVER_WINDOW`, `ENTITY_AREA_CELLS`, alert chances).

## 🔊 Audio

Paste your own audio asset IDs into the slots — any left `""` is silent.

| Sound | Where | Behaviour |
|---|---|---|
| Ambience | `SoundController.LocalScript.lua` | constant background drone (2D) |
| Breathing | `SoundController.LocalScript.lua` | swells louder as the Entity nears — no direction |
| Footsteps (walk/run) | `SoundController.LocalScript.lua` | your own steps; sneaking is silent |
| Entity sound | `ENTITY_SOUND` in `EntityAI.Script.lua` | looping growl/drone, **positional** (you hear which way) |
| Alert siren | `ALERT_SOUND` in `SoundController.LocalScript.lua` | plays during ALERT (red-lights) mode |
| Jumpscare | `JUMPSCARE_SOUND` in `JumpscareUI.LocalScript.lua` | plays on death |

## ⚙️ Key tuning knobs (top of `MazeGenerator.Script.lua`)

| Knob | Does |
|---|---|
| `GRID` | maze size in cells (1 cell = 24 studs) |
| `OPENNESS` / `NOISE_SCALE` / `PLAZA_T` | corridor-vs-open-room balance |
| `PIT_ZONES` / `PIT_ZONE_CELLS` / `PIT_HOLE` / `PIT_GAP` | pit room count/size/hole layout |
| `FLICKER_CHANCE` / `DEAD_CHANCE` | fraction of lights that flicker / are broken |
| `SEED` | set a number for the same maze every run |

Entity difficulty lives at the top of `EntityAI.Script.lua`
(`SIGHT_RANGE`, `SIGHT_ANGLE`, `HEAR_RANGE`, speeds).

## 🗺️ Roadmap

**Done**
- [x] Procedural maze — corridors, plazas, pit rooms, centered elevator
- [x] Round loop — elevator intro, one life, win/lose
- [x] Entity AI — sight (cone + close-range) · hearing footsteps · frame-tight chase · pit avoidance
- [x] Puzzle win — fuses → fuse boxes → levers → exit _(placeholder shapes; model them)_
- [x] Clutch — a fallen teammate's lever latches on, no more 10s sync
- [x] Audio hooks — ambience, breathing, footsteps, entity, alert, jumpscare _(drop in asset IDs)_
- [x] **Player fog** — limited view distance (Atmosphere removed, tight legacy fog)
- [x] Pit falls kill · Entity can't get stuck in / enter pit fields

**Next**
- [ ] **Lever status lights** — each lever shows a row of lights for ALL levers, so
      you can read which are already on/off from any lever
- [ ] **Fuse-box → lever wire** — a visible cable/marker linking each box to its
      lever, to follow for navigation
- [ ] **More decor**
- [ ] **Stage hazard** — Entity can throw objects at players stranded on pit beams
- [ ] **No interacting through walls** — ProximityPrompts require line of sight
- [ ] **Flashlight battery** — drains with use / limited, not always-on
- [ ] **Stamina** — sprint is limited, not unlimited
- [ ] Level 2 (the exit currently just wins)
- [ ] Spectate teammates while dead
- [ ] Custom Entity model + walk animation _(fixes the visual "gliding")_
