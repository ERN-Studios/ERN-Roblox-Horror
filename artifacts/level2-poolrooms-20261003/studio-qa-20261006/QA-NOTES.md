# Level 2 Poolrooms - practical Studio QA (2026-10-05/06, Level 2 session)

Place 131311258779917, Studio 1df8b7bb, installed build = commits 3b80fb2 + 1be05fc (0.5-stud tiles).
Driven through the Studio MCP: real prompts by E / touch, real Humanoid movement, server/client readbacks.

## Gameplay (preview round, solo)
| Check | Result | Evidence |
|---|---|---|
| Preview start, desktop | PASS | pedestal prompt in QueueBay_Level2, E hold -> Level2BlenderPreviewActive, SelectedLevel 2, InRound |
| Preview start, mobile (Device Simulator, touch UI forced) | PASS | prompt shown with InputType Touch; touch-hold on the HUD plate started the round; round HUD shows joystick/SCAN/SHIELD/POV/DROP GLOW/SNEAK/RUN/JUMP; 60 fps |
| Pumps (3) | PASS | each pump prompt shows from the lever side (east/south-east/south), hidden behind the pump body (line of sight); Level2Pumps 1/2/3 |
| Pool Foam | PASS | Dormant -> Foreshadow -> Pressure (pump 2, Level2FoamLethal true) -> Finale (pump 3); 5 foam bodies moving towards the player |
| Pool Slide | PASS | spawns at pump 2 (CHASE), ENRAGED at pump 3; it killed the player (AttackSerial 1) -> round lost -> lobby |
| Exit power | PASS | Level2ExitPowered + LightingMode EXIT_OPEN after the third pump |
| Exit stair (F11 walk) | PASS | pathfinding climb from the hall floor to the platform top y 81.6: Humanoid state Running on every sample, max vertical speed 13, no jumps or falls |
| Exit tube ride (F13) | PASS | walked into the collar -> slid 682,81 -> 749,30 -> 798,0 -> Escaped, ExitTransition |
| Round end | PASS | escape and death both end the round; back in the lobby, preview flag cleared |
| Collisions (F12) spot test | PASS | walking into a column stops at its radius; walking into a hall wall stops at its face (offline audit: 0 walk-through on 14 seeds) |
| Spiral stairs (F8) | PASS | kit: highest walkable 14 studs under the ceiling (H42 at 28, H52 at 38), only the core passes the hole; at most one well per map (one map had none) |
| Frame rate | PASS | 42-56 fps in rounds incl. exit hall after all pumps (Studio in front; ~9 fps was background throttling) |

## Visual (first pass, before the SurfaceAppearance change)
- F1 coves concave, F2 corners continue, F5 water to the walls, F7/F14 round flush skylights, F9 whole-room swerve walls,
  F10 wall openings are dark recesses (no white frames): shapes correct.
- Tiles on curved meshes (coves, corners, swerve walls, tunnel/pipe barrels) are warped: Roblox projects a
  MaterialVariant on a MeshPart in the mesh's own space and ignores its UVs. Fix in progress: tiled kit meshes get a
  SurfaceAppearance (measured: follows the UVs exactly, 0.4994 vs 0.5 stud).
