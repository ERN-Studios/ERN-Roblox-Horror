# Cinema final4 source delivery

This bundle copies the verified final4 assets without changing the external
originals, the open Blender session or Roblox Studio. `delivery-inventory.json`
lists every selected source path, byte size and SHA256. `.gitattributes` keeps
the frozen export and receipt bytes exact across checkouts.

`world/Cinema_Final4.blend` is the final culled authorable cinema. The filtered
`world/export` contains 570 mesh chunks and the placement packet used for Studio;
`authoring-manifest.json` and its packet retain the original native marker set.
The Studio import removes the 5607 physical navigation marker copies because
`nav/graph.json` and the runtime Usher Nav module carry the graph. The delivery
contains 38 light zones, 14 interactive models and the existing round anchors.

`templates/Cinema_Templates.blend` holds the Usher and FilmReel/Fuse/BatteryPack/
Note assets. Its export has 32 chunks, eight PBR atlases, the original rig and
30fps walk/run data. The scoped template builder consumes the hash-qualified
mesh receipts and the named texture ID receipts.

Generate a new template packet explicitly with the bundled export path:

```powershell
python assets/level4/cinema-final4/templates/build_templates.py assets/level4/cinema-final4/receipts/mesh-assets.jsonl assets/level4/cinema-final4/receipts/template-texture-assets.json new-build-templates.luau --export assets/level4/cinema-final4/templates/export
```

Both native files preserve their frozen original bytes. To author them on a
different machine, open the chosen native file and run `relink_textures.py` in
Blender. It maps external image paths to bundled files by their exact SHA256;
packed images stay embedded. It does not save the scene. `native-audit.json`
records the read-only inspection and all texture bindings.

The full bundle is about 369MB; every individual file is below 100MB (largest
47.84MB). All 602 mesh content hashes match the upload receipts. Texture receipts
provide filenames and asset IDs; they do not report uploaded pixel hashes. PNG
source hashes are recorded independently in the delivery inventory.

`qa/native` contains selected final Blender review frames. `qa/previous-session`
contains the handback session's real-anchor round, preview, Usher and clear
captures. These are provenance, not a certification of the final joint release.
The recorded offline contract/coverage checks passed; current Studio parity,
joint gameplay, cleanup and publication require separate live release evidence.

The collecting/audit tools perform no Studio writes, upload, Play, staging,
commit or native-place backup. Existing scripts and instances in Studio remain
authoritative; this bundle must never be bulk-imported over a concurrent game.
