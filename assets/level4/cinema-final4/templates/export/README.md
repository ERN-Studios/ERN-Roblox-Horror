# Level 4 templates — standalone native chunk export

Upload the 32 chunks with the existing `tools/level4_blender/studio_upload.py` workflow when Studio work is authorized. IDs50000–50031 are intentionally separate from the cinema export IDs.

Upload the eight files in `textures/`; record IDs by filename in a JSON object, for example `{"L4T_Usher_base_color.png":"rbxassetid://<uploaded id>", ...}`. Do not use fabricated IDs.

Generate the scoped template builder:

```powershell
python G:/Roblox/_local/l4facelift/v5/assets/build_templates.py <results.jsonl> <texture_ids.json> <build_templates.luau>
```

The generator verifies uploaded-result content hashes against this exact export and requires all atlas maps. The generated Luau prepares all meshes before replacing only Usher, FilmReel, Fuse, BatteryPack and Note under ServerStorage."Level 4 Templates". It preserves unrelated children. No upload or Studio invocation is performed by this generator.

Run offline checks:

```powershell
python G:/Roblox/_local/l4facelift/v5/assets/build_templates.py --selftest
```

Visual proof and native Blender copy: `../templates/`. Rig/schema details and measured source retiming: `../templates/PROGRESS.md` and `audit.json`.
