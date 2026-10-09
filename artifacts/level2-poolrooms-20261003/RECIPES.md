# Poolrooms hall recipes (shared by the Blender level assembler and the Roblox Kit World Builder)

Input: one hall record from the Kit Layout Generator (bounds, FloorY, CeilingClass, DeepEnd, PoolAxis, Type, Role,
its corridors) plus the kit components (tools/level2_poolrooms). Output: the hall's shell and dressing. Both the
Blender assembler (review renders) and the Luau builder implement exactly these rules, seeded from hall.LocalSeed.

## Shell (every big hall)
- Floor: one Aqua tile Part at FloorY - water depth (flooded halls; depth 1.6, deep end along PoolAxis to DeepEnd),
  terrain water surface at FloorY + 0.1. Raised tiled walkway strips (Walkway modules, top FloorY + 0.45) run along
  1-2 walls; every door/pipe mouth is reached by a walkway or by pool steps.
- Walls: Tile Parts per run between openings, height = CeilingClass. Openings: tunnels show a ROUND hole (the
  tunnel collar panel), the wall Part leaves a 30 x 30 rectangle behind it; pipes a 12 x 12 rectangle behind a round
  12 hole.
- Corners: CornerCove of radius 16 (8 in halls under 112 on a side, 24 above 200) in all four corners.
- Coves: CoveTop along every wall top and CoveBase along every wall foot (cut at openings), corner pieces matching.
- Ceiling: flat Tile Parts (named "Level 2 Overhead Tile ...") with one invisible "Level 2 Hall Roof Collider".
- Light: 1-3 LightWell_R6/R10 openings (real sky; the sun makes the patches) placed over water, never over a
  door approach; 0-2 SunSlit windows in long walls; Big Pool halls instead get a regular grid of LightRound every
  16 studs (lights budget: only every third one carries a Light).
- Darkness accents: 1-2 WallVoid high on a wall, DrainHole in flooded floors (1 per 1500 square studs, max 4).

## Types
| Type | Dressing (all outside the AI lanes: +-17 along both centre axes and every door spoke, 30 x 38 door approaches) |
|---|---|
| ColumnHall | loose jittered grid of Column_D10 (spacing 28-36), 1-2 Column_D16 as landmarks |
| BigPool | regular rows of Column_D10 every 32 along the long axis, one round island (Walkway_End pair) around one column, LightRound grid, 3-6 WallVoid "outflows" at the far wall's foot |
| VaultArcade | ceiling of VaultBay32 bays on VaultPier where the bay grid fits (replaces the flat ceiling there), a curved pool edge (Walkway_Bend) across the hall |
| CurvedChannel | 2-4 CurveWall_Q/S partitions forming a winding channel along PoolAxis with a curving walkway on one side; the channel keeps a >= 34-wide clear path between every pair of openings (Pool Slide) |
| SpiralWell | SpiralStairWell in one quadrant (its ceiling hole is the hall's light well), Column_D10 pairs elsewhere |
| CorridorHall | long walkway down one side, square VaultPier columns every 24, SunSlit every 24 in the other wall, DrainHole row in the channel |
| PaddlingRoom (kids role) | very shallow (0.8) aqua floor everywhere, PoolSteps_Curved at doors, CornerCove 24, 1-2 Column_D6, the Pool Foam spawn pocket (8 x 8 clear, as live) |
| PumpHall | dry or ankle-deep around the PumpStation plinth at the centre; one LightWell straight above the pump |
| Arrival | dry, ArrivalDoor on the spawn wall, 32 x 30 clear apron, one SunSlit |
| ExitHall | ExitSpiral to ExitPlatform at y 74, ExitMouth on the platform at the flume gap, ExitSkylight above, ExitTubeVisual outside |
| Chambers | prefabs Chamber_A..D as authored (low, ceiling 15), plugs removed where a pipe connects |

## Corridors
- Tunnels (34-class): RoundTunnel_<Wet|Dry|Stair4|Stair8>_<Len>; drain corridors are Wet with the drain water region.
- Narrow passages: Pipe_<Flat|Stair4>_<Len>.
