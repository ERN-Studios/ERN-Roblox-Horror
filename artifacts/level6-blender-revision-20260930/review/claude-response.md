**Verdict:** The approach is sound if you (a) move tiling surfaces off the atlas, (b) make Blender materials sample only sidecar images, and (c) accept that resizing MeshParts at runtime can't be fixed offline. **[verify]** means confirm in the official Roblox docs. Nothing here has been tested in Studio.

**1. Preservation & determinism**
- Commit or hash v2 first. Edit the kit's mesh data and material slots so every instance inherits the changes. Leave actions and anchor empties alone.
- Avoid Make Instances Real, Make Single User, and Apply Transforms on multi-user data. Export from a temp copy and never save back.
- Snapshot a baseline: kit names, anchor names and matrices, sorted instance name+matrix, and action keyframe hashes.
- Don't perturb Seed101's RNG. Pick the new zones in a post-pass from a derived sub-seed (`sha256(f"{seed}:zones")`, not Python's salted `hash()`), iterating rooms in sorted order. The 32/37/3,220 base then regenerates identically, plus an explicit delta.

**2. Level 3 artwork & stud-space repeats**
- Atlas cells can't repeat: UV wrap tiles the whole image, and mips bleed across cells. Give carpet, each wall, and linoleum its own tileable image. Use Level 3 originals for carpet and walls, with provenance = asset ID + sha256.
- Shells that become multi-material should split into child objects inside the same kit collection, keeping the item name, pivot and anchors.
- One config holds the tile periods for both UVs and the manifest. Mark them `UNVERIFIED` until they are read from live Level 3. Note that `Texture` has StudsPerTileU/V, but MaterialVariant has a single StudsPerTile, so non-square periods won't map 1:1.
- Re-mapped surfaces get planar UV index 0: face-plane stud coordinates ÷ periodU/V. Legacy atlas UVs stay in the source only.
- Module widths that are integer multiples of the period keep the pattern phase continuous across grid-snapped instances.
- Scaled rooms in Blender: a per-object Geometry Nodes modifier can write stud-space UVs from position × Self Object scale while keeping mesh data shared. This works on linked duplicates, not on collection-instance empties, because the modifier can't see the instancer's scale.
- Roblox, SurfaceAppearance (MeshPart): follows mesh UVs, so runtime resizing still causes drift. Blender's compensated preview hides this.
- Roblox, MaterialVariant (native Parts): designed to tile by StudsPerTile regardless of part size. Three things are **[verify]**: face orientation/phase, MaterialVariant's behavior on MeshParts, and SurfaceAppearance wrap beyond 0–1.

**3. Carpet & DiamondPlate relief**
- Generate height maps with seeded numpy at the color map's period. Never derive them from color luminance: the confetti is dye, not relief.
- Carpet: FFT-filtered periodic noise, with 3–8 px tuft clumps plus faint fibre. Single-pixel noise only aliases.
- DiamondPlate: SDF lozenges on the staggered lattice, integer repeats per tile, rounded 2–4 px bevels.
- Derive normals from float height using wraparound central differences (`np.roll`), which makes them seamless by construction. Keep the 16-bit/EXR height as source only.
- Blender uses OpenGL (+Y green) with MikkTSpace. Roblox's green direction, tangent basis, and whether it reconstructs blue are all **[verify]**. Prove them with an asymmetric test tile, and avoid mirrored UVs on these surfaces.

**4. Strengths, QA, color space**
- Don't rely on a Roblox normal-strength property **[verify]**. Bake strength into the map and keep Blender's Normal Map node at 1.0.
- Starting strengths: carpet ≤10° tilt (z ≥ 0.985), DiamondPlate bevels 30–40°, wallpaper 0–3°.
- QA checks:
  - Tile-mean R,G ≈ 127.5±1. Periodic gradients average to zero, so an offset means an encoding bug.
  - Decoded normal length 1±0.02.
  - Inspect 3×3-tiled and half-offset views.
  - Box-filtered mips 2–4 show no moiré (lozenge period ≥16 px at base).
- Color space: ColorMap is sRGB. Normal, roughness and metalness are linear ("Non-Color") with no alpha; roughness and metalness are single-channel.
- Use power-of-two sizes for new maps. The upload cap may downscale the 2048 atlas **[verify]**.
- Compare colors under the Standard view transform, not AgX/Filmic.

**5. Packed images vs sidecars**
Packed images alone don't suffice: Roblox never sees the node graph, and how the importer maps FBX materials to PBR is **[verify]**. Sidecars are canonical, and any packed copies must hash-match them. Ship:
- `Level6_WornParty_kit.fbx`, exported with the v2 preset (recorded in the manifest)
- `textures/<material>_{color,normal,roughness,metalness}.png`
- `source/*_height.exr` and `gen_textures.py`
- `level6_pbr_manifest.json`, containing:
  - generator commit + seed, and the .blend sha256
  - per texture: file, sha256, size, colorSpace, role, normalConvention, tilePeriodStuds, provenance
  - per material: maps, UV index 0, and two untested candidate routes:
    - `SurfaceAppearance`: MeshPart, opaque ColorMap, white part color (tinting **[verify]**)
    - `MaterialVariant`: native Part, BaseMaterial, StudsPerTile, Pattern Regular
  - per mesh object: exactly one material, native size, scaledAtRuntime, anchors

**6. Kitchen & service zones**
- Build them as dressing variants of existing small-room and corridor footprints, reusing the same shell and link sockets. That keeps 32 rooms and 37 links.
- Kitchen (~5 items): counter run, corner counter, fridge, stove, shuttered serving-hatch wall variant; linoleum floor.
- Service (~5 items): DiamondPlate floor module, breaker panel, wall pipes above head height, mop sink/shelf, staff-door variant on existing door anchors.
- Props hug walls within a fixed depth.
- Add non-exported `NAV_CLEAR_*` boxes at doors, links and corridor spines, and fail validation on any intersection. Clear widths must fit the pathfinding agent, whose size should be read later rather than guessed.
- Leave existing anchors untouched and namespace new ones (`L6K_*`, `L6S_*`).

**7. Risks & acceptance**
Highest risks:
- inverted relief
- normals ingested as sRGB
- drift from runtime scaling
- Seed101 RNG perturbation
- accidental de-instancing
- `.001` anchor renames
- multi-material objects (one SurfaceAppearance per MeshPart; importer splitting **[verify]**)
- wrong UV set used **[verify]**

Acceptance criteria (offline, scriptable):
1. All 49 v2 kit names are present. The Seed101 base matches the baseline snapshot (32/37/3,220; matrices within 1e-4), with additions listed as a delta. Mesh datablocks grow only by new items and declared splits.
2. All v2 anchors (exact names) and actions are present. Anchor matrices are within 1e-4, and keyframe hashes are unchanged.
3. On every tiling face, measured studs-per-UV is within 0.5% of the configured period.
4. The §4 texture metrics pass, and the wrap-seam gradient jump is ≤ the interior 99th percentile.
5. Carpet and wall ColorMaps hash-match the Level 3 originals or a documented resample, proving no relief was baked into color.
6. A fixed-direction light render shows DiamondPlate raised, not sunken.
7. The manifest validates, every FBX material has an entry, hashes match, and each exported mesh has one material.
8. Zero `NAV_CLEAR` intersections, and link sockets are unchanged.
