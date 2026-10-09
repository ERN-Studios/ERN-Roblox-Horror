# Level 1 elevator inset — geometry proposal, 2026-10-04

This is a proposal only. No Studio instances, runtime sources, Blender models, imports, assets or backups were changed by this analysis.

Fresh Edit inspection confirmed MazeGenerator and BlenderRoomRenderer Source/editor parity. The authoritative before-studio export has normalized LF source SHA256:

- MazeGenerator: `a8f4cbdc78bd73d4acd7e06331281c8558782081f8f321d96f0f6f8932511dc4`.
- BlenderRoomRenderer: `5a071ee012f805d3ea17223f40be8705882555178f24544c7e94ec6e7fec389f`.
- Existing V2 kit manifest: `dbfb65f59d765fdf1266734442b69f921fa7ae61295c17a715e69cf47a0b3c53`.

The existing graphify graph is older (commit a6551306) and has no BlenderRoomRenderer nodes. Its extracted buildCabin -> part/applyTexture/refreshCableGuidePoster relationships were checked against fresh Studio source; its historical line locations were not used as a live baseline. Query vocabulary: build, cabin, wall, texture, door.

## Actual exterior geometry

The east facade is 24 studs wide and 14 high. Its clear aperture is 8 wide by 10 high. The visible steel surround comes from three unnamed query Parts in MazeGenerator:

| Existing part | World size X/Y/Z | Center |
| --- | --- | --- |
| frameTop | 2 / 4 / 24 | x1-1 / 12 / cz |
| frameSideA | 2 / 10 / 8 | x1-1 / 5 / z0+4 |
| frameSideB | 2 / 10 / 8 | x1-1 / 5 / z1-4 |

The south/north/west outer walls already receive WallHalf skins immediately in wallPart(). The renderer's skinned guard prevents the later Elevator watcher from replacing these with steel.

Replace the three front fields with named wallpaper roles while preserving their exact world bounds. Use local size `(width,height,2)` and a 90-degree Y rotation so the WallHalf component's local Z face points to world +/-X:

- Header: local Size `(24,4,2)` at `(x1-1,12,cz)`.
- Side A/B: local Size `(8,10,2)` at their existing centers.
- Suggested names: `EntranceWallpaperHeader`, `EntranceWallpaperL`, `EntranceWallpaperR`.
- Skip only the Header clone's Trim material so its inherited baseboard does not appear above the door. Do not hide wallpaper or change query collisions.

Rotation fixes direction, not baked UV density. WallHalf wallpaper UVs have a six-stud repeat over the authored 24x14 mesh. Resizing to 8x10 produces an effective 2x4.286-stud repeat; resizing the header to 24x4 produces 6x1.714. Exact six-stud repeats require a dedicated UV variant or a correctly oriented original Texture overlay. Keep the original wallpaper source image 87947439437597 and its PBR pattern unchanged. Decide whether a UV variant is needed from the in-engine close-up; no model generation has been undertaken.

## One narrow stainless jamb/header

Reuse the published MetalPanel/ElevatorDoorSkin mesh for three decorative pieces. Suggested world bounds:

| Piece | World size X/Y/Z | Center |
| --- | --- | --- |
| EntranceJambL | 2.04 / 10 / .28 | x1-1 / 5 / cz-4.14 |
| EntranceJambR | 2.04 / 10 / .28 | x1-1 / 5 / cz+4.14 |
| EntranceHeader | 2.04 / .28 / 8.56 | x1-1 / 10.14 / cz |

The jambs remain outside Z +/-4, and the header remains above Y10, so the aperture stays exactly 8x10. Their front faces sit .02 studs beyond the wallpaper facade to avoid z-fighting. Their 2.04-stud depth wraps the existing recessed opening. Set CanCollide/CanQuery/CanTouch false. For correct front-facing mesh orientation, local jamb Size is `(.28,10,2.04)` and local header Size `(8.56,.28,2.04)`, both with 90-degree Y rotation.

The bundled ElevatorFrame has .75-stud jambs, an .8-stud header and a nominal 7.95x10.95 opening. Stretching that whole frame onto the live opening would distort both thickness and aperture; three independently fitted existing Blender pieces are the smaller robust change. Avoid a second outline or wider facade-sized steel field.

DoorL/DoorR retain world Size `(.45,10,4)`, X center `x1-1`, closed Z centers `cz +/-2`, dynamic skin welds and GameManager's actual +/-3.6-stud slide. The wall aperture is 8x10; fully open leaves retain the existing 7.2-stud clear width. The +/-4 comment in MazeGenerator is inaccurate. Do not rename, resize or reposition these interactive/collision authorities.

## Cabin panels and line light

Existing cabin clear width is 8 studs, ceiling underside Y10, and depth grows monotonically from 10 to 18 with crew size. Preserve the full cabin query walls, floor, rebuild logic and spawn geometry.

- Name/tag fixed structural walls, roof, floor and decorative pieces by an explicit elevator material role. Do not use one blanket rule for every non-Neon Elevator descendant; the selector and CableGuidePoster are separate display roles.
- Reuse existing Blender steel geometry for approximately two-stud panel modules or sparse narrow vertical reveals. Side-wall reveal faces can sit .015 studs inside Z +/-4; the back-wall reveal face can sit at xBack+.015. Reveal widths .02-.04 studs read as seams without creating protruding obstacles. All added detail is noncolliding.
- A slim central ceiling line can use a plain existing Blender panel mesh fitted to `(depth-.8,.06,.12)`, centered at `(bx,9.96,cz)`. This gives a bottom at 9.93 and top at 9.99 under the Y10 ceiling. A linear light must have its own role; mapping it to LightFixture would produce the existing five-tube grille rather than a linear diffuser.
- Clone the mesh for that role, omit its SurfaceAppearance, and use restrained white Neon. Exclude the role from the elevatorSteel override. Keep the existing PointLight power/range and progression logic unchanged; only its visual fixture changes. No new uploaded mesh is required.
- Preserve CableGuidePoster, CableGuideSurface, paper/labels, current circuit allocation update function, its position and selector UI. The full before-studio guide baseline is recorded separately by root.

Current Steel albedo is dark and slightly olive, with mean RGB approximately 104/106/94. The installed 231/226/255 tint makes it neutral but cannot increase base-map luminance. A genuinely light gray brushed steel finish may need an elevator-only lighter albedo/material variant; keep normal, roughness and metalness maps and all geometry. Do not alter the shared Steel/MetalPanel definition used by puzzle props. Model generation, asset changes and imports require root's agreement before execution.

## Verification targets for root

- Exterior wallpaper reaches the single .28-stud jamb/header; no broad steel/black facade remains.
- Eight-by-ten clear aperture, unchanged original collider bounds and unchanged moving door transforms.
- No header baseboard, doubled trim, wallpaper/steel z-fighting or hidden door-edge blockers.
- Light gray continuous cabin panels, a slim ceiling line and the existing guide remain visible.
- Crew-size rebuild and reset remove only round-owned detail; original Level 1 navigation, random generation, progression, Level 4 and lobby remain unchanged.
