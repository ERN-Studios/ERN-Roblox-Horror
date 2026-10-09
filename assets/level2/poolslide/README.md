# Pool Slide asset recovery — 2026-08-31

This is the large, clean, vivid tube humanoid for Level 2's second-pump
encounter. It replaces the retired Slidemouth. `asset-manifest.json` records
the actual imported mesh/texture IDs and the captured 16-stud template.

Current encounter update: the humanoid now **replaces Slidemouth** and spawns on
the second distinct pump. Its four random groans are attached to its body.
See [SECOND_PUMP_VERIFICATION.md](SECOND_PUMP_VERIFICATION.md) for dev controls,
tests and current publication; the original third-pump integration below is history.

Pathfinding follow-up: see [NAVIGATION_VERIFICATION.md](NAVIGATION_VERIFICATION.md)
for the reproduced pacing issues,76 regression checks, final live trials,
physical-clearance limitations and verified publication as version1699.

## Verify or restore exact source files

From the repository root, using Python 3's standard library:

```sh
python3 tools/restore-poolslide-assets.py --verify-only
python3 tools/restore-poolslide-assets.py --output /absolute/path/to/new-empty-name
```

The destination must not already exist. The restore tool verifies every 640-KiB
archive part, the complete archive, and every contained file before extraction;
it rejects links, duplicate members and unsafe paths. Files are verified again
after extraction. It never contacts Roblox or modifies the game.

`source-pack/manifest.json` contains all part/file sizes and SHA-256 hashes.
The supplemental pack includes the exact corrected `Final_Roblox` authoring
assets; Studio-import FBX/GLB and unchanged textures; Blender preparation,
skinning and roundtrip diagnostics; all source animation samples; conversion
scripts and actual-target keyframes; the captured Studio hierarchy and a
reconstruction helper. No old source packs or original Desktop files are changed.
Large binary/source data is split to match the existing repository bridge's
640-KiB per-part convention.

The actual imported template has 138 instances: one Model, seven MeshParts,
one invisible RootPart, seven Motor6Ds, one shared 24-Bone hierarchy, an
AnimationController, and a Folder containing 96 CFrameValues. The mesh assets
contain the skinned geometry. `template-reconstruction.json` preserves the
captured parenting, reference links, attributes, transforms and material data.

## Reconstruct the captured template and keyframes

`recovery-bundle.json` combines that hierarchy with the three actual-target
KeyframeSequence payloads. `reconstruct_poolslide.luau` returns a recovery module:

```lua
local Recovery = require(theRecoveryModule)
local built = Recovery.Build(decodedRecoveryBundle)
-- built.Template and built.Sequences remain detached for inspection.
-- ALTERNATIVE to Build, explicitly install in Studio Edit:
-- local installed = Recovery.Install(decodedRecoveryBundle)
```

Load the helper and JSON through an explicitly authorized Studio plugin/command
workflow. Roblox scripts cannot directly read these repository files. Do not put
the helper in a runtime service or execute both example calls unintentionally.
`Install` checks the place ID and refuses existing template/keyframe names. It
builds detached objects first, rechecks destinations after mesh-download yields,
then installs into `ServerStorage.Level2Assets` and `ReplicatedStorage.Level 2 Assets`.
It never publishes anything or overwrites existing instances.

MeshPart MeshId is read-only, so recovery uses the documented
[`AssetService:CreateMeshPartAsync`](https://create.roblox.com/docs/reference/engine/classes/AssetService#CreateMeshPartAsync)
with `Content.fromUri` and the recorded fidelity options. Access to the original
ERN Roblox Studios mesh/texture assets is required. The helper reconstructs
captured bones, motors and initial poses; it does not attempt to invent or replace
skin weights. The source FBXs provide the geometry/weights fallback if uploaded
assets become unavailable.

**Recovery limitation:** this JSON reconstruction has not been visually
round-trip tested in Studio. It is an auditable recovery path, not a claim that
Roblox's internal skinned binding has been proven identical. Reserved `RBX_`
importer metadata is archived but intentionally not replayed. Absolute dimensions
and transforms are preserved, but Model scale metadata was not captured. Keep
a saved full place as the definitive recovery copy, and verify idle/walk/run
deformation before replacing a production template. The source pack does not
contain a full place unless one is explicitly added later.

Keyframes are local Bone.Transform data, not published Animation assets. A
recovered or resized/imported rig must be checked against
`actual-studio-poolslide-rest.json`; re-run the archived retarget/validation tools
if its bind or size differs. The new entity controller/client and shared
Navigator remain in the repository's normal script mirror, outside this pack.

## Intentional snapshot refresh

```sh
python3 assets/level2/poolslide/build_source_pack.py \
  --desktop-root /absolute/path/to/Backrooms_Stay_Quiet_Level2_PoolSlide_Entity \
  --staging-root /absolute/path/to/implementation_work/level2_poolslide \
  --replace-snapshot
```

This updates only the Pool Slide recovery snapshot, not the general script-sync
or live-asset manifest. Re-run verification and a fresh-directory extraction
after refreshing it. Source-payload hashes change if any input changes.
