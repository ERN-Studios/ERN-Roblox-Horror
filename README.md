# ERN Backrooms Test

A round-based **Backrooms-inspired horror game** for Roblox. You and your party wake
up in an elevator. The doors open into an endless yellow maze. One of you makes it
back — or none of you do.

Built entirely with procedural generation: every round is a new maze.

## 🎮 Gameplay

- Everyone spawns **inside an elevator** — doors shut, countdown, doors slide open
- **One life per round.** Die and you spectate until the round ends
- The **Entity** hunts by sight and sound: sprinting is loud, crouching is silent
- Flickering lights ahead of it can betray its approach — or just be a dying tube
- **Pit rooms**: huge open halls where the floor is a grid of holes with narrow
  beams between them. Falling in counts as your death. The Entity can't enter —
  balancing over the void is the only safe haven
- Everyone dead → **you lose** · survive the timer → **you win** · back to the
  elevator, next round

## ⌨️ Controls

| Key | Action | Effect |
|---|---|---|
| `WASD` | Walk | quiet — the Entity hears it at medium range |
| `Left Shift` | Sprint | **loud** — audible across the maze |
| `Left Ctrl` | Crouch | silent, slow |
| `F` | Flashlight | see further — but the Entity sees YOU much further |
| — | Jump | disabled. The beams are the only way across the pits |

First person is forced. The cursor is hidden. There is no map.

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
  NoiseRegistry.ModuleScript.lua  footstep noise bookkeeping
StarterPlayer/StarterPlayerScripts/
  NoiseReporter.LocalScript.lua      movement state → noise events
  FlashlightController.LocalScript.lua  handheld two-cone flashlight
  RoundUI.LocalScript.lua            round status bar
  JumpscareUI.LocalScript.lua        death flicker/shake (+ optional image/sound)
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
   `ReportNoise`, `ToggleFlashlight`, `Jumpscare`, `RoundStatus` (all RemoteEvents,
   names are case-sensitive — see the `.txt` files in `ReplicatedStorage/Remotes/`)
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
dead light fixture · elevator walls/floor/doors.

Alignment notes:
- **Ceiling**: one image = one office tile; the grid auto-aligns so every light
  panel replaces exactly one tile
- **Mold**: transparent PNG, mold hanging from the image top — tiled once over
  the wall height, applied to random walls and around every pit shaft

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

- [ ] **Puzzle exit** — win by escaping, not just surviving the timer
- [ ] Stamina system (sprint has a cost)
- [ ] Ambient audio — fluorescent buzz, distant drones, jumpscare sound
- [ ] Spectate teammates while dead
- [ ] Custom Entity model + animations
