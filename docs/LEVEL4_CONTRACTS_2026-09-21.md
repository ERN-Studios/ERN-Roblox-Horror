# Level 4 — THE QUIET SUBURBS: contracts, install order and smoke test

Written 2026-09-21 for the art/audio polish hand-off and for the lead who has to
create these scripts in Studio and run them for the first time.

**Status: milestones 1 and 2 only** — a walkable blockout plus one end-to-end
prototype of house / task / entity. This is not a finished level and it must not
be described as one.

**Update 2026-09-22 — installed and run.** All twelve scripts exist in Studio
(section 1 is history now: the sync tools push them like any other script) and
the level has been played solo in Studio on seeds 101 (CLOSE) and 202 (TERRACE):
three signals → three cabinet controls in order → the transit door → `Escaped`,
and one real Neighbour kill with the `THE NEIGHBOUR GOT YOU` card. The in-Studio
suite reports plan 163 / brain 18 / world 66 checks, 0 failures. Facade fixes of
the same day (marked `FACADE_POLISH_20260922`, `CALM_ARRIVAL_20260922`,
`EXIT_POINTER_20260922`, `LEVEL4_DEV_RETRY_20260922`): the roof wedge now peaks at
the ridge (19.5 studs over the slab at z ±0.1, 14.2 at the eaves), the window
units stand 0.4 studs PROUD of the outer wall (they were 0.2–0.6 studs inside
it), the house scheduler waits `HouseStates.CalmLeadSeconds` (24 s, measured
25.4 s) after `RoundActive` before the first house leaves SAFE, the client's
danger grade only follows a threat to THIS player (Neighbour ALERT/CHASE on them,
or the house they stand in), `Level4_ExitPosition` is the trigger's own centre
and the server sweeps living roots inside the open trigger, and a dev round that
ends without escape raises `Level4DevRoundEnded` on the player instead of a
`RetryGuideLevel` beam to a bay that does not exist. Evidence and images:
`docs/CODEX_POLISH_HANDOFF.md`, `artifacts/claude-20260922/screens/`.

Everything below this line is the 2026-09-21 text; where it says "unverified",
read the 2026-09-22 handoff for what has since been run.

**Level 4 is dev-only.** The lobby gate stays "coming soon". A round can only
start when `workspace.Level4DevEnabled == true` **and** every player present
passes `DevAccess.IsAllowed`. `Routing.MaxLevel` is still 3 and Level 3 still
offers no Continue to a normal party.

---

## 1. Scripts to create in Studio, in dependency order

Create each as the listed class at the listed Explorer path, paste the repo file
of the same name, then add its manifest item with
`tools/studio_source_contract.py` (`sha256_of` / `canonical_bytes`). New scripts
cannot be pushed by the sync tools; they have to exist in Studio first.

| # | Explorer path | Class | Repo file |
|---|---|---|---|
| 1 | `ServerScriptService/Level 4 Systems` | **Folder** | — |
| 2 | `ServerScriptService/Level 4 Systems/Level 4 Configuration` | ModuleScript | `ServerScriptService/Level 4 Systems/Level 4 Configuration.ModuleScript.lua` |
| 3 | `.../Level 4 Plan Generator` | ModuleScript | same folder |
| 4 | `.../Level 4 Neighbour Brain` | ModuleScript | same folder |
| 5 | `.../Level 4 World Builder` | ModuleScript | same folder |
| 6 | `.../Level 4 Objective Controller` | ModuleScript | same folder |
| 7 | `.../Level 4 Neighbour Controller` | ModuleScript | same folder |
| 8 | `.../Level 4 Round Adapter` | ModuleScript | same folder |
| 9 | `.../Level 4 Test Suite` | ModuleScript | same folder |
| 10 | `ServerScriptService/Level4Generator` | ModuleScript | `ServerScriptService/Level4Generator.ModuleScript.lua` |
| 11 | `StarterPlayer/StarterPlayerScripts/Level 4 Lighting Controller` | **LocalScript** | `StarterPlayer/StarterPlayerScripts/...` |
| 12 | `StarterPlayer/StarterPlayerScripts/Level 4 Objective UI` | **LocalScript** | `StarterPlayer/StarterPlayerScripts/...` |

Dependency order matters: 6 requires 2, 7 requires 2/4/6, 8 requires 2/3/5/6/7,
10 requires 8. Create 1–9 before 10, or `Level4Generator`'s `WaitForChild` will
hang the first `require`.

Three existing scripts also changed and must be pushed with the usual audit:

