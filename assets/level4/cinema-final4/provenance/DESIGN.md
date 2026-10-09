# Level 4 "Den Sidste Forestilling" — design and contracts (2026-10-02)

Owner request (Danish, verbatim idea they approved): see `G:\Roblox\_local\l4facelift\v4\idea_discord.txt`. Owner decisions:
dev-only first (only DevAccess developers can start the round; one switch makes it public later); solo players lock the
main breaker with a fuse for ~60 s, co-op players hold it (the Usher hunts the holder); up to 100 Meshy credits (65 used:
Usher + rig + film canister); the finale completes the level like the others (rewards, back to lobby). Extra owner wish:
the round STARTS IN TOTAL DARKNESS and the players can fairly quickly turn the power on — the whole cinema lights up in a
"woooow" moment. Architecture map of the existing game: `G:\Roblox\_local\l4facelift\v5\arch\ARCH.md` (read it).

Implementation split: Claude writes all gameplay Lua (server + client) and the GameManager touchpoints; Codex builds the
Blender/asset side and reviews code. All names below are contracts — do not rename.

## 1. World anchors (exported from Blender into Workspace."Level 4 Cinema Blender")

Markers are non-colliding invisible parts (export collider kind "Marker") carrying CollectionService tags + attributes.
Interactive props are prop Models (export l4_prop) carrying tags (+ attributes) on the Model.

| Tag | Kind | Count | Attributes | Where |
|---|---|---|---|---|
| L4EntrySpawn | Marker 4x1x4, top = floor + 0.05 | 6 | Slot 1..6 | round start: the concession spawn passage / lobby side of the service door, in darkness |
| L4PowerCabinet | prop Model | 2 | CabinetId "A"/"B" | the two service breaker cabinets (props_rooms), door OPEN, label POWER A / POWER B |
| L4Breaker | prop Model (switch handle as its own part "Handle", pivot at the hinge) | 6 | CabinetId, SwitchIndex 1..3 | 3 big switches inside each cabinet, reachable, labels A1..A3 / B1..B3 painted next to them |
| L4NoteSpot | Marker 1x0.2x1.4 (paper size) | 6 | (none) | flat on surfaces near the start: service workbench, concession counter, lobby café table, service shelf, ticket booth sill, near the service door |
| L4MainBreaker | prop Model (lever "Lever" part, pivot at hinge) | 1 | (none) | big red-handled main breaker box on a service room wall |
| L4FuseSocket | Marker 1x1x1 | 1 | (none) | the fuse slot next to the main breaker (solo fuse lock) |
| L4ReelSpot | Marker 1.4x0.6x1.4 | 10 | SpotName (Danish label) | arcade prize counter (inside the locked prize case: attribute Locked=true), popcorn machine, men's restroom stall, women's restroom stall, service shelf, lobby café table, concession back counter, a seat in Cinema 1, gallery lockers, ticket booth |
| L4Projector | prop Model (the booth projector, already placed by props_lobby) | 3 | Screen 1..3 (= A1..A3) | booth projectors; prompt anchor = the projector |
| L4Screen | Marker covering each auditorium screen surface | 3 | Screen 1..3 | the three screens (finale glow, "film" flicker when its projector runs) |
| L4ExitScreen | Marker volume 0.5 deep in front of Cinema 2's screen, full screen size | 1 | (none) | Cinema 2 (A2) screen = finale exit |
| L4ExitSafeSpawn | Marker | 6 | Slot | hidden "after credits" room / far below the map — escaped players are parked here |
| L4HideZone | Marker volume | ~40 | HideKind "Seats"/"Stall"/"Counter" | between seat rows (each auditorium: several row volumes), each restroom stall, behind the concession counter |
| L4ArcadeCode | prop Model (one arcade cabinet; its screen part named "Screen") | 1 | (none) | the machine that shows the HI-SCORE code |
| L4PrizeKeypad | Marker (keypad part) | 1 | (none) | on the arcade prize counter front |
| L4PrizeCase | prop Model (glass door part "Door") | 1 | (none) | the prize counter case that opens on the right code |
| L4LightZone | Marker (floor-level disc/box) | Z (~30-40) | Zone 1..Z, Radius (studs) | one per light zone, on the floor at the zone centre |
| L4UsherNode | Marker 1x1x1 on walkable floor | many (every ~10 studs across all walkable floors, incl. stairs/gallery/booths) | Zone (nearest zone id) | Usher navigation graph nodes (the Usher hops/moves between these) |

