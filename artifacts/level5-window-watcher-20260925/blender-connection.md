# Blender connection audit — 2026-09-25

## Recommendation

Use the installed Blender executable through background Python (`bpy`) now. This is a verified direct connection to Blender's own scene/rig/animation/export API, not a mock or merely external Python. It avoids adding an MCP bridge for the current asset pipeline and can produce repeatable .blend, preview renders, model exports and one animation file per clip.

No Blender install, addon install, persistent configuration changes, UI actions or Roblox Studio edits were performed. The only Blender processes launched were bounded `--version`, `--help` and factory-startup background diagnostic processes; none saved a file or preferences.

## Local evidence

- Executable: `/Applications/Blender.app/Contents/MacOS/Blender`.
- Actual version: **Blender 5.2.0 LTS**, Darwin, build `fbe6228777e7`, built2026-07-14.
- No Blender process was running at the initial check. `blender` is not on PATH; use the absolute path.
- Bundled modules include `io_scene_fbx`, `io_scene_gltf2`, `rigify` and `pose_library`.
- No Blender-MCP configuration entry or user-addon Python files were found in the bounded known-path checks. No Blender/Meshy tools were callable in this subagent's current catalog; Meshy connection is being handled separately by parent.
- Actual Plugin Management search `Blender`, limit10: **plugins=[]**. No directory plugin was installed or suggested.

Final diagnostic command shape:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --disable-autoexec --python-exit-code 23 --python-expr '...read-only bpy/importlib/RNA inspection...'
```

Final actual output, exit0:

```text
CODEX_BLENDER_CONNECTION={"version": "5.2.0 LTS", "background": true, "fbx_addon_available": true, "gltf_addon_available": true, "fbx_export_operator_rna": "EXPORT_SCENE_OT_fbx", "gltf_import_operator_rna": "IMPORT_SCENE_OT_gltf", "fbx_export_options": true, "writes_performed": false}
Blender 5.2.0 LTS (hash fbe6228777e7 built 2026-07-14 01:31:22)

