The material candidate is local and uninstalled. Studio remains authoritative. Fresh Edit RuntimeBake Source/editor agree at SHA256 `1f564fdde835ad89b529d9069ddf87b0ed4991636f363eacbd098cc0b342ff28`; the raw R4 manifest reads back and independently hashes to `17b68efc473a0f100cf6ce6b9389332a5f2a87d82faf7694a0536a82483bc995`. All 71 local raw mesh hashes match the freshly captured live payload attributes. The current checkout and remote were inspected read-only; no Git operation, Studio edit, Play change, camera operation, or publication was performed by the material agent.

Install `tools/lobby_reimagined/polish_20261002/materials/MaterialPolish.ModuleScript.luau` as the new owned `ServerScriptService.LobbyReimaginedPreview.MaterialPolish` ModuleScript. The compiled candidate is 22848 bytes with SHA256 `6b4ef80ea746c39c900c59f6311ad1f7ea862cb20b24aa1aaab85816ec71c54e`. Preserve RuntimeBake, the raw manifest, original static PBR templates, and shared runtime atlas. Use the root agent's fresh scoped CAS for the Builder hook.

Required native child hierarchy:

```text
ServerScriptService.LobbyReimaginedPreview.MaterialPolish [ModuleScript]
  LobbyReimaginedOwned = true
  StaticPBRMaterials [Folder]
    LobbyReimaginedOwned = true
    Ready = true
    tunnel_concrete [SurfaceAppearance]
    asphalt_road [SurfaceAppearance]
    sidewalk_concrete [SurfaceAppearance]
  SidewalkAtlas [StringValue]
    LobbyReimaginedOwned = true
    Value = <published sidewalk_joint_atlas image asset ID, digits only>
    PNG_SHA256 = <candidate sidewalk atlas PNG SHA256>
```

Each SurfaceAppearance has `LobbyReimaginedOwned=true`, `AlphaMode=Overlay`, `Color=(1,1,1)`, empty MetalnessMap and published ColorMap/NormalMap/RoughnessMap IDs. Its `colorPNG_SHA256`, `normalPNG_SHA256`, and `roughnessPNG_SHA256` attributes must exactly match `candidate-manifest.json.assetSpec`. The published IDs are recorded and pinned by the root's upload/installation receipt. The helper itself reads URI-backed Content fields; it never allocates runtime PBR EditableImages or writes protected map properties. `Module.AssetSpec()` returns the exact map hashes and original baseline URIs required by the root installer.

Call `require(script.Parent.MaterialPolish).Apply(model)` once after EndBlockades has populated BlenderVisuals, before model Ready and parenting. No other source file needs modification. Material Apply snapshots and validates all its parts before replacement. It replaces only cloned owned SurfaceAppearances on the runtime R4 model. Exactly 14 SidewalkSection_atlas meshes must be present. Selected Embedded06/07/08 upper end furniture receives deterministic neutral tints between .94 and 1; the source furniture palettes, overlay placement and crown CRTs are preserved.

The assets are recalculated from the exact CC0 Poly Haven source scans using the existing native `r4_materials.py` pipeline. Asphalt median rises to approximately [92,93,89] from [62,64,63]. Wall contrast increases .72→1.24, wall normal strength .70→1.25, dry roughness becomes .77–.98. The sidewalk-only atlas maps the shared joint/drain-body dark-steel swatch from [43,48,49] to [108,104,96]; other parts retain the original atlas. Scan normal convention remains OpenGL, all maps stay aligned at 1024², all sampled normals are unit length within .012 and have positive Z. Review the swatches in `candidate-maps.jpg`; the live dark route and normal eye-height images are still required to assess final response.

Optional optimization is disabled by default. `Apply(model,{OptimizeBackfaces=true})` sets DoubleSided=false only for 46 unique raw mesh hashes that passed closed manifold, winding, nondegeneracy and geometric/shading normal alignment proof; they represent 49 of 71 chunk records / 23916 of 66872 unique triangles. Open hologram bands and inconsistent furniture remain double-sided. `AutomaticFidelity=true` additionally affects only five proven closed chunk hashes in ArchRib, CableTray, R4MonitorArm, R4BalloonBouquet and SidewalkSection, preserving shell curvature and other interactive silhouettes. Compile and topology evidence are not performance or gameplay checks. Keep both flags disabled until actual profile and all relevant sight lines support their use.

Required Play checks: static texture permission/loading and appearance replacement counts; normal eye-height road and avatar readability under the current night settings; shop-wall grain close view; sidewalk joint/drain legibility; upper cabinet tint and silhouettes; no material change to ServerLobby or global Lighting; frame time/CPU/memory measurements and all occupied-queue view silhouettes before accepting optional optimization. No check is marked passed here from source inspection alone.