Light zones: every exported Roblox light holder part gets attribute `L4Zone` (int) and every neon/emissive surface is
pooled PER ZONE in the export (pooled MeshParts of EMIT_* / Neon materials carry attribute `L4Zone`), so a zone's neon
can go dark with its lights. Stars stay global (one set). Zones are spatial clusters (k-means on light positions, ~12-20
lights each, never spanning two rooms separated by walls). Each room-ish space gets at least one zone; auditoria 3-4
zones each; the gallery 3-4; service 2 (Backrooms fluorescents); restrooms 1 each.

Templates (ServerStorage."Level 4 Templates", built in Studio from uploaded meshes): `Usher` (Model, PrimaryPart
"HumanoidRootPart", segmented MeshParts + Motor6Ds named after the 24 Meshy bones, red ticket flashlight in the right
hand), `FilmReel` (Model, the Meshy canister ~0.38 m diameter), `Fuse` (Model), `BatteryPack` (Model), `Note` (Model:
paper part "Paper" with a SurfaceGui text label "Text").

## 2. Server modules (Claude)

- `ServerScriptService.Level4RoundGenerator` (ModuleScript): Build()/Cleanup() for GameManager (LEVEL_GENERATORS[4]).
  Build: isolates Level 1 runtime like the L2/L3 adapters, creates compatibility parts (Workspace.Elevator with DoorL/DoorR,
  MazeStart, ElevatorSpawn at L4EntrySpawn Slot 1, attribute Level4_CompatibilityMarker=true), collects the manifest from
  the tags above (asserts required counts), creates `Level 4 Round Runtime` under the cinema model, starts the controllers.
  Cleanup: stops controllers, restores mutated authored state (lights, neon, doors, prompts), destroys only owned runtime +
  compat parts. Never destroys the cinema.
- `ServerScriptService."Level 4 Systems"` folder:
  - `Level 4 Configuration` (ModuleScript): all tuning numbers.
  - `Level 4 Light Director` (ModuleScript): server authority for light. PowerState in {"Preview","Off","PoweringUp","On",
    "Failing","Finale"}; per-zone state; blink scheduler with escalation 0..3; `IsLit(position) -> boolean, zoneId`;
    publishes ReplicatedStorage."Level 4 State" attributes `Level4_PowerState`, `Level4_ZoneStates` (string of '1'/'0'
    per zone), `Level4_ZoneSerial`, `Level4_PowerUpStartedAt` (server time). Clients render from these.
  - `Level 4 Objective Controller` (ModuleScript): note/sequence, cabinets, reels (WORLD/CARRIED/DROPPED/INSERTED records,
    drop on death/leave), main breaker hold/fuse lock, projectors (hold-to-thread with server elapsed time), arcade code +
    keypad + prize case, finale exit (root-in-OBB, sets Escaped=true, escape message), hiding (`IsHidden(player)`: crouched
    + inside an L4HideZone, server Crouching attribute), TeamObjectives announcements, noise for reels/projector/breaker.
  - `Level 4 Usher Controller` (ModuleScript): kinematic server rig on the L4UsherNode graph; dark-only (Light Director);
    hops; noise/holder/nearest targeting; flashlight stun (FlashlightOn + mount aim cone/LOS); "shhh" warning windup;
    capture via the Jumpscare remote protocol + DeathAdvice "L4Usher" + Health=0; PlayerProtection respected; EntityPaused.
  - `Level 4 Test Suite` (ModuleScript): server-side checks runnable in a play session.