- `ServerScriptService/GameManager.Script.lua`
- `ServerScriptService/Round Completion Routing.ModuleScript.lua`
- `StarterPlayer/StarterPlayerScripts/Round Entry Client.LocalScript.lua`

All three hunks are marked `LEVEL4_DEV_GATE_20260921`.

---

## 2. The dev gate

Three independent locks, all of which must be open:

1. `workspace:SetAttribute("Level4DevEnabled", true)` — checked by
   `Routing.Level4DevAttribute` in GameManager and asserted again in
   `Level 4 Round Adapter.Build()`.
2. Every player in the group passes `DevAccess.IsAllowed` — GameManager's
   `devCeiling(group)`. A single non-developer in the session drops the ceiling
   back to `Routing.MaxLevel`, so a normal player cannot be carried in.
3. `ServerStorage.Level4DevStart:Invoke()` — the only entry point. It is a
   BindableFunction with no remote in front of it, so no client can reach it.

Level 3 → Level 4 Continue uses the same ceiling: `Routing.NextLevelTo`.

---

## 3. Starting a Level 4 round in Studio

```lua
-- Command bar, on the SERVER of a running play session:
workspace:SetAttribute("Level4DevEnabled", true)
-- optional: pin the map. 0/negative/NaN mean "random"; only >= 1 pins.
workspace:SetAttribute("Level4Seed", 101)
print(game:GetService("ServerStorage").Level4DevStart:Invoke())
```

`Invoke()` returns `true`, or `false` plus one of `RESERVED_SERVER`,
`DISABLED`, `BUSY`, `NOT_DEVELOPER`, `NO_PLAYERS`.

The round then runs GameManager's ordinary path: loading cover → seven
`elevator` ticks → doors open → `RoundActive = true`.

---

## 4. Derived geometry — the numbers everything is built from

`Level 4 Configuration.Body` holds the two body envelopes; `Configuration.Derived`
computes every opening from them, and both the offline test and the in-Studio
suite re-derive them rather than reading them back.

| Quantity | Value | Derivation |
|---|---:|---|
| Player height / width / pass gap | 5 / 2 / 2 | R15 at default scale |
| Two players abreast | **6.0** | `2 * 2 + 2` |
| Neighbour height | **9.5** | authored; just under twice a player |
| Neighbour shoulder / arm swing / jamb clearance | 3.4 / 0.8 / 1.2 | authored |
| Neighbour widest pass | 5.4 | `3.4 + 0.8 + 1.2` |
| **DoorWidth** | **6.0** | `max(6.0, 5.4)` — the player pair decides |
| **DoorHeight** | **10.5** | `9.5 + 1.0` head clearance |
| PassageWidth / StairWidth | 6.0 | = DoorWidth |
| InteriorCeiling | 13.0 | `Lots.StoreyHeight`, must exceed DoorHeight |
| StairRise / StairRun | 0.9 / 1.6 | under the R15 step limit |
| **AgentRadius** | **2.7** | `(3.4 + 0.8) / 2 + 1.2 / 2` |
| **AgentHeight** | **10.0** | `9.5 + 0.5` |

**If the art pass changes the rig, change `Configuration.Body` and let the rest
follow.** Every door, passage, stair and PathfindingService agent is computed
from those five numbers; hard-coding a replacement door width will silently
break the navigation envelope.

Street and lot geometry (plan coordinates, relative to
`Configuration.WorldOrigin = (12400, 24, 0)`):

| Quantity | Value |
|---|---:|
| Main street length (SW→SE) | 420 |
| Block depth (Main→Back Lane) | 220 |
| Carriageway half width | 12 |
| Pavement width | 6 |
| Service passage length / half width | 74 / 9 |
| House footprint (W × D) | 30 × 34 |
| Storey height / roof height | 13 / 7 |
| Front yard depth | 18 |
| Lot centre offset from street centreline | 53 (`12 + 6 + 18 + 17`) |
| Hedge height / thickness | 3.2 / 1.6 |
| Fence height | 2.4 |
| Mailbox height | 4.2 |

---

## 5. Instance paths the art pass must keep

Everything lives under `workspace["Level 4 Generated World"]`, except three
compatibility markers that GameManager waits on at the Workspace root.

### 5.1 Workspace root (do not rename — GameManager resolves these by name)

| Path | Why |
|---|---|
| `workspace.Elevator` (Model) with children `DoorL`, `DoorR` | `connectElevator()` tweens these two by name |
| `workspace.ElevatorSpawn` (BasePart, **CanCollide true**) | `placeSafelyInElevator` places the party on it; `Round Entry Client` rays down onto it |
| `workspace.MazeStart` (BasePart) | `ensureWorld` waits on it |