Blender quit
```

This proves background Python and registered FBX export/glTF import operators. It does **not** yet prove a real model's weights, export roundtrip, rendered appearance or Studio import. Those are subsequent asset QA.

## Connection options

| Route | Current state | Assessment |
| --- | --- | --- |
| Installed Blender background+bpy | Verified running successfully | Recommended for reproducible generation, rig inspection, weights, poses, clips, renders and exports. Save an inspectable .blend for the owner. |
| Community MCP for Blender | Not installed/connected here | Useful later for interactive manipulation of an open Blender session; not needed to execute the asset pipeline now. |
| Mouse/keyboard Blender UI only | Not used | Useful for reviewing final .blend; less repeatable for precise multi-clip rig/export work. |

The community project previously named `ahujasid/blender-mcp` now redirects to [ahujasid/mcp-for-blender](https://github.com/ahujasid/mcp-for-blender). Its package is now `mcp-for-blender`; older package invocation remains compatible. It requires a Blender addon plus Python MCP process, starts a local socket and executes Python in Blender. The maintainer recommends one active connection. If installed later, keep it localhost and check its safe mode; this audit made no such changes. The project is third-party, not an official Blender integration.

## Recommended Window Watcher asset pipeline

1. **Meshy source → immutable source copy.** Prefer GLB for original material/rig interchange when available, plus original texture images. Inspect whether Meshy supplied a usable armature and skinning before selecting the rigging strategy.
2. **Blender project.** Import through the verified glTF operator, inspect silhouettes/front/back, object scales, normals, topology, bone hierarchy and material connections. Establish the intended Roblox size and orientation once; do not repeatedly rescale animated bones. Save a separate working .blend.
3. **Custom NPC skeleton and weights.** This creature can be a custom skinned NPC; forcing a15-part player-avatar conversion is unnecessary unless the design needs avatar compatibility. Preserve stable unique bone names/rest hierarchy between model and clips. A non-deforming root plus weighted pelvis/spine/limbs is a suitable starting structure. Meshy automatic weights need pose inspection around long fingers, shoulders, elbows, neck and any touching surfaces; repair local weighting rather than accepting automatic results blindly. Roblox represents the imported rig as Bone instances; their deformation does not change collision shape. [Roblox rigging/skinning](https://create.roblox.com/docs/art/modeling/rigging)
4. **Weight/model validation.** Enforce no more than4 influences per vertex, normalized nonzero weights, no weights on the root, root at origin and clean transforms. Check no exposed holes/backfaces or zero-thickness surfaces. Individual generic meshes may not exceed20,000 triangles; use a lower task budget if the silhouette permits. Validate the posed mesh rather than only the neutral pose. Roblox accepts a single animation track per export, so keep one clip per file. [General specifications](https://create.roblox.com/docs/art/modeling/specifications)
5. **Author and bake poses/clips.** Work on the actual final armature. Use30fps for this pipeline, with explicit frame ranges and a separate action for every agreed pose/animation. Bake constraint/IK-driven movement onto the export skeleton; control rigs themselves are not the Roblox playback mechanism. Keep stationary loops in place and inspect foot/hand contacts and loop boundaries. Render representative first/middle/last/extreme frames and a contact sheet/video for visual review. Roblox's custom-creature workflow recommends at least30fps and separate animation FBX files made with the same character. [Custom characters](https://create.roblox.com/docs/resources/beyond-the-dark/custom-characters)
6. **Export model and one FBX per clip.** Model export: selected mesh+armature, `add_leaf_bones=False`, animation disabled. Clip export: correct action selected, `bake_anim=True`, `bake_anim_use_all_actions=False`, `bake_anim_use_nla_strips=False`, sample every frame, simplify0 for initial fidelity. Disable extras/control bones while retaining required root/deforming ancestors. Blender5.2's bundled FBX source confirms **All Actions and NLA Strips default true**, so defaults would accidentally create multiple animation stacks. Roblox documents FBX Unit Scale and disabling leaf bones; bake animation only when exporting keyframes. [Export settings](https://create.roblox.com/docs/art/modeling/export-requirements)
7. **Scale/orientation and Studio QA.** Use a documented calibration size and verify actual imported bounds; avoid an improvised0.01 multiplier on both model and clips. Roblox's current Blender guide specifies FBX Unit Scale, Z Forward/Y Up, with corresponding import orientation and Stud scale, and notes glTF avoids the extra FBX scaling configuration. [Blender-to-Studio guide](https://create.roblox.com/docs/art/blender)
8. **Roundtrip before calling it Roblox-ready.** Reimport each export in a clean background Blender process to check mesh/bones/weights/action duration; then parent imports the model and clips into Studio, verifies correct bones/skin/materials/size, plays the animations on the actual NPC and checks asset ownership/permissions for the game's group. Keep model and animation asset IDs plus .blend, FBX/GLB, textures, scripts, manifests and previews.

## Official Blender reference and retrieval limitation

The current official manual endpoints were attempted but returned402 via web and403 via direct read-only HTTP in this environment. Flag/parameter claims above were therefore additionally checked against the installed official5.2 binary's `--help` and bundled addon source/RNA, rather than inferred from inaccessible pages.

- [Command-line arguments](https://docs.blender.org/manual/en/latest/advanced/command_line/arguments.html): local `--help` confirmed background, Python scripts/expressions, factory startup, disable-autoexec and nonzero Python-error exit codes.
- [glTF import/export](https://docs.blender.org/manual/en/latest/addons/import_export/scene_gltf2.html): local bundled source/RNA confirmed import operator and exporter options including4 influences by default, explicit sampling and action modes.
- [FBX import/export](https://docs.blender.org/manual/en/latest/addons/import_export/scene_fbx.html): local bundled source/RNA confirmed leaf-bone, deform-only, animation-stack, baking and simplification options.

## Workspace constraints

Local project AGENTS says `sources/` is read-only. Repository AGENTS keeps Studio authoritative and requires fresh instance/source checks before scoped Studio edits, preserving concurrent developer work and distinguishing Git push from publication. No Blender-specific local AGENTS or addon workflow was found. Current work is an asset preparation/connection task; no game-state changes were made by this audit.