- State replicated in ReplicatedStorage."Level 4 State" (Folder): `Level4_Phase` ("Dark","Reels","Finale","Done"),
  `Level4_SequenceProgress`, `Level4_SequenceGoal`, `Level4_ReelsCollected`, `Level4_ReelsLoaded`, `Level4_ReelGoal` (3),
  `Level4_BreakerHolder` (UserId, 0 none), `Level4_FuseUntil` (server time, 0 none), `Level4_ExitUnlocked`,
  `Level4_ExitPosition` (Vector3), `Level4_UsherActive`, `Level4_UsherState`, `Level4_ThreadScreen`, `Level4_ThreadUntil`.
  Player attrs: `Level4_Hidden` (bool), `Level4_ReelsCarried` (int).
- Remotes: ReplicatedStorage."Level 4 Remotes": `ClientEvent` (server -> client cues: Type "PowerUp","Wrong","Shush",
  "Stun","Thread","ProjectorStart","Finale","Credits","Keypad"...), `KeypadSubmit` (client -> server 4 digits),
  `UsherMotion` (UnreliableRemoteEvent, 20 Hz root CFrame + state for smooth client animation).

## 3. Client (Claude)
- `StarterPlayerScripts."Level 4 Round Client"`: briefing, objective HUD, captions, power-up "wow" (thunks per zone, neon
  buzz, a short low camera rumble unless ReduceCameraShake), keypad UI, credits roll, finale screen visuals, hidden/carry
  indicators, Usher client animation (Motor6D.Transform from the keyframe module + procedural idle/shush/lunge/stun),
  red flashlight glow.
- `Workspace."Level 4 Cinema Blender".OccasionalFixtureFlicker` (existing client script, rewritten): Preview mode = today's
  cosmetic flicker; round mode = render server zone states (lights, per-zone neon, stars) with short stutters; ReduceFlashing
  = fades. Visual only; the server decides darkness.

## 4. Flow
1. Dark start (Phase "Dark", PowerState "Off"): every light and neon off, stars off, only exit signs dim. Players spawn on
   L4EntrySpawn, flashlights on. A note with a 4-step switch order (e.g. "B2 - A1 - B3 - A2") lies on a random L4NoteSpot
   within ~35 studs of the spawn. Wrong switch: sparks + reset. Usher dormant.
2. Power up (PowerState "PoweringUp" ~4 s): zones switch on in a wave ordered by distance from the service room, each with a
   thunk; stars fade in; then "On" for ~15 s (everything lit — the wow), then "Failing": blinks start, escalating with each
   reel loaded. Usher activates when Failing starts (+ grace 8 s).
3. Reels: 3 random distinct L4ReelSpots (the prize case spot only if chosen gets Locked until the code is entered). Carry
   slows (x0.88 per reel, min x0.7), running with reels makes "reel" noise. Death drops carried reels on the floor.
4. Projectors: thread = hold 5 s at a booth projector while carrying a reel AND the main breaker engaged (held by a living
   participant standing at the lever, or the fuse active). Threading emits "projector" noise every second. Loaded projector
   runs its screen. Main breaker: co-op hold (holder anchored at the lever, releases on E/damage/death/leave/hiding);
   fuse: only while exactly one living non-escaped participant remains; 60 s, then it blows.
5. Finale (after 3 loaded): PowerState "Finale": all zones dark, the three screens glow, Cinema 2's screen shows the
   cinema from above and becomes the exit; credits roll; Usher speed up and may move anywhere (all dark). Touching
   L4ExitScreen escapes (Escaped=true -> parked at L4ExitSafeSpawn). GameManager wins when all living participants escaped.
6. Bonus: L4ArcadeCode shows a random 4-digit HI-SCORE; entering it on L4PrizeKeypad opens L4PrizeCase: a reel (if a reel
   spot is inside) or a BatteryPack (refills the flashlight).