All three carry `Level4_CompatibilityMarker = true`; Cleanup sweeps exactly
those.

### 5.2 Houses

Each house is `World.House_<LotId>`, a Model with:

| Child | Attribute / contract |
|---|---|
| `HouseFloor` | the Model's `PrimaryPart`. The HUD measures house distance from it |
| `HouseWallSide` ×2, `HouseWallBack`, `HouseWallFront` ×2, `HouseDoorLintel` | shell |
| **`DoorFrame`** | `Level4_DoorFrame = true`, `Level4_DoorWidth = 6.0`, `Level4_DoorHeight = 10.5`. The Round Adapter asserts the width matches `Derived.DoorWidth` |
| `HouseRoof` ×2 (WedgePart) | dark roof, ridge along x |
| `HouseWindow` ×4 | facade windows |
| `HouseCeiling`, **`InteriorVolume`** | `InteriorVolume` carries `Level4_InteriorVolume = true` and is the box `ObjectiveController.IsSheltered` tests a player against. **This is the hiding mechanic.** Resizing it changes what counts as safe |
| `InteriorPartition` ×1–2, `InteriorStair` ×8, `InteriorLanding` | interior module 1/2/3 |
| `Sofa`, `CoffeeTable`, `EmptyPictureFrame` | furniture; `EmptyPictureFrame` carries `Level4_EmptyFrame` |
| `Hedge` ×2, `Fence` ×2, `Path` | yard |
| **`Mailbox`** | `Level4_Mailbox = true`, `Level4_MailboxFacesStreet` (false = the anomaly) |
| **`PorchSignal`** | `Level4_PorchSignal = true`. Colour IS the house state; a `PointLight` named `Level4Light` hangs off it on enterable houses |

Model attributes: `Level4_LotId`, `Level4_Zone` (1–3), **`Level4_HouseState`**
(`SAFE` / `WARNED` / `DANGEROUS` — replicated, read by the HUD).

### 5.3 Anomaly sockets

One per changed house, named `AnomalySocket` (except the reversed mailbox, which
stays named `Mailbox`), carrying `Level4_AnomalySocket = true`,
`Level4_Anomaly = <kind>` and `Level4_LotId`.

| Kind | What it is now | What the art pass replaces it with |
|---|---|---|
| `ExtraWindow` | a fifth facade window | a real extra window |
| `WrongNumber` | a plate with a SurfaceGui reading `13B` | a house-number plate out of the street's sequence |
| `ReversedMailbox` | the `Mailbox` part rotated 180° | same, modelled |
| `DrawnCurtains` | a fabric slab filling one window | curtains drawn on one side only |

The anomaly is the readable "this house changed" tell **and** the FacadeCompare
clue. It must stay legible from the pavement.

### 5.4 Signal fixtures

Three, one per zone, inside/beside the variant's chosen house:

| Instance | Attributes |
|---|---|
| `SignalFixture` | `Level4_SignalIndex` (1–3), `Level4_SignalKind` (`FacadeCompare` / `Broadcast` / `Sample`) |
| `Level4Prompt` (ProximityPrompt, child of the fixture) | `Level4_SignalIndex` |
| `SignalClueScreen` / `SignalClueReadout` / the fixture itself | `Level4_SignalClue = <index>` |

**Every signal must keep a VISUAL clue instance.** The Round Adapter and both
test suites refuse a signal without one: no task in this level may require
hearing or a microphone.

### 5.5 Finale — `World.ExtractionBeacon`

| Instance | Attributes |
|---|---|
| `ShelterRoof`, `ShelterBack`, `ShelterBench`, `ShelterSign` | the bus stop |
| `SignalCabinet` | `Level4_Cabinet = true` |
| `CabinetStatus` | `Level4_CabinetStatus = true` — red → amber (unlocked) → green (open) |
| `CabinetControl1..3` | `Level4_CabinetControl = <index>`, each with a `Level4Prompt` that starts **disabled** |
| `ExitGate` | `Level4_ExitGate = true`; slides clear when the exit opens and never closes inside a round |
| `EscapeTrigger` | `Level4_EscapeTrigger = true`; `CanTouch` **false** until the exit opens. Only a living root INSIDE this box grants `Escaped` |
| `ExitSafeSpawn` | `Level4_ExitSafeSpawn = true`; escapees are parked here in six slots |

### 5.6 Landmarks and boundary

