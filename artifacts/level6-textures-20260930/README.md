# Level 6 texture restyle — prepared, not installed

The owner requested the original Level 3 textures, stronger 1990s colors, carpet in public/party areas, and hard floors in maintenance/kitchen areas. This package is an offline candidate. **No Studio source, instances, assets or publication were changed during this task.**

## Access and authority

Repository status and local history were inspected before development. HEAD at task start was `210e9fd4a189d36241b1b7081b8417afff36a5a3`. No Git remote is configured, so remote history could not be fetched. The unrelated cathedral Blender modification and existing untracked developer files were preserved.

Studio was closed at task start. It was opened, but the current LaverSneglen session returned HTTP 401 from Roblox's open-place endpoint: `User is not authenticated`. Opening and retrying place `131311258779917` failed. The only connected MCP instance remains the empty Studio start window, not the target place. The owner was asked to sign in on the previously authorized ZenMeister02 account and open BACKROOMS: STAY QUIET.

Fresh live Level 3/6 reads, source/editor parity checks, native backups, installation, gameplay verification and publication remain pending that access. Historical verified exports are references only; they must never overwrite newer Studio state.

## Reference and candidates

- [Original texture catalogue](reference-textures/README.md): all 15 configuration image originals, plus Mall Manager ColorMap, recovered from the checksum-verified source archive. The folding-table source image remains unavailable. Current effective live StringValue overrides and furniture properties are unverified.
- [Contact sheet](reference-textures/level3-textures-contact-sheet.jpg) and [manifest](reference-textures/reference-manifest.json): source-to-ID provenance, original hashes, repeat sizes and explicit live-verification status.
- [Styling and floor mapping](offline-reference.md): historical original floor/wall RGB values and exact 52/22/30/28-stud carpet repeat sizes.
- [Claude review](claude-review/review.md), [constrained candidate review](claude-review/candidate-review.md) and [palette proposal](claude-review/palette-proposal.json): actual Claude Code calls reported `claude-opus-5-5`, with CLI effort `max`, its highest supported level. Both reviews ran with tools disabled and no Studio access. Raw CLI responses and prompts are local temporary records, not deployment inputs.
- `candidate/`: replacement atlas, runtime RGBA pixels, a copied Blender project, comparison images and reproducible generation/verification scripts. These files are not live Studio exports.

## Implementation decisions

Level 6's adapter currently hides the builder's original Textures and renders different procedural atlas pixels. Updating configuration texture IDs alone would leave that visible mismatch intact.

The proposed adapter exposes the existing native room/corridor floor proxies and their original Top Textures, while omitting competing Blender floor skins. That preserves the exact carpet artwork and physical repeat size regardless of room/corridor dimensions. Blender walls, ceilings, furniture, collision/navigation anchors, lamps and CD interactions remain in place. Wall theme routing gains the original aliases and default orange plaster behavior.

The proposed Room Dressing edit limits the `FloorService` overlay to the actual `MaintenanceWorkshop` alcove. Arcade and party-supply alcoves keep their room carpet, partition, props and interactions. The historical rooms named `Maintenance` and `Janitor` are party-room identifiers and must not be used to classify hard floors. No separate kitchen variant exists in the inspected layout; a future kitchen needs explicit functional floor metadata.

The candidate atlas preserves the original UV layout and material keys. It reuses original carpet/wall artwork and applies Claude's per-material saturated chair, balloon and arcade-screen palette. Wall composites are approximations requiring a matched Studio visual check; the red wall retains red hue rather than inheriting the orange source image's hue. No global saturation multiplier or geometry reimport is proposed.

This game's atlas is stored as compressed 1024 × 1024 RGBA in `ServerStorage.Level6BlenderSource.AtlasJSON` / `AtlasPixels`. `Level6BlenderRuntimeBake` creates static `TextureContent` per server. A scoped, guarded pixel-payload update can therefore change the atlas without uploading new mesh assets or changing any of the 49 mesh payloads. The current live storage structure must first be verified.

## Required continuation

1. Select the correct live MCP instance; verify place `131311258779917`, universe `10559217407`, and Edit mode. Capture a complete native place checkpoint with the existing backup tooling.
2. Run `tools/level6_build/import/receive_texture_reference.py` with a new local capture directory, then execute `capture_texture_reference.luau`. This reads relevant live sources/editor buffers, effective texture slots, furniture maps and atlas payloads. The receiver rejects source/editor conflicts and a mismatched place.
3. Resolve any live drift or changed image IDs against that fresh Studio state. Rebase only the requested Level 6 appearance changes, preserving unrelated developers' work. Never install the offline historical baselines as current state.
4. Review the exact source and property diff. Recheck Source/editor and atlas StringValue baselines inside the scoped write. Preserve mesh-payload hashes and all Level 3 source/properties.
5. Verify actual Level 3/6 visuals, fixed carpet scale, maintenance-only hard floor, both corridor directions, loading/spawn/walking, lamps/night ownership and developer CD ESP. No such gameplay or performance check has passed during this offline preparation.
6. Export verified Studio state and a full native after-checkpoint; commit the task's verified mirrors and relevant records. Publish the current target place only after checks pass, and verify Roblox reports successful publication.

The new read-only Python receiver passes a syntax compile check. Offline image/Blender verification is recorded in the candidate manifest. These checks do not establish Studio parity, gameplay correctness or publication.
