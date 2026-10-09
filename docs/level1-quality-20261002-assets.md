# Level 1 classic yellow Blender kit, V2

The separate `assets/level1/blender-v2` project keeps the prior native kit and the
user's open Blender session intact. It contains 42 explicit socket-matched room
collections, 41 shared authored components, and 93 exported material mesh chunks
(22,768 triangles in the shared component library). All 15 open socket masks use
the existing 24-stud cell, 14-stud wall and two-stud full boundary contract.

Quiet rooms have selection weight 16. Column bays have weight 1 and one moulded,
bevelled corner column. Special rooms have weight 4. Eight weight-3 variants add
a six-stud-wide internal divider with an 8.5-stud-high matching collider. Their
closed boundary walls remain visibly full height. Dividers and columns stay out
of the central +/-8-stud square and the +/-3-stud cardinal routing bands.

Wallpaper ColorMap is the owner's exact existing asset `87947439437597`, read
through the owning Studio session. `wallpaper_albedo.png` is byte-identical to
the extracted source PNG; its SHA256 is
`342e97e0f53df9e1cf50dae255c8e8f867cbe3d33a07ce29988827054ba46980`.
The stronger yellow is a material tint, RGB (255,235,150), with separate derived
normal and roughness maps. All six published carpet/ceiling maps are reused
unchanged from V1. Mechanical props share painted-metal, brushed-metal and
porcelain PBR finishes.

The original lit fixture image `135786374638992` and its dead counterpart were
also read from Studio. The model is a four-stud square with five fluorescent
banks, a 5x5 recessed metal grille, reflector channels, sockets and rim screws.
Only the `Lamp` mesh material emits. Fixture depth is retained independently
of the original thin gameplay light proxy.

The new ImageGen references are in `concept/`. Fixed puzzle shells are
`RelayShell`, `FuseBoxShell`, `LeverShell` and `ExitPortal`. Moving or variable
visuals remain separate: `RelayDoor`, `ExitDoor`, `FuseSocket`, `LeverShaft`,
`LeverKnob`, `FuseCore` and `FuseCap`. The olive exit leaf has a real aperture,
wire glass, push bar, kickplate, hinges and fasteners; `GreenGlass` alone has
authored partial transparency. Live prompts, circuit labels, indicators and
moving proxy parts remain the integration's authority.

Build and bounded asset checks:

```powershell
python tools/level1_blender/export_fixture_reference.py --studio-id <owning-session-id>
python tools/level1_blender/prepare_v2_textures.py
& D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 -P tools/level1_blender/build_v2.py
python tools/level1_blender/check_assets.py --assets assets/level1/blender-v2
& D:/Blender/blender.exe -b assets/level1/blender-v2/Level1_ModularKit.blend --python-exit-code 1 -P tools/level1_blender/verify_native.py -- --assets assets/level1/blender-v2
```

The exported manifest is frozen at SHA256
`dbfb65f59d765fdf1266734442b69f921fa7ae61295c17a715e69cf47a0b3c53`.
The checks passed binary lengths, finite values, triangle indices, source hashes,
socket masks, additional collision clearance, original wallpaper preservation,
42 native room collections, and 41 FBX component meshes with matching UV and
material slots. All 20 source texture references are portable `//textures/...`.
Native file hashes are recorded in `native-verification.json`.

The kit's scoped `.gitattributes` preserves exported asset bytes, including JSON
line endings, so Git checkout matches the frozen Studio import hash exactly.

Rebuilding can change Blender sphere index ordering without changing the shape;
upload receipts therefore bind to the final exported wire hash, never just a
component name. Do not rebuild while uploading a frozen export. Studio gameplay
and publication are recorded separately by the owning integration workflow.