| Instance | Notes |
|---|---|
| `World.SignalTower` | `Level4_Tower = true`. Legs, cylindrical `TowerTank` (the Model's PrimaryPart), `TowerBeacon` + one counted light. Height 92, leg spread 22 |
| `World.CentralGreen` | `GreenSurface`, `Bench`, `PlaygroundFrame` ×3, `PhoneBox` |
| `World.Boundary` | `BoundaryFacade` / `BoundaryRoof` repeated rows, `BoundaryHill` ×4, and four `BoundaryBlocker` walls (`Level4_Blocker = true`, invisible, **CanQuery true** so the AI sees the world's edge) |
| `World.PatrolNodes` | `PatrolJunction_*`, `PatrolMailbox_*`, `PatrolPorch_*`, each with `Level4_PatrolKind` = `Street` / `Mailbox` / `Porch`. This is the AI's patrol set; adding or moving nodes changes where it walks |
| `World.NeighbourRuntime` | the rig's parent. Excluded from every line-of-sight ray |

---

## 6. The Neighbour — rig contract

Built by `Level 4 Neighbour Controller.buildRig` as `NeighbourRuntime["The Neighbour"]`.
A replacement model must keep **every name below**; the AI moves the root and
poses the rest by name, and the audio pass attaches to the two Attachments.

| Part | Size (studs) | Role |
|---|---|---|
| `HumanoidRootPart` | 2 × 2 × 1 | the Model's `PrimaryPart`, invisible, anchored, moved by CFrame. Frame sits at the hips |
| `Torso` | 3.4 × 3.42 × 1.5 | |
| `Head` | 1.6 × 1.9 × 1.6 | carries the constant unnatural tilt (0.22 rad pitch, 0.14 rad roll) |
| `Mask` | 1.2 × 1.2 × 0.2 | matte glass face; sits 0.85 studs in front of the head |
| `UpperArmLeft` / `UpperArmRight` | 0.7 × 1.9 × 0.7 | |
| `ForearmLeft` / `ForearmRight` | 0.6 × 2.85 × 0.6 | **too long on purpose** — 1.5× the upper arm. This is the silhouette |
| `LegLeft` / `LegRight` | 0.8 × 4.18 × 0.8 | |

Overall envelope: height **9.5**, widest point **4.2** (`shoulder + arm swing`).
Published on the Model as `Level4_RigHeight` / `Level4_RigWidth`.

Attachments, both on `HumanoidRootPart`:

| Attachment | Local position | For |
|---|---|---|
| `FootstepAttachment` | `(0, -4.75, 0)` | footstep emitters |
| `HeadAttachment` | `(0, +4.37, 0)` | breath / vocal emitters |

Detector registration (no detector change needed — this is
`ZyntraDetectorSensing`'s documented extension point):
`CollectionService` tag `ZyntraDetectableEntity`, attributes
`ZyntraDetectorLevel = 4` and `ZyntraDetectorActive = true`.

**There is no Humanoid.** `ZyntraDetectorSensing.IsLiving` treats a Humanoid-less
model with a PrimaryPart as alive, which is the intended behaviour here. Adding a
Humanoid later would make its Health authoritative.

### 6.1 Animation slots and reference speeds

The rig is posed procedurally today. The state is published as
`Level4_NeighbourAnimation` on the `Level 4 State` folder; bind real tracks to it.

| Slot | Published when | Reference speed (studs/s) | Notes |
|---|---|---:|---|
| `Idle` | `ALERT` | 0 | The telegraph. The rig **stops and turns** to face the player for `AlertSeconds` = 1.1 s. Must read as "it has noticed you" from 40 studs |
| `Walk` | `PATROL`, `RETURN` | 7 / 11 | slow, deliberate, long stride |
| `Search` | `INVESTIGATE`, `SEARCH` | 13 / 15 | head sweeps; stops at porches |
| `Chase` | `CHASE` | **24** | deliberately under the player sprint of 26 (`NoiseReporter`) — Level 4 is decided by route, not by a race |
| `Attack` | published for one `AttackSerial` bump | — | windup 0.5 s, recovery 1.2 s. The hit lands at the END of the windup, re-validated |

Turn rate 3.2 rad/s. One movement frame is clamped to **2.2 studs**
(`MaximumStepStuds`) and 0.05 s, so a server hitch can never move the rig through
a wall or onto a player.

### 6.2 Behaviour, as rules

All of it lives in `Level 4 Neighbour Brain` (pure, offline-tested). Six states:

```
PATROL --noise--> INVESTIGATE --arrived--> SEARCH --timeout--> RETURN --> PATROL
   \                                          /
    \--close detection--> ALERT --1.1s--> CHASE --contact lost--> SEARCH
                            \--line broken--> SEARCH
```

- **CHASE is never entered directly.** Only through ALERT, and ALERT needs a
  real detection: in the 110° cone, with line of sight, within **42 studs**.
- A player seen beyond 42 studs (up to the 78-stud vision range) is a **trace**:
  it produces a SEARCH at the sighting, never a chase.
- Noise comes from `NoiseRegistry` and is investigated **at the noise position**.
  The AI is never handed a player position it did not earn through sight.
- Breaking line of sight for 3.5 s ends a chase — **1.19 s** if the player is
  crouched (`QuietContactMultiplier` 0.34). Crouch is separately zero loudness in
  `NoiseRegistry`, so a crouching player emits no noise to investigate either;
  there is deliberately no second hearing multiplier on top of that.
- A player inside a **SAFE** house's `InteriorVolume` is sheltered: not seen, not
  targeted, not attackable.
- Attacks re-test range, shelter, `PlayerProtection` and line of sight at the end
  of the windup. No damage through a wall, ever.
- Doors delay, never deadlock: no progress for `DoorWaitSeconds` = 2.5 s and the
  AI takes a different goal entirely.

Debug readbacks on `ReplicatedStorage["Level 4 State"]`:
`Level4_NeighbourState`, `Level4_NeighbourAnimation`,
`Level4_NeighbourTargetUserId`, `Level4_NeighbourPathStatus`,
`Level4_NeighbourSpeed`, `Level4_NeighbourReason`,
`Level4_NeighbourGoalX/Z`, `Level4_NeighbourNoiseX/Z`,
`Level4_NeighbourAttackSerial`. Also `Level4_NeighbourState` on the rig Model.

---

## 7. Materials, colours and textures

No texture, decal, image or sound asset id is introduced anywhere in Level 4.
Every surface is a stock `Enum.Material` plus a `Color3`.

| Token | RGB | Used for |
|---|---|---|
| `FadedCream` | 226, 216, 190 | house body |
| `DustyYellow` | 214, 194, 132 | house body |
| `BlueGrey` | 163, 176, 184 | house body, shelter |
| `DarkRoof` | 56, 56, 62 | every roof |
| `Hedge` | 78, 112, 68 | hedges |
| `Lawn` | 104, 156, 88 | **one flat green everywhere** — the uniformity is the point |
| `Asphalt` | 64, 66, 70 | carriageways |
| `Kerb` | 196, 194, 188 | pavements |
| `Concrete` | 178, 176, 170 | paths, fences, service floor |
| `Timber` | 150, 128, 100 | mailbox, bench, stairs |
| `Hill` | 96, 134, 86 | boundary hills |
| `Interior` | 206, 198, 180 | interior walls/ceilings |
| `InteriorFloor` | 122, 98, 74 | interior floors |
| `Zyntra` | 66, 244, 218 | **restrained** — test equipment only, never street dressing |
| `ZyntraCabinet` | 48, 54, 58 | cabinet, tower, service door |
| `SignalSafe` / `SignalWarned` / `SignalDangerous` | 96,214,128 / 244,186,74 / 214,78,66 | porch signals, cabinet status |

Materials in use: `Grass`, `Asphalt`, `Concrete`, `Slate`, `Metal`,
`DiamondPlate`, `Wood`, `WoodPlanks`, `Plaster`, `Fabric`, `Glass`, `Neon`,
`SmoothPlastic`.

Text is drawn with `SurfaceGui` + `Enum.Font.Code` on parts named `Level4Face`.
Replacing these with real signage is an art-pass job; keep the parent part's name.

**Light budget.** `MaximumDynamicLights = 12`, asserted by the adapter and
measured again by the suite. Current build: one per enterable house porch
(7), plus the cabinet, the exit gate and the tower beacon = **10**. Every light
in the level is created through one helper that sets `Shadows = false`; the suite
fails if any light in the world casts a shadow. Every decorative part has
`CastShadow = false`.

`MaximumWorldDescendants = 12000`, asserted at build time.

---

## 8. Sound slots

**Nothing is wired yet.** Level 4 emits cue NAMES, never asset ids, so an empty
slot is simply silent and never an error.

| Cue name | Fired from | Duration target | Loop | Rolloff min/max (studs) |
|---|---|---|---|---|
| `HouseWarned` | `ClientEvent` `{Type="House", State="WARNED", Cue=...}` | 1.5–2.5 s | no | 12 / 70 — audible on the street outside the house |
| `HouseDangerous` | `ClientEvent` `{Type="House", State="DANGEROUS"}` | 1.0–2.0 s | no | 12 / 70 |
| Neighbour footsteps | `FootstepAttachment` | 0.3–0.6 s per step | no | 18 / 90 |
| Neighbour patrol breath | `HeadAttachment` | 3–6 s | yes | 10 / 45 |
| Neighbour alert | `HeadAttachment`, on `ALERT` | 0.8–1.5 s | no | 25 / 140 — the telegraph must carry |
| Neighbour chase | `HeadAttachment`, on `CHASE` | 4–10 s | yes | 20 / 180 |
| Neighbour attack | `HeadAttachment`, on `AttackSerial` | 0.5–1.2 s | no | 15 / 80 |
| Signal logged | `ClientEvent` `{Type="Signal"}` | 0.5–1.0 s | no | 2D, own-client |
| Beacon unlocked / exit warning / exit open | `ClientEvent` `{Type="Alert"}` | 1–3 s | no | 2D, own-client |
| Ambience: faint wind, distant electrical hum | level-wide | 20 s+ | yes | 2D bed |

Brief's audio rules that the polish pass must honour: no constant music; tails
fade cleanly to zero; outdoor attenuation plus short house reflections rather
than a corridor reverb everywhere; **every critical warning also has a visual
component** (the porch signal and the HUD line already do).

---

## 9. UI strings

All player-facing text is English, Zyntra voice.

| String | Where |
|---|---|
| `Investigate three residential signals. Restore the extraction beacon. Stay quiet.` | briefing; `Configuration.Objectives.BriefingLine`, also published as `Level4_Briefing` |
| `> ZYNTRA RESIDENTIAL TEST SITE` | panel eyebrow |
| `SIGNALS n/3  [#][ ][ ]` | panel headline |
| `BEACON: LOCKED` / `BEACON CONTROLS n/3` / `DOOR OPENS IN n` / `TRANSIT DOOR OPEN` | panel second line |
| `SHELTER: STABLE` / `SHELTER: UNSTABLE -- LEAVE` / `SHELTER: LOST` / `SHELTER: NONE NEARBY` | panel house line |
| `!! YOU HAVE BEEN SEEN` / `!! PURSUIT -- BREAK THE LINE` / `> SOMETHING IS LOOKING` | panel threat line |
| `HOUSE <id> IS GOING DARK -- LEAVE WITHIN 12s` | banner, on WARNED |
| `EXTRACTION BEACON LIVE` / `Three controls at the bus stop. Set them in order.` | banner, at 3/3 |
| `BEACON RESTORED` / `Transit door opens in 6 seconds. Stand clear of the road.` | banner, finale warning |
| `TRANSIT DOOR OPEN` / `Reach the bus stop to extract.` | banner |
| `Investigate` / `SIGNAL 0n  //  ZONE n` | ProximityPrompt |
| `Set` / `BEACON CONTROL 0n` | ProximityPrompt |
| `ZYNTRA REFERENCE / 4 WINDOWS / NUMBER IN SEQUENCE / BOX TO STREET / CURTAINS OPEN` | FacadeCompare board |
| `OFF AIR / SIGNAL 0n`, `OUT OF RANGE`, `LOGGED 0n` | clue faces |
| `ZYNTRA TRANSIT / SERVICE 04` | bus-stop sign |

Team feed lines go through `TeamObjectives.Announce(actor, detail, 4)` and appear
in the existing Objectives style.

---

## 10. What is placeholder

**Everything visual.** Every generated instance carries
`Level4_Placeholder = true`; a descendant scan for that attribute is the complete
art hand-over list, and the suite fails if it finds none.

Specifically placeholder: the whole Neighbour rig (Part-built, no mesh, no
animation tracks, procedural pose), every house and its interior, every window
and curtain, the tower, the bus stop, the cabinet, all signage (SurfaceGui text
in `Enum.Font.Code`), the boundary facades and hills, and every sound slot in
section 8 (all empty).

Not placeholder, and not to be changed without reading section 4: the derived
geometry, the instance names and attributes in section 5, the rig part names and
attachments in section 6, and the light budget.

---

## 11. Studio smoke test

Run in order. Each step names the attribute to watch.

**0. Install.** Create scripts 1–12, push the three changed scripts, restart the
place, start a play session (Server view).

**1. Arm and start.**

```lua
workspace:SetAttribute("Level4DevEnabled", true)
workspace:SetAttribute("Level4Seed", 101)   -- pin, so a failure is reproducible
print(game:GetService("ServerStorage").Level4DevStart:Invoke())
```

Watch, in order:
`workspace.LoadStage` → `LEVEL_4_GENERATING_PLAN` → `LEVEL_4_BUILDING_WORLD` →
`READY`; `workspace.SelectedLevel` → 4; `workspace.WorldGenerated` → true.
`ReplicatedStorage["Level 4 State"]`: `Level4_Phase` → `GENERATING_PLAN` →
`BUILDING_WORLD` → `READY` → `INVESTIGATE`, plus `Level4_ResolvedSeed`,
`Level4_Variant`, `Level4_VariantName`, `Level4_PlanSeconds`,
`Level4_BuildSeconds`, `Level4_WorldDescendants`, `Level4_DynamicLightCount`.

If `Level4_Phase` is `ERROR`, `Level4_Error` carries the traceback.

**2. Run the suite.**

```lua
local Suite = require(game:GetService("ServerScriptService")["Level 4 Systems"]["Level 4 Test Suite"])
local result = Suite.RunAll()
print(result.Text)
print("PASSED:", result.Passed)
```

Expect 0 failures. `result.World` also reports `Lights`, `Descendants`,
`Houses` and `Placeholders`.

**3. Walk the blockout.** Arrive in the service passage, walk east onto Main
Street. Check: the tower is visible from the street, the loop can be walked
without doubling back, and the cross shortcut connects Main to the Back Lane.

**4. The briefing.** Within two seconds of `RoundActive` the banner shows the
briefing line and the Objectives feed carries it plus `RESIDENTIAL SIGNALS // 0/3`.
Panel reads `SIGNALS 0/3`.

**5. Signal 1 (the forgiving one).** Zone 1, generous 16-stud reach, no hold, no
noise. Trigger it. Watch `Level4_SignalProgress` → 1 and `Level4_Signal1` →
`LOGGED`. The clue part turns green and its text changes to `LOGGED 01`.

Server-side check (a prompt a player should not be able to use):

```lua
-- from the command bar, while dead or far away -- must return false
local OC = require(game:GetService("ServerScriptService")["Level 4 Systems"]["Level 4 Objective Controller"])
print(OC.DebugCompleteSignal(game.Players:GetPlayers()[1], 2))
```

(Note: `require` from the command bar is a **separate module instance**, so this
returns `false` for the wrong reason. Prefer testing the refusal in-game: die,
then try the prompt.)

**6. Signals 2 and 3.** Standard: 10-stud reach, 1.2 s hold, each reports
gameplay noise — expect `Level4_NeighbourState` to move to `INVESTIGATE` shortly
after. At 3/3, `Level4_BeaconUnlocked` → true, `Level4_Phase` → `BEACON`, and the
three cabinet prompts become enabled.

**7. Neighbour states.** Each can be forced:

| State | How |
|---|---|
| `PATROL` | default; watch it walk between junctions, mailboxes and porches |
| `INVESTIGATE` | sprint anywhere in the open (NoiseReporter reports it) and watch `Level4_NeighbourNoiseX/Z` |
| `SEARCH` | let it arrive at the noise, or show yourself from more than 42 studs |
| `ALERT` | stand in its cone inside 42 studs with a clear line — it stops and turns for 1.1 s |
| `CHASE` | keep the line for the full 1.1 s |
| back to `SEARCH` | break line of sight; **crouch** and it takes ~1.2 s instead of 3.5 s |
| `RETURN` | wait out `SearchSeconds` (14 s) |

Also check: standing inside a SAFE house's `InteriorVolume` makes you invisible
to it (`Level4_NeighbourTargetUserId` drops to 0) and unattackable, and it never
teleports onto you or hits you through a wall.

**8. House states.** The scheduler promotes one house every ~9 s, at most 2
non-safe at once.

```lua
print(OC.DebugSetHouseState("A1", "WARNED"))  -- again: command-bar require is a
                                              -- separate instance; prefer waiting
```

In-game, watch the porch signal go amber, the banner say
`HOUSE A1 IS GOING DARK -- LEAVE WITHIN 12s`, the panel line read
`SHELTER: UNSTABLE -- LEAVE`, and after 12 s the porch light go out. Nothing
should damage or trap you. Confirm `Level4_UnsafeHouses` never exceeds 2 and
every zone always keeps a safe house (the suite asserts this too).

**9. Finale, solo.** Walk to the bus stop. Set control 01, 02, 03 in order —
trying 02 first must answer `OUT OF SEQUENCE`. After 03: `Level4_Phase` →
`EXIT_WARNING`, `Level4_ExitWarningEndsAt` counts down 6 s, banner and panel both
count it, then `Level4_ExitOpen` → true and the gate slides clear.

**10. Escape and rewards.** Walk into the transit door. `Escaped` → true on your
Player, you are parked on `ExitSafeSpawn`, and GameManager's round loop declares
a win once no living participant is left inside. Confirm exactly one
`zyntraLevelCompleted` payout per escapee.

> **Reward note.** `ZyntraMonetization` treats level 4 as `tracked = false`: it
> pays the base completion tokens plus Friend Boost, and deliberately records no
> `LevelsCleared["4"]` and awards no badge. That is the correct behaviour for a
> dev-only level and needs no new reward path. It is idempotent by the existing
> mechanism.

**11. Cleanup.** After the result window, confirm: the world is gone, the lobby
is back in Workspace, `workspace.Entity` is back (Level 1's entity),
`ServerStorage` holds no `Level 4 Stored *`, `SelectedLevel` is 1, and
`Level4_Phase` is `IDLE`.

**12. Restart and re-seed.** Clear `Level4Seed` (or set 0) and start again:
`Level4_SeedPinned` must read false and a different variant must eventually
appear.

---

## 13. Known gaps against the brief's ten points

Honest list, for the card.

1. **Visual direction** — blockout colours and proportions only. No modular art,
   no CRT, no real curtains. The concept board is not implemented.
2. **Map** — 11 visible houses, loop + one cross shortcut, three zones, tower,
   bus stop, boundary facades and hills: done as blockout. Interiors are three
   module patterns, not authored rooms. **8–12 minutes is a design target and has
   not been measured.**
3. **Round flow** — arrival, briefing, three free-order signals, finale, warned
   exit, completion/Continue/Return: coded. Not yet run.
4. **The Neighbour** — full patrol/investigate/search/alert/chase/return with a
   placeholder rig. **No animations, no audio, no mesh.** Chase pacing unmeasured.
5. **Safe houses and variation** — three states with forewarning, safe-house
   invariant enforced and tested, three controlled variants. No per-variant
   entity tuning (deliberately: the brief says entity rules must not vary).
6. **Audio** — nothing. Section 8 is the slot list.
7. **Build phases** — milestones 1 and 2 only, as scoped.
8. **Done criteria** — untested: solo and full-party completion, touch controls,
   spectate, re-entry, death and lobby return **in Level 4 specifically**. The
   code paths are GameManager's existing ones and are unchanged.
9. **Neighbouring cards** — the detector extension point is used. Research
   camera, entity archive and shared objective messages are untouched.
10. **Inspiration/boundaries** — own layout, own entity, own assets. No borrowed
    geometry or ids.

Other honest gaps:

- **`Round Entry Client` had to change.** Its payload guard rejected any level
  above 3, which would have hung the entry barrier for 60 s and failed every
  Level 4 round. The change is one bound, `> 3` → `> 4`, marked in place.
- **Level 3 → Level 4 Continue works in Studio, not across a real teleport.**
  `continueStudioCampaign` hands `nextLevel = 4` straight to
  `prepareGroupLoading`, so the Studio path is live. The reserved-server path
  goes through `Routing.ArrivalPacket` and the arrival decode, both of which
  still call `Routing.ClampLevel` (ceiling 3), so a packet saying "level 4"
  arrives as level 3. Left deliberately: those two lines are the live transfer
  protocol, the failure is fail-safe (the party lands in Level 3, nothing
  leaks), and Level 4 must not be publishable anyway. When Level 4 becomes a
  real campaign level, raise `Routing.MaxLevel` and this disappears.
- **The loading cover is green, not a Level 4 palette.** `RoundUI.LOADING_PALETTES`
  has no entry for 4 and falls back to Level 1's. Cosmetic; left alone rather
  than editing RoundUI, which sits at the Luau 200-register limit.
- **Navmesh is unverified.** `AgentRadius` 2.7 fits a 24-stud street and a
  6-stud door arithmetically, but Roblox's 4-stud navmesh voxels have refused
  geometrically valid agents before (see Level 3's `PathAgentRadius` note). If
  `Level4_NeighbourPathStatus` sits on `FAILED`, drop `Derived.AgentRadius`
  toward 2.0 **for pathing only** and keep the body envelope where it is.
- **No frame-time measurement.** The light and instance budgets are asserted;
  actual mobile performance is not.
