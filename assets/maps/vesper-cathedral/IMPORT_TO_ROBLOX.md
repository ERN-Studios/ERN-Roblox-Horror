# Import Vesper Cathedral into Roblox Studio

The cathedral is authored in Blender at **1 Blender unit = 1 Roblox stud**. Its full site measures **108 × 82.56 × 168 studs** (Roblox X width × Y height × Z depth). It is a static, modular map with a shared image atlas. Use **`VesperCathedral.glb`** as the primary import; **`VesperCathedral.fbx`** is the fallback. Keep the editable `VesperCathedral.blend` and supplied `textures` folder as your source assets. Preview renders use Blender lighting; they are not Studio screenshots.

The export converts Blender coordinates `(x, y, z)` into Roblox `(x, z, -y)`. In the authored frame the full visual bounds are X `[-54, 54]`, Y `[-3.06, 79.50]`, Z `[-81, 87]`, with center `(0, 38.22, 3)`. The interior floor top is Y `1.62`; the entrance is toward positive Z and the altar toward negative Z. The optional setup retains your chosen whole-model placement and orientation.

## Import

1. Open a separate test place in Studio. Choose **File → Import**, then select `VesperCathedral.glb`. If your file picker requires the extension filter, choose its glTF option or All Files. Use `VesperCathedral.fbx` if GLB is unavailable.
2. In the preview, set **Import Only As Model = on**, **Anchored = on**, **Scale Unit = Studs**, **Merge Meshes = off**, **Set Pivot to Scene Origin = on**, and **Insert Using Scene Position = on**. Keep the default **World Forward = Front** and **World Up = Top**. Retain all mesh objects. Do not merge the cathedral into one mesh.
3. For an iteration, **Upload to Roblox** can be off. For a reusable uploaded asset, select the intended owner under **Creator**; use the group that owns the destination game when appropriate. Imported private assets must have permission to be used by the destination experience.
4. Inspect the object hierarchy, materials, and any warnings before importing. The image atlas should be connected to each mesh's base color. Import errors or missing-texture warnings must be resolved before proceeding. Preserve the supplied texture paths/files alongside the FBX fallback when it uses external images.
5. Import the model. Keep its full hierarchy intact. You may move or rotate the whole Model normally. Do not independently change its pivot orientation, distort its proportions, remove pieces, or add extra geometry before applying the optional setup below.

The importer supports hierarchy, texture data, and vertex colors in FBX/glTF. Roblox limits each individual mesh to 20,000 triangles and one material; the package uses separate pieces for predictable importing. [Importer reference](https://create.roblox.com/docs/studio/importer), [mesh specifications](https://create.roblox.com/docs/art/modeling/specifications), [texture specifications](https://create.roblox.com/docs/art/modeling/texture-specifications).

## Apply collision and local lights

Use **`SetupCathedral.luau`** from this package. It already contains the collider and light metadata. The development template `tools/cathedral_setup_template.luau` contains an unfilled metadata placeholder and is not the file to run.

In Studio **Edit mode**, select exactly the imported cathedral **Model**, open the **Command Bar**, and run the generated setup script. It:

- Checks the selection, supplied mesh names, and proportions before editing.
- Normalizes its width to the recorded authored dimensions, including imports that arrived too small, while preserving the Model's pivot position and orientation.
- Anchors visual MeshParts, turns their collision and touch events off, and installs simple invisible collision parts in `_VesperSetup`.
- Adds the supplied local point lights. Set `ENABLE_LOCAL_LIGHTS = false` at the top before running if you want to light it yourself.
- Creates a Studio Undo step. Repeating the script replaces only its own tagged setup folder. It refuses an unknown folder with the same name or unrecognized objects placed inside its owned folder.

The script edits only the selected Model. It does not change global Lighting, create gameplay scripts, upload assets, save, or publish. Moving, rotating, or uniformly scaling the whole model **after** setup keeps the colliders together; rerunning setup returns it to the authored scale. Keep your own additions outside `_VesperSetup`.

Simple parts provide predictable collision for the floor, stairs, walls, and pillars. A single Box/Hull collision mesh around the entire cathedral would block its interior. Precise mesh collision also remains approximate and costs more. [Roblox collision guidance](https://create.roblox.com/docs/workspace/collisions), [performance recommendations](https://create.roblox.com/docs/performance-optimization/improve).

## Check before game integration

- Confirm upright orientation, the manifest's dimensions, complete modular hierarchy, and the stone, roof, wood, gold, and glass atlas colors. Check the nave from inside and the building from outside for reversed faces, missing surfaces, or texture problems.
- After setup, enable Studio's **Collision fidelity** visualization and inspect floors, entrances, stairs, columns, and open aisles. Test a normal player character walking from the entrance to the altar and along both side aisles. Check for snagging, invisible obstructions, floor gaps, and unexpected climbing.
- Inspect local lights under the intended game's existing lighting settings. Blender rendering, shadow softness, and stained-glass appearance will differ from Roblox. Adjust lighting in the test place as needed; the setup script does not modify global lighting.
- Check Play-mode errors and frame time on the intended device class before using this as a production map. Geometry validation and Blender roundtrip checks do not establish multiplayer, collision, Studio material appearance, or mobile performance.

This is an import package. Consult its verification manifest for the checks actually completed. It is not a claim of an uploaded asset, a Studio-tested playable map, or a published game change. Integrate into the authoritative live Studio place only as a separate, scoped task.

`collision-design-check.json` records an offline check of the supplied collider boxes along the central and side aisles with a 2.2 × 5.5 × 2.2 stud player box. It checks these straight paths before the altar steps; it does not run Studio physics, test character stepping, or establish that every route is traversable.

For Blender re-export, use selected meshes in the active cathedral scene only, applied transforms, and the shared atlas connected to Principled BSDF. This package's FBX fallback uses **Apply Scalings = FBX Unit Scale**, export scale `1`, **-Z Forward**, and **Y Up**, matching its GLB coordinate mapping. Preserve this package's export settings rather than changing axis conventions on only one format. Studio's glTF workflow avoids the additional FBX scale configuration. [Official Blender workflow](https://create.roblox.com/docs/art/blender), [texture assignment](https://create.roblox.com/docs/art/modeling/assign-textures).
