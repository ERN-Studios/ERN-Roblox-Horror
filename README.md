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
  beams between them. Falling in counts as your death. The Entity can't walk in —
  but if it spots you out there it **roars and shoves you off the beams**, so the
  void is a risky shortcut, not a safe haven
- **Win by solving the puzzle** (fuses → boxes → levers → exit — see below).
  There is **no timer**. The round ends only when the party escapes (**win**) or
  everyone is dead (**lose**). You're never told how many teammates are still alive.

## ⌨️ Controls

| Key | Action | Effect |
|---|---|---|
| `WASD` | Walk | quiet — the Entity hears it at medium range |
| `Left Shift` | Sprint | **loud** — limited stamina (no bar), can't sprint when exhausted |
| `Left Ctrl` | Sneak | slow + silent walk (there's no crouch pose) |
| `F` | Flashlight | see further — but limited **battery**; dies when drained |
| `Q` / `E` | Spectate | while dead, take a teammate's full first-person POV (you see their flashlight); cycle survivors |
| — | Jump | disabled. The beams are the only way across the pits |

First person is forced. The cursor is hidden. There is no map and **no HUD**.
Both limits are felt, not shown: **stamina** cuts your sprint out when it's spent,
and the **flashlight** warns you it's low by flickering — one blink at 50%, a few
at 25% — before it dies.

**Dev cheats** (`DevCheats.LocalScript` — testing only, remove before release):
`B` toggles ESP (fuses / boxes / levers / exit / entity glow through walls),
`V` toggles noclip fly (WASD + Space/Ctrl), `P` pauses/unpauses the Entity,
`I` toggles immunity to the Entity's yell push-back. Restrict via `ALLOWED_NAMES`
or delete. `P` and `I` need the `DevControl` RemoteEvent.

## 🗂️ Repository layout

The folder structure mirrors the **Roblox Studio Explorer** 1:1 — every file
states at the top exactly where it gets pasted.

```
ReplicatedStorage/
  Remotes/                  ← RemoteEvents (objects, not scripts — see the .txt files)
ServerScriptService/
  MazeGenerator.Script.lua      procedural maze, pit zones, elevator, lighting
  GameManager.Script.lua        round loop, one-life rule, elevator doors
  EntityAI.Script.lua           sight/sound hunting, chase, lunge, pit yell
  EntityAnimation.Script.lua    walk/run/idle + yell animation (fires on PlayYell)
  EntityKill.Script.lua         touch = death + jumpscare
  FlashlightSync.Script.lua     server-side flashlight state (Entity sight bonus)
  AvatarNormalize.Script.lua    forces every player to the default avatar size
  PuzzleManager.Script.lua      fuses → fuse boxes → levers → exit (the win)
  NoiseRegistry.ModuleScript.lua  footstep noise bookkeeping
StarterPlayer/StarterPlayerScripts/
  NoiseReporter.LocalScript.lua      movement state → noise events
  FlashlightController.LocalScript.lua  handheld two-cone flashlight
  SoundController.LocalScript.lua       ambience, proximity breathing, footsteps
  RoundUI.LocalScript.lua            round status bar
  PuzzleUI.LocalScript.lua           objective + fuse counter
  SpectateController.LocalScript.lua spectate teammates while dead (Q/E)
  EntityShakeController.LocalScript.lua screen shake — trembles when it lurks near, stomps when it chases
  JumpscareUI.LocalScript.lua        death flicker/shake (+ optional image/sound)
  DevCheats.LocalScript.lua          TESTING ONLY — ESP, noclip fly, entity pause,
                                     push immunity, unlimited battery/stamina (U, whitelisted)
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
   (and `DevControl` if you use the dev cheats) — all RemoteEvents, names are
   case-sensitive — see the `.txt` files in `ReplicatedStorage/Remotes/`
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
| GameManager | `ELEVATOR_TIME` | `2` | `19` (matches the elevator sound) |

## 🎨 Textures

All decals are **our own uploads** (source PNGs in [`textures/`](textures/)).
To change one: upload the PNG via Studio's Asset Manager → copy the asset ID →
paste it into the matching `*_TEXTURE` config at the top of
`MazeGenerator.Script.lua`. Decal IDs and image IDs both work — the script
resolves them automatically at server start.

Single-ID slots: wall · floor · ceiling tile · lit light fixture · dead light
fixture · elevator walls/floor/doors.

**Plug-and-play decal lists** (each holds up to **5 variants**, picked at random;
leave empty = nothing generates):
- `MOLD_TEXTURES` — grime hanging from the **top of walls** and wrapping the top
  of **every pit shaft**. Transparent PNG, mold at the image top.
- `STAIN_TEXTURES` — stamped flat on random floor tiles, **anywhere** on the carpet.
- `ARTWORK` — stamped **dead-centre on a wall** (middle height + middle of the
  panel), so it reads like hung art. `ARTWORK_SIZE` controls the stamp size.

Alignment notes:
- **Ceiling**: one image = one office tile; the grid auto-aligns so every light
  panel replaces exactly one tile
- **Mold**: transparent PNG, mold hanging from the image top — tiled once over
  the wall height, applied to random walls and around every pit shaft

### 🪑 Decor (furniture props)

Furniture is **built from primitive Parts** in `MazeGenerator.Script.lua`
(`DECOR_BUILDERS`) — always upright and correctly sized, no Toolbox loading
(those IDs mostly failed to load / imported sideways). Props: **chair, table
(+ telephone on top), cardboard box, printer/fax, grandfather clock** (its two
hands spin to a random time per clock). Placement:
- **Chairs / tables** stand alone in the middle of open cells; **one chair is
  guaranteed in the plaza**.
- **Boxes / printers / grandfather clocks** stand against a wall, facing in.

Knobs:
- `DECOR_DENSITY` — master rarity (per eligible cell). Scales with `GRID`, so
  lower it for the big production maze.
- per-prop `height` — each object's size in studs.
- `DECOR_SCALE_JITTER` — random ± size wobble per prop (`0.2` = up to ±20%), for
  that off-kilter generated look.
- `DECOR_MIN_GAP` — same-type props stay more than this many cells apart (`2` =
  no two chairs / two printers clustering).
- `DECOR_COLLIDE` — `true` = solid for players. Either way the Entity **passes
  through** all decor (a `Decor` collision group), so it never gets stuck on it.

To restyle a prop, edit its builder in `DECOR_BUILDERS`; to add a new one, add a
builder + a `PROPS` entry.

## 🧩 How to win (the puzzle)

Scales with the party — **per player: 2 fuses spawn, 1 fuse box, 1 lever.**

1. **Find fuses** on the ground (glowing bricks). Twice as many spawn as needed.
2. **Insert them into the fuse boxes** (one per player, `FUSES_PER_BOX = 1`).
   Boxes are **mounted on walls**. Every insert makes it worse: lights flicker
   more, the entity speeds up, and **the entity appears in that area** (~10 cells
   off — near, not on top of you).
3. **All boxes full → the levers unlock** (also wall-mounted, near the map edges,
   spread far apart, so the party has to **split up**). Each box has a **coloured
   wire** on the floor leading to its lever — follow it to navigate. Once the
   boxes are done there's a chance every 10s of **ALERT** (red pulsing lights +
   siren) — 50% the first roll, 5% after.
4. **Flick every lever within 10 seconds of each other.** Each lever wears a
   **column of status lights** (one per lever, on the side of the plate) showing
   every lever's on/off, so you can read progress from any of them. **Clutch:** if a teammate dies, the 10-second sync is
   dropped — levers become flip-and-stay, so survivors can pull them at their own
   pace (they still have to find and pull them all).
5. **All levers together → the lights drop** (a few stay faintly on; the entity
   becomes a blinking beacon), the **EXIT opens in the outer wall** with the
   entity guarding it. Reach the exit to **win** (level 2 later).

The HUD shows **status only** — fuses carried and boxes on. It does **not**
explain the objective; players are briefed beforehand and figure the rest out.

Placeholder shapes for now — model the `Fuse` / `FuseBox` / `Lever` / `Exit`
later, just keep the names. Tuning is at the top of `PuzzleManager.Script.lua`
(`FUSES_PER_BOX`, `SPAWN_MULT`, `LEVER_WINDOW`, `ENTITY_AREA_CELLS`, alert chances).

## 🔊 Audio

**Every sound ID lives in one place** — the slots at the top of
`SoundController.LocalScript.lua`. Paste your asset IDs there; any left `""` is
silent.

| Slot (`SoundController`) | Behaviour |
|---|---|
| `AMBIENCE_SOUND` | constant background drone (2D) |
| `BREATHING_SOUND` | **your own** winded breathing — fades in below 50% stamina, lingers until full |
| `FOOTSTEP_WALK` / `FOOTSTEP_RUN` | your own steps; sneaking is silent |
| `ALERT_SOUND` | plays during ALERT (red-lights) mode |
| `ENTITY_SOUND` | the Entity's looping growl, **positional** (you hear which way) |
| `ENTITY_STEP_WALK` / `ENTITY_STEP_RUN` | the Entity's footstep thumps, **positional** (walk vs chase pace) |
| `IDLE_SOUNDS` (×3) | random idle vocalisations while it roams, **positional** (fill 1–3) |
| `CHASE_SOUND` | loops while it's actively chasing you, **positional** (off during a yell) |
| `LUNGE_SOUND` | telegraph cue as it winds up a pounce, **positional** |
| `YELL_SOUND` | the Entity's roar when it shoves you off a pit beam, **positional** |
| `DEATH_SOUND` | the scream **alive** players hear when someone dies, positional at the kill (quieter further away) |
| `JUMPSCARE_SOUND` | the **dying** player's own jumpscare sound (2D, only they hear it) |

(The jumpscare's optional full-screen **image** stays in `JumpscareUI.LocalScript.lua`
as `JUMPSCARE_IMAGE` — that's a visual, not a sound.)

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
- [x] Entity AI — sight (cone + close-range) · hearing footsteps · frame-tight chase
- [x] **Chase upgrades** — pathfinds around corners (no more wall-humping), walks
      nearer room centres, and **lurks toward open room middles** when idle
- [x] **Lunge** — freezes to telegraph (0.5s), then pounces to where you stand and stops
- [x] **Pit "yell"** — can't cross the beams, so it walks to the edge, faces you,
      roars, and shoves you off with a steady push **you can walk against**
- [x] Puzzle win — fuses → fuse boxes → levers → exit _(placeholder shapes; model them)_
- [x] Clutch — a teammate's death drops the 10s lever sync (flip-and-stay)
- [x] **Player fog** — limited view distance (Atmosphere removed, tight legacy fog)
- [x] Pit falls kill · Entity can't get stuck in / enter pit fields
- [x] **Lever status lights** · **fuse-box → lever wire** (rides the floor/beams)
- [x] **No interacting through walls** — ProximityPrompts require line of sight
- [x] **Flashlight battery** (flicker warnings) · **Stamina** (no bar, felt)
- [x] **Spectate teammates while dead** (Q/E)
- [x] **Custom Entity model** — walk/run animations in, self fill-light so it isn't
      pure black; yell/lunge animation **slots ready** (paste IDs in EntityAnimation)
- [x] **Audio hub** — every sound id in one place (`SoundController`): ambience,
      winded breathing, footsteps, alert, entity growl/idle/chase/lunge/yell/steps,
      death scream (alive, positional) + dying player's own jumpscare
- [x] **Dev cheats** — ESP · noclip fly · pause Entity (`P`) · push immunity (`I`)
- [x] **Decor** — furniture props (chairs, tables + phone, boxes, printers,
      grandfather clocks) at low tunable density; 5-slot mold/stain/artwork lists
- [x] **Wires cross pits** — a run that would pass over a hole field climbs the
      wall, runs across the ceiling, and drops down the far side
- [x] **Screen shake** — faint tremble as the Entity lurks nearer, heavy footstep
      stomps while it chases (`STOMP_INTERVAL` knob to sync with the run sound/anim)
- [x] **Wall-slide chase** — the Entity projects its heading along a wall that's
      ahead and rounds the corner instead of grinding its face into it
- [x] **Exit → safe room** — stepping through the exit drops you in a sealed
      elevator-style room the Entity can't reach (placeholder for the level-2 start)
- [x] **Escape flow** — first escapee triggers the GREEN GUIDE LINE (ceiling
      lights along the actual route elevator → exit) + a top-bar notice; escapees
      spectate the players still inside; round ends when everyone's out or dead
- [x] **Full audio pass** — footstep/breathing loops (fade in/out, run = own clip),
      flashlight click, jumpscare image+scream synced with fade-to-black death
      sequence, whole-map death scream, spot sting + chase music with 5s memory fade
- [x] **Glowing eyes** — neon EyeL/EyeR dots (parts or attachments, auto-found)
      with a directional glow where it faces; amber roaming → red when hunting
- [x] **Adrenaline** — stamina lasts 3× while the Entity is on you (+ linger)
- [x] **Camera feel** — subtle walk head-bob (stronger running) + entity shake
- [x] **QoL** — scattered elevator spawns, forced default avatar size, teammate
      flashlights visible, themed stamina bar, battery widget, Gotham UI
- [x] **Dev cheats** — + unlimited battery/stamina (`U`, whitelisted)

**Next** _(the current todo)_

_🗺️ Map / Level Design_:
- [ ] Create the lobby
- [ ] Environmental details (`MazeGenerator.Script.lua`, 5 ID slots each — plug in and it works):
  - [ ] Mold — `MOLD_TEXTURES`
  - [ ] Stains — `STAIN_TEXTURES`
  - [x] Wall art — `ARTWORK` (10 wall writings / doodles in)

_🎨 Graphics / 3D Models_:
- [ ] Create player models

_🎬 Animations_:
- [ ] Lunge animation — `LUNGE_ANIM_ID` in `EntityAnimation`

_Empty sound slots left_ (`SoundController.LocalScript.lua`):
- [ ] Lunge telegraph — `LUNGE_SOUND`
- [ ] Entity footstep — run/chase — `ENTITY_STEP_RUN`
- [ ] Entity idle vocalisations ×3 — `IDLE_SOUNDS`

_Later_:
- [ ] More decor variety · Level 2 (exit currently loops into the safe room)
